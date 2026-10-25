import { convertMinor } from './money';
import type { Expense, Group, SplitItem, SplitMode, Transfer } from './types';

/**
 * Split `total` into integer parts proportional to `weights` (largest remainder method).
 * Parts always add up to exactly `total`. Ties go to the earlier index, so results are stable.
 */
export function allocate(total: number, weights: number[]): number[] {
  const sum = weights.reduce((a, b) => a + Math.max(0, b), 0);
  if (sum <= 0 || total === 0) return weights.map(() => 0);
  const sign = total < 0 ? -1 : 1;
  const t = Math.abs(total);
  const raw = weights.map((w) => (Math.max(0, w) * t) / sum);
  const base = raw.map(Math.floor);
  let left = t - base.reduce((a, b) => a + b, 0);
  const order = raw
    .map((r, i) => ({ i, frac: r - Math.floor(r), w: weights[i] }))
    .filter((x) => x.w > 0)
    .sort((a, b) => b.frac - a.frac || a.i - b.i);
  for (let k = 0; left > 0 && order.length; k = (k + 1) % order.length, left--) {
    base[order[k].i] += 1;
  }
  return base.map((b) => b * sign);
}

export type SplitError =
  | 'noAmount'
  | 'noPeople'
  | 'exactMismatch'
  | 'percentMismatch'
  | 'noShares'
  | 'payerMissing';

/** Check an expense's split. Returns null when it is valid. */
export function validateSplit(
  amount: number,
  mode: SplitMode,
  items: SplitItem[],
  paidBy: string,
  memberIds: string[],
): SplitError | null {
  if (!(amount > 0)) return 'noAmount';
  if (!memberIds.includes(paidBy)) return 'payerMissing';
  const active = items.filter((i) => memberIds.includes(i.memberId) && i.value > 0);
  if (!active.length) return mode === 'shares' ? 'noShares' : 'noPeople';
  const sum = active.reduce((a, b) => a + b.value, 0);
  if (mode === 'exact' && sum !== amount) return 'exactMismatch';
  if (mode === 'percent' && sum !== 10000) return 'percentMismatch';
  return null;
}

/** What each member owes for one expense, in the expense's own currency (minor units). */
export function owedInExpenseCurrency(e: Pick<Expense, 'amount' | 'mode' | 'items'>): Record<string, number> {
  const items = e.items.filter((i) => i.value > 0);
  const out: Record<string, number> = {};
  if (e.mode === 'exact') {
    for (const i of items) out[i.memberId] = (out[i.memberId] ?? 0) + i.value;
    return out;
  }
  const weights = items.map((i) => (e.mode === 'equal' ? 1 : i.value));
  const parts = allocate(e.amount, weights);
  items.forEach((i, k) => (out[i.memberId] = (out[i.memberId] ?? 0) + parts[k]));
  return out;
}

/** Expense total in the group currency. */
export function expenseInGroupCurrency(e: Expense, groupCurrency: string): number {
  return convertMinor(e.amount, e.currency, groupCurrency, e.rate);
}

/** What each member owes for one expense, in the group currency. Adds up to the converted total. */
export function owedInGroupCurrency(e: Expense, groupCurrency: string): Record<string, number> {
  const own = owedInExpenseCurrency(e);
  if (e.currency === groupCurrency) return own;
  const ids = Object.keys(own);
  const total = expenseInGroupCurrency(e, groupCurrency);
  const parts = allocate(total, ids.map((id) => own[id]));
  return Object.fromEntries(ids.map((id, k) => [id, parts[k]]));
}

/**
 * Net balance per member in the group currency.
 * Positive = the group owes them. Negative = they owe the group. Always sums to 0.
 */
export function computeBalances(g: Group): Record<string, number> {
  const bal: Record<string, number> = Object.fromEntries(g.members.map((m) => [m.id, 0]));
  for (const e of g.expenses) {
    const total = expenseInGroupCurrency(e, g.currency);
    if (bal[e.paidBy] !== undefined) bal[e.paidBy] += total;
    const owed = owedInGroupCurrency(e, g.currency);
    for (const [id, v] of Object.entries(owed)) if (bal[id] !== undefined) bal[id] -= v;
  }
  for (const p of g.payments) {
    if (bal[p.from] !== undefined) bal[p.from] += p.amount;
    if (bal[p.to] !== undefined) bal[p.to] -= p.amount;
  }
  return bal;
}

/**
 * Fewest-transfers plan: repeatedly match the biggest debtor with the biggest creditor.
 * At most n-1 transfers. Deterministic for the same input order.
 */
export function simplifyDebts(balances: Record<string, number>, order: string[] = Object.keys(balances)): Transfer[] {
  const idx = (id: string) => order.indexOf(id);
  const cred = order.filter((id) => (balances[id] ?? 0) > 0).map((id) => ({ id, v: balances[id] }));
  const debt = order.filter((id) => (balances[id] ?? 0) < 0).map((id) => ({ id, v: -balances[id] }));
  const out: Transfer[] = [];
  const sortDesc = (a: { id: string; v: number }, b: { id: string; v: number }) => b.v - a.v || idx(a.id) - idx(b.id);
  while (cred.length && debt.length) {
    cred.sort(sortDesc);
    debt.sort(sortDesc);
    const c = cred[0];
    const d = debt[0];
    const amt = Math.min(c.v, d.v);
    if (amt > 0) out.push({ from: d.id, to: c.id, amount: amt });
    c.v -= amt;
    d.v -= amt;
    if (c.v === 0) cred.shift();
    if (d.v === 0) debt.shift();
  }
  return out;
}

export function groupTotal(g: Group): number {
  return g.expenses.reduce((a, e) => a + expenseInGroupCurrency(e, g.currency), 0);
}

/** How much one member has paid out of pocket and their share of all expenses. */
export function memberStats(g: Group, memberId: string): { paid: number; share: number } {
  let paid = 0;
  let share = 0;
  for (const e of g.expenses) {
    if (e.paidBy === memberId) paid += expenseInGroupCurrency(e, g.currency);
    share += owedInGroupCurrency(e, g.currency)[memberId] ?? 0;
  }
  return { paid, share };
}
