// An in-memory stand-in for the NestJS API, just enough for widget tests.
// Balances come from the same Dart core the app uses, as the real server does with the TypeScript core.
import 'dart:convert';

import 'package:nussnuss/core/split.dart';
import 'package:nussnuss/core/types.dart';
import 'package:nussnuss/data/api.dart';

class FakeGroup {
  FakeGroup(this.id, this.name, this.emoji, this.currency);
  final String id;
  final String name;
  final String emoji;
  final String currency;
  int version = 1;
  String remindEvery = 'off';
  DateTime? tripPassUntil;
  final members = <Map<String, Object?>>[];
  final expenses = <Map<String, Object?>>[];
  final deleted = <Map<String, Object?>>[];
  final payments = <Map<String, Object?>>[];
  final circles = <Map<String, Object?>>[];
  final recurring = <Map<String, Object?>>[];
}

class FakeServer {
  final _users = <String, Map<String, Object?>>{};
  final _groups = <String, FakeGroup>{};
  final _invites = <String, String>{};
  final _codes = <String, String>{};
  int _n = 0;
  final calls = <String>[];

  /// While true every call fails as if there were no connection.
  bool offline = false;

  /// Plus for everyone (the server's view; the app learns it from /me/plan).
  bool plus = false;

  /// Reminder notifications to hand out, per user name.
  final notifications = <String, List<Map<String, Object?>>>{};

  String _id() =>
      '00000000-0000-4000-8000-${(++_n).toString().padLeft(12, '0')}';

  ApiResponse _ok(Object? o, [int status = 200]) =>
      ApiResponse(status, jsonEncode(o));
  ApiResponse _err(int status, String message, {bool plus = false}) =>
      ApiResponse(
        status,
        jsonEncode({'message': message, if (plus) 'plus': true}),
      );
  ApiResponse _needsPlus() => _err(403, 'This is part of Plus.', plus: true);

  FakeGroup groupNamed(String name) =>
      _groups.values.firstWhere((g) => g.name == name);

  /// Gives a member a way to get paid, as if they had joined and filled it in.
  void setPayTo(String group, String member, List<Map<String, Object>> payTo) {
    final g = groupNamed(group);
    final m = g.members.firstWhere((m) => m['name'] == member);
    m['payTo'] = payTo;
  }

  GroupLike _core(FakeGroup g) => GroupLike(
    currency: g.currency,
    memberIds: [for (final m in g.members) m['id']! as String],
    expenses: [
      for (final e in g.expenses)
        ExpenseLike(
          amount: e['amount']! as int,
          currency: e['currency'] as String? ?? g.currency,
          rate: (e['rate'] as num?)?.toDouble() ?? 1,
          paidBy: e['paidBy']! as String,
          mode: SplitMode.parse(e['mode']! as String),
          items: [
            for (final i
                in (e['items']! as List<dynamic>).cast<Map<String, dynamic>>())
              SplitItem(i['memberId'] as String, i['value'] as int),
          ],
        ),
    ],
    payments: [
      for (final p in g.payments)
        PaymentLike(
          from: p['from']! as String,
          to: p['to']! as String,
          amount: p['amount']! as int,
        ),
    ],
  );

  String _memberOf(FakeGroup g, String userId) =>
      g.members.firstWhere((m) => m['userId'] == userId)['id']! as String;

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, Object?> _circleView(Map<String, Object?> c) {
    final turns = (c['turns']! as List<dynamic>).cast<String>();
    final start = DateTime.parse(c['startOn']! as String);
    final paid = (c['paid']! as List<dynamic>).cast<String>();
    final today = _day(DateTime.now());
    final rounds = [
      for (var r = 0; r < turns.length; r++)
        () {
          final due = c['every'] == 'week'
              ? start.add(Duration(days: 7 * r))
              : DateTime(start.year, start.month + r, start.day);
          final inRound = [
            for (final m in turns)
              if (m != turns[r] && paid.contains('$r:$m')) m,
          ];
          return {
            'round': r,
            'receiver': turns[r],
            'dueOn': _day(due),
            'paid': inRound,
            'late': _day(due).compareTo(today) < 0
                ? [
                    for (final m in turns)
                      if (m != turns[r] && !inRound.contains(m)) m,
                  ]
                : <String>[],
          };
        }(),
    ];
    final open = rounds.indexWhere(
      (r) => (r['paid']! as List).length < turns.length - 1,
    );
    return {
      'id': c['id'],
      'name': c['name'],
      'amount': c['amount'],
      'every': c['every'],
      'startOn': c['startOn'],
      'turns': turns,
      'pot': (c['amount']! as int) * turns.length,
      'status': today.compareTo(c['startOn']! as String) < 0
          ? 'upcoming'
          : (open == -1 ? 'done' : 'running'),
      'current': open == -1 ? null : open,
      'rounds': rounds,
    };
  }

  Map<String, Object?> _detail(FakeGroup g, String userId) {
    final core = _core(g);
    final balances = computeBalances(core);
    final me = _memberOf(g, userId);
    return {
      'id': g.id,
      'name': g.name,
      'emoji': g.emoji,
      'currency': g.currency,
      'version': g.version,
      'createdBy': null,
      'updatedAt': DateTime.now().toIso8601String(),
      'remindEvery': g.remindEvery,
      'tripPassUntil': g.tripPassUntil?.toIso8601String(),
      'me': me,
      'members': [
        for (final m in g.members)
          {
            'id': m['id'],
            'name': m['name'],
            'claimed': m['userId'] != null,
            'isMe': m['id'] == me,
            'payTo':
                m['payTo'] ??
                (m['userId'] == null
                    ? const <Object>[]
                    : _users.values.firstWhere(
                        (u) => u['id'] == m['userId'],
                      )['payTo']),
          },
      ],
      'expenses': [
        for (final e in g.expenses.reversed)
          {
            ...e,
            'currency': e['currency'] ?? g.currency,
            'rate': e['rate'] ?? 1,
            'spentAt': DateTime.now().toIso8601String(),
          },
      ],
      'payments': [
        for (final p in g.payments)
          {...p, 'paidAt': DateTime.now().toIso8601String()},
      ],
      'total': groupTotal(core),
      'balances': balances,
      'transfers': [
        for (final t in simplifyDebts(balances, core.memberIds)) t.toJson(),
      ],
      'circles': [for (final c in g.circles) _circleView(c)],
      'recurring': g.recurring,
    };
  }

  Map<String, Object?> _plan(Map<String, Object?> user) => {
    'plus': plus || user['plus'] == true,
    'plusUntil': plus || user['plus'] == true
        ? DateTime.now().add(const Duration(days: 365)).toIso8601String()
        : null,
    'tripPasses': [
      for (final g in _groups.values)
        if (g.tripPassUntil != null)
          {'groupId': g.id, 'until': g.tripPassUntil!.toIso8601String()},
    ],
    'looks': user['looks'] ?? const <String>[],
  };

  bool _hasPlus(Map<String, Object?> user, FakeGroup? g) =>
      plus ||
      user['plus'] == true ||
      (g?.tripPassUntil?.isAfter(DateTime.now()) ?? false);

  Map<String, Object?> _session(Map<String, Object?> user) {
    final token = 'token-${_id()}';
    _users[token] = user;
    return {'token': token, 'user': _meView(user)};
  }

  Map<String, Object?> _meView(Map<String, Object?> u) => {
    'id': u['id'],
    'name': u['name'],
    'locale': u['locale'],
    'payTo': u['payTo'] ?? const <Object>[],
  };

  Future<ApiResponse> call(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    final path = url.path;
    calls.add('$method $path');
    if (offline) throw const ApiException(0, 'offline');
    final b = body == null
        ? const <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;

    if (method == 'POST' && path == '/auth/anonymous') {
      final user = <String, Object?>{
        'id': _id(),
        'name': b['name'] as String,
        'locale': b['locale'] as String? ?? 'en',
        'payTo': <Object>[],
      };
      return _ok(_session(user), 201);
    }
    if (method == 'POST' && (path == '/auth/link' || path == '/auth/recover')) {
      final code = (b['code'] as String).replaceAll(RegExp(r'[\s-]'), '');
      final userId = _codes.remove(code);
      if (userId == null) return _err(401, 'That code does not match.');
      final user = _users.values.firstWhere((u) => u['id'] == userId);
      return _ok(_session(user), 201);
    }
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    if (method == 'GET' && seg.length == 2 && seg[0] == 'invites') {
      final g = _groups[_invites[seg[1]]];
      if (g == null) return _err(404, 'This link does not work.');
      return _ok({
        'group': {
          'id': g.id,
          'name': g.name,
          'emoji': g.emoji,
          'currency': g.currency,
        },
        'members': [
          for (final m in g.members)
            {'id': m['id'], 'name': m['name'], 'claimed': m['userId'] != null},
        ],
      });
    }
    if (method == 'POST' && path == '/telemetry/crash') {
      return const ApiResponse(204, '');
    }

    final user = _users[headers['Authorization']?.replaceFirst('Bearer ', '')];
    if (user == null) return _err(401, 'Sign in again.');
    final uid = user['id']! as String;

    if (method == 'GET' && path == '/me') return _ok(_meView(user));
    if (method == 'PATCH' && path == '/me') {
      if (b['name'] != null) user['name'] = b['name'];
      if (b['locale'] != null) user['locale'] = b['locale'];
      if (b['payTo'] != null) {
        final list = (b['payTo'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (final p in list) {
          if (p['kind'] == 'iban' &&
              !RegExp(
                r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$',
              ).hasMatch((p['value'] as String).replaceAll(' ', ''))) {
            return _err(400, 'That IBAN does not look right.');
          }
        }
        user['payTo'] = list;
      }
      return _ok(_meView(user));
    }
    if (method == 'GET' && path == '/me/plan') return _ok(_plan(user));
    if (method == 'GET' && path == '/me/security') {
      return _ok({
        'recoveryCode': user['recovery'] != null,
        'recoveryCreatedAt': user['recovery'],
        'identities': <Object>[],
        'passkeys': <Object>[],
        'sessions': [
          {
            'id': 'this',
            'device': 'ios',
            'lastSeenAt': DateTime.now().toIso8601String(),
            'current': true,
          },
        ],
        'providers': {'apple': false, 'google': false, 'passkeys': true},
      });
    }
    if (method == 'POST' && path == '/me/recovery') {
      const code = 'ABCDE-FGHJK-MNPQR-STVWX';
      _codes[code.replaceAll('-', '')] = uid;
      user['recovery'] = DateTime.now().toIso8601String();
      return _ok({'code': code}, 201);
    }
    if (method == 'POST' && path == '/me/link') {
      const code = 'K7M2-Q9XD';
      _codes[code.replaceAll('-', '')] = uid;
      return _ok({
        'code': code,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
      }, 201);
    }
    if (method == 'GET' && path == '/me/notifications') {
      return _ok(notifications[user['name']] ?? const <Object>[]);
    }
    if (method == 'POST' && path == '/me/notifications/read') {
      for (final n
          in notifications[user['name']] ?? const <Map<String, Object?>>[]) {
        n['read'] = true;
      }
      return const ApiResponse(204, '');
    }
    if (method == 'GET' && path == '/me/export') {
      return _ok({'account': _meView(user), 'groups': <Object>[]});
    }
    if (method == 'POST' && path == '/purchases/dev') {
      final id = b['productId'] as String;
      if (id.startsWith('nussnuss.plus')) user['plus'] = true;
      if (id.startsWith('nussnuss.look')) {
        user['looks'] = [...?(user['looks'] as List?), id];
      }
      if (id == 'nussnuss.trip_pass') {
        _groups[b['groupId']]?.tripPassUntil = DateTime.now().add(
          const Duration(days: 30),
        );
      }
      return _ok(_plan(user), 201);
    }
    if (method == 'GET' && path == '/groups') {
      return _ok([
        for (final g in _groups.values.where(
          (g) => g.members.any((m) => m['userId'] == uid),
        ))
          {
            'id': g.id,
            'name': g.name,
            'emoji': g.emoji,
            'currency': g.currency,
            'version': g.version,
            'updatedAt': DateTime.now().toIso8601String(),
            'memberCount': g.members.length,
            'memberNames': [for (final m in g.members) m['name']],
            'total': groupTotal(_core(g)),
            'myBalance': computeBalances(_core(g))[_memberOf(g, uid)],
          },
      ]);
    }
    if (method == 'POST' && path == '/groups') {
      final g = FakeGroup(
        _id(),
        b['name'] as String,
        b['emoji'] as String,
        b['currency'] as String,
      );
      g.members.add({'id': _id(), 'name': user['name'], 'userId': uid});
      for (final n in (b['members'] as List<dynamic>).cast<String>()) {
        g.members.add({'id': _id(), 'name': n, 'userId': null});
      }
      _groups[g.id] = g;
      return _ok(_detail(g, uid), 201);
    }
    if (method == 'GET' && path == '/rates') {
      final g = _groups[url.queryParameters['groupId']];
      if (!_hasPlus(user, g)) return _needsPlus();
      return _ok({'rate': 3.6725});
    }
    if (method == 'POST' &&
        seg.length == 3 &&
        seg[0] == 'invites' &&
        seg[2] == 'join') {
      final g = _groups[_invites[seg[1]]];
      if (g == null) return _err(404, 'This link does not work.');
      if (b['memberId'] != null) {
        g.members.firstWhere((m) => m['id'] == b['memberId'])['userId'] = uid;
      } else {
        g.members.add({'id': _id(), 'name': b['name'], 'userId': uid});
      }
      g.version++;
      return _ok(_detail(g, uid), 201);
    }
    if (seg.length >= 2 && seg[0] == 'groups') {
      final g = _groups[seg[1]];
      if (g == null) return _err(404, 'Group not found.');
      if (method == 'GET' && seg.length == 2) return _ok(_detail(g, uid));
      if (method == 'GET' && seg.length == 3 && seg[2] == 'changes') {
        return _ok({'version': g.version, 'changes': <Object>[]});
      }
      if (method == 'POST' && seg.length == 3 && seg[2] == 'invites') {
        final token = 'invite${_id().substring(24)}';
        _invites[token] = g.id;
        return _ok({'token': token, 'expiresAt': ''}, 201);
      }
      if (method == 'POST' && seg.length == 3 && seg[2] == 'expenses') {
        final id = b['id'] as String? ?? _id();
        if (!g.expenses.any((e) => e['id'] == id)) {
          g.expenses.add({
            'id': id,
            'title': b['title'],
            'amount': b['amount'],
            'paidBy': b['paidBy'],
            'mode': b['mode'],
            'items': b['items'],
            'category': b['category'],
            'currency': b['currency'],
            'rate': b['rate'],
          });
          g.version++;
        }
        return _ok({'id': id, 'detail': _detail(g, uid)}, 201);
      }
      if (method == 'POST' && seg.length == 3 && seg[2] == 'payments') {
        final id = b['id'] as String? ?? _id();
        if (!g.payments.any((p) => p['id'] == id)) {
          g.payments.add({
            'id': id,
            'from': b['from'],
            'to': b['to'],
            'amount': b['amount'],
          });
          g.version++;
        }
        return _ok({'id': id, 'detail': _detail(g, uid)}, 201);
      }
      if (method == 'PATCH' && seg.length == 3 && seg[2] == 'reminders') {
        if (b['every'] == 'week' && !_hasPlus(user, g)) return _needsPlus();
        g.remindEvery = b['every'] as String;
        g.version++;
        return _ok(_detail(g, uid));
      }
      if (method == 'GET' && seg.length == 3 && seg[2] == 'export.csv') {
        if (!_hasPlus(user, g)) return _needsPlus();
        return const ApiResponse(200, 'Date,Title,Amount\n');
      }
      if (method == 'POST' && seg.length == 3 && seg[2] == 'recurring') {
        if (!_hasPlus(user, g)) return _needsPlus();
        g.recurring.add({
          'id': _id(),
          'title': b['title'],
          'amount': b['amount'],
          'paidBy': b['paidBy'],
          'mode': b['mode'],
          'items': b['items'],
          'category': b['category'],
          'every': b['every'],
          'nextAt': b['startAt'] ?? DateTime.now().toIso8601String(),
        });
        g.version++;
        return _ok(_detail(g, uid), 201);
      }
      if (method == 'POST' && seg.length == 3 && seg[2] == 'circles') {
        g.circles.add({
          'id': _id(),
          'name': b['name'],
          'amount': b['amount'],
          'every': b['every'],
          'startOn': b['startOn'],
          'turns': b['turns'],
          'paid': <String>[],
        });
        g.version++;
        return _ok(_detail(g, uid), 201);
      }
    }
    if (seg.length >= 2 && seg[0] == 'circles') {
      for (final g in _groups.values) {
        final c = g.circles.where((c) => c['id'] == seg[1]).firstOrNull;
        if (c == null) continue;
        final paid = c['paid']! as List<String>;
        final key = '${b['round']}:${b['memberId']}';
        if (method == 'POST' && seg.length == 3 && seg[2] == 'paid') {
          if (!paid.contains(key)) paid.add(key);
        } else if (method == 'POST' && seg.length == 3 && seg[2] == 'unpaid') {
          paid.remove(key);
        } else if (method == 'DELETE' && seg.length == 2) {
          g.circles.remove(c);
        }
        g.version++;
        return _ok(_detail(g, uid));
      }
      return _err(404, 'Circle not found.');
    }
    if (method == 'DELETE' && seg.length == 2 && seg[0] == 'recurring') {
      for (final g in _groups.values) {
        if (g.recurring.any((r) => r['id'] == seg[1])) {
          g.recurring.removeWhere((r) => r['id'] == seg[1]);
          g.version++;
          return _ok(_detail(g, uid));
        }
      }
      return _err(404, 'Not found.');
    }
    if (seg.length >= 2 && seg[0] == 'expenses') {
      for (final g in _groups.values) {
        if (method == 'POST' && seg.length == 3 && seg[2] == 'restore') {
          final e = g.deleted.where((e) => e['id'] == seg[1]).firstOrNull;
          if (e == null) continue;
          g.deleted.remove(e);
          g.expenses.add(e);
          g.version++;
          return _ok(_detail(g, uid));
        }
        final i = g.expenses.indexWhere((e) => e['id'] == seg[1]);
        if (i < 0) continue;
        if (method == 'DELETE') {
          g.deleted.add(g.expenses.removeAt(i));
        } else if (method == 'PATCH') {
          g.expenses[i] = {...g.expenses[i], ...b, 'id': seg[1]};
        }
        g.version++;
        return _ok(_detail(g, uid));
      }
      return _err(404, 'Expense not found.');
    }
    if (method == 'DELETE' && seg.length == 2 && seg[0] == 'payments') {
      for (final g in _groups.values) {
        final before = g.payments.length;
        g.payments.removeWhere((p) => p['id'] == seg[1]);
        if (g.payments.length != before) {
          g.version++;
          return _ok(_detail(g, uid));
        }
      }
      return _err(404, 'Payment not found.');
    }
    return _err(404, 'No route for $method $path in the fake server.');
  }
}
