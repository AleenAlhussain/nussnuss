'use client';

import { AnimatePresence, motion } from 'motion/react';
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react';
import { spring } from '@/lib/feel';

interface Toast {
  id: number;
  text: string;
  action?: { label: string; run: () => void };
}
const Ctx = createContext<(text: string, action?: Toast['action']) => void>(() => {});
export const useToast = () => useContext(Ctx);

/** A glass capsule above the tab bar. With an action (Undo) it stays 5 seconds, otherwise 2.5. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<Toast | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const show = useCallback((text: string, action?: Toast['action']) => {
    if (timer.current) clearTimeout(timer.current);
    setToast({ id: Date.now(), text, action });
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
              className="glass pointer-events-auto flex max-w-md items-center gap-4 rounded-full py-2 ps-5 pe-2"
              data-testid="toast"
            >
              <span className="t-subhead font-medium text-text">{toast.text}</span>
              {toast.action ? (
                <button
                  type="button"
                  className="tap focus-ring rounded-full bg-accent px-4 t-subhead font-semibold text-on-accent"
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
