import { minorToInput } from './money.js';
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
