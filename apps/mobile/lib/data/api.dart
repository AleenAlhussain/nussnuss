import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/extras.dart';
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
  const ApiException(this.status, this.message, {this.plus = false});

  /// 0 means the request never reached the server.
  final int status;
  final String message;

  /// The server said this needs Plus (403 with `plus: true`): show the paywall.
  final bool plus;

  bool get offline => status == 0;

  /// The request reached the server and was refused, so retrying the same thing will not help.
  bool get rejected => status >= 400 && status < 500 && status != 408;

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
      throw ApiException(
        res.status,
        msg,
        plus: data is Map<String, dynamic> && data['plus'] == true,
      );
    }
    return data;
  }

  /// For non-JSON answers (the CSV export).
  Future<String> _text(String path) async {
    final headers = <String, String>{'Accept': 'text/csv'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final res = await _send('GET', Uri.parse('$baseUrl$path'), headers, null);
    if (res.status >= 400) {
      Object? data;
      try {
        data = jsonDecode(res.body);
      } on FormatException {
        data = null;
      }
      final map = data is Map<String, dynamic> ? data : const {};
      throw ApiException(
        res.status,
        map['message'] as String? ?? 'Something went wrong.',
        plus: map['plus'] == true,
      );
    }
    return res.body;
  }

  Uri url(String path) => Uri.parse('$baseUrl$path');

  Map<String, dynamic> _map(Object? v) => v as Map<String, dynamic>;
  GroupDetail _detail(Object? v) => GroupDetail.fromJson(_map(v));
  List<Map<String, dynamic>> _list(Object? v) =>
      (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  ({String token, Me me}) _session(Object? v) {
    final d = _map(v);
    return (token: d['token'] as String, me: Me.fromJson(_map(d['user'])));
  }

  Future<({String token, Me me})> anonymous(String name, String locale) async {
    return _session(
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
  }

  Future<Me> me() async => Me.fromJson(_map(await _call('GET', '/me')));
  Future<Me> patchMe({
    String? name,
    String? locale,
    List<PayTo>? payTo,
    AvatarLook? avatar,
  }) async => Me.fromJson(
    _map(
      await _call(
        'PATCH',
        '/me',
        body: {
          'name': ?name,
          'locale': ?locale,
          if (payTo != null) 'payTo': [for (final p in payTo) p.toJson()],
          // Only an initial or an emoji; photos go up through [setPhoto].
          if (avatar != null)
            'avatar': {
              'kind': avatar.kind,
              'tone': avatar.tone,
              'value': ?avatar.value,
            },
        },
      ),
    ),
  );

  /// A profile photo: a small JPEG, PNG or WebP (at most 70 KB), as base64.
  Future<Me> setPhoto(String base64) async => Me.fromJson(
    _map(await _call('POST', '/me/photo', body: {'data': base64})),
  );
  Future<Me> removePhoto() async =>
      Me.fromJson(_map(await _call('DELETE', '/me/photo')));

  /// Where a photo avatar's relative url is served.
  String photoUrl(String url) => url.startsWith('http') ? url : '$baseUrl$url';
  Future<void> deleteMe() => _call('DELETE', '/me');

  // Keeping an account: recovery codes, codes for another device, signed-in devices.
  Future<Security> security() async =>
      Security.fromJson(_map(await _call('GET', '/me/security')));
  Future<String> makeRecoveryCode() async =>
      _map(await _call('POST', '/me/recovery'))['code'] as String;
  Future<({String code, DateTime expiresAt})> makeLinkCode() async {
    final d = _map(await _call('POST', '/me/link'));
    return (
      code: d['code'] as String,
      expiresAt:
          DateTime.tryParse(d['expiresAt'] as String? ?? '')?.toLocal() ??
          DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  /// Signs in with a code: 8 characters is a code from another device, longer is a recovery code.
  Future<({String token, Me me})> signInWithCode(String code) async {
    final clean = code.replaceAll(RegExp(r'[\s-]'), '');
    return _session(
      await _call(
        'POST',
        clean.length <= 8 ? '/auth/link' : '/auth/recover',
        body: {'code': code.trim(), 'device': Platform.operatingSystem},
        auth: false,
      ),
    );
  }

  Future<void> endSession(String id) => _call('DELETE', '/me/sessions/$id');
  Future<String> exportMine() async =>
      jsonEncode(await _call('GET', '/me/export'));

  // Plus.
  Future<Plan> plan() async =>
      Plan.fromJson(_map(await _call('GET', '/me/plan')));
  Future<Plan> verifyApple(String signedTransaction, {String? groupId}) async =>
      Plan.fromJson(
        _map(
          await _call(
            'POST',
            '/purchases/apple',
            body: {'signedTransaction': signedTransaction, 'groupId': ?groupId},
          ),
        ),
      );
  Future<Plan> verifyGoogle(
    String productId,
    String purchaseToken, {
    String? groupId,
  }) async => Plan.fromJson(
    _map(
      await _call(
        'POST',
        '/purchases/google',
        body: {
          'productId': productId,
          'purchaseToken': purchaseToken,
          'groupId': ?groupId,
        },
      ),
    ),
  );
  Future<Plan> devPurchase(String productId, {String? groupId}) async =>
      Plan.fromJson(
        _map(
          await _call(
            'POST',
            '/purchases/dev',
            body: {'productId': productId, 'groupId': ?groupId},
          ),
        ),
      );

  // Notifications inbox.
  Future<List<AppNotification>> notifications() async => [
    for (final n in (await _call('GET', '/me/notifications')) as List<dynamic>)
      AppNotification.fromJson(_map(n)),
  ];
  Future<void> markNotificationsRead() =>
      _call('POST', '/me/notifications/read', body: const <String, Object>{});

  /// Crash reports carry no personal data: the message, the stack, the app version.
  Future<void> reportCrash({
    required String app,
    required String version,
    required String message,
    String? stack,
  }) => _call(
    'POST',
    '/telemetry/crash',
    body: {
      'app': app,
      'version': version,
      'message': message.length > 500 ? message.substring(0, 500) : message,
      if (stack != null)
        'stack': stack.length > 8000 ? stack.substring(0, 8000) : stack,
    },
    auth: false,
  );

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

  Future<GroupDetail> patchGroup(
    String id, {
    String? name,
    String? cover,
    String? currency,
  }) async => _detail(
    await _call(
      'PATCH',
      '/groups/$id',
      body: {'name': ?name, 'cover': ?cover, 'currency': ?currency},
    ),
  );

  // Home, people and activity across every group.
  Future<Overview> overview() async =>
      Overview.fromJson(_map(await _call('GET', '/overview')));

  Future<PersonDetail> person(String key) async =>
      PersonDetail.fromJson(_map(await _call('GET', '/people/$key')));

  /// Records a payment in every shared group that isn't even. Returns the payments, for Undo.
  Future<({List<String> payments, PersonDetail person})> settleAll(
    String key, {
    List<String>? groups,
  }) async {
    final d = _map(
      await _call('POST', '/people/$key/settle', body: {'groups': ?groups}),
    );
    return (
      payments: [for (final p in _list(d['payments'])) p['id'] as String],
      person: PersonDetail.fromJson(_map(d['person'])),
    );
  }

  Future<void> undoPayments(List<String> ids) =>
      _call('POST', '/payments/undo', body: {'ids': ids});

  Future<ActivityPage> activity({String? before, String? group}) async {
    final q = {'before': ?before, 'group': ?group};
    final path = q.isEmpty
        ? '/activity'
        : '/activity?${Uri(queryParameters: q).query}';
    return ActivityPage.fromJson(_map(await _call('GET', path)));
  }

  Future<void> activitySeen() => _call('POST', '/activity/seen');

  /// Anonymous task timings (phase 0 of the design plan): no token, never awaited by the interface.
  Future<void> timing({
    required String app,
    required String version,
    required String job,
    required int ms,
    required bool ok,
  }) => _call(
    'POST',
    '/telemetry/timing',
    body: {
      'app': app,
      'version': version,
      'job': job,
      'ms': ms.clamp(0, 600000),
      'ok': ok,
    },
    auth: false,
  );

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

  /// [id] is made on the device, so "mark as paid" is safe to send again after a dropped connection.
  Future<({String id, GroupDetail detail})> pay(
    String groupId,
    Transfer t, {
    String? id,
  }) async {
    final d = _map(
      await _call(
        'POST',
        '/groups/$groupId/payments',
        body: {...t.toJson(), 'id': ?id},
      ),
    );
    return (id: d['id'] as String, detail: _detail(d['detail']));
  }

  Future<GroupDetail> unpay(String paymentId) async =>
      _detail(await _call('DELETE', '/payments/$paymentId'));

  Future<String> invite(String groupId) async =>
      (await inviteLink(groupId)).token;

  /// A new invite: the short code and the path the web serves it at (/j/<code>).
  Future<({String token, String path})> inviteLink(String groupId) async {
    final d = _map(await _call('POST', '/groups/$groupId/invites'));
    final token = d['token'] as String;
    return (token: token, path: d['path'] as String? ?? '/j/$token');
  }

  Future<({Map<String, dynamic> group, List<Member> members})> preview(
    String token,
  ) async {
    final d = _map(await _call('GET', '/invites/$token', auth: false));
    return (
      group: _map(d['group']),
      members: [for (final m in _list(d['members'])) Member.fromJson(m)],
    );
  }

  Future<GroupDetail> join(
    String token, {
    String? memberId,
    String? name,
  }) async => _detail(
    await _call(
      'POST',
      '/invites/$token/join',
      body: {'memberId': ?memberId, 'name': ?name},
    ),
  );

  // Plus features of a group.
  Future<GroupDetail> addRecurring(
    String groupId,
    ExpenseInput e, {
    required String every,
    DateTime? startAt,
  }) async => _detail(
    await _call(
      'POST',
      '/groups/$groupId/recurring',
      body: {
        ...e.toJson()
          ..remove('id')
          ..remove('currency')
          ..remove('rate'),
        'every': every,
        if (startAt != null) 'startAt': startAt.toUtc().toIso8601String(),
      },
    ),
  );
  Future<GroupDetail> stopRecurring(String id) async =>
      _detail(await _call('DELETE', '/recurring/$id'));
  Future<double> rate(String from, String to, {String? groupId}) async =>
      ((_map(
                await _call(
                  'GET',
                  '/rates?from=$from&to=$to${groupId == null ? '' : '&groupId=$groupId'}',
                ),
              ))['rate']
              as num)
          .toDouble();
  Future<String> exportCsv(String groupId) =>
      _text('/groups/$groupId/export.csv');
  Future<GroupDetail> setReminders(
    String groupId, {
    required bool weekly,
  }) async => _detail(
    await _call(
      'PATCH',
      '/groups/$groupId/reminders',
      body: {'every': weekly ? 'week' : 'off'},
    ),
  );

  // Money circles.
  Future<GroupDetail> createCircle(
    String groupId, {
    required String name,
    required int amount,
    required String every,
    required String startOn,
    required List<String> turns,
  }) async => _detail(
    await _call(
      'POST',
      '/groups/$groupId/circles',
      body: {
        'name': name,
        'amount': amount,
        'every': every,
        'startOn': startOn,
        'turns': turns,
      },
    ),
  );
  Future<GroupDetail> circlePaid(
    String circleId, {
    required int round,
    required String memberId,
    required bool paid,
  }) async => _detail(
    await _call(
      'POST',
      '/circles/$circleId/${paid ? 'paid' : 'unpaid'}',
      body: {'round': round, 'memberId': memberId},
    ),
  );
  Future<GroupDetail> deleteCircle(String id) async =>
      _detail(await _call('DELETE', '/circles/$id'));
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
