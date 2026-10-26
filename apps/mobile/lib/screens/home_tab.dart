import 'dart:async';

import 'package:flutter/material.dart';

import '../core/extras.dart';
import '../core/types.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/coin.dart';
import '../design/glass.dart';
import '../design/motion.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import '../format.dart';
import '../l10n/strings.g.dart';
import 'common.dart';
import 'group_screen.dart';
import 'group_sheets.dart';
import 'notifications.dart';
import 'people.dart';
import 'summary_card.dart' show originOf;

/// Home: where you stand overall, the one thing worth doing next, the people you split with and
/// your groups (the settled ones folded away). The copy on this device shows at once; the server's
/// answer replaces it.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<GroupSummary>? _groups;
  Overview? _overview;
  String? _error;
  int _seen = -1;

  /// Unread reminders, for the bell.
  int _bell = 0;

  /// True while the list first appears: its rows arrive one after another.
  bool _fresh = true;
  bool _showSettled = false;

  /// The next step the person closed; a different one shows again.
  String? _dismissed;
  bool _timed = false;

  // Search: groups by name and members, people by name, expenses by title in the groups kept on
  // this device.
  final _q = TextEditingController();
  final _focus = FocusNode();
  List<GroupDetail> _details = const [];
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    SessionScope.read(context).recentSearches().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rev = SessionScope.of(context).revision;
    if (rev != _seen) {
      _seen = rev;
      _details = const [];
      _load();
    }
  }

  Future<void> _load() async {
    final session = SessionScope.read(context);
    if (_groups == null || _overview == null) {
      final cached = await session.repo.cachedGroups();
      final overview = await session.repo.cachedOverview();
      if (mounted) {
        setState(() {
          _groups ??= cached;
          _overview ??= overview;
        });
      }
    }
    await Future.wait([_loadGroups(), _loadOverview()]);
    unawaited(_countBell());
  }

  Future<void> _loadGroups() async {
    final session = SessionScope.read(context);
    try {
      final list = await session.repo.groups();
      if (!mounted) return;
      setState(() {
        _groups = list;
        _error = null;
        _details = const [];
      });
      if (_query.isNotEmpty) unawaited(_loadDetails());
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.offline ? session.s.offline : e.message;
          _groups ??= e.offline ? null : const [];
        });
      }
    }
  }

  Future<void> _loadOverview() async {
    final session = SessionScope.read(context);
    try {
      final o = await session.repo.overview();
      if (!mounted) return;
      setState(() => _overview = o);
      session.unread.value = o.unread;
    } on ApiException {
      // Offline (or an older server): the totals come from the groups list instead.
    }
  }

  Future<void> _countBell() async {
    try {
      final list = await SessionScope.read(context).api.notifications();
      if (mounted) setState(() => _bell = list.where((n) => !n.read).length);
    } on ApiException {
      // The bell just stays quiet.
    }
  }

  String get _query => _q.text.trim().toLowerCase();

  Future<void> _loadDetails() async {
    final groups = _groups;
    if (groups == null || _details.isNotEmpty) return;
    final repo = SessionScope.read(context).repo;
    final all = <GroupDetail>[];
    for (final g in groups) {
      final d = await repo.cachedGroup(g.id);
      if (d != null) all.add(d);
    }
    if (mounted) setState(() => _details = all);
  }

  void _onQuery() {
    setState(() {});
    if (_query.isNotEmpty) unawaited(_loadDetails());
  }

  Future<void> _remember() async {
    if (_q.text.trim().isEmpty) return;
    final r = await SessionScope.read(context).rememberSearch(_q.text);
    if (mounted) setState(() => _recent = r);
  }

  /// My balance per currency from the groups list, biggest first: what the overview says, worked
  /// out here when there is no overview (offline before the first one, or an older server).
  List<Money> get _totals {
    final o = _overview;
    if (o != null) return o.totals;
    final by = <String, int>{};
    for (final g in _groups ?? const <GroupSummary>[]) {
      by[g.currency] = (by[g.currency] ?? 0) + g.myBalance;
    }
    return [
      for (final e in by.entries)
        if (e.value != 0) Money(e.key, e.value),
    ]..sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
  }

  Future<void> _openGroup(String id, {Rect? origin, bool add = false}) async {
    await Navigator.of(context).push(
      NNPageRoute<void>(
        origin: origin,
        builder: (_) => GroupScreen(groupId: id, addOnOpen: add),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openPerson(
    String key,
    String name,
    AvatarLook look, {
    Rect? origin,
  }) async {
    await Navigator.of(context).push(
      NNPageRoute<void>(
        origin: origin,
        builder: (_) => PersonScreen(personKey: key, name: name, look: look),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _seeAll(List<PersonSummary> people) async {
    await Navigator.of(
      context,
    ).push(NNPageRoute<void>(builder: (_) => PeopleScreen(people: people)));
    if (mounted) await _load();
  }

  Future<GroupDetail> _detail(String id) async {
    final repo = SessionScope.read(context).repo;
    return await repo.cachedGroup(id) ?? await repo.group(id);
  }

  Future<void> _markNextPaid(NextStep n) async {
    final session = SessionScope.read(context);
    final s = session.s;
    final other = n.memberId;
    if (other == null) return;
    try {
      final g = await _detail(n.group.id);
      final t = n.kind == 'pay'
          ? Transfer(from: g.me, to: other, amount: n.amount)
          : Transfer(from: other, to: g.me, amount: n.amount);
      final r = await session.repo.pay(g, t);
      haptic(Haptic.success);
      session.timings.finish('settle');
      session.touch();
      if (!mounted) return;
      showToast(
        context,
        r.queued ? '${s.paidRecorded}. ${s.savedOffline}' : s.paidRecorded,
        key: const ValueKey('toast'),
        check: true,
        actionLabel: s.undo,
        onAction: () async {
          try {
            if (r.queued) {
              await session.repo.cancelPending(r.detail, r.id);
            } else {
              await session.repo.took(await session.api.unpay(r.id));
            }
            session.touch();
          } on ApiException catch (e) {
            if (mounted) setState(() => _error = e.message);
          }
        },
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.offline ? s.offline : e.message);
    }
  }

  Future<void> _payNext(NextStep n) async {
    if (n.payTo.isEmpty) return;
    final PayTo? way = n.payTo.length == 1
        ? n.payTo.first
        : await showNNSheet<PayTo>(
            context,
            key: const ValueKey('pay-ways'),
            title: context.s.fill(context.s.payName, {
              'name': n.person?.name ?? '',
            }),
            builder: (ctx) => Wrap(
              spacing: NNSpace.xs,
              runSpacing: NNSpace.xs,
              children: [
                for (var i = 0; i < n.payTo.length; i++)
                  NNChip(
                    key: ValueKey('pay-way-$i'),
                    label: ctx.s.fill(ctx.s.payWith, {
                      'method': payMethodName(ctx.s, n.payTo[i]),
                    }),
                    icon: Icons.account_balance_wallet_outlined,
                    selected: false,
                    onTap: () => Navigator.of(ctx).pop(n.payTo[i]),
                  ),
              ],
            ),
          );
    if (way == null || !mounted) return;
    await payWithMethod(context, way, amount: n.amount, currency: n.currency);
  }

  Future<void> _remindNext(NextStep n) async {
    final session = SessionScope.read(context);
    final s = session.s;
    await sendReminder(
      session,
      s.fill(s.remindMessage, {
        'name': n.person?.name ?? '',
        'amount': money(n.amount, n.currency, s.lang),
        'group': n.group.name,
      }),
    );
  }

  Future<void> _inviteNext(NextStep n) async {
    try {
      final g = await _detail(n.group.id);
      if (mounted) await showShareSheet(context, g);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? context.s.offline : e.message);
      }
    }
  }

  Future<void> _startGroup(Rect? origin) async {
    final g = await showNewGroupSheet(context, origin: origin);
    if (g == null || !mounted) return;
    SessionScope.read(context).touch();
    unawaited(_openGroup(g.id));
  }

  Widget _search() {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Glass(
      child: SearchFieldBody(
        controller: _q,
        focusNode: _focus,
        hint: s.searchGroups,
        semibold: true,
        onChanged: _onQuery,
        onSubmitted: () {
          final (groups, people, expenses) = _found();
          if (groups.isNotEmpty || people.isNotEmpty || expenses.isNotEmpty) {
            _remember();
          }
        },
        fieldKey: const ValueKey('search'),
        clearKey: const ValueKey('search-clear'),
        ring: p.accent,
      ),
    );
  }

  /// Groups whose name or people match, people whose name does, and expenses whose title does
  /// (at most 30).
  (List<GroupSummary>, List<PersonSummary>, List<(Expense, GroupDetail)>)
  _found() {
    final k = _query;
    final groups = _groups ?? const <GroupSummary>[];
    bool hit(String x) => x.toLowerCase().contains(k);
    return (
      [
        for (final g in groups)
          if (hit(g.name) || g.memberNames.any(hit)) g,
      ],
      [
        for (final p in _overview?.people ?? const <PersonSummary>[])
          if (hit(p.name)) p,
      ],
      [
        for (final d in _details)
          for (final e in d.expenses)
            if (hit(e.title)) (e, d),
      ].take(30).toList(),
    );
  }

  List<Widget> _results() {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final (groups, people, expenses) = _found();
    if (groups.isEmpty && people.isEmpty && expenses.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            key: const ValueKey('no-results'),
            padding: const EdgeInsets.symmetric(vertical: NNSpace.xl),
            child: Text(
              s.fill(s.noResults, {'q': _q.text.trim()}),
              textAlign: TextAlign.center,
              style: NNType.subhead.copyWith(color: p.text2),
            ),
          ),
        ),
      ];
    }
    return [
      if (groups.isNotEmpty)
        SliverToBoxAdapter(
          child: RowsCard(
            children: [
              for (var i = 0; i < groups.length; i++)
                _row(groups[i], i, remember: true),
            ],
          ),
        ),
      if (people.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionLabel(s.people)),
        SliverToBoxAdapter(
          child: RowsCard(
            children: [
              for (final x in people)
                PersonRow(
                  person: x,
                  onTap: (origin) {
                    _remember();
                    _openPerson(x.key, x.name, x.avatar, origin: origin);
                  },
                ),
            ],
          ),
        ),
      ],
      if (expenses.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionLabel(s.searchExpenses)),
        SliverToBoxAdapter(
          child: RowsCard(
            children: [
              for (final (e, g) in expenses)
                _FoundExpense(
                  e: e,
                  group: g,
                  onTap: () {
                    _remember();
                    _openGroup(g.id);
                  },
                ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _row(GroupSummary g, int i, {bool remember = false}) => FadeIn(
    key: ValueKey('fade-${g.id}'),
    index: i,
    animate: _fresh,
    child: _GroupRow(
      g: g,
      onTap: (origin) {
        if (remember) _remember();
        _openGroup(g.id, origin: origin);
      },
    ),
  );

  Widget _bellButton() {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlassIconButton(
          key: const ValueKey('bell'),
          icon: _bell > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          label: _bell > 0 ? '${s.notifications}, $_bell' : s.notifications,
          onTap: () async {
            await showNotifications(context);
            if (mounted) setState(() => _bell = 0);
          },
        ),
        if (_bell > 0)
          PositionedDirectional(
            top: 6,
            end: 6,
            child: IgnorePointer(
              child: Container(
                width: 10,
                height: 10,
                decoration: ShapeDecoration(
                  shape: const CircleBorder(),
                  color: p.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    final groups = _groups;
    final overview = _overview;
    if (groups != null && _fresh) {
      // Rows built after this frame (while scrolling) just appear.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fresh = false);
    }
    final ready = groups != null && groups.isNotEmpty;
    if (ready && !_timed) {
      // find_balance: from app start to the overall balance on screen.
      _timed = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => session.timings.balanceShown(),
      );
    }
    final searching = _query.isNotEmpty;
    final showRecent =
        _focus.hasFocus && _q.text.trim().isEmpty && _recent.isNotEmpty;
    final open = [
      for (final g in groups ?? const <GroupSummary>[])
        if (!g.settled) g,
    ];
    final settled = [
      for (final g in groups ?? const <GroupSummary>[])
        if (g.settled) g,
    ];
    final next = overview?.next;
    final nextKey = next == null
        ? null
        : '${next.kind}:${next.group.id}:${next.personKey}:${next.amount}';
    final people = overview?.people ?? const <PersonSummary>[];
    final pending = session.repo.pending;
    final busy = groups == null
        ? 0
        : groups.where((g) => g.myBalance != 0).length;

    return NNPage(
      key: const ValueKey('groups'),
      title: s.tabHome,
      actions: [_bellButton()],
      onRefresh: _load,
      pinned: ready ? _search() : null,
      pinnedHeight: searchFieldHeight(context) + 14,
      slivers: [
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: NNSpace.sm),
              child: Text(
                _error!,
                style: NNType.footnote.copyWith(color: p.danger),
              ),
            ),
          ),
        if (showRecent)
          SliverToBoxAdapter(
            child: Padding(
              key: const ValueKey('recent-searches'),
              padding: const EdgeInsets.only(bottom: NNSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(s.recentSearches),
                  Wrap(
                    spacing: NNSpace.xs,
                    runSpacing: NNSpace.xs,
                    children: [
                      for (var i = 0; i < _recent.length; i++)
                        NNChip(
                          key: ValueKey('recent-$i'),
                          label: _recent[i],
                          icon: Icons.search_rounded,
                          selected: false,
                          onTap: () {
                            _q.text = _recent[i];
                            _onQuery();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (groups == null && _error == null)
          SliverToBoxAdapter(child: SkeletonRows(label: s.loading))
        else if (groups != null && groups.isEmpty)
          SliverToBoxAdapter(
            child: Column(
              children: [
                EmptyState(
                  title: s.noGroupsTitle,
                  body: s.noGroupsBody,
                  art: const Coin(size: 88),
                ),
                Builder(
                  builder: (ctx) => NNButton(
                    key: const ValueKey('start-group'),
                    label: s.startGroup,
                    icon: Icons.add_rounded,
                    onTap: () => _startGroup(originOf(ctx)),
                  ),
                ),
              ],
            ),
          )
        else if (groups != null && searching)
          ..._results()
        else if (groups != null) ...[
          SliverToBoxAdapter(
            child: _Overall(totals: _totals, groups: busy),
          ),
          if (pending > 0)
            SliverToBoxAdapter(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Waiting(count: pending),
              ),
            ),
          if (next != null && nextKey != _dismissed)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: NNSpace.lg),
                child: _NextStepCard(
                  next: next,
                  onDismiss: () => setState(() => _dismissed = nextKey),
                  onPay: () => _payNext(next),
                  onRemind: () => _remindNext(next),
                  onMarkPaid: () => _markNextPaid(next),
                  onAddFirst: () => _openGroup(next.group.id, add: true),
                  onInvite: () => _inviteNext(next),
                ),
              ),
            ),
          if (people.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _Heading(
                s.people,
                action: s.seeAll,
                actionKey: const ValueKey('see-all-people'),
                onAction: () => _seeAll(people),
              ),
            ),
            SliverToBoxAdapter(
              child: _PeopleStrip(
                people: people,
                onOpen: (x, origin) =>
                    _openPerson(x.key, x.name, x.avatar, origin: origin),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Builder(
              builder: (ctx) => _Heading(
                s.groups,
                action: s.newGroup,
                actionKey: const ValueKey('new-group'),
                onAction: () => _startGroup(originOf(ctx)),
              ),
            ),
          ),
          if (open.isNotEmpty)
            SliverToBoxAdapter(
              child: RowsCard(
                children: [
                  for (var i = 0; i < open.length; i++) _row(open[i], i),
                ],
              ),
            ),
          if (settled.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: NNSpace.md),
                child: _FoldButton(
                  key: const ValueKey('show-settled'),
                  label: _showSettled
                      ? s.hideSettled
                      : s.fill(s.showSettled, {'n': settled.length}),
                  open: _showSettled,
                  onTap: () => setState(() => _showSettled = !_showSettled),
                ),
              ),
            ),
            if (_showSettled)
              SliverToBoxAdapter(
                child: RowsCard(
                  muted: true,
                  children: [
                    for (final g in settled)
                      _SettledRow(
                        g: g,
                        onTap: (origin) => _openGroup(g.id, origin: origin),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// A section title with an optional link at the end ("See all").
class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.action, this.actionKey, this.onAction});
  final String text;
  final String? action;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: NNSpace.xxs,
        top: NNSpace.xl,
        bottom: NNSpace.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: NNType.title3.copyWith(color: p.text)),
            ),
          ),
          if (action != null)
            Pressable(
              key: actionKey,
              onTap: onAction,
              semanticLabel: action,
              excludeChildSemantics: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: touchTarget(context),
                  minWidth: touchTarget(context),
                ),
                child: Center(
                  child: Text(
                    action!,
                    style: NNType.subhead.copyWith(
                      color: p.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Overall, you get back" and the first currency big; other currencies as "and OMR 12.500".
class _Overall extends StatelessWidget {
  const _Overall({required this.totals, required this.groups});
  final List<Money> totals;

  /// How many groups the balance comes from.
  final int groups;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    if (totals.isEmpty) {
      return Semantics(
        container: true,
        child: Padding(
          key: const ValueKey('overall-even'),
          padding: const EdgeInsets.only(top: NNSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.overallEven, style: NNType.title1.copyWith(color: p.text)),
              const SizedBox(height: NNSpace.xxs),
              Text(
                s.overallEvenBody,
                style: NNType.subhead.copyWith(color: p.text2),
              ),
            ],
          ),
        ),
      );
    }
    final first = totals.first;
    final color = balanceColor(p, first.amount);
    final others = totals.skip(1).toList();
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: NNSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first.amount > 0 ? s.overallBack : s.overallOwe,
              style: NNType.subhead.copyWith(
                color: p.text2,
                fontWeight: FontWeight.w500,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: RollingText(
                money(first.amount.abs(), first.currency, s.lang),
                key: const ValueKey('overall-balance'),
                style: NNType.amountHero.copyWith(
                  fontSize: 52,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: NNSpace.xxs),
            Wrap(
              spacing: NNSpace.xs,
              runSpacing: NNSpace.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (groups > 0)
                  Text(
                    groups == 1
                        ? s.acrossOne
                        : s.fill(s.acrossN, {'n': groups}),
                    style: NNType.footnote.copyWith(color: p.text2),
                  ),
                for (final m in others)
                  Container(
                    key: ValueKey('overall-${m.currency}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: p.accentSoft,
                    ),
                    child: Text(
                      s.fill(s.andAmount, {
                        // Only an amount going the other way carries a sign.
                        'amount': (m.amount > 0) == (first.amount > 0)
                            ? money(m.amount.abs(), m.currency, s.lang)
                            : signedMoney(m.amount, m.currency, s),
                      }),
                      style: NNType.footnote.copyWith(
                        color: p.onAccentSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What is waiting to sync, on Home too.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('pending-home'),
        margin: const EdgeInsets.only(top: NNSpace.sm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: p.accentSoft,
          borderRadius: BorderRadius.circular(NNRadius.row),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 16, color: p.onAccentSoft),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                s.fill(s.waitingHome, {'n': count}),
                style: NNType.footnote.copyWith(
                  color: p.onAccentSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one thing worth doing next: pay what you owe, collect what you're owed, or get a group
/// going. It can be closed; a different step comes back.
class _NextStepCard extends StatelessWidget {
  const _NextStepCard({
    required this.next,
    required this.onDismiss,
    required this.onPay,
    required this.onRemind,
    required this.onMarkPaid,
    required this.onAddFirst,
    required this.onInvite,
  });
  final NextStep next;
  final VoidCallback onDismiss;
  final VoidCallback onPay;
  final VoidCallback onRemind;
  final VoidCallback onMarkPaid;
  final VoidCallback onAddFirst;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final n = next;
    final name = n.person?.name ?? '';
    final amount = money(n.amount, n.currency, s.lang);
    final (String line, Widget lead) = switch (n.kind) {
      'pay' => (
        s.fill(s.nextPay, {'name': name, 'amount': amount}),
        Avatar(name: name, look: n.person?.avatar, size: 44),
      ),
      'collect' => (
        s.fill(s.nextCollect, {'name': name, 'amount': amount}),
        Avatar(name: name, look: n.person?.avatar, size: 44),
      ),
      'invite' => (
        s.fill(s.nextInvite, {'group': n.group.name}),
        CoverTile(cover: n.group.cover, size: 44),
      ),
      _ => (
        s.fill(s.nextFirst, {'group': n.group.name}),
        CoverTile(cover: n.group.cover, size: 44),
      ),
    };
    final isMoney = n.kind == 'pay' || n.kind == 'collect';
    final actions = <Widget>[
      if (n.kind == 'pay' && n.payTo.isNotEmpty)
        NNButton(
          key: const ValueKey('next-pay'),
          label: s.fill(s.payName, {'name': name}),
          icon: Icons.account_balance_wallet_outlined,
          kind: ButtonKind.tinted,
          expand: false,
          onTap: onPay,
        ),
      if (n.kind == 'collect')
        NNButton(
          key: const ValueKey('next-remind'),
          label: s.fill(s.remindName, {'name': name}),
          icon: Icons.chat_bubble_outline_rounded,
          kind: ButtonKind.tinted,
          expand: false,
          onTap: onRemind,
        ),
      if (isMoney)
        _LinkButton(
          key: const ValueKey('next-mark-paid'),
          label: s.markPaid,
          onTap: onMarkPaid,
        ),
      if (n.kind == 'first')
        NNButton(
          key: const ValueKey('next-add'),
          label: s.addFirst,
          icon: Icons.add_rounded,
          kind: ButtonKind.tinted,
          expand: false,
          onTap: onAddFirst,
        ),
      if (n.kind == 'invite')
        NNButton(
          key: const ValueKey('next-invite'),
          label: s.inviteFriends,
          icon: Icons.person_add_alt_1_rounded,
          kind: ButtonKind.tinted,
          expand: false,
          onTap: onInvite,
        ),
    ];
    return Semantics(
      container: true,
      child: NNCard(
        key: const ValueKey('next-step'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      s.nextStep,
                      style: NNType.footnote.copyWith(
                        color: p.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Pressable(
                  key: const ValueKey('next-dismiss'),
                  onTap: onDismiss,
                  semanticLabel: s.close,
                  excludeChildSemantics: true,
                  child: SizedBox.square(
                    dimension: touchTarget(context),
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          color: p.surface2,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: p.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                lead,
                const SizedBox(width: NNSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line,
                        key: const ValueKey('next-line'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.headline.copyWith(color: p.text),
                      ),
                      if (isMoney)
                        Text(
                          n.group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NNType.footnote.copyWith(color: p.text2),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: NNSpace.sm),
              Wrap(
                spacing: NNSpace.xs,
                runSpacing: NNSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A text button in the accent colour, at least a touch target tall.
class _LinkButton extends StatelessWidget {
  const _LinkButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: touchTarget(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NNSpace.sm),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: NNType.headline.copyWith(color: p.accent),
            ),
          ),
        ),
      ),
    );
  }
}

/// The people you split with, side by side: who owes whom shows as the ring and the amount.
class _PeopleStrip extends StatelessWidget {
  const _PeopleStrip({required this.people, required this.onOpen});
  final List<PersonSummary> people;
  final void Function(PersonSummary person, Rect? origin) onOpen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('people-strip'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final x in people)
            Builder(
              builder: (ctx) =>
                  _PersonChip(person: x, onTap: () => onOpen(x, originOf(ctx))),
            ),
        ],
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person, required this.onTap});
  final PersonSummary person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final first = person.balances.isEmpty ? null : person.balances.first;
    final signed = first?.amount ?? 0;
    final ring = signed > 0
        ? p.success
        : signed < 0
        ? p.accent
        : p.separator;
    final amount = first == null
        ? s.personEven
        : signedMoney(first.amount, first.currency, s);
    final words = first == null
        ? s.personEven
        : s.fill(signed > 0 ? s.owesYouX : s.youOweX, {
            'amount': amountsLine(person.balances, s),
          });
    final width = MediaQuery.textScalerOf(context).scale(72).clamp(72.0, 120.0);
    return Pressable(
      key: ValueKey('person-${person.key}'),
      onTap: onTap,
      semanticLabel: '${person.name}, $words',
      excludeChildSemantics: true,
      scale: 0.96,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NNSpace.xxs),
          child: Column(
            children: [
              Avatar(
                name: person.name,
                look: person.avatar,
                size: 48,
                ring: ring,
              ),
              const SizedBox(height: NNSpace.xxs),
              Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NNType.footnote.copyWith(
                  color: p.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  amount,
                  style: NNType.caption.copyWith(
                    color: signed > 0 ? p.success : p.text2,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group on Home: its cover, its name, what last happened, and where you stand in words.
class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.g, required this.onTap});
  final GroupSummary g;

  /// Gets the row's rectangle on screen, so the group can grow out of it.
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final b = g.myBalance;
    final label = b > 0 ? s.youAreOwed : (b < 0 ? s.youOwe : s.personEven);
    final amount = b == 0 ? '' : money(b.abs(), g.currency, s.lang);
    final line = lastLine(g, s);
    return Pressable(
      key: ValueKey('group-${g.id}'),
      onTap: () => onTap(originOf(context)),
      semanticLabel: [g.name, line, '$label $amount'.trim()].join(', '),
      excludeChildSemantics: true,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NNSpace.sm),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                CoverTile(cover: g.cover),
                const SizedBox(width: NNSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.headline.copyWith(color: p.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.footnote.copyWith(color: p.text2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NNSpace.xs),
                // The balance gives way to the name before anything overflows, at any text size.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.42),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.caption.copyWith(
                          color: b > 0 ? p.success : p.text2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (amount.isNotEmpty)
                        AmountText(
                          amount,
                          key: ValueKey('group-balance-${g.id}'),
                          style: NNType.headline.copyWith(
                            color: balanceColor(p, b),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Sara added Lunch · 2:05 PM": what last happened in a group, or who is in it.
String lastLine(GroupSummary g, NNStrings s) {
  final a = g.lastActivity;
  if (a == null) return g.memberNames.join(s.isRtl ? '، ' : ', ');
  String name(Who? w) => w == null ? '' : (w.me ? s.you : w.name);
  final what = a.kind == 'payment'
      ? s.fill(s.actPaidLine, {'from': name(a.from), 'to': name(a.to)})
      : a.who?.me == true
      ? s.fill(s.actYouAdded, {'title': a.title})
      : s.fill(s.actNameAdded, {'name': name(a.who), 'title': a.title});
  return '$what · ${whenLabel(a.at, s)}';
}

/// A settled group, quieter: a check, the name and when it was settled.
class _SettledRow extends StatelessWidget {
  const _SettledRow({required this.g, required this.onTap});
  final GroupSummary g;
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final when = s.fill(s.settledOn, {
      'date': dateLabel(g.lastActivity?.at ?? g.updatedAt, s),
    });
    return Pressable(
      key: ValueKey('group-${g.id}'),
      onTap: () => onTap(originOf(context)),
      semanticLabel: '${g.name}, $when',
      excludeChildSemantics: true,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Icon(Icons.check_circle_rounded, color: p.success),
              ),
              const SizedBox(width: NNSpace.sm),
              Expanded(
                child: Text(
                  g.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NNType.callout.copyWith(
                    color: p.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: NNSpace.xs),
              Flexible(
                child: Text(
                  when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NNType.footnote.copyWith(color: p.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Show settled groups (2)" / "Hide settled groups".
class _FoldButton extends StatelessWidget {
  const _FoldButton({
    super.key,
    required this.label,
    required this.open,
    required this.onTap,
  });
  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      selected: open,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: touchTarget(context)),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: NNSpace.xxs),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: NNType.subhead.copyWith(
                    color: p.text2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: NNSpace.xxs),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: NNMotion.fade,
                child: Icon(
                  Icons.expand_more_rounded,
                  color: p.text2,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An expense found by search: what, in which group, how much. Opens the group.
class _FoundExpense extends StatelessWidget {
  const _FoundExpense({
    required this.e,
    required this.group,
    required this.onTap,
  });
  final Expense e;
  final GroupDetail group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final amount = money(e.amount, e.currency, s.lang);
    return Pressable(
      key: ValueKey('search-expense-${e.id}'),
      onTap: onTap,
      semanticLabel: '${e.title}, ${group.name}, $amount',
      excludeChildSemantics: true,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NNSpace.sm),
        child: Row(
          children: [
            CoverTile(cover: group.cover),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NNType.headline.copyWith(color: p.text),
                  ),
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NNType.footnote.copyWith(color: p.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NNSpace.xs),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.4,
              ),
              child: AmountText(
                amount,
                style: NNType.subhead.copyWith(
                  color: p.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
