'use client';

import { useEffect, useState } from 'react';

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

export function useUnread(): number {
  const [n, setN] = useState(0);
  useEffect(() => {
    setN(unread);
    subs.add(setN);
    return () => {
      subs.delete(setN);
    };
  }, []);
  return n;
}
