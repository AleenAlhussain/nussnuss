import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/types.dart';
import 'models.dart';

/// Where the API lives. Set at build time:
///   flutter run --dart-define=API_URL=https://api.example.com
/// Without it, debug builds talk to a NestJS API on this machine (10.0.2.2 is the host from the Android emulator).
String defaultApiUrl() {
  const fromBuild = String.fromEnvironment('API_URL');
  if (fromBuild.isNotEmpty) return fromBuild.replaceAll(RegExp(r'/$'), '');
  return Platform.isAndroid ? 'http://10.0.2.2:4000' : 'http://127.0.0.1:4000';
}

class ApiResponse {
  const ApiResponse(this.status, this.body);
  final int status;
  final String body;
}

/// One HTTP call. Swapped for a fake in tests.
typedef Transport =
    Future<ApiResponse> Function(
      String method,
      Uri url,
      Map<String, String> headers,
      String? body,
    );

class ApiException implements Exception {
  const ApiException(this.status, this.message);

  /// 0 means the request never reached the server.
  final int status;
  final String message;

  bool get offline => status == 0;

  @override
  String toString() => 'ApiException($status, $message)';
}

/// HTTP over dart:io with one shared client, so connections are reused.
class IoTransport {
  IoTransport()
    : _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final HttpClient _client;

  Future<ApiResponse> call(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    try {
      final req = await _client.openUrl(method, url);
      headers.forEach((k, v) => req.headers.set(k, v));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      return ApiResponse(res.statusCode, text);
    } on SocketException {
      throw const ApiException(0, 'offline');
    } on TimeoutException {
      throw const ApiException(0, 'offline');
    } on HttpException {
      throw const ApiException(0, 'offline');
    } on HandshakeException {
      throw const ApiException(0, 'offline');
    }
  }
}

/// Typed client for the NussNuss API. Mirrors apps/web/lib/api.ts call for call.
class Api {
  Api({required this.baseUrl, required Transport transport, this.token})
    : _send = transport;

  final String baseUrl;
  final Transport _send;
  String? token;

  Future<Object?> _call(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (auth && token != null) headers['Authorization'] = 'Bearer $token';
    final res = await _send(
      method,
      Uri.parse('$baseUrl$path'),
      headers,
      body == null ? null : jsonEncode(body),
    );
    if (res.status == 204 || res.body.isEmpty) {
      if (res.status >= 400) {
        throw ApiException(res.status, 'Something went wrong.');
      }
      return null;
    }
    Object? data;
    try {
      data = jsonDecode(res.body);
    } on FormatException {
      data = null;
    }
    if (res.status >= 400) {
      final msg = data is Map<String, dynamic> && data['message'] is String
          ? data['message'] as String
          : 'Something went wrong.';
      throw ApiException(res.status, msg);
    }
    return data;
  }

  Map<String, dynamic> _map(Object? v) => v as Map<String, dynamic>;
  GroupDetail _detail(Object? v) => GroupDetail.fromJson(_map(v));

  Future<({String token, Me me})> anonymous(String name, String locale) async {
    final d = _map(
      await _call(
        'POST',
        '/auth/anonymous',
        body: {
          'name': name,
          'locale': locale,
          'device': Platform.operatingSystem,
        },
        auth: false,
      ),
    );
    return (token: d['token'] as String, me: Me.fromJson(_map(d['user'])));
  }

  Future<Me> me() async => Me.fromJson(_map(await _call('GET', '/me')));
  Future<Me> patchMe({String? name, String? locale}) async => Me.fromJson(
    _map(await _call('PATCH', '/me', body: {'name': ?name, 'locale': ?locale})),
  );
  Future<void> deleteMe() => _call('DELETE', '/me');

  Future<List<GroupSummary>> groups() async => [
    for (final g in (await _call('GET', '/groups')) as List<dynamic>)
      GroupSummary.fromJson(_map(g)),
  ];

  Future<GroupDetail> createGroup({
    required String name,
    required String emoji,
    required String currency,
    required List<String> members,
  }) async => _detail(
    await _call(
      'POST',
      '/groups',
      body: {
        'name': name,
        'emoji': emoji,
        'currency': currency,
        'members': members,
      },
    ),
  );

  Future<GroupDetail> group(String id) async =>
      _detail(await _call('GET', '/groups/$id'));

  Future<int> version(String id, int since) async =>
      ((_map(await _call('GET', '/groups/$id/changes?since=$since')))['version']
              as num)
          .toInt();

  Future<GroupDetail> addMember(String groupId, String name) async => _detail(
    await _call('POST', '/groups/$groupId/members', body: {'name': name}),
  );

  Future<GroupDetail> addExpense(String groupId, ExpenseInput e) async =>
      _detail(
        _map(
          await _call('POST', '/groups/$groupId/expenses', body: e.toJson()),
        )['detail'],
      );

  Future<GroupDetail> updateExpense(ExpenseInput e) async => _detail(
    await _call('PATCH', '/expenses/${e.id}', body: e.toJson()..remove('id')),
  );

  Future<GroupDetail> deleteExpense(String id) async =>
      _detail(await _call('DELETE', '/expenses/$id'));

  Future<GroupDetail> restoreExpense(String id) async =>
      _detail(await _call('POST', '/expenses/$id/restore'));

  Future<({String id, GroupDetail detail})> pay(
    String groupId,
    Transfer t,
  ) async {
    final d = _map(
      await _call('POST', '/groups/$groupId/payments', body: t.toJson()),
    );
    return (id: d['id'] as String, detail: _detail(d['detail']));
  }

  Future<GroupDetail> unpay(String paymentId) async =>
      _detail(await _call('DELETE', '/payments/$paymentId'));

  Future<String> invite(String groupId) async =>
      _map(await _call('POST', '/groups/$groupId/invites'))['token'] as String;
}

final _rng = Random.secure();

/// RFC 4122 version 4 UUID from a secure random source.
String newId() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
