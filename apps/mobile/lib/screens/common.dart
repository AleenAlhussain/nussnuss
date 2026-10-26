// Small pieces Home, a person, Activity and a group share: how a balance is coloured, how long
// ago something happened, reminding and paying someone.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/extras.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../format.dart';
import '../l10n/strings.g.dart';

/// Owing is never red: what you get back is green, what you owe is in the text colour, even is
/// quiet. Red is for errors, deleting and late payments only.
Color balanceColor(NNPalette p, int signed) =>
    signed > 0 ? p.success : (signed < 0 ? p.text : p.text2);

/// A template like "owes {amount}" without its amount, to sit above the amount itself.
String wordsOnly(String template) =>
    template.replaceAll('{amount}', '').replaceAll('  ', ' ').trim();

/// When something happened, short: the time today, "Yesterday", the weekday within the week, the
/// date before that. Western digits, as everywhere in the app.
String whenLabel(DateTime at, NNStrings s, {DateTime? now}) {
  final today = dayKey(now ?? clock());
  final days = today.difference(dayKey(at)).inDays;
  final DateFormat f;
  if (days <= 0) {
    f = DateFormat.jm(s.lang);
  } else if (days == 1) {
    return s.yesterday;
  } else if (days < 7) {
    f = DateFormat.E(s.lang);
  } else {
    f = DateFormat('d MMM', s.lang);
  }
  return (f..useNativeDigits = false).format(at);
}

/// A short date ("3 Oct") in the person's language with Western digits.
String dateLabel(DateTime at, NNStrings s) =>
    (DateFormat('d MMM', s.lang)..useNativeDigits = false).format(at);

/// An amount with its sign: "+AED 55.00", "−AED 48.00", for amounts that go either way.
String signedMoney(int signed, String currency, NNStrings s) {
  final m = money(signed.abs(), currency, s.lang);
  if (signed > 0) return '+$m';
  if (signed < 0) return '−$m';
  return m;
}

/// The name of a way to get paid ("Bank (IBAN)", or the person's own label).
String payMethodName(NNStrings s, PayTo x) =>
    x.label?.isNotEmpty == true ? x.label! : s.raw('pay_${x.kind}');

/// Opens WhatsApp with [text]; the share sheet when WhatsApp is not there.
Future<void> sendReminder(Session session, String text) async {
  final opened = await session.device.open(
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
  );
  if (!opened) await session.device.share(text: text);
}

/// Pays someone the way they shared: opens the bank or wallet link, or copies the number, then
/// says to mark it as paid afterwards.
Future<void> payWithMethod(
  BuildContext context,
  PayTo p, {
  required int amount,
  required String currency,
}) async {
  final session = SessionScope.read(context);
  final s = session.s;
  final method = payMethodName(s, p);
  void toast(String text) {
    if (context.mounted) {
      showToast(context, text, key: const ValueKey('toast'));
    }
  }

  Future<void> copy(String text) async {
    await session.device.copy(text);
    haptic(Haptic.success);
    toast('${s.fill(s.payCopied, {'method': method})} ${s.payThenMark}');
  }

  switch (payAction(p, amount, currency)) {
    case PayOpen(:final url):
      final ok = await session.device.open(Uri.parse(url));
      if (!ok) {
        await copy(url);
      } else {
        toast(s.payThenMark);
      }
    case PayCopy(:final text):
      await copy(text);
  }
}

/// "AED 55.00 and OMR 12.500": the amounts in each currency, for a reminder or a summary.
String amountsLine(List<Money> list, NNStrings s) {
  if (list.isEmpty) return '';
  final parts = [
    for (final m in list) money(m.amount.abs(), m.currency, s.lang),
  ];
  return [
    parts.first,
    for (final x in parts.skip(1)) s.fill(s.andAmount, {'amount': x}),
  ].join(' ');
}

/// Rows in one card with hairlines between them (lists on Home, a person, Activity).
class RowsCard extends StatelessWidget {
  const RowsCard({
    super.key,
    required this.children,
    this.muted = false,
    this.indent = 60,
  });
  final List<Widget> children;

  /// Settled things sit on a lighter card.
  final bool muted;

  /// Where the hairlines start (past the avatar or cover).
  final double indent;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
      decoration: BoxDecoration(
        color: muted ? p.surface.withValues(alpha: 0.6) : p.surface,
        borderRadius: BorderRadius.circular(NNRadius.card),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: indent,
                color: p.separator,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
