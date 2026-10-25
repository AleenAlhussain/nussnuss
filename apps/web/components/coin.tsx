'use client';

import { motion, useMotionValue, useReducedMotion, useSpring, useTransform, type MotionValue } from 'motion/react';
import { useEffect } from 'react';
import { bouncy } from '@/lib/feel';

/**
 * One shared tilt for every coin on the page: the phone's orientation where the browser offers it
 * (Android; iPhone only after permission, which we never ask for just for a sheen), otherwise the pointer.
 * Values run from -1 to 1. Reduce Motion keeps the coin still.
 */
const tiltX = typeof window === 'undefined' ? null : { x: 0, y: 0, subs: new Set<() => void>(), started: false };

function startTilt() {
  if (!tiltX || tiltX.started) return;
  tiltX.started = true;
  const set = (x: number, y: number) => {
    tiltX.x = Math.max(-1, Math.min(1, x));
    tiltX.y = Math.max(-1, Math.min(1, y));
    tiltX.subs.forEach((s) => s());
  };
  window.addEventListener('deviceorientation', (e) => {
    if (e.gamma == null || e.beta == null) return;
    set(e.gamma / 35, (e.beta - 45) / 35);
  });
  window.addEventListener(
    'pointermove',
    (e) => {
      if (e.pointerType !== 'mouse') return;
      set((e.clientX / window.innerWidth) * 2 - 1, (e.clientY / window.innerHeight) * 2 - 1);
    },
    { passive: true },
  );
}

function useTilt(): { x: MotionValue<number>; y: MotionValue<number> } {
  const reduce = useReducedMotion();
  const rx = useMotionValue(0);
  const ry = useMotionValue(0);
  const x = useSpring(rx, { stiffness: 60, damping: 14 });
  const y = useSpring(ry, { stiffness: 60, damping: 14 });
  useEffect(() => {
    if (reduce || !tiltX) return;
    startTilt();
    const on = () => {
      rx.set(tiltX.x);
      ry.set(tiltX.y);
    };
    tiltX.subs.add(on);
    return () => {
      tiltX.subs.delete(on);
    };
  }, [reduce, rx, ry]);
  return { x, y };
}

/**
 * The NussNuss mark, minted: a violet enamel half and a saffron metal half, each with a sheen that
 * moves as the phone tilts. `joined` brings the halves together (the settled moment).
 */
export function Coin({ size = 72, joined = false, label }: { size?: number; joined?: boolean; label?: string }) {
  const half = size / 2;
  const gap = size * 0.07;
  const drop = joined ? 0 : size * 0.08;
  const { x, y } = useTilt();
  const sheen = useTransform([x, y], ([a, b]: number[]) => `${50 + a * 40}% ${40 + b * 40}%`);
  const metal = useTransform(x, (a) => `linear-gradient(${115 + a * 40}deg, rgba(255,255,255,0) 20%, rgba(255,255,255,0.55) 45%, rgba(255,255,255,0) 62%)`);
  return (
    <span dir="ltr" role={label ? 'img' : undefined} aria-label={label} aria-hidden={label ? undefined : true} className="relative inline-flex" style={{ width: size + gap, height: size + size * 0.08 }}>
      <motion.span
        initial={false}
        animate={{ x: joined ? size * 0.035 : 0 }}
        transition={bouncy}
        className="absolute left-0 top-0 overflow-hidden bg-accent"
        style={{ width: half, height: size, borderTopLeftRadius: half, borderBottomLeftRadius: half, boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.35), inset 0 -2px 4px rgba(0,0,0,0.18)' }}
      >
        <motion.span aria-hidden className="absolute inset-0" style={{ background: 'radial-gradient(circle at var(--p), rgba(255,255,255,0.38), transparent 55%)', ['--p' as string]: sheen }} />
      </motion.span>
      <motion.span
        initial={false}
        animate={{ x: joined ? -size * 0.035 : 0, y: drop }}
        transition={bouncy}
        className="absolute top-0 overflow-hidden bg-highlight"
        style={{ left: half + gap, width: half, height: size, borderTopRightRadius: half, borderBottomRightRadius: half, boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.5), inset 0 -2px 4px rgba(0,0,0,0.15)' }}
      >
        <motion.span aria-hidden className="absolute inset-0" style={{ backgroundImage: metal, backgroundSize: '220% 100%', backgroundPosition: sheen }} />
      </motion.span>
    </span>
  );
}

/** Shown when the last transfer is paid: the halves join, a soft ring pulses once. */
export function SettledMoment({ title, body }: { title: string; body: string }) {
  return (
    <div className="flex flex-col items-center gap-4 rounded-card bg-surface px-6 py-10 text-center" data-testid="all-settled">
      <div className="relative">
        <motion.span aria-hidden className="absolute -inset-4 rounded-full bg-success-soft" initial={{ scale: 0.6, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={bouncy} />
        <span className="relative">
          <Coin size={64} joined />
        </span>
      </div>
      <h3 className="t-title-3 text-text">{title}</h3>
      <p className="t-subhead text-text-2">{body}</p>
    </div>
  );
}
