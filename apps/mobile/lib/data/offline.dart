import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/split.dart';
import '../core/types.dart';
import 'api.dart';
import 'models.dart';
import 'store.dart';

/// A change made with no connection, waiting to be sent. Expense and payment ids are made on the
/// device, so sending one twice never creates two.
class PendingOp {
  PendingOp({
    required this.kind,
    required this.groupId,
    required this.targetId,
    required this.body,
    required this.title,
  });

  /// 'add', 'edit', 'delete' (expenses) or 'pay'.
  final String kind;
  final String groupId;

  /// The expense or payment id.
  final String targetId;
  Map<String, dynamic> body;
  final String title;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'groupId': groupId,
    'targetId': targetId,
    'body': body,
    'title': title,
  };

  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
    kind: j['kind'] as String,
    groupId: j['groupId'] as String,
    targetId: j['targetId'] as String,
    body: (j['body'] as Map<String, dynamic>?) ?? {},
    title: j['title'] as String? ?? '',
  );
}

/// The group as the person should see it: the server's copy with the waiting changes laid on top,
/// balances and the settle-up plan worked out again with the same rules as the server.
/// Safe to apply twice: adding an expense that is already there replaces it.
Map<String, dynamic> applyPending(
  Map<String, dynamic> server,
  List<PendingOp> ops, {
  DateTime? now,
}) {
  final j = jsonDecode(jsonEncode(server)) as Map<String, dynamic>;
  final at = (now ?? DateTime.now()).toUtc().toIso8601String();
  final currency = j['currency'] as String;
  final expenses = [
    for (final e in (j['expenses'] as List<dynamic>? ?? const []))
      e as Map<String, dynamic>,
  ];
  final payments = [
    for (final p in (j['payments'] as List<dynamic>? ?? const []))
      p as Map<String, dynamic>,
  ];
  for (final op in ops) {
    switch (op.kind) {
      case 'add' || 'edit':
        final e = <String, dynamic>{
          ...op.body,
          'currency': op.body['currency'] ?? currency,
          'rate': op.body['rate'] ?? 1,
          'pending': true,
        };
        final i = expenses.indexWhere((x) => x['id'] == op.targetId);
        if (i >= 0) {
          expenses[i] = {...expenses[i], ...e};
        } else {
          expenses.insert(0, {'spentAt': at, 'createdAt': at, ...e});
        }
      case 'delete':
        expenses.removeWhere((x) => x['id'] == op.targetId);
      case 'pay':
        if (!payments.any((p) => p['id'] == op.targetId)) {
          payments.insert(0, {'paidAt': at, ...op.body, 'id': op.targetId});
        }
    }
  }
  j['expenses'] = expenses;
  j['payments'] = payments;

  final memberIds = [
    for (final m in (j['members'] as List<dynamic>? ?? const []))
      (m as Map<String, dynamic>)['id'] as String,
  ];
  final g = GroupLike(
    currency: currency,
    memberIds: memberIds,
    expenses: [for (final e in expenses) Expense.fromJson(e).core],
    payments: [
      for (final p in payments)
        PaymentLike(
          from: p['from'] as String,
          to: p['to'] as String,
          amount: (p['amount'] as num).toInt(),
        ),
    ],
  );
  final balances = computeBalances(g);
  j['balances'] = balances;
  j['transfers'] = [
    for (final t in simplifyDebts(balances, memberIds)) t.toJson(),
  ];
  j['total'] = groupTotal(g);
  return j;
}

/// Groups for the screens: from the server when there is a connection, from the copy on this
/// device when there is not, with changes made offline queued and replayed in order.
class Repo extends ChangeNotifier {
  Repo({required this.api, required this.store});

  final Api api;
  final KeyValueStore store;

  static const _queueKey = 'nn:queue';
  static const _groupsKey = 'nn:cache:groups';
  static const _overviewKey = 'nn:cache:overview';
  static String _groupKey(String id) => 'nn:cache:g:$id';

  final _ops = <PendingOp>[];
  final _server = <String, Map<String, dynamic>>{};
  var _syncing = false;

  /// Called with the title of a change the server refused while syncing (it is dropped).
  void Function(String title)? onSyncFailed;

  int get pending => _ops.length;
  int pendingFor(String groupId) =>
      _ops.where((o) => o.groupId == groupId).length;

  Future<void> load() async {
    final raw = await store.read(_queueKey);
    _ops.clear();
    if (raw != null) {
      try {
        for (final o in jsonDecode(raw) as List<dynamic>) {
          _ops.add(PendingOp.fromJson(o as Map<String, dynamic>));
        }
      } on FormatException {
        // A broken queue is dropped rather than blocking the app.
      }
    }
  }

  Future<void> forget() async {
    _ops.clear();
    _server.clear();
    await store.write(_queueKey, null);
    await store.write(_groupsKey, null);
    await store.write(_overviewKey, null);
  }

  Future<void> _saveQueue() async {
    await store.write(
      _queueKey,
      _ops.isEmpty ? null : jsonEncode([for (final o in _ops) o.toJson()]),
    );
    notifyListeners();
  }

  Future<void> _remember(GroupDetail g) async {
    _server[g.id] = g.json;
    await store.write(_groupKey(g.id), jsonEncode(g.json));
  }

  GroupDetail _withPending(Map<String, dynamic> server) {
    final id = server['id'] as String;
    final ops = [
      for (final o in _ops)
        if (o.groupId == id) o,
    ];
    return GroupDetail.fromJson(
      ops.isEmpty ? server : applyPending(server, ops),
    );
  }

  Future<Map<String, dynamic>?> _serverCopy(String id) async {
    final hit = _server[id];
    if (hit != null) return hit;
    final raw = await store.read(_groupKey(id));
    if (raw == null) return null;
    try {
      return _server[id] = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  Future<List<GroupSummary>?> cachedGroups() async {
    final raw = await store.read(_groupsKey);
    if (raw == null) return null;
    try {
      return [
        for (final g in jsonDecode(raw) as List<dynamic>)
          GroupSummary.fromJson(g as Map<String, dynamic>),
      ];
    } on FormatException {
      return null;
    }
  }

  Future<List<GroupSummary>> groups() async {
    final list = await api.groups();
    await store.write(_groupsKey, jsonEncode([for (final g in list) g.json]));
    return list;
  }

  /// Home's last overview on this device, shown at once while the server's answer comes.
  Future<Overview?> cachedOverview() async {
    final raw = await store.read(_overviewKey);
    if (raw == null) return null;
    try {
      return Overview.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  Future<Overview> overview() async {
    final o = await api.overview();
    await store.write(_overviewKey, jsonEncode(o.json));
    return o;
  }

  Future<GroupDetail?> cachedGroup(String id) async {
    final s = await _serverCopy(id);
    return s == null ? null : _withPending(s);
  }

  /// The group from the server, with anything still waiting to sync laid on top.
  Future<GroupDetail> group(String id) async {
    final g = await api.group(id);
    await _remember(g);
    return _withPending(g.json);
  }

  /// Keeps a detail the server just sent (after any change made online).
  Future<GroupDetail> took(GroupDetail g) async {
    await _remember(g);
    return _withPending(g.json);
  }

  Future<GroupDetail> _local(GroupDetail fallback) async =>
      _withPending(await _serverCopy(fallback.id) ?? fallback.json);

  Future<void> _queue(PendingOp op) async {
    _ops.add(op);
    await _saveQueue();
  }

  PendingOp? _pendingAdd(String expenseId) {
    for (final o in _ops) {
      if (o.kind == 'add' && o.targetId == expenseId) return o;
    }
    return null;
  }

  Future<({GroupDetail detail, bool queued})> saveExpense(
    GroupDetail g,
    ExpenseInput e, {
    required bool editing,
    DateTime? spentAt,
  }) async {
    final add = editing ? _pendingAdd(e.id) : null;
    if (add != null) {
      // Still waiting to be sent: change what will be sent.
      add.body = {...add.body, ...e.toJson()};
      await _saveQueue();
      return (detail: await _local(g), queued: true);
    }
    try {
      final d = editing
          ? await api.updateExpense(e)
          : await api.addExpense(g.id, e);
      return (detail: await took(d), queued: false);
    } on ApiException catch (x) {
      if (!x.offline) rethrow;
      await _queue(
        PendingOp(
          kind: editing ? 'edit' : 'add',
          groupId: g.id,
          targetId: e.id,
          title: e.title,
          body: {
            ...e.toJson(),
            if (!editing)
              'spentAt': (spentAt ?? DateTime.now()).toUtc().toIso8601String(),
          },
        ),
      );
      return (detail: await _local(g), queued: true);
    }
  }

  Future<({GroupDetail detail, bool queued})> deleteExpense(
    GroupDetail g,
    String id,
  ) async {
    if (_pendingAdd(id) != null) {
      _ops.removeWhere((o) => o.targetId == id);
      await _saveQueue();
      return (detail: await _local(g), queued: true);
    }
    try {
      return (detail: await took(await api.deleteExpense(id)), queued: false);
    } on ApiException catch (x) {
      if (!x.offline) rethrow;
      _ops.removeWhere((o) => o.targetId == id && o.kind == 'edit');
      final title = g.expenses
          .firstWhere(
            (e) => e.id == id,
            orElse: () => Expense.fromJson({
              'id': id,
              'title': '',
              'currency': g.currency,
              'paidBy': g.me,
            }),
          )
          .title;
      await _queue(
        PendingOp(
          kind: 'delete',
          groupId: g.id,
          targetId: id,
          title: title,
          body: const {},
        ),
      );
      return (detail: await _local(g), queued: true);
    }
  }

  /// Undoes a change that has not been sent yet.
  Future<GroupDetail> cancelPending(GroupDetail g, String targetId) async {
    _ops.removeWhere((o) => o.targetId == targetId);
    await _saveQueue();
    return _local(g);
  }

  Future<({String id, GroupDetail detail, bool queued})> pay(
    GroupDetail g,
    Transfer t,
  ) async {
    final id = newId();
    try {
      final r = await api.pay(g.id, t, id: id);
      return (id: r.id, detail: await took(r.detail), queued: false);
    } on ApiException catch (x) {
      if (!x.offline) rethrow;
      await _queue(
        PendingOp(
          kind: 'pay',
          groupId: g.id,
          targetId: id,
          title: '${g.nameOf(t.from)} → ${g.nameOf(t.to)}',
          body: t.toJson(),
        ),
      );
      return (id: id, detail: await _local(g), queued: true);
    }
  }

  /// Sends what is waiting, oldest first. Stops at the first sign of no connection; drops (and
  /// reports) anything the server refuses. Returns how many went through.
  Future<int> sync() async {
    if (_syncing || _ops.isEmpty) return 0;
    _syncing = true;
    var sent = 0;
    try {
      while (_ops.isNotEmpty) {
        final op = _ops.first;
        try {
          final GroupDetail d;
          switch (op.kind) {
            case 'add':
              d = await api.addExpense(
                op.groupId,
                ExpenseInput.fromJson(op.body),
              );
            case 'edit':
              d = await api.updateExpense(ExpenseInput.fromJson(op.body));
            case 'delete':
              d = await api.deleteExpense(op.targetId);
            default:
              d = (await api.pay(
                op.groupId,
                Transfer.fromJson(op.body),
                id: op.targetId,
              )).detail;
          }
          _ops.removeAt(0);
          await _remember(d);
          sent++;
        } on ApiException catch (x) {
          if (x.rejected) {
            _ops.removeAt(0);
            onSyncFailed?.call(op.title);
            continue;
          }
          break;
        }
      }
    } finally {
      _syncing = false;
      await _saveQueue();
    }
    return sent;
  }
}
