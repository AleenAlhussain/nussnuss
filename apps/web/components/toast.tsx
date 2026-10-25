'use client';

import { AnimatePresence, motion } from 'motion/react';
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react';
import { spring } from '@/lib/feel';
import { DrawCheck } from './ui';

interface Toast {
  id: number;
  text: string;
  action?: { label: string; run: () => void };
  /** Something got done (paid, settled): a checkmark draws itself before the text. */
  done?: boolean;
}
type Show = (text: string, action?: Toast['action'], opts?: { done?: boolean }) => void;
const Ctx = createContext<Show>(() => {});
export const useToast = () => useContext(Ctx);

/**
 * A glass capsule above the tab bar. With an action (Undo) it stays 5 seconds, otherwise 2.5.
 * Over an open sheet it turns solid (CSS: html[data-sheet] .toast), so glass never sits on glass.
 */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<Toast | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const show = useCallback<Show>((text, action, opts) => {
    if (timer.current) clearTimeout(timer.current);
    setToast({ id: Date.now(), text, action, done: opts?.done });
    timer.current = setTimeout(() => setToast(null), action ? 5000 : 2500);
  }, []);

  return (
    <Ctx.Provider value={show}>
      {children}
      <div
        className="pointer-events-none fixed inset-x-0 z-50 flex justify-center px-4"
        style={{ bottom: 'calc(env(safe-area-inset-bottom, 0px) + var(--nn-layout-tab-bar) + 24px)' }}
        aria-live="polite"
        role="status"
      >
        <AnimatePresence>
          {toast && (
            <motion.div
              key={toast.id}
              initial={{ opacity: 0, y: 16, scale: 0.96 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 8, scale: 0.98 }}
              transition={spring}
              className="glass toast pointer-events-auto flex max-w-md items-center gap-4 rounded-full py-2 ps-5 pe-2"
              data-testid="toast"
            >
              <span className="flex items-center gap-2 t-subhead font-semibold text-text">
                {toast.done ? <DrawCheck size={18} className="shrink-0 text-success" /> : null}
                {toast.text}
              </span>
              {toast.action ? (
                <button
                  type="button"
                  className="tap press focus-ring rounded-full bg-accent px-4 t-subhead font-semibold text-on-accent"
                  onClick={() => {
                    toast.action?.run();
                    setToast(null);
                  }}
                >
                  {toast.action.label}
                </button>
              ) : (
                <span className="w-3" />
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </Ctx.Provider>
  );
}
