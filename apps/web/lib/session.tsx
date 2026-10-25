'use client';

import { MotionConfig } from 'motion/react';
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, ApiError, getToken, setToken, type Me } from './api';
import { translate, type Lang, type TKey } from './i18n';

export type ThemePref = 'system' | 'light' | 'dark';
export type GlassPref = 'auto' | 'frosted';

interface Prefs {
  lang: Lang;
  theme: ThemePref;
  glass: GlassPref;
}

interface Session {
  ready: boolean;
  me: Me | null;
  prefs: Prefs;
  t: (k: TKey, p?: Record<string, string | number>) => string;
  setPrefs: (p: Partial<Prefs>) => void;
  start: (name: string) => Promise<void>;
  signOut: () => void;
  deleteAccount: () => Promise<void>;
}

const PREFS_KEY = 'nn:prefs';
const Ctx = createContext<Session | null>(null);

function readPrefs(): Prefs {
  const fallback: Prefs = {
    lang: typeof navigator !== 'undefined' && navigator.language?.startsWith('ar') ? 'ar' : 'en',
    theme: 'system',
    glass: 'auto',
  };
  try {
    return { ...fallback, ...JSON.parse(localStorage.getItem(PREFS_KEY) ?? '{}') };
  } catch {
    return fallback;
  }
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [me, setMe] = useState<Me | null>(null);
  const [prefs, setPrefsState] = useState<Prefs>({ lang: 'en', theme: 'system', glass: 'auto' });

  useEffect(() => {
    const p = readPrefs();
    setPrefsState(p);
    if (!getToken()) {
      setReady(true);
      return;
    }
    api
      .me()
      .then(setMe)
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) setToken(null);
      })
      .finally(() => setReady(true));
  }, []);

  // Language, direction, theme and glass live on <html> so CSS tokens and logical properties follow.
  useEffect(() => {
    const el = document.documentElement;
    el.lang = prefs.lang;
    el.dir = prefs.lang === 'ar' ? 'rtl' : 'ltr';
    if (prefs.theme === 'system') delete el.dataset.theme;
    else el.dataset.theme = prefs.theme;
    if (prefs.glass === 'frosted') el.dataset.glass = 'frosted';
    else delete el.dataset.glass;
  }, [prefs]);

  const setPrefs = useCallback((p: Partial<Prefs>) => {
    setPrefsState((old) => {
      const next = { ...old, ...p };
      try {
        localStorage.setItem(PREFS_KEY, JSON.stringify(next));
      } catch {}
      return next;
    });
    if (p.lang && getToken()) api.patchMe({ locale: p.lang }).catch(() => {});
  }, []);

  const start = useCallback(
    async (name: string) => {
      const r = await api.anonymous(name, prefs.lang);
      setToken(r.token);
      setMe(r.user);
    },
    [prefs.lang],
  );

  const signOut = useCallback(() => {
    setToken(null);
    setMe(null);
  }, []);

  const deleteAccount = useCallback(async () => {
    await api.deleteMe();
    setToken(null);
    setMe(null);
  }, []);

  const value = useMemo<Session>(
    () => ({ ready, me, prefs, setPrefs, start, signOut, deleteAccount, t: (k, p) => translate(prefs.lang, k, p) }),
    [ready, me, prefs, setPrefs, start, signOut, deleteAccount],
  );

  return (
    <Ctx.Provider value={value}>
      <MotionConfig reducedMotion="user">{children}</MotionConfig>
    </Ctx.Provider>
  );
}

export function useSession(): Session {
  const s = useContext(Ctx);
  if (!s) throw new Error('SessionProvider missing');
  return s;
}
