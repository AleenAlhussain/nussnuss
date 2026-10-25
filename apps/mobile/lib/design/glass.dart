import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

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

/// The navigation layer material: a blurred, saturated, lightly tinted pane with a rim of light along
/// the top edge. Use it only for things that float above content (bars, the add button, sheets) and never
/// put glass inside glass. With Frosted (chosen, or forced by Increase Contrast) it becomes a solid pane
/// with a hairline border, so text on it always meets contrast.
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

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? s.fill,
        borderRadius: r,
        border: s.bordered && !tinted
            ? Border.all(color: nn.palette.separator)
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!s.bordered || tinted) {
      body = CustomPaint(
        foregroundPainter: _RimPainter(
          r,
          tinted ? const Color(0x73FFFFFF) : s.highlight,
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

/// Light from above: a 1px rim that is bright at the top edge and fades out down the sides.
class _RimPainter extends CustomPainter {
  _RimPainter(this.radius, this.color);
  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color,
          color.withValues(alpha: 0),
          color.withValues(alpha: color.a * 0.3),
        ],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    canvas.drawRRect(radius.toRRect(rect).deflate(0.5), paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.color != color || old.radius != radius;
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

enum Haptic { none, selection, light, medium, success }

void haptic(Haptic h) {
  switch (h) {
    case Haptic.none:
      return;
    case Haptic.selection:
      HapticFeedback.selectionClick();
    case Haptic.light:
      HapticFeedback.lightImpact();
    case Haptic.medium:
      HapticFeedback.mediumImpact();
    case Haptic.success:
      HapticFeedback.heavyImpact();
  }
}

/// Anything tappable: shrinks a little under the finger on a spring and settles back with a small bounce.
/// With Reduce Motion it dims instead. Exposes itself as a button to VoiceOver and TalkBack.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.scale = 0.96,
    this.haptic = Haptic.none,
    this.selected,
    this.checked,
    this.excludeChildSemantics = false,
  });

  final Widget child;
  final VoidCallback? onTap;
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
    if (_enabled) _press.springTo(1, NNMotion.standard);
  }

  void _up() => _press.springTo(0, NNMotion.bouncy);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return Semantics(
      button: widget.checked == null,
      enabled: _enabled,
      selected: widget.selected,
      checked: widget.checked,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeChildSemantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onTap: _enabled
            ? () {
                haptic(widget.haptic);
                widget.onTap!();
              }
            : null,
        child: AnimatedBuilder(
          animation: _press,
          child: widget.child,
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
      scale: 0.9,
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
  const AddButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<AddButton> {
  Alignment _light = const Alignment(-0.4, -0.6);

  void _move(Offset local) {
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
        onTap: widget.onTap,
        semanticLabel: widget.label,
        excludeChildSemantics: true,
        haptic: Haptic.light,
        scale: 0.92,
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
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Floating glass capsule with the tabs. The selected tab sits in a filled capsule; while the person
/// scrolls down the bar shrinks and the other labels tuck away, then it comes back on scroll up.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.compact = false,
  });

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool compact;

  static TextStyle _labelStyle(Color color) =>
      NNType.subhead.copyWith(fontWeight: FontWeight.w600, color: color);

  /// Width the bar needs with every label showing, at the person's text size.
  double _fullWidth(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    var w = 12.0;
    for (final item in items) {
      final tp = TextPainter(
        text: TextSpan(
          text: item.label,
          style: _labelStyle(const Color(0xFF000000)),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      w += 32 + 22 + 8 + tp.width;
      tp.dispose();
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    // With large text or long labels, the unselected labels tuck away (as when scrolling), and as a last
    // resort the whole capsule scales down, so the bar never overflows the screen.
    return LayoutBuilder(
      builder: (context, box) {
        final squeezed =
            box.hasBoundedWidth && _fullWidth(context) > box.maxWidth;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.bottomStart,
          child: _bar(context, compact || squeezed),
        );
      },
    );
  }

  Widget _bar(BuildContext context, bool compact) {
    final p = NNTheme.of(context).palette;
    final still = reduceMotion(context);
    final duration = still ? NNMotion.fade : NNMotion.standardDuration;
    return AnimatedScale(
      scale: this.compact && !still ? 0.9 : 1,
      alignment: AlignmentDirectional.bottomStart.resolve(
        Directionality.of(context),
      ),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: Glass(
        padding: const EdgeInsets.all(6),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                Pressable(
                  key: ValueKey('tab-$i'),
                  onTap: () => onChanged(i),
                  haptic: Haptic.selection,
                  selected: i == index,
                  semanticLabel: items[i].label,
                  excludeChildSemantics: true,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: i == index
                          ? p.surface2
                          : p.surface2.withValues(alpha: 0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          i == index ? items[i].selectedIcon : items[i].icon,
                          size: 22,
                          color: i == index ? p.text : p.text2,
                        ),
                        AnimatedSize(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          child: compact && i != index
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 8,
                                  ),
                                  child: Text(
                                    items[i].label,
                                    style: NNType.subhead.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: i == index ? p.text : p.text2,
                                    ),
                                  ),
                                ),
                        ),
                      ],
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

/// Opens a glass sheet: grabber, a title with a close button, scrollable content and an optional footer
/// that stays above the keyboard. Contents are solid fills: never glass on glass.
Future<T?> showNNSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  WidgetBuilder? footer,
  Key? key,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    sheetAnimationStyle: AnimationStyle(
      duration: NNMotion.standardDuration,
      reverseDuration: const Duration(milliseconds: 250),
    ),
    builder: (ctx) =>
        _SheetFrame(key: key, title: title, body: builder, footer: footer),
  );
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
                    scale: 0.9,
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
