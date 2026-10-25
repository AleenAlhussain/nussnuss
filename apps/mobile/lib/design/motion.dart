import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.g.dart';

final _number = RegExp(r'[0-9][0-9.,]*');

/// Text whose digits roll like a counter when it changes: each changed digit slides up and away
/// while the new one comes up from below. The words around the number (a currency code or symbol)
/// stay put, and the number itself always reads left to right, in Arabic too.
/// Reduce Motion makes the digits fade instead.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final parts = <Widget>[];
    var at = 0;
    for (final m in _number.allMatches(text)) {
      if (m.start > at) {
        parts.add(Text(text.substring(at, m.start), style: style));
      }
      final digits = m.group(0)!;
      parts.add(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < digits.length; i++)
                _Roll(
                  // Keyed from the right, so units stay units when the number grows.
                  key: ValueKey('${m.start}-${digits.length - i}'),
                  char: digits[i],
                  style: style,
                  still: still,
                ),
            ],
          ),
        ),
      );
      at = m.end;
    }
    if (at < text.length) parts.add(Text(text.substring(at), style: style));
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: parts),
    );
  }
}

class _Roll extends StatelessWidget {
  const _Roll({
    super.key,
    required this.char,
    required this.style,
    required this.still,
  });
  final String char;
  final TextStyle style;
  final bool still;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: still ? NNMotion.fade : const Duration(milliseconds: 380),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          if (still) return FadeTransition(opacity: animation, child: child);
          final incoming = child.key == ValueKey(char);
          final slide = Tween<Offset>(
            begin: incoming ? const Offset(0, 0.7) : const Offset(0, -0.7),
            end: Offset.zero,
          ).animate(animation);
          return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, ?current],
        ),
        child: Text(char, key: ValueKey(char), style: style),
      ),
    );
  }
}

/// A placeholder shaped like what is loading: its blocks shimmer, a band of light sweeping across
/// them (still with Reduce Motion). Announced once as "Loading".
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, required this.label});
  final Widget child;
  final String label;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final still = reduceMotion(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      excludeSemantics: true,
      child: still
          ? widget.child
          : AnimatedBuilder(
              animation: _c,
              child: widget.child,
              builder: (context, child) {
                // The band runs from the start edge to the end edge.
                final t = rtl ? 1 - _c.value : _c.value;
                return ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment(-1 + 4 * t - 1.5, -0.2),
                    end: Alignment(1 + 4 * t - 1.5, 0.2),
                    colors: [
                      p.surface2,
                      Color.lerp(p.surface2, p.surface, 0.7)!,
                      p.surface2,
                    ],
                    stops: const [0.3, 0.5, 0.7],
                  ).createShader(rect),
                  child: child,
                );
              },
            ),
    );
  }
}

/// One block of a skeleton.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 14, this.radius = 7});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Rows like a list card while it loads: a round icon, a title and a line under it, an amount.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    required this.label,
    this.count = 3,
    this.separate = true,
  });
  final String label;
  final int count;

  /// One card per row (the groups list) or one card for all of them (expenses).
  final bool separate;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    Widget row(int i) => Padding(
      padding: const EdgeInsets.all(NNSpace.md),
      child: Row(
        children: [
          const Bone(width: 44, height: 44, radius: 14),
          const SizedBox(width: NNSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(width: 150.0 - i * 22),
                const SizedBox(height: NNSpace.xs),
                Bone(width: 96.0 + i * 14, height: 11),
              ],
            ),
          ),
          const Bone(width: 64, height: 16),
        ],
      ),
    );
    Widget card(Widget child) => DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(NNRadius.card),
      ),
      child: child,
    );
    return Skeleton(
      label: label,
      child: separate
          ? Column(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(height: NNSpace.sm),
                  card(row(i)),
                ],
              ],
            )
          : card(Column(children: [for (var i = 0; i < count; i++) row(i)])),
    );
  }
}

/// A row arriving with its list: it fades and rises in, 30 ms after the row before it (from the
/// fifth row on, all together), so a whole list is in within 400 ms. [animate] is false for rows
/// built later, while scrolling. With Reduce Motion it only fades.
class FadeIn extends StatefulWidget {
  const FadeIn({
    super.key,
    required this.index,
    required this.child,
    this.animate = true,
  });
  final int index;
  final Widget child;
  final bool animate;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 400);
  static const _each = Duration(milliseconds: 280);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _total,
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _t = () {
    final start = math.min(widget.index, 4) * 30 / _total.inMilliseconds;
    return CurvedAnimation(
      parent: _c,
      curve: Interval(
        start,
        start + _each.inMilliseconds / _total.inMilliseconds,
        curve: SpringCurve(NNMotion.standard, _each, clamp: true),
      ),
    );
  }();

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        // The same widgets at rest, so the row keeps its state when the fade ends.
        final v = _t.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, still ? 0 : 8 * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Shakes its child three times, small (5 pt), in 300 ms, each time [trigger] goes up, and plays
/// the error haptic. Used for validation errors. With Reduce Motion it does not move; the haptic
/// still plays.
class Shake extends StatefulWidget {
  const Shake({
    super.key,
    required this.trigger,
    required this.child,
    this.haptic = true,
  });
  final int trigger;
  final Widget child;

  /// Off for a second thing shaking with the same error, so the haptic plays once.
  final bool haptic;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  bool _mounted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A message that appears with its first error shakes as it appears.
    if (!_mounted) {
      _mounted = true;
      if (widget.trigger > 0) _shake();
    }
  }

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger > old.trigger) _shake();
  }

  void _shake() {
    if (widget.haptic) haptic(Haptic.error);
    if (!reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // Always the same widgets, so a field keeps its focus while it shakes.
        final t = _c.value;
        return Transform.translate(
          offset: Offset(-5 * math.sin(t * 3 * 2 * math.pi), 0),
          child: child,
        );
      },
    );
  }
}

/// Pulses once (600 ms) when it first appears: a small swell and a ring of [color] that spreads and
/// fades. Then it stays as it is. Nothing with Reduce Motion.
class PulseOnce extends StatefulWidget {
  const PulseOnce({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  State<PulseOnce> createState() => _PulseOnceState();
}

class _PulseOnceState extends State<PulseOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (!reduceMotion(context)) _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final swell = t < 0.4
            ? Curves.easeOut.transform(t / 0.4)
            : 1 - Curves.easeInOut.transform((t - 0.4) / 0.6);
        return Transform.scale(
          scale: 1 + 0.06 * swell,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              shadows: t == 0 || t == 1
                  ? const []
                  : [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.55 * (1 - t)),
                        spreadRadius: 10 * Curves.easeOut.transform(t),
                      ),
                    ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// A checkmark that draws itself (stroke from the short arm to the tip) as [progress] goes 0 → 1.
class DrawnCheck extends StatelessWidget {
  const DrawnCheck({
    super.key,
    required this.progress,
    required this.color,
    this.size = 22,
    this.stroke = 2.6,
  });
  final double progress;
  final Color color;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _CheckPainter(progress.clamp(0.0, 1.0), color, stroke),
  );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color, this.stroke);
  final double t;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.2, w * 0.53)
      ..lineTo(w * 0.42, w * 0.74)
      ..lineTo(w * 0.8, w * 0.3);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.t != t || old.color != color || old.stroke != stroke;
}

/// Something done: a check draws itself over the content in a green circle, then the whole thing
/// folds away (about 300 ms), with the success haptic, before [onDone] runs. With Reduce Motion it
/// fades out instead. While [done] is false it is just [child].
class DoneAndGone extends StatefulWidget {
  const DoneAndGone({
    super.key,
    required this.done,
    required this.onDone,
    required this.child,
  });
  final bool done;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<DoneAndGone> createState() => _DoneAndGoneState();
}

class _DoneAndGoneState extends State<DoneAndGone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _draw = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.35, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _fold = CurvedAnimation(
    parent: _c,
    curve: Interval(
      1 / 3,
      1,
      curve: SpringCurve(
        NNMotion.standard,
        const Duration(milliseconds: 300),
        clamp: true,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.done) WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  @override
  void didUpdateWidget(DoneAndGone old) {
    super.didUpdateWidget(old);
    if (widget.done && !old.done) {
      _go();
    } else if (!widget.done && old.done) {
      _c.value = 0;
    }
  }

  Future<void> _go() async {
    if (!mounted) return;
    haptic(Haptic.success);
    if (reduceMotion(context)) {
      _c.value = 0.35;
      await _c.animateTo(1, duration: NNMotion.fade);
    } else {
      await _c.forward(from: 0);
    }
    if (mounted && widget.done) widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final still = reduceMotion(context);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        if (_c.value == 0) return child!;
        final fold = _fold.value;
        final shown = Stack(
          alignment: Alignment.center,
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(NNRadius.card),
                  ),
                ),
              ),
            ),
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                shape: const CircleBorder(),
                color: p.success,
              ),
              child: DrawnCheck(progress: _draw.value, color: p.surface),
            ),
          ],
        );
        if (still) return Opacity(opacity: 1 - fold, child: shown);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1 - fold,
            child: Opacity(opacity: 1 - fold, child: shown),
          ),
        );
      },
    );
  }
}
