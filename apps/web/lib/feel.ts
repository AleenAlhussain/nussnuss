import { springs } from '@nussnuss/tokens/motion';
import type { Transition } from 'motion/react';

/** The token springs, as Motion transitions. MotionConfig reducedMotion="user" turns them into fades. */
export const spring: Transition = { type: 'spring', duration: springs.standard.duration, bounce: springs.standard.bounce };
export const bouncy: Transition = { type: 'spring', duration: springs.bouncy.duration, bounce: springs.bouncy.bounce };
export const gentle: Transition = { type: 'spring', duration: springs.gentle.duration, bounce: springs.gentle.bounce };
/** Sheets: about 400 ms with a slight bounce. */
export const sheetSpring: Transition = { type: 'spring', duration: springs.sheet.duration, bounce: springs.sheet.bounce };

type Haptic = 'selection' | 'light' | 'medium' | 'success' | 'warning' | 'error';
const patterns: Record<Haptic, number | number[]> = { selection: 6, light: 12, medium: 20, success: [14, 60, 22], warning: [24, 40, 24], error: [30, 40, 30, 40, 30] };

/** Vibration where the browser supports it (Android). iOS Safari has none; the native app plays real haptics. */
export function haptic(kind: Haptic) {
  try {
    if (typeof navigator !== 'undefined' && 'vibrate' in navigator) navigator.vibrate(patterns[kind]);
  } catch {}
}

/** Shake an element once (three small moves in 300 ms). Calling it again restarts the shake. */
export function shake(el: Element | null | undefined) {
  if (!el) return;
  el.classList.remove('shake');
  void (el as HTMLElement).offsetWidth;
  el.classList.add('shake');
}

export function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
}
