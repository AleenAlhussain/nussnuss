import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/coin.dart';
import '../design/glass.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import '../format.dart';
import 'group_screen.dart';
import 'group_sheets.dart';
import 'settings_screen.dart';

/// Two tabs under one floating glass tab bar, and the add button beside it on Groups.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _compact = false;

  void _onScroll(bool down) {
    if (down != _compact) setState(() => _compact = down);
  }

  Future<void> _newGroup() async {
    final g = await showNewGroupSheet(context);
    if (g == null || !mounted) return;
    SessionScope.read(context).touch();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupScreen(groupId: g.id, initial: g),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final side = ((width - NNLayout.maxContent) / 2).clamp(
      16.0,
      double.infinity,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(
            index: _tab,
            children: [
              GroupsTab(onScrollDirection: _onScroll),
              SettingsScreen(onScrollDirection: _onScroll),
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
                  onChanged: (i) => setState(() {
                    _tab = i;
                    _compact = false;
                  }),
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
              AnimatedSwitcher(
                duration: NNMotion.fade,
                child: _tab == 0
                    ? AddButton(label: s.newGroup, onTap: _newGroup)
                    : const SizedBox(width: 64, height: 64),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key, this.onScrollDirection});
  final ValueChanged<bool>? onScrollDirection;

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  List<GroupSummary>? _groups;
  String? _error;
  int _seen = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rev = SessionScope.of(context).revision;
    if (rev != _seen) {
      _seen = rev;
      _load();
    }
  }

  Future<void> _load() async {
    final session = SessionScope.read(context);
    try {
      final list = await session.api.groups();
      if (mounted) {
        setState(() {
          _groups = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? session.s.offline : e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final groups = _groups;
    return NNPage(
      key: const ValueKey('groups'),
      title: s.groups,
      onRefresh: _load,
      onScrollDirection: widget.onScrollDirection,
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
        if (groups == null && _error == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(NNSpace.xxl),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          )
        else if (groups != null && groups.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              title: s.noGroupsTitle,
              body: s.noGroupsBody,
              art: const Coin(size: 88),
            ),
          )
        else if (groups != null)
          SliverList.separated(
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: NNSpace.sm),
            itemBuilder: (context, i) => _GroupCard(
              g: groups[i],
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupScreen(groupId: groups[i].id),
                  ),
                );
                if (mounted) await _load();
              },
            ),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.g, required this.onTap});
  final GroupSummary g;
  final VoidCallback onTap;

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
      onTap: onTap,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  balance.$1,
                  style: NNType.caption.copyWith(color: p.text2),
                ),
                if (balance.$2.isNotEmpty)
                  Text(
                    balance.$2,
                    style: NNType.headline.copyWith(
                      color: balance.$3,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
