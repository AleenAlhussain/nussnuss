import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import 'activity.dart';
import 'group_screen.dart';
import 'group_sheets.dart';
import 'home_tab.dart';
import 'settings_screen.dart';

/// Three tabs under one floating glass tab bar (Home, Activity, You), and the add button beside
/// it. Each tab is its own navigator, so it keeps its history (a group stays open under Home while
/// you look at Activity) and the tab bar stays over every page. Tapping the tab you are on scrolls
/// its page to the top, and once at the top goes back to the tab's first page.
///
/// The + adds an expense from anywhere: with one group it goes straight there, with more it asks
/// which group, with none it starts the first one.
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
    GlobalKey<NavigatorState>(debugLabel: 'home'),
    GlobalKey<NavigatorState>(debugLabel: 'activity'),
    GlobalKey<NavigatorState>(debugLabel: 'you'),
  ];
  late final _pages = [
    for (var i = 0; i < 3; i++) TabPages(onScroll: _onScroll),
  ];

  /// Per tab: whether something (a group, a person) is open on top of the tab's first page.
  final _deep = [for (var i = 0; i < 3; i++) ValueNotifier(false)];
  late final _observers = [
    for (final d in _deep) <NavigatorObserver>[_Depth(d)],
  ];

  /// The tab on screen, for tabs that refresh when they are picked (Activity).
  final _current = ValueNotifier<int>(0);

  void _onScroll(bool down) {
    if (down != _compact) setState(() => _compact = down);
  }

  @override
  void dispose() {
    for (final d in _deep) {
      d.dispose();
    }
    _current.dispose();
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

  void _show(int i) {
    if (_tab == i) return;
    setState(() {
      _tab = i;
      _compact = false;
    });
    _current.value = i;
  }

  /// Opens a group in the Home tab, with Home underneath. With [add], "Add expense" comes up on it.
  Future<void> _open(
    String id, {
    GroupDetail? initial,
    bool add = false,
  }) async {
    _show(0);
    final nav = _navs[0].currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    await nav.push(
      NNPageRoute<void>(
        builder: (_) =>
            GroupScreen(groupId: id, initial: initial, addOnOpen: add),
      ),
    );
  }

  Future<void> _newGroup([Rect? origin]) async {
    final g = await showNewGroupSheet(context, origin: origin);
    if (g == null || !mounted) return;
    SessionScope.read(context).touch();
    unawaited(_open(g.id, initial: g));
  }

  Future<void> _addExpense(Rect origin) async {
    final session = SessionScope.read(context);
    final timings = session.timings;
    timings.start('add_expense');
    var groups = await session.repo.cachedGroups();
    if (groups == null || groups.isEmpty) {
      try {
        groups = await session.repo.groups();
      } on ApiException {
        groups ??= const [];
      }
    }
    if (!mounted) return;
    if (groups.isEmpty) {
      timings.cancel('add_expense');
      return _newGroup(origin);
    }
    final String? picked = groups.length == 1
        ? groups.first.id
        : await showGroupPicker(context, groups, origin: origin);
    if (!mounted) return;
    if (picked == null) {
      timings.cancel('add_expense');
      return;
    }
    if (picked == newGroupChoice) {
      timings.cancel('add_expense');
      return _newGroup();
    }
    await _open(picked, add: true);
  }

  void _select(int i) {
    if (i == _tab) {
      final nav = _navs[i].currentState;
      if (nav != null) _pages[i].toTopOrRoot(nav, still: reduceMotion(context));
      return;
    }
    _show(i);
  }

  Widget _tabNav(int i, Widget root) => NavigatorPopHandler<Object?>(
    enabled: _tab == i,
    onPopWithResult: (_) => _navs[i].currentState?.maybePop(),
    child: TabScope(
      pages: _pages[i],
      child: Navigator(
        key: _navs[i],
        observers: _observers[i],
        onGenerateInitialRoutes: (_, _) => [
          NNPageRoute<void>(builder: (_) => root),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    // The bar keeps its size at large text; past 135 % a long press shows the tab big instead.
    final largeContent =
        MediaQuery.textScalerOf(context).scale(10) / 10 >= 1.35;
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
                _tabNav(0, const HomeTab()),
                _tabNav(1, ActivityTab(current: _current, index: 1)),
                _tabNav(2, const YouScreen()),
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
                  child: ValueListenableBuilder<int>(
                    valueListenable: session.unread,
                    builder: (context, unread, _) => GlassTabBar(
                      compact: _compact,
                      index: _tab,
                      onChanged: _select,
                      largeContent: largeContent,
                      items: [
                        TabItem(
                          label: s.tabHome,
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home_rounded,
                        ),
                        TabItem(
                          label: s.tabActivity,
                          icon: Icons.history_rounded,
                          selectedIcon: Icons.history_rounded,
                          badge: unread,
                          badgeLabel: s.fill(s.unreadN, {'n': unread}),
                        ),
                        TabItem(
                          label: s.tabYou,
                          icon: Icons.person_outline_rounded,
                          selectedIcon: Icons.person_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // On a group the group's own add button takes this place.
                ListenableBuilder(
                  listenable: _deep[_tab],
                  builder: (context, _) => AnimatedSwitcher(
                    duration: NNMotion.fade,
                    child: !_deep[_tab].value
                        ? AddButton(label: s.addExpense, onTap: _addExpense)
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

/// Counts the pages in a tab.
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

/// What [showGroupPicker] returns when the person picks "New group".
const newGroupChoice = '\u0000new';

/// Which group the new expense goes in: groups still open first, most recently busy first, then a
/// "New group" row.
Future<String?> showGroupPicker(
  BuildContext context,
  List<GroupSummary> groups, {
  Rect? origin,
}) {
  DateTime when(GroupSummary g) => g.lastActivity?.at ?? g.updatedAt;
  final sorted = [...groups]
    ..sort((a, b) {
      if (a.settled != b.settled) return a.settled ? 1 : -1;
      return when(b).compareTo(when(a));
    });
  return showNNSheet<String>(
    context,
    key: const ValueKey('group-picker'),
    origin: origin,
    title: context.s.addExpense,
    builder: (ctx) {
      final s = ctx.s;
      final p = NNTheme.of(ctx).palette;
      Widget row({
        required Key key,
        required Widget lead,
        required String label,
        required String value,
      }) => Pressable(
        key: key,
        onTap: () => Navigator.of(ctx).pop(value),
        semanticLabel: label,
        excludeChildSemantics: true,
        scale: 0.98,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
            child: Row(
              children: [
                lead,
                const SizedBox(width: NNSpace.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NNType.headline.copyWith(color: p.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return NNCard(
        padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
        child: Column(
          children: [
            for (var i = 0; i < sorted.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 52,
                  color: p.separator,
                ),
              row(
                key: ValueKey('pick-${sorted[i].id}'),
                lead: CoverTile(cover: sorted[i].cover, size: 40),
                label: sorted[i].name,
                value: sorted[i].id,
              ),
            ],
            Divider(height: 1, thickness: 0.5, indent: 52, color: p.separator),
            row(
              key: const ValueKey('pick-new-group'),
              lead: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(40 * 0.29),
                ),
                child: Icon(Icons.add_rounded, color: p.onAccentSoft),
              ),
              label: s.newGroup,
              value: newGroupChoice,
            ),
          ],
        ),
      );
    },
  );
}
