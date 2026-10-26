import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'core/money.dart';
import 'core/types.dart';
import 'l10n/strings.g.dart';

String money(int minor, String code, String lang) =>
    formatMoney(minor, code, lang);

DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Now" for labels like "2:05 PM" and the Today / Yesterday sections of Activity. Tests pin it,
/// so pictures of the screens do not change with the time they are taken.
DateTime Function() clock = DateTime.now;

/// "Today", "Yesterday", or "Mon 20 Oct", in the person's language with Western digits (same as the web).
String dayLabel(DateTime d, NNStrings s, {DateTime? now}) {
  final diff = dayKey(now ?? DateTime.now()).difference(dayKey(d)).inDays;
  if (diff == 0) return s.today;
  if (diff == 1) return s.yesterday;
  return (DateFormat('EEE d MMM', s.lang)..useNativeDigits = false).format(d);
}

/// Category icons. Rounded symbols, the same meaning on both platforms.
IconData categoryIcon(String c) => switch (c) {
  'food' => Icons.restaurant_rounded,
  'groceries' => Icons.shopping_basket_rounded,
  'transport' => Icons.directions_car_rounded,
  'stay' => Icons.bed_rounded,
  'fun' => Icons.local_activity_rounded,
  'bills' => Icons.receipt_long_rounded,
  'shopping' => Icons.shopping_bag_rounded,
  _ => Icons.sell_rounded,
};

/// "Sara pays Omar", "Sara pays you" or "You pay Omar": never "You pays".
String transferText(
  Transfer t, {
  required String me,
  required String Function(String id) nameOf,
  required NNStrings s,
}) {
  if (t.to == me) return s.fill(s.paysYou, {'name': nameOf(t.from)});
  if (t.from == me) return s.fill(s.youPayTo, {'name': nameOf(t.to)});
  return '${nameOf(t.from)} ${s.pays} ${nameOf(t.to)}';
}

/// The same sentence with the other person's name in bold, for cards.
TextSpan transferSpan(
  Transfer t, {
  required String me,
  required String Function(String id) nameOf,
  required NNStrings s,
  required Color soft,
}) {
  const bold = TextStyle(fontWeight: FontWeight.w600);
  TextSpan around(String template, String name) {
    final i = template.indexOf('{name}');
    return TextSpan(
      children: [
        TextSpan(text: template.substring(0, i)),
        TextSpan(text: name, style: bold),
        TextSpan(text: template.substring(i + 6)),
      ],
    );
  }

  if (t.to == me) return around(s.paysYou, nameOf(t.from));
  if (t.from == me) return around(s.youPayTo, nameOf(t.to));
  return TextSpan(
    children: [
      TextSpan(text: nameOf(t.from), style: bold),
      TextSpan(
        text: ' ${s.pays} ',
        style: TextStyle(color: soft),
      ),
      TextSpan(text: nameOf(t.to), style: bold),
    ],
  );
}
