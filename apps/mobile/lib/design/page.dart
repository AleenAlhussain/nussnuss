import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/session.dart';
import 'coin.dart';
import 'glass.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// The ambient light behind every screen: a soft accent glow at the top-start corner and a
/// highlight glow at the top-end one (mirrored in Arabic), so glass always has colour under it.
/// It sits on the screen background only, never on cards or rows.
class Ambient extends StatelessWidget {
  const Ambient({super.key});

  /// [child] with the ambient light behind it, filling the screen.
  static Widget behind(Widget child) =>
      Stack(fit: StackFit.expand, children: [const Ambient(), child]);

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final p = nn.palette;
    return IgnorePointer(
      child: CustomPaint(
        painter: _AmbientPainter(
          accent: p.accent.withValues(
            alpha: nn.isDark
                ? NNAmbient.accentAlphaDark
                : NNAmbient.accentAlphaLight,
          ),
          highlight: p.highlight.withValues(
            alpha: nn.isDark
                ? NNAmbient.highlightAlphaDark
                : NNAmbient.highlightAlphaLight,
          ),
          rtl: Directionality.of(context) == TextDirection.rtl,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.accent,
    required this.highlight,
    required this.rtl,
  });
  final Color accent;
  final Color highlight;
  final bool rtl;

  /// An elliptical glow centred at [x] on the top edge, [w] × [h] of the screen in radius.
  void _glow(Canvas canvas, Size size, double x, double w, double h, Color c) {
    final rx = size.width * w;
    final ry = size.height * h;
    if (rx <= 0 || ry <= 0) return;
    canvas
      ..save()
      ..translate(x, 0)
      ..scale(1, ry / rx)
      ..drawCircle(
        Offset.zero,
        rx,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            rx,
            [c, c.withValues(alpha: 0)],
            const [0, 0.7],
          ),
      )
      ..restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final start = rtl ? size.width : 0.0;
    final end = rtl ? 0.0 : size.width;
    canvas.clipRect(Offset.zero & size);
    _glow(canvas, size, start, 1.2, 0.6, accent);
    _glow(canvas, size, end, 0.9, 0.45, highlight);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.accent != accent || old.highlight != highlight || old.rtl != rtl;
}

/// One tab's stack of pages, for the tab bar: the scroll position of the page on top, and which
/// way it is scrolling (the tab bar folds while scrolling down).
class TabPages {
  TabPages({required this.onScroll});
  final ValueChanged<bool> onScroll;
  final _scrolls = <ScrollController>[];

  void _add(ScrollController c) => _scrolls.add(c);
  void _remove(ScrollController c) => _scrolls.remove(c);

  /// Tapping the tab you are on: the page on top scrolls to its top; if it already is at the top,
  /// the tab goes back to its first page.
  void toTopOrRoot(NavigatorState nav, {required bool still}) {
    final c = _scrolls.lastOrNull;
    if (c != null && c.hasClients && c.offset > 1) {
      if (still) {
        c.jumpTo(0);
      } else {
        c.animateTo(
          0,
          duration: NNMotion.standardDuration,
          curve: SpringCurve(
            NNMotion.standard,
            NNMotion.standardDuration,
            clamp: true,
          ),
        );
      }
      return;
    }
    nav.popUntil((r) => r.isFirst);
  }
}

class TabScope extends InheritedWidget {
  const TabScope({super.key, required this.pages, required super.child});
  final TabPages pages;

  static TabPages? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TabScope>()?.pages;

  @override
  bool updateShouldNotify(TabScope old) => old.pages != pages;
}

/// A page in the app. It slides in the platform's way (keeping the iOS back swipe). A group opened
/// from its card instead grows out of that card ([origin]) into the full screen on the standard
/// spring (350 ms, no bounce) and shrinks back into it. With Reduce Motion both are a crossfade.
class NNPageRoute<T> extends MaterialPageRoute<T> {
  NNPageRoute({required super.builder, this.origin, super.settings});
  final Rect? origin;

  bool get _expands => origin != null && !origin!.isEmpty;

  static final _spring = SpringCurve(
    NNMotion.standard,
    NNMotion.standardDuration,
    clamp: true,
  );
  CurvedAnimation? _curved;

  @override
  void dispose() {
    _curved?.dispose();
    super.dispose();
  }

  @override
  Duration get transitionDuration =>
      _expands ? NNMotion.standardDuration : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _expands
      ? const Duration(milliseconds: 300)
      : super.reverseTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) {
      // Still the platform's route underneath (for the back swipe), but nothing slides.
      return FadeTransition(
        opacity: animation,
        child: super.buildTransitions(
          context,
          kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation,
          child,
        ),
      );
    }
    if (!_expands) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    // Following a back swipe, the shape tracks the finger instead of the spring.
    return _Expand(
      origin: origin!,
      animation: popGestureInProgress
          ? animation
          : _curved ??= CurvedAnimation(
              parent: animation,
              curve: _spring,
              reverseCurve: _spring.flipped,
            ),
      child: super.buildTransitions(
        context,
        kAlwaysCompleteAnimation,
        secondaryAnimation,
        child,
      ),
    );
  }
}

class _Expand extends StatelessWidget {
  const _Expand({
    required this.origin,
    required this.animation,
    required this.child,
  });
  final Rect origin;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        final size = MediaQuery.sizeOf(context);
        final rect = Rect.lerp(origin, Offset.zero & size, t)!;
        final radius = ui.lerpDouble(NNRadius.card, 0, t)!;
        return Stack(
          children: [
            // The card itself grows first; the page fades in inside it.
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ClipPath(
                clipper: _RRectClipper(rect, radius),
                child: Opacity(
                  opacity: (t / 0.45).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RRectClipper extends CustomClipper<Path> {
  _RRectClipper(this.rect, this.radius);
  final Rect rect;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  bool shouldReclip(_RRectClipper old) =>
      old.rect != rect || old.radius != radius;
}

/// A screen with a large title that hands over to a small one in the top bar as you scroll. At the
/// top the bar is clear and only its buttons are glass; once the title has scrolled under it the
/// bar itself turns into a band of glass and its buttons become plain fills (never glass on
/// glass). [pinned] (a search field) stays under the bar. [bottom] floats over the content at the
/// bottom. With [onRefresh], pulling down from the top draws and spins the coin until it is done,
/// with a light haptic when the pull is far enough.
class NNPage extends StatefulWidget {
  const NNPage({
    super.key,
    required this.title,
    required this.slivers,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.onRefresh,
    this.onScrollDirection,
    this.titleKey,
    this.pinned,
    this.pinnedHeight = 56,
  });

  final String title;
  final List<Widget> slivers;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;
  final Future<void> Function()? onRefresh;

  /// Called with true while the person scrolls down past the title, false when they scroll back up.
  final ValueChanged<bool>? onScrollDirection;
  final Key? titleKey;
  final Widget? pinned;
  final double pinnedHeight;

  @override
  State<NNPage> createState() => _NNPageState();
}

class _NNPageState extends State<NNPage> with SingleTickerProviderStateMixin {
  static const _trigger = 72.0;

  final _scroll = ScrollController();
  bool _collapsed = false;

  /// False while the titles are fading between the large and the small one. Neither is in the
  /// semantics tree until it has fully appeared, so nothing half-transparent is ever read or checked.
  bool _settled = true;
  double _last = 0;
  TabPages? _tab;

  // Pull to refresh.
  final _pull = ValueNotifier<double>(0);
  bool _dragging = false;
  bool _armed = false;
  bool _busy = false;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tab == null) {
      _tab = TabScope.maybeOf(context);
      _tab?._add(_scroll);
    }
  }

  void _onScroll() {
    final y = _scroll.offset;
    final collapsed = y > 44;
    if (collapsed != _collapsed) {
      setState(() {
        _collapsed = collapsed;
        _settled = false;
      });
    }
    if ((y - _last).abs() > 6) {
      final down = y > _last && y > 80;
      widget.onScrollDirection?.call(down);
      _tab?.onScroll(down);
      _last = y;
    }
  }

  bool _onNotification(ScrollNotification n) {
    if (widget.onRefresh == null || n.depth != 0 || _busy) return false;
    if (n is ScrollStartNotification) {
      _dragging = n.dragDetails != null;
    } else if (n is ScrollUpdateNotification) {
      final over = n.metrics.minScrollExtent - n.metrics.pixels;
      if (n.dragDetails != null) {
        _dragging = true;
        _setPull(math.max(0, over));
      } else if (_dragging) {
        _release();
      } else {
        _pull.value = 0;
      }
    } else if (n is OverscrollNotification) {
      // Platforms that do not bounce report the pull as overscroll instead.
      if (n.dragDetails != null && n.overscroll < 0) {
        _dragging = true;
        _setPull(_pull.value - n.overscroll * 0.5);
      }
    } else if (n is ScrollEndNotification) {
      if (_dragging) _release();
    }
    return false;
  }

  void _setPull(double v) {
    _pull.value = v;
    if (!_armed && v >= _trigger) {
      _armed = true;
      haptic(Haptic.light);
    } else if (_armed && v < _trigger) {
      _armed = false;
    }
  }

  void _release() {
    _dragging = false;
    if (_armed) {
      _refresh();
    } else {
      _pull.value = 0;
    }
  }

  Future<void> _refresh() async {
    _armed = false;
    setState(() => _busy = true);
    _pull.value = _trigger;
    if (!reduceMotion(context)) _spin.repeat();
    try {
      await widget.onRefresh!();
    } finally {
      if (mounted) {
        _spin
          ..stop()
          ..value = 0;
        setState(() => _busy = false);
        _pull.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _tab?._remove(_scroll);
    _scroll.dispose();
    _pull.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final p = nn.palette;
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final side = ((width - NNLayout.maxContent) / 2).clamp(
      NNSpace.margin,
      double.infinity,
    );
    final still = reduceMotion(context);
    final duration = still ? NNMotion.fade : const Duration(milliseconds: 220);
    final bar = pad.top + NNLayout.topBar;
    // Both sides get the same width so the small title stays centred; wide enough for the buttons.
    final n = widget.actions.length;
    final sideWidth = n <= 1
        ? 96.0
        : (n * touchTarget(context) + (n - 1) * NNSpace.xs).clamp(96.0, 220.0);
    final pinned = widget.pinned;

    Widget list = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // With a pinned field the space under the top bar is pinned too, so the field stops under it.
        if (pinned != null)
          SliverPersistentHeader(pinned: true, delegate: _Fixed(bar, null))
        else
          SliverToBoxAdapter(child: SizedBox(height: bar)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverToBoxAdapter(
            child: AnimatedOpacity(
              opacity: _collapsed ? 0 : 1,
              duration: duration,
              onEnd: () {
                if (mounted && !_settled) setState(() => _settled = true);
              },
              child: AnimatedScale(
                scale: _collapsed && !still ? 0.96 : 1,
                duration: duration,
                alignment: AlignmentDirectional.centerStart.resolve(
                  Directionality.of(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: NNSpace.md),
                  child: ExcludeSemantics(
                    excluding: _collapsed || !_settled,
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.title,
                        key: widget.titleKey,
                        style: NNType.largeTitle.copyWith(color: p.text),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (pinned != null)
          SliverPersistentHeader(
            pinned: true,
            delegate: _Fixed(
              widget.pinnedHeight,
              Padding(
                padding: EdgeInsets.fromLTRB(side, 0, side, NNSpace.sm),
                child: pinned,
              ),
            ),
          ),
        for (final s in widget.slivers)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: s,
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: pad.bottom + NNLayout.tabBar + 56),
        ),
      ],
    );
    if (widget.onRefresh != null) {
      list = NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: list,
      );
    }

    return StepBack(
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: Ambient()),
            Positioned.fill(child: list),
            // Once the title has scrolled under it, the bar is a band of glass that fades out at its
            // lower edge.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _collapsed ? 1 : 0,
                  duration: duration,
                  child: _Band(height: bar),
                ),
              ),
            ),
            if (widget.onRefresh != null)
              Positioned(
                top: bar,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: _PullCoin(
                    pull: _pull,
                    spin: _spin,
                    busy: _busy,
                    trigger: _trigger,
                    still: still,
                  ),
                ),
              ),
            Positioned(
              top: pad.top,
              left: 0,
              right: 0,
              height: NNLayout.topBar,
              child: GlassLayer(
                active: _collapsed,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: (side - 12).clamp(8, double.infinity),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: sideWidth,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: widget.leading,
                        ),
                      ),
                      // The small title is a label, not a control: taps go through to the content.
                      Expanded(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            excluding: !_collapsed || !_settled,
                            child: AnimatedOpacity(
                              opacity: _collapsed ? 1 : 0,
                              duration: duration,
                              child: AnimatedSlide(
                                offset: _collapsed || still
                                    ? Offset.zero
                                    : const Offset(0, 0.15),
                                duration: duration,
                                child: Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NNType.headline.copyWith(
                                    color: p.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: sideWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (var i = 0; i < widget.actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: NNSpace.xs),
                              widget.actions[i],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.bottom != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    (side - 4).clamp(16, double.infinity),
                    0,
                    (side - 4).clamp(16, double.infinity),
                    pad.bottom + 12,
                  ),
                  child: widget.bottom,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A fixed-height pinned header ([child] null: empty space that lets taps through).
class _Fixed extends SliverPersistentHeaderDelegate {
  _Fixed(this.height, this.child);
  final double height;
  final Widget? child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) =>
      child ?? const SizedBox.shrink();

  @override
  bool shouldRebuild(_Fixed old) => old.height != height || old.child != child;
}

/// The top bar once content has scrolled under it: the glass of the current level (blurred and
/// tinted; opaque for Solid) with a 16 pt fade at its lower edge instead of a hard line.
class _Band extends StatelessWidget {
  const _Band({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = NNTheme.of(context).glass;
    Widget band = Container(height: height, color: g.fill);
    if (g.blur > 0) {
      band = ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: g.blur, sigmaY: g.blur),
          child: band,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        band,
        Container(
          height: 16,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [g.fill, g.fill.withValues(alpha: 0)],
            ),
          ),
        ),
      ],
    );
  }
}

/// The pull-to-refresh coin: it comes down with the finger, its ring drawing round as the pull
/// nears the point where it will refresh, then it spins until the new data is in. With Reduce
/// Motion it does not turn.
class _PullCoin extends StatelessWidget {
  const _PullCoin({
    required this.pull,
    required this.spin,
    required this.busy,
    required this.trigger,
    required this.still,
  });
  final ValueListenable<double> pull;
  final Animation<double> spin;
  final bool busy;
  final double trigger;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final s = context.s;
    return ValueListenableBuilder<double>(
      valueListenable: pull,
      builder: (context, v, _) {
        if (v <= 0 && !busy) return const SizedBox.shrink();
        final progress = busy ? 1.0 : (v / trigger).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, math.min(v, trigger + 24) - 48),
          child: Opacity(
            opacity: busy ? 1 : progress,
            child: Center(
              child: Semantics(
                key: const ValueKey('pull-refresh'),
                liveRegion: true,
                label: busy ? s.loading : s.pullRefresh,
                child: RotationTransition(
                  turns: spin,
                  child: Transform.rotate(
                    angle: still || busy ? 0 : v * 3 * math.pi / 180,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: ShapeDecoration(
                        shape: const CircleBorder(),
                        color: p.surface,
                        shadows: const [
                          BoxShadow(
                            color: Color(0x1F000000),
                            blurRadius: 20,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        foregroundPainter: _Ring(progress, p.accent),
                        child: const Center(
                          child: Coin(size: 22, join: 1, tilt: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    canvas.drawArc(
      (Offset.zero & size).deflate(3),
      -math.pi / 2,
      2 * math.pi * t,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.t != t || old.color != color;
}
