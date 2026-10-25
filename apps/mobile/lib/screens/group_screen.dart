import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../core/types.dart';
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
import 'expense_sheet.dart';
import 'group_sheets.dart';

enum _Tab { expenses, settle }

/// One group: what you owe or get back, every expense by day, and the settle-up plan.
/// Polls for changes from friends every few seconds while open, and on coming back to the app.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.groupId, this.initial});
  final String groupId;
  final GroupDetail? initial;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with WidgetsBindingObserver {
  GroupDetail? _g;
  String? _error;
  _Tab _tab = _Tab.expenses;
  Timer? _poll;

  Api get _api => SessionScope.read(context).api;

  @override
  void initState() {
    super.initState();
    _g = widget.initial;
    WidgetsBinding.instance.addObserver(this);
    _load();
    _poll = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _checkForChanges(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final g = await _api.group(widget.groupId);
      if (mounted) {
        setState(() {
          _g = g;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? context.s.offline : e.message);
      }
    }
  }

  Future<void> _checkForChanges() async {
    final g = _g;
    if (g == null || !mounted) return;
    try {
      final v = await _api.version(g.id, g.version);
      if (v != g.version) await _load();
    } on ApiException {
      // Quietly try again on the next tick.
    }
  }

  void _apply(GroupDetail g) {
    setState(() => _g = g);
    SessionScope.read(context).touch();
  }

  void _toast(String message, {Future<GroupDetail> Function()? undo}) {
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('toast'),
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: undo == null
            ? null
            : SnackBarAction(
                label: s.undo,
                onPressed: () async {
                  try {
                    final g = await undo();
                    if (mounted) _apply(g);
                  } on ApiException catch (e) {
                    if (mounted) setState(() => _error = e.message);
                  }
                },
              ),
      ),
    );
  }

  Future<void> _addOrEdit([Expense? e]) async {
    final g = _g;
    if (g == null) return;
    final r = await showExpenseSheet(context, group: g, editing: e);
    if (r == null || !mounted) return;
    _apply(r.detail);
    final deleted = r.deletedId;
    if (deleted != null) {
      _toast(context.s.deleted, undo: () => _api.restoreExpense(deleted));
    }
  }

  Future<void> _markPaid(Transfer t) async {
    final g = _g;
    if (g == null) return;
    try {
      final r = await _api.pay(g.id, t);
      if (!mounted) return;
      _apply(r.detail);
      haptic(Haptic.success);
      _toast(context.s.paidRecorded, undo: () => _api.unpay(r.id));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? context.s.offline : e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final g = _g;
    final back = Navigator.of(context).canPop()
        ? GlassIconButton(
            icon: Icons.adaptive.arrow_back_rounded,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          )
        : null;

    if (g == null) {
      return NNPage(
        title: '',
        leading: back,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: _error == null
                  ? const CircularProgressIndicator.adaptive()
                  : EmptyState(
                      title: s.error,
                      body: _error!,
                      art: const Coin(size: 64, join: 0),
                    ),
            ),
          ),
        ],
      );
    }

    return NNPage(
      key: const ValueKey('group'),
      title: '${g.emoji} ${g.name}'.trim(),
      leading: back,
      actions: [
        GlassIconButton(
          key: const ValueKey('share'),
          icon: Icons.ios_share_rounded,
          label: s.share,
          onTap: () => showShareSheet(context, g),
        ),
      ],
      onRefresh: _load,
      bottom: Row(
        children: [
          const Spacer(),
          AddButton(label: s.addExpense, onTap: _addOrEdit),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(child: _BalanceHero(group: g)),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: NNSpace.sm),
              child: Text(
                _error!,
                style: NNType.footnote.copyWith(
                  color: NNTheme.of(context).palette.danger,
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NNSpace.lg),
            child: Segmented<_Tab>(
              values: _Tab.values,
              selected: _tab,
              label: (t) => t == _Tab.expenses ? s.expenses : s.settleUp,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
        ),
        if (_tab == _Tab.expenses) ..._expenses(g) else ..._settle(g),
      ],
    );
  }

  List<Widget> _expenses(GroupDetail g) {
    final s = context.s;
    if (g.expenses.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            title: s.noExpensesTitle,
            body: s.noExpensesBody,
            art: const Coin(size: 72),
          ),
        ),
      ];
    }
    final days = <DateTime, List<Expense>>{};
    for (final e in g.expenses) {
      days.putIfAbsent(dayKey(e.spentAt), () => []).add(e);
    }
    return [
      for (final entry in days.entries)
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(dayLabel(entry.key, s)),
              NNCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < entry.value.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 64,
                          color: NNTheme.of(context).palette.separator,
                        ),
                      _ExpenseRow(
                        group: g,
                        e: entry.value[i],
                        onTap: () => _addOrEdit(entry.value[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _settle(GroupDetail g) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    if (g.transfers.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SettledMoment(title: s.allSettled, body: s.allSettledBody),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: NNSpace.xxs,
            bottom: NNSpace.xs,
          ),
          child: Text(
            s.swipeHint,
            style: NNType.footnote.copyWith(color: p.text2),
          ),
        ),
      ),
      SliverList.separated(
        itemCount: g.transfers.length,
        separatorBuilder: (_, _) => const SizedBox(height: NNSpace.xs),
        itemBuilder: (context, i) {
          final t = g.transfers[i];
          return _TransferCard(
            key: ValueKey('transfer-${t.from}-${t.to}-${t.amount}'),
            group: g,
            t: t,
            onPaid: () => _markPaid(t),
          );
        },
      ),
      SliverToBoxAdapter(child: SectionLabel(s.people)),
      SliverToBoxAdapter(
        child: NNCard(
          padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
          child: Column(
            children: [
              for (var i = 0; i < g.members.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 0.5, color: p.separator),
                _BalanceRow(group: g, m: g.members[i]),
              ],
            ],
          ),
        ),
      ),
    ];
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.group});
  final GroupDetail group;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final b = group.myBalance;
    final label = b > 0 ? s.youAreOwed : (b < 0 ? s.youOwe : s.allSettled);
    final color = b > 0 ? p.success : (b < 0 ? p.danger : p.text);
    return NNCard(
      padding: const EdgeInsets.all(NNSpace.lg),
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: NNType.subhead.copyWith(
                color: p.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: NNSpace.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: b.abs().toDouble()),
                duration: reduceMotion(context)
                    ? Duration.zero
                    : NNMotion.gentleDuration,
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  money(v.round(), group.currency, s.lang),
                  key: const ValueKey('my-balance'),
                  style: NNType.amountHero.copyWith(
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: NNSpace.xs),
            Text(
              '${s.total} · ${money(group.total, group.currency, s.lang)}',
              key: const ValueKey('group-total'),
              style: NNType.footnote.copyWith(color: p.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.group,
    required this.e,
    required this.onTap,
  });
  final GroupDetail group;
  final Expense e;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final payer = e.paidBy == group.me ? s.you : group.nameOf(e.paidBy);
    final people = e.items.where((i) => i.value > 0).length;
    final amount = money(e.amount, e.currency, s.lang);
    final sub =
        '${s.fill(s.paidByName, {'name': payer})} · ${people == group.members.length ? s.everyone : s.fill(s.forN, {'n': people})}';
    return Pressable(
      key: ValueKey('expense-${e.id}'),
      onTap: onTap,
      semanticLabel: '${e.title}, $amount, $sub',
      excludeChildSemantics: true,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NNSpace.md,
          vertical: NNSpace.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: ShapeDecoration(
                shape: const CircleBorder(),
                color: p.accentSoft,
              ),
              child: Icon(
                categoryIcon(e.category),
                size: 20,
                color: p.onAccentSoft,
              ),
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
                    style: NNType.body.copyWith(color: p.text),
                  ),
                  Text(
                    sub,
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
              style: NNType.headline.copyWith(
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

/// Swipe toward the person being paid to mark it as paid, or use the button. Undo lives in the toast.
class _TransferCard extends StatelessWidget {
  const _TransferCard({
    super.key,
    required this.group,
    required this.t,
    required this.onPaid,
  });
  final GroupDetail group;
  final Transfer t;
  final VoidCallback onPaid;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final from = t.from == group.me ? s.you : group.nameOf(t.from);
    final to = t.to == group.me ? s.you : group.nameOf(t.to);
    final amount = money(t.amount, group.currency, s.lang);
    return Dismissible(
      key: ValueKey('swipe-${t.from}-${t.to}-${t.amount}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        onPaid();
        return false;
      },
      background: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: NNSpace.lg),
        decoration: BoxDecoration(
          color: p.success,
          borderRadius: BorderRadius.circular(NNRadius.card),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: p.surface),
            const SizedBox(width: NNSpace.xs),
            Text(s.markPaid, style: NNType.headline.copyWith(color: p.surface)),
          ],
        ),
      ),
      child: Semantics(
        container: true,
        label: '$from ${s.pays} $to, $amount',
        customSemanticsActions: {
          CustomSemanticsAction(label: s.markPaid): onPaid,
        },
        child: NNCard(
          child: Row(
            children: [
              Avatar(name: group.nameOf(t.from)),
              const SizedBox(width: NNSpace.xs),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: from,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: ' ${s.pays} ',
                              style: TextStyle(color: p.text2),
                            ),
                            TextSpan(
                              text: to,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        style: NNType.callout.copyWith(color: p.text),
                      ),
                      Text(
                        amount,
                        style: NNType.title3.copyWith(
                          color: p.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              NNButton(
                key: const ValueKey('mark-paid'),
                label: s.markPaid,
                kind: ButtonKind.tinted,
                expand: false,
                onTap: onPaid,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.group, required this.m});
  final GroupDetail group;
  final Member m;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final b = group.balances[m.id] ?? 0;
    final text = b > 0
        ? s.fill(s.getsBack, {'amount': money(b, group.currency, s.lang)})
        : b < 0
        ? s.fill(s.owes, {'amount': money(-b, group.currency, s.lang)})
        : s.even;
    return MergeSemantics(
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Avatar(name: m.name, size: 32),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Text(
                m.isMe ? s.you : m.name,
                style: NNType.body.copyWith(color: p.text),
              ),
            ),
            Text(
              text,
              style: NNType.subhead.copyWith(
                color: b > 0 ? p.success : (b < 0 ? p.danger : p.text2),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
