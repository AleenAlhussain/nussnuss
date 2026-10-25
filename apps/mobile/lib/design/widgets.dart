import 'package:flutter/material.dart';

import 'glass.dart';
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
    return Pressable(
      onTap: enabled ? onTap : null,
      semanticLabel: label,
      excludeChildSemantics: true,
      haptic: kind == ButtonKind.filled ? Haptic.light : Haptic.none,
      child: AnimatedOpacity(
        opacity: enabled || busy ? 1 : 0.45,
        duration: NNMotion.fade,
        child: Container(
          height: 50,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: NNSpace.lg),
          decoration: ShapeDecoration(shape: const StadiumBorder(), color: bg),
          child: Row(
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NNType.headline.copyWith(color: fg),
                ),
              ),
            ],
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
              curve: Curves.easeOutBack,
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

/// Initials on a soft color picked from the name, so the same friend always looks the same.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 36});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final pairs = [
      (p.accentSoft, p.onAccentSoft),
      (p.successSoft, p.success),
      (p.dangerSoft, p.danger),
      (p.surface2, p.text),
    ];
    final h = name.runes.fold<int>(0, (a, r) => (a * 31 + r) & 0x7fffffff);
    final (bg, fg) = pairs[h % pairs.length];
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? String.fromCharCodes(parts.first.runes.take(1))
        : String.fromCharCodes(parts.first.runes.take(1)) +
              String.fromCharCodes(parts.last.runes.take(1));
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: ShapeDecoration(shape: const CircleBorder(), color: bg),
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
          textScaler: TextScaler.noScaling,
        ),
      ),
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
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? trailing;

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
      child: AnimatedContainer(
        duration: NNMotion.fade,
        constraints: BoxConstraints(minHeight: touchTarget(context)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? p.accent : p.separator,
              width: selected ? 1.5 : 1,
            ),
          ),
          color: selected ? p.accentSoft : p.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: NNType.subhead.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
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
  });

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
    return MergeSemantics(
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
    );
  }
}
