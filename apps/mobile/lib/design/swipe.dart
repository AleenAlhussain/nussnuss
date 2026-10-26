import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'tokens.g.dart';

/// One button behind a row, revealed by swiping it toward the start.
class SwipeAction {
  const SwipeAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  /// For the button's key: `swipe-<id>`.
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;
}

/// iOS trailing actions: swipe a row from the end toward the start and its buttons show behind it.
/// Let go past half way and it stays open; tap a button to run it, or tap the row to close. The
/// same actions should also be the row's screen-reader actions, so nobody has to swipe.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.actions,
    required this.child,
    this.buttonWidth = 76,
  });
  final List<SwipeAction> actions;
  final Widget child;
  final double buttonWidth;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    upperBound: 1.3,
  );

  double get _width => widget.actions.length * widget.buttonWidth;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  /// +1 when a drag toward the start opens it (left in English, right in Arabic).
  double get _toStart =>
      Directionality.of(context) == TextDirection.rtl ? 1 : -1;

  void _drag(DragUpdateDetails d) {
    final v = _open.value + d.delta.dx * _toStart / _width;
    _open.value = v.clamp(0.0, 1.3);
  }

  void _end(DragEndDetails d) {
    final v = (d.primaryVelocity ?? 0) * _toStart;
    final open = v > 300 || (v > -300 && _open.value > 0.5);
    _settle(open);
  }

  void _settle(bool open) {
    final still = reduceMotion(context);
    if (still) {
      _open.value = open ? 1 : 0;
      return;
    }
    if (open && _open.value < 1) haptic(Haptic.selection);
    _open.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic);
  }

  void close() => _settle(false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // The row's own actions stand in for the swipe, so it adds no scroll actions of its own.
      excludeFromSemantics: true,
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _end,
      child: AnimatedBuilder(
        animation: _open,
        child: widget.child,
        builder: (context, child) {
          final t = _open.value;
          final shown = _width * t;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  // Screen readers use the row's own actions; the buttons only exist while shown.
                  excluding: t == 0,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: SizedBox(
                      width: math.max(0, shown),
                      child: ClipRect(
                        child: Row(
                          children: [
                            for (final a in widget.actions)
                              Expanded(child: _button(a)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(shown * _toStart, 0),
                child: Stack(
                  children: [
                    IgnorePointer(ignoring: t > 0, child: child),
                    // While open, a tap on the row closes it instead of opening it.
                    if (t > 0)
                      Positioned.fill(
                        child: GestureDetector(
                          key: const ValueKey('swipe-close'),
                          behavior: HitTestBehavior.opaque,
                          onTap: close,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _button(SwipeAction a) {
    return Pressable(
      key: ValueKey('swipe-${a.id}'),
      onTap: () {
        _settle(false);
        a.onTap();
      },
      semanticLabel: a.label,
      excludeChildSemantics: true,
      haptic: Haptic.light,
      scale: 1,
      child: ColoredBox(
        color: a.color,
        child: OverflowBox(
          maxWidth: widget.buttonWidth,
          minWidth: widget.buttonWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(a.icon, color: a.onColor, size: 22),
              const SizedBox(height: 2),
              Text(
                a.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: NNType.caption.copyWith(
                  color: a.onColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
