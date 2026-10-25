// Dart port of packages/core/src/types.ts. Pure Dart: no Flutter imports, so it runs anywhere.

enum SplitMode {
  equal,
  exact,
  percent,
  shares;

  static SplitMode parse(String s) => SplitMode.values.firstWhere(
    (m) => m.name == s,
    orElse: () => SplitMode.equal,
  );
}

const categories = [
  'food',
  'groceries',
  'transport',
  'stay',
  'fun',
  'bills',
  'shopping',
  'other',
];

/// `value` meaning by mode:
///  * equal   – 1 = included, 0 = left out
///  * exact   – amount in minor units of the expense currency
///  * percent – basis points (25% = 2500); all items sum to 10000
///  * shares  – a whole-number weight (2 = twice as much as 1)
class SplitItem {
  const SplitItem(this.memberId, this.value);
  final String memberId;
  final int value;

  Map<String, Object> toJson() => {'memberId': memberId, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is SplitItem && other.memberId == memberId && other.value == value;

  @override
  int get hashCode => Object.hash(memberId, value);
}

/// The parts of an expense the money rules need.
class ExpenseLike {
  const ExpenseLike({
    required this.amount,
    required this.paidBy,
    required this.items,
    this.currency = 'AED',
    this.rate = 1,
    this.mode = SplitMode.equal,
  });

  /// Minor units in [currency].
  final int amount;
  final String currency;

  /// Group-currency major units per one expense-currency major unit.
  final double rate;
  final String paidBy;
  final SplitMode mode;
  final List<SplitItem> items;
}

class PaymentLike {
  const PaymentLike({
    required this.from,
    required this.to,
    required this.amount,
  });
  final String from;
  final String to;

  /// Minor units in the group currency.
  final int amount;
}

class GroupLike {
  const GroupLike({
    required this.currency,
    required this.memberIds,
    required this.expenses,
    this.payments = const [],
  });
  final String currency;
  final List<String> memberIds;
  final List<ExpenseLike> expenses;
  final List<PaymentLike> payments;
}

class Transfer {
  const Transfer({required this.from, required this.to, required this.amount});
  final String from;
  final String to;
  final int amount;

  factory Transfer.fromJson(Map<String, dynamic> j) => Transfer(
    from: j['from'] as String,
    to: j['to'] as String,
    amount: (j['amount'] as num).toInt(),
  );

  Map<String, Object> toJson() => {'from': from, 'to': to, 'amount': amount};

  @override
  bool operator ==(Object other) =>
      other is Transfer &&
      other.from == from &&
      other.to == to &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(from, to, amount);

  @override
  String toString() => 'Transfer($from → $to: $amount)';
}
