import type { SplitMode, Transfer } from '@nussnuss/core';

export const API_URL = (process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000').replace(/\/$/, '');
const TOKEN_KEY = 'nn:token';

export interface Me {
  id: string;
  name: string;
  locale: 'en' | 'ar';
}
export interface GroupSummary {
  id: string;
  name: string;
  emoji: string;
  currency: string;
  version: number;
  updatedAt: string;
  memberCount: number;
  memberNames: string[];
  total: number;
  myBalance: number;
}
export interface Member {
  id: string;
  name: string;
  claimed: boolean;
  isMe: boolean;
}
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
}
export interface InvitePreview {
  group: { id: string; name: string; emoji: string; currency: string };
  members: { id: string; name: string; claimed: boolean }[];
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
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
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
  if (!res.ok) throw new ApiError(res.status, typeof data?.message === 'string' ? data.message : 'Something went wrong.');
  return data as T;
}

export const api = {
  anonymous: (name: string, locale: string) => call<{ token: string; user: Me }>('POST', '/auth/anonymous', { name, locale }, false),
  me: () => call<Me>('GET', '/me'),
  patchMe: (b: Partial<{ name: string; locale: string }>) => call<Me>('PATCH', '/me', b),
  deleteMe: () => call<void>('DELETE', '/me'),
  groups: () => call<GroupSummary[]>('GET', '/groups'),
  createGroup: (b: { name: string; emoji: string; currency: string; members: string[] }) => call<GroupDetail>('POST', '/groups', b),
  group: (id: string) => call<GroupDetail>('GET', `/groups/${id}`),
  changes: (id: string, since: number) => call<{ version: number; changes: unknown[] }>('GET', `/groups/${id}/changes?since=${since}`),
  addMember: (id: string, name: string) => call<GroupDetail>('POST', `/groups/${id}/members`, { name }),
  addExpense: (groupId: string, b: ExpenseInput) => call<{ id: string; detail: GroupDetail }>('POST', `/groups/${groupId}/expenses`, b),
  updateExpense: (id: string, b: ExpenseInput) => call<GroupDetail>('PATCH', `/expenses/${id}`, b),
  deleteExpense: (id: string) => call<GroupDetail>('DELETE', `/expenses/${id}`),
  restoreExpense: (id: string) => call<GroupDetail>('POST', `/expenses/${id}/restore`),
  pay: (groupId: string, t: Transfer) => call<{ id: string; detail: GroupDetail }>('POST', `/groups/${groupId}/payments`, t),
  unpay: (id: string) => call<GroupDetail>('DELETE', `/payments/${id}`),
  invite: (groupId: string) => call<{ token: string; expiresAt: string }>('POST', `/groups/${groupId}/invites`),
  preview: (token: string) => call<InvitePreview>('GET', `/invites/${token}`, undefined, false),
  join: (token: string, b: { memberId: string } | { name: string }) => call<GroupDetail>('POST', `/invites/${token}/join`, b),
};

export const newId = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0;
        return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
      });
