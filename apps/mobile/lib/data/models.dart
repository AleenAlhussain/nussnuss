// What the API sends back. Field names match apps/web/lib/api.ts and the NestJS controllers.
import '../core/types.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime _date(Object? v) =>
    DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

class Me {
  const Me({required this.id, required this.name, required this.locale});
  final String id;
  final String name;
  final String locale;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    name: j['name'] as String,
    locale: j['locale'] as String? ?? 'en',
  );

  Map<String, String> toJson() => {'id': id, 'name': name, 'locale': locale};
}

class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.emoji,
    required this.currency,
    required this.version,
    required this.updatedAt,
    required this.memberNames,
    required this.total,
    required this.myBalance,
  });

  final String id;
  final String name;
  final String emoji;
  final String currency;
  final int version;
  final DateTime updatedAt;
  final List<String> memberNames;
  final int total;
  final int myBalance;

  factory GroupSummary.fromJson(Map<String, dynamic> j) => GroupSummary(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: j['emoji'] as String? ?? '',
    currency: j['currency'] as String,
    version: _int(j['version']),
    updatedAt: _date(j['updatedAt']),
    memberNames: (j['memberNames'] as List<dynamic>? ?? const [])
        .cast<String>(),
    total: _int(j['total']),
    myBalance: _int(j['myBalance']),
  );
}

class Member {
  const Member({
    required this.id,
    required this.name,
    required this.claimed,
    required this.isMe,
  });
  final String id;
  final String name;
  final bool claimed;
  final bool isMe;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    id: j['id'] as String,
    name: j['name'] as String,
    claimed: j['claimed'] as bool? ?? false,
    isMe: j['isMe'] as bool? ?? false,
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    required this.rate,
    required this.paidBy,
    required this.mode,
    required this.items,
    required this.category,
    required this.spentAt,
  });

  final String id;
  final String title;
  final int amount;
  final String currency;
  final double rate;
  final String paidBy;
  final SplitMode mode;
  final List<SplitItem> items;
  final String category;
  final DateTime spentAt;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'] as String,
    title: j['title'] as String,
    amount: _int(j['amount']),
    currency: j['currency'] as String,
    rate: (j['rate'] as num?)?.toDouble() ?? 1,
    paidBy: j['paidBy'] as String,
    mode: SplitMode.parse(j['mode'] as String? ?? 'equal'),
    items: [
      for (final i in _list(j['items']))
        SplitItem(i['memberId'] as String, _int(i['value'])),
    ],
    category: j['category'] as String? ?? 'other',
    spentAt: _date(j['spentAt']),
  );

  ExpenseLike get core => ExpenseLike(
    amount: amount,
    currency: currency,
    rate: rate,
    paidBy: paidBy,
    mode: mode,
    items: items,
  );
}

class Payment {
  const Payment({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.paidAt,
  });
  final String id;
  final String from;
  final String to;
  final int amount;
  final DateTime paidAt;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: j['id'] as String,
    from: j['from'] as String,
    to: j['to'] as String,
    amount: _int(j['amount']),
    paidAt: _date(j['paidAt']),
  );
}

class GroupDetail {
  const GroupDetail({
    required this.id,
    required this.name,
    required this.emoji,
    required this.currency,
    required this.version,
    required this.me,
    required this.members,
    required this.expenses,
    required this.payments,
    required this.total,
    required this.balances,
    required this.transfers,
  });

  final String id;
  final String name;
  final String emoji;
  final String currency;
  final int version;

  /// The member id that is the signed-in person in this group.
  final String me;
  final List<Member> members;
  final List<Expense> expenses;
  final List<Payment> payments;
  final int total;
  final Map<String, int> balances;
  final List<Transfer> transfers;

  factory GroupDetail.fromJson(Map<String, dynamic> j) => GroupDetail(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: j['emoji'] as String? ?? '',
    currency: j['currency'] as String,
    version: _int(j['version']),
    me: j['me'] as String,
    members: [for (final m in _list(j['members'])) Member.fromJson(m)],
    expenses: [for (final e in _list(j['expenses'])) Expense.fromJson(e)],
    payments: [for (final p in _list(j['payments'])) Payment.fromJson(p)],
    total: _int(j['total']),
    balances: {
      for (final e
          in (j['balances'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: _int(e.value),
    },
    transfers: [for (final t in _list(j['transfers'])) Transfer.fromJson(t)],
  );

  String nameOf(String memberId) {
    for (final m in members) {
      if (m.id == memberId) return m.name;
    }
    return '?';
  }

  int get myBalance => balances[me] ?? 0;
}

class ExpenseInput {
  const ExpenseInput({
    required this.id,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.mode,
    required this.items,
    required this.category,
  });

  /// Client-made UUID, so retrying a save never creates two expenses.
  final String id;
  final String title;
  final int amount;
  final String paidBy;
  final SplitMode mode;
  final List<SplitItem> items;
  final String category;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'paidBy': paidBy,
    'mode': mode.name,
    'items': [for (final i in items) i.toJson()],
    'category': category,
  };
}
