import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/session.dart';
import 'glass.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// The NussNuss mark: one coin in two fair halves, the same drawing as the web and the app icon.
/// [join] runs from 0 (apart, the right half dropped a little) to 1 (one whole coin).
/// Halves are drawn left and right in every language: the mark is a picture, not text.
///
/// It is minted: violet enamel and saffron metal with a rim, and a sheen that slides across the
/// faces as the phone tilts. Reduce Motion keeps the sheen still.
class Coin extends StatefulWidget {
  const Coin({super.key, this.size = 72, this.join = 0, this.tilt = true});

  /// Diameter of the coin. The widget is a little larger to fit the gap and the drop.
  final double size;
  final double join;

  /// Follow the phone's tilt. Off for coins drawn into images.
  final bool tilt;

  @override
  State<Coin> createState() => _CoinState();
}

class _CoinState extends State<Coin> with SingleTickerProviderStateMixin {
  StreamSubscription<Offset>? _sub;
  late final Ticker _ticker = createTicker(_tick);
  Offset _target = Offset.zero;
  Offset _sheen = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reduceMotion(context);
    final scope = context.getInheritedWidgetOfExactType<SessionScope>();
    if (!widget.tilt || still || scope?.notifier == null) {
      _stop();
      return;
    }
    _sub ??= scope!.notifier!.device.tilt().listen((o) {
      _target = o;
      if (!_ticker.isActive) _ticker.start();
    });
  }

  void _tick(Duration _) {
    // Ease toward the latest reading so the light glides instead of jittering.
    final next = Offset.lerp(_sheen, _target, 0.12)!;
    if ((next - _sheen).distance < 0.002) {
      _ticker.stop();
      return;
    }
    setState(() => _sheen = next);
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    if (_ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _stop();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final size = widget.size;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(size * 1.07, size * 1.08),
          painter: _CoinPainter(widget.join, p.accent, p.highlight, _sheen),
        ),
      ),
    );
  }
}

/// One half of the coin as a closed half-disc in [r], starting at angle [start] (π/2 draws the left
/// half, −π/2 the right one): enamel with depth, a sheen that follows [sheen], and the minted rim.
void _paintHalf(
  Canvas canvas,
  Rect r,
  double start,
  Color color,
  Offset sheen,
) {
  final path = Path()
    ..moveTo(r.center.dx, r.center.dy)
    ..arcTo(r, start, math.pi, false)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
  canvas.save();
  canvas.clipPath(path);
  // Depth: a little darker toward the bottom edge.
  canvas.drawRect(
    r,
    Paint()
      ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [
        const Color(0x00000000),
        const Color(0x2E000000),
      ]),
  );
  // Sheen: a soft light whose spot follows the tilt.
  final spot =
      r.center +
      Offset(
        r.width * (-0.18 + 0.32 * sheen.dx),
        r.height * (-0.26 + 0.28 * sheen.dy),
      );
  canvas.drawCircle(
    spot,
    r.width * 0.62,
    Paint()
      ..shader = ui.Gradient.radial(spot, r.width * 0.62, [
        const Color(0x52FFFFFF),
        const Color(0x00FFFFFF),
      ]),
  );
  // The minted rim: a fine light ring just inside the edge.
  canvas.drawArc(
    r.deflate(r.width * 0.06),
    start,
    math.pi,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r.width * 0.022)
      ..color = const Color(0x40FFFFFF),
  );
  canvas.restore();
}

/// One half of the coin on its own, drawn in a [size] × [size] box (the whole disc's box), so the
/// halves can move apart: the indigo (accent) half when [left], else the saffron (highlight) one.
/// Always left and right, in every language.
class CoinHalf extends StatelessWidget {
  const CoinHalf({super.key, required this.left, required this.size});
  final bool left;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return CustomPaint(
      size: Size.square(size),
      painter: _HalfPainter(left ? p.accent : p.highlight, left),
    );
  }
}

class _HalfPainter extends CustomPainter {
  _HalfPainter(this.color, this.left);
  final Color color;
  final bool left;

  @override
  void paint(Canvas canvas, Size size) => _paintHalf(
    canvas,
    Offset.zero & size,
    left ? math.pi / 2 : -math.pi / 2,
    color,
    Offset.zero,
  );

  @override
  bool shouldRepaint(_HalfPainter old) =>
      old.color != color || old.left != left;
}

class _CoinPainter extends CustomPainter {
  _CoinPainter(this.join, this.left, this.right, this.sheen);
  final double join;
  final Color left;
  final Color right;
  final Offset sheen;

  void _half(Canvas canvas, Rect r, double start, Color color) =>
      _paintHalf(canvas, r, start, color, sheen);

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.width / 1.07;
    final t = join;
    final slide = d * 0.035 * t;
    final drop = d * 0.08 * (1 - t).clamp(0.0, 1.0);
    _half(canvas, Rect.fromLTWH(slide, 0, d, d), math.pi / 2, left);
    _half(
      canvas,
      Rect.fromLTWH(d * 0.07 - slide, drop, d, d),
      -math.pi / 2,
      right,
    );
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.join != join ||
      old.left != left ||
      old.right != right ||
      old.sheen != sheen;
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

/// The two halves drifted apart: the art of an empty screen (nothing split yet). The saffron half
/// sits a little lower and turned, as if it had just come off.
class DriftedCoin extends StatelessWidget {
  const DriftedCoin({super.key, this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) {
    final gap = size * 0.22;
    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('drifted-coin'),
        width: size + gap,
        height: size * 1.12,
        child: Directionality(
          // A picture, not text: the halves stay left and right in Arabic too.
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: CoinHalf(left: true, size: size),
              ),
              Positioned(
                left: gap,
                top: size * 0.1,
                child: Transform.rotate(
                  angle: 0.14,
                  child: CoinHalf(left: false, size: size),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
