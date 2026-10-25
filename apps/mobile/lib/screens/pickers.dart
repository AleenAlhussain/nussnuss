import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';

/// A choice that opens a picker: looks like a field, shows the value and a chevron. Pickers are
/// glass sheets (menus float on the navigation layer).
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  /// What is being picked, for screen readers (the visible label sits above).
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label, $value',
      excludeChildSemantics: true,
      child: PressGlow(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NNRadius.control),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(
            horizontal: NNSpace.md,
            vertical: NNSpace.sm,
          ),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(NNRadius.control),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NNType.body.copyWith(color: p.text),
                ),
              ),
              const SizedBox(width: NNSpace.xs),
              Icon(Icons.unfold_more_rounded, size: 20, color: p.text2),
            ],
          ),
        ),
      ),
    );
  }
}

String currencyLabel(String code, String lang) {
  for (final c in currencies) {
    if (c.code == code) return '${c.code} · ${c.name(lang)}';
  }
  return code;
}

/// Picks a currency from a glass sheet, with a filter at the top. Returns the code, or null.
Future<String?> showCurrencyPicker(
  BuildContext context, {
  required String selected,
  required String title,
}) {
  return showNNSheet<String>(
    context,
    key: const ValueKey('currency-picker'),
    title: title,
    builder: (_) => _CurrencyList(selected: selected),
  );
}

class _CurrencyList extends StatefulWidget {
  const _CurrencyList({required this.selected});
  final String selected;

  @override
  State<_CurrencyList> createState() => _CurrencyListState();
}

class _CurrencyListState extends State<_CurrencyList> {
  final _q = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final k = _q.text.trim().toLowerCase();
    final shown = [
      for (final c in currencies)
        if (k.isEmpty ||
            c.code.toLowerCase().contains(k) ||
            c.name('en').toLowerCase().contains(k) ||
            c.name('ar').contains(k))
          c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: p.surface2,
          ),
          child: SearchFieldBody(
            controller: _q,
            focusNode: _focus,
            hint: s.search,
            onChanged: () => setState(() {}),
            ring: p.focus,
            fieldKey: const ValueKey('currency-search'),
          ),
        ),
        const SizedBox(height: NNSpace.md),
        NNCard(
          padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 0.5, color: p.separator),
                Pressable(
                  key: ValueKey('currency-${shown[i].code}'),
                  onTap: () => Navigator.of(context).pop(shown[i].code),
                  checked: shown[i].code == widget.selected,
                  semanticLabel: currencyLabel(shown[i].code, s.lang),
                  excludeChildSemantics: true,
                  haptic: Haptic.selection,
                  scale: 0.98,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 50),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            shown[i].code,
                            style: NNType.headline.copyWith(color: p.text),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            shown[i].name(s.lang),
                            style: NNType.body.copyWith(color: p.text2),
                          ),
                        ),
                        if (shown[i].code == widget.selected)
                          Icon(Icons.check_rounded, color: p.accent),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Picks a day from a calendar in a glass sheet. Returns the day, or null.
Future<DateTime?> showDateSheet(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) {
  return showNNSheet<DateTime>(
    context,
    key: const ValueKey('date-picker'),
    title: title,
    builder: (ctx) => CalendarDatePicker(
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      onDateChanged: (d) => Navigator.of(ctx).pop(d),
    ),
  );
}
