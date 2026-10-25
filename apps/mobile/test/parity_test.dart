// Replays random groups computed by the TypeScript core (tool/parity.mjs) through the Dart port.
// CI writes test/parity.json first; locally the test is skipped when the file is missing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nussnuss/core/money.dart';
import 'package:nussnuss/core/split.dart';
import 'package:nussnuss/core/types.dart';

void main() {
  final file = File('test/parity.json');
  test('Dart and TypeScript agree on every random group', () {
    final cases = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    expect(cases, isNotEmpty);
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final g0 = c['g'] as Map<String, dynamic>;
      final ids = (c['ids'] as List<dynamic>).cast<String>();
      final g = GroupLike(
        currency: g0['currency'] as String,
        memberIds: ids,
        expenses: [
          for (final e
              in (g0['expenses'] as List<dynamic>).cast<Map<String, dynamic>>())
            ExpenseLike(
              amount: e['amount'] as int,
              currency: e['currency'] as String,
              rate: (e['rate'] as num).toDouble(),
              paidBy: e['paidBy'] as String,
              mode: SplitMode.parse(e['mode'] as String),
              items: [
                for (final i
                    in (e['items'] as List<dynamic>)
                        .cast<Map<String, dynamic>>())
                  SplitItem(i['memberId'] as String, i['value'] as int),
              ],
            ),
        ],
        payments: [
          for (final p
              in (g0['payments'] as List<dynamic>).cast<Map<String, dynamic>>())
            PaymentLike(
              from: p['from'] as String,
              to: p['to'] as String,
              amount: p['amount'] as int,
            ),
        ],
      );
      final bal = computeBalances(g);
      final why = jsonEncode(c['g']);
      expect(
        bal,
        (c['bal'] as Map<String, dynamic>).cast<String, int>(),
        reason: why,
      );
      expect(simplifyDebts(bal, ids), [
        for (final t
            in (c['transfers'] as List<dynamic>).cast<Map<String, dynamic>>())
          Transfer.fromJson(t),
      ], reason: why);
      expect(groupTotal(g), c['total'], reason: why);
      expect(
        formatMoney(bal[ids.first]!, g.currency, 'ar'),
        c['fmt'],
        reason: why,
      );
      for (final p in c['parsed'] as List<dynamic>) {
        final input = (p as List<dynamic>)[0] as String;
        expect(parseAmountExpression(input, g.currency), p[1], reason: input);
        expect(parseAmount(input, g.currency), p[2], reason: input);
      }
    }
  }, skip: file.existsSync() ? false : 'run tool/parity.mjs first');
}
