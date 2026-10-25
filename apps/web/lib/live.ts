'use client';

import { useEffect, useRef } from 'react';
import { API_URL, api, getToken } from './api';

/**
 * Live updates for one group: a server-sent event stream read with fetch (so the token travels in the
 * Authorization header, not the URL). `onVersion` runs whenever the group's version moves. If the stream
 * cannot be held open, a light check every 30 s takes over until it can.
 */
export function useLiveVersion(groupId: string | null, version: number, onVersion: (v: number) => void) {
  const current = useRef(version);
  const cb = useRef(onVersion);
  current.current = version;
  cb.current = onVersion;

  useEffect(() => {
    if (!groupId) return;
    let stopped = false;
    let ctrl: AbortController | null = null;
    let retry = 1000;
    let poll: ReturnType<typeof setInterval> | null = null;
    const seen = (v: number) => {
      if (v !== current.current) cb.current(v);
    };
    const startPoll = () => {
      poll ??= setInterval(async () => {
        if (document.visibilityState !== 'visible') return;
        try {
          seen((await api.changes(groupId, current.current)).version);
        } catch {}
      }, 30_000);
    };
    const stopPoll = () => {
      if (poll) clearInterval(poll);
      poll = null;
    };

    const connect = async () => {
      while (!stopped) {
        ctrl = new AbortController();
        try {
          const res = await fetch(`${API_URL}/groups/${groupId}/events`, {
            headers: { Authorization: `Bearer ${getToken() ?? ''}`, Accept: 'text/event-stream' },
            signal: ctrl.signal,
            cache: 'no-store',
          });
          if (!res.ok || !res.body) throw new Error(String(res.status));
          stopPoll();
          retry = 1000;
          const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
          let buf = '';
          for (;;) {
            const { value, done } = await reader.read();
            if (done) break;
            buf += value;
            let i: number;
            while ((i = buf.indexOf('\n\n')) >= 0) {
              const block = buf.slice(0, i);
              buf = buf.slice(i + 2);
              const data = block
                .split('\n')
                .filter((l) => l.startsWith('data:'))
                .map((l) => l.slice(5).trim())
                .join('');
              if (!data) continue;
              try {
                const v = JSON.parse(data)?.version;
                if (typeof v === 'number') seen(v);
              } catch {}
            }
          }
        } catch {
          if (stopped) return;
          startPoll();
        }
        if (stopped) return;
        await new Promise((r) => setTimeout(r, retry));
        retry = Math.min(retry * 2, 30_000);
      }
    };
    connect();
    // Coming back to the tab: check at once, in case the stream was asleep.
    const onVis = async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        seen((await api.changes(groupId, current.current)).version);
      } catch {}
    };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      stopped = true;
      ctrl?.abort();
      stopPoll();
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [groupId]);
}
