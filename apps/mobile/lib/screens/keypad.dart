import 'package:flutter/material.dart';

import '../core/money.dart';
import '../design/glass.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../format.dart';

const _keys = ['7', '8', '9', '4', '5', '6', '1', '2', '3', '.', '0', 'back'];

/// Next keypad text after pressing [k]. Same rules as the web keypad: one decimal point per term,
/// no more decimals than the currency has, and + / − only after a number.
String keypadPress(String value, String k, String currency) {
  final decimals = decimalsOf(currency);
  if (k == 'back') {
    return value.isEmpty ? value : value.substring(0, value.length - 1);
  }
  if (k == '+' || k == '-') {
    if (value.isEmpty || RegExp(r'[+-]$').hasMatch(value)) return value;
    return value + k;
  }
  final term = value.split(RegExp('[+-]')).last;
  if (k == '.') {
    if (decimals == 0 || term.contains('.')) return value;
    return value + (term.isEmpty ? '0.' : '.');
  }
  final dot = term.indexOf('.');
  if (dot >= 0 && term.length - dot - 1 >= decimals) return value;
  if (term.replaceAll('.', '').length >= 12) return value;
  return value + k;
}

/// The amount keypad: big number on top, keys below, simple sums (12 + 8.5).
/// Digits stay left-to-right in Arabic too, like a calculator.
class Keypad extends StatelessWidget {
  const Keypad({
    super.key,
    required this.value,
    required this.onChanged,
    required this.currency,
    required this.lang,
    required this.label,
    this.shake = 0,
  });

  /// Goes up when the amount is missing: the amount shakes.
  final int shake;
  final String value;
  final ValueChanged<String> onChanged;
  final String currency;
  final String lang;
  final String label;

  void _press(String k) {
    final next = keypadPress(value, k, currency);
    if (next != value) {
      haptic(Haptic.selection);
      onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final decimals = decimalsOf(currency);
    final parsed = parseAmountExpression(value, currency);
    final isSum =
        value.length > 1 && RegExp('[+-]').hasMatch(value.substring(1));
    final shown = value.isEmpty
        ? (decimals > 0 ? '0.${'0' * decimals}' : '0')
        : value.replaceAll('-', ' − ').replaceAll('+', ' + ');
    final sumText = isSum && parsed != null
        ? '= ${money(parsed, currency, lang)}'
        : currency;

    Widget key(
      String k, {
      Color? bg,
      Color? fg,
      String? semantic,
      double height = 56,
    }) {
      final disabled = k == '.' && decimals == 0;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Pressable(
            key: ValueKey('key-$k'),
            onTap: disabled ? null : () => _press(k),
            semanticLabel: semantic ?? k,
            excludeChildSemantics: true,
            child: Opacity(
              opacity: disabled ? 0.3 : 1,
              child: PressGlow(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NNRadius.control),
                ),
                child: Container(
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg ?? p.surface,
                    borderRadius: BorderRadius.circular(NNRadius.control),
                  ),
                  child: k == 'back'
                      ? Icon(
                          Icons.backspace_outlined,
                          size: 24,
                          color: fg ?? p.text,
                        )
                      : Text(
                          k == '-' ? '−' : k,
                          style: NNType.title2.copyWith(
                            color: fg ?? p.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Semantics(
          label: label,
          value: isSum && parsed != null
              ? '$shown $sumText'
              : (value.isEmpty ? shown : money(parsed ?? 0, currency, lang)),
          liveRegion: true,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
            child: Column(
              children: [
                Shake(
                  trigger: shake,
                  haptic: false,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      shown,
                      key: const ValueKey('amount'),
                      textDirection: TextDirection.ltr,
                      style: NNType.amountHero.copyWith(
                        color: value.isEmpty ? p.text3 : p.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 22,
                  child: Text(
                    sumText,
                    key: const ValueKey('amount-sum'),
                    style: NNType.subhead.copyWith(color: p.text2),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: NNSpace.xs),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    for (var r = 0; r < 4; r++)
                      Row(
                        children: [
                          for (final k in _keys.sublist(r * 3, r * 3 + 3))
                            key(
                              k,
                              semantic: switch (k) {
                                'back' => MaterialLocalizations.of(
                                  context,
                                ).deleteButtonTooltip,
                                '.' =>
                                  lang == 'ar'
                                      ? 'فاصلة عشرية'
                                      : 'Decimal point',
                                _ => null,
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        key(
                          '+',
                          bg: p.accentSoft,
                          fg: p.onAccentSoft,
                          semantic: lang == 'ar' ? 'زائد' : 'Plus',
                          height: 120,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        key(
                          '-',
                          bg: p.accentSoft,
                          fg: p.onAccentSoft,
                          semantic: lang == 'ar' ? 'ناقص' : 'Minus',
                          height: 120,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
