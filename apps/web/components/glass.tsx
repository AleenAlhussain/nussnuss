'use client';

import { AnimatePresence, motion, useDragControls } from 'motion/react';
import { CaretLeft, GearSix, Plus, UsersThree } from '@phosphor-icons/react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createContext, useCallback, useContext, useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { bouncy, haptic, sheetSpring, spring } from '@/lib/feel';
import { useSession } from '@/lib/session';
import { cx } from './ui';

/**
 * Whether the top bar has become glass (once the large title has scrolled under it). Its buttons then
 * become plain fills, because glass never sits on glass.
 */
const BarGlass = createContext(false);

/** Tracks scroll: how far down, and whether the person is scrolling down (to shrink the tab bar). */
function useScroll() {
  const [y, setY] = useState(0);
  const [down, setDown] = useState(false);
  useEffect(() => {
    let last = window.scrollY;
    let raf = 0;
    const on = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const now = window.scrollY;
        setY(now);
        if (Math.abs(now - last) > 6) setDown(now > last && now > 80);
        last = now;
      });
    };
    on();
    window.addEventListener('scroll', on, { passive: true });
    return () => {
      window.removeEventListener('scroll', on);
      cancelAnimationFrame(raf);
    };
  }, []);
  return { y, down };
}

/**
 * A screen with an iOS-style large title that collapses into the glass top bar on scroll,
 * the floating tab bar, and an optional add button. Content stays a solid layer underneath.
 */
export function Screen({
  title,
  back,
  actions,
  onAdd,
  onAddHold,
  addLabel,
  tabs = true,
  children,
  header,
  testId,
}: {
  title: string;
  back?: string;
  actions?: ReactNode;
  onAdd?: () => void;
  /** Press and hold on the add button (repeat the last expense). */
  onAddHold?: () => void;
  addLabel?: string;
  tabs?: boolean;
  children: ReactNode;
  header?: ReactNode;
  testId?: string;
}) {
  const { y, down } = useScroll();
  const { t } = useSession();
  const router = useRouter();
  const collapsed = y > 44;
  return (
    <div className="min-h-dvh" data-testid={testId}>
      {/* At the top the bar is clear and its buttons are glass. Once the title scrolls under it, the bar itself
          turns into a band of glass (fading out at its lower edge) and the buttons become plain fills. */}
      <header className="fixed inset-x-0 top-0 z-30" style={{ paddingTop: 'env(safe-area-inset-top, 0px)' }} data-collapsed={collapsed || undefined}>
        <div
          aria-hidden
          className={cx('pointer-events-none absolute inset-x-0 top-0 transition-opacity duration-200', collapsed ? 'opacity-100' : 'opacity-0')}
          style={{
            height: 'calc(env(safe-area-inset-top, 0px) + var(--nn-layout-top-bar) + 16px)',
            background: 'var(--nn-glass-fill)',
            WebkitBackdropFilter: 'blur(var(--nn-glass-blur)) saturate(var(--nn-glass-saturate))',
            backdropFilter: 'blur(var(--nn-glass-blur)) saturate(var(--nn-glass-saturate))',
            WebkitMaskImage: 'linear-gradient(to bottom, #000 calc(100% - 16px), transparent)',
            maskImage: 'linear-gradient(to bottom, #000 calc(100% - 16px), transparent)',
          }}
        />
        <div
          className="relative mx-auto flex items-center gap-1"
          style={{ height: 'var(--nn-layout-top-bar)', maxWidth: 'var(--nn-layout-max-content)', paddingInline: 'max(8px, env(safe-area-inset-left, 0px))' }}
        >
          <BarGlass.Provider value={collapsed}>
          <div className="flex min-w-[88px] items-center">
            {back ? (
              <BarButton label={t('back')} onClick={() => (window.history.length > 1 ? router.back() : router.push(back))} testId="back">
                <CaretLeft size={22} weight="bold" className="rtl:-scale-x-100" />
              </BarButton>
            ) : null}
          </div>
          <motion.h1
            aria-hidden={!collapsed}
            initial={false}
            animate={{ opacity: collapsed ? 1 : 0, y: collapsed ? 0 : 6 }}
            transition={spring}
            className="flex-1 truncate text-center t-headline text-text"
          >
            {title}
          </motion.h1>
          <div className="flex min-w-[88px] items-center justify-end gap-1">{actions}</div>
          </BarGlass.Provider>
        </div>
      </header>

      <main
        className="mx-auto flex flex-col gap-6"
        style={{
          maxWidth: 'var(--nn-layout-max-content)',
          paddingTop: 'calc(env(safe-area-inset-top, 0px) + var(--nn-layout-top-bar))',
          paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + var(--nn-layout-tab-bar) + 56px)',
          paddingInline: 'max(var(--nn-space-margin), env(safe-area-inset-left, 0px))',
        }}
      >
        <motion.h1
          initial={false}
          animate={{ opacity: collapsed ? 0 : 1, scale: collapsed ? 0.96 : 1 }}
          transition={spring}
          className="t-large-title origin-[0%_50%] text-text rtl:origin-[100%_50%]"
        >
          {title}
        </motion.h1>
        {header}
        {children}
      </main>

      {tabs || onAdd ? <TabBar compact={down} onAdd={onAdd} onAddHold={onAddHold} addLabel={addLabel} showTabs={tabs} /> : null}
    </div>
  );
}

/** Which tab a path belongs to, and where each tab was last (so switching tabs never loses your place). */
const TAB_OF = (path: string) => (path.startsWith('/settings') || path === '/privacy' || path === '/terms' ? 'settings' : 'groups');
const lastPath = (tab: string): string | null => {
  try {
    return sessionStorage.getItem(`nn:tab:${tab}`);
  } catch {
    return null;
  }
};

/**
 * Floating glass capsule with the two tabs, and a separate tinted add button, like the iOS 26 tab bar.
 * Scrolling down shrinks it to an icon-only capsule; scrolling up brings the labels back. Each tab keeps
 * its own place; tapping the tab you are on scrolls to the top, and tapping it again goes to its first screen.
 */
function TabBar({ compact, onAdd, onAddHold, addLabel, showTabs }: { compact: boolean; onAdd?: () => void; onAddHold?: () => void; addLabel?: string; showTabs: boolean }) {
  const path = usePathname();
  const router = useRouter();
  const { t } = useSession();
  const current = TAB_OF(path);
  useEffect(() => {
    try {
      sessionStorage.setItem(`nn:tab:${current}`, path);
    } catch {}
  }, [current, path]);
  const tabs = [
    { key: 'groups', href: '/', label: t('groups'), icon: UsersThree },
    { key: 'settings', href: '/settings', label: t('settings'), icon: GearSix },
  ];
  return (
    <nav
      aria-label="Main"
      className="pointer-events-none fixed inset-x-0 bottom-0 z-30 flex justify-center"
      style={{ paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 12px)', paddingInline: 'max(16px, env(safe-area-inset-left, 0px))' }}
    >
      {/* A container, so the tab labels step aside (icons only) when large text would push the add button off screen. */}
      <div className="@container flex w-full items-end justify-between gap-3" style={{ maxWidth: 'var(--nn-layout-max-content)' }}>
        {showTabs ? (
          <motion.div
            initial={false}
            animate={{ scale: compact ? 0.9 : 1, y: compact ? 4 : 0 }}
            transition={spring}
            className="glass pointer-events-auto flex origin-bottom-left items-center gap-1 rounded-full p-1.5 rtl:origin-bottom-right"
            data-testid="tab-bar"
            data-compact={compact || undefined}
          >
            {tabs.map((tab) => {
              const on = tab.key === current;
              const target = on ? tab.href : (lastPath(tab.key) ?? tab.href);
              return (
                <Link
                  key={tab.key}
                  href={target}
                  aria-current={on ? 'page' : undefined}
                  aria-label={tab.label}
                  data-testid={`tab-${tab.key}`}
                  onClick={(e) => {
                    haptic('selection');
                    if (!on) return;
                    e.preventDefault();
                    // On the tab already: first to the top, then back to its first screen.
                    if (window.scrollY > 4) window.scrollTo({ top: 0, behavior: 'smooth' });
                    else if (path !== tab.href) router.push(tab.href);
                  }}
                  className={cx(
                    'glass-press focus-ring flex h-12 items-center gap-2 rounded-full px-4 t-subhead font-semibold transition-colors',
                    on ? 'on-glass-fill text-text' : 'text-text-2',
                  )}
                >
                  <tab.icon size={22} weight={on ? 'fill' : 'regular'} />
                  <motion.span
                    initial={false}
                    animate={{ width: compact ? 0 : 'auto', opacity: compact ? 0 : 1 }}
                    transition={spring}
                    className="overflow-hidden whitespace-nowrap @max-[21.5rem]:sr-only"
                    aria-hidden
                  >
                    {tab.label}
                  </motion.span>
                </Link>
              );
            })}
          </motion.div>
        ) : (
          <span />
        )}
        {onAdd ? <AddButton onClick={onAdd} onHold={onAddHold} label={addLabel ?? t('addExpense')} /> : null}
      </div>
    </nav>
  );
}

/** The add button and the sheet it opens share this id, so the button grows into the sheet. */
export const ADD_MORPH = 'add-morph';

/**
 * The one tinted glass control on the screen. A light follows the pointer across it, like light on glass.
 * Press and hold runs `onHold` (repeat the last expense); a normal press opens the sheet.
 */
function AddButton({ onClick, onHold, label }: { onClick: () => void; onHold?: () => void; label: string }) {
  const ref = useRef<HTMLButtonElement>(null);
  const [light, setLight] = useState({ x: 30, y: 20 });
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const held = useRef(false);
  const cancel = () => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
  };
  return (
    <motion.button
      ref={ref}
      type="button"
      aria-label={label}
      data-testid="add"
      layoutId={ADD_MORPH}
      // Glass swells under the finger (and brightens) instead of shrinking.
      whileTap={{ scale: 1.04, filter: 'brightness(1.12)' }}
      transition={bouncy}
      style={{ borderRadius: 999 }}
      onPointerDown={() => {
        held.current = false;
        if (!onHold) return;
        cancel();
        timer.current = setTimeout(() => {
          held.current = true;
          haptic('success');
          onHold();
        }, 500);
      }}
      onPointerUp={cancel}
      onPointerLeave={cancel}
      onPointerCancel={cancel}
      onContextMenu={(e) => {
        if (onHold) e.preventDefault();
      }}
      onPointerMove={(e) => {
        const r = ref.current?.getBoundingClientRect();
        if (r) setLight({ x: ((e.clientX - r.left) / r.width) * 100, y: ((e.clientY - r.top) / r.height) * 100 });
      }}
      onClick={() => {
        if (held.current) {
          held.current = false;
          return;
        }
        haptic('light');
        onClick();
      }}
      className="focus-ring pointer-events-auto relative grid h-16 w-16 place-items-center overflow-hidden rounded-full bg-accent text-on-accent shadow-[0_10px_30px_color-mix(in_srgb,var(--nn-accent)_45%,transparent)]"
    >
      <span
        aria-hidden
        className="absolute inset-0"
        style={{ background: `radial-gradient(circle at ${light.x}% ${light.y}%, rgba(255,255,255,0.45), transparent 55%)` }}
      />
      <span aria-hidden className="absolute inset-0 rounded-full shadow-[inset_0_1px_0_rgba(255,255,255,0.5)]" />
      <Plus size={28} weight="bold" className="relative" />
    </motion.button>
  );
}

/** Icon button for the top bar: glass over content, a plain fill once the bar itself is glass. */
export function BarButton({ label, onClick, children, testId }: { label: string; onClick: () => void; children: ReactNode; testId?: string }) {
  const onGlass = useContext(BarGlass);
  return (
    <button
      type="button"
      aria-label={label}
      data-testid={testId}
      onClick={() => {
        haptic('light');
        onClick();
      }}
      className={cx('tap focus-ring glass-press inline-grid place-items-center rounded-full text-text', onGlass ? 'on-glass-fill' : 'glass')}
    >
      {children}
    </button>
  );
}

/** How many sheets are open; while any is, the screen behind steps back (see `html[data-sheet]` in CSS). */
let openSheets = 0;
function stepBack(open: boolean) {
  const el = document.documentElement;
  openSheets = Math.max(0, openSheets + (open ? 1 : -1));
  if (openSheets) {
    if (open && openSheets === 1) el.style.setProperty('--nn-sheet-origin', `${window.scrollY + window.innerHeight / 2}px`);
    el.dataset.sheet = 'open';
  } else delete el.dataset.sheet;
}

/**
 * A sheet: slides up on phones, floats in the middle on wide screens. Glass, drag the grabber down to close,
 * Esc closes, focus moves in and comes back. Its contents are solid fills, never glass on glass.
 */
export function Sheet({
  open,
  onClose,
  title,
  children,
  footer,
  testId,
  morph,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  footer?: ReactNode;
  testId?: string;
  /** Grow out of the add button (and shrink back into it) instead of sliding up. */
  morph?: boolean;
}) {
  const titleId = useId();
  const panel = useRef<HTMLDivElement>(null);
  const opener = useRef<Element | null>(null);
  const drag = useDragControls();
  const { t } = useSession();

  const close = useCallback(() => onClose(), [onClose]);
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  useEffect(() => {
    if (!open) return;
    stepBack(true);
    opener.current = document.activeElement;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const first = setTimeout(() => {
      const el = panel.current?.querySelector<HTMLElement>('[data-autofocus], input, button:not([data-grabber])');
      el?.focus();
    }, 60);
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
      if (e.key === 'Tab' && panel.current) {
        const items = [...panel.current.querySelectorAll<HTMLElement>('button, input, select, textarea, a[href], [tabindex]:not([tabindex="-1"])')].filter((n) => !n.hasAttribute('disabled'));
        if (!items.length) return;
        const a = items[0];
        const z = items[items.length - 1];
        if (e.shiftKey && document.activeElement === a) {
          e.preventDefault();
          z.focus();
        } else if (!e.shiftKey && document.activeElement === z) {
          e.preventDefault();
          a.focus();
        }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      clearTimeout(first);
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prevOverflow;
      stepBack(false);
      (opener.current as HTMLElement | null)?.focus?.();
    };
  }, [open, close]);

  // In <body>, outside <main>: the screen behind scales back while a sheet is open, and the sheet must not.
  if (!mounted) return null;
  return createPortal(
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-40 flex items-end justify-center sm:items-center" data-testid={testId}>
          <motion.div
            className="absolute inset-0 bg-black/30"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={close}
            aria-hidden
          />
          <motion.div
            ref={panel}
            role="dialog"
            aria-modal="true"
            aria-labelledby={titleId}
            layoutId={morph ? ADD_MORPH : undefined}
            initial={morph ? { opacity: 1 } : { y: '100%', opacity: 0.6 }}
            animate={{ y: 0, opacity: 1 }}
            exit={morph ? { opacity: 1 } : { y: '100%', opacity: 0.6 }}
            transition={sheetSpring}
            drag="y"
            dragControls={drag}
            dragListener={false}
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.6 }}
            onDragEnd={(_, info) => {
              if (info.offset.y > 120 || info.velocity.y > 600) close();
            }}
            className="glass relative flex max-h-[92dvh] w-full flex-col rounded-t-sheet sm:mb-0 sm:max-w-lg sm:rounded-sheet"
            style={{ paddingBottom: 'env(safe-area-inset-bottom, 0px)' }}
          >
            {morph ? (
              // The accent of the button fades into the glass of the sheet as it grows.
              <motion.span aria-hidden className="pointer-events-none absolute inset-0 z-10 rounded-[inherit] bg-accent" initial={{ opacity: 1 }} animate={{ opacity: 0 }} exit={{ opacity: 1 }} transition={{ duration: 0.28 }} />
            ) : null}
            <div className="flex cursor-grab touch-none justify-center pt-2 active:cursor-grabbing" onPointerDown={(e) => drag.start(e)}>
              <span data-grabber className="h-1.5 w-10 rounded-full bg-text-3/50" />
            </div>
            <div className="flex items-center justify-between gap-2 px-4 pb-2 pt-1">
              <span className="w-11" />
              <h2 id={titleId} className="t-headline text-text">
                {title}
              </h2>
              <button type="button" onClick={close} className="tap press focus-ring on-glass-fill grid place-items-center rounded-full t-subhead font-semibold text-text" aria-label={t('close')} data-testid="sheet-close">
                ✕
              </button>
            </div>
            <div
              className="flex-1 overflow-y-auto overscroll-contain px-5 pb-4 pt-2"
              style={{ WebkitMaskImage: 'linear-gradient(to bottom, transparent 0, #000 12px)', maskImage: 'linear-gradient(to bottom, transparent 0, #000 12px)' }}
            >
              {children}
            </div>
            {footer ? <div className="px-5 pb-5 pt-2">{footer}</div> : null}
          </motion.div>
        </div>
      )}
    </AnimatePresence>,
    document.body,
  );
}
