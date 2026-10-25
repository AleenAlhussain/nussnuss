import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/services.dart';
import '../data/session.dart';
import '../design/coin.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';

/// Test builds can unlock without a store when the server allows it (--dart-define=DEV_PURCHASES=true).
const _devPurchases = bool.fromEnvironment('DEV_PURCHASES');

/// Opens NussNuss Plus. From a group it also offers that group's Trip Pass; from Settings > Look it
/// also offers that one look. Returns whether the thing asked for is now unlocked.
Future<bool> showPaywall(
  BuildContext context, {
  GroupDetail? group,
  String? look,
}) async {
  final session = SessionScope.read(context);
  await showNNSheet<void>(
    context,
    key: const ValueKey('paywall'),
    title: session.s.plus,
    builder: (_) => _Paywall(group: group, look: look),
  );
  return look != null ? session.plan.ownsLook(look) : session.hasPlus(group);
}

class _Paywall extends StatefulWidget {
  const _Paywall({this.group, this.look});
  final GroupDetail? group;
  final String? look;

  @override
  State<_Paywall> createState() => _PaywallState();
}

class _PaywallState extends State<_Paywall> {
  Map<String, StoreProduct>? _products;
  late String _pick = widget.look != null
      ? 'nussnuss.look.${widget.look}'
      : Products.plusYearly;
  bool _busy = false;
  String? _error;

  List<String> get _options => [
    Products.plusYearly,
    Products.plusMonthly,
    if (widget.group != null) Products.tripPass,
    if (widget.look != null) 'nussnuss.look.${widget.look}',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await SessionScope.read(
      context,
    ).purchases.products(Products.all);
    if (mounted) setState(() => _products = {for (final p in list) p.id: p});
  }

  String? get _groupFor => _pick == Products.tripPass ? widget.group?.id : null;

  Future<void> _buy() async {
    final session = SessionScope.read(context);
    final product = _products?[_pick];
    if (product == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final plan = await session.buy(product, groupId: _groupFor);
    if (!mounted) return;
    setState(() => _busy = false);
    if (plan != null) _done();
  }

  Future<void> _devBuy() async {
    final session = SessionScope.read(context);
    setState(() => _busy = true);
    try {
      await session.devBuy(_pick, groupId: _groupFor);
      if (mounted) _done();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    // The toast floats above everything, so it stays after the paywall closes.
    showToast(context, context.s.plusThanks);
    Navigator.of(context).maybePop();
  }

  String _name(String id) {
    final s = context.s;
    return switch (id) {
      Products.plusYearly => s.planYearly,
      Products.plusMonthly => s.planMonthly,
      Products.tripPass => s.tripPass,
      _ => s.raw('look_${id.split('.').last}'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    final products = _products;
    final features = [
      (Icons.event_repeat_rounded, s.plusFRecurring),
      (Icons.notifications_active_rounded, s.plusFReminders),
      (Icons.currency_exchange_rounded, s.plusFRates),
      (Icons.donut_large_rounded, s.plusFCharts),
      (Icons.receipt_long_rounded, s.plusFItems),
      (Icons.file_download_rounded, s.plusFExport),
      (Icons.palette_rounded, s.plusFLooks),
    ];
    final until = session.plan.plusUntil;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Coin(size: 64, join: 1)),
        const SizedBox(height: NNSpace.sm),
        Text(
          s.plusTagline,
          textAlign: TextAlign.center,
          style: NNType.title3.copyWith(color: p.text),
        ),
        if (session.plan.plus && until != null) ...[
          const SizedBox(height: NNSpace.xs),
          Text(
            s.fill(s.plusOnUntil, {
              'date': MaterialLocalizations.of(context).formatMediumDate(until),
            }),
            textAlign: TextAlign.center,
            style: NNType.subhead.copyWith(color: p.success),
          ),
        ],
        const SizedBox(height: NNSpace.md),
        NNCard(
          child: Column(
            children: [
              for (final f in features)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
                  child: Row(
                    children: [
                      Icon(f.$1, size: 22, color: p.accent),
                      const SizedBox(width: NNSpace.sm),
                      Expanded(
                        child: Text(
                          f.$2,
                          style: NNType.callout.copyWith(color: p.text),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NNSpace.md),
        for (final id in _options)
          Padding(
            padding: const EdgeInsets.only(bottom: NNSpace.xs),
            child: _Option(
              key: ValueKey('plan-$id'),
              name: _name(id),
              price: products?[id]?.price,
              note: switch (id) {
                Products.plusYearly => s.planYearlySave,
                Products.tripPass => s.tripPassBody,
                _ => null,
              },
              selected: _pick == id,
              onTap: () => setState(() => _pick = id),
            ),
          ),
        if (products != null && products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
            child: Text(
              s.storeSoon,
              key: const ValueKey('store-soon'),
              textAlign: TextAlign.center,
              style: NNType.footnote.copyWith(color: p.text2),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.xs),
            child: Text(
              _error!,
              style: NNType.subhead.copyWith(color: p.danger),
            ),
          ),
        const SizedBox(height: NNSpace.sm),
        NNButton(
          key: const ValueKey('buy'),
          label: s.buy,
          busy: _busy,
          onTap: products?[_pick] == null ? null : _buy,
        ),
        const SizedBox(height: NNSpace.xs),
        NNButton(
          key: const ValueKey('restore'),
          label: s.restore,
          kind: ButtonKind.plain,
          onTap: _busy ? null : () => session.restore(),
        ),
        if (_devPurchases) ...[
          const SizedBox(height: NNSpace.xs),
          NNButton(
            key: const ValueKey('dev-buy'),
            label: s.devBuy,
            kind: ButtonKind.tinted,
            onTap: _busy ? null : _devBuy,
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: NNSpace.sm),
          child: Text(
            s.cancelAnytime,
            textAlign: TextAlign.center,
            style: NNType.footnote.copyWith(color: p.text2),
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.name,
    required this.price,
    required this.note,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final String? price;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: [name, ?price, ?note].join(', '),
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.98,
      child: AnimatedContainer(
        duration: NNMotion.fade,
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(
          horizontal: NNSpace.md,
          vertical: NNSpace.sm,
        ),
        decoration: ShapeDecoration(
          color: selected ? p.accentSoft : p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NNRadius.row),
            side: BorderSide(
              color: selected ? p.accent : p.separator,
              width: selected ? 2 : 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? p.accent : p.text3,
            ),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: NNType.headline.copyWith(
                      color: selected ? p.onAccentSoft : p.text,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: NNType.footnote.copyWith(
                        color: selected ? p.onAccentSoft : p.text2,
                      ),
                    ),
                ],
              ),
            ),
            if (price != null)
              Text(
                price!,
                style: NNType.headline.copyWith(
                  color: selected ? p.onAccentSoft : p.text,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
