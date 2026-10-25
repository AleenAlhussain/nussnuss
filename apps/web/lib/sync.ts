'use client';

import { computeBalances, groupTotal, simplifyDebts } from '@nussnuss/core';
import { useEffect, useState } from 'react';
import { api, ApiError, newId, type Expense, type ExpenseInput, type GroupDetail, type GroupSummary } from './api';
import { kvGet, kvSet } from './kv';

/**
 * Offline first: every group is kept on the device, changes made without a connection wait in a queue
 * and are replayed in order once it is back. Client-made ids make each replay safe to send twice.
 */
export type Op =
  | { opId: string; kind: 'add'; groupId: string; input: ExpenseInput & { id: string }; title: string }
  | { opId: string; kind: 'update'; groupId: string; expenseId: string; input: ExpenseInput; title: string }
  | { opId: string; kind: 'delete'; groupId: string; expenseId: string; title: string }
  | { opId: string; kind: 'pay'; groupId: string; payment: { id: string; from: string; to: string; amount: number }; title: string };
export type NewOp = Op extends infer O ? (O extends Op ? Omit<O, 'opId'> : never) : never;

const QUEUE = 'queue';
let queue: Op[] = [];
let loaded: Promise<void> | null = null;
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((l) => l());

function load() {
  loaded ??= kvGet<Op[]>(QUEUE).then((q) => {
    queue = Array.isArray(q) ? q : [];
    notify();
  });
  return loaded;
}

async function save() {
  await kvSet(QUEUE, queue);
  notify();
}

export const isOffline = (e: unknown) => e instanceof ApiError && e.status === 0;

/** Balances, total and settle-up plan recomputed with the shared rules, as the server would. */
export function recompute(d: GroupDetail): GroupDetail {
  const core = {
    currency: d.currency,
    members: d.members.map((m) => ({ id: m.id })),
    expenses: d.expenses,
    payments: d.payments.map((p) => ({ from: p.from, to: p.to, amount: p.amount })),
  };
  const balances = computeBalances(core);
  return { ...d, balances, total: groupTotal(core), transfers: simplifyDebts(balances, d.members.map((m) => m.id)) };
}

function expenseFrom(input: ExpenseInput, id: string, d: GroupDetail, old?: Expense): Expense {
  const now = new Date().toISOString();
  return {
    id,
    title: input.title,
    amount: input.amount,
    currency: input.currency ?? old?.currency ?? d.currency,
    rate: input.rate ?? old?.rate ?? 1,
    paidBy: input.paidBy,
    mode: input.mode,
    items: input.items,
    category: input.category,
    spentAt: input.spentAt ?? old?.spentAt ?? now,
    createdAt: old?.createdAt ?? now,
    updatedAt: now,
  };
}

/** Lays one waiting change over a group, so what the person did shows before it reaches the server. */
function applyOp(d: GroupDetail, op: Op): GroupDetail {
  if (op.groupId !== d.id) return d;
  switch (op.kind) {
    case 'add':
      if (d.expenses.some((e) => e.id === op.input.id)) return d;
      return { ...d, expenses: [expenseFrom(op.input, op.input.id, d), ...d.expenses].sort((a, b) => b.spentAt.localeCompare(a.spentAt)) };
    case 'update':
      return { ...d, expenses: d.expenses.map((e) => (e.id === op.expenseId ? expenseFrom(op.input, e.id, d, e) : e)) };
    case 'delete':
      return { ...d, expenses: d.expenses.filter((e) => e.id !== op.expenseId) };
    case 'pay':
      if (d.payments.some((p) => p.id === op.payment.id)) return d;
      return { ...d, payments: [{ ...op.payment, paidAt: new Date().toISOString() }, ...d.payments] };
  }
}

export function withPending(d: GroupDetail): GroupDetail {
  const mine = queue.filter((o) => o.groupId === d.id);
  return mine.length ? recompute(mine.reduce(applyOp, d)) : d;
}

export async function cacheGroup(d: GroupDetail) {
  await kvSet(`group:${d.id}`, d);
}
export const cachedGroup = (id: string) => kvGet<GroupDetail>(`group:${id}`);
export const cacheGroups = (g: GroupSummary[]) => kvSet('groups', g);
export const cachedGroups = () => kvGet<GroupSummary[]>('groups');

async function send(op: Op): Promise<GroupDetail> {
  switch (op.kind) {
    case 'add':
      return (await api.addExpense(op.groupId, op.input)).detail;
    case 'update':
      return api.updateExpense(op.expenseId, op.input);
    case 'delete':
      return api.deleteExpense(op.expenseId);
    case 'pay':
      return (await api.pay(op.groupId, op.payment)).detail;
  }
}

/**
 * Sends a change now, or keeps it for later when offline. Returns the group as it should look,
 * and whether the change is waiting.
 */
export async function submit(next: NewOp, current: GroupDetail): Promise<{ detail: GroupDetail; queued: boolean }> {
  await load();
  const op = { ...next, opId: newId() } as Op;
  // Changes wait behind earlier ones for the same group, so the order on the server matches the order here.
  if (!queue.some((o) => o.groupId === op.groupId)) {
    try {
      const detail = await send(op);
      await cacheGroup(detail);
      return { detail: withPending(detail), queued: false };
    } catch (e) {
      if (!isOffline(e)) throw e;
    }
  }
  queue.push(op);
  await save();
  const detail = recompute(applyOp(current, op));
  await cacheGroup(detail);
  return { detail, queued: true };
}

let flushing: Promise<void> | null = null;
let again = false;
const dropped = new Set<(op: Op, message: string) => void>();
const synced = new Set<(d: GroupDetail) => void>();

async function replay() {
  await load();
  while (queue.length) {
    const op = queue[0];
    try {
      const detail = await send(op);
      queue.shift();
      await save();
      await cacheGroup(detail);
      synced.forEach((f) => f(withPending(detail)));
    } catch (e) {
      if (isOffline(e) || (e instanceof ApiError && e.status >= 500)) break;
      queue.shift();
      await save();
      dropped.forEach((f) => f(op, e instanceof Error ? e.message : String(e)));
    }
  }
}

/**
 * Replays waiting changes in order. A change the server refuses is dropped and reported; offline stops
 * the run. A call made while a run is going (say, the connection just came back) makes it go round again.
 */
export function flush(onDropped?: (op: Op, message: string) => void, onSynced?: (d: GroupDetail) => void): Promise<void> {
  if (onDropped) dropped.add(onDropped);
  if (onSynced) synced.add(onSynced);
  if (flushing) {
    again = true;
    return flushing;
  }
  flushing = (async () => {
    do {
      again = false;
      await replay();
    } while (again && queue.length);
  })().finally(() => {
    flushing = null;
    dropped.clear();
    synced.clear();
  });
  return flushing;
}

export function pendingCount(groupId?: string) {
  return queue.filter((o) => !groupId || o.groupId === groupId).length;
}

/** How many changes are waiting (for one group, or all), live. */
export function usePending(groupId?: string): number {
  const [n, setN] = useState(0);
  useEffect(() => {
    const on = () => setN(pendingCount(groupId));
    listeners.add(on);
    load().then(on);
    return () => {
      listeners.delete(on);
    };
  }, [groupId]);
  return n;
}

export async function clearQueue() {
  queue = [];
  await save();
}
