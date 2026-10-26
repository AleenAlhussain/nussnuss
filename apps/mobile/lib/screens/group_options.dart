import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/extras.dart';
import '../core/money.dart';
import '../core/split.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/services.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import '../format.dart';
import 'expense_sheet.dart';
import 'paywall.dart';
import 'pickers.dart';
import 'summary_card.dart';

String _day(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatMediumDate(d);

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _fromIso(String s) => DateTime.tryParse(s) ?? DateTime.now();

/// Everything about a group beyond its expenses: Trip Pass, weekly reminders, recurring bills,
/// money circles, spending and the CSV. Changes come back through [onChanged].
Future<void> showGroupOptions(
  BuildContext context, {
  required GroupDetail group,
  required ValueChanged<GroupDetail> onChanged,
}) {
  return showNNSheet<void>(
    context,
    key: const ValueKey('group-options'),
    title: context.s.groupMore,
    builder: (_) => _Options(group: group, onChanged: onChanged),
  );
}

class _Options extends StatefulWidget {
  const _Options({required this.group, required this.onChanged});
  final GroupDetail group;
  final ValueChanged<GroupDetail> onChanged;

  @override
  State<_Options> createState() => _OptionsState();
}

class _OptionsState extends State<_Options> {
  late GroupDetail g = widget.group;
  String? _error;
  bool _busy = false;

  void _take(GroupDetail d) {
    setState(() => g = d);
    widget.onChanged(d);
  }

  Future<void> _run(Future<GroupDetail> Function() call) async {
    final session = SessionScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _take(await session.repo.took(await call()));
    } on ApiException catch (e) {
      if (e.plus && mounted) {
        await showPaywall(context, group: g);
      } else if (mounted) {
        setState(() => _error = e.offline ? session.s.offline : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _needPlus() async {
    final session = SessionScope.read(context);
    if (session.hasPlus(g)) return true;
    return showPaywall(context, group: g);
  }

  /// A new bill that repeats every month: the expense sheet with "Repeats" already set.
  Future<void> _addRepeating() async {
    if (!await _needPlus() || !mounted) return;
    final r = await showExpenseSheet(context, group: g, repeat: 'month');
    if (r != null && mounted) _take(r.detail);
  }

  Future<void> _reminders(bool on) async {
    if (on && !await _needPlus()) return;
    if (!mounted) return;
    final api = SessionScope.read(context).api;
    await _run(() => api.setReminders(g.id, weekly: on));
  }

  Future<void> _csv(BuildContext buttonContext) async {
    final origin = originOf(buttonContext);
    if (!await _needPlus() || !mounted) return;
    final session = SessionScope.read(context);
    try {
      final csv = await session.api.exportCsv(g.id);
      await session.device.share(
        files: [
          SharedFile(
            utf8.encode(csv),
            name: '${g.name.replaceAll(RegExp(r'[^\w\- ]+'), '').trim()}.csv',
            mimeType: 'text/csv',
          ),
        ],
        origin: origin,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.plus) {
        await showPaywall(context, group: g);
      } else {
        setState(() => _error = e.offline ? session.s.offline : e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    final plus = session.hasPlus(g);
    final api = session.api;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trip Pass.
        NNCard(
          child: g.tripPass
              ? Row(
                  children: [
                    Icon(Icons.flight_takeoff_rounded, color: p.success),
                    const SizedBox(width: NNSpace.sm),
                    Expanded(
                      child: Text(
                        s.fill(s.tripOnUntil, {
                          'date': _day(context, g.tripPassUntil!),
                        }),
                        style: NNType.callout.copyWith(color: p.text),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flight_takeoff_rounded, color: p.accent),
                        const SizedBox(width: NNSpace.sm),
                        Expanded(
                          child: Text(
                            s.tripPass,
                            style: NNType.headline.copyWith(color: p.text),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NNSpace.xxs),
                    Text(
                      s.tripPassBody,
                      style: NNType.footnote.copyWith(color: p.text2),
                    ),
                    const SizedBox(height: NNSpace.sm),
                    NNButton(
                      key: const ValueKey('get-trip-pass'),
                      label: s.seePlus,
                      kind: ButtonKind.tinted,
                      onTap: () async {
                        await showPaywall(context, group: g);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
        ),
        // The row names itself; a header saying the same again would only repeat it.
        const SizedBox(height: NNSpace.md),
        _SwitchRow(
          key: const ValueKey('reminders'),
          label: s.weeklyReminders,
          hint: s.weeklyRemindersHint,
          value: g.remindEvery == 'week',
          locked: !plus,
          onChanged: _busy ? null : _reminders,
        ),
        SectionLabel(s.recurringTitle),
        if (g.recurring.isEmpty)
          Padding(
            key: const ValueKey('no-repeating'),
            padding: const EdgeInsetsDirectional.only(
              start: NNSpace.xxs,
              bottom: NNSpace.xs,
            ),
            child: Text(
              s.noRepeating,
              style: NNType.footnote.copyWith(color: p.text2),
            ),
          )
        else
          NNCard(
            padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
            child: Column(
              children: [
                for (var i = 0; i < g.recurring.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 0.5, color: p.separator),
                  _RecurringRow(
                    bill: g.recurring[i],
                    group: g,
                    onStop: _busy
                        ? null
                        : () =>
                              _run(() => api.stopRecurring(g.recurring[i].id)),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: NNSpace.xs),
        NNButton(
          key: const ValueKey('add-repeating'),
          label: s.addRepeating,
          icon: Icons.event_repeat_rounded,
          kind: ButtonKind.tinted,
          onTap: _busy ? null : _addRepeating,
        ),
        if (!plus)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.xs),
            child: Text(
              '${s.plusFRecurring} · ${s.needsPlus}',
              style: NNType.footnote.copyWith(color: p.text2),
            ),
          ),
        SectionLabel(s.circles),
        for (final c in g.circles)
          Padding(
            padding: const EdgeInsets.only(bottom: NNSpace.xs),
            child: CircleCard(
              group: g,
              circle: c,
              onTap: () => showCircleSheet(
                context,
                group: g,
                circleId: c.id,
                onChanged: _take,
              ),
            ),
          ),
        NNButton(
          key: const ValueKey('new-circle'),
          label: s.newCircle,
          icon: Icons.donut_small_rounded,
          kind: ButtonKind.tinted,
          onTap: () async {
            final d = await showNewCircleSheet(context, group: g);
            if (d != null) _take(d);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: NNSpace.xs),
          child: Text(
            s.circleHint,
            style: NNType.footnote.copyWith(color: p.text2),
          ),
        ),
        SectionLabel(s.spending),
        if (plus)
          _Spending(group: g)
        else
          _Locked(
            key: const ValueKey('spending-locked'),
            label: s.plusFCharts,
            onTap: () async {
              await showPaywall(context, group: g);
              if (mounted) setState(() {});
            },
          ),
        const SizedBox(height: NNSpace.lg),
        Builder(
          builder: (ctx) => NNButton(
            key: const ValueKey('export-csv'),
            label: s.exportCsv,
            icon: Icons.file_download_rounded,
            kind: ButtonKind.plain,
            onTap: () => _csv(ctx),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: NNType.subhead.copyWith(color: p.danger),
              ),
            ),
          ),
      ],
    );
  }
}

/// A switch with its label and a line of explanation; locked ones say they are part of Plus.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.locked,
    required this.onChanged,
  });
  final String label;
  final String hint;
  final bool value;
  final bool locked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return NNCard(
      padding: const EdgeInsets.symmetric(
        horizontal: NNSpace.md,
        vertical: NNSpace.xs,
      ),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: NNType.body.copyWith(color: p.text)),
                  Text(
                    locked ? '$hint ${s.needsPlus}.' : hint,
                    style: NNType.footnote.copyWith(color: p.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NNSpace.xs),
            Switch.adaptive(
              value: value,
              activeTrackColor: p.accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label, ${s.needsPlus}',
      excludeChildSemantics: true,
      child: NNCard(
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: p.accent),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: NNType.callout.copyWith(color: p.text)),
                  Text(
                    s.needsPlus,
                    style: NNType.footnote.copyWith(
                      color: p.accent,
                      fontWeight: FontWeight.w600,
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

class _RecurringRow extends StatelessWidget {
  const _RecurringRow({
    required this.bill,
    required this.group,
    required this.onStop,
  });
  final RecurringBill bill;
  final GroupDetail group;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NNSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(categoryIcon(bill.category), size: 20, color: p.accent),
              const SizedBox(width: NNSpace.sm),
              Expanded(
                child: Text(
                  bill.title,
                  style: NNType.body.copyWith(color: p.text),
                ),
              ),
              Text(
                money(bill.amount, group.currency, s.lang),
                style: NNType.headline.copyWith(color: p.text),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 32, top: 2),
            child: Text(
              '${s.raw('every_${bill.every}')} · ${s.fill(s.nextOn, {'date': _day(context, bill.nextAt)})}',
              style: NNType.footnote.copyWith(color: p.text2),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: NNButton(
              label: s.stopRepeating,
              kind: ButtonKind.plain,
              expand: false,
              onTap: onStop,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bars for each category, then what each person paid. All in the group currency.
class _Spending extends StatelessWidget {
  const _Spending({required this.group});
  final GroupDetail group;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final g = group;
    final cats = spendingByCategory([
      for (final e in g.expenses) (expense: e.core, category: e.category),
    ], g.currency);
    final paid = [
      for (final m in g.members)
        (name: m.isMe ? s.you : m.name, amount: memberStats(g.core, m.id).paid),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    Widget bars(List<({String label, int amount})> rows, Color color) {
      final top = rows.isEmpty ? 1 : rows.first.amount.clamp(1, 1 << 52);
      return Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.label,
                            style: NNType.subhead.copyWith(color: p.text),
                          ),
                        ),
                        Text(
                          money(r.amount, g.currency, s.lang),
                          style: NNType.subhead.copyWith(
                            color: p.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(NNRadius.pill),
                      child: SizedBox(
                        height: 8,
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: (r.amount / top).clamp(0.02, 1.0),
                          child: ColoredBox(color: color),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return NNCard(
      key: const ValueKey('spending'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.byCategory,
            style: NNType.footnote.copyWith(
              color: p.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
          bars([
            for (final c in cats)
              (label: s.raw('cat_${c.category}'), amount: c.amount),
          ], p.accent),
          const SizedBox(height: NNSpace.sm),
          Text(
            s.byPerson,
            style: NNType.footnote.copyWith(
              color: p.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
          bars([
            for (final x in paid)
              if (x.amount > 0) (label: x.name, amount: x.amount),
          ], p.highlight),
        ],
      ),
    );
  }
}

/// A money circle at a glance: this round, who gets the pot, how many have paid, who is late.
/// A money circle on the group: the round, who gets the pot, who has paid in, and who is late.
/// The late pill pulses once when it appears; if more people become late while the group is open,
/// it pulses again with the warning haptic.
class CircleCard extends StatefulWidget {
  const CircleCard({
    super.key,
    required this.group,
    required this.circle,
    required this.onTap,
  });
  final GroupDetail group;
  final Circle circle;
  final VoidCallback onTap;

  @override
  State<CircleCard> createState() => _CircleCardState();
}

int _lateCount(Circle c) => c.currentRound?.late.length ?? 0;

class _CircleCardState extends State<CircleCard> {
  @override
  void didUpdateWidget(CircleCard old) {
    super.didUpdateWidget(old);
    if (_lateCount(widget.circle) > _lateCount(old.circle)) {
      haptic(Haptic.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final group = widget.group;
    final onTap = widget.onTap;
    final c = widget.circle;
    final r = c.currentRound;
    final status = switch (c.status) {
      'upcoming' => s.fill(s.circleUpcoming, {
        'date': _day(context, _fromIso(c.startOn)),
      }),
      'done' => s.circleDone,
      _ => s.circleRunning,
    };
    final late = r == null
        ? const <String>[]
        : [for (final id in r.late) group.nameOf(id)];
    final lines = <String>[
      if (r != null) ...[
        '${s.fill(s.circleRound, {'n': r.round + 1})} · ${r.receiver == group.me ? s.circleYouGet : s.fill(s.circleGets, {'name': group.nameOf(r.receiver)})}',
        '${s.fill(s.circlePaidN, {'paid': r.paid.length, 'total': c.turns.length - 1})} · ${s.fill(s.circleDue, {'date': _day(context, _fromIso(r.dueOn))})}',
      ],
    ];
    return Pressable(
      key: ValueKey('circle-${c.id}'),
      onTap: onTap,
      semanticLabel: [
        c.name,
        status,
        s.fill(s.circlePot, {'amount': money(c.pot, group.currency, s.lang)}),
        ...lines,
        if (late.isNotEmpty) '${s.late}: ${late.join(', ')}',
      ].join(', '),
      excludeChildSemantics: true,
      scale: 0.98,
      child: NNCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.donut_small_rounded, color: p.accent),
                const SizedBox(width: NNSpace.sm),
                Expanded(
                  child: Text(
                    c.name,
                    style: NNType.headline.copyWith(color: p.text),
                  ),
                ),
                Text(
                  s.fill(s.circlePot, {
                    'amount': money(c.pot, group.currency, s.lang),
                  }),
                  style: NNType.subhead.copyWith(
                    color: p.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NNSpace.xxs),
            Text(status, style: NNType.footnote.copyWith(color: p.text2)),
            for (final l in lines)
              Text(l, style: NNType.footnote.copyWith(color: p.text)),
            if (late.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: NNSpace.xs),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PulseOnce(
                    // A new pulse each time more people are late.
                    key: ValueKey('late-${late.length}'),
                    color: p.danger,
                    child: LatePill(
                      key: ValueKey('late-pill-${c.id}'),
                      text: '${s.late}: ${late.join(s.isRtl ? '، ' : ', ')}',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Late: red words on a soft red capsule.
class LatePill extends StatelessWidget {
  const LatePill({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: p.dangerSoft,
      ),
      child: Text(
        text,
        style: NNType.footnote.copyWith(
          color: p.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One circle: every round with its receiver, and a toggle per person for who has paid in.
Future<void> showCircleSheet(
  BuildContext context, {
  required GroupDetail group,
  required String circleId,
  required ValueChanged<GroupDetail> onChanged,
}) {
  final c = group.circles.firstWhere((c) => c.id == circleId);
  return showNNSheet<void>(
    context,
    key: const ValueKey('circle-sheet'),
    title: c.name,
    builder: (_) =>
        _CircleBody(group: group, circleId: circleId, onChanged: onChanged),
  );
}

class _CircleBody extends StatefulWidget {
  const _CircleBody({
    required this.group,
    required this.circleId,
    required this.onChanged,
  });
  final GroupDetail group;
  final String circleId;
  final ValueChanged<GroupDetail> onChanged;

  @override
  State<_CircleBody> createState() => _CircleBodyState();
}

class _CircleBodyState extends State<_CircleBody> {
  late GroupDetail g = widget.group;
  String? _error;
  bool _busy = false;

  Circle? get _c {
    for (final c in g.circles) {
      if (c.id == widget.circleId) return c;
    }
    return null;
  }

  Future<void> _toggle(int round, String memberId, bool paid) async {
    final session = SessionScope.read(context);
    setState(() => _busy = true);
    try {
      final d = await session.repo.took(
        await session.api.circlePaid(
          widget.circleId,
          round: round,
          memberId: memberId,
          paid: paid,
        ),
      );
      setState(() => g = d);
      widget.onChanged(d);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? session.s.offline : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final session = SessionScope.read(context);
    try {
      final d = await session.repo.took(
        await session.api.deleteCircle(widget.circleId),
      );
      widget.onChanged(d);
      if (mounted) Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    String name(String id) => id == g.me ? s.you : g.nameOf(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${s.fill(s.circlePot, {'amount': money(c.pot, g.currency, s.lang)})} · ${s.raw('every_${c.every}')}',
          style: NNType.callout.copyWith(color: p.text2),
        ),
        for (final r in c.rounds) ...[
          SectionLabel(
            '${s.fill(s.circleRound, {'n': r.round + 1})} · ${r.receiver == g.me ? s.circleYouGet : s.fill(s.circleGets, {'name': g.nameOf(r.receiver)})} · ${s.fill(s.circleDue, {'date': _day(context, _fromIso(r.dueOn))})}',
          ),
          NNCard(
            padding: const EdgeInsets.symmetric(
              horizontal: NNSpace.md,
              vertical: NNSpace.xxs,
            ),
            child: Column(
              children: [
                for (final m in c.turns)
                  if (m != r.receiver)
                    _PaidToggle(
                      key: ValueKey('circle-paid-${r.round}-$m'),
                      label: name(m),
                      avatarName: g.nameOf(m),
                      look: g.member(m)?.avatar,
                      late: r.late.contains(m),
                      paid: r.paid.contains(m),
                      onChanged: _busy ? null : (v) => _toggle(r.round, m, v),
                    ),
              ],
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.sm),
            child: Text(
              _error!,
              style: NNType.subhead.copyWith(color: p.danger),
            ),
          ),
        const SizedBox(height: NNSpace.lg),
        Text(s.circleHint, style: NNType.footnote.copyWith(color: p.text2)),
        const SizedBox(height: NNSpace.md),
        NNButton(
          key: const ValueKey('delete-circle'),
          label: s.deleteCircle,
          kind: ButtonKind.danger,
          onTap: _delete,
        ),
      ],
    );
  }
}

/// Whether someone has paid in this round. When they are marked paid the check draws itself
/// (300 ms) with the success haptic.
class _PaidToggle extends StatefulWidget {
  const _PaidToggle({
    super.key,
    required this.label,
    required this.avatarName,
    this.look,
    required this.late,
    required this.paid,
    required this.onChanged,
  });
  final String label;
  final String avatarName;
  final AvatarLook? look;
  final bool late;
  final bool paid;
  final ValueChanged<bool>? onChanged;

  @override
  State<_PaidToggle> createState() => _PaidToggleState();
}

class _PaidToggleState extends State<_PaidToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.paid ? 1 : 0,
  );

  @override
  void didUpdateWidget(_PaidToggle old) {
    super.didUpdateWidget(old);
    if (widget.paid && !old.paid) {
      haptic(Haptic.success);
      if (reduceMotion(context)) {
        _draw.value = 1;
      } else {
        _draw.forward(from: 0);
      }
    } else if (!widget.paid) {
      _draw.value = 0;
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final label = widget.label;
    final late = widget.late;
    final paid = widget.paid;
    final onChanged = widget.onChanged;
    return Pressable(
      onTap: onChanged == null ? null : () => onChanged(!paid),
      checked: paid,
      semanticLabel: [
        s.fill(s.markMemberPaid, {'name': label}),
        if (late && !paid) s.late,
      ].join(', '),
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Avatar(name: widget.avatarName, look: widget.look, size: 28),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Text(label, style: NNType.body.copyWith(color: p.text)),
            ),
            if (late && !paid)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: NNSpace.xs),
                child: PulseOnce(
                  color: p.danger,
                  child: LatePill(text: s.late),
                ),
              ),
            if (paid)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.all(1),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  shape: const CircleBorder(),
                  color: p.success,
                ),
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (context, _) => DrawnCheck(
                    progress: Curves.easeOutCubic.transform(_draw.value),
                    color: p.surface,
                    size: 18,
                    stroke: 2.4,
                  ),
                ),
              )
            else
              Icon(
                Icons.radio_button_unchecked_rounded,
                color: p.text3,
                size: 26,
              ),
          ],
        ),
      ),
    );
  }
}

/// A new money circle: what each person pays, how often, when it starts, and the order of turns.
Future<GroupDetail?> showNewCircleSheet(
  BuildContext context, {
  required GroupDetail group,
}) {
  return showNNSheet<GroupDetail>(
    context,
    key: const ValueKey('new-circle-sheet'),
    title: context.s.newCircle,
    builder: (_) => _NewCircle(group: group),
  );
}

class _NewCircle extends StatefulWidget {
  const _NewCircle({required this.group});
  final GroupDetail group;

  @override
  State<_NewCircle> createState() => _NewCircleState();
}

class _NewCircleState extends State<_NewCircle> {
  late final GroupDetail g = widget.group;
  final _name = TextEditingController();
  final _amount = TextEditingController();
  String _every = 'month';
  DateTime _start = DateTime.now();
  final _order = <String>[];
  String? _error;

  /// Goes up with every error: the field or message shakes, with the error haptic.
  int _shakes = 0;

  void _fail(String message) => setState(() {
    _error = message;
    _shakes++;
  });
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDateSheet(
      context,
      title: context.s.circleStart,
      initial: _start,
      first: DateTime.now().subtract(const Duration(days: 365)),
      last: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null && mounted) setState(() => _start = d);
  }

  Future<void> _create() async {
    final session = SessionScope.read(context);
    final s = session.s;
    final amount = parseAmount(_amount.text, g.currency);
    final name = _name.text.trim().isEmpty ? s.circleNamePh : _name.text.trim();
    if (amount == null) {
      _fail(s.errAmount);
      return;
    }
    if (_order.length < 2) {
      _fail(s.circleNeedTwo);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await session.repo.took(
        await session.api.createCircle(
          g.id,
          name: name,
          amount: amount,
          every: _every,
          startOn: _isoDay(_start),
          turns: _order,
        ),
      );
      if (mounted) Navigator.of(context).pop(d);
    } on ApiException catch (e) {
      if (mounted) _fail(e.offline ? s.offline : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final pot = (parseAmount(_amount.text, g.currency) ?? 0) * _order.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NNField(
          label: s.circleName,
          hint: s.circleNamePh,
          controller: _name,
          fieldKey: const ValueKey('circle-name'),
        ),
        SectionLabel(s.circleEach),
        TextField(
          key: const ValueKey('circle-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: minorToInput(0, g.currency),
            suffixText: g.currency,
          ),
        ),
        SectionLabel(s.circleEvery),
        Segmented<String>(
          values: const ['week', 'month'],
          selected: _every,
          label: (v) => s.raw('every_$v'),
          onChanged: (v) => setState(() => _every = v),
        ),
        SectionLabel(s.circleStart),
        NNButton(
          key: const ValueKey('circle-start'),
          label: _day(context, _start),
          icon: Icons.event_rounded,
          kind: ButtonKind.plain,
          onTap: _pickDate,
        ),
        SectionLabel(s.circleOrder),
        Wrap(
          spacing: NNSpace.xs,
          runSpacing: NNSpace.xs,
          children: [
            for (final m in g.members)
              NNChip(
                key: ValueKey('turn-${m.id}'),
                label: _order.contains(m.id)
                    ? '${_order.indexOf(m.id) + 1}. ${m.isMe ? s.you : m.name}'
                    : (m.isMe ? s.you : m.name),
                selected: _order.contains(m.id),
                onTap: () => setState(
                  () => _order.contains(m.id)
                      ? _order.remove(m.id)
                      : _order.add(m.id),
                ),
              ),
          ],
        ),
        if (pot > 0)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.sm),
            child: Text(
              s.fill(s.circlePot, {'amount': money(pot, g.currency, s.lang)}),
              style: NNType.subhead.copyWith(color: p.text2),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.sm),
            child: ErrorText(_error!, shake: _shakes),
          ),
        const SizedBox(height: NNSpace.md),
        Text(s.circleHint, style: NNType.footnote.copyWith(color: p.text2)),
        const SizedBox(height: NNSpace.lg),
        NNButton(
          key: const ValueKey('create-circle'),
          label: s.createCircle,
          busy: _busy,
          onTap: _create,
        ),
      ],
    );
  }
}
