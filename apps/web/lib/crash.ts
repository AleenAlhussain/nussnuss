'use client';

import { API_URL } from './api';

/**
 * Sends uncaught errors to the API's crash log (which ignores them unless the server turns it on).
 * Only the message and stack are sent, once per distinct message per visit: no names, amounts or ids.
 */
const sent = new Set<string>();

function report(message: string, stack?: string) {
  const key = message.slice(0, 200);
  if (sent.has(key) || sent.size > 20) return;
  sent.add(key);
  try {
    fetch(`${API_URL}/telemetry/crash`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ app: 'web', version: process.env.NEXT_PUBLIC_APP_VERSION ?? '2.0.0', message: message.slice(0, 500), stack: stack?.slice(0, 8000) }),
      keepalive: true,
    }).catch(() => {});
  } catch {}
}

export function installCrashReporting() {
  if (typeof window === 'undefined') return;
  window.addEventListener('error', (e) => report(e.message || 'error', e.error?.stack));
  window.addEventListener('unhandledrejection', (e) => {
    const r = e.reason;
    // A dropped connection is not a crash.
    if (r?.status === 0) return;
    report(r instanceof Error ? r.message : String(r), r instanceof Error ? r.stack : undefined);
  });
}
