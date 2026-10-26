'use client';

import { sendTiming } from './api';

/**
 * Phase 0 of the design plan: how long the five main jobs take, measured on the device and sent
 * without any account or device id (the server only logs them when its operator turns timings on).
 */
export type Job = 'add_expense' | 'uneven_split' | 'settle' | 'invite' | 'find_balance';
const started = new Map<Job, number>();

export function timeStart(job: Job) {
  started.set(job, performance.now());
}

export function timeEnd(job: Job, ok = true) {
  const s = started.get(job);
  if (s == null) return;
  started.delete(job);
  sendTiming(job, performance.now() - s, ok);
}

/** Opening the app to seeing where you stand: from the start of the page load. Once per load. */
let balanceSent = false;
export function balanceShown() {
  if (balanceSent || typeof performance === 'undefined') return;
  balanceSent = true;
  sendTiming('find_balance', performance.now(), true);
}
