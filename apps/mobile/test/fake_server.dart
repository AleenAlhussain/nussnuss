// An in-memory stand-in for the NestJS API, just enough for widget tests.
// Balances come from the same Dart core the app uses, as the real server does with the TypeScript core.
import 'dart:convert';

import 'package:nussnuss/core/split.dart';
import 'package:nussnuss/core/types.dart';
import 'package:nussnuss/data/api.dart';

class _Group {
  _Group(this.id, this.name, this.emoji, this.currency);
  final String id;
  final String name;
  final String emoji;
  final String currency;
  int version = 1;
  final members = <Map<String, Object?>>[];
  final expenses = <Map<String, Object?>>[];
  final payments = <Map<String, Object?>>[];
}

class FakeServer {
  final _users = <String, Map<String, String>>{};
  final _groups = <String, _Group>{};
  int _n = 0;
  final calls = <String>[];

  String _id() =>
      '00000000-0000-4000-8000-${(++_n).toString().padLeft(12, '0')}';

  ApiResponse _ok(Object o, [int status = 200]) =>
      ApiResponse(status, jsonEncode(o));
  ApiResponse _err(int status, String message) =>
      ApiResponse(status, jsonEncode({'message': message}));

  GroupLike _core(_Group g) => GroupLike(
    currency: g.currency,
    memberIds: [for (final m in g.members) m['id']! as String],
    expenses: [
      for (final e in g.expenses)
        ExpenseLike(
          amount: e['amount']! as int,
          currency: g.currency,
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

  String _memberOf(_Group g, String userId) =>
      g.members.firstWhere((m) => m['userId'] == userId)['id']! as String;

  Map<String, Object?> _detail(_Group g, String userId) {
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
      'me': me,
      'members': [
        for (final m in g.members)
          {
            'id': m['id'],
            'name': m['name'],
            'claimed': m['userId'] != null,
            'isMe': m['id'] == me,
          },
      ],
      'expenses': [
        for (final e in g.expenses.reversed)
          {
            ...e,
            'currency': g.currency,
            'rate': 1,
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
    };
  }

  Future<ApiResponse> call(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    final path = url.path;
    calls.add('$method $path');
    final b = body == null
        ? const <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;

    if (method == 'POST' && path == '/auth/anonymous') {
      final token = 'token-${_id()}';
      final user = {
        'id': _id(),
        'name': b['name'] as String,
        'locale': b['locale'] as String? ?? 'en',
      };
      _users[token] = user;
      return _ok({'token': token, 'user': user}, 201);
    }

    final user = _users[headers['Authorization']?.replaceFirst('Bearer ', '')];
    if (user == null) return _err(401, 'Sign in again.');
    final uid = user['id']!;
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();

    if (method == 'GET' && path == '/me') return _ok(user);
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
      final g = _Group(
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
    if (seg.length >= 2 && seg[0] == 'groups') {
      final g = _groups[seg[1]];
      if (g == null) return _err(404, 'Group not found.');
      if (method == 'GET' && seg.length == 2) return _ok(_detail(g, uid));
      if (method == 'GET' && seg.length == 3 && seg[2] == 'changes') {
        return _ok({'version': g.version, 'changes': <Object>[]});
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
          });
          g.version++;
        }
        return _ok({'id': id, 'detail': _detail(g, uid)}, 201);
      }
      if (method == 'POST' && seg.length == 3 && seg[2] == 'payments') {
        final id = _id();
        g.payments.add({
          'id': id,
          'from': b['from'],
          'to': b['to'],
          'amount': b['amount'],
        });
        g.version++;
        return _ok({'id': id, 'detail': _detail(g, uid)}, 201);
      }
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
