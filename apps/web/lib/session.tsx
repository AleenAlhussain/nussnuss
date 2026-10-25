'use client';

import { MotionConfig } from 'motion/react';
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, ApiError, getToken, setToken, type Me, type Plan, type Session as Signed } from './api';
import { kvClear } from './kv';
import { translate, type Lang, type TKey } from './i18n';

export type ThemePref = 'system' | 'light' | 'dark';
export type GlassPref = 'auto' | 'frosted';
export type Look = 'default' | 'night' | 'saffron';
export const LOOKS: Look[] = ['default', 'night', 'saffron'];

interface Prefs {
  lang: Lang;
  theme: ThemePref;
  glass: GlassPref;
  look: Look;
  sounds: boolean;
}

interface Session {
  ready: boolean;
  me: Me | null;
  prefs: Prefs;
  plan: Plan | null;
  t: (k: TKey, p?: Record<string, string | number>) => string;
  setPrefs: (p: Partial<Prefs>) => void;
  start: (name: string) => Promise<void>;
  /** Takes over a session made elsewhere (a recovery code, a device code, a passkey). */
  adopt: (s: Signed) => void;
  setMe: (m: Me) => void;
  refreshPlan: () => Promise<Plan | null>;
  ownsLook: (l: Look) => boolean;
  /** True once someone has just made their account, so the app can go straight to the first group. */
  firstRun: boolean;
  endFirstRun: () => void;
  signOut: () => void;
  deleteAccount: () => Promise<void>;
}

const FREE: Plan = { plus: false, plusUntil: null, tripPasses: [], looks: [] };

const PREFS_KEY = 'nn:prefs';
const Ctx = createContext<Session | null>(null);

function readPrefs(): Prefs {
  const fallback: Prefs = {
    lang: typeof navigator !== 'undefined' && navigator.language?.startsWith('ar') ? 'ar' : 'en',
    theme: 'system',
    glass: 'auto',
    look: 'default',
    sounds: false,
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
  const [prefs, setPrefsState] = useState<Prefs>({ lang: 'en', theme: 'system', glass: 'auto', look: 'default', sounds: false });
  const [plan, setPlan] = useState<Plan | null>(null);
  const [firstRun, setFirstRun] = useState(false);

  const refreshPlan = useCallback(async () => {
    try {
      const p = await api.plan();
      setPlan(p);
      try {
        localStorage.setItem('nn:plan', JSON.stringify(p));
      } catch {}
      return p;
    } catch {
      return null;
    }
  }, []);

  useEffect(() => {
    const p = readPrefs();
    setPrefsState(p);
    try {
      const cached = localStorage.getItem('nn:plan');
      if (cached) setPlan(JSON.parse(cached));
    } catch {}
    try {
      const cachedMe = localStorage.getItem('nn:me');
      if (cachedMe && getToken()) setMe(JSON.parse(cachedMe));
    } catch {}
    if (!getToken()) {
      setReady(true);
      return;
    }
    api
      .me()
      .then((m) => {
        setMe(m);
        refreshPlan();
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) {
          setToken(null);
          setMe(null);
        }
        // Offline: keep the copy of the account saved on this device.
      })
      .finally(() => setReady(true));
  }, [refreshPlan]);

  useEffect(() => {
    try {
      if (me) localStorage.setItem('nn:me', JSON.stringify(me));
      else localStorage.removeItem('nn:me');
    } catch {}
  }, [me]);

  const ownsLook = useCallback((l: Look) => l === 'default' || !!plan?.plus || !!plan?.looks.includes(`nussnuss.look.${l}`), [plan]);

  // Language, direction, theme and glass live on <html> so CSS tokens and logical properties follow.
  useEffect(() => {
    const el = document.documentElement;
    el.lang = prefs.lang;
    el.dir = prefs.lang === 'ar' ? 'rtl' : 'ltr';
    if (prefs.theme === 'system') delete el.dataset.theme;
    else el.dataset.theme = prefs.theme;
    if (prefs.glass === 'frosted') el.dataset.glass = 'frosted';
    else delete el.dataset.glass;
    // A look someone has not got (or no longer has) falls back to the standard one.
    if (prefs.look !== 'default' && ownsLook(prefs.look)) el.dataset.look = prefs.look;
    else delete el.dataset.look;
    // The browser bar takes the screen's background, including a look's.
    const bg = getComputedStyle(el).getPropertyValue('--nn-bg').trim();
    if (bg) document.querySelectorAll('meta[name="theme-color"]').forEach((m) => m.setAttribute('content', bg));
  }, [prefs, ownsLook]);

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
      setPlan(FREE);
      setFirstRun(true);
    },
    [prefs.lang],
  );

  const adopt = useCallback(
    (r: Signed) => {
      kvClear();
      setToken(r.token);
      setMe(r.user);
      refreshPlan();
    },
    [refreshPlan],
  );

  const forget = useCallback(() => {
    setToken(null);
    setMe(null);
    setPlan(null);
    kvClear();
    try {
      localStorage.removeItem('nn:plan');
    } catch {}
  }, []);

  const signOut = useCallback(() => forget(), [forget]);

  const deleteAccount = useCallback(async () => {
    await api.deleteMe();
    forget();
  }, [forget]);

  const endFirstRun = useCallback(() => setFirstRun(false), []);

  const value = useMemo<Session>(
    () => ({
      ready,
      me,
      prefs,
      plan,
      setPrefs,
      start,
      adopt,
      setMe,
      refreshPlan,
      ownsLook,
      firstRun,
      endFirstRun,
      signOut,
      deleteAccount,
      t: (k, p) => translate(prefs.lang, k, p),
    }),
    [ready, me, prefs, plan, setPrefs, start, adopt, refreshPlan, ownsLook, firstRun, endFirstRun, signOut, deleteAccount],
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
