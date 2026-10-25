'use client';

import { useEffect } from 'react';
import { installCrashReporting } from '@/lib/crash';
import { useSession } from '@/lib/session';
import { flush } from '@/lib/sync';
import { useToast } from './toast';

/**
 * Work the whole app needs, whatever screen is open: replay waiting changes when the connection
 * comes back (telling the person about any the server refused), report crashes, and register the
 * service worker so the app opens offline.
 */
export function AppAgent() {
  const { me, t } = useSession();
  const toast = useToast();
  useEffect(() => {
    installCrashReporting();
    if (process.env.NODE_ENV === 'production' && 'serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
  }, []);
  useEffect(() => {
    if (!me) return;
    const run = () => flush((op) => toast(t('syncFailed', { title: op.title })));
    run();
    window.addEventListener('online', run);
    const h = setInterval(run, 60_000);
    return () => {
      window.removeEventListener('online', run);
      clearInterval(h);
    };
  }, [me, t, toast]);
  return null;
}
