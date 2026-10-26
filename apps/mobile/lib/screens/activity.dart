import 'package:flutter/foundation.dart';
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
import '../l10n/strings.g.dart';
import 'common.dart';
import 'group_screen.dart';
import 'summary_card.dart' show originOf;

/// What happened across all your groups, newest first: by day (Today, Yesterday, This week,
/// Earlier), with a filter per group, a dot on what is new and "Mark all read".
class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key, required this.current, required this.index});

  /// The tab on screen; Activity refreshes when it is picked.
  final ValueListenable<int> current;
  final int index;

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  List<ActivityItem>? _items;
  String? _next;
  String? _group;
  String? _error;
  bool _more = false;
  bool _allRead = false;
  List<GroupBrief> _groups = const [];
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    widget.current.addListener(_onTab);
  }

  @override
  void dispose() {
    widget.current.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (widget.current.value == widget.index) _load();
  }

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
    final group = _group;
    try {
      final cached = await session.repo.cachedGroups();
      final page = await session.api.activity(group: group);
      if (!mounted || group != _group) return;
      setState(() {
        _items = page.items;
        _next = page.next;
        _error = null;
        _allRead = false;
        if (cached != null) {
          _groups = [for (final g in cached) g.brief];
        }
      });
      if (group == null) session.unread.value = page.unread;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? session.s.offline : e.message);
      }
    }
  }

  Future<void> _showMore() async {
    final next = _next;
    if (next == null || _more) return;
    final session = SessionScope.read(context);
    setState(() => _more = true);
    try {
      final page = await session.api.activity(before: next, group: _group);
      if (!mounted) return;
      setState(() {
        _items = [...?_items, ...page.items];
        _next = page.next;
        _more = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _more = false;
          _error = e.offline ? session.s.offline : e.message;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    final session = SessionScope.read(context);
    setState(() => _allRead = true);
    session.unread.value = 0;
    haptic(Haptic.selection);
    try {
      await session.api.activitySeen();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? session.s.offline : e.message);
      }
    }
  }

  void _filter(String? id) {
    if (id == _group) return;
    setState(() {
      _group = id;
      _items = null;
      _next = null;
    });
    _load();
  }

  Future<void> _open(ActivityItem it, Rect? origin) async {
    await Navigator.of(context).push(
      NNPageRoute<void>(
        origin: origin,
        builder: (_) => GroupScreen(groupId: it.group.id),
      ),
    );
    if (mounted) await _load();
  }

  /// The groups to filter by: those on this device, else the ones in the list.
  List<GroupBrief> get _chips {
    if (_groups.isNotEmpty) return _groups;
    final seen = <String>{};
    return [
      for (final it in _items ?? const <ActivityItem>[])
        if (seen.add(it.group.id)) it.group,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final items = _items;
    final unread = _allRead
        ? 0
        : (items ?? const <ActivityItem>[]).where((i) => i.unread).length;
    final chips = _chips;

    // Today, Yesterday, This week, Earlier.
    final sections = <String, List<ActivityItem>>{};
    final today = dayKey(clock());
    for (final it in items ?? const <ActivityItem>[]) {
      final days = today.difference(dayKey(it.at)).inDays;
      final label = days <= 0
          ? s.today
          : days == 1
          ? s.yesterday
          : days < 7
          ? s.thisWeek
          : s.earlier;
      (sections[label] ??= []).add(it);
    }

    return NNPage(
      key: const ValueKey('activity'),
      title: s.tabActivity,
      onRefresh: _load,
      slivers: [
        if (chips.length > 1)
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              key: const ValueKey('activity-filters'),
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  NNChip(
                    key: const ValueKey('filter-all'),
                    label: s.everything,
                    selected: _group == null,
                    onTap: () => _filter(null),
                  ),
                  for (final g in chips) ...[
                    const SizedBox(width: NNSpace.xs),
                    NNChip(
                      key: ValueKey('filter-${g.id}'),
                      label: g.name,
                      selected: _group == g.id,
                      onTap: () => _filter(g.id),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: NNSpace.sm),
              child: Text(
                _error!,
                style: NNType.footnote.copyWith(color: p.danger),
              ),
            ),
          ),
        if (unread > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: NNSpace.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.fill(s.unreadN, {'n': unread}),
                      style: NNType.subhead.copyWith(
                        color: p.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Pressable(
                      key: const ValueKey('mark-all-read'),
                      onTap: _markAllRead,
                      semanticLabel: s.markAllRead,
                      excludeChildSemantics: true,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: touchTarget(context),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NNSpace.xs,
                          ),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              s.markAllRead,
                              textAlign: TextAlign.end,
                              style: NNType.subhead.copyWith(
                                color: p.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (items == null && _error == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: NNSpace.md),
              child: SkeletonRows(label: s.loading),
            ),
          )
        else if (items != null && items.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              key: const ValueKey('no-activity'),
              title: s.noActivityTitle,
              body: s.noActivityBody,
              art: const Coin(size: 72),
            ),
          )
        else if (items != null) ...[
          for (final e in sections.entries) ...[
            SliverToBoxAdapter(child: SectionLabel(e.key)),
            SliverToBoxAdapter(
              child: RowsCard(
                indent: 71,
                children: [
                  for (final it in e.value)
                    Builder(
                      builder: (ctx) => _ActivityRow(
                        item: it,
                        unread: it.unread && !_allRead,
                        onTap: () => _open(it, originOf(ctx)),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_next != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: NNSpace.md),
                child: NNButton(
                  key: const ValueKey('show-more'),
                  label: s.showMore,
                  kind: ButtonKind.plain,
                  busy: _more,
                  onTap: _showMore,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// [template] with its {placeholders} filled, the ones in [bold] in semibold.
List<InlineSpan> _fill(
  String template,
  Map<String, String> values, {
  Set<String> bold = const {},
}) {
  const strong = TextStyle(fontWeight: FontWeight.w600);
  final out = <InlineSpan>[];
  var at = 0;
  for (final m in RegExp(r'\{(\w+)\}').allMatches(template)) {
    if (m.start > at) out.add(TextSpan(text: template.substring(at, m.start)));
    final k = m.group(1)!;
    out.add(
      TextSpan(text: values[k] ?? '', style: bold.contains(k) ? strong : null),
    );
    at = m.end;
  }
  if (at < template.length) out.add(TextSpan(text: template.substring(at)));
  return out;
}

/// "Sara added Lunch", "You marked a payment to Omar": who did what, the person in semibold.
List<InlineSpan> activitySentence(ActivityItem it, NNStrings s) {
  const strong = TextStyle(fontWeight: FontWeight.w600);
  String name(Who? w) => w == null ? '' : (w.me ? s.you : w.name);
  final actor = it.actor;
  if (it.kind == 'expense') {
    final who = actor ?? it.paidBy;
    final title = {'title': it.title};
    if (it.op == 'update') {
      if (who?.me == true) return _fill(s.actYouEdited, title);
      return [
        TextSpan(text: name(who), style: strong),
        const TextSpan(text: ' '),
        ..._fill(s.actEdited, title),
      ];
    }
    if (who?.me == true) return _fill(s.actYouAdded, title);
    return _fill(
      s.actNameAdded,
      {'name': name(who), 'title': it.title},
      bold: {'name'},
    );
  }
  final from = it.from;
  final to = it.to;
  if (actor?.me == true) {
    if (from?.me == true) {
      return _fill(s.actYouPaid, {'name': name(to)}, bold: {'name'});
    }
    if (to?.me == true) {
      return _fill(s.actYouGot, {'name': name(from)}, bold: {'name'});
    }
  } else if (actor != null && from != null && actor.name == from.name) {
    return [
      TextSpan(text: actor.name, style: strong),
      const TextSpan(text: ' '),
      if (to?.me == true)
        ..._fill(s.actPaidYou, const {})
      else
        ..._fill(s.actPaid, {'name': name(to)}, bold: {'name'}),
    ];
  }
  return _fill(
    s.actPaidLine,
    {'from': name(from), 'to': name(to)},
    bold: {'from', 'to'},
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.item,
    required this.unread,
    required this.onTap,
  });
  final ActivityItem item;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final it = item;
    final who = it.actor ?? (it.kind == 'expense' ? it.paidBy : it.from);
    final sentence = TextSpan(children: activitySentence(it, s));
    final cur = it.group.currency;
    final impact = it.kind != 'expense'
        ? null
        : it.impact < 0
        ? s.fill(s.yourShare, {'amount': money(-it.impact, cur, s.lang)})
        : it.impact > 0
        ? s.fill(s.youLent, {'amount': money(it.impact, cur, s.lang)})
        : s.notInvolved;
    final sub = [it.group.name, whenLabel(it.at, s), ?impact].join(' · ');
    final amount = money(it.amount, cur, s.lang);
    return Pressable(
      key: ValueKey('activity-${it.id}'),
      onTap: onTap,
      semanticLabel: [
        if (unread) s.newItem,
        sentence.toPlainText(),
        sub,
        amount,
      ].join(', '),
      excludeChildSemantics: true,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NNSpace.sm),
        child: LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              SizedBox(
                width: 7,
                child: unread
                    ? Container(
                        key: ValueKey('unread-${it.id}'),
                        width: 7,
                        height: 7,
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          color: p.accent,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: NNSpace.xs),
              Avatar(name: who?.name ?? '', look: who?.avatar, size: 40),
              const SizedBox(width: NNSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      sentence,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NNType.callout.copyWith(color: p.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NNType.footnote.copyWith(color: p.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NNSpace.xs),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.32),
                child: AmountText(
                  amount,
                  style: NNType.subhead.copyWith(
                    color: p.text,
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
