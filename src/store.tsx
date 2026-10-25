import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { getLocales } from 'expo-localization';
import { translate } from './i18n';
import type { Expense, ExpenseDraft, Group, Lang, Member, Payment, Settings } from './types';

const K_SETTINGS = 'nn:settings:v1';
const K_GROUPS = 'nn:groups:v1';
const kDraft = (groupId: string) => `nn:draft:v1:${groupId}`;

export function uid(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 9);
}

const nowISO = () => new Date().toISOString();

function deviceLang(): Lang {
  try {
    return getLocales()[0]?.languageCode === 'ar' ? 'ar' : 'en';
  } catch {
    return 'en';
  }
}

const defaultSettings = (): Settings => ({
  lang: deviceLang(),
  name: '',
  theme: 'system',
  accent: 'violet',
  plus: false,
  onboarded: false,
});

export interface Store {
  ready: boolean;
  settings: Settings;
  groups: Group[];
  setSettings: (s: Partial<Settings>) => void;
  createGroup: (g: { name: string; emoji: string; currency: string; members: Member[] }) => string;
  updateGroup: (id: string, g: Partial<Pick<Group, 'name' | 'emoji' | 'currency' | 'members'>>) => void;
  deleteGroup: (id: string) => void;
  addExpense: (groupId: string, e: Omit<Expense, 'id' | 'createdAt'>) => void;
  updateExpense: (groupId: string, e: Expense) => void;
  deleteExpense: (groupId: string, expenseId: string) => void;
  addPayment: (groupId: string, p: Omit<Payment, 'id' | 'date'>) => string;
  deletePayment: (groupId: string, paymentId: string) => void;
  importGroup: (g: Group) => 'new' | 'updated';
  createDemo: (lang: Lang, myName?: string) => string;
  loadDraft: (groupId: string) => Promise<ExpenseDraft | null>;
  saveDraft: (d: ExpenseDraft) => void;
  clearDraft: (groupId: string) => void;
}

const Ctx = createContext<Store | null>(null);

export function useStore(): Store {
  const s = useContext(Ctx);
  if (!s) throw new Error('StoreProvider missing');
  return s;
}

async function readJSON<T>(key: string): Promise<T | null> {
  try {
    const raw = await AsyncStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [settings, setSettingsState] = useState<Settings>(defaultSettings);
  const [groups, setGroups] = useState<Group[]>([]);
  const loaded = useRef(false);

  useEffect(() => {
    (async () => {
      const [s, g] = await Promise.all([readJSON<Settings>(K_SETTINGS), readJSON<Group[]>(K_GROUPS)]);
      if (s) setSettingsState({ ...defaultSettings(), ...s });
      if (Array.isArray(g)) setGroups(g);
      loaded.current = true;
      setReady(true);
    })();
  }, []);

  useEffect(() => {
    if (loaded.current) AsyncStorage.setItem(K_SETTINGS, JSON.stringify(settings)).catch(() => {});
  }, [settings]);
  useEffect(() => {
    if (loaded.current) AsyncStorage.setItem(K_GROUPS, JSON.stringify(groups)).catch(() => {});
  }, [groups]);

  const touch = (g: Group): Group => ({ ...g, updatedAt: nowISO() });
  const mapGroup = useCallback((id: string, fn: (g: Group) => Group) => {
    setGroups((gs) => gs.map((g) => (g.id === id ? touch(fn(g)) : g)));
  }, []);

  const setSettings = useCallback((s: Partial<Settings>) => setSettingsState((p) => ({ ...p, ...s })), []);

  const createGroup: Store['createGroup'] = useCallback((g) => {
    const id = uid();
    const t = nowISO();
    setGroups((gs) => [{ id, ...g, expenses: [], payments: [], createdAt: t, updatedAt: t }, ...gs]);
    return id;
  }, []);

  const updateGroup: Store['updateGroup'] = useCallback((id, patch) => mapGroup(id, (g) => ({ ...g, ...patch })), [mapGroup]);
  const deleteGroup = useCallback((id: string) => {
    setGroups((gs) => gs.filter((g) => g.id !== id));
    AsyncStorage.removeItem(kDraft(id)).catch(() => {});
  }, []);

  const addExpense: Store['addExpense'] = useCallback(
    (groupId, e) => mapGroup(groupId, (g) => ({ ...g, expenses: [{ ...e, id: uid(), createdAt: nowISO() }, ...g.expenses] })),
    [mapGroup],
  );
  const updateExpense: Store['updateExpense'] = useCallback(
    (groupId, e) => mapGroup(groupId, (g) => ({ ...g, expenses: g.expenses.map((x) => (x.id === e.id ? e : x)) })),
    [mapGroup],
  );
  const deleteExpense: Store['deleteExpense'] = useCallback(
    (groupId, id) => mapGroup(groupId, (g) => ({ ...g, expenses: g.expenses.filter((x) => x.id !== id) })),
    [mapGroup],
  );
  const addPayment: Store['addPayment'] = useCallback(
    (groupId, p) => {
      const id = uid();
      mapGroup(groupId, (g) => ({ ...g, payments: [...g.payments, { ...p, id, date: nowISO() }] }));
      return id;
    },
    [mapGroup],
  );
  const deletePayment: Store['deletePayment'] = useCallback(
    (groupId, id) => mapGroup(groupId, (g) => ({ ...g, payments: g.payments.filter((x) => x.id !== id) })),
    [mapGroup],
  );

  const groupsRef = useRef(groups);
  groupsRef.current = groups;
  const importGroup: Store['importGroup'] = useCallback((incoming) => {
    const exists = groupsRef.current.some((g) => g.id === incoming.id);
    setGroups((gs) =>
      exists ? gs.map((g) => (g.id === incoming.id ? { ...incoming, updatedAt: nowISO() } : g)) : [{ ...incoming, updatedAt: nowISO() }, ...gs],
    );
    return exists ? 'updated' : 'new';
  }, []);

  const createDemo: Store['createDemo'] = useCallback((lang, myName) => {
    const tr = (k: Parameters<typeof translate>[1]) => translate(lang, k);
    const keys = ['demoM1', 'demoM2', 'demoM3', 'demoM4'] as const;
    const others = keys.slice(1).map((k) => tr(k).toLowerCase());
    const mine = myName?.trim() && !others.includes(myName.trim().toLowerCase()) ? myName.trim().slice(0, 40) : null;
    const m = keys.map((k, i) => ({ id: uid(), name: i === 0 && mine ? mine : tr(k) }));
    const all = m.map((x) => ({ memberId: x.id, value: 1 }));
    const day = (n: number) => new Date(Date.now() - n * 86400000).toISOString();
    const ex = (title: string, amount: number, payer: number, n: number, cat: Expense['category'], over: Partial<Expense> = {}): Expense => ({
      id: uid(),
      title,
      amount,
      currency: 'OMR',
      rate: 1,
      paidBy: m[payer].id,
      mode: 'equal',
      items: all,
      category: cat,
      date: day(n),
      createdAt: day(n),
      ...over,
    });
    const id = uid();
    const t = nowISO();
    const g: Group = {
      id,
      name: tr('demoGroup'),
      emoji: '🏝️',
      currency: 'OMR',
      members: m,
      expenses: [
        ex(tr('demoE5'), 48000, 3, 0, 'fun', { mode: 'shares', items: [{ memberId: m[0].id, value: 1 }, { memberId: m[1].id, value: 1 }, { memberId: m[2].id, value: 2 }, { memberId: m[3].id, value: 0 }] }),
        ex(tr('demoE4'), 6750, 2, 1, 'food'),
        ex(tr('demoE3'), 12500, 0, 1, 'transport'),
        ex(tr('demoE2'), 37400, 1, 2, 'food'),
        ex(tr('demoE1'), 140000, 0, 2, 'stay'),
      ],
      payments: [],
      createdAt: t,
      updatedAt: t,
    };
    setGroups((gs) => [g, ...gs]);
    return id;
  }, []);

  const loadDraft = useCallback((groupId: string) => readJSON<ExpenseDraft>(kDraft(groupId)), []);
  const saveDraft = useCallback((d: ExpenseDraft) => {
    AsyncStorage.setItem(kDraft(d.groupId), JSON.stringify(d)).catch(() => {});
  }, []);
  const clearDraft = useCallback((groupId: string) => {
    AsyncStorage.removeItem(kDraft(groupId)).catch(() => {});
  }, []);

  const value = useMemo<Store>(
    () => ({
      ready,
      settings,
      groups,
      setSettings,
      createGroup,
      updateGroup,
      deleteGroup,
      addExpense,
      updateExpense,
      deleteExpense,
      addPayment,
      deletePayment,
      importGroup,
      createDemo,
      loadDraft,
      saveDraft,
      clearDraft,
    }),
    [ready, settings, groups, setSettings, createGroup, updateGroup, deleteGroup, addExpense, updateExpense, deleteExpense, addPayment, deletePayment, importGroup, createDemo, loadDraft, saveDraft, clearDraft],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
