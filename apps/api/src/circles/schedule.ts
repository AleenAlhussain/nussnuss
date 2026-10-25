/** Calendar maths for money circles and recurring bills. Dates are plain YYYY-MM-DD strings in UTC. */

export type Every = 'week' | 'month';

const pad = (n: number) => String(n).padStart(2, '0');
export const isoDay = (d: Date) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;

function daysInMonth(y: number, m0: number) {
  return new Date(Date.UTC(y, m0 + 1, 0)).getUTCDate();
}

/** `n` weeks or months after `from`. Monthly dates keep `anchorDay` when the month is long enough (31 Jan, 28 Feb, 31 Mar). */
export function addPeriods(from: Date, every: Every, n: number, anchorDay = from.getUTCDate()): Date {
  if (every === 'week') return new Date(from.getTime() + n * 7 * 864e5);
  const y = from.getUTCFullYear();
  const m0 = from.getUTCMonth() + n;
  const ty = y + Math.floor(m0 / 12);
  const tm = ((m0 % 12) + 12) % 12;
  const day = Math.min(anchorDay, daysInMonth(ty, tm));
  return new Date(Date.UTC(ty, tm, day, from.getUTCHours(), from.getUTCMinutes(), from.getUTCSeconds()));
}

export interface CircleRow {
  id: string;
  name: string;
  amountMinor: number;
  every: string;
  startOn: string;
  turns: string[];
}

export interface CircleRound {
  round: number;
  receiver: string;
  dueOn: string;
  /** Members (other than the receiver) who have paid into this round. */
  paid: string[];
  /** Members who still owe this round after its date has passed. */
  late: string[];
}

export interface CircleView {
  id: string;
  name: string;
  amount: number;
  every: Every;
  startOn: string;
  turns: string[];
  pot: number;
  status: 'upcoming' | 'running' | 'done';
  /** Index of the first round not fully paid; null once the circle is done. */
  current: number | null;
  rounds: CircleRound[];
}

export function circleView(c: CircleRow, paidRows: { round: number; memberId: string }[], today: Date = new Date()): CircleView {
  const start = new Date(`${c.startOn}T00:00:00Z`);
  const every = c.every as Every;
  const todayIso = isoDay(today);
  const rounds: CircleRound[] = c.turns.map((receiver, round) => {
    const dueOn = isoDay(addPeriods(start, every, round));
    const paid = c.turns.filter((m) => m !== receiver && paidRows.some((p) => p.round === round && p.memberId === m));
    const late = dueOn < todayIso ? c.turns.filter((m) => m !== receiver && !paid.includes(m)) : [];
    return { round, receiver, dueOn, paid, late };
  });
  const firstOpen = rounds.findIndex((r) => r.paid.length < c.turns.length - 1);
  const status = todayIso < c.startOn ? 'upcoming' : firstOpen === -1 ? 'done' : 'running';
  return {
    id: c.id,
    name: c.name,
    amount: c.amountMinor,
    every,
    startOn: c.startOn,
    turns: c.turns,
    pot: c.amountMinor * c.turns.length,
    status,
    current: firstOpen === -1 ? null : firstOpen,
    rounds,
  };
}
