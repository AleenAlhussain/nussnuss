/// <reference types="jest" />
import { allocate, computeBalances, simplifyDebts, validateSplit, owedInGroupCurrency, groupTotal } from '../split';
import { formatMoney, parseAmount, convertMinor, normalizeDigits, minorToInput } from '../money';
import { encodeGroup, decodeGroup, payloadFromUrl, shareLink, summaryText, toCSV } from '../share';
import type { Expense, Group } from '../types';

const now = '2026-10-23T10:00:00.000Z';
const mk = (over: Partial<Expense> & Pick<Expense, 'id' | 'amount' | 'paidBy' | 'items'>): Expense => ({
  title: 'x',
  currency: 'AED',
  rate: 1,
  mode: 'equal',
  category: 'food',
  date: now,
  createdAt: now,
  ...over,
});
const group = (expenses: Expense[], payments: Group['payments'] = []): Group => ({
  id: 'g1',
  name: 'Trip',
  emoji: '🏝️',
  currency: 'AED',
  members: [
    { id: 'a', name: 'Ahmed' },
    { id: 's', name: 'Sara' },
    { id: 'o', name: 'Omar' },
  ],
  expenses,
  payments,
  createdAt: now,
  updatedAt: now,
});
const all3 = [
  { memberId: 'a', value: 1 },
  { memberId: 's', value: 1 },
  { memberId: 'o', value: 1 },
];
const sum = (r: Record<string, number>) => Object.values(r).reduce((a, b) => a + b, 0);

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
  test('many random totals always sum exactly', () => {
    for (let t = 1; t < 3000; t += 7) {
      const w = [1, 3, 7, 2, 5];
      expect(allocate(t, w).reduce((a, b) => a + b, 0)).toBe(t);
    }
  });
});

describe('money', () => {
  test('format 2 and 3 decimal currencies', () => {
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
  test('round trip to input', () => {
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
    const g = group([mk({ id: 'e1', amount: 30000, paidBy: 'a', items: all3 })]);
    const b = computeBalances(g);
    expect(b).toEqual({ a: 20000, s: -10000, o: -10000 });
    expect(sum(b)).toBe(0);
    expect(simplifyDebts(b, ['a', 's', 'o'])).toEqual([
      { from: 's', to: 'a', amount: 10000 },
      { from: 'o', to: 'a', amount: 10000 },
    ]);
  });

  test('mixed modes and payments still sum to zero', () => {
    const g = group(
      [
        mk({ id: 'e1', amount: 10000, paidBy: 'a', items: all3 }),
        mk({ id: 'e2', amount: 9000, paidBy: 's', mode: 'exact', items: [{ memberId: 'a', value: 2000 }, { memberId: 's', value: 7000 }] }),
        mk({ id: 'e3', amount: 777, paidBy: 'o', mode: 'percent', items: [{ memberId: 'a', value: 3333 }, { memberId: 's', value: 3333 }, { memberId: 'o', value: 3334 }] }),
        mk({ id: 'e4', amount: 1001, paidBy: 'a', mode: 'shares', items: [{ memberId: 's', value: 2 }, { memberId: 'o', value: 1 }] }),
      ],
      [{ id: 'p1', from: 's', to: 'a', amount: 500, date: now }],
    );
    const b = computeBalances(g);
    expect(sum(b)).toBe(0);
    const t = simplifyDebts(b, ['a', 's', 'o']);
    expect(t.length).toBeLessThanOrEqual(2);
    // applying the transfers settles everyone
    const after = { ...b };
    for (const x of t) {
      after[x.from] += x.amount;
      after[x.to] -= x.amount;
    }
    expect(Object.values(after).every((v) => v === 0)).toBe(true);
  });

  test('foreign currency expense converts and still adds up', () => {
    const e = mk({ id: 'e1', amount: 10001, currency: 'USD', rate: 3.6725, paidBy: 's', items: all3 });
    const owed = owedInGroupCurrency(e, 'AED');
    expect(sum(owed)).toBe(convertMinor(10001, 'USD', 'AED', 3.6725));
    const g = group([e]);
    expect(sum(computeBalances(g))).toBe(0);
    expect(groupTotal(g)).toBe(36729);
  });

  test('a fully settled group needs no transfers', () => {
    const g = group(
      [mk({ id: 'e1', amount: 2000, paidBy: 'a', items: [{ memberId: 'a', value: 1 }, { memberId: 's', value: 1 }] })],
      [{ id: 'p1', from: 's', to: 'a', amount: 1000, date: now }],
    );
    expect(simplifyDebts(computeBalances(g))).toEqual([]);
  });

  test('ten people, random expenses: transfers ≤ n-1 and settle everything', () => {
    const ids = 'abcdefghij'.split('');
    let seed = 7;
    const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    const expenses: Expense[] = Array.from({ length: 60 }, (_, k) =>
      mk({
        id: 'e' + k,
        amount: 1 + Math.floor(rnd() * 50000),
        paidBy: ids[Math.floor(rnd() * 10)],
        items: ids.filter(() => rnd() > 0.3).map((memberId) => ({ memberId, value: 1 })).concat([{ memberId: 'a', value: 1 }]).filter((v, i, arr) => arr.findIndex((x) => x.memberId === v.memberId) === i),
      }),
    );
    const g: Group = { ...group(expenses), members: ids.map((id) => ({ id, name: id })) };
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

describe('share links', () => {
  const g = group(
    [
      mk({ id: 'e1', title: 'عشاء "بحري", ok', amount: 30000, paidBy: 'a', items: all3 }),
      mk({ id: 'e2', title: 'Taxi', amount: 4500, currency: 'USD', rate: 3.6725, paidBy: 's', mode: 'shares', items: [{ memberId: 'a', value: 2 }, { memberId: 'o', value: 1 }], category: 'transport' }),
    ],
    [{ id: 'p1', from: 'o', to: 'a', amount: 1000, date: now }],
  );

  test('round trip keeps everything that matters', () => {
    const back = decodeGroup(encodeGroup(g))!;
    expect(back).not.toBeNull();
    expect(back.members).toEqual(g.members);
    expect(back.expenses.map((e) => [e.title, e.amount, e.currency, e.rate, e.mode, e.items, e.category])).toEqual(
      g.expenses.map((e) => [e.title, e.amount, e.currency, e.rate, e.mode, e.items, e.category]),
    );
    expect(computeBalances(back)).toEqual(computeBalances(g));
  });

  test('payload is found in every link form', () => {
    const link = shareLink(g, 'https://nussnuss.app/');
    const p = payloadFromUrl(link)!;
    expect(decodeGroup(p)?.name).toBe('Trip');
    expect(payloadFromUrl(`nussnuss://g?d=${p}`)).toBe(p);
    expect(payloadFromUrl('https://nussnuss.app/')).toBeNull();
  });

  test('garbage and tampered links are rejected', () => {
    expect(decodeGroup('not-a-real-payload')).toBeNull();
    expect(decodeGroup('')).toBeNull();
    const LZ = require('lz-string');
    const bad = LZ.compressToEncodedURIComponent(JSON.stringify({ v: 1, i: 'x', n: 'n', e: 'e', c: 'AED', t: now, m: [['a', 'A']], x: [['e', 't', -5, 'AED', 1, 'a', 0, [], 0, now]], p: [] }));
    expect(decodeGroup(bad)).toBeNull();
    const ghost = LZ.compressToEncodedURIComponent(JSON.stringify({ v: 1, i: 'x', n: 'n', e: 'e', c: 'AED', t: now, m: [['a', 'A']], x: [['e', 't', 5, 'AED', 1, 'zz', 0, [], 0, now]], p: [] }));
    expect(decodeGroup(ghost)).toBeNull();
  });

  test('summary text in both languages', () => {
    const en = summaryText(g, 'en', 'https://x');
    expect(en).toContain('Who pays whom');
    expect(en).toContain('https://x');
    const ar = summaryText(g, 'ar');
    expect(ar).toContain('مين يدفع لمين');
    expect(ar).toContain('د.إ');
  });

  test('csv escapes quotes and commas', () => {
    const csv = toCSV(g, 'en');
    expect(csv.split('\n')[1]).toContain('"عشاء ""بحري"", ok"');
    expect(csv.split('\n')[2]).toContain('45.00,USD,Sara,shares');
  });
});
