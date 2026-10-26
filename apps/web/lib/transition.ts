'use client';

import { prefersReducedMotion } from './feel';

type Router = { push: (href: string) => void };
type VT = { startViewTransition?: (cb: () => Promise<void>) => { finished: Promise<void>; ready: Promise<void> } };

/**
 * Opens a page so that `from` (a card) grows into the element on the new page marked
 * `data-vt="<name>"`: the shared-element transition, with the browser's View Transitions where it has them
 * (a plain navigation otherwise, and with Reduce Motion a short fade from the CSS).
 */
export function openWith(router: Router, href: string, from: HTMLElement | null, name: string) {
  const doc = document as Document & VT;
  if (!doc.startViewTransition || !from || prefersReducedMotion()) {
    router.push(href);
    return;
  }
  from.style.viewTransitionName = name;
  const vt = doc.startViewTransition(
    () =>
      new Promise<void>((resolve) => {
        router.push(href);
        const started = performance.now();
        // Timers, not animation frames: the browser holds rendering (and frames) while it waits for this.
        const wait = () => {
          const target = document.querySelector<HTMLElement>(`[data-vt="${name}"]`);
          if (target && !from.isConnected) {
            target.style.viewTransitionName = name;
            resolve();
          } else if (performance.now() - started > 450) resolve();
          else setTimeout(wait, 16);
        };
        setTimeout(wait, 16);
      }),
  );
  // A skipped transition rejects `ready`; that is fine, the page has still changed.
  vt.ready.catch(() => {});
  vt.finished
    .catch(() => {})
    .finally(() => {
      document.querySelectorAll<HTMLElement>(`[data-vt="${name}"]`).forEach((el) => (el.style.viewTransitionName = ''));
    });
}
