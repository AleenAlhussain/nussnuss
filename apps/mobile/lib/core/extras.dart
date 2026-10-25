// Dart port of packages/core/src/extras.ts. Change both together.

import 'money.dart';
import 'split.dart';
import 'types.dart';

/// One line of a receipt: its price (minor units of the expense currency) and who had it.
class ReceiptItem {
  const ReceiptItem(this.price, this.members);
  final int price;
  final List<String> members;
}

/// Splits a receipt by item. Each item is shared equally by the people who had it; whatever the
/// items do not cover (tax, service, rounding) is shared in proportion to what each person had.
/// Returns exact split items that add up to [total], or null when the items are empty or come to
/// more than the total. Items with no price or nobody on them are ignored.
({List<SplitItem> items, int rest})? itemizedSplit(
  int total,
  List<ReceiptItem> items,
  List<String> memberIds,
) {
  final sub = {for (final id in memberIds) id: 0};
  var sum = 0;
  for (final it in items) {
    final who = [
      for (final id in memberIds)
        if (it.members.contains(id)) id,
    ];
    if (it.price <= 0 || who.isEmpty) continue;
    sum += it.price;
    final parts = allocate(it.price, [for (final _ in who) 1]);
    for (var i = 0; i < who.length; i++) {
      sub[who[i]] = sub[who[i]]! + parts[i];
    }
  }
  if (sum <= 0 || sum > total) return null;
  final rest = total - sum;
  final extra = allocate(rest, [for (final id in memberIds) sub[id]!]);
  return (
    items: [
      for (var i = 0; i < memberIds.length; i++)
        SplitItem(memberIds[i], sub[memberIds[i]]! + extra[i]),
    ],
    rest: rest,
  );
}

const payToKinds = [
  'iban',
  'instapay',
  'stcpay',
  'phone',
  'paypal',
  'wise',
  'link',
];

/// A way someone gets paid, as saved on their account.
class PayTo {
  const PayTo(this.kind, this.value, {this.label});
  final String kind;
  final String value;
  final String? label;

  factory PayTo.fromJson(Map<String, dynamic> j) => PayTo(
    j['kind'] as String? ?? 'link',
    j['value'] as String? ?? '',
    label: j['label'] as String?,
  );

  Map<String, Object> toJson() => {
    'kind': kind,
    'value': value,
    if (label != null && label!.isNotEmpty) 'label': label!,
  };

  @override
  bool operator ==(Object other) =>
      other is PayTo &&
      other.kind == kind &&
      other.value == value &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, value, label);
}

/// What "Pay with" does: open a link (with the amount where the service supports it) or copy a
/// detail.
sealed class PayAction {
  const PayAction();
}

class PayOpen extends PayAction {
  const PayOpen(this.url);
  final String url;

  @override
  bool operator ==(Object other) => other is PayOpen && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'PayOpen($url)';
}

class PayCopy extends PayAction {
  const PayCopy(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is PayCopy && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'PayCopy($text)';
}

final _https = RegExp(r'^https://', caseSensitive: false);
final _paypalMe = RegExp(
  r'^https://(www\.)?paypal\.me/([^/?#]+)/?$',
  caseSensitive: false,
);

PayAction payAction(PayTo p, int amount, String code) {
  final v = p.value.trim();
  switch (p.kind) {
    case 'iban':
    case 'stcpay':
    case 'phone':
      return PayCopy(v);
    case 'instapay':
      return _https.hasMatch(v) ? PayOpen(v) : PayCopy(v);
    case 'paypal':
      // paypal.me/name takes the amount and currency as the next path part: paypal.me/name/12.50USD
      final m = _paypalMe.firstMatch(v);
      return m != null && amount > 0
          ? PayOpen(
              'https://paypal.me/${m.group(2)}/${minorToInput(amount, code)}$code',
            )
          : PayOpen(v);
    default:
      return PayOpen(v);
  }
}

/// Spending per category in the group currency, largest first. Categories with nothing spent are
/// left out.
List<({String category, int amount})> spendingByCategory(
  List<({ExpenseLike expense, String category})> expenses,
  String groupCurrency,
) {
  final by = <String, int>{};
  for (final e in expenses) {
    by[e.category] =
        (by[e.category] ?? 0) +
        expenseInGroupCurrency(e.expense, groupCurrency);
  }
  final out = [
    for (final entry in by.entries)
      if (entry.value > 0) (category: entry.key, amount: entry.value),
  ];
  out.sort((a, b) {
    final c = b.amount.compareTo(a.amount);
    return c != 0 ? c : a.category.compareTo(b.category);
  });
  return out;
}

final _receiptSkip = RegExp(
  r'\b(sub\s*-?total|total|vat|tax|service|svc|tip|gratuity|change|cash|card|visa|master|balance|amount due|paid|discount|round(ing)?|qty|invoice|receipt|tel|phone|date|time|table|order|bill no|trn)\b|المجموع|الإجمالي|الاجمالي|ضريبة|خدمة|نقد|الباقي|المدفوع|خصم|فاتورة|هاتف|تاريخ|طاولة',
  caseSensitive: false,
);
final _receiptTotal = RegExp(
  r'\b(grand\s*total|total(\s*due)?|amount\s*due|net\s*total)\b|الإجمالي|الاجمالي|المجموع\s*الكلي|المبلغ\s*المستحق',
  caseSensitive: false,
);
final _priceAtEnd = RegExp(
  r'^(.*?)[\s:.\-–]*(\d{1,3}(?:,\d{3})+(?:\.\d{1,3})?|\d+(?:[.,]\d{1,3})?)\s*([A-Za-z]{2,3}|د\.إ|ر\.س|ر\.ع|د\.ك|د\.ب|ر\.ق|ج\.م)?\s*$',
);
final _subtotal = RegExp(r'sub\s*-?total', caseSensitive: false);
final _letter = RegExp(r'\p{L}', unicode: true);

/// Reads the text of a photographed receipt (from on-device text recognition) into items and the
/// total. Each line that ends in a price becomes an item ("2 x Burger 30.00" → Burger, 30.00); tax,
/// service, payment and header lines are skipped; a "Total" line gives the total. Arabic digits are
/// fine.
({List<({String name, int price})> items, int? total}) parseReceipt(
  String text,
  String code,
) {
  final items = <({String name, int price})>[];
  int? total;
  for (final raw in normalizeDigits(text).split(RegExp(r'\r?\n'))) {
    final line = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty) continue;
    final m = _priceAtEnd.firstMatch(line);
    if (m == null) continue;
    final price = parseAmount(m.group(2)!, code);
    if (price == null || price == 0) continue;
    final name = m
        .group(1)!
        .replaceFirst(RegExp(r'^\d+\s*[x×*]\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*[x×*]\s*\d+$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'[\s:.\-–]+$'), '')
        .trim();
    if (_receiptTotal.hasMatch(line) && !_subtotal.hasMatch(line)) {
      total = (total ?? 0) > price ? total : price;
      continue;
    }
    if (name.isEmpty ||
        !_letter.hasMatch(name) ||
        _receiptSkip.hasMatch(name)) {
      continue;
    }
    items.add((
      name: name.length > 60 ? name.substring(0, 60) : name,
      price: price,
    ));
  }
  return (items: items, total: total);
}
