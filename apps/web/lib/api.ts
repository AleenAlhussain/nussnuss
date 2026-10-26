import type { Avatar, CoverTone, PayTo, SplitMode, Transfer } from '@nussnuss/core';

export const API_URL = (process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000').replace(/\/$/, '');
const TOKEN_KEY = 'nn:token';

export type { Avatar };
export interface Me {
  id: string;
  name: string;
  locale: 'en' | 'ar';
  payTo: PayTo[];
  avatar?: Avatar;
}
/** Someone shown with their look: a name, and their avatar when the server sent one. */
export interface Who {
  name: string;
  me?: boolean;
  avatar?: Avatar;
}
export type LastActivity =
  | { kind: 'expense'; who: Who | null; title: string; at: string }
  | { kind: 'payment'; from: Who | null; to: Who | null; at: string };
export interface GroupSummary {
  id: string;
  name: string;
  emoji: string;
  /** "icon:tone"; older servers leave it out. */
  cover?: string;
  currency: string;
  version: number;
  updatedAt: string;
  memberCount: number;
  memberNames: string[];
  members?: Who[];
  expenseCount?: number;
  total: number;
  myBalance: number;
  settled?: boolean;
  lastActivity?: LastActivity | null;
}
export interface Member {
  id: string;
  name: string;
  claimed: boolean;
  isMe: boolean;
  payTo?: PayTo[];
  avatar?: Avatar;
}
export interface Money {
  currency: string;
  amount: number;
}
export interface GroupBrief {
  id: string;
  name: string;
  emoji: string;
  cover: string;
  currency: string;
}
export interface PersonSummary {
  key: string;
  name: string;
  avatar: Avatar;
  /** + they owe you, − you owe them; biggest first. */
  balances: Money[];
  groups: number;
}
export type NextStep =
  | { kind: 'pay' | 'collect'; person: { key: string; name: string; avatar: Avatar }; amount: number; currency: string; group: GroupBrief; memberId: string; payTo: PayTo[] }
  | { kind: 'first' | 'invite'; group: GroupBrief };
export interface Overview {
  totals: Money[];
  groups: number;
  next: NextStep | null;
  people: PersonSummary[];
  unread: number;
}
export interface PersonDetail {
  key: string;
  name: string;
  avatar: Avatar;
  claimed: boolean;
  balances: Money[];
  groups: (GroupBrief & { amount: number; memberId: string; me: string; payTo: PayTo[] })[];
  shared: { id: string; group: GroupBrief; title: string; category: string; currency: string; amount: number; paidByMe: boolean; at: string }[];
}
interface ActivityBase {
  id: string;
  op: 'create' | 'update';
  at: string;
  group: GroupBrief;
  unread: boolean;
  actor: Who | null;
}
export type ActivityItem =
  | (ActivityBase & { kind: 'expense'; expense: { id: string; title: string; amount: number; category: string; paidBy: Who | null; impact: number } })
  | (ActivityBase & { kind: 'payment'; payment: { id: string; amount: number; from: Who | null; to: Who | null } });
export interface ActivityPage {
  items: ActivityItem[];
  next: string | null;
  unread: number;
}
export type AvatarInput = { kind: 'initial'; tone: CoverTone } | { kind: 'emoji'; value: string; tone: CoverTone };
export interface Expense {
  id: string;
  title: string;
  amount: number;
  currency: string;
  rate: number;
  paidBy: string;
  mode: SplitMode;
  items: { memberId: string; value: number }[];
  category: string;
  spentAt: string;
  createdAt: string;
  updatedAt: string;
}
export interface Payment {
  id: string;
  from: string;
  to: string;
  amount: number;
  paidAt: string;
}
export interface GroupDetail {
  id: string;
  name: string;
  emoji: string;
  cover?: string;
  currency: string;
  version: number;
  createdBy: string | null;
  updatedAt: string;
  me: string;
  members: Member[];
  expenses: Expense[];
  payments: Payment[];
  total: number;
  balances: Record<string, number>;
  transfers: Transfer[];
  remindEvery?: 'off' | 'week';
  tripPassUntil?: string | null;
  circles?: Circle[];
  recurring?: Recurring[];
}
export interface CircleRound {
  round: number;
  receiver: string;
  dueOn: string;
  paid: string[];
  late: string[];
}
export interface Circle {
  id: string;
  name: string;
  amount: number;
  every: 'week' | 'month';
  startOn: string;
  turns: string[];
  pot: number;
  status: 'upcoming' | 'running' | 'done';
  current: number | null;
  rounds: CircleRound[];
}
export interface Recurring {
  id: string;
  title: string;
  amount: number;
  paidBy: string;
  mode: SplitMode;
  items: { memberId: string; value: number }[];
  category: string;
  every: 'week' | 'month';
  nextAt: string;
}
export interface Plan {
  plus: boolean;
  plusUntil: string | null;
  tripPasses: { groupId: string; until: string }[];
  looks: string[];
}
export interface Security {
  recoveryCode: boolean;
  recoveryCreatedAt: string | null;
  identities: { provider: 'apple' | 'google'; email: string | null }[];
  passkeys: { id: string; createdAt: string }[];
  sessions: { id: string; device: string | null; lastSeenAt: string; current: boolean }[];
  providers: { apple: boolean; google: boolean; passkeys: boolean };
}
export interface Notice {
  id: string;
  kind: string;
  groupId: string | null;
  data: { to?: string; amount?: number; currency?: string; group?: string; emoji?: string };
  createdAt: string;
  read: boolean;
}
export type Session = { token: string; user: Me };
export interface InvitePreview {
  group: { id: string; name: string; emoji: string; cover?: string; currency: string };
  members: { id: string; name: string; claimed: boolean; avatar?: Avatar }[];
  invitedBy?: Who | null;
}
export interface ExpenseInput {
  id?: string;
  title: string;
  amount: number;
  currency?: string;
  rate?: number;
  paidBy: string;
  mode: SplitMode;
  items: { memberId: string; value: number }[];
  category: string;
  spentAt?: string;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    /** The server says this needs Plus (403 with `plus: true`): show the paywall. */
    public plus = false,
  ) {
    super(message);
  }
}

/** A short device name for the signed-in devices list. */
export function deviceName(): string {
  if (typeof navigator === 'undefined') return 'Web';
  const ua = navigator.userAgent;
  const os = /iPhone|iPad/.test(ua) ? 'iPhone' : /Android/.test(ua) ? 'Android' : /Mac/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : 'Web';
  const browser = /Edg\//.test(ua) ? 'Edge' : /Chrome\//.test(ua) ? 'Chrome' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) ? 'Safari' : 'Browser';
  return `${browser} on ${os}`;
}

export function getToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}
export function setToken(token: string | null) {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* private mode: the session lasts for this tab only */
  }
}

async function call<T>(method: string, path: string, body?: unknown, auth = true): Promise<T> {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const token = auth ? getToken() : null;
  if (token) headers.Authorization = `Bearer ${token}`;
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError(0, 'offline');
  }
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = Array.isArray(data?.message) ? data.message[0] : data?.message;
    throw new ApiError(res.status, typeof msg === 'string' ? msg : 'Something went wrong.', data?.plus === true);
  }
  return data as T;
}

/** Authorised GET of a file (CSV, JSON export) as a Blob. */
async function download(path: string): Promise<Blob> {
  const token = getToken();
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  } catch {
    throw new ApiError(0, 'offline');
  }
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new ApiError(res.status, typeof data?.message === 'string' ? data.message : 'Something went wrong.', data?.plus === true);
  }
  return res.blob();
}

/** Hands a Blob to the person as a file. */
export function saveBlob(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

export const api = {
  anonymous: (name: string, locale: string) => call<Session>('POST', '/auth/anonymous', { name, locale, device: deviceName() }, false),
  me: () => call<Me>('GET', '/me'),
  patchMe: (b: Partial<{ name: string; locale: string; payTo: PayTo[]; avatar: AvatarInput }>) => call<Me>('PATCH', '/me', b),
  setPhoto: (data: string) => call<Me>('POST', '/me/photo', { data }),
  removePhoto: () => call<Me>('DELETE', '/me/photo'),
  deleteMe: () => call<void>('DELETE', '/me'),
  groups: () => call<GroupSummary[]>('GET', '/groups'),
  createGroup: (b: { name: string; emoji: string; cover?: string; currency: string; members: string[] }) => call<GroupDetail>('POST', '/groups', b),
  patchGroup: (id: string, b: Partial<{ name: string; cover: string; currency: string }>) => call<GroupDetail>('PATCH', `/groups/${id}`, b),
  overview: () => call<Overview>('GET', '/overview'),
  person: (key: string) => call<PersonDetail>('GET', `/people/${key}`),
  settleAll: (key: string, groups?: string[]) => call<{ payments: { id: string; groupId: string }[]; person: PersonDetail }>('POST', `/people/${key}/settle`, groups ? { groups } : {}),
  undoPayments: (ids: string[]) => call<{ undone: number }>('POST', '/payments/undo', { ids }),
  activity: (opts: { before?: string; group?: string } = {}) =>
    call<ActivityPage>('GET', `/activity${opts.before || opts.group ? '?' : ''}${new URLSearchParams(Object.entries(opts).filter(([, v]) => v) as [string, string][]).toString()}`),
  activitySeen: () => call<void>('POST', '/activity/seen'),
  activityUnread: () => call<{ unread: number }>('GET', '/activity/unread'),
  group: (id: string) => call<GroupDetail>('GET', `/groups/${id}`),
  changes: (id: string, since: number) => call<{ version: number; changes: unknown[] }>('GET', `/groups/${id}/changes?since=${since}`),
  addMember: (id: string, name: string) => call<GroupDetail>('POST', `/groups/${id}/members`, { name }),
  addExpense: (groupId: string, b: ExpenseInput) => call<{ id: string; detail: GroupDetail }>('POST', `/groups/${groupId}/expenses`, b),
  updateExpense: (id: string, b: ExpenseInput) => call<GroupDetail>('PATCH', `/expenses/${id}`, b),
  deleteExpense: (id: string) => call<GroupDetail>('DELETE', `/expenses/${id}`),
  restoreExpense: (id: string) => call<GroupDetail>('POST', `/expenses/${id}/restore`),
  pay: (groupId: string, t: Transfer & { id?: string }) => call<{ id: string; detail: GroupDetail }>('POST', `/groups/${groupId}/payments`, t),
  unpay: (id: string) => call<GroupDetail>('DELETE', `/payments/${id}`),
  invite: (groupId: string) => call<{ token: string; path?: string; expiresAt: string }>('POST', `/groups/${groupId}/invites`),
  preview: (token: string) => call<InvitePreview>('GET', `/invites/${token}`, undefined, false),
  join: (token: string, b: { memberId: string } | { name: string }) => call<GroupDetail>('POST', `/invites/${token}/join`, b),

  // Accounts
  security: () => call<Security>('GET', '/me/security'),
  makeRecovery: () => call<{ code: string }>('POST', '/me/recovery'),
  /** 8-character codes come from another device; longer ones are recovery codes. */
  signInWithCode: (code: string) => {
    const plain = code.replace(/[\s-]/g, '');
    return call<Session>('POST', plain.length <= 8 ? '/auth/link' : '/auth/recover', { code, device: deviceName() }, false);
  },
  makeLink: () => call<{ code: string; expiresAt: string }>('POST', '/me/link'),
  identity: (provider: 'apple' | 'google', token: string, name?: string) =>
    call<Session | { linked: true; user: Me }>('POST', `/auth/${provider}`, { token, name, device: deviceName() }),
  passkeyRegisterOptions: () => call<{ challengeId: string; options: Record<string, unknown> }>('POST', '/me/passkeys/options'),
  passkeyRegister: (challengeId: string, response: unknown) => call<{ id: string }>('POST', '/me/passkeys', { challengeId, response }),
  passkeyRemove: (id: string) => call<void>('DELETE', `/me/passkeys/${id}`),
  passkeyLoginOptions: () => call<{ challengeId: string; options: Record<string, unknown> }>('POST', '/auth/passkey/options', undefined, false),
  passkeyLogin: (challengeId: string, response: unknown) => call<Session>('POST', '/auth/passkey', { challengeId, response, device: deviceName() }, false),
  endSession: (id: string) => call<void>('DELETE', `/me/sessions/${id}`),
  exportMine: () => download('/me/export'),

  // Plus
  plan: () => call<Plan>('GET', '/me/plan'),
  devPurchase: (productId: string, groupId?: string) => call<Plan>('POST', '/purchases/dev', { productId, groupId }),
  addRecurring: (groupId: string, b: Omit<ExpenseInput, 'id' | 'currency' | 'rate'> & { every: 'week' | 'month'; startAt?: string }) =>
    call<GroupDetail>('POST', `/groups/${groupId}/recurring`, b),
  stopRecurring: (id: string) => call<GroupDetail>('DELETE', `/recurring/${id}`),
  rate: (from: string, to: string, groupId: string) => call<{ rate: number; at: string }>('GET', `/rates?from=${from}&to=${to}&groupId=${groupId}`),
  exportCsv: (groupId: string) => download(`/groups/${groupId}/export.csv`),
  reminders: (groupId: string, every: 'off' | 'week') => call<GroupDetail>('PATCH', `/groups/${groupId}/reminders`, { every }),
  notifications: () => call<Notice[]>('GET', '/me/notifications'),
  markRead: (ids?: string[]) => call<void>('POST', '/me/notifications/read', ids ? { ids } : {}),

  // Money circles
  addCircle: (groupId: string, b: { name: string; amount: number; every: 'week' | 'month'; startOn: string; turns: string[] }) =>
    call<GroupDetail>('POST', `/groups/${groupId}/circles`, b),
  circlePaid: (id: string, round: number, memberId: string, paid: boolean) =>
    call<GroupDetail>('POST', `/circles/${id}/${paid ? 'paid' : 'unpaid'}`, { round, memberId }),
  deleteCircle: (id: string) => call<GroupDetail>('DELETE', `/circles/${id}`),
};

/** Photos are served by the API; avatars carry a path relative to it. */
export const avatarSrc = (url: string) => (/^https?:/.test(url) ? url : `${API_URL}${url}`);

/** Anonymous task timings (phase 0 of the design plan). Never blocks, never throws, sends no token. */
export function sendTiming(job: 'add_expense' | 'uneven_split' | 'settle' | 'invite' | 'find_balance', ms: number, ok = true) {
  try {
    const body = JSON.stringify({ app: 'web', version: '2.0.0', job, ms: Math.max(0, Math.min(600_000, Math.round(ms))), ok });
    fetch(`${API_URL}/telemetry/timing`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, keepalive: true }).catch(() => {});
  } catch {
    /* measuring must never get in the way */
  }
}

export const newId = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0;
        return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
      });
