import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/models.dart';
import '../data/services.dart';
import '../data/session.dart';
import '../design/coin.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../format.dart';

/// The "who owes who" card people post in their group chat. Always drawn on the violet night, so
/// it looks the same whoever shares it, and every share shows the brand.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.group});
  final GroupDetail group;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final g = group;
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      color: p.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Coin(size: 36, join: g.transfers.isEmpty ? 1 : 0.55, tilt: false),
              const SizedBox(width: 10),
              Text(
                s.appName,
                style: NNType.headline.copyWith(
                  color: p.text,
                  fontFamily: nnDisplayFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '${g.emoji} ${g.name}'.trim(),
            style: NNType.title2.copyWith(color: p.text),
          ),
          const SizedBox(height: 4),
          Text(
            '${s.total} · ${money(g.total, g.currency, s.lang)}',
            style: NNType.subhead.copyWith(color: p.text2),
          ),
          const SizedBox(height: 20),
          Text(
            s.summaryTitle,
            style: NNType.footnote.copyWith(
              color: p.highlight,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (g.transfers.isEmpty)
            Text(s.allSettled, style: NNType.title3.copyWith(color: p.success))
          else
            for (final t in g.transfers)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(NNRadius.row),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        // Real names for everyone: "you" means nothing to the friends it is sent to.
                        transferSpan(
                          t,
                          me: '',
                          nameOf: g.nameOf,
                          s: s,
                          soft: p.text2,
                        ),
                        style: NNType.callout.copyWith(color: p.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      money(t.amount, g.currency, s.lang),
                      style: NNType.headline.copyWith(
                        color: p.text,
                        fontFamily: nnDisplayFamily,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          Text(s.summaryMade, style: NNType.footnote.copyWith(color: p.text2)),
        ],
      ),
    );
  }
}

/// Draws [SummaryCard] off-screen at 3× (1080 pixels wide) and returns it as a PNG.
Future<Uint8List?> renderSummaryCard(
  BuildContext context,
  GroupDetail group,
) async {
  final session = SessionScope.read(context);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final key = GlobalKey();
  final theme = buildTheme(
    brightness: Brightness.dark,
    glass: session.glass,
    look: session.activeLook,
  );
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Laid out and painted, but far outside the screen.
      left: -4000,
      top: 0,
      child: Theme(
        data: theme,
        child: Directionality(
          textDirection: session.s.isRtl
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.noScaling),
            child: RepaintBoundary(
              key: key,
              child: Material(
                type: MaterialType.transparency,
                child: SummaryCard(group: group),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}

/// Renders the card and opens the share sheet with it.
Future<void> shareSummary(
  BuildContext context,
  GroupDetail group, {
  Rect? origin,
}) async {
  final session = SessionScope.read(context);
  final bytes = await renderSummaryCard(context, group);
  if (bytes == null) return;
  await session.device.share(
    text: '${group.emoji} ${group.name}'.trim(),
    files: [
      SharedFile(bytes, name: 'nussnuss-summary.png', mimeType: 'image/png'),
    ],
    origin: origin,
  );
}

/// The on-screen rectangle of the widget at [context], for the iPad share popover.
Rect? originOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
