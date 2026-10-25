'use client';

import { motion } from 'motion/react';
import { bouncy } from '@/lib/feel';

/** The NussNuss mark: one coin in two fair halves. `joined` brings the halves together (the settled moment). */
export function Coin({ size = 72, joined = false, label }: { size?: number; joined?: boolean; label?: string }) {
  const half = size / 2;
  const gap = size * 0.07;
  const drop = joined ? 0 : size * 0.08;
  return (
    <span dir="ltr" role={label ? 'img' : undefined} aria-label={label} aria-hidden={label ? undefined : true} className="relative inline-flex" style={{ width: size + size * 0.07, height: size + size * 0.08 }}>
      <motion.span
        initial={false}
        animate={{ x: joined ? size * 0.035 : 0 }}
        transition={bouncy}
        className="absolute left-0 top-0 bg-accent"
        style={{ width: half, height: size, borderTopLeftRadius: half, borderBottomLeftRadius: half }}
      />
      <motion.span
        initial={false}
        animate={{ x: joined ? -size * 0.035 : 0, y: drop }}
        transition={bouncy}
        className="absolute top-0 bg-highlight"
        style={{ left: half + gap, width: half, height: size, borderTopRightRadius: half, borderBottomRightRadius: half }}
      />
    </span>
  );
}

/** Shown when the last transfer is paid: the halves join, a soft ring pulses once. */
export function SettledMoment({ title, body }: { title: string; body: string }) {
  return (
    <div className="flex flex-col items-center gap-4 rounded-card bg-surface px-6 py-10 text-center" data-testid="all-settled">
      <div className="relative">
        <motion.span
          aria-hidden
          className="absolute -inset-4 rounded-full bg-success-soft"
          initial={{ scale: 0.6, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={bouncy}
        />
        <span className="relative">
          <Coin size={64} joined />
        </span>
      </div>
      <h3 className="t-title-3 text-text">{title}</h3>
      <p className="t-subhead text-text-2">{body}</p>
    </div>
  );
}
