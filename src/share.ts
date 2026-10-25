import LZString from 'lz-string';
import { computeBalances, simplifyDebts, groupTotal } from './split';
import { formatMoney } from './money';
import type { CategoryId, Expense, Group, Lang, Payment, SplitMode } from './types';

/** Where share links point. The web build of this app is hosted there (see replica/deploy.md). */
export const SHARE_BASE_URL = 'https://nussnuss.app/app/';

/** Links longer than this are unreliable in some chat apps; we fall back to text only. */
export const MAX_LINK_LENGTH = 8000;

const MODES: SplitMode[] = ['equal', 'exact', 'percent', 'shares'];
const CATS: CategoryId[] = ['food', 'groceries', 'transport', 'stay', 'fun', 'bills', 'shopping', 'other'];

type Packed = {
  v: 1;
  i: string;
  n: string;
  e: string;
  c: string;
  t: string;
  m: [string, string][];
  x: [string, string, number, string, number, string, number, [string, number][], number, string][];
  p: [string, string, string, number, string][];
};

export function encodeGroup(g: Group): string {
  const packed: Packed = {
    v: 1,
    i: g.id,
    n: g.name,
    e: g.emoji,
    c: g.currency,
    t: g.updatedAt,
    m: g.members.map((m) => [m.id, m.name]),
    x: g.expenses.map((e) => [
      e.id,
      e.title,
      e.amount,
      e.currency,
      e.rate,
      e.paidBy,
      MODES.indexOf(e.mode),
      e.items.map((i) => [i.memberId, i.value] as [string, number]),
      CATS.indexOf(e.category),
      e.date,
    ]),
    p: g.payments.map((p) => [p.id, p.from, p.to, p.amount, p.date]),
  };
  return LZString.compressToEncodedURIComponent(JSON.stringify(packed));
}

const isStr = (v: unknown, max = 200): v is string => typeof v === 'string' && v.length <= max;
const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isSafeInteger(v);

/** Decode and validate a shared group. Returns null for anything malformed. */
export function decodeGroup(payload: string): Group | null {
  try {
    const json = LZString.decompressFromEncodedURIComponent(payload);
    if (!json || json.length > 2_000_000) return null;
    const p = JSON.parse(json) as Packed;
    if (p?.v !== 1 || !isStr(p.i) || !isStr(p.n, 60) || !isStr(p.e, 16) || !isStr(p.c, 3)) return null;
    if (!Array.isArray(p.m) || !Array.isArray(p.x) || !Array.isArray(p.p)) return null;
    if (p.m.length > 100 || p.x.length > 5000 || p.p.length > 5000) return null;
    const members = p.m.map(([id, name]) => {
      if (!isStr(id) || !isStr(name, 40)) throw new Error('member');
      return { id, name };
    });
    const ids = new Set(members.map((m) => m.id));
    const expenses: Expense[] = p.x.map(([id, title, amount, cur, rate, paidBy, mode, items, cat, date]) => {
      if (!isStr(id) || !isStr(title, 80) || !isInt(amount) || amount <= 0 || !isStr(cur, 3)) throw new Error('x');
      if (typeof rate !== 'number' || !(rate > 0) || !ids.has(paidBy) || !MODES[mode]) throw new Error('x');
      if (!Array.isArray(items) || !isStr(date, 40)) throw new Error('x');
      return {
        id,
        title,
        amount,
        currency: cur,
        rate,
        paidBy,
        mode: MODES[mode],
        items: items.map(([memberId, value]) => {
          if (!ids.has(memberId) || !isInt(value) || value < 0) throw new Error('item');
          return { memberId, value };
        }),
        category: CATS[cat] ?? 'other',
        date,
        createdAt: date,
      };
    });
    const payments: Payment[] = p.p.map(([id, from, to, amount, date]) => {
      if (!isStr(id) || !ids.has(from) || !ids.has(to) || !isInt(amount) || amount <= 0 || !isStr(date, 40)) {
        throw new Error('p');
      }
      return { id, from, to, amount, date };
    });
    return {
      id: p.i,
      name: p.n,
      emoji: p.e,
      currency: p.c,
      members,
      expenses,
      payments,
      createdAt: p.t,
      updatedAt: p.t,
    };
  } catch {
    return null;
  }
}

export function shareLink(g: Group, base: string = SHARE_BASE_URL): string {
  return `${base}#g=${encodeGroup(g)}`;
}

/** Pull the payload out of any link form: ...#g=XXX, ...?g=XXX, nussnuss://g?d=XXX */
export function payloadFromUrl(url: string | null | undefined): string | null {
  if (!url) return null;
  const m = url.match(/[#?&](?:g|d)=([A-Za-z0-9+\-_$]+)/);
  return m ? m[1] : null;
}

const L = {
  en: { total: 'Total', pays: 'Who pays whom', settled: 'All settled ✅', open: 'Full breakdown:', made: 'Split with NussNuss' },
  ar: { total: 'المجموع', pays: 'مين يدفع لمين', settled: 'كل الحسابات مسوّاة ✅', open: 'التفاصيل كاملة:', made: 'مقسومة بتطبيق نص نص' },
};

/** The WhatsApp-ready summary. */
export function summaryText(g: Group, lang: Lang, link?: string): string {
  const s = L[lang];
  const name = (id: string) => g.members.find((m) => m.id === id)?.name ?? '?';
  const transfers = simplifyDebts(computeBalances(g), g.members.map((m) => m.id));
  const arrow = lang === 'ar' ? '←' : '→';
  const lines = [
    `${g.emoji} ${g.name}`,
    `${s.total}: ${formatMoney(groupTotal(g), g.currency, lang)}`,
    '',
    transfers.length ? `${s.pays}:` : s.settled,
    ...transfers.map((t) => `• ${name(t.from)} ${arrow} ${name(t.to)}: ${formatMoney(t.amount, g.currency, lang)}`),
  ];
  if (link) lines.push('', s.open, link);
  lines.push('', `— ${s.made}`);
  return lines.join('\n');
}

export function toCSV(g: Group, lang: Lang): string {
  const name = (id: string) => g.members.find((m) => m.id === id)?.name ?? '';
  const esc = (v: string) => (/[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
  const head = lang === 'ar'
    ? ['التاريخ', 'الوصف', 'المبلغ', 'العملة', 'دفع', 'الطريقة']
    : ['Date', 'Description', 'Amount', 'Currency', 'Paid by', 'Split'];
  const rows = g.expenses.map((e) => [
    e.date.slice(0, 10),
    e.title,
    formatMoney(e.amount, e.currency, 'en').split(' ')[1],
    e.currency,
    name(e.paidBy),
    e.mode,
  ]);
  return [head, ...rows].map((r) => r.map(esc).join(',')).join('\n');
}
