import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// Minimum touch target: 44pt on Apple platforms (HIG), 48dp on Android (Material).
double touchTarget(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => 48,
      TargetPlatform.iOS || TargetPlatform.macOS => NNSpace.touch,
    };

/// Reduce Motion: springs become short fades, nothing scales or slides.
bool reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

extension SpringTo on AnimationController {
  /// Animate to [target] with a token spring, keeping the current velocity so interrupted motion stays smooth.
  TickerFuture springTo(double target, SpringDescription spring) =>
      animateWith(SpringSimulation(spring, value, target, velocity));
}

/// A token spring as a curve, for motion that runs on a fixed duration (routes, implicit
/// animations, scrolling). [clamp] cuts the overshoot for motion that must not bounce.
class SpringCurve extends Curve {
  SpringCurve(this.spring, this.duration, {this.clamp = false})
    : _sim = SpringSimulation(spring, 0, 1, 0);
  final SpringDescription spring;
  final Duration duration;
  final bool clamp;
  final SpringSimulation _sim;

  @override
  double transformInternal(double t) {
    final x = _sim.x(
      t * duration.inMicroseconds / Duration.microsecondsPerSecond,
    );
    return clamp ? x.clamp(0.0, 1.0) : x;
  }
}

/// Glass never sits on glass. Inside a glass surface (a sheet, a toast, the top bar once it has
/// turned to glass) a [Glass] is drawn as a plain fill instead.
class GlassLayer extends InheritedWidget {
  const GlassLayer({super.key, required this.active, required super.child});
  final bool active;

  static bool on(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassLayer>()?.active ?? false;

  @override
  bool updateShouldNotify(GlassLayer old) => old.active != active;
}

/// Saturation matrix with Rec. 709 luma weights, the same maths as CSS `saturate()`.
List<double> _saturation(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final i = 1 - s;
  return [
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0,
    r * i, g * i, b * i + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

final _filters = <NNGlassStyle, ui.ImageFilter>{};

ui.ImageFilter _filterFor(NNGlassStyle s) => _filters.putIfAbsent(
  s,
  () => ui.ImageFilter.compose(
    outer: ColorFilter.matrix(_saturation(s.saturation)),
    inner: ui.ImageFilter.blur(sigmaX: s.blur, sigmaY: s.blur),
  ),
);

/// The navigation layer material: a blurred, saturated, tinted pane with a 1 px edge of light that is
/// brightest at the top-start corner. Use it only for things that float above content (the tab bar,
/// bar buttons, the add button, the pinned search field, sheets, toasts) and never put glass inside
/// glass: controls inside a sheet use solid fills. The level comes from Settings > Glass: Clear,
/// Tinted (the default) or Solid; Solid (also forced by Increase Contrast) is an opaque pane with a
/// separator hairline, so text on it always meets contrast.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = NNRadius.pill,
    this.borderRadius,
    this.tint,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final BorderRadius? borderRadius;

  /// Tinted glass is for the one primary action on a screen.
  final Color? tint;
  final EdgeInsetsGeometry padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final s = nn.glass;
    final r = borderRadius ?? BorderRadius.circular(radius);
    final tinted = tint != null;
    final press = PressScope.of(context);

    // Pressed glass brightens, as if more light came through it.
    Widget pressed(Widget body) => press == null
        ? body
        : Stack(
            children: [
              body,
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: press,
                    builder: (_, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: r,
                        color: Colors.white.withValues(
                          alpha:
                              (nn.isDark ? 0.10 : 0.18) *
                              press.value.clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

    if (!tinted && GlassLayer.on(context)) {
      // Already on glass: a plain fill, no blur, edge or shadow.
      return ClipRRect(
        borderRadius: r,
        child: pressed(
          DecoratedBox(
            decoration: BoxDecoration(
              color: nn.palette.text.withValues(alpha: 0.07),
              borderRadius: r,
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }

    final solid = s.bordered && !tinted;
    Widget body = pressed(
      DecoratedBox(
        decoration: BoxDecoration(
          color: tint ?? s.fill,
          borderRadius: r,
          border: solid ? Border.all(color: nn.palette.separator) : null,
        ),
        child: Padding(
          padding: padding,
          child: GlassLayer(active: true, child: child),
        ),
      ),
    );
    if (!solid) {
      body = CustomPaint(
        foregroundPainter: _EdgePainter(
          r,
          top: nn.isDark ? NNGlass.edgeTopDark : NNGlass.edgeTopLight,
          hairline: nn.isDark
              ? NNGlass.edgeHairlineDark
              : NNGlass.edgeHairlineLight,
          direction: Directionality.of(context),
        ),
        child: body,
      );
    }
    if (s.blur > 0 && !tinted) {
      body = BackdropFilter(filter: _filterFor(s), child: body);
    }
    body = ClipRRect(borderRadius: r, child: body);
    final shadowColor = tinted ? tint!.withValues(alpha: 0.4) : s.shadow;
    if (shadow && shadowColor.a > 0) {
      body = CustomPaint(
        painter: _OuterShadowPainter(r, shadowColor),
        child: body,
      );
    }
    return body;
  }
}

/// The glass edge: a 1 px hairline of white that brightens toward the top-start corner, where the
/// light comes from (top-left in English, top-right in Arabic).
class _EdgePainter extends CustomPainter {
  _EdgePainter(
    this.radius, {
    required this.top,
    required this.hairline,
    required this.direction,
  });
  final BorderRadius radius;
  final Color top;
  final Color hairline;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: AlignmentDirectional.topStart.resolve(direction),
        end: AlignmentDirectional.bottomEnd.resolve(direction),
        colors: [top, hairline, hairline],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRRect(radius.toRRect(rect).deflate(0.5), paint);
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.top != top ||
      old.hairline != hairline ||
      old.radius != radius ||
      old.direction != direction;
}

/// A soft drop shadow painted only outside the shape, so it never darkens the glass itself.
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.radius, this.color);
  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = radius.toRRect(rect);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(80))
      ..addRRect(rr);
    canvas
      ..save()
      ..clipPath(outside)
      ..drawRRect(
        rr.shift(const Offset(0, 8)),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.color != color || old.radius != radius;
}

enum Haptic { none, selection, light, medium, success, warning, error }

/// Where haptics go. Tests swap it for a recorder.
void Function(Haptic) hapticPlayer = _playHaptic;

void haptic(Haptic h) {
  if (h != Haptic.none) hapticPlayer(h);
}

void _playHaptic(Haptic h) {
  switch (h) {
    case Haptic.none:
      return;
    case Haptic.selection:
      HapticFeedback.selectionClick();
    case Haptic.light:
      HapticFeedback.lightImpact();
    case Haptic.medium || Haptic.success || Haptic.warning:
      HapticFeedback.mediumImpact();
    case Haptic.error:
      HapticFeedback.heavyImpact();
  }
}

/// The press of the nearest [Pressable] (0 at rest, 1 fully pressed), so glass and solid buttons
/// can brighten under the finger.
class PressScope extends InheritedWidget {
  const PressScope({super.key, required this.press, required super.child});
  final Animation<double> press;

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PressScope>()?.press;

  @override
  bool updateShouldNotify(PressScope old) => old.press != press;
}

/// A white wash over a solid button while it is pressed.
class PressGlow extends StatelessWidget {
  const PressGlow({super.key, required this.shape, required this.child});
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final press = PressScope.of(context);
    if (press == null) return child;
    final dark = NNTheme.of(context).isDark;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: press,
              builder: (_, _) => DecoratedBox(
                decoration: ShapeDecoration(
                  shape: shape,
                  color: Colors.white.withValues(
                    alpha: (dark ? 0.08 : 0.16) * press.value.clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Anything tappable. Pressing takes 100 ms; letting go settles back on the standard spring. Solid
/// things shrink to [NNMotion.pressScale]; glass controls pass [NNMotion.glassPressScale] and swell.
/// Both brighten (see [PressScope]). With Reduce Motion nothing moves: it dims instead. Exposes
/// itself as a button to VoiceOver and TalkBack.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.scale = NNMotion.pressScale,
    this.haptic = Haptic.none,
    this.selected,
    this.checked,
    this.excludeChildSemantics = false,
    this.onLongPress,
    this.longPressLabel,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// A shortcut, never the only way: screen readers get it as a named action ([longPressLabel]).
  final VoidCallback? onLongPress;
  final String? longPressLabel;
  final String? semanticLabel;
  final double scale;
  final Haptic haptic;
  final bool? selected;

  /// For toggles: announced as a checkbox state instead of "selected".
  final bool? checked;
  final bool excludeChildSemantics;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  bool get _enabled => widget.onTap != null;

  void _down() {
    if (_enabled) {
      _press.animateTo(
        1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _up() => _press.springTo(0, NNMotion.standard);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final long = widget.onLongPress;
    return Semantics(
      button: widget.checked == null,
      enabled: _enabled,
      selected: widget.selected,
      checked: widget.checked,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeChildSemantics,
      customSemanticsActions: long != null && widget.longPressLabel != null
          ? {CustomSemanticsAction(label: widget.longPressLabel!): long}
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onLongPress: long == null
            ? null
            : () {
                _up();
                haptic(Haptic.success);
                long();
              },
        onTap: _enabled
            ? () {
                haptic(widget.haptic);
                widget.onTap!();
              }
            : null,
        child: AnimatedBuilder(
          animation: _press,
          child: PressScope(press: _press, child: widget.child),
          builder: (context, child) {
            final t = _press.value;
            if (still) {
              return Opacity(opacity: 1 - 0.3 * t.clamp(0, 1), child: child);
            }
            return Transform.scale(
              scale: 1 - (1 - widget.scale) * t,
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// Round glass button for bars: back, share, close. 44pt, the minimum touch target.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.flipInRtl = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool flipInRtl;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    Widget glyph = Icon(icon, size: 22, color: p.text);
    if (flipInRtl && Directionality.of(context) == TextDirection.rtl) {
      glyph = Transform.flip(flipX: true, child: glyph);
    }
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      haptic: Haptic.light,
      scale: NNMotion.glassPressScale,
      child: Glass(
        child: SizedBox.square(
          dimension: touchTarget(context),
          child: Center(child: glyph),
        ),
      ),
    );
  }
}

/// The one tinted glass control on a screen. A light follows the finger across it, like light on glass.
class AddButton extends StatefulWidget {
  const AddButton({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.longPressLabel,
  });
  final String label;

  /// Gets the button's rectangle on screen, so a sheet can grow out of it.
  final void Function(Rect origin) onTap;
  final VoidCallback? onLongPress;
  final String? longPressLabel;

  @override
  State<AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<AddButton> {
  Alignment _light = const Alignment(-0.4, -0.6);

  Rect _rect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _move(Offset local) {
    // With Reduce Motion the light stays where it is.
    if (reduceMotion(context)) return;
    const size = 64.0;
    setState(
      () => _light = Alignment(
        (local.dx / size) * 2 - 1,
        (local.dy / size) * 2 - 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Listener(
      onPointerDown: (e) => _move(e.localPosition),
      onPointerMove: (e) => _move(e.localPosition),
      onPointerUp: (_) => setState(() => _light = const Alignment(-0.4, -0.6)),
      child: Pressable(
        key: const ValueKey('add'),
        onTap: () => widget.onTap(_rect()),
        onLongPress: widget.onLongPress,
        longPressLabel: widget.longPressLabel,
        semanticLabel: widget.label,
        excludeChildSemantics: true,
        haptic: Haptic.light,
        scale: NNMotion.glassPressScale,
        child: Glass(
          tint: p.accent,
          child: SizedBox.square(
            dimension: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: _light,
                        radius: 0.8,
                        colors: const [Color(0x73FFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
                Icon(Icons.add_rounded, size: 32, color: p.onAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TabItem {
  const TabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge = 0,
    this.badgeLabel,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// New things to look at (Activity): a small count on the icon.
  final int badge;

  /// How a screen reader says the badge ("3 new").
  final String? badgeLabel;
}

/// Floating glass capsule with the tabs: each an icon over its name, the selected one in a filled
/// capsule. While the person scrolls down the bar shrinks to icons only, then it comes back on
/// scroll up. It keeps its size at large text sizes (like the system's own bars); instead, with
/// [largeContent], pressing and holding a tab shows it big in the middle of the screen (Apple's
/// large content viewer), and letting go there picks it.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.compact = false,
    this.largeContent = false,
  });

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool compact;
  final bool largeContent;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  OverlayEntry? _hud;

  void _showHud(int i) {
    _hideHud();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final item = widget.items[i];
    final entry = OverlayEntry(
      builder: (_) => _LargeContent(icon: item.selectedIcon, label: item.label),
    );
    _hud = entry;
    overlay.insert(entry);
    haptic(Haptic.selection);
  }

  void _hideHud() {
    final h = _hud;
    _hud = null;
    if (h != null && h.mounted) {
      h.remove();
      h.dispose();
    }
  }

  @override
  void dispose() {
    _hideHud();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final still = reduceMotion(context);
    final duration = still ? NNMotion.fade : NNMotion.standardDuration;
    final compact = widget.compact;
    // Fixed sizes, whatever the text size: the large content viewer is how big text reaches it.
    // On the narrowest phones the whole capsule scales down rather than overflow.
    return MediaQuery.withNoTextScaling(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.bottomStart,
        child: AnimatedScale(
          scale: compact && !still ? 0.92 : 1,
          alignment: AlignmentDirectional.bottomStart.resolve(
            Directionality.of(context),
          ),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Glass(
            padding: const EdgeInsets.all(5),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    _tab(context, i, p, duration),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i, NNPalette p, Duration duration) {
    final item = widget.items[i];
    final selected = i == widget.index;
    final compact = widget.compact;
    final color = selected ? p.text : p.text2;
    Widget icon = Icon(
      selected ? item.selectedIcon : item.icon,
      size: 24,
      color: color,
    );
    if (item.badge > 0) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          PositionedDirectional(
            top: -4,
            end: -9,
            child: Container(
              key: ValueKey('tab-badge-$i'),
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                shape: StadiumBorder(
                  side: BorderSide(color: p.surface, width: 1.5),
                ),
                color: p.accent,
              ),
              child: Text(
                item.badge > 99 ? '99+' : '${item.badge}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: p.onAccent,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final label = [
      item.label,
      if (item.badge > 0 && item.badgeLabel != null) item.badgeLabel!,
    ].join(', ');
    return GestureDetector(
      onLongPressStart: widget.largeContent ? (_) => _showHud(i) : null,
      onLongPressEnd: widget.largeContent
          ? (_) {
              _hideHud();
              widget.onChanged(i);
            }
          : null,
      onLongPressCancel: widget.largeContent ? _hideHud : null,
      child: Pressable(
        key: ValueKey('tab-$i'),
        onTap: () => widget.onChanged(i),
        haptic: Haptic.light,
        scale: NNMotion.glassPressScale,
        selected: selected,
        semanticLabel: label,
        excludeChildSemantics: true,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          width: compact ? 54 : 76,
          height: 54,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: selected
                ? p.text.withValues(alpha: 0.07)
                : p.text.withValues(alpha: 0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                child: compact
                    ? const SizedBox(width: 24)
                    : Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 70,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              style: NNType.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: color,
                                height: 1.2,
                              ),
                            ),
                          ),
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

/// The large content viewer: a tab's icon and name, big, in the middle of the screen while it is
/// held.
class _LargeContent extends StatelessWidget {
  const _LargeContent({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Center(
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('large-content'),
          width: 190,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(NNRadius.card),
            border: Border.all(color: p.separator),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: p.text),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: NNType.title1.copyWith(color: p.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a glass sheet: grabber, a title with a close button, scrollable content and an optional footer
/// that stays above the keyboard. Contents are plain fills: never glass on glass.
///
/// It slides up on the sheet spring while the screen behind dims and steps back ([StepBack]).
/// With [origin] (the add button's rectangle) the sheet grows out of that button as one shape and
/// shrinks back into it on close. Reduce Motion turns both into a fade. Sheets open on the root
/// navigator, above the tab bar.
Future<T?> showNNSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  WidgetBuilder? footer,
  Key? key,
  Rect? origin,
}) {
  final nav = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: nav.context);
  final label = MaterialLocalizations.of(context).modalBarrierDismissLabel;
  Widget frame(BuildContext ctx) =>
      _SheetFrame(key: key, title: title, body: builder, footer: footer);
  if (origin != null && origin != Rect.zero) {
    return nav.push<T>(
      _MorphSheetRoute<T>(
        origin: origin,
        tint: NNTheme.of(context).palette.accent,
        barrierLabel: label,
        capturedThemes: themes,
        builder: frame,
      ),
    );
  }
  return nav.push<T>(
    _SheetRoute<T>(barrierLabel: label, capturedThemes: themes, builder: frame),
  );
}

/// How far the screen behind has stepped back for the open sheets: 0 (none) to 1.
final ValueNotifier<double> sheetBehind = ValueNotifier(0);
final _openSheets = <Animation<double>>[];

void _syncBehind() {
  var v = 0.0;
  for (final a in _openSheets) {
    v = math.max(v, a.value.clamp(0.0, 1.0));
  }
  sheetBehind.value = v;
}

/// While a sheet is open the screen behind it steps back: it scales to 0.96 and rounds its
/// corners, on the sheet's spring (the dimming comes from the sheet's barrier). Not with Reduce
/// Motion. Nested uses step back once.
class StepBack extends StatelessWidget {
  const StepBack({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.findAncestorWidgetOfExactType<_SteppedBack>() != null) {
      return child;
    }
    final still = reduceMotion(context);
    return _SteppedBack(
      child: ValueListenableBuilder<double>(
        valueListenable: sheetBehind,
        child: child,
        builder: (context, v, child) {
          final t = still ? 0.0 : v;
          return Transform.scale(
            scale: 1 - 0.04 * t,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NNRadius.sheet * t),
              clipBehavior: t > 0 ? Clip.antiAlias : Clip.none,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _SteppedBack extends ProxyWidget {
  const _SteppedBack({required super.child});

  @override
  Element createElement() => _SteppedBackElement(this);
}

class _SteppedBackElement extends ProxyElement {
  _SteppedBackElement(super.widget);

  @override
  void notifyClients(ProxyWidget oldWidget) {}
}

/// Sheets report their animation, so the screen behind can step back with them.
mixin _StepsBack<T> on PopupRoute<T> {
  CurvedAnimation? _behind;

  @override
  void install() {
    super.install();
    final behind = CurvedAnimation(
      parent: animation!,
      curve: SpringCurve(NNMotion.sheet, NNMotion.sheetDuration, clamp: true),
      reverseCurve: Curves.easeInCubic,
    );
    _behind = behind;
    _openSheets.add(behind);
    behind.addListener(_syncBehind);
  }

  @override
  void dispose() {
    final behind = _behind;
    if (behind != null) {
      behind
        ..removeListener(_syncBehind)
        ..dispose();
      _openSheets.remove(behind);
      // Not while the tree is being torn down.
      scheduleMicrotask(_syncBehind);
    }
    super.dispose();
  }
}

/// The page of a sheet route: bottom-aligned, at most 640 wide, below the status bar, draggable.
Widget _sheetPage(
  BuildContext context,
  CapturedThemes themes,
  WidgetBuilder builder,
) {
  final size = MediaQuery.sizeOf(context);
  final top = MediaQuery.paddingOf(context).top;
  return themes.wrap(
    _DragToClose(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: size.height - top,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: builder(context),
          ),
        ),
      ),
    ),
  );
}

/// A sheet that slides up from the bottom edge on the sheet spring (a slight bounce).
class _SheetRoute<T> extends PopupRoute<T> with _StepsBack<T> {
  _SheetRoute({
    required this.builder,
    required this.barrierLabel,
    required this.capturedThemes,
  });

  final WidgetBuilder builder;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.black.withValues(alpha: 0.3);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => NNMotion.sheetDuration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  late final CurvedAnimation _slide = CurvedAnimation(
    parent: animation!,
    curve: SpringCurve(NNMotion.sheet, NNMotion.sheetDuration),
    reverseCurve: Curves.easeInCubic,
  );
  late final _position = Tween(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_slide);

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _sheetPage(context, capturedThemes, builder);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return SlideTransition(position: _position, child: child);
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    super.key,
    required this.title,
    required this.body,
    this.footer,
  });
  final String title;
  final WidgetBuilder body;
  final WidgetBuilder? footer;

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final p = nn.palette;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.paddingOf(context).bottom;
    final close = MaterialLocalizations.of(context).closeButtonTooltip;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Glass(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NNRadius.sheet),
        ),
        shadow: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: p.text3.withValues(alpha: 0.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NNSpace.md,
                NNSpace.xs,
                NNSpace.xs,
                NNSpace.xs,
              ),
              child: Row(
                children: [
                  SizedBox(width: touchTarget(context)),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: NNType.headline.copyWith(color: p.text),
                      ),
                    ),
                  ),
                  Pressable(
                    key: const ValueKey('sheet-close'),
                    onTap: () => Navigator.of(context).maybePop(),
                    semanticLabel: close,
                    excludeChildSemantics: true,
                    child: PressGlow(
                      shape: const CircleBorder(),
                      child: Container(
                        width: touchTarget(context),
                        height: touchTarget(context),
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          color: p.surface2,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: p.text2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NNSpace.margin,
                  NNSpace.xs,
                  NNSpace.margin,
                  NNSpace.md,
                ),
                child: Builder(builder: body),
              ),
            ),
            if (footer != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  NNSpace.margin,
                  0,
                  NNSpace.margin,
                  NNSpace.md + (insets > 0 ? 0 : safe),
                ),
                child: Builder(builder: footer!),
              )
            else
              SizedBox(height: insets > 0 ? 0 : safe),
          ],
        ),
      ),
    );
  }
}

/// A sheet that grows out of the button that opened it: a circle from the button's centre widens
/// until it uncovers the whole sheet, tinted with the button's colour at first. Drag the top down
/// or tap outside to close; it shrinks back into the button.
class _MorphSheetRoute<T> extends PopupRoute<T> with _StepsBack<T> {
  _MorphSheetRoute({
    required this.origin,
    required this.tint,
    required this.builder,
    required this.barrierLabel,
    required this.capturedThemes,
  });

  final Rect origin;
  final Color tint;
  final WidgetBuilder builder;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.black.withValues(alpha: 0.3);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => NNMotion.sheetDuration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  late final CurvedAnimation _grow = CurvedAnimation(
    parent: animation!,
    curve: SpringCurve(NNMotion.sheet, NNMotion.sheetDuration),
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _sheetPage(context, capturedThemes, builder);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curve = _grow;
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (context, child) {
        final t = curve.value;
        final size = MediaQuery.sizeOf(context);
        final c = origin.center;
        // Far enough to uncover every corner of the screen.
        final far = [
          c,
          Offset(size.width - c.dx, c.dy),
          Offset(c.dx, size.height - c.dy),
          Offset(size.width - c.dx, size.height - c.dy),
        ].map((o) => o.distance).reduce((a, b) => a > b ? a : b);
        final r = ui.lerpDouble(origin.shortestSide / 2, far, t)!;
        return ClipPath(
          clipper: _CircleClipper(c, r),
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: ((t - 0.15) / 0.5).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1 - t * 2.2).clamp(0.0, 1.0),
                    child: CustomPaint(painter: _DotPainter(c, r, tint)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.center != center || old.radius != radius;
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.center, this.radius, this.color);
  final Offset center;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawCircle(center, radius, Paint()..color = color);

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.center != center || old.radius != radius || old.color != color;
}

/// Drag the sheet down past a third of a thumb's length (or flick it) to close it.
class _DragToClose extends StatefulWidget {
  const _DragToClose({required this.child});
  final Widget child;

  @override
  State<_DragToClose> createState() => _DragToCloseState();
}

class _DragToCloseState extends State<_DragToClose> {
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onVerticalDragUpdate: (d) =>
          setState(() => _dy = (_dy + d.delta.dy).clamp(0, double.infinity)),
      onVerticalDragEnd: (d) {
        if (_dy > 120 || (d.primaryVelocity ?? 0) > 700) {
          Navigator.of(context).maybePop();
        } else {
          setState(() => _dy = 0);
        }
      },
      child: Transform.translate(offset: Offset(0, _dy), child: widget.child),
    );
  }
}

/// The toast on screen, if any.
_ToastEntry? _toast;

class _ToastEntry {
  _ToastEntry(this.entry);
  final OverlayEntry entry;

  /// Taken off the overlay, or gone with it.
  bool gone = false;

  void remove() {
    if (gone) return;
    gone = true;
    entry
      ..remove()
      ..dispose();
  }
}

/// A toast: a glass capsule that floats above everything (sheets too) just over the tab bar for a
/// few seconds, with an optional action (Undo). A new toast replaces the current one. Text on it is
/// semibold, as on all glass; while a sheet is open it turns solid, because glass never sits on
/// glass. With a screen reader on, a toast with an action stays until it is used or replaced.
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
  Key? key,
  bool check = false,
}) {
  final overlay =
      Navigator.maybeOf(context, rootNavigator: true)?.overlay ??
      Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toast?.remove();
  late final _ToastEntry toast;
  toast = _ToastEntry(
    OverlayEntry(
      builder: (_) => _Toast(
        key: key,
        message: message,
        check: check,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        onGone: () {
          if (_toast == toast) _toast = null;
          toast.remove();
        },
        onDispose: () {
          if (_toast == toast) _toast = null;
          toast.gone = true;
        },
      ),
    ),
  );
  _toast = toast;
  overlay.insert(toast.entry);
}

class _Toast extends StatefulWidget {
  const _Toast({
    super.key,
    required this.message,
    required this.duration,
    required this.onGone,
    required this.onDispose,
    this.actionLabel,
    this.onAction,
    this.check = false,
  });
  final String message;

  /// Something got done: a check draws itself at the start.
  final bool check;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onGone;
  final VoidCallback onDispose;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer == null && !_leaving) {
      if (reduceMotion(context)) {
        _in.animateTo(1, duration: NNMotion.fade);
      } else {
        _in.springTo(1, NNMotion.standard);
      }
      final waits =
          MediaQuery.accessibleNavigationOf(context) && widget.onAction != null;
      _timer = Timer(
        waits ? const Duration(minutes: 10) : widget.duration,
        _leave,
      );
    }
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _in.animateTo(0, duration: NNMotion.fade);
    if (mounted) widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final p = nn.palette;
    final pad = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final still = reduceMotion(context);
    final width = MediaQuery.sizeOf(context).width;
    final side = ((width - NNLayout.maxContent) / 2).clamp(
      NNSpace.md,
      double.infinity,
    );
    final action = widget.actionLabel;
    final onAction = widget.onAction;
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: touchTarget(context) + 8),
      child: Row(
        children: [
          if (widget.check) ...[
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                shape: const CircleBorder(),
                color: p.success,
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => DrawnCheck(
                  progress: t,
                  color: p.surface,
                  size: 18,
                  stroke: 2.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                widget.message,
                style: NNType.subhead.copyWith(
                  color: p.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (action != null && onAction != null)
            Pressable(
              key: const ValueKey('toast-action'),
              onTap: () {
                _leave();
                onAction();
              },
              semanticLabel: action,
              excludeChildSemantics: true,
              haptic: Haptic.light,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: touchTarget(context),
                  minWidth: touchTarget(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: Text(
                      action,
                      style: NNType.subhead.copyWith(
                        color: p.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
    return Positioned(
      left: side,
      right: side,
      bottom: math.max(
        pad.bottom + NNLayout.tabBar + 24,
        keyboard + NNSpace.sm,
      ),
      child: AnimatedBuilder(
        animation: _in,
        builder: (context, child) {
          final t = _in.value;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, still ? 0 : (1 - t) * 16),
              child: child,
            ),
          );
        },
        child: Semantics(
          container: true,
          liveRegion: true,
          child: ValueListenableBuilder<double>(
            valueListenable: sheetBehind,
            builder: (context, behind, _) => behind > 0
                ? DecoratedBox(
                    decoration: ShapeDecoration(
                      color: p.surface,
                      shape: StadiumBorder(
                        side: BorderSide(color: p.separator),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 20,
                        end: 6,
                      ),
                      child: content,
                    ),
                  )
                : Glass(
                    padding: const EdgeInsetsDirectional.only(
                      start: 20,
                      end: 6,
                    ),
                    child: content,
                  ),
          ),
        ),
      ),
    );
  }
}
