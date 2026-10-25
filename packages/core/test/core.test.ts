import { describe, expect, test } from 'vitest';
import {
  allocate,
  computeBalances,
  convertMinor,
  formatMoney,
  groupTotal,
  minorToInput,
  normalizeDigits,
  owedInGroupCurrency,
  parseAmount,
  parseAmountExpression,
  simplifyDebts,
  validateSplit,
  type ExpenseLike,
  type GroupLike,
} from '../src/index.js';

/* These cases are shared with the Flutter port (apps/mobile/test/core_test.dart). Change both together. */

const mk = (over: Partial<ExpenseLike> & Pick<ExpenseLike, 'amount' | 'paidBy' | 'items'>): ExpenseLike => ({
  currency: 'AED',
  rate: 1,
  mode: 'equal',
  ...over,
});
const all3 = [
  { memberId: 'a', value: 1 },
  { memberId: 's', value: 1 },
  { memberId: 'o', value: 1 },
];
const group = (expenses: ExpenseLike[], payments: GroupLike['payments'] = []): GroupLike => ({
  currency: 'AED',
  members: [{ id: 'a' }, { id: 's' }, { id: 'o' }],
  expenses,
  payments,
});
const sum = (r: Record<string, number>) => Object.values(r).reduce((x, y) => x + y, 0);

describe('allocate', () => {
  test('100.00 between 3 adds up exactly, extra cent to the first', () => {
    expect(allocate(10000, [1, 1, 1])).toEqual([3334, 3333, 3333]);
  });
  test('weights and zeros', () => {
    expect(allocate(1000, [2, 0, 1, 1])).toEqual([500, 0, 250, 250]);
    expect(allocate(1, [1, 1, 1])).toEqual([1, 0, 0]);
    expect(allocate(0, [1, 1])).toEqual([0, 0]);
    expect(allocate(500, [0, 0])).toEqual([0, 0]);
  });
  test('many totals always sum exactly', () => {
    for (let t = 1; t < 3000; t += 7) {
      expect(allocate(t, [1, 3, 7, 2, 5]).reduce((a, b) => a + b, 0)).toBe(t);
    }
  });
});

describe('money', () => {
  test('format 0, 2 and 3 decimal currencies in both languages', () => {
    expect(formatMoney(4550, 'AED', 'en')).toBe('AED 45.50');
    expect(formatMoney(4550, 'AED', 'ar')).toBe('45.50 د.إ');
    expect(formatMoney(1250750, 'KWD', 'en')).toBe('KWD 1,250.750');
    expect(formatMoney(5, 'BHD', 'en')).toBe('BHD 0.005');
    expect(formatMoney(1500, 'JPY', 'en')).toBe('JPY 1,500');
    expect(formatMoney(-12345, 'USD', 'en')).toBe('USD -123.45');
  });
  test('parse what people type, including Arabic digits', () => {
    expect(parseAmount('45', 'AED')).toBe(4500);
    expect(parseAmount('45.5', 'AED')).toBe(4550);
    expect(parseAmount('45,50', 'AED')).toBe(4550);
    expect(parseAmount('1,250.75', 'AED')).toBe(125075);
    expect(parseAmount('1,250', 'AED')).toBe(125000);
    expect(parseAmount('٤٥٫٥', 'AED')).toBe(4550);
    expect(parseAmount('۱۲', 'AED')).toBe(1200);
    expect(parseAmount('2.125', 'KWD')).toBe(2125);
    expect(parseAmount('2.125', 'AED')).toBeNull();
    expect(parseAmount('0', 'AED')).toBeNull();
    expect(parseAmount('abc', 'AED')).toBeNull();
    expect(parseAmount('', 'AED')).toBeNull();
    expect(parseAmount('-5', 'AED')).toBeNull();
    expect(parseAmount('.5', 'AED')).toBe(50);
  });
  test('keypad sums', () => {
    expect(parseAmountExpression('12 + 8.5', 'AED')).toBe(2050);
    expect(parseAmountExpression('100-15', 'AED')).toBe(8500);
    expect(parseAmountExpression('٤٥ + ٥', 'AED')).toBe(5000);
    expect(parseAmountExpression('1.250+0.750', 'KWD')).toBe(2000);
    expect(parseAmountExpression('10 - 10', 'AED')).toBeNull();
    expect(parseAmountExpression('5 *2', 'AED')).toBeNull();
    expect(parseAmountExpression('+', 'AED')).toBeNull();
    expect(parseAmountExpression('7', 'AED')).toBe(700);
  });
  test('round trip to input and digit normalising', () => {
    expect(minorToInput(125075, 'AED')).toBe('1250.75');
    expect(normalizeDigits('١٢٣')).toBe('123');
  });
  test('convert between currencies with different decimals', () => {
    expect(convertMinor(10000, 'USD', 'AED', 3.6725)).toBe(36725);
    expect(convertMinor(1000, 'KWD', 'AED', 11.95)).toBe(1195);
    expect(convertMinor(10000, 'AED', 'KWD', 0.0837)).toBe(8370);
  });
});

describe('splits and balances', () => {
  test('validate', () => {
    expect(validateSplit(0, 'equal', all3, 'a', ['a', 's', 'o'])).toBe('noAmount');
    expect(validateSplit(100, 'equal', [], 'a', ['a'])).toBe('noPeople');
    expect(validateSplit(100, 'exact', [{ memberId: 'a', value: 40 }, { memberId: 's', value: 50 }], 'a', ['a', 's'])).toBe('exactMismatch');
    expect(validateSplit(100, 'percent', [{ memberId: 'a', value: 5000 }, { memberId: 's', value: 4000 }], 'a', ['a', 's'])).toBe('percentMismatch');
    expect(validateSplit(100, 'equal', all3, 'zz', ['a', 's', 'o'])).toBe('payerMissing');
    expect(validateSplit(100, 'percent', [{ memberId: 'a', value: 6000 }, { memberId: 's', value: 4000 }], 'a', ['a', 's'])).toBeNull();
  });

  test('equal split, one payer', () => {
    const b = computeBalances(group([mk({ amount: 30000, paidBy: 'a', items: all3 })]));
    expect(b).toEqual({ a: 20000, s: -10000, o: -10000 });
    expect(simplifyDebts(b, ['a', 's', 'o'])).toEqual([
      { from: 's', to: 'a', amount: 10000 },
      { from: 'o', to: 'a', amount: 10000 },
    ]);
  });

  test('mixed modes and payments still sum to zero and settle', () => {
    const g = group(
      [
        mk({ amount: 10000, paidBy: 'a', items: all3 }),
        mk({ amount: 9000, paidBy: 's', mode: 'exact', items: [{ memberId: 'a', value: 2000 }, { memberId: 's', value: 7000 }] }),
        mk({ amount: 777, paidBy: 'o', mode: 'percent', items: [{ memberId: 'a', value: 3333 }, { memberId: 's', value: 3333 }, { memberId: 'o', value: 3334 }] }),
        mk({ amount: 1001, paidBy: 'a', mode: 'shares', items: [{ memberId: 's', value: 2 }, { memberId: 'o', value: 1 }] }),
      ],
      [{ from: 's', to: 'a', amount: 500 }],
    );
    const b = computeBalances(g);
    expect(sum(b)).toBe(0);
    const t = simplifyDebts(b, ['a', 's', 'o']);
    expect(t.length).toBeLessThanOrEqual(2);
    const after = { ...b };
    for (const x of t) {
      after[x.from] += x.amount;
      after[x.to] -= x.amount;
    }
    expect(Object.values(after).every((v) => v === 0)).toBe(true);
  });

  test('foreign currency expense converts and still adds up', () => {
    const e = mk({ amount: 10001, currency: 'USD', rate: 3.6725, paidBy: 's', items: all3 });
    expect(sum(owedInGroupCurrency(e, 'AED'))).toBe(convertMinor(10001, 'USD', 'AED', 3.6725));
    const g = group([e]);
    expect(sum(computeBalances(g))).toBe(0);
    expect(groupTotal(g)).toBe(36729);
  });

  test('ten people, sixty expenses: at most nine transfers and everyone settled', () => {
    const ids = 'abcdefghij'.split('');
    let seed = 7;
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    const expenses: ExpenseLike[] = Array.from({ length: 60 }, () => {
      const picked = new Set(ids.filter(() => rnd() > 0.3));
      picked.add('a');
      return mk({ amount: 1 + Math.floor(rnd() * 50000), paidBy: ids[Math.floor(rnd() * 10)], items: [...picked].map((memberId) => ({ memberId, value: 1 })) });
    });
    const g: GroupLike = { currency: 'AED', members: ids.map((id) => ({ id })), expenses, payments: [] };
    const b = computeBalances(g);
    expect(sum(b)).toBe(0);
    const t = simplifyDebts(b, ids);
    expect(t.length).toBeLessThanOrEqual(9);
    const after = { ...b };
    for (const x of t) {
      after[x.from] += x.amount;
      after[x.to] -= x.amount;
    }
    expect(Object.values(after).every((v) => v === 0)).toBe(true);
  });
});
