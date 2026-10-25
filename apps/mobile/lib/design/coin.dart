import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// The NussNuss mark: one coin in two fair halves, the same drawing as the web and the app icon.
/// [join] runs from 0 (apart, the right half dropped a little) to 1 (one whole coin).
/// Halves are drawn left and right in every language: the mark is a picture, not text.
class Coin extends StatelessWidget {
  const Coin({super.key, this.size = 72, this.join = 0});

  /// Diameter of the coin. The widget is a little larger to fit the gap and the drop.
  final double size;
  final double join;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size * 1.07, size * 1.08),
        painter: _CoinPainter(join, p.accent, p.highlight),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter(this.join, this.left, this.right);
  final double join;
  final Color left;
  final Color right;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.width / 1.07;
    final t = join;
    final slide = d * 0.035 * t;
    final drop = d * 0.08 * (1 - t).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromLTWH(slide, 0, d, d),
      math.pi / 2,
      math.pi,
      true,
      Paint()..color = left,
    );
    canvas.drawArc(
      Rect.fromLTWH(d * 0.07 - slide, drop, d, d),
      -math.pi / 2,
      math.pi,
      true,
      Paint()..color = right,
    );
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.join != join || old.left != left || old.right != right;
}

/// When everyone is square the two halves snap together on a bouncy spring, with one firm haptic.
class SettledMoment extends StatefulWidget {
  const SettledMoment({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  State<SettledMoment> createState() => _SettledMomentState();
}

class _SettledMomentState extends State<SettledMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (reduceMotion(context)) {
        _c.value = 1;
      } else {
        _c.springTo(1, NNMotion.bouncy);
      }
      haptic(Haptic.success);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Semantics(
      key: const ValueKey('all-settled'),
      liveRegion: true,
      label: '${widget.title}. ${widget.body}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NNSpace.xxl),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Coin(size: 104, join: _c.value),
            ),
            const SizedBox(height: NNSpace.lg),
            Text(widget.title, style: NNType.title2.copyWith(color: p.text)),
            const SizedBox(height: NNSpace.xxs),
            Text(
              widget.body,
              textAlign: TextAlign.center,
              style: NNType.callout.copyWith(color: p.text2),
            ),
          ],
        ),
      ),
    );
  }
}
