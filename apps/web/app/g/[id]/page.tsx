'use client';

import {
  Airplane,
  Basket,
  Car,
  Coffee,
  House,
  Receipt,
  ShareNetwork,
  ShoppingBag,
  Sparkle,
  Tag,
} from '@phosphor-icons/react';
import { expenseInGroupCurrency, type Transfer } from '@nussnuss/core';
import { AnimatePresence, motion } from 'motion/react';
import { useParams, useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useRef, useState, type ComponentType } from 'react';
import { ExpenseSheet } from '@/components/expense-sheet';
import { BarButton, Screen } from '@/components/glass';
import { ShareSheet } from '@/components/group-sheets';
import { SettlePlan } from '@/components/settle';
import { useToast } from '@/components/toast';
import { Empty, Segmented } from '@/components/ui';
import { api, ApiError, newId, type Expense, type ExpenseInput, type GroupDetail } from '@/lib/api';
import { spring } from '@/lib/feel';
import { dayKey, dayLabel, money } from '@/lib/format';
import { useSession } from '@/lib/session';

const CAT_ICON: Record<string, ComponentType<{ size?: number; weight?: 'regular' | 'fill' }>> = {
  food: Coffee,
  groceries: Basket,
  transport: Car,
  stay: House,
  fun: Sparkle,
  bills: Receipt,
  shopping: ShoppingBag,
  other: Tag,
};

function BalanceHero({ g }: { g: GroupDetail }) {
  const { t, prefs } = useSession();
  const mine = g.balances[g.me] ?? 0;
  const label = mine > 0 ? t('youAreOwed') : mine < 0 ? t('youOwe') : t('allSettled');
  const tone = mine > 0 ? 'text-success' : mine < 0 ? 'text-danger' : 'text-text';
  return (
    <section className="flex flex-col gap-1 rounded-card bg-surface p-5" aria-label={label}>
      <span className="t-subhead font-medium text-text-2">{label}</span>
      <motion.span key={mine} initial={{ opacity: 0.4, y: 4 }} animate={{ opacity: 1, y: 0 }} transition={spring} className={`t-amount-hero ${tone}`} data-testid="my-balance">
        {money(Math.abs(mine), g.currency, prefs.lang)}
      </motion.span>
      <span className="t-footnote text-text-2 num" data-testid="group-total">
        {t('total')} · {money(g.total, g.currency, prefs.lang)}
      </span>
    </section>
  );
}

function ExpenseList({ g, onOpen }: { g: GroupDetail; onOpen: (e: Expense) => void }) {
  const { t, prefs } = useSession();
  const lang = prefs.lang;
  const days = useMemo(() => {
    const out: { key: string; label: string; items: Expense[] }[] = [];
    for (const e of g.expenses) {
      const k = dayKey(e.spentAt);
      let d = out.find((x) => x.key === k);
      if (!d) out.push((d = { key: k, label: dayLabel(e.spentAt, lang, t), items: [] }));
      d.items.push(e);
    }
    return out;
  }, [g.expenses, lang, t]);
  const name = (id: string) => {
    const m = g.members.find((x) => x.id === id);
    return m?.isMe ? t('you') : (m?.name ?? '?');
  };

  if (!g.expenses.length) return <Empty icon={<Receipt size={36} />} title={t('noExpensesTitle')} body={t('noExpensesBody')} />;
  return (
    <div className="flex flex-col gap-5">
      {days.map((d) => (
        <section key={d.key} className="flex flex-col gap-2">
          <h2 className="t-subhead font-semibold text-text-2 ps-1">{d.label}</h2>
          <ul className="overflow-hidden rounded-card bg-surface">
            <AnimatePresence initial={false}>
              {d.items.map((e) => {
                const Icon = CAT_ICON[e.category] ?? Tag;
                const shareCount = e.items.filter((i) => i.value > 0).length;
                return (
                  <motion.li key={e.id} layout initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, height: 0 }} transition={spring} className="border-b border-separator/60 last:border-0">
                    <button type="button" onClick={() => onOpen(e)} className="focus-ring flex w-full items-center gap-3 px-4 py-3 text-start active:bg-surface-2" data-testid="expense-row">
                      <span className="grid h-11 w-11 shrink-0 place-items-center rounded-row bg-accent-soft text-on-accent-soft" aria-hidden>
                        <Icon size={22} />
                      </span>
                      <span className="flex min-w-0 flex-1 flex-col">
                        <span className="truncate t-headline text-text">{e.title}</span>
                        <span className="truncate t-footnote text-text-2">
                          {t('paidByName', { name: name(e.paidBy) })} · {shareCount === g.members.length ? t('everyone') : t('forN', { n: shareCount })}
                        </span>
                      </span>
                      <span className="t-headline text-text num">{money(expenseInGroupCurrency(e, g.currency), g.currency, lang)}</span>
                    </button>
                  </motion.li>
                );
              })}
            </AnimatePresence>
          </ul>
        </section>
      ))}
    </div>
  );
}

export default function GroupPage() {
  const { id } = useParams<{ id: string }>();
  const { ready, me, t } = useSession();
  const router = useRouter();
  const toast = useToast();
  const [g, setG] = useState<GroupDetail | null>(null);
  const [missing, setMissing] = useState(false);
  const [tab, setTab] = useState<'expenses' | 'settle'>('expenses');
  const [sheet, setSheet] = useState<{ open: boolean; editing: Expense | null }>({ open: false, editing: null });
  const [sharing, setSharing] = useState(false);
  const version = useRef(0);

  const load = useCallback(async () => {
    try {
      const d = await api.group(id);
      version.current = d.version;
      setG(d);
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) setMissing(true);
    }
  }, [id]);

  useEffect(() => {
    if (ready && !me) router.replace('/');
    if (ready && me) load();
  }, [ready, me, load, router]);

  // Friends' changes arrive while the screen is open: a light check every 8 s while visible.
  useEffect(() => {
    if (!g) return;
    const tick = async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        const c = await api.changes(id, version.current);
        if (c.version !== version.current) load();
      } catch {}
    };
    const h = setInterval(tick, 8000);
    const onVis = () => tick();
    document.addEventListener('visibilitychange', onVis);
    return () => {
      clearInterval(h);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [g, id, load]);

  const apply = (d: GroupDetail) => {
    version.current = d.version;
    setG(d);
  };

  const save = async (input: ExpenseInput) => {
    if (!g) return;
    try {
      if (sheet.editing) apply(await api.updateExpense(sheet.editing.id, input));
      else apply((await api.addExpense(g.id, { ...input, id: newId() })).detail);
      setSheet({ open: false, editing: null });
    } catch (e) {
      toast(e instanceof ApiError && e.status === 0 ? t('offline') : (e as Error).message);
    }
  };

  const remove = async (e: Expense) => {
    setSheet({ open: false, editing: null });
    try {
      apply(await api.deleteExpense(e.id));
      toast(t('deleted'), { label: t('undo'), run: () => api.restoreExpense(e.id).then(apply).catch(() => toast(t('error'))) });
    } catch {
      toast(t('error'));
    }
  };

  const pay = async (tr: Transfer) => {
    if (!g) return;
    try {
      const r = await api.pay(g.id, tr);
      apply(r.detail);
      toast(t('paidRecorded'), { label: t('undo'), run: () => api.unpay(r.id).then(apply).catch(() => toast(t('error'))) });
    } catch {
      toast(t('error'));
    }
  };

  if (missing) {
    return (
      <Screen title="" back="/" testId="group">
        <Empty icon={<Airplane size={36} />} title={t('badLink')} body="" />
      </Screen>
    );
  }
  if (!g) {
    return (
      <Screen title="" back="/" testId="group">
        <div className="h-40 animate-pulse rounded-card bg-surface" />
        <div className="h-64 animate-pulse rounded-card bg-surface" />
      </Screen>
    );
  }

  const lastPayer = g.expenses[0]?.paidBy;
  return (
    <Screen
      title={`${g.emoji} ${g.name}`}
      back="/"
      testId="group"
      onAdd={() => setSheet({ open: true, editing: null })}
      addLabel={t('addExpense')}
      actions={
        <BarButton label={t('share')} onClick={() => setSharing(true)} testId="share">
          <ShareNetwork size={22} />
        </BarButton>
      }
      header={<BalanceHero g={g} />}
    >
      <Segmented
        label={t('expenses')}
        value={tab}
        onChange={setTab}
        testId="tab"
        options={[
          { key: 'expenses', label: `${t('expenses')} (${g.expenses.length})` },
          { key: 'settle', label: t('settleUp') },
        ]}
      />
      {tab === 'expenses' ? <ExpenseList g={g} onOpen={(e) => setSheet({ open: true, editing: e })} /> : <SettlePlan group={g} onPay={pay} />}
      <ExpenseSheet open={sheet.open} editing={sheet.editing} onClose={() => setSheet({ open: false, editing: null })} group={g} lastPayer={lastPayer} onSave={save} onDelete={remove} />
      <ShareSheet open={sharing} onClose={() => setSharing(false)} group={g} />
    </Screen>
  );
}
