import { minorToInput, normalizeDigits, parseAmount } from './money.js';
import { allocate, expenseInGroupCurrency } from './split.js';
import type { ExpenseLike, SplitItem } from './types.js';

/** One line of a receipt: its price (minor units of the expense currency) and who had it. */
export interface ReceiptItem {
  price: number;
  members: string[];
}

/**
 * Splits a receipt by item. Each item is shared equally by the people who had it; whatever the items
 * do not cover (tax, service, rounding) is shared in proportion to what each person had.
 * Returns exact split items that add up to `total`, or null when the items are empty or come to more
 * than the total. Items with no price or nobody on them are ignored.
 */
export function itemizedSplit(total: number, items: ReceiptItem[], memberIds: string[]): { items: SplitItem[]; rest: number } | null {
  const sub = Object.fromEntries(memberIds.map((id) => [id, 0])) as Record<string, number>;
  let sum = 0;
  for (const it of items) {
    const who = memberIds.filter((id) => it.members.includes(id));
    if (it.price <= 0 || !who.length) continue;
    sum += it.price;
    allocate(it.price, who.map(() => 1)).forEach((v, i) => (sub[who[i]] += v));
  }
  if (sum <= 0 || sum > total) return null;
  const rest = total - sum;
  const extra = allocate(rest, memberIds.map((id) => sub[id]));
  return { items: memberIds.map((id, i) => ({ memberId: id, value: sub[id] + extra[i] })), rest };
}

export type PayToKind = 'iban' | 'instapay' | 'stcpay' | 'phone' | 'paypal' | 'wise' | 'link';
export const PAY_TO_KINDS: readonly PayToKind[] = ['iban', 'instapay', 'stcpay', 'phone', 'paypal', 'wise', 'link'] as const;

/** A way someone gets paid, as saved on their account. */
export interface PayTo {
  kind: PayToKind;
  value: string;
  label?: string;
}

/** What "Pay with" does: open a link (with the amount where the service supports it) or copy a detail. */
export type PayAction = { open: string } | { copy: string };

export function payAction(p: PayTo, amount: number, code: string): PayAction {
  const v = p.value.trim();
  switch (p.kind) {
    case 'iban':
    case 'stcpay':
    case 'phone':
      return { copy: v };
    case 'instapay':
      return /^https:\/\//i.test(v) ? { open: v } : { copy: v };
    case 'paypal': {
      // paypal.me/name takes the amount and currency as the next path part: paypal.me/name/12.50USD
      const m = /^https:\/\/(www\.)?paypal\.me\/([^/?#]+)\/?$/i.exec(v);
      return m && amount > 0 ? { open: `https://paypal.me/${m[2]}/${minorToInput(amount, code)}${code}` } : { open: v };
    }
    default:
      return { open: v };
  }
}

/** Spending per category in the group currency, largest first. Categories with nothing spent are left out. */
export function spendingByCategory(expenses: (ExpenseLike & { category: string })[], groupCurrency: string): { category: string; amount: number }[] {
  const by = new Map<string, number>();
  for (const e of expenses) by.set(e.category, (by.get(e.category) ?? 0) + expenseInGroupCurrency(e, groupCurrency));
  return [...by.entries()]
    .filter(([, a]) => a > 0)
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount || a.category.localeCompare(b.category));
}

const RECEIPT_SKIP = /\b(sub\s*-?total|total|vat|tax|service|svc|tip|gratuity|change|cash|card|visa|master|balance|amount due|paid|discount|round(ing)?|qty|invoice|receipt|tel|phone|date|time|table|order|bill no|trn)\b|المجموع|الإجمالي|الاجمالي|ضريبة|خدمة|نقد|الباقي|المدفوع|خصم|فاتورة|هاتف|تاريخ|طاولة/i;
const RECEIPT_TOTAL = /\b(grand\s*total|total(\s*due)?|amount\s*due|net\s*total)\b|الإجمالي|الاجمالي|المجموع\s*الكلي|المبلغ\s*المستحق/i;
const PRICE_AT_END = /^(.*?)[\s:.\-–]*(\d{1,3}(?:,\d{3})+(?:\.\d{1,3})?|\d+(?:[.,]\d{1,3})?)\s*([A-Za-z]{2,3}|د\.إ|ر\.س|ر\.ع|د\.ك|د\.ب|ر\.ق|ج\.م)?\s*$/;

/**
 * Reads the text of a photographed receipt (from on-device text recognition) into items and the total.
 * Each line that ends in a price becomes an item ("2 x Burger 30.00" → Burger, 30.00); tax, service,
 * payment and header lines are skipped; a "Total" line gives the total. Arabic digits are fine.
 */
export function parseReceipt(text: string, code: string): { items: { name: string; price: number }[]; total: number | null } {
  const items: { name: string; price: number }[] = [];
  let total: number | null = null;
  for (const raw of normalizeDigits(text).split(/\r?\n/)) {
    const line = raw.replace(/\s+/g, ' ').trim();
    if (!line) continue;
    const m = PRICE_AT_END.exec(line);
    if (!m) continue;
    const price = parseAmount(m[2], code);
    if (!price) continue;
    const name = m[1]
      .replace(/^\d+\s*[x×*]\s*/i, '')
      .replace(/\s*[x×*]\s*\d+$/i, '')
      .replace(/[\s:.\-–]+$/, '')
      .trim();
    if (RECEIPT_TOTAL.test(line) && !/sub\s*-?total/i.test(line)) {
      total = Math.max(total ?? 0, price);
      continue;
    }
    if (!name || !/\p{L}/u.test(name) || RECEIPT_SKIP.test(name)) continue;
    items.push({ name: name.slice(0, 60), price });
  }
  return { items, total };
}
