// Dart port of packages/core/src/split.ts. Same rules, same rounding, same results.

import 'dart:math' as math;

import 'money.dart';
import 'types.dart';

/// Split [total] into integer parts proportional to [weights] (largest remainder method).
/// Parts always add up to exactly [total]. Ties go to the earlier index, so results are stable.
List<int> allocate(int total, List<int> weights) {
  final sum = weights.fold<int>(0, (a, b) => a + math.max(0, b));
  if (sum <= 0 || total == 0) return List.filled(weights.length, 0);
  final sign = total < 0 ? -1 : 1;
  final t = total.abs();
  final raw = [for (final w in weights) (math.max(0, w) * t) / sum];
  final base = [for (final r in raw) r.floor()];
  var left = t - base.fold<int>(0, (a, b) => a + b);
  final order =
      [
        for (var i = 0; i < weights.length; i++)
          if (weights[i] > 0) (i: i, frac: raw[i] - raw[i].floor()),
      ]..sort((a, b) {
        final byFrac = b.frac.compareTo(a.frac);
        return byFrac != 0 ? byFrac : a.i.compareTo(b.i);
      });
  for (
    var k = 0;
    left > 0 && order.isNotEmpty;
    k = (k + 1) % order.length, left--
  ) {
    base[order[k].i] += 1;
  }
  return [for (final b in base) b * sign];
}

enum SplitError {
  noAmount,
  noPeople,
  exactMismatch,
  percentMismatch,
  noShares,
  payerMissing,
}

/// Check an expense's split. Returns null when it is valid.
SplitError? validateSplit(
  int amount,
  SplitMode mode,
  List<SplitItem> items,
  String paidBy,
  List<String> memberIds,
) {
  if (amount <= 0) return SplitError.noAmount;
  if (!memberIds.contains(paidBy)) return SplitError.payerMissing;
  final active = items
      .where((i) => memberIds.contains(i.memberId) && i.value > 0)
      .toList();
  if (active.isEmpty) {
    return mode == SplitMode.shares ? SplitError.noShares : SplitError.noPeople;
  }
  final sum = active.fold<int>(0, (a, b) => a + b.value);
  if (mode == SplitMode.exact && sum != amount) return SplitError.exactMismatch;
  if (mode == SplitMode.percent && sum != 10000) {
    return SplitError.percentMismatch;
  }
  return null;
}

/// What each member owes for one expense, in the expense's own currency (minor units).
Map<String, int> owedInExpenseCurrency(ExpenseLike e) {
  final items = e.items.where((i) => i.value > 0).toList();
  final out = <String, int>{};
  if (e.mode == SplitMode.exact) {
    for (final i in items) {
      out[i.memberId] = (out[i.memberId] ?? 0) + i.value;
    }
    return out;
  }
  final weights = [
    for (final i in items) e.mode == SplitMode.equal ? 1 : i.value,
  ];
  final parts = allocate(e.amount, weights);
  for (var k = 0; k < items.length; k++) {
    out[items[k].memberId] = (out[items[k].memberId] ?? 0) + parts[k];
  }
  return out;
}

/// Expense total in the group currency.
int expenseInGroupCurrency(ExpenseLike e, String groupCurrency) =>
    convertMinor(e.amount, e.currency, groupCurrency, e.rate);

/// What each member owes for one expense, in the group currency. Adds up to the converted total.
Map<String, int> owedInGroupCurrency(ExpenseLike e, String groupCurrency) {
  final own = owedInExpenseCurrency(e);
  if (e.currency == groupCurrency) return own;
  final ids = own.keys.toList();
  final parts = allocate(expenseInGroupCurrency(e, groupCurrency), [
    for (final id in ids) own[id]!,
  ]);
  return {for (var k = 0; k < ids.length; k++) ids[k]: parts[k]};
}

/// Net balance per member in the group currency.
/// Positive = the group owes them. Negative = they owe the group. Always sums to 0.
Map<String, int> computeBalances(GroupLike g) {
  final bal = {for (final id in g.memberIds) id: 0};
  for (final e in g.expenses) {
    final total = expenseInGroupCurrency(e, g.currency);
    if (bal.containsKey(e.paidBy)) bal[e.paidBy] = bal[e.paidBy]! + total;
    owedInGroupCurrency(e, g.currency).forEach((id, v) {
      if (bal.containsKey(id)) bal[id] = bal[id]! - v;
    });
  }
  for (final p in g.payments) {
    if (bal.containsKey(p.from)) bal[p.from] = bal[p.from]! + p.amount;
    if (bal.containsKey(p.to)) bal[p.to] = bal[p.to]! - p.amount;
  }
  return bal;
}

class _Side {
  _Side(this.id, this.v);
  final String id;
  int v;
}

/// Fewest-transfers plan: repeatedly match the biggest debtor with the biggest creditor.
/// At most n-1 transfers. Deterministic for the same input order.
List<Transfer> simplifyDebts(Map<String, int> balances, [List<String>? order]) {
  final ids = order ?? balances.keys.toList();
  int idx(String id) => ids.indexOf(id);
  final cred = [
    for (final id in ids)
      if ((balances[id] ?? 0) > 0) _Side(id, balances[id]!),
  ];
  final debt = [
    for (final id in ids)
      if ((balances[id] ?? 0) < 0) _Side(id, -balances[id]!),
  ];
  int byDesc(_Side a, _Side b) {
    final c = b.v.compareTo(a.v);
    return c != 0 ? c : idx(a.id).compareTo(idx(b.id));
  }

  final out = <Transfer>[];
  while (cred.isNotEmpty && debt.isNotEmpty) {
    cred.sort(byDesc);
    debt.sort(byDesc);
    final c = cred.first;
    final d = debt.first;
    final amt = math.min(c.v, d.v);
    if (amt > 0) out.add(Transfer(from: d.id, to: c.id, amount: amt));
    c.v -= amt;
    d.v -= amt;
    if (c.v == 0) cred.removeAt(0);
    if (d.v == 0) debt.removeAt(0);
  }
  return out;
}

int groupTotal(GroupLike g) =>
    g.expenses.fold(0, (a, e) => a + expenseInGroupCurrency(e, g.currency));

/// How much one member has paid out of pocket and their share of all expenses.
({int paid, int share}) memberStats(GroupLike g, String memberId) {
  var paid = 0;
  var share = 0;
  for (final e in g.expenses) {
    if (e.paidBy == memberId) paid += expenseInGroupCurrency(e, g.currency);
    share += owedInGroupCurrency(e, g.currency)[memberId] ?? 0;
  }
  return (paid: paid, share: share);
}
