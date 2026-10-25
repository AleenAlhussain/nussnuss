import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
import 'expense_sheet.dart';
import 'group_options.dart';
import 'group_sheets.dart';
import 'summary_card.dart';

enum _Tab { expenses, settle }

/// One group: what you owe or get back, every expense by day, and the settle-up plan.
/// Friends' changes arrive live (server-sent events), with a slow poll as a fallback; with no
/// connection it shows the copy on this device and keeps what you add until it can send it.
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
  StreamSubscription<int>? _live;
  late final Session _session = SessionScope.read(context);
  int _pending = 0;

  Api get _api => _session.api;

  @override
  void initState() {
    super.initState();
    _g = widget.initial;
    WidgetsBinding.instance.addObserver(this);
    _session.repo.addListener(_onQueue);
    _pending = _session.repo.pendingFor(widget.groupId);
    _start();
  }

  Future<void> _start() async {
    if (_g == null) {
      final cached = await _session.repo.cachedGroup(widget.groupId);
      if (mounted && cached != null && _g == null) setState(() => _g = cached);
    }
    await _load();
    _listen();
  }

  void _listen() {
    final live = _session.live;
    if (live == null) {
      _startPoll();
      return;
    }
    _live = live(widget.groupId).listen(
      (v) {
        _poll?.cancel();
        _poll = null;
        if (v != _g?.version) _load();
      },
      // The stream reconnects by itself; meanwhile a slow poll keeps things fresh.
      onError: (Object _) => _startPoll(),
    );
  }

  void _startPoll() {
    _poll ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkForChanges(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    _session.repo.removeListener(_onQueue);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onQueue() {
    final n = _session.repo.pendingFor(widget.groupId);
    if (n == _pending) return;
    final synced = n < _pending;
    setState(() => _pending = n);
    if (synced) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_session.repo.sync());
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final g = await _session.repo.group(widget.groupId);
      if (mounted) {
        setState(() {
          _g = g;
          _error = null;
        });
      }
      if (_session.repo.pendingFor(widget.groupId) > 0) {
        unawaited(_session.repo.sync());
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? _session.s.offline : e.message);
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
    _session.touch();
  }

  void _toast(String message, {Future<GroupDetail> Function()? undo}) {
    final s = _session.s;
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

  Future<void> _addOrEdit({Expense? e, Rect? origin}) async {
    final g = _g;
    if (g == null) return;
    final r = await showExpenseSheet(
      context,
      group: g,
      editing: e,
      origin: origin,
    );
    if (r == null || !mounted) return;
    _apply(r.detail);
    final deleted = r.deletedId;
    final s = _session.s;
    if (deleted != null) {
      _toast(
        r.queued ? '${s.deleted}. ${s.savedOffline}' : s.deleted,
        undo: () async => r.queued
            ? _session.repo.cancelPending(r.detail, deleted)
            : _session.repo.took(await _api.restoreExpense(deleted)),
      );
    } else if (r.queued) {
      _toast(s.savedOffline);
    }
  }

  /// Long-press on +: the last expense again, now. Covers rent, coffee and the daily taxi.
  Future<void> _repeatLast() async {
    final g = _g;
    if (g == null || g.expenses.isEmpty) {
      return _addOrEdit();
    }
    final last = g.expenses.first;
    final input = ExpenseInput(
      id: newId(),
      title: last.title,
      amount: last.amount,
      paidBy: g.member(last.paidBy) != null ? last.paidBy : g.me,
      mode: last.mode,
      items: last.items,
      category: last.category,
      currency: last.currency == g.currency ? null : last.currency,
      rate: last.currency == g.currency ? null : last.rate,
    );
    try {
      final r = await _session.repo.saveExpense(g, input, editing: false);
      if (!mounted) return;
      _apply(r.detail);
      _session.click();
      final s = _session.s;
      _toast(
        r.queued ? '${s.repeated}. ${s.savedOffline}' : s.repeated,
        undo: () async =>
            (await _session.repo.deleteExpense(r.detail, input.id)).detail,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _markPaid(Transfer t) async {
    final g = _g;
    if (g == null) return;
    try {
      final r = await _session.repo.pay(g, t);
      if (!mounted) return;
      _apply(r.detail);
      haptic(Haptic.success);
      final s = _session.s;
      _toast(
        r.queued ? '${s.paidRecorded}. ${s.savedOffline}' : s.paidRecorded,
        undo: () async => r.queued
            ? _session.repo.cancelPending(r.detail, r.id)
            : _session.repo.took(await _api.unpay(r.id)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remind(Transfer t) async {
    final g = _g!;
    final s = _session.s;
    final text = s.fill(s.remindMessage, {
      'name': g.nameOf(t.from),
      'amount': money(t.amount, g.currency, s.lang),
      'group': g.name,
    });
    final opened = await _session.device.open(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
    );
    if (!opened) await _session.device.share(text: text);
  }

  Future<void> _payWith(Transfer t, PayTo p) async {
    final g = _g!;
    final s = _session.s;
    final method = p.label?.isNotEmpty == true
        ? p.label!
        : s.raw('pay_${p.kind}');
    final action = payAction(p, t.amount, g.currency);
    Future<void> copy(String text) async {
      await _session.device.copy(text);
      haptic(Haptic.success);
      if (mounted) {
        _toast('${s.fill(s.payCopied, {'method': method})} ${s.payThenMark}');
      }
    }

    switch (action) {
      case PayOpen(:final url):
        final ok = await _session.device.open(Uri.parse(url));
        if (!ok) {
          await copy(url);
        } else if (mounted) {
          _toast(s.payThenMark);
        }
      case PayCopy(:final text):
        await copy(text);
    }
  }

  Future<void> _options() async {
    final g = _g;
    if (g == null) return;
    await showGroupOptions(context, group: g, onChanged: _apply);
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
          SliverToBoxAdapter(
            child: _error == null
                ? Padding(
                    padding: const EdgeInsets.only(top: NNSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(
                          label: s.loading,
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Bone(width: 110),
                              SizedBox(height: NNSpace.sm),
                              Bone(width: 220, height: 48, radius: 12),
                              SizedBox(height: NNSpace.sm),
                              Bone(width: 160, height: 12),
                            ],
                          ),
                        ),
                        const SizedBox(height: NNSpace.xl),
                        SkeletonRows(
                          label: s.loading,
                          count: 4,
                          separate: false,
                        ),
                      ],
                    ),
                  )
                : EmptyState(
                    title: s.error,
                    body: _error!,
                    art: const Coin(size: 64, join: 0),
                  ),
          ),
        ],
      );
    }

    final last = g.expenses.isEmpty ? null : g.expenses.first;
    return NNPage(
      key: const ValueKey('group'),
      title: '${g.emoji} ${g.name}'.trim(),
      leading: back,
      actions: [
        GlassIconButton(
          key: const ValueKey('share'),
          icon: Icons.person_add_alt_1_rounded,
          label: s.share,
          onTap: () => showShareSheet(context, g),
        ),
        GlassIconButton(
          key: const ValueKey('more'),
          icon: Icons.more_horiz_rounded,
          label: s.groupMore,
          onTap: _options,
        ),
      ],
      onRefresh: _load,
      bottom: Row(
        children: [
          const Spacer(),
          AddButton(
            label: s.addExpense,
            onTap: (origin) => _addOrEdit(origin: origin),
            onLongPress: last == null ? null : _repeatLast,
            longPressLabel: last == null
                ? null
                : s.fill(s.repeatLast, {'title': last.title}),
          ),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(child: _BalanceHero(group: g)),
        if (_pending > 0)
          SliverToBoxAdapter(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _PendingPill(count: _pending),
            ),
          ),
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
        for (final c in g.circles)
          if (c.status != 'done')
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: NNSpace.md),
                child: CircleCard(
                  group: g,
                  circle: c,
                  onTap: () => showCircleSheet(
                    context,
                    group: g,
                    circleId: c.id,
                    onChanged: _apply,
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
    final p = NNTheme.of(context).palette;
    if (g.expenses.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            title: s.noExpensesTitle,
            body: '${s.noExpensesBody} ${s.repeatHint}',
            art: const Coin(size: 72),
          ),
        ),
      ];
    }
    // One continuous list: a day heading, then that day's expenses, with air between days.
    final rows = <Object>[];
    DateTime? day;
    for (final e in g.expenses) {
      final k = dayKey(e.spentAt);
      if (k != day) {
        rows.add(k);
        day = k;
      }
      rows.add(e);
    }
    return [
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          if (r is DateTime) return SectionLabel(dayLabel(r, s));
          final e = r as Expense;
          final nextIsRow = i + 1 < rows.length && rows[i + 1] is Expense;
          return Column(
            children: [
              _ExpenseRow(
                group: g,
                e: e,
                onTap: () => _addOrEdit(e: e),
              ),
              if (nextIsRow)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 52,
                  color: p.separator,
                ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _settle(GroupDetail g) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final share = Builder(
      builder: (ctx) => NNButton(
        key: const ValueKey('share-summary'),
        label: s.shareSummary,
        icon: Icons.ios_share_rounded,
        kind: ButtonKind.tinted,
        onTap: () => shareSummary(ctx, g, origin: originOf(ctx)),
      ),
    );
    if (g.transfers.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SettledMoment(title: s.allSettled, body: s.allSettledBody),
        ),
        SliverToBoxAdapter(child: share),
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
            onRemind: t.to == g.me ? () => _remind(t) : null,
            payTo: t.from == g.me
                ? g.member(t.to)?.payTo ?? const []
                : const [],
            onPayWith: (p) => _payWith(t, p),
          );
        },
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: NNSpace.md),
          child: share,
        ),
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

class _PendingPill extends StatelessWidget {
  const _PendingPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('pending'),
        margin: const EdgeInsets.only(top: NNSpace.sm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: p.accentSoft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 16, color: p.onAccentSoft),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                s.fill(s.pendingN, {'n': count}),
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

/// The balance first and large, on the page itself: no box around it, plenty of air.
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
    return Padding(
      padding: const EdgeInsets.only(top: NNSpace.xs, bottom: NNSpace.xs),
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
              child: RollingText(
                money(b.abs(), group.currency, s.lang),
                key: const ValueKey('my-balance'),
                style: NNType.amountHero.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
      semanticLabel: [
        e.title,
        amount,
        sub,
        if (e.pending) s.savedOffline,
      ].join(', '),
      excludeChildSemantics: true,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NNSpace.sm),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
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
            if (e.pending)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 16,
                  color: p.text2,
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.42,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  amount,
                  style: NNType.headline.copyWith(
                    color: p.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// Swipe toward the person being paid to mark it as paid, or use the button. Undo lives in the toast.
/// When they owe you there is a Remind button; when you owe someone who shared how to pay them,
/// there is one button per way.
class _TransferCard extends StatelessWidget {
  const _TransferCard({
    super.key,
    required this.group,
    required this.t,
    required this.onPaid,
    required this.onRemind,
    required this.payTo,
    required this.onPayWith,
  });
  final GroupDetail group;
  final Transfer t;
  final VoidCallback onPaid;
  final VoidCallback? onRemind;
  final List<PayTo> payTo;
  final ValueChanged<PayTo> onPayWith;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final sentence = transferText(t, me: group.me, nameOf: group.nameOf, s: s);
    final amount = money(t.amount, group.currency, s.lang);
    String method(PayTo x) =>
        x.label?.isNotEmpty == true ? x.label! : s.raw('pay_${x.kind}');
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
        label: '$sentence, $amount',
        customSemanticsActions: {
          CustomSemanticsAction(label: s.markPaid): onPaid,
        },
        child: NNCard(
          // The buttons sit under the words, so long names, Arabic and large text never squeeze them.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Avatar(
                    name: group.nameOf(t.from == group.me ? t.to : t.from),
                  ),
                  const SizedBox(width: NNSpace.sm),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            transferSpan(
                              t,
                              me: group.me,
                              nameOf: group.nameOf,
                              s: s,
                              soft: p.text2,
                            ),
                            style: NNType.callout.copyWith(color: p.text),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              amount,
                              style: NNType.title3.copyWith(
                                color: p.text,
                                fontFamily: nnDisplayFamily,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (payTo.isNotEmpty) ...[
                const SizedBox(height: NNSpace.sm),
                Wrap(
                  spacing: NNSpace.xs,
                  runSpacing: NNSpace.xs,
                  children: [
                    for (var i = 0; i < payTo.length; i++)
                      NNChip(
                        key: ValueKey('pay-with-$i'),
                        label: s.fill(s.payWith, {'method': method(payTo[i])}),
                        icon: Icons.account_balance_wallet_outlined,
                        selected: false,
                        onTap: () => onPayWith(payTo[i]),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: NNSpace.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: NNSpace.xs,
                runSpacing: NNSpace.xs,
                children: [
                  if (onRemind != null)
                    NNButton(
                      key: const ValueKey('remind'),
                      label: s.remind,
                      icon: Icons.chat_bubble_outline_rounded,
                      kind: ButtonKind.plain,
                      expand: false,
                      onTap: onRemind,
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
    // Name and balance share the row; either wraps rather than overflowing at large text sizes.
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
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
              const SizedBox(width: NNSpace.xs),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.end,
                  style: NNType.subhead.copyWith(
                    color: b > 0 ? p.success : (b < 0 ? p.danger : p.text2),
                    fontWeight: FontWeight.w600,
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
