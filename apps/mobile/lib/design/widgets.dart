import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/identity.dart';
import '../data/session.dart';
import 'glass.dart';
import 'motion.dart';
import 'theme.dart';
import 'tokens.g.dart';

enum ButtonKind { filled, tinted, plain, danger }

/// Primary actions are filled accent capsules; secondary ones are tinted. 50pt tall, full width in sheets.
class NNButton extends StatelessWidget {
  const NNButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = ButtonKind.filled,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onTap;
  final ButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final (bg, fg) = switch (kind) {
      ButtonKind.filled => (p.accent, p.onAccent),
      ButtonKind.tinted => (p.accentSoft, p.onAccentSoft),
      ButtonKind.plain => (p.surface2, p.text),
      ButtonKind.danger => (p.dangerSoft, p.danger),
    };
    final enabled = onTap != null && !busy;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: NNType.headline.copyWith(color: fg),
    );
    return Pressable(
      onTap: enabled ? onTap : null,
      semanticLabel: label,
      excludeChildSemantics: true,
      // Solid buttons give no tap haptic; what they do answers (success or error).
      child: AnimatedOpacity(
        opacity: enabled || busy ? 1 : 0.45,
        duration: NNMotion.fade,
        // Pressed, it brightens a little as it shrinks.
        child: PressGlow(
          shape: const StadiumBorder(),
          child: Container(
            height: 50,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: NNSpace.lg),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: bg,
            ),
            // A compact button may sit in a row that gives it unbounded width, where Flexible
            // would throw; where the width is bounded the label shortens instead of overflowing.
            child: LayoutBuilder(
              builder: (context, c) => Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator.adaptive(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(fg),
                      ),
                    )
                  else if (icon != null)
                    Icon(icon, size: 20, color: fg),
                  if (busy || icon != null) const SizedBox(width: NNSpace.xs),
                  if (c.hasBoundedWidth) Flexible(child: text) else text,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A segmented control with a pill that slides to the selected segment.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final n = values.length;
    final i = values.indexOf(selected);
    final x = n == 1 ? 0.0 : -1 + 2 * i / (n - 1);
    return Container(
      height: touchTarget(context),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: p.surface2,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(3),
            child: AnimatedAlign(
              alignment: AlignmentDirectional(x, 0),
              duration: reduceMotion(context)
                  ? Duration.zero
                  : NNMotion.standardDuration,
              curve: SpringCurve(NNMotion.standard, NNMotion.standardDuration),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: p.surface,
                    shadows: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The segments span the full height so each one is a full-size touch target.
          Positioned.fill(
            child: Row(
              children: [
                for (final v in values)
                  Expanded(
                    child: Pressable(
                      key: ValueKey('seg-$v'),
                      onTap: v == selected ? () {} : () => onChanged(v),
                      selected: v == selected,
                      semanticLabel: label(v),
                      excludeChildSemantics: true,
                      haptic: Haptic.selection,
                      scale: 1,
                      child: Center(
                        child: Text(
                          label(v),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NNType.subhead.copyWith(
                            fontWeight: v == selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: v == selected ? p.text : p.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A person: their photo, their emoji or their initial, on the tone they chose (or one picked
/// from their name), so the same friend always looks the same. A photo falls back to the initial
/// while it loads or when it can't. [ring] draws a ring around it (on the people strip, the colour
/// of what you owe each other).
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.look,
    this.size = 36,
    this.ring,
  });
  final String name;
  final AvatarLook? look;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final l = look ?? AvatarLook.forName(name);
    final covers = nn.isDark ? NNCovers.dark : NNCovers.light;
    final c = covers[l.tone] ?? covers['violet']!;
    Widget initial() => Center(
      child: Text(
        initialOf(name),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: c.fg,
          height: 1.1,
        ),
        textScaler: TextScaler.noScaling,
      ),
    );
    final api = context
        .getInheritedWidgetOfExactType<SessionScope>()
        ?.notifier
        ?.api;
    final Widget face = switch (l.kind) {
      'emoji' => Center(
        child: Text(
          l.value!,
          style: TextStyle(fontSize: size * 0.54, height: 1.1),
          textScaler: TextScaler.noScaling,
        ),
      ),
      'photo' when api != null => Image.network(
        api.photoUrl(l.url!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (_, child, frame, sync) =>
            frame == null && !sync ? initial() : child,
        errorBuilder: (_, _, _) => initial(),
      ),
      _ => initial(),
    };
    Widget disc = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: ColoredBox(color: c.bg, child: face),
      ),
    );
    if (ring != null) {
      final w = math.max(2.0, size * 0.045);
      disc = Container(
        padding: EdgeInsets.all(w + 1),
        decoration: ShapeDecoration(
          shape: CircleBorder(
            side: BorderSide(color: ring!, width: w),
          ),
        ),
        child: disc,
      );
    }
    return ExcludeSemantics(child: disc);
  }
}

/// The drawn icon for each cover icon name. One icon family (Material rounded) throughout.
const coverIconData = <String, IconData>{
  'plane': Icons.flight_rounded,
  'beach': Icons.beach_access_rounded,
  'mountain': Icons.landscape_rounded,
  'car': Icons.directions_car_rounded,
  'home': Icons.home_rounded,
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'moon': Icons.nightlight_round,
  'party': Icons.celebration_rounded,
  'gift': Icons.card_giftcard_rounded,
  'cart': Icons.shopping_cart_rounded,
  'heart': Icons.favorite_rounded,
  'ball': Icons.sports_soccer_rounded,
  'work': Icons.work_rounded,
  'book': Icons.menu_book_rounded,
  'music': Icons.music_note_rounded,
};

/// A group's cover: its drawn icon on its tone, split on the diagonal into two soft halves like the
/// coin. Used for group cards and headers.
class CoverTile extends StatelessWidget {
  const CoverTile({super.key, required this.cover, this.size = 48});
  final Cover cover;
  final double size;

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final covers = nn.isDark ? NNCovers.dark : NNCovers.light;
    final c = covers[cover.tone] ?? covers['violet']!;
    final other = Color.lerp(c.bg, c.fg, nn.isDark ? 0.14 : 0.08)!;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.29),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.bg, c.bg, other, other],
            stops: const [0, 0.5, 0.5, 1],
          ),
        ),
        child: Icon(
          coverIconData[cover.icon] ?? Icons.restaurant_rounded,
          size: size * 0.5,
          color: c.fg,
        ),
      ),
    );
  }
}

/// An amount on one line. When it doesn't fit it shrinks, but never below body size; only then
/// does it take a second line.
class AmountText extends StatelessWidget {
  const AmountText(
    this.text, {
    super.key,
    required this.style,
    this.alignment = AlignmentDirectional.centerEnd,
    this.textAlign,
  });
  final String text;
  final TextStyle style;
  final AlignmentGeometry alignment;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final one = Text(text, style: style, maxLines: 1, softWrap: false);
        if (!c.hasBoundedWidth) return one;
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = tp.width;
        tp.dispose();
        if (width <= c.maxWidth) return one;
        final size = style.fontSize ?? NNType.body.fontSize!;
        final floor = math.min(1.0, NNType.body.fontSize! / size);
        if (c.maxWidth / width >= floor) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            child: one,
          );
        }
        return Text(
          text,
          style: style.copyWith(
            fontSize: math.min(size, NNType.body.fontSize!),
          ),
          maxLines: 2,
          textAlign: textAlign,
        );
      },
    );
  }
}

/// A selectable chip for people and categories.
class NNChip extends StatelessWidget {
  const NNChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? trailing;

  /// Instead of [icon]: a small avatar (who paid).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final fg = selected ? p.onAccentSoft : p.text;
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      child: PressGlow(
        shape: const StadiumBorder(),
        child: AnimatedContainer(
          duration: NNMotion.fade,
          constraints: BoxConstraints(minHeight: touchTarget(context)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? p.accent : p.edge,
                width: selected ? 1.5 : 1,
              ),
            ),
            color: selected ? p.accentSoft : p.surface,
          ),
          // In a wrap (bounded) a long label wraps onto a second line; in a scrolling row it doesn't need to.
          child: LayoutBuilder(
            builder: (context, c) {
              final text = Text(
                label,
                maxLines: c.hasBoundedWidth ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: NNType.subhead.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              );
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 6),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                  ],
                  if (c.hasBoundedWidth) Flexible(child: text) else text,
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing!,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A solid content card. Content is never glass.
class NNCard extends StatelessWidget {
  const NNCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NNSpace.md),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(NNRadius.card),
      ),
      child: child,
    );
  }
}

/// A small section label in sentence case, above a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: NNSpace.xxs,
        bottom: NNSpace.xs,
        top: NNSpace.md,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: NNType.footnote.copyWith(
            color: p.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Empty screens say what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.art,
  });
  final String title;
  final String body;
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: NNSpace.xxl,
        horizontal: NNSpace.md,
      ),
      child: Column(
        children: [
          if (art != null) ...[art!, const SizedBox(height: NNSpace.lg)],
          Text(
            title,
            textAlign: TextAlign.center,
            style: NNType.title3.copyWith(color: p.text),
          ),
          const SizedBox(height: NNSpace.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: NNType.callout.copyWith(color: p.text2),
          ),
        ],
      ),
    );
  }
}

/// A labelled text field. The label sits above, the hint inside, the error below in words.
class NNField extends StatelessWidget {
  const NNField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.help,
    this.error,
    this.autofocus = false,
    this.onSubmitted,
    this.textInputAction,
    this.maxLength = 60,
    this.fieldKey,
    this.shake = 0,
  });

  /// Goes up with each error: the field shakes (see [Shake]).
  final int shake;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? help;
  final String? error;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final int maxLength;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    // MergeSemantics: the visible label above is the field's name for VoiceOver and TalkBack too.
    return Shake(
      trigger: shake,
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: NNSpace.xxs,
                bottom: 6,
              ),
              child: Text(
                label,
                style: NNType.footnote.copyWith(
                  color: p.text2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextField(
              key: fieldKey,
              controller: controller,
              autofocus: autofocus,
              onSubmitted: onSubmitted,
              textInputAction: textInputAction,
              maxLength: maxLength,
              textCapitalization: TextCapitalization.sentences,
              style: NNType.body.copyWith(color: p.text),
              decoration: InputDecoration(
                hintText: hint,
                counterText: '',
                errorText: error,
                helperText: help,
                helperStyle: NNType.footnote.copyWith(color: p.text3),
                helperMaxLines: 3,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A form's error in words, read out when it appears; it shakes each time [shake] goes up.
class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key, required this.shake, this.textKey});
  final String text;
  final int shake;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Shake(
      trigger: shake,
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          key: textKey,
          style: NNType.subhead.copyWith(color: p.danger),
        ),
      ),
    );
  }
}

/// Height of a [SearchFieldBody] at the person's text size: at least a touch target.
double searchFieldHeight(BuildContext context) => math.max(
  touchTarget(context),
  28 +
      MediaQuery.textScalerOf(context).scale(NNType.body.fontSize!) *
          NNType.body.height!,
);

/// The inside of a search capsule: a magnifier, the field (named "Search" for screen readers) and a
/// clear button once something is typed. A focus ring goes round the capsule while it has focus.
/// The capsule itself (glass or a plain fill) comes from the caller.
class SearchFieldBody extends StatelessWidget {
  const SearchFieldBody({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.ring,
    this.onSubmitted,
    this.semibold = false,
    this.fieldKey,
    this.clearKey,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onChanged;
  final VoidCallback? onSubmitted;
  final Color ring;

  /// On glass, typed text is semibold.
  final bool semibold;
  final Key? fieldKey;
  final Key? clearKey;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, controller]),
      // Its edge shows (1 pt); focused, a 2 pt outline in [ring] (the accent).
      builder: (context, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: focusNode.hasFocus
                ? BorderSide(color: ring, width: 2)
                : BorderSide(color: p.edge),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            ExcludeSemantics(
              child: Icon(Icons.search_rounded, size: 20, color: p.text2),
            ),
            const SizedBox(width: NNSpace.xs),
            Expanded(
              child: MergeSemantics(
                child: Semantics(
                  label: s.search,
                  child: TextField(
                    key: fieldKey,
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmitted?.call(),
                    style: NNType.body.copyWith(
                      color: p.text,
                      fontWeight: semibold ? FontWeight.w600 : null,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: NNType.body.copyWith(color: p.text2),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              Pressable(
                key: clearKey,
                onTap: () {
                  controller.clear();
                  onChanged();
                },
                semanticLabel: s.close,
                excludeChildSemantics: true,
                child: SizedBox.square(
                  dimension: touchTarget(context),
                  child: Icon(Icons.close_rounded, size: 18, color: p.text2),
                ),
              )
            else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}
