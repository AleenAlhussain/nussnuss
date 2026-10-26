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
import 'group_sheets.dart' show webUrl;

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
    final benefits = [
      (Icons.event_repeat_rounded, s.plusB1T, s.plusB1B),
      (Icons.receipt_long_rounded, s.plusB2T, s.plusB2B),
      (Icons.palette_rounded, s.plusB3T, s.plusB3B),
    ];
    final until = session.plan.plusUntil;
    Widget card(String id) => _Option(
      key: ValueKey('plan-$id'),
      name: _name(id),
      price: products?[id]?.price,
      per: switch (id) {
        Products.plusYearly => s.perYear,
        Products.plusMonthly => s.perMonth,
        _ => null,
      },
      note: switch (id) {
        Products.tripPass => s.tripPassBody,
        _ => null,
      },
      badge: id == Products.plusYearly ? s.planYearlySave : null,
      selected: _pick == id,
      onTap: () => setState(() => _pick = id),
    );
    final plus = _pick == Products.plusYearly || _pick == Products.plusMonthly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Coin(size: 56, join: 1)),
        const SizedBox(height: NNSpace.xs),
        Text(
          s.plusFree,
          key: const ValueKey('plus-free'),
          textAlign: TextAlign.center,
          style: NNType.subhead.copyWith(color: p.text2),
        ),
        if (session.plan.plus && until != null) ...[
          const SizedBox(height: NNSpace.xs),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: p.successSoft,
              ),
              child: Text(
                s.fill(s.plusOnUntil, {
                  'date': MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(until),
                }),
                style: NNType.footnote.copyWith(
                  color: p.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: NNSpace.md),
        // What Plus adds, three things.
        NNCard(
          key: const ValueKey('plus-benefits'),
          padding: const EdgeInsets.symmetric(
            horizontal: NNSpace.sm,
            vertical: NNSpace.xs,
          ),
          child: Column(
            children: [
              for (final (i, b) in benefits.indexed)
                MergeSemantics(
                  key: ValueKey('plus-benefit-${i + 1}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: p.accentSoft,
                            borderRadius: BorderRadius.circular(
                              NNRadius.control,
                            ),
                          ),
                          child: Icon(b.$1, size: 20, color: p.onAccentSoft),
                        ),
                        const SizedBox(width: NNSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.$2,
                                style: NNType.headline.copyWith(color: p.text),
                              ),
                              Text(
                                b.$3,
                                style: NNType.footnote.copyWith(color: p.text2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NNSpace.md),
        // The plans side by side, so the price is there without scrolling.
        Row(
          key: const ValueKey('plan-cards'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: card(Products.plusYearly)),
            const SizedBox(width: NNSpace.xs),
            Expanded(child: card(Products.plusMonthly)),
          ],
        ),
        for (final id in _options.skip(2)) ...[
          const SizedBox(height: NNSpace.xs),
          card(id),
        ],
        if (products != null && products.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.xs),
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
          label: plus ? s.startPlus : s.buy,
          busy: _busy,
          onTap: products?[_pick] == null ? null : _buy,
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
        const SizedBox(height: NNSpace.sm),
        NNButton(
          key: const ValueKey('restore'),
          label: s.restore,
          kind: ButtonKind.plain,
          onTap: _busy ? null : () => session.restore(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: NNSpace.sm),
          child: Text(
            s.billedBy,
            key: const ValueKey('billed-by'),
            textAlign: TextAlign.center,
            style: NNType.footnote.copyWith(color: p.text2),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: NNSpace.sm,
          children: [
            for (final (key, label, path) in [
              ('paywall-terms', s.terms, 'terms'),
              ('paywall-privacy', s.privacy, 'privacy'),
            ])
              TextButton(
                key: ValueKey(key),
                onPressed: () => session.device.open(
                  Uri.parse('${webUrl()}/$path?lang=${session.lang}'),
                ),
                child: Text(
                  label,
                  style: NNType.footnote.copyWith(
                    color: p.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A plan as a card: its name and a tick, the store's price ("AED 79.99 a year" where it fits),
/// and a note or a badge.
class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.name,
    required this.price,
    required this.per,
    required this.note,
    required this.badge,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final String? price;

  /// "{price} a year", for the price when it fits.
  final String? per;
  final String? note;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final full = price == null
        ? null
        : (per == null ? price! : s.fill(per!, {'price': price!}));
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: [name, ?full, ?note, ?badge].join(', '),
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.98,
      child: AnimatedContainer(
        duration: NNMotion.fade,
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(NNSpace.sm),
        decoration: ShapeDecoration(
          color: selected ? p.accentSoft : p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NNRadius.card),
            side: BorderSide(
              color: selected ? p.accent : p.edge,
              width: selected ? 2 : 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: NNType.headline.copyWith(
                      color: selected ? p.onAccentSoft : p.text,
                    ),
                  ),
                ),
                const SizedBox(width: NNSpace.xs),
                AnimatedContainer(
                  duration: NNMotion.fade,
                  width: 24,
                  height: 24,
                  decoration: ShapeDecoration(
                    shape: CircleBorder(
                      side: BorderSide(
                        color: selected ? p.accent : p.edge,
                        width: 2,
                      ),
                    ),
                    color: selected ? p.accent : null,
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded, size: 16, color: p.onAccent)
                      : null,
                ),
              ],
            ),
            if (price != null) ...[
              const SizedBox(height: NNSpace.xxs),
              _Price(full: full!, price: price!, selected: selected),
            ],
            if (note != null)
              Text(
                note!,
                style: NNType.footnote.copyWith(
                  color: selected ? p.onAccentSoft : p.text2,
                ),
              ),
            if (badge != null) ...[
              const SizedBox(height: NNSpace.xxs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: p.highlight,
                ),
                child: Text(
                  badge!,
                  style: NNType.caption.copyWith(
                    color: p.onHighlight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The price with its period when that fits on the card, else the price alone, shrunk to fit.
class _Price extends StatelessWidget {
  const _Price({
    required this.full,
    required this.price,
    required this.selected,
  });
  final String full;
  final String price;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final style = NNType.title3.copyWith(
      color: selected ? p.onAccentSoft : p.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: full, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = !c.hasBoundedWidth || tp.width <= c.maxWidth;
        tp.dispose();
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            fits ? full : price,
            key: const ValueKey('plan-price'),
            maxLines: 1,
            style: style,
          ),
        );
      },
    );
  }
}
