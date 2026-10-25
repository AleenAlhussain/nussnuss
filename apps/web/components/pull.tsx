'use client';

import { motion, useMotionValue, useReducedMotion, useTransform } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import { haptic } from '@/lib/feel';
import { useSession } from '@/lib/session';
import { Coin } from './coin';

const TRIGGER = 72;

/**
 * Pull to refresh on touch screens: pull down from the top of the page, the coin follows your finger and
 * turns, a light tap tells you it will refresh, and it spins until the new data is in.
 * The browser's own pull-to-refresh is turned off in CSS (overscroll-behavior), so only this one runs.
 */
export function PullToRefresh({ onRefresh }: { onRefresh: () => Promise<unknown> }) {
  const { t } = useSession();
  const reduce = useReducedMotion();
  const pull = useMotionValue(0);
  const [busy, setBusy] = useState(false);
  const run = useRef(onRefresh);
  run.current = onRefresh;
  const y = useTransform(pull, (p) => Math.min(p, TRIGGER + 24) - 48);
  const rotate = useTransform(pull, (p) => (reduce ? 0 : p * 3));
  const opacity = useTransform(pull, [0, 24, TRIGGER], [0, 0.6, 1]);

  useEffect(() => {
    let startY: number | null = null;
    let armed = false;
    const down = (e: TouchEvent) => {
      if (busy || window.scrollY > 0 || e.touches.length !== 1 || document.documentElement.dataset.sheet) return;
      startY = e.touches[0].clientY;
      armed = false;
    };
    const move = (e: TouchEvent) => {
      if (startY === null) return;
      const dy = e.touches[0].clientY - startY;
      if (dy <= 0 || window.scrollY > 0) {
        pull.set(0);
        return;
      }
      // Resistance: the further you pull, the less it moves.
      const p = dy * 0.5;
      pull.set(p);
      if (!armed && p >= TRIGGER) {
        armed = true;
        haptic('light');
      } else if (armed && p < TRIGGER) armed = false;
    };
    const up = async () => {
      if (startY === null) return;
      startY = null;
      if (!armed) {
        pull.set(0);
        return;
      }
      setBusy(true);
      pull.set(TRIGGER);
      try {
        await run.current();
      } catch {}
      setBusy(false);
      pull.set(0);
    };
    window.addEventListener('touchstart', down, { passive: true });
    window.addEventListener('touchmove', move, { passive: true });
    window.addEventListener('touchend', up);
    window.addEventListener('touchcancel', up);
    return () => {
      window.removeEventListener('touchstart', down);
      window.removeEventListener('touchmove', move);
      window.removeEventListener('touchend', up);
      window.removeEventListener('touchcancel', up);
    };
  }, [busy, pull]);

  return (
    <motion.div
      aria-hidden={!busy}
      role="status"
      aria-label={busy ? t('loading') : t('pullRefresh')}
      className="pointer-events-none fixed inset-x-0 z-20 flex justify-center"
      style={{ top: 'calc(env(safe-area-inset-top, 0px) + var(--nn-layout-top-bar))', y, opacity }}
      data-testid="pull-refresh"
      data-busy={busy || undefined}
    >
      <motion.span
        className="grid h-11 w-11 place-items-center rounded-full bg-surface shadow-[0_6px_20px_rgba(0,0,0,0.12)]"
        style={{ rotate }}
        animate={busy && !reduce ? { rotate: [0, 360] } : undefined}
        transition={busy ? { repeat: Infinity, duration: 0.9, ease: 'linear' } : undefined}
      >
        <Coin size={24} />
      </motion.span>
    </motion.div>
  );
}
