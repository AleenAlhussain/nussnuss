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

/// A placeholder shaped like what is loading: soft blocks that breathe gently (still with Reduce
/// Motion). Announced once as "Loading".
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
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 0.5;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      liveRegion: true,
      excludeSemantics: true,
      child: FadeTransition(
        opacity: Tween(begin: 0.55, end: 1.0).animate(_c),
        child: widget.child,
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
