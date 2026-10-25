import 'dart:async';

import 'package:flutter/material.dart';

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
import 'group_screen.dart';
import 'group_sheets.dart';
import 'notifications.dart';
import 'settings_screen.dart';
import 'summary_card.dart' show originOf;

/// Two tabs under one floating glass tab bar, and the add button beside it on Groups. Each tab is
/// its own navigator, so it keeps its history (a group stays open under Groups while you visit
/// Settings) and the tab bar stays over every page. Tapping the tab you are on scrolls its page to
/// the top, and once at the top goes back to the tab's first page.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _compact = false;
  bool _opening = false;
  final _navs = [
    GlobalKey<NavigatorState>(debugLabel: 'groups'),
    GlobalKey<NavigatorState>(debugLabel: 'settings'),
  ];
  late final _pages = [
    TabPages(onScroll: _onScroll),
    TabPages(onScroll: _onScroll),
  ];

  /// Whether a group (or anything else) is open on top of the groups list.
  final _deep = ValueNotifier(false);
  late final _depth = _Depth(_deep);
  late final _groupsObservers = <NavigatorObserver>[_depth];

  void _onScroll(bool down) {
    if (down != _compact) setState(() => _compact = down);
  }

  @override
  void dispose() {
    _deep.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = SessionScope.of(context);
    // First run goes straight to making the first group; a joined link or a notification goes
    // straight to its group.
    if (session.firstRun || session.openGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _arrive());
    }
  }

  Future<void> _arrive() async {
    if (!mounted || _opening) return;
    final session = SessionScope.read(context);
    _opening = true;
    try {
      final id = session.openGroupId;
      if (id != null) {
        session.openGroupId = null;
        unawaited(_open(id));
      } else if (session.firstRun) {
        session.firstRun = false;
        await _newGroup();
      }
    } finally {
      _opening = false;
    }
  }

  /// Opens a group in the Groups tab, with the groups list underneath.
  Future<void> _open(String id, {GroupDetail? initial}) async {
    if (_tab != 0) {
      setState(() {
        _tab = 0;
        _compact = false;
      });
    }
    final nav = _navs[0].currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    await nav.push(
      NNPageRoute<void>(
        builder: (_) => GroupScreen(groupId: id, initial: initial),
      ),
    );
  }

  Future<void> _newGroup([Rect? origin]) async {
    final g = await showNewGroupSheet(context, origin: origin);
    if (g == null || !mounted) return;
    SessionScope.read(context).touch();
    unawaited(_open(g.id, initial: g));
  }

  void _select(int i) {
    if (i == _tab) {
      final nav = _navs[i].currentState;
      if (nav != null) _pages[i].toTopOrRoot(nav, still: reduceMotion(context));
      return;
    }
    setState(() {
      _tab = i;
      _compact = false;
    });
  }

  Widget _tabNav(int i, Widget root) => NavigatorPopHandler<Object?>(
    enabled: _tab == i,
    onPopWithResult: (_) => _navs[i].currentState?.maybePop(),
    child: TabScope(
      pages: _pages[i],
      child: Navigator(
        key: _navs[i],
        observers: i == 0 ? _groupsObservers : const [],
        onGenerateInitialRoutes: (_, _) => [
          NNPageRoute<void>(builder: (_) => root),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    // The same side margin as a page's own bottom bar, so a group's add button sits where this one does.
    final side =
        (((width - NNLayout.maxContent) / 2).clamp(
                  NNSpace.margin,
                  double.infinity,
                ) -
                4)
            .clamp(16.0, double.infinity);
    return StepBack(
      child: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _tab,
              children: [
                _tabNav(0, const GroupsTab()),
                _tabNav(1, const SettingsScreen()),
              ],
            ),
          ),
          Positioned(
            left: side,
            right: side,
            bottom: pad.bottom + 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: GlassTabBar(
                    compact: _compact,
                    index: _tab,
                    onChanged: _select,
                    items: [
                      TabItem(
                        label: s.groups,
                        icon: Icons.group_outlined,
                        selectedIcon: Icons.group_rounded,
                      ),
                      TabItem(
                        label: s.settings,
                        icon: Icons.settings_outlined,
                        selectedIcon: Icons.settings_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // On a group the group's own add button (new expense) takes this place.
                ValueListenableBuilder<bool>(
                  valueListenable: _deep,
                  builder: (context, deep, _) => AnimatedSwitcher(
                    duration: NNMotion.fade,
                    child: _tab == 0 && !deep
                        ? AddButton(label: s.newGroup, onTap: _newGroup)
                        : const SizedBox(width: 64, height: 64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Counts the pages in the Groups tab.
class _Depth extends NavigatorObserver {
  _Depth(this.deep);
  final ValueNotifier<bool> deep;
  int _n = 0;

  void _set(int n) {
    _n = n;
    deep.value = _n > 1;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(_n + 1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(_n - 1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(_n - 1);
}

class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key});

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  List<GroupSummary>? _groups;
  String? _error;
  int _seen = -1;
  int _unread = 0;

  /// True while the list first appears: its rows arrive one after another.
  bool _fresh = true;

  // Search: groups by name and members, expenses by title in the groups kept on this device.
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
    if (_groups == null) {
      // The copy on this device shows at once; the server's answer replaces it.
      final cached = await session.repo.cachedGroups();
      if (mounted && cached != null && _groups == null) {
        setState(() => _groups = cached);
      }
    }
    try {
      final list = await session.repo.groups();
      if (mounted) {
        setState(() {
          _groups = list;
          _error = null;
          _details = const [];
        });
        if (_query.isNotEmpty) unawaited(_loadDetails());
      }
      unawaited(_countUnread());
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.offline ? session.s.offline : e.message;
          _groups ??= e.offline ? null : const [];
        });
      }
    }
  }

  Future<void> _countUnread() async {
    try {
      final list = await SessionScope.read(context).api.notifications();
      if (mounted) setState(() => _unread = list.where((n) => !n.read).length);
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

  Future<void> _openGroup(String id, {Rect? origin}) async {
    await Navigator.of(context).push(
      NNPageRoute<void>(
        origin: origin,
        builder: (_) => GroupScreen(groupId: id),
      ),
    );
    if (mounted) await _load();
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
          final (groups, expenses) = _found();
          if (groups.isNotEmpty || expenses.isNotEmpty) _remember();
        },
        fieldKey: const ValueKey('search'),
        clearKey: const ValueKey('search-clear'),
        ring: p.focus,
      ),
    );
  }

  /// Groups whose name or people match, and expenses whose title does (at most 30).
  (List<GroupSummary>, List<(Expense, GroupDetail)>) _found() {
    final k = _query;
    final groups = _groups ?? const <GroupSummary>[];
    bool hit(String x) => x.toLowerCase().contains(k);
    return (
      [
        for (final g in groups)
          if (hit(g.name) || g.memberNames.any(hit)) g,
      ],
      [
        for (final d in _details)
          for (final e in d.expenses)
            if (hit(e.title)) (e, d),
      ].take(30).toList(),
    );
  }

  Widget _card(GroupSummary g, int i, {bool remember = false}) => FadeIn(
    key: ValueKey('fade-${g.id}'),
    index: i,
    animate: _fresh,
    child: _GroupCard(
      g: g,
      onTap: (origin) {
        if (remember) _remember();
        _openGroup(g.id, origin: origin);
      },
    ),
  );

  List<Widget> _results() {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final (groups, expenses) = _found();
    if (groups.isEmpty && expenses.isEmpty) {
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
      SliverList.separated(
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: NNSpace.sm),
        itemBuilder: (context, i) => _card(groups[i], i, remember: true),
      ),
      if (expenses.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionLabel(s.searchExpenses)),
        SliverToBoxAdapter(
          child: NNCard(
            padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
            child: Column(
              children: [
                for (var i = 0; i < expenses.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 0.5, color: p.separator),
                  _FoundExpense(
                    e: expenses[i].$1,
                    group: expenses[i].$2,
                    onTap: () {
                      _remember();
                      _openGroup(expenses[i].$2.id);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final groups = _groups;
    if (groups != null && _fresh) {
      // Rows built after this frame (while scrolling) just appear.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fresh = false);
    }
    final searching = _query.isNotEmpty;
    final showRecent =
        _focus.hasFocus && _q.text.trim().isEmpty && _recent.isNotEmpty;
    return NNPage(
      key: const ValueKey('groups'),
      title: s.groups,
      actions: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            GlassIconButton(
              key: const ValueKey('bell'),
              icon: _unread > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              label: _unread > 0
                  ? '${s.notifications}, $_unread'
                  : s.notifications,
              onTap: () async {
                await showNotifications(context);
                if (mounted) setState(() => _unread = 0);
              },
            ),
            if (_unread > 0)
              PositionedDirectional(
                top: 6,
                end: 6,
                child: IgnorePointer(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: ShapeDecoration(
                      shape: const CircleBorder(),
                      color: p.danger,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      onRefresh: _load,
      pinned: groups != null && groups.isNotEmpty ? _search() : null,
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
            child: EmptyState(
              title: s.noGroupsTitle,
              body: s.noGroupsBody,
              art: const Coin(size: 88),
            ),
          )
        else if (groups != null && searching)
          ..._results()
        else if (groups != null)
          SliverList.separated(
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: NNSpace.sm),
            itemBuilder: (context, i) => _card(groups[i], i),
          ),
      ],
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
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(NNRadius.row),
              ),
              child: Text(group.emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
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
            Text(
              amount,
              style: NNType.subhead.copyWith(
                color: p.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.g, required this.onTap});
  final GroupSummary g;

  /// Gets the card's rectangle on screen, so the group can grow out of it.
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final b = g.myBalance;
    final balance = b > 0
        ? (s.youAreOwed, money(b, g.currency, s.lang), p.success)
        : b < 0
        ? (s.youOwe, money(-b, g.currency, s.lang), p.danger)
        : (s.even, '', p.text2);
    final names = g.memberNames.join(s.isRtl ? '، ' : ', ');
    return Pressable(
      key: ValueKey('group-${g.id}'),
      onTap: () => onTap(originOf(context)),
      semanticLabel: '${g.name}, $names, ${balance.$1} ${balance.$2}',
      excludeChildSemantics: true,
      scale: 0.98,
      child: NNCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(NNRadius.row),
              ),
              child: Text(g.emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NNType.headline.copyWith(color: p.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    names,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NNType.footnote.copyWith(color: p.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NNSpace.xs),
            // The balance gives way to the name before anything overflows, at any text size.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    balance.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NNType.caption.copyWith(color: p.text2),
                  ),
                  if (balance.$2.isNotEmpty)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        balance.$2,
                        style: NNType.headline.copyWith(
                          color: balance.$3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
