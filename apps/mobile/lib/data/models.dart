// What the API sends back. Field names match apps/web/lib/api.ts and the NestJS controllers.
// Each model keeps the JSON it came from, so the offline cache can store it as it is.
import '../core/extras.dart';
import '../core/identity.dart';
import '../core/types.dart';

export '../core/identity.dart' show AvatarLook, Cover;

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
    this.avatar,
  });
  final String id;
  final String name;
  final String locale;
  final List<PayTo> payTo;

  /// How friends see me. Older servers send none: the initial on the tone of the name.
  final AvatarLook? avatar;

  AvatarLook get look => avatar ?? AvatarLook.forName(name);

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    name: j['name'] as String,
    locale: j['locale'] as String? ?? 'en',
    payTo: _payTo(j['payTo']),
    avatar: AvatarLook.fromJson(j['avatar'], name: j['name'] as String),
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'locale': locale,
    'payTo': [for (final p in payTo) p.toJson()],
    if (avatar != null) 'avatar': avatar!.toJson(),
  };
}

/// Someone as a list shows them: a name, whether it is me, and how they look.
class Who {
  const Who({required this.name, this.me = false, AvatarLook? avatar})
    : _avatar = avatar;
  final String name;
  final bool me;
  final AvatarLook? _avatar;

  AvatarLook get avatar => _avatar ?? AvatarLook.forName(name);

  static Who? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final name = j['name'] as String? ?? '';
    return Who(
      name: name,
      me: j['me'] as bool? ?? false,
      avatar: AvatarLook.fromJson(j['avatar'], name: name),
    );
  }
}

/// An amount in one currency (minor units).
class Money {
  const Money(this.currency, this.amount);
  final String currency;
  final int amount;

  factory Money.fromJson(Map<String, dynamic> j) =>
      Money(j['currency'] as String, _int(j['amount']));

  static List<Money> list(Object? v) => [
    for (final m in _list(v)) Money.fromJson(m),
  ];
}

/// A group in a list elsewhere (Home, a person, an activity row).
class GroupBrief {
  const GroupBrief({
    required this.id,
    required this.name,
    required this.emoji,
    required this.currency,
    this.coverKey,
  });
  final String id;
  final String name;
  final String emoji;
  final String currency;
  final String? coverKey;

  Cover get cover => groupCover(cover: coverKey, emoji: emoji);

  factory GroupBrief.fromJson(Map<String, dynamic> j) => GroupBrief(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    emoji: j['emoji'] as String? ?? '',
    currency: j['currency'] as String? ?? 'AED',
    coverKey: j['cover'] as String?,
  );
}

/// What last happened in a group, for its card on Home.
class LastActivity {
  const LastActivity({
    required this.kind,
    required this.at,
    this.who,
    this.title = '',
    this.from,
    this.to,
  });

  /// 'expense' or 'payment'.
  final String kind;
  final DateTime at;
  final Who? who;
  final String title;
  final Who? from;
  final Who? to;

  static LastActivity? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    return LastActivity(
      kind: j['kind'] as String? ?? 'expense',
      at: _date(j['at']),
      who: Who.fromJson(j['who']),
      title: j['title'] as String? ?? '',
      from: Who.fromJson(j['from']),
      to: Who.fromJson(j['to']),
    );
  }
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
    this.coverKey,
    this.members = const [],
    this.expenseCount,
    this.settled = false,
    this.lastActivity,
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
  final String? coverKey;

  /// The first few members, with how they look.
  final List<Who> members;
  final int? expenseCount;

  /// Everyone is even and something was spent: Home folds these away.
  final bool settled;
  final LastActivity? lastActivity;
  final Map<String, dynamic> json;

  Cover get cover => groupCover(cover: coverKey, emoji: emoji);

  GroupBrief get brief => GroupBrief(
    id: id,
    name: name,
    emoji: emoji,
    currency: currency,
    coverKey: coverKey,
  );

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
    coverKey: j['cover'] as String?,
    members: [for (final m in _list(j['members'])) ?Who.fromJson(m)],
    expenseCount: (j['expenseCount'] as num?)?.toInt(),
    settled: j['settled'] as bool? ?? false,
    lastActivity: LastActivity.fromJson(j['lastActivity']),
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
    AvatarLook? avatar,
  }) : _avatar = avatar;
  final String id;
  final String name;
  final bool claimed;
  final bool isMe;

  /// How this person gets paid, if they shared it.
  final List<PayTo> payTo;
  final AvatarLook? _avatar;

  AvatarLook get avatar => _avatar ?? AvatarLook.forName(name);

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    id: j['id'] as String,
    name: j['name'] as String,
    claimed: j['claimed'] as bool? ?? false,
    isMe: j['isMe'] as bool? ?? false,
    payTo: _payTo(j['payTo']),
    avatar: AvatarLook.fromJson(j['avatar'], name: j['name'] as String),
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
    this.coverKey,
    this.json = const {},
  });

  final String id;
  final String name;
  final String emoji;
  final String currency;
  final int version;
  final String? coverKey;

  Cover get cover => groupCover(cover: coverKey, emoji: emoji);

  GroupBrief get brief => GroupBrief(
    id: id,
    name: name,
    emoji: emoji,
    currency: currency,
    coverKey: coverKey,
  );

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
    coverKey: j['cover'] as String?,
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

/// Home: where I stand overall, the one thing worth doing next, and the people I split with.
class Overview {
  const Overview({
    required this.totals,
    required this.groups,
    required this.next,
    required this.people,
    required this.unread,
    this.json = const {},
  });

  /// My balance per currency, nonzero, biggest first (+ I get back).
  final List<Money> totals;
  final int groups;
  final NextStep? next;
  final List<PersonSummary> people;
  final int unread;
  final Map<String, dynamic> json;

  factory Overview.fromJson(Map<String, dynamic> j) => Overview(
    totals: Money.list(j['totals']),
    groups: _int(j['groups']),
    next: NextStep.fromJson(j['next']),
    people: [for (final p in _list(j['people'])) PersonSummary.fromJson(p)],
    unread: _int(j['unread']),
    json: j,
  );
}

/// pay / collect: one person and one group; first / invite: a group to get going.
class NextStep {
  const NextStep({
    required this.kind,
    required this.group,
    this.personKey,
    this.person,
    this.amount = 0,
    this.currency = '',
    this.memberId,
    this.payTo = const [],
  });
  final String kind;
  final GroupBrief group;
  final String? personKey;
  final Who? person;
  final int amount;
  final String currency;
  final String? memberId;
  final List<PayTo> payTo;

  static NextStep? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final p = j['person'];
    return NextStep(
      kind: j['kind'] as String? ?? 'first',
      group: GroupBrief.fromJson(j['group'] as Map<String, dynamic>),
      personKey: p is Map<String, dynamic> ? p['key'] as String? : null,
      person: Who.fromJson(p),
      amount: _int(j['amount']),
      currency: j['currency'] as String? ?? '',
      memberId: j['memberId'] as String?,
      payTo: _payTo(j['payTo']),
    );
  }
}

/// Someone on the people strip: what we owe each other per currency (+ they owe me).
class PersonSummary {
  const PersonSummary({
    required this.key,
    required this.name,
    required this.avatar,
    required this.balances,
    required this.groups,
  });
  final String key;
  final String name;
  final AvatarLook avatar;
  final List<Money> balances;
  final int groups;

  factory PersonSummary.fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String? ?? '';
    return PersonSummary(
      key: j['key'] as String,
      name: name,
      avatar:
          AvatarLook.fromJson(j['avatar'], name: name) ??
          AvatarLook.forName(name),
      balances: Money.list(j['balances']),
      groups: _int(j['groups']),
    );
  }
}

class PersonGroup {
  const PersonGroup({
    required this.group,
    required this.amount,
    required this.memberId,
    required this.me,
    this.payTo = const [],
  });
  final GroupBrief group;

  /// + they owe me, − I owe them, in the group currency.
  final int amount;
  final String memberId;
  final String me;
  final List<PayTo> payTo;

  factory PersonGroup.fromJson(Map<String, dynamic> j) => PersonGroup(
    group: GroupBrief.fromJson(j),
    amount: _int(j['amount']),
    memberId: j['memberId'] as String,
    me: j['me'] as String? ?? '',
    payTo: _payTo(j['payTo']),
  );
}

/// An expense one of us paid that the other was part of.
class SharedExpense {
  const SharedExpense({
    required this.id,
    required this.group,
    required this.title,
    required this.category,
    required this.currency,
    required this.amount,
    required this.paidByMe,
    required this.at,
  });
  final String id;
  final GroupBrief group;
  final String title;
  final String category;
  final String currency;

  /// What it moved between us: + they owe me for it, − I owe them.
  final int amount;
  final bool paidByMe;
  final DateTime at;

  factory SharedExpense.fromJson(Map<String, dynamic> j) => SharedExpense(
    id: j['id'] as String,
    group: GroupBrief.fromJson(j['group'] as Map<String, dynamic>),
    title: j['title'] as String? ?? '',
    category: j['category'] as String? ?? 'other',
    currency: j['currency'] as String? ?? '',
    amount: _int(j['amount']),
    paidByMe: j['paidByMe'] as bool? ?? false,
    at: _date(j['at']),
  );
}

/// One person across every group we share.
class PersonDetail {
  const PersonDetail({
    required this.key,
    required this.name,
    required this.avatar,
    required this.claimed,
    required this.balances,
    required this.groups,
    required this.shared,
  });
  final String key;
  final String name;
  final AvatarLook avatar;
  final bool claimed;
  final List<Money> balances;
  final List<PersonGroup> groups;
  final List<SharedExpense> shared;

  factory PersonDetail.fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String? ?? '';
    return PersonDetail(
      key: j['key'] as String,
      name: name,
      avatar:
          AvatarLook.fromJson(j['avatar'], name: name) ??
          AvatarLook.forName(name),
      claimed: j['claimed'] as bool? ?? false,
      balances: Money.list(j['balances']),
      groups: [for (final g in _list(j['groups'])) PersonGroup.fromJson(g)],
      shared: [for (final e in _list(j['shared'])) SharedExpense.fromJson(e)],
    );
  }
}

/// Something that happened in one of my groups.
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.op,
    required this.at,
    required this.group,
    required this.unread,
    required this.kind,
    this.actor,
    this.expenseId,
    this.title = '',
    this.amount = 0,
    this.category = 'other',
    this.paidBy,
    this.impact = 0,
    this.paymentId,
    this.from,
    this.to,
  });
  final String id;

  /// 'create' or 'update'.
  final String op;
  final DateTime at;
  final GroupBrief group;
  final bool unread;

  /// 'expense' or 'payment'.
  final String kind;
  final Who? actor;
  final String? expenseId;
  final String title;

  /// In the group currency.
  final int amount;
  final String category;
  final Who? paidBy;

  /// My net in the group currency: + it lent money for me, − what it cost me.
  final int impact;
  final String? paymentId;
  final Who? from;
  final Who? to;

  factory ActivityItem.fromJson(Map<String, dynamic> j) {
    final e = j['expense'] as Map<String, dynamic>?;
    final p = j['payment'] as Map<String, dynamic>?;
    return ActivityItem(
      id: '${j['id']}',
      op: j['op'] as String? ?? 'create',
      at: _date(j['at']),
      group: GroupBrief.fromJson(j['group'] as Map<String, dynamic>),
      unread: j['unread'] as bool? ?? false,
      kind: j['kind'] as String? ?? 'expense',
      actor: Who.fromJson(j['actor']),
      expenseId: e?['id'] as String?,
      title: e?['title'] as String? ?? '',
      amount: _int(e?['amount'] ?? p?['amount']),
      category: e?['category'] as String? ?? 'other',
      paidBy: Who.fromJson(e?['paidBy']),
      impact: _int(e?['impact']),
      paymentId: p?['id'] as String?,
      from: Who.fromJson(p?['from']),
      to: Who.fromJson(p?['to']),
    );
  }
}

class ActivityPage {
  const ActivityPage({required this.items, this.next, this.unread = 0});
  final List<ActivityItem> items;
  final String? next;
  final int unread;

  factory ActivityPage.fromJson(Map<String, dynamic> j) => ActivityPage(
    items: [for (final i in _list(j['items'])) ActivityItem.fromJson(i)],
    next: j['next'] == null ? null : '${j['next']}',
    unread: _int(j['unread']),
  );
}
