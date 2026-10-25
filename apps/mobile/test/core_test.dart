// Mirrors packages/core/test/core.test.ts case for case. Change both together.
import 'package:flutter_test/flutter_test.dart';
import 'package:nussnuss/core/extras.dart';
import 'package:nussnuss/core/money.dart';
import 'package:nussnuss/core/split.dart';
import 'package:nussnuss/core/suggest.dart';
import 'package:nussnuss/core/types.dart';

const all3 = [SplitItem('a', 1), SplitItem('s', 1), SplitItem('o', 1)];

GroupLike mkGroup(
  List<ExpenseLike> expenses, [
  List<PaymentLike> payments = const [],
]) => GroupLike(
  currency: 'AED',
  memberIds: const ['a', 's', 'o'],
  expenses: expenses,
  payments: payments,
);

int sum(Map<String, int> r) => r.values.fold(0, (a, b) => a + b);

bool settles(Map<String, int> balances, List<Transfer> transfers) {
  final after = Map.of(balances);
  for (final t in transfers) {
    after[t.from] = after[t.from]! + t.amount;
    after[t.to] = after[t.to]! - t.amount;
  }
  return after.values.every((v) => v == 0);
}

void main() {
  group('allocate', () {
    test('100.00 between 3 adds up exactly, extra cent to the first', () {
      expect(allocate(10000, [1, 1, 1]), [3334, 3333, 3333]);
    });
    test('weights and zeros', () {
      expect(allocate(1000, [2, 0, 1, 1]), [500, 0, 250, 250]);
      expect(allocate(1, [1, 1, 1]), [1, 0, 0]);
      expect(allocate(0, [1, 1]), [0, 0]);
      expect(allocate(500, [0, 0]), [0, 0]);
    });
    test('many totals always sum exactly', () {
      for (var t = 1; t < 3000; t += 7) {
        expect(allocate(t, [1, 3, 7, 2, 5]).fold<int>(0, (a, b) => a + b), t);
      }
    });
  });

  group('money', () {
    test('format 0, 2 and 3 decimal currencies in both languages', () {
      expect(formatMoney(4550, 'AED', 'en'), 'AED 45.50');
      expect(formatMoney(4550, 'AED', 'ar'), '45.50 د.إ');
      expect(formatMoney(1250750, 'KWD', 'en'), 'KWD 1,250.750');
      expect(formatMoney(5, 'BHD', 'en'), 'BHD 0.005');
      expect(formatMoney(1500, 'JPY', 'en'), 'JPY 1,500');
      expect(formatMoney(-12345, 'USD', 'en'), 'USD -123.45');
    });
    test('parse what people type, including Arabic digits', () {
      expect(parseAmount('45', 'AED'), 4500);
      expect(parseAmount('45.5', 'AED'), 4550);
      expect(parseAmount('45,50', 'AED'), 4550);
      expect(parseAmount('1,250.75', 'AED'), 125075);
      expect(parseAmount('1,250', 'AED'), 125000);
      expect(parseAmount('٤٥٫٥', 'AED'), 4550);
      expect(parseAmount('۱۲', 'AED'), 1200);
      expect(parseAmount('2.125', 'KWD'), 2125);
      expect(parseAmount('2.125', 'AED'), isNull);
      expect(parseAmount('0', 'AED'), isNull);
      expect(parseAmount('abc', 'AED'), isNull);
      expect(parseAmount('', 'AED'), isNull);
      expect(parseAmount('-5', 'AED'), isNull);
      expect(parseAmount('.5', 'AED'), 50);
    });
    test('keypad sums', () {
      expect(parseAmountExpression('12 + 8.5', 'AED'), 2050);
      expect(parseAmountExpression('100-15', 'AED'), 8500);
      expect(parseAmountExpression('٤٥ + ٥', 'AED'), 5000);
      expect(parseAmountExpression('1.250+0.750', 'KWD'), 2000);
      expect(parseAmountExpression('10 - 10', 'AED'), isNull);
      expect(parseAmountExpression('5 *2', 'AED'), isNull);
      expect(parseAmountExpression('+', 'AED'), isNull);
      expect(parseAmountExpression('7', 'AED'), 700);
    });
    test('round trip to input and digit normalising', () {
      expect(minorToInput(125075, 'AED'), '1250.75');
      expect(normalizeDigits('١٢٣'), '123');
    });
    test('convert between currencies with different decimals', () {
      expect(convertMinor(10000, 'USD', 'AED', 3.6725), 36725);
      expect(convertMinor(1000, 'KWD', 'AED', 11.95), 1195);
      expect(convertMinor(10000, 'AED', 'KWD', 0.0837), 8370);
    });
  });

  group('splits and balances', () {
    test('validate', () {
      const ids = ['a', 's', 'o'];
      expect(
        validateSplit(0, SplitMode.equal, all3, 'a', ids),
        SplitError.noAmount,
      );
      expect(
        validateSplit(100, SplitMode.equal, const [], 'a', const ['a']),
        SplitError.noPeople,
      );
      expect(
        validateSplit(
          100,
          SplitMode.exact,
          const [SplitItem('a', 40), SplitItem('s', 50)],
          'a',
          const ['a', 's'],
        ),
        SplitError.exactMismatch,
      );
      expect(
        validateSplit(
          100,
          SplitMode.percent,
          const [SplitItem('a', 5000), SplitItem('s', 4000)],
          'a',
          const ['a', 's'],
        ),
        SplitError.percentMismatch,
      );
      expect(
        validateSplit(100, SplitMode.equal, all3, 'zz', ids),
        SplitError.payerMissing,
      );
      expect(
        validateSplit(
          100,
          SplitMode.percent,
          const [SplitItem('a', 6000), SplitItem('s', 4000)],
          'a',
          const ['a', 's'],
        ),
        isNull,
      );
    });

    test('equal split, one payer', () {
      final b = computeBalances(
        mkGroup([const ExpenseLike(amount: 30000, paidBy: 'a', items: all3)]),
      );
      expect(b, {'a': 20000, 's': -10000, 'o': -10000});
      expect(simplifyDebts(b, ['a', 's', 'o']), [
        const Transfer(from: 's', to: 'a', amount: 10000),
        const Transfer(from: 'o', to: 'a', amount: 10000),
      ]);
    });

    test('mixed modes and payments still sum to zero and settle', () {
      final g = mkGroup(
        const [
          ExpenseLike(amount: 10000, paidBy: 'a', items: all3),
          ExpenseLike(
            amount: 9000,
            paidBy: 's',
            mode: SplitMode.exact,
            items: [SplitItem('a', 2000), SplitItem('s', 7000)],
          ),
          ExpenseLike(
            amount: 777,
            paidBy: 'o',
            mode: SplitMode.percent,
            items: [
              SplitItem('a', 3333),
              SplitItem('s', 3333),
              SplitItem('o', 3334),
            ],
          ),
          ExpenseLike(
            amount: 1001,
            paidBy: 'a',
            mode: SplitMode.shares,
            items: [SplitItem('s', 2), SplitItem('o', 1)],
          ),
        ],
        const [PaymentLike(from: 's', to: 'a', amount: 500)],
      );
      final b = computeBalances(g);
      expect(sum(b), 0);
      final t = simplifyDebts(b, ['a', 's', 'o']);
      expect(t.length, lessThanOrEqualTo(2));
      expect(settles(b, t), isTrue);
    });

    test('foreign currency expense converts and still adds up', () {
      const e = ExpenseLike(
        amount: 10001,
        currency: 'USD',
        rate: 3.6725,
        paidBy: 's',
        items: all3,
      );
      expect(
        sum(owedInGroupCurrency(e, 'AED')),
        convertMinor(10001, 'USD', 'AED', 3.6725),
      );
      final g = mkGroup([e]);
      expect(sum(computeBalances(g)), 0);
      expect(groupTotal(g), 36729);
    });

    test(
      'ten people, sixty expenses: at most nine transfers and everyone settled',
      () {
        final ids = 'abcdefghij'.split('');
        var seed = 7;
        double rnd() => (seed = (seed * 16807) % 2147483647) / 2147483647;
        final expenses = List.generate(60, (_) {
          final picked = <String>{...ids.where((_) => rnd() > 0.3), 'a'};
          return ExpenseLike(
            amount: 1 + (rnd() * 50000).floor(),
            paidBy: ids[(rnd() * 10).floor()],
            items: [for (final id in picked) SplitItem(id, 1)],
          );
        });
        final g = GroupLike(
          currency: 'AED',
          memberIds: ids,
          expenses: expenses,
        );
        final b = computeBalances(g);
        expect(sum(b), 0);
        final t = simplifyDebts(b, ids);
        expect(t.length, lessThanOrEqualTo(9));
        expect(settles(b, t), isTrue);
      },
    );
  });

  group('title suggestions', () {
    test('recent titles first, then ideas for the hour and the kind of group, '
        'without repeats', () {
      const recent = [
        (title: 'Shawarma', category: 'food'),
        (title: 'shawarma ', category: 'food'),
        (title: 'Dinner', category: 'food'),
        (title: 'Fuel', category: 'transport'),
      ];
      String label(String k) => k[0].toUpperCase() + k.substring(1);
      expect(suggestTitles(recent: recent, hour: 21, label: label), const [
        Suggestion(title: 'Shawarma', category: 'food'),
        Suggestion(title: 'Dinner', category: 'food'),
        Suggestion(key: 'groceries', category: 'groceries'),
        Suggestion(key: 'taxi', category: 'transport'),
      ]);
      List<String?> keys(List<Suggestion> s) => s.map((x) => x.key).toList();
      expect(keys(suggestTitles(recent: const [], hour: 9, emoji: '🏠')), [
        'groceries',
        'rent',
        'internet',
        'electricity',
      ]);
      expect(
        keys(suggestTitles(recent: const [], hour: 2, emoji: '🌙', n: 2)),
        ['suhoor', 'iftar'],
      );
      expect(keys(suggestTitles(recent: const [], hour: 13, emoji: '✈️')), [
        'lunch',
        'taxi',
        'hotel',
        'tickets',
      ]);
    });
  });

  group('receipt by item', () {
    const ids = ['a', 's', 'o'];
    test('items shared by who had them, tax and service in proportion, '
        'adds up exactly', () {
      // 100.00 bill: a's burger 40, s and o share a 30 pizza, everyone shares 15 fries; 15 tax.
      final r = itemizedSplit(10000, const [
        ReceiptItem(4000, ['a']),
        ReceiptItem(3000, ['s', 'o']),
        ReceiptItem(1500, ['a', 's', 'o']),
      ], ids)!;
      expect(r.rest, 1500);
      expect(r.items.fold<int>(0, (x, y) => x + y.value), 10000);
      expect(r.items, const [
        SplitItem('a', 5294),
        SplitItem('s', 2353),
        SplitItem('o', 2353),
      ]);
    });
    test('no items, or more than the total, is not a split', () {
      expect(itemizedSplit(1000, const [], ids), isNull);
      expect(itemizedSplit(1000, const [ReceiptItem(500, [])], ids), isNull);
      expect(
        itemizedSplit(1000, const [
          ReceiptItem(1500, ['a']),
        ], ids),
        isNull,
      );
      expect(
        itemizedSplit(1000, const [
          ReceiptItem(1000, ['o']),
        ], ids)!.items.map((i) => i.value).toList(),
        [0, 0, 1000],
      );
    });
  });

  group('pay with', () {
    test('links open, account details copy, PayPal.me gets the amount', () {
      expect(
        payAction(const PayTo('iban', 'AE070331234567890123456'), 4550, 'AED'),
        const PayCopy('AE070331234567890123456'),
      );
      expect(
        payAction(const PayTo('instapay', 'sara@instapay'), 100, 'EGP'),
        const PayCopy('sara@instapay'),
      );
      expect(
        payAction(
          const PayTo('instapay', 'https://ipn.eg/S/sara/instapay/abc'),
          100,
          'EGP',
        ),
        const PayOpen('https://ipn.eg/S/sara/instapay/abc'),
      );
      expect(
        payAction(const PayTo('paypal', 'https://paypal.me/sara'), 1250, 'USD'),
        const PayOpen('https://paypal.me/sara/12.50USD'),
      );
      expect(
        payAction(
          const PayTo('paypal', 'https://paypal.me/sara/5'),
          1250,
          'USD',
        ),
        const PayOpen('https://paypal.me/sara/5'),
      );
      expect(
        payAction(const PayTo('paypal', 'https://paypal.me/sara'), 1250, 'KWD'),
        const PayOpen('https://paypal.me/sara/1.250KWD'),
      );
      expect(
        payAction(
          const PayTo('wise', 'https://wise.com/pay/me/sara'),
          1,
          'GBP',
        ),
        const PayOpen('https://wise.com/pay/me/sara'),
      );
      expect(
        payAction(const PayTo('stcpay', '+966 50 000 0000'), 1, 'SAR'),
        const PayCopy('+966 50 000 0000'),
      );
    });
  });

  group('spending by category', () {
    test('in the group currency, largest first', () {
      ({ExpenseLike expense, String category}) e(
        int amount,
        String category, [
        String currency = 'AED',
        double rate = 1,
      ]) => (
        expense: ExpenseLike(
          amount: amount,
          currency: currency,
          rate: rate,
          paidBy: 'a',
          items: all3,
        ),
        category: category,
      );
      expect(
        spendingByCategory([
          e(1000, 'food'),
          e(500, 'transport'),
          e(2000, 'food'),
          e(1000, 'stay', 'USD', 3.6725),
        ], 'AED'),
        [
          (category: 'stay', amount: 3673),
          (category: 'food', amount: 3000),
          (category: 'transport', amount: 500),
        ],
      );
    });
  });

  group('reading a receipt', () {
    test('items with prices, quantities, tax and the total; Arabic digits', () {
      final text = [
        'SHAWARMA HOUSE',
        'Tel 04 123 4567',
        '2 x Chicken shawarma   24.00',
        'Fries 8.50',
        'Fresh juice x2 ..... 18',
        'Subtotal 50.50',
        'VAT 5% 2.53',
        'Service 5.00',
        'TOTAL AED 58.03',
        'Cash 60.00',
        'Change 1.97',
        'شاي كرك ٣٫٥٠',
      ].join('\n');
      final r = parseReceipt(text, 'AED');
      expect(r.items, [
        (name: 'Chicken shawarma', price: 2400),
        (name: 'Fries', price: 850),
        (name: 'Fresh juice', price: 1800),
        (name: 'شاي كرك', price: 350),
      ]);
      expect(r.total, 5803);
      final k = parseReceipt('Machboos 4.250\nالإجمالي 4.250', 'KWD');
      expect(k.items, [(name: 'Machboos', price: 4250)]);
      expect(k.total, 4250);
      final none = parseReceipt('nothing to see here', 'AED');
      expect(none.items.isEmpty, isTrue);
      expect(none.total, isNull);
    });
  });
}
