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
import 'common.dart';
import 'group_screen.dart';
import 'summary_card.dart' show originOf;

/// Everyone you split with, from Home's "See all".
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key, required this.people});
  final List<PersonSummary> people;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return NNPage(
      key: const ValueKey('people'),
      title: s.people,
      leading: GlassIconButton(
        icon: Icons.adaptive.arrow_back_rounded,
        label: MaterialLocalizations.of(context).backButtonTooltip,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: people.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: NNSpace.xl),
                  child: Text(
                    s.noPeople,
                    textAlign: TextAlign.center,
                    style: NNType.subhead.copyWith(color: p.text2),
                  ),
                )
              : RowsCard(
                  indent: 52,
                  children: [
                    for (final x in people)
                      PersonRow(
                        person: x,
                        onTap: (origin) => Navigator.of(context).push(
                          NNPageRoute<void>(
                            origin: origin,
                            builder: (_) => PersonScreen(
                              personKey: x.key,
                              name: x.name,
                              look: x.avatar,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A person in a list: their avatar, name, how many groups you share, and where you stand.
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.person, required this.onTap});
  final PersonSummary person;
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final first = person.balances.isEmpty ? null : person.balances.first;
    final signed = first?.amount ?? 0;
    final groups = person.groups == 1
        ? s.acrossOne
        : s.fill(s.acrossN, {'n': person.groups});
    final words = first == null
        ? s.personEven
        : s.fill(signed > 0 ? s.owesYouX : s.youOweX, {
            'amount': amountsLine(person.balances, s),
          });
    return Pressable(
      key: ValueKey('person-row-${person.key}'),
      onTap: () => onTap(originOf(context)),
      semanticLabel: '${person.name}, $groups, $words',
      excludeChildSemantics: true,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                Avatar(name: person.name, look: person.avatar, size: 40),
                const SizedBox(width: NNSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.headline.copyWith(color: p.text),
                      ),
                      Text(
                        groups,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.footnote.copyWith(color: p.text2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NNSpace.xs),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
                  child: _Stand(signed: signed, balances: person.balances),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "owes you" over the amount, "you owe" over it, or "Even".
class _Stand extends StatelessWidget {
  const _Stand({required this.signed, required this.balances});
  final int signed;
  final List<Money> balances;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    if (signed == 0 || balances.isEmpty) {
      return Text(
        s.personEven,
        style: NNType.footnote.copyWith(
          color: p.text2,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final first = balances.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          wordsOnly(signed > 0 ? s.owesYouX : s.youOweX),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NNType.caption.copyWith(
            color: signed > 0 ? p.success : p.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
        AmountText(
          money(first.amount.abs(), first.currency, s.lang),
          style: NNType.subhead.copyWith(
            color: balanceColor(p, signed),
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// One person across every group you share: what you owe each other overall, settling it all in
/// one go (with Undo), a reminder, the groups you share and what you split.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.personKey,
    this.name = '',
    this.look,
  });
  final String personKey;

  /// Shown at once, before the server's answer.
  final String name;
  final AvatarLook? look;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late final Session _session = SessionScope.read(context);
  PersonDetail? _p;
  String? _error;
  bool _gone = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // settle runs from opening a person to marking things paid.
    _session.timings.start('settle');
    _load();
  }

  @override
  void dispose() {
    _session.timings.cancel('settle');
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _session.api.person(widget.personKey);
      if (mounted) {
        setState(() {
          _p = p;
          _error = null;
          _gone = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.status == 404) {
          _gone = true;
        } else {
          _error = e.offline ? _session.s.offline : e.message;
        }
      });
    }
  }

  Future<void> _settleAll() async {
    final person = _p;
    if (person == null || _busy) return;
    final s = _session.s;
    final open = [
      for (final g in person.groups)
        if (g.amount != 0) g,
    ];
    if (open.isEmpty) return;
    final ok = await showNNSheet<bool>(
      context,
      key: const ValueKey('settle-sheet'),
      title: s.settleEverything,
      builder: (ctx) => _SettleSummary(person: person, groups: open),
      footer: (ctx) => NNButton(
        key: const ValueKey('settle-confirm'),
        label: s.settleConfirm,
        onTap: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _session.api.settleAll(person.key);
      _session.timings.finish('settle');
      haptic(Haptic.success);
      _session.touch();
      if (!mounted) return;
      setState(() {
        _p = r.person;
        _busy = false;
      });
      showToast(
        context,
        s.fill(s.settledWith, {'name': person.name}),
        key: const ValueKey('toast'),
        check: true,
        actionLabel: s.undo,
        onAction: () async {
          try {
            await _session.api.undoPayments(r.payments);
            _session.touch();
            if (mounted) await _load();
          } on ApiException catch (e) {
            if (mounted) setState(() => _error = e.message);
          }
        },
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.offline ? s.offline : e.message;
        });
      }
    }
  }

  Future<void> _remind() async {
    final person = _p;
    if (person == null) return;
    final s = _session.s;
    final owed = [
      for (final m in person.balances)
        if (m.amount > 0) m,
    ];
    await sendReminder(
      _session,
      s.fill(s.remindAllMessage, {
        'name': person.name,
        'amounts': amountsLine(owed, s),
      }),
    );
  }

  Future<void> _openGroup(String id, Rect? origin) async {
    await Navigator.of(context).push(
      NNPageRoute<void>(
        origin: origin,
        builder: (_) => GroupScreen(groupId: id),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final person = _p;
    final name = person?.name ?? widget.name;
    final look = person?.avatar ?? widget.look;
    final first = person == null || person.balances.isEmpty
        ? null
        : person.balances.first;
    final signed = first?.amount ?? 0;
    final ring = signed > 0
        ? p.success
        : signed < 0
        ? p.accent
        : p.separator;
    final back = GlassIconButton(
      icon: Icons.adaptive.arrow_back_rounded,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      onTap: () => Navigator.of(context).maybePop(),
    );
    final large = MediaQuery.textScalerOf(context).scale(10) / 10 >= 1.3;
    return NNPage(
      key: const ValueKey('person'),
      title: name,
      titleLeading: Avatar(name: name, look: look, size: 56, ring: ring),
      leading: back,
      onRefresh: _load,
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
        if (_gone)
          SliverToBoxAdapter(
            child: EmptyState(
              title: name,
              body: s.personNotFound,
              art: const Coin(size: 64, join: 0),
            ),
          )
        else if (person == null)
          SliverToBoxAdapter(child: SkeletonRows(label: s.loading, count: 3))
        else ...[
          SliverToBoxAdapter(
            child: Semantics(
              container: true,
              child: Column(
                key: const ValueKey('person-balance'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.fill(
                      signed > 0
                          ? s.personOwesYou
                          : signed < 0
                          ? s.personYouOwe
                          : s.personEvenTitle,
                      {'name': name},
                    ),
                    style: NNType.subhead.copyWith(color: p.text2),
                  ),
                  if (first != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: RollingText(
                        money(first.amount.abs(), first.currency, s.lang),
                        key: const ValueKey('person-amount'),
                        style: NNType.amountHero.copyWith(
                          fontSize: 44,
                          color: balanceColor(p, signed),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  for (final m in person.balances.skip(1))
                    Text(
                      signedMoney(m.amount, m.currency, s),
                      style: NNType.headline.copyWith(
                        color: balanceColor(p, m.amount),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (person.groups.any((g) => g.amount != 0))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: NNSpace.lg),
                child: _Actions(
                  stacked: large,
                  settle: NNButton(
                    key: const ValueKey('settle-all'),
                    label: s.settleEverything,
                    busy: _busy,
                    expand: large,
                    onTap: _settleAll,
                  ),
                  remind: person.balances.any((m) => m.amount > 0)
                      ? NNButton(
                          key: const ValueKey('remind-all'),
                          label: s.remind,
                          icon: Icons.chat_bubble_outline_rounded,
                          kind: ButtonKind.tinted,
                          expand: large,
                          onTap: _remind,
                        )
                      : null,
                ),
              ),
            ),
          if (person.groups.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionLabel(s.groupsShared)),
            SliverToBoxAdapter(
              child: RowsCard(
                indent: 52,
                children: [
                  for (final g in person.groups)
                    Builder(
                      builder: (ctx) => _SharedGroupRow(
                        g: g,
                        onTap: () => _openGroup(g.group.id, originOf(ctx)),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (person.shared.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionLabel(s.betweenYou)),
            SliverToBoxAdapter(
              child: RowsCard(
                indent: 0,
                children: [
                  for (final e in person.shared)
                    _SharedExpenseRow(e: e, name: name),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Settle everything and Remind: side by side, stacked at large text sizes.
class _Actions extends StatelessWidget {
  const _Actions({required this.stacked, required this.settle, this.remind});
  final bool stacked;
  final Widget settle;
  final Widget? remind;

  @override
  Widget build(BuildContext context) {
    final r = remind;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          settle,
          if (r != null) ...[const SizedBox(height: NNSpace.xs), r],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: settle),
        if (r != null) ...[const SizedBox(width: NNSpace.xs), r],
      ],
    );
  }
}

/// What "Settle everything" will mark as paid, group by group.
class _SettleSummary extends StatelessWidget {
  const _SettleSummary({required this.person, required this.groups});
  final PersonDetail person;
  final List<PersonGroup> groups;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.fill(s.settleEverythingBody, {'name': person.name}),
          style: NNType.callout.copyWith(color: p.text2),
        ),
        const SizedBox(height: NNSpace.md),
        RowsCard(
          indent: 44,
          children: [
            for (final g in groups)
              ConstrainedBox(
                key: ValueKey('settle-row-${g.group.id}'),
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
                  child: Row(
                    children: [
                      CoverTile(cover: g.group.cover, size: 32),
                      const SizedBox(width: NNSpace.sm),
                      Expanded(
                        child: Text(
                          g.group.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: NNType.body.copyWith(color: p.text),
                        ),
                      ),
                      const SizedBox(width: NNSpace.xs),
                      Flexible(
                        child: Text(
                          s.fill(g.amount > 0 ? s.owesYouX : s.youOweX, {
                            'amount': money(
                              g.amount.abs(),
                              g.group.currency,
                              s.lang,
                            ),
                          }),
                          textAlign: TextAlign.end,
                          style: NNType.subhead.copyWith(
                            color: balanceColor(p, g.amount),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SharedGroupRow extends StatelessWidget {
  const _SharedGroupRow({required this.g, required this.onTap});
  final PersonGroup g;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final amount = g.amount == 0
        ? ''
        : money(g.amount.abs(), g.group.currency, s.lang);
    final words = g.amount == 0
        ? s.personEven
        : wordsOnly(g.amount > 0 ? s.owesYouX : s.youOweX);
    return Pressable(
      key: ValueKey('shared-group-${g.group.id}'),
      onTap: onTap,
      semanticLabel: '${g.group.name}, $words $amount'.trim(),
      excludeChildSemantics: true,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                CoverTile(cover: g.group.cover, size: 40),
                const SizedBox(width: NNSpace.sm),
                Expanded(
                  child: Text(
                    g.group.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NNType.headline.copyWith(color: p.text),
                  ),
                ),
                const SizedBox(width: NNSpace.xs),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        words,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.caption.copyWith(
                          color: g.amount > 0 ? p.success : p.text2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (amount.isNotEmpty)
                        AmountText(
                          amount,
                          style: NNType.subhead.copyWith(
                            color: balanceColor(p, g.amount),
                            fontWeight: FontWeight.w600,
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

/// An expense one of you paid: what it moved between you two.
class _SharedExpenseRow extends StatelessWidget {
  const _SharedExpenseRow({required this.e, required this.name});
  final SharedExpense e;
  final String name;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final date = dateLabel(e.at, s);
    final sub = e.paidByMe
        ? s.fill(s.youPaidOn, {'date': date})
        : s.fill(s.namePaidOn, {'name': name, 'date': date});
    final amount = signedMoney(e.amount, e.currency, s);
    return MergeSemantics(
      key: ValueKey('shared-${e.id}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.callout.copyWith(
                          color: p.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$sub · ${e.group.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NNType.footnote.copyWith(color: p.text2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NNSpace.xs),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
                  child: AmountText(
                    amount,
                    style: NNType.subhead.copyWith(
                      color: balanceColor(p, e.amount),
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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
