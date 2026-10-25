import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'core/money.dart';
import 'l10n/strings.g.dart';

String money(int minor, String code, String lang) =>
    formatMoney(minor, code, lang);

DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

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
  'fun' => Icons.celebration_rounded,
  'bills' => Icons.receipt_long_rounded,
  'shopping' => Icons.shopping_bag_rounded,
  _ => Icons.more_horiz_rounded,
};
