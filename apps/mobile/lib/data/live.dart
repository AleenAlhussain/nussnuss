import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Opens a live stream of a group's version. The app uses [sseVersions]; tests pass none and the
/// group screen falls back to a slow poll.
typedef LiveUpdates = Stream<int> Function(String groupId);

/// Server-sent events from GET /groups/:id/events over dart:io, with the token in the header.
/// Emits every version the server announces. Reconnects by itself with a growing pause (1 s, 2 s,
/// 4 s … 30 s); errors are passed on so the screen can poll meanwhile.
Stream<int> sseVersions({
  required String baseUrl,
  required String groupId,
  required String? Function() token,
}) {
  late final StreamController<int> out;
  HttpClient? client;
  Timer? retry;
  var closed = false;
  var attempt = 0;

  Future<void> connect() async {
    if (closed) return;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client!.getUrl(
        Uri.parse('$baseUrl/groups/$groupId/events'),
      );
      final t = token();
      if (t != null) req.headers.set('Authorization', 'Bearer $t');
      req.headers.set('Accept', 'text/event-stream');
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('events answered ${res.statusCode}');
      }
      attempt = 0;
      var event = 'message';
      await for (final line
          in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (closed) break;
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:') && event == 'version') {
          final data = jsonDecode(line.substring(5).trim());
          final v = data is Map<String, dynamic> ? data['version'] : null;
          if (v is num) out.add(v.toInt());
        } else if (line.isEmpty) {
          event = 'message';
        }
      }
    } on Object catch (e) {
      if (!closed) out.addError(e);
    } finally {
      client?.close(force: true);
      client = null;
    }
    if (closed) return;
    final wait = Duration(seconds: min(30, 1 << min(attempt, 5)));
    attempt++;
    retry = Timer(wait, connect);
  }

  out = StreamController<int>(
    onListen: connect,
    onCancel: () {
      closed = true;
      retry?.cancel();
      client?.close(force: true);
    },
  );
  return out.stream;
}
