// Dart port of packages/core/src/money.ts. Keep the two in step: test/core_test.dart mirrors
// packages/core/test/core.test.ts case for case.

import 'dart:math' as math;

import 'currencies.g.dart';

export 'currencies.g.dart' show CurrencyInfo, currencies;

final Map<String, CurrencyInfo> _byCode = {
  for (final c in currencies) c.code: c,
};

CurrencyInfo currency(String code) =>
    _byCode[code] ?? CurrencyInfo(code: code, decimals: 2, en: code, ar: code);

int decimalsOf(String code) => currency(code).decimals;

/// JavaScript's Math.round: halves go up, toward positive infinity. Dart's round() goes away from zero.
int jsRound(num x) => (x + 0.5).floor();

String _groupThousands(String intPart) =>
    intPart.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// 4550 AED -> "45.50"; never uses floating point for the digits.
String formatNumber(int minor, String code) {
  final d = decimalsOf(code);
  final neg = minor < 0;
  final s = minor.abs().toString().padLeft(d + 1, '0');
  final intPart = d > 0 ? s.substring(0, s.length - d) : s;
  final frac = d > 0 ? s.substring(s.length - d) : '';
  return '${neg ? '-' : ''}${_groupThousands(intPart)}${d > 0 ? '.$frac' : ''}';
}

/// "AED 45.50" in English, "45.50 د.إ" in Arabic.
String formatMoney(int minor, String code, String lang) {
  final n = formatNumber(minor, code);
  if (lang == 'ar') return '$n ${currency(code).arSymbol ?? code}';
  return '$code $n';
}

const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
const _persian = '۰۱۲۳۴۵۶۷۸۹';

/// Turn Arabic-Indic / Persian digits and separators into plain ASCII.
String normalizeDigits(String input) {
  final out = StringBuffer();
  for (final r in input.runes) {
    final ch = String.fromCharCode(r);
    final a = _arabicIndic.indexOf(ch);
    final p = _persian.indexOf(ch);
    if (a >= 0) {
      out.write(a);
    } else if (p >= 0) {
      out.write(p);
    } else if (ch == '٫') {
      out.write('.');
    } else if (ch == '٬') {
      out.write(',');
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

final _decimalComma = RegExp(r'^\d+,\d{1,3}$');
final _thousandsOnly = RegExp(r'^\d{1,3},\d{3}$');
final _plain = RegExp(r'^\d+(\.\d*)?$');
final _leadingDot = RegExp(r'^\.\d+$');
const _maxMinor = 900000000000000; // 9e14, same ceiling as the web and the API

/// Parse what a person typed into minor units. Accepts "45", "45.5", "45,50", "1,250.75", "٤٥٫٥".
/// Returns null if it is not a positive amount with at most `decimals` places.
int? parseAmount(String input, String code) {
  final d = decimalsOf(code);
  var s = normalizeDigits(input).trim().replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return null;
  // A single comma followed by 1..3 digits at the end, with no dot, is a decimal comma.
  if (!s.contains('.') &&
      _decimalComma.hasMatch(s) &&
      !_thousandsOnly.hasMatch(s)) {
    s = s.replaceFirst(',', '.');
  }
  s = s.replaceAll(',', '');
  if (!_plain.hasMatch(s) && !_leadingDot.hasMatch(s)) return null;
  final parts = s.split('.');
  final i = parts[0];
  final f = parts.length > 1 ? parts[1] : '';
  if (f.length > d) return null;
  if (i.length > 16) return null;
  final scale = math.pow(10, d).toInt();
  final fracDigits = (f + '0' * d).substring(0, d);
  final minor =
      int.parse(i.isEmpty ? '0' : i) * scale +
      (fracDigits.isEmpty ? 0 : int.parse(fracDigits));
  if (minor <= 0 || minor > _maxMinor) return null;
  return minor;
}

/// Minor units -> plain editable string, e.g. 4550 AED -> "45.50".
String minorToInput(int minor, String code) =>
    formatNumber(minor, code).replaceAll(',', '');

/// Convert minor units between currencies using a major-unit rate.
int convertMinor(int minor, String fromCode, String toCode, double rate) {
  if (fromCode == toCode) return minor;
  final shift = decimalsOf(toCode) - decimalsOf(fromCode);
  return jsRound(minor * rate * math.pow(10, shift));
}

final _expression = RegExp(r'^[0-9.,]+([+-][0-9.,]+)*$');
final _term = RegExp(r'[+-]?[0-9.,]+');

/// Amount keypad input with simple sums: "12 + 8.5", "100 - 15", "٤٥ + ٥".
/// Returns minor units, or null when any term is invalid or the total is not positive.
int? parseAmountExpression(String input, String code) {
  final s = normalizeDigits(
    input,
  ).replaceAll(RegExp('[−–]'), '-').replaceAll(RegExp(r'\s+'), '');
  if (s.isEmpty || !_expression.hasMatch(s)) return null;
  var total = 0;
  for (final m in _term.allMatches(s)) {
    final t = m.group(0)!;
    final sign = t.startsWith('-') ? -1 : 1;
    final v = parseAmount(t.replaceFirst(RegExp(r'^[+-]'), ''), code);
    if (v == null) return null;
    total += sign * v;
  }
  return total > 0 ? total : null;
}
