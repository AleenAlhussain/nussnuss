'use client';

import { useEffect, useState } from 'react';
import { api, getToken } from './api';

/** How many Activity items are new, shared by the pages that learn it and the tab bar that shows it. */
let unread = 0;
const subs = new Set<(n: number) => void>();
try {
  unread = Number(sessionStorage.getItem('nn:unread') ?? 0) || 0;
} catch {}

export function setUnread(n: number) {
  unread = Math.max(0, Math.min(99, n | 0));
  try {
    sessionStorage.setItem('nn:unread', String(unread));
  } catch {}
  subs.forEach((s) => s(unread));
}

let lastAsked = 0;
/** Asks the server for the count, at most every 30 seconds (when a tab bar appears, and on focus). */
function refresh() {
  if (Date.now() - lastAsked < 30_000 || !getToken()) return;
  lastAsked = Date.now();
  api
    .activityUnread()
    .then((r) => setUnread(r.unread))
    .catch(() => {});
}

export function useUnread(): number {
  const [n, setN] = useState(0);
  useEffect(() => {
    setN(unread);
    subs.add(setN);
    refresh();
    window.addEventListener('focus', refresh);
    return () => {
      subs.delete(setN);
      window.removeEventListener('focus', refresh);
    };
  }, []);
  return n;
}
