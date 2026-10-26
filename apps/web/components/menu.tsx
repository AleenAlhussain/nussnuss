'use client';

import { AnimatePresence, motion } from 'motion/react';
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { haptic, spring } from '@/lib/feel';

export interface MenuItem {
  label: string;
  icon?: ReactNode;
  danger?: boolean;
  run: () => void;
  testId?: string;
}

/**
 * Press and hold (or right-click, or the menu key) to open a menu for this row, like an iOS context menu:
 * a preview of the row and its actions. Returns props for the row and the menu to render. A press that
 * opened the menu doesn't also count as a tap.
 */
export function useContextMenu(items: () => MenuItem[], preview?: () => ReactNode) {
  const [at, setAt] = useState<{ x: number; y: number; w: number; bottom: number } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const opened = useRef(false);
  const start = useRef<{ x: number; y: number } | null>(null);
  const cancel = () => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
  };
  const openAt = useCallback((el: HTMLElement) => {
    const r = el.getBoundingClientRect();
    opened.current = true;
    haptic('medium');
    setAt({ x: r.left, y: r.top, w: r.width, bottom: r.bottom });
  }, []);
  const close = useCallback(() => setAt(null), []);
  const bind = {
    onPointerDown: (e: React.PointerEvent<HTMLElement>) => {
      opened.current = false;
      if (e.button !== 0) return;
      start.current = { x: e.clientX, y: e.clientY };
      const el = e.currentTarget;
      cancel();
      timer.current = setTimeout(() => openAt(el), 500);
    },
    onPointerMove: (e: React.PointerEvent<HTMLElement>) => {
      // Moving (scrolling, swiping) is not holding.
      if (start.current && Math.hypot(e.clientX - start.current.x, e.clientY - start.current.y) > 8) cancel();
    },
    // No pointerleave: a swipe-able row captures the pointer, which would end the hold at once.
    onPointerUp: cancel,
    onPointerCancel: cancel,
    onContextMenu: (e: React.MouseEvent<HTMLElement>) => {
      e.preventDefault();
      cancel();
      openAt(e.currentTarget);
    },
    onKeyDown: (e: React.KeyboardEvent<HTMLElement>) => {
      if (e.key === 'ContextMenu' || (e.shiftKey && e.key === 'F10')) {
        e.preventDefault();
        openAt(e.currentTarget);
      }
    },
    /** Call from the row's click handler: true when this press opened the menu instead. */
    swallow: () => {
      if (!opened.current) return false;
      opened.current = false;
      return true;
    },
    style: { WebkitTouchCallout: 'none' as const },
  };
  const menu = <ContextMenu at={at} onClose={close} items={at ? items() : []} preview={at ? preview?.() : null} />;
  /** Opens the menu from a button (a tap, not a hold). */
  const show = (el: HTMLElement) => {
    const r = el.getBoundingClientRect();
    haptic('selection');
    setAt({ x: r.left, y: r.top, w: r.width, bottom: r.bottom });
  };
  return { bind, menu, open: !!at, show };
}

function ContextMenu({ at, onClose, items, preview }: { at: { x: number; y: number; w: number; bottom: number } | null; onClose: () => void; items: MenuItem[]; preview?: ReactNode }) {
  const panel = useRef<HTMLDivElement>(null);
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  useEffect(() => {
    if (!at) return;
    const back = document.activeElement as HTMLElement | null;
    const first = setTimeout(() => panel.current?.querySelector<HTMLElement>('[role="menuitem"]')?.focus(), 30);
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        const list = [...(panel.current?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? [])];
        const i = list.indexOf(document.activeElement as HTMLElement);
        const n = e.key === 'ArrowDown' ? (i + 1) % list.length : (i - 1 + list.length) % list.length;
        list[n]?.focus();
        e.preventDefault();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      clearTimeout(first);
      window.removeEventListener('keydown', onKey);
      back?.focus?.();
    };
  }, [at, onClose]);
  if (!mounted) return null;
  const vw = typeof window === 'undefined' ? 400 : window.innerWidth;
  const vh = typeof window === 'undefined' ? 800 : window.innerHeight;
  const width = Math.min(300, vw - 32);
  const left = at ? Math.max(16, Math.min(at.x, vw - width - 16)) : 0;
  // Below the row when there is room, otherwise above it.
  const below = at ? at.bottom + 8 + 64 * items.length + (preview ? 96 : 0) < vh : true;
  return createPortal(
    <AnimatePresence>
      {at ? (
        <div className="fixed inset-0 z-50" data-testid="context-menu">
          <motion.div className="absolute inset-0 bg-black/25" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose} aria-hidden />
          <motion.div
            ref={panel}
            role="menu"
            initial={{ opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.96 }}
            transition={spring}
            className="absolute flex flex-col gap-2"
            style={{ left, width, ...(below ? { top: Math.max(16, at.y) } : { bottom: Math.max(16, vh - at.bottom) }), transformOrigin: below ? 'top center' : 'bottom center' }}
          >
            {preview ? <div className="rounded-card bg-surface p-4 shadow-[0_12px_40px_rgba(0,0,0,0.25)]">{preview}</div> : null}
            <div className="glass overflow-hidden rounded-card">
              {items.map((it) => (
                <button
                  key={it.label}
                  type="button"
                  role="menuitem"
                  data-testid={it.testId}
                  onClick={() => {
                    haptic('selection');
                    onClose();
                    it.run();
                  }}
                  className={`focus-ring flex min-h-12 w-full items-center justify-between gap-3 border-b border-separator/60 px-4 text-start t-body last:border-0 ${it.danger ? 'text-danger' : 'text-text'}`}
                >
                  <span>{it.label}</span>
                  <span aria-hidden>{it.icon}</span>
                </button>
              ))}
            </div>
          </motion.div>
        </div>
      ) : null}
    </AnimatePresence>,
    document.body,
  );
}
