// What the API sends back. Field names match apps/web/lib/api.ts and the NestJS controllers.
// Each model keeps the JSON it came from, so the offline cache can store it as it is.
import '../core/extras.dart';
import '../core/types.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime _date(Object? v) =>
    DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();
DateTime? _dateOrNull(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
List<String> _strings(Object? v) =>
    (v as List<dynamic>? ?? const []).cast<String>();
List<PayTo> _payTo(Object? v) => [for (final p in _list(v)) PayTo.fromJson(p)];

class Me {
  const Me({
    required this.id,
    required this.name,
    required this.locale,
    this.payTo = const [],
  });
  final String id;
  final String name;
  final String locale;
  final List<PayTo> payTo;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    name: j['name'] as String,
    locale: j['locale'] as String? ?? 'en',
    payTo: _payTo(j['payTo']),
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'locale': locale,
    'payTo': [for (final p in payTo) p.toJson()],
  };
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
    this.json = const {},
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
  final Map<String, dynamic> json;

  factory GroupSummary.fromJson(Map<String, dynamic> j) => GroupSummary(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: j['emoji'] as String? ?? '',
    currency: j['currency'] as String,
    version: _int(j['version']),
    updatedAt: _date(j['updatedAt']),
    memberNames: _strings(j['memberNames']),
    total: _int(j['total']),
    myBalance: _int(j['myBalance']),
    json: j,
  );
}

class Member {
  const Member({
    required this.id,
    required this.name,
    required this.claimed,
    required this.isMe,
    this.payTo = const [],
  });
  final String id;
  final String name;
  final bool claimed;
  final bool isMe;

  /// How this person gets paid, if they shared it.
  final List<PayTo> payTo;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    id: j['id'] as String,
    name: j['name'] as String,
    claimed: j['claimed'] as bool? ?? false,
    isMe: j['isMe'] as bool? ?? false,
    payTo: _payTo(j['payTo']),
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
    this.pending = false,
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

  /// Saved on this device and waiting to sync.
  final bool pending;

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
    pending: j['pending'] as bool? ?? false,
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

/// One round of a money circle (جمعية): who takes the pot, when, who has paid in and who is late.
class CircleRound {
  const CircleRound({
    required this.round,
    required this.receiver,
    required this.dueOn,
    required this.paid,
    required this.late,
  });
  final int round;
  final String receiver;

  /// YYYY-MM-DD.
  final String dueOn;
  final List<String> paid;
  final List<String> late;

  factory CircleRound.fromJson(Map<String, dynamic> j) => CircleRound(
    round: _int(j['round']),
    receiver: j['receiver'] as String,
    dueOn: j['dueOn'] as String? ?? '',
    paid: _strings(j['paid']),
    late: _strings(j['late']),
  );
}

class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.amount,
    required this.every,
    required this.startOn,
    required this.turns,
    required this.pot,
    required this.status,
    required this.current,
    required this.rounds,
  });
  final String id;
  final String name;

  /// What each person pays in every round, in minor units of the group currency.
  final int amount;

  /// 'week' or 'month'.
  final String every;
  final String startOn;
  final List<String> turns;
  final int pot;

  /// 'upcoming', 'running' or 'done'.
  final String status;
  final int? current;
  final List<CircleRound> rounds;

  CircleRound? get currentRound => current == null ? null : rounds[current!];

  factory Circle.fromJson(Map<String, dynamic> j) => Circle(
    id: j['id'] as String,
    name: j['name'] as String,
    amount: _int(j['amount']),
    every: j['every'] as String? ?? 'month',
    startOn: j['startOn'] as String? ?? '',
    turns: _strings(j['turns']),
    pot: _int(j['pot']),
    status: j['status'] as String? ?? 'running',
    current: (j['current'] as num?)?.toInt(),
    rounds: [for (final r in _list(j['rounds'])) CircleRound.fromJson(r)],
  );
}

class RecurringBill {
  const RecurringBill({
    required this.id,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.category,
    required this.every,
    required this.nextAt,
  });
  final String id;
  final String title;
  final int amount;
  final String paidBy;
  final String category;
  final String every;
  final DateTime nextAt;

  factory RecurringBill.fromJson(Map<String, dynamic> j) => RecurringBill(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    amount: _int(j['amount']),
    paidBy: j['paidBy'] as String? ?? '',
    category: j['category'] as String? ?? 'other',
    every: j['every'] as String? ?? 'month',
    nextAt: _date(j['nextAt']),
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
    this.circles = const [],
    this.recurring = const [],
    this.remindEvery = 'off',
    this.tripPassUntil,
    this.json = const {},
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
  final List<Circle> circles;
  final List<RecurringBill> recurring;

  /// 'off' or 'week'.
  final String remindEvery;
  final DateTime? tripPassUntil;

  /// The JSON this came from, for the offline cache.
  final Map<String, dynamic> json;

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
    circles: [for (final c in _list(j['circles'])) Circle.fromJson(c)],
    recurring: [
      for (final r in _list(j['recurring'])) RecurringBill.fromJson(r),
    ],
    remindEvery: j['remindEvery'] as String? ?? 'off',
    tripPassUntil: _dateOrNull(j['tripPassUntil']),
    json: j,
  );

  String nameOf(String memberId) {
    for (final m in members) {
      if (m.id == memberId) return m.name;
    }
    return '?';
  }

  Member? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  int get myBalance => balances[me] ?? 0;

  bool get tripPass =>
      tripPassUntil != null && tripPassUntil!.isAfter(DateTime.now());

  GroupLike get core => GroupLike(
    currency: currency,
    memberIds: [for (final m in members) m.id],
    expenses: [for (final e in expenses) e.core],
    payments: [
      for (final p in payments)
        PaymentLike(from: p.from, to: p.to, amount: p.amount),
    ],
  );
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
    this.currency,
    this.rate,
  });

  /// Client-made UUID, so retrying a save never creates two expenses.
  final String id;
  final String title;
  final int amount;
  final String paidBy;
  final SplitMode mode;
  final List<SplitItem> items;
  final String category;

  /// Only when it was paid in another currency than the group's.
  final String? currency;
  final double? rate;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'paidBy': paidBy,
    'mode': mode.name,
    'items': [for (final i in items) i.toJson()],
    'category': category,
    'currency': ?currency,
    'rate': ?rate,
  };

  factory ExpenseInput.fromJson(Map<String, dynamic> j) => ExpenseInput(
    id: j['id'] as String,
    title: j['title'] as String,
    amount: _int(j['amount']),
    paidBy: j['paidBy'] as String,
    mode: SplitMode.parse(j['mode'] as String? ?? 'equal'),
    items: [
      for (final i in _list(j['items']))
        SplitItem(i['memberId'] as String, _int(i['value'])),
    ],
    category: j['category'] as String? ?? 'other',
    currency: j['currency'] as String?,
    rate: (j['rate'] as num?)?.toDouble(),
  );
}

/// What the person has bought. Plus includes every look.
class Plan {
  const Plan({
    this.plus = false,
    this.plusUntil,
    this.tripPasses = const {},
    this.looks = const [],
  });
  final bool plus;
  final DateTime? plusUntil;

  /// Group id → until when.
  final Map<String, DateTime> tripPasses;

  /// Product ids, like nussnuss.look.night.
  final List<String> looks;

  static const free = Plan();

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
    plus: j['plus'] as bool? ?? false,
    plusUntil: _dateOrNull(j['plusUntil']),
    tripPasses: {
      for (final t in _list(j['tripPasses']))
        t['groupId'] as String: _date(t['until']),
    },
    looks: _strings(j['looks']),
  );

  bool ownsLook(String look) =>
      look == 'default' || plus || looks.contains('nussnuss.look.$look');
}

class Identity {
  const Identity(this.provider, this.email);
  final String provider;
  final String? email;
}

class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.device,
    required this.lastSeenAt,
    required this.current,
  });
  final String id;
  final String? device;
  final DateTime lastSeenAt;
  final bool current;
}

/// What protects the account, for Settings.
class Security {
  const Security({
    required this.recoveryCode,
    required this.recoveryCreatedAt,
    required this.identities,
    required this.passkeys,
    required this.sessions,
  });
  final bool recoveryCode;
  final DateTime? recoveryCreatedAt;
  final List<Identity> identities;
  final int passkeys;
  final List<DeviceSession> sessions;

  bool get safe => recoveryCode || passkeys > 0 || identities.isNotEmpty;

  factory Security.fromJson(Map<String, dynamic> j) => Security(
    recoveryCode: j['recoveryCode'] as bool? ?? false,
    recoveryCreatedAt: _dateOrNull(j['recoveryCreatedAt']),
    identities: [
      for (final i in _list(j['identities']))
        Identity(i['provider'] as String, i['email'] as String?),
    ],
    passkeys: _list(j['passkeys']).length,
    sessions: [
      for (final d in _list(j['sessions']))
        DeviceSession(
          id: d['id'] as String,
          device: d['device'] as String?,
          lastSeenAt: _date(d['lastSeenAt']),
          current: d['current'] as bool? ?? false,
        ),
    ],
  );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.groupId,
    required this.data,
    required this.createdAt,
    required this.read,
  });
  final String id;
  final String kind;
  final String? groupId;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final bool read;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? '',
    groupId: j['groupId'] as String?,
    data: (j['data'] as Map<String, dynamic>?) ?? const {},
    createdAt: _date(j['createdAt']),
    read: j['read'] as bool? ?? false,
  );
}
