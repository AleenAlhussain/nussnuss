import { springs } from '@nussnuss/tokens/motion';
import type { Transition } from 'motion/react';

/** The token springs, as Motion transitions. MotionConfig reducedMotion="user" turns them into fades. */
export const spring: Transition = { type: 'spring', duration: springs.standard.duration, bounce: springs.standard.bounce };
export const bouncy: Transition = { type: 'spring', duration: springs.bouncy.duration, bounce: springs.bouncy.bounce };
export const gentle: Transition = { type: 'spring', duration: springs.gentle.duration, bounce: springs.gentle.bounce };

type Haptic = 'selection' | 'light' | 'success' | 'warning';
const patterns: Record<Haptic, number | number[]> = { selection: 6, light: 12, success: [14, 60, 22], warning: [24, 40, 24] };

/** Vibration where the browser supports it (Android). iOS Safari has none; the native app plays real haptics. */
export function haptic(kind: Haptic) {
  try {
    if (typeof navigator !== 'undefined' && 'vibrate' in navigator) navigator.vibrate(patterns[kind]);
  } catch {}
}

export function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
}
