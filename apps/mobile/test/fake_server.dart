// An in-memory stand-in for the NestJS API, just enough for widget tests.
// Balances come from the same Dart core the app uses, as the real server does with the TypeScript core.
import 'dart:convert';

import 'package:nussnuss/core/identity.dart';
import 'package:nussnuss/core/split.dart';
import 'package:nussnuss/core/types.dart';
import 'package:nussnuss/data/api.dart';
import 'package:nussnuss/format.dart' show clock;

class FakeGroup {
  FakeGroup(this.id, this.name, this.emoji, this.currency, {this.cover});
  final String id;
  String name;
  final String emoji;
  String currency;

  /// 'icon:tone', or null for one drawn from the emoji.
  String? cover;
  int version = 1;

  /// What happened, oldest first, like the server's changes table: id, entity ('expense' or
  /// 'payment'), entityId, op ('create' or 'update'), actor (a user id or null) and at.
  final log = <Map<String, Object?>>[];
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

  /// Task timings the app reported (POST /telemetry/timing).
  final timings = <Map<String, dynamic>>[];

  /// Who made each invite, by token.
  final _invitedBy = <String, String>{};
  int _change = 0;

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

  Map<String, Object?>? _userById(Object? id) => id == null
      ? null
      : _users.values.where((u) => u['id'] == id).firstOrNull ?? _others[id];

  /// Friends who joined from another phone (see [claim]).
  final _others = <Object?, Map<String, Object?>>{};

  /// [member] joins [group] from their own phone, so what they do shows as theirs.
  String claim(String group, String member) {
    final g = groupNamed(group);
    final m = g.members.firstWhere((m) => m['name'] == member);
    final id = m['userId'] as String? ?? _id();
    m['userId'] = id;
    _others[id] ??= {'id': id, 'name': member, 'locale': 'en'};
    return id;
  }

  /// [member] (claimed with [claim]) adds an expense they paid, split equally between everyone.
  void addExpenseBy(String group, String member, String title, int amount) {
    final g = groupNamed(group);
    final m = g.members.firstWhere((m) => m['name'] == member);
    final id = _id();
    g.expenses.add({
      'id': id,
      'title': title,
      'amount': amount,
      'paidBy': m['id'],
      'mode': 'equal',
      'items': [
        for (final x in g.members) {'memberId': x['id'], 'value': 1},
      ],
      'category': 'food',
      'currency': null,
      'rate': null,
    });
    g.version++;
    _logChange(g, 'expense', id, 'create', m['userId'] as String?);
  }

  void _logChange(
    FakeGroup g,
    String entity,
    String id,
    String op,
    String? actor,
  ) => g.log.add({
    'id': ++_change,
    'entity': entity,
    'entityId': id,
    'op': op,
    'actor': actor,
    'at': clock(),
  });

  Map<String, Object?> _avatar(Object? setting, String name) {
    final a = setting is Map ? setting : null;
    final tone = a?['tone'] is String ? a!['tone'] as String : toneFor(name);
    return switch (a?['kind']) {
      'emoji' => {'kind': 'emoji', 'value': a!['value'], 'tone': tone},
      'photo' => {'kind': 'photo', 'url': '/avatars/${a!['id']}', 'tone': tone},
      _ => {'kind': 'initial', 'tone': tone},
    };
  }

  Map<String, Object?> _memberAvatar(Map<String, Object?> m) =>
      _avatar(_userById(m['userId'])?['avatar'], m['name']! as String);

  String _coverOf(FakeGroup g) =>
      coverKey(groupCover(cover: g.cover, emoji: g.emoji));

  Map<String, Object?> _brief(FakeGroup g) => {
    'id': g.id,
    'name': g.name,
    'emoji': g.emoji,
    'cover': _coverOf(g),
    'currency': g.currency,
  };

  Map<String, Object?>? _person(FakeGroup g, String me, Object? memberId) {
    final m = g.members.where((m) => m['id'] == memberId).firstOrNull;
    if (m == null) return null;
    return {'name': m['name'], 'me': m['id'] == me, 'avatar': _memberAvatar(m)};
  }

  ExpenseLike _expenseLike(FakeGroup g, Map<String, Object?> e) => ExpenseLike(
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
  );

  Iterable<FakeGroup> _mine(String uid) =>
      _groups.values.where((g) => g.members.any((m) => m['userId'] == uid));

  /// What [other] and I owe each other in a group, from its settle-up plan (+ they owe me).
  int _pair(FakeGroup g, String me, String other) {
    final core = _core(g);
    var v = 0;
    for (final t in simplifyDebts(computeBalances(core), core.memberIds)) {
      if (t.from == other && t.to == me) v += t.amount;
      if (t.from == me && t.to == other) v -= t.amount;
    }
    return v;
  }

  String _hex(String seed) {
    final a = stableHash('a:$seed').toRadixString(16).padLeft(8, '0');
    final b = stableHash('b:$seed').toRadixString(16).padLeft(8, '0');
    final c = stableHash('c:$seed').toRadixString(16).padLeft(8, '0');
    return '$a$b$c'.substring(0, 20);
  }

  /// Everyone I share a group with, by person key: a claimed member by account, a name by name.
  Map<
    String,
    ({
      String name,
      Object? avatar,
      bool claimed,
      List<(FakeGroup, Map<String, Object?>, int)> groups,
    })
  >
  _links(String uid) {
    final out =
        <
          String,
          ({
            String name,
            Object? avatar,
            bool claimed,
            List<(FakeGroup, Map<String, Object?>, int)> groups,
          })
        >{};
    for (final g in _mine(uid)) {
      final me = _memberOf(g, uid);
      for (final m in g.members) {
        if (m['id'] == me) continue;
        final claimed = m['userId'] != null;
        final key = claimed
            ? 'u${_hex('${m['userId']}')}'
            : 'n${_hex((m['name']! as String).trim().toLowerCase())}';
        final link = out[key] ??= (
          name: m['name']! as String,
          avatar: _memberAvatar(m),
          claimed: claimed,
          groups: [],
        );
        link.groups.add((g, m, _pair(g, me, m['id']! as String)));
      }
    }
    return out;
  }

  List<Map<String, Object?>> _sum(Iterable<(String, int)> items) {
    final by = <String, int>{};
    for (final (c, a) in items) {
      by[c] = (by[c] ?? 0) + a;
    }
    final list =
        [
          for (final e in by.entries)
            if (e.value != 0) {'currency': e.key, 'amount': e.value},
        ]..sort(
          (a, b) => (b['amount']! as int).abs() - (a['amount']! as int).abs(),
        );
    return list;
  }

  int _unread(String uid) {
    final seen = _userById(uid)?['seenAt'] as DateTime?;
    var n = 0;
    for (final g in _mine(uid)) {
      for (final c in g.log) {
        if (c['actor'] == uid) continue;
        if (seen != null && !(c['at']! as DateTime).isAfter(seen)) continue;
        n++;
      }
    }
    return n > 99 ? 99 : n;
  }

  Map<String, Object?> _overview(String uid) {
    final mine = _mine(uid).toList();
    final links = _links(uid);
    final totals = _sum([
      for (final g in mine)
        (g.currency, computeBalances(_core(g))[_memberOf(g, uid)] ?? 0),
    ]);
    final pairs = [
      for (final e in links.entries)
        for (final (g, m, amount) in e.value.groups)
          if (amount != 0)
            (key: e.key, link: e.value, g: g, m: m, amount: amount),
    ];
    final owe = [...pairs.where((x) => x.amount < 0)]
      ..sort((a, b) => a.amount - b.amount);
    final owed = [...pairs.where((x) => x.amount > 0)]
      ..sort((a, b) => b.amount - a.amount);
    final pick = owe.firstOrNull ?? owed.firstOrNull;
    Map<String, Object?>? next;
    if (pick != null) {
      next = {
        'kind': pick.amount < 0 ? 'pay' : 'collect',
        'person': {
          'key': pick.key,
          'name': pick.link.name,
          'avatar': pick.link.avatar,
        },
        'amount': pick.amount.abs(),
        'currency': pick.g.currency,
        'group': _brief(pick.g),
        'memberId': pick.m['id'],
        'payTo': pick.amount < 0
            ? (pick.m['payTo'] ?? const <Object>[])
            : const <Object>[],
      };
    } else {
      final empty = mine.where((g) => g.expenses.isEmpty).firstOrNull;
      if (empty != null) {
        next = {
          'kind': empty.members.length > 1 ? 'first' : 'invite',
          'group': _brief(empty),
        };
      }
    }
    final strip =
        [
          for (final e in links.entries)
            (
              key: e.key,
              link: e.value,
              sums: _sum([
                for (final (g, _, a) in e.value.groups) (g.currency, a),
              ]),
            ),
        ]..sort((a, b) {
          int size(List<Map<String, Object?>> s) =>
              s.isEmpty ? 0 : (s.first['amount']! as int).abs();
          final d = size(b.sums) - size(a.sums);
          return d != 0 ? d : a.link.name.compareTo(b.link.name);
        });
    return {
      'totals': totals,
      'groups': mine.length,
      'next': next,
      'people': [
        for (final x in strip.take(24))
          {
            'key': x.key,
            'name': x.link.name,
            'avatar': x.link.avatar,
            'balances': x.sums,
            'groups': x.link.groups.length,
          },
      ],
      'unread': _unread(uid),
    };
  }

  Map<String, Object?>? _personView(String uid, String key) {
    final link = _links(uid)[key];
    if (link == null) return null;
    final shared = <Map<String, Object?>>[];
    for (final (g, m, _) in link.groups) {
      final me = _memberOf(g, uid);
      for (final e in g.expenses.reversed) {
        final mine = e['paidBy'] == me;
        final theirs = e['paidBy'] == m['id'];
        if (!mine && !theirs) continue;
        final owed = owedInGroupCurrency(_expenseLike(g, e), g.currency);
        final amount = mine ? owed[m['id']] ?? 0 : -(owed[me] ?? 0);
        if (amount == 0) continue;
        shared.add({
          'id': e['id'],
          'group': _brief(g),
          'title': e['title'],
          'category': e['category'] ?? 'other',
          'currency': g.currency,
          'amount': amount,
          'paidByMe': mine,
          'at': DateTime.now().toIso8601String(),
        });
      }
    }
    return {
      'key': key,
      'name': link.name,
      'avatar': link.avatar,
      'claimed': link.claimed,
      'balances': _sum([for (final (g, _, a) in link.groups) (g.currency, a)]),
      'groups': [
        for (final (g, m, a) in link.groups)
          {
            ..._brief(g),
            'amount': a,
            'memberId': m['id'],
            'me': _memberOf(g, uid),
            'payTo': m['payTo'] ?? const <Object>[],
          },
      ],
      'shared': shared.take(30).toList(),
    };
  }

  Map<String, Object?> _activity(String uid, {int? before, String? group}) {
    final seen = _userById(uid)?['seenAt'] as DateTime?;
    final mine = [
      for (final g in _mine(uid))
        if (group == null || g.id == group) g,
    ];
    final rows = [
      for (final g in mine)
        for (final c in g.log)
          if (before == null || (c['id']! as int) < before) (g, c),
    ]..sort((a, b) => (b.$2['id']! as int) - (a.$2['id']! as int));
    final items = <Map<String, Object?>>[];
    final once = <String>{};
    int? last;
    for (final (g, c) in rows) {
      if (items.length >= 30) break;
      last = c['id']! as int;
      if (!once.add('${c['entityId']}:${c['op']}')) continue;
      final me = _memberOf(g, uid);
      final actor = g.members
          .where((m) => m['userId'] != null && m['userId'] == c['actor'])
          .firstOrNull;
      final at = c['at']! as DateTime;
      final base = {
        'id': '${c['id']}',
        'op': c['op'],
        'at': at.toIso8601String(),
        'group': _brief(g),
        'unread': c['actor'] != uid && (seen == null || at.isAfter(seen)),
      };
      if (c['entity'] == 'expense') {
        final e = g.expenses.where((x) => x['id'] == c['entityId']).firstOrNull;
        if (e == null) continue;
        final like = _expenseLike(g, e);
        final owed = owedInGroupCurrency(like, g.currency)[me] ?? 0;
        final total = expenseInGroupCurrency(like, g.currency);
        items.add({
          ...base,
          'kind': 'expense',
          'actor': _person(g, me, actor?['id'] ?? e['paidBy']),
          'expense': {
            'id': e['id'],
            'title': e['title'],
            'amount': total,
            'category': e['category'] ?? 'other',
            'paidBy': _person(g, me, e['paidBy']),
            'impact': (e['paidBy'] == me ? total : 0) - owed,
          },
        });
      } else {
        final pay = g.payments
            .where((x) => x['id'] == c['entityId'])
            .firstOrNull;
        if (pay == null) continue;
        items.add({
          ...base,
          'kind': 'payment',
          'actor': _person(g, me, actor?['id']),
          'payment': {
            'id': pay['id'],
            'amount': pay['amount'],
            'from': _person(g, me, pay['from']),
            'to': _person(g, me, pay['to']),
          },
        });
      }
    }
    final more = last != null && rows.isNotEmpty && last != rows.last.$2['id'];
    return {
      'items': items,
      'next': more ? '$last' : null,
      'unread': _unread(uid),
    };
  }

  Map<String, Object?>? _lastActivity(FakeGroup g, String uid) {
    final me = _memberOf(g, uid);
    for (final c in g.log.reversed) {
      final at = (c['at']! as DateTime).toIso8601String();
      if (c['entity'] == 'expense') {
        final e = g.expenses.where((x) => x['id'] == c['entityId']).firstOrNull;
        if (e == null) continue;
        final actor = g.members
            .where((m) => m['userId'] != null && m['userId'] == c['actor'])
            .firstOrNull;
        return {
          'kind': 'expense',
          'who': _person(g, me, actor?['id'] ?? e['paidBy']),
          'title': e['title'],
          'at': at,
        };
      }
      final pay = g.payments.where((x) => x['id'] == c['entityId']).firstOrNull;
      if (pay == null) continue;
      return {
        'kind': 'payment',
        'from': _person(g, me, pay['from']),
        'to': _person(g, me, pay['to']),
        'at': at,
      };
    }
    return null;
  }

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
      'cover': _coverOf(g),
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
            'avatar': _memberAvatar(m),
            'payTo':
                m['payTo'] ??
                (m['userId'] == null
                    ? const <Object>[]
                    : _userById(m['userId'])?['payTo'] ?? const <Object>[]),
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
    'avatar': _avatar(u['avatar'], u['name']! as String),
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
      final by = _userById(_invitedBy[seg[1]]);
      return _ok({
        'group': {
          'id': g.id,
          'name': g.name,
          'emoji': g.emoji,
          'cover': _coverOf(g),
          'currency': g.currency,
        },
        'members': [
          for (final m in g.members)
            {
              'id': m['id'],
              'name': m['name'],
              'claimed': m['userId'] != null,
              'avatar': _memberAvatar(m),
            },
        ],
        'invitedBy': by == null
            ? null
            : {
                'name': by['name'],
                'avatar': _avatar(by['avatar'], by['name']! as String),
              },
      });
    }
    if (method == 'POST' && path == '/telemetry/crash') {
      return const ApiResponse(204, '');
    }
    if (method == 'POST' && path == '/telemetry/timing') {
      timings.add(b);
      return const ApiResponse(204, '');
    }

    final user = _users[headers['Authorization']?.replaceFirst('Bearer ', '')];
    if (user == null) return _err(401, 'Sign in again.');
    final uid = user['id']! as String;

    if (method == 'GET' && path == '/me') return _ok(_meView(user));
    if (method == 'PATCH' && path == '/me') {
      if (b['name'] != null) user['name'] = b['name'];
      if (b['locale'] != null) user['locale'] = b['locale'];
      final avatar = b['avatar'];
      if (avatar is Map) {
        if (avatar['kind'] != 'initial' && avatar['kind'] != 'emoji') {
          return _err(400, 'Pick an initial or an emoji.');
        }
        user['avatar'] = {
          'kind': avatar['kind'],
          'tone': avatar['tone'],
          if (avatar['value'] != null) 'value': avatar['value'],
        };
      }
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
    if (method == 'POST' && path == '/me/photo') {
      final bytes = base64Decode(b['data'] as String);
      if (bytes.length > 70000) {
        return _err(400, 'That photo is too big. Try a smaller one.');
      }
      final tone = _avatar(user['avatar'], user['name']! as String)['tone'];
      user['avatar'] = {'kind': 'photo', 'id': _id(), 'tone': tone};
      return _ok(_meView(user), 201);
    }
    if (method == 'DELETE' && path == '/me/photo') {
      final tone = _avatar(user['avatar'], user['name']! as String)['tone'];
      user['avatar'] = {'kind': 'initial', 'tone': tone};
      return _ok(_meView(user));
    }
    if (method == 'GET' && path == '/overview') return _ok(_overview(uid));
    if (method == 'GET' && seg.length == 2 && seg[0] == 'people') {
      final view = _personView(uid, seg[1]);
      return view == null ? _err(404, 'Person not found.') : _ok(view);
    }
    if (method == 'POST' &&
        seg.length == 3 &&
        seg[0] == 'people' &&
        seg[2] == 'settle') {
      final link = _links(uid)[seg[1]];
      if (link == null) return _err(404, 'Person not found.');
      final made = <Map<String, Object?>>[];
      for (final (g, m, amount) in link.groups) {
        if (amount == 0) continue;
        final me = _memberOf(g, uid);
        final id = _id();
        g.payments.add({
          'id': id,
          'from': amount > 0 ? m['id'] : me,
          'to': amount > 0 ? me : m['id'],
          'amount': amount.abs(),
        });
        g.version++;
        _logChange(g, 'payment', id, 'create', uid);
        made.add({'id': id, 'groupId': g.id});
      }
      return _ok({'payments': made, 'person': _personView(uid, seg[1])}, 201);
    }
    if (method == 'POST' && path == '/payments/undo') {
      final ids = (b['ids'] as List<dynamic>).cast<String>();
      var n = 0;
      for (final g in _groups.values) {
        final before = g.payments.length;
        g.payments.removeWhere((p) => ids.contains(p['id']));
        if (g.payments.length != before) {
          n += before - g.payments.length;
          g.version++;
        }
      }
      return _ok({'undone': n});
    }
    if (method == 'GET' && path == '/activity') {
      final before = url.queryParameters['before'];
      return _ok(
        _activity(
          uid,
          before: before == null ? null : int.parse(before),
          group: url.queryParameters['group'],
        ),
      );
    }
    if (method == 'POST' && path == '/activity/seen') {
      user['seenAt'] = clock();
      return const ApiResponse(204, '');
    }
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
        for (final g in _mine(uid))
          {
            'id': g.id,
            'name': g.name,
            'emoji': g.emoji,
            'cover': _coverOf(g),
            'currency': g.currency,
            'version': g.version,
            'updatedAt': DateTime.now().toIso8601String(),
            'memberCount': g.members.length,
            'memberNames': [for (final m in g.members) m['name']],
            'members': [
              for (final m in g.members.take(5))
                {
                  'name': m['name'],
                  'me': m['userId'] == uid,
                  'avatar': _memberAvatar(m),
                },
            ],
            'expenseCount': g.expenses.length,
            'settled':
                g.expenses.isNotEmpty &&
                computeBalances(_core(g)).values.every((v) => v == 0),
            'lastActivity': _lastActivity(g, uid),
            'total': groupTotal(_core(g)),
            'myBalance': computeBalances(_core(g))[_memberOf(g, uid)],
          },
      ]);
    }
    if (method == 'POST' && path == '/groups') {
      final g = FakeGroup(
        _id(),
        b['name'] as String,
        b['emoji'] as String? ?? '',
        b['currency'] as String,
        cover: b['cover'] as String?,
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
      if (method == 'PATCH' && seg.length == 2) {
        if (b['name'] != null) g.name = b['name'] as String;
        if (b['cover'] != null) g.cover = b['cover'] as String;
        if (b['currency'] != null) g.currency = b['currency'] as String;
        g.version++;
        return _ok(_detail(g, uid));
      }
      if (method == 'GET' && seg.length == 3 && seg[2] == 'changes') {
        return _ok({'version': g.version, 'changes': <Object>[]});
      }
      if (method == 'POST' && seg.length == 3 && seg[2] == 'invites') {
        final token = 'inv${_id().substring(29)}';
        _invites[token] = g.id;
        _invitedBy[token] = uid;
        return _ok({'token': token, 'path': '/j/$token', 'expiresAt': ''}, 201);
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
          _logChange(g, 'expense', id, 'create', uid);
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
          _logChange(g, 'payment', id, 'create', uid);
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
          _logChange(g, 'expense', seg[1], 'update', uid);
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
