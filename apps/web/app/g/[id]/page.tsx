'use client';

import { Airplane, Basket, Car, CloudArrowUp, Coffee, DotsThree, House, MagnifyingGlass, Receipt, ShareNetwork, ShoppingBag, Sparkle, Tag } from '@phosphor-icons/react';
import { expenseInGroupCurrency, minorToInput, type Transfer } from '@nussnuss/core';
import { AnimatePresence, motion } from 'motion/react';
import { useParams, useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useRef, useState, type ComponentType } from 'react';
import { ExpenseSheet, isPlusError, repeatInput, type Every } from '@/components/expense-sheet';
import { BarButton, Screen } from '@/components/glass';
import { CircleSheet, CirclesCard, GroupOptions, NewCircleSheet } from '@/components/group-options';
import { ShareSheet } from '@/components/group-sheets';
import { usePaywall } from '@/components/paywall';
import { PullToRefresh } from '@/components/pull';
import { Rolling } from '@/components/rolling';
import { SettlePlan } from '@/components/settle';
import { useToast } from '@/components/toast';
import { Empty, Segmented } from '@/components/ui';
import { api, ApiError, newId, type Circle, type Expense, type ExpenseInput, type GroupDetail } from '@/lib/api';
import { spring } from '@/lib/feel';
import { dayKey, dayLabel, money } from '@/lib/format';
import { useLiveVersion } from '@/lib/live';
import { useSession } from '@/lib/session';
import { play } from '@/lib/sound';
import { cacheGroup, cachedGroup, flush, isOffline, submit, usePending, withPending } from '@/lib/sync';

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

function BalanceHero({ g, pending }: { g: GroupDetail; pending: number }) {
  const { t, prefs } = useSession();
  const mine = g.balances[g.me] ?? 0;
  const label = mine > 0 ? t('youAreOwed') : mine < 0 ? t('youOwe') : t('allSettled');
  const tone = mine > 0 ? 'text-success' : mine < 0 ? 'text-danger' : 'text-text';
  return (
    <section className="flex flex-col gap-1 px-1 pb-2" aria-label={label} data-vt="group-card">
      <span className="t-subhead font-medium text-text-2">{label}</span>
      <Rolling text={money(Math.abs(mine), g.currency, prefs.lang)} className={`t-amount-hero ${tone}`} testId="my-balance" />
      <span className="flex flex-wrap items-center gap-2 t-footnote text-text-2">
        <span className="num" data-testid="group-total">
          {t('total')} · {money(g.total, g.currency, prefs.lang)}
        </span>
        {pending ? (
          <span className="inline-flex items-center gap-1 rounded-full bg-accent-soft px-2 py-0.5 font-semibold text-on-accent-soft" data-testid="pending">
            <CloudArrowUp size={14} weight="bold" />
            {t('pendingN', { n: pending })}
          </span>
        ) : null}
      </span>
    </section>
  );
}

/** One continuous list with day headings: the balance first and large, then everything that happened. */
function ExpenseList({ g, onOpen, q = '' }: { g: GroupDetail; onOpen: (e: Expense) => void; q?: string }) {
  const { t, prefs } = useSession();
  const lang = prefs.lang;
  // The first time the list appears its rows arrive one after another (30 ms apart, within 400 ms).
  const first = useRef(true);
  useEffect(() => {
    first.current = false;
  }, []);
  const name = (id: string) => {
    const m = g.members.find((x) => x.id === id);
    return m?.isMe ? t('you') : (m?.name ?? '?');
  };
  const shown = useMemo(() => {
    const k = q.trim().toLocaleLowerCase();
    if (!k) return g.expenses;
    return g.expenses.filter((e) => {
      const who = g.members.find((m) => m.id === e.paidBy)?.name ?? '';
      const amount = money(expenseInGroupCurrency(e, g.currency), g.currency, lang).toLocaleLowerCase();
      return e.title.toLocaleLowerCase().includes(k) || who.toLocaleLowerCase().includes(k) || amount.includes(k) || minorToInput(e.amount, e.currency).includes(k);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, g.expenses, g.members, g.currency, lang]);
  const days = useMemo(() => {
    const out: { key: string; label: string; items: Expense[] }[] = [];
    for (const e of shown) {
      const k = dayKey(e.spentAt);
      let d = out.find((x) => x.key === k);
      if (!d) out.push((d = { key: k, label: dayLabel(e.spentAt, lang, t), items: [] }));
      d.items.push(e);
    }
    return out;
  }, [shown, lang, t]);

  if (!g.expenses.length) return <Empty icon={<Receipt size={36} />} title={t('noExpensesTitle')} body={t('noExpensesBody')} />;
  if (!shown.length) return <p className="py-8 text-center t-subhead text-text-2">{t('noResults', { q: q.trim() })}</p>;
  let row = 0;
  // overflow-clip, not hidden: hidden would make the list its own scroll box and break the sticky day headings.
  return (
    <div className="overflow-clip rounded-card bg-surface">
      {days.map((d) => (
        <section key={d.key}>
          <h2 className="sticky top-[calc(env(safe-area-inset-top,0px)+var(--nn-layout-top-bar))] z-10 bg-surface/95 px-4 pb-1 pt-3 t-footnote font-semibold text-text-2 backdrop-blur">{d.label}</h2>
          <ul>
            <AnimatePresence>
              {d.items.map((e) => {
                const Icon = CAT_ICON[e.category] ?? Tag;
                const shareCount = e.items.filter((i) => i.value > 0).length;
                const n = row++;
                return (
                  <motion.li
                    key={e.id}
                    layout
                    initial={{ opacity: 0, y: first.current ? 8 : -6 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, height: 0 }}
                    transition={{ ...spring, delay: first.current ? Math.min(n * 0.03, 0.12) : 0 }}
                  >
                    <button type="button" onClick={() => onOpen(e)} className="focus-ring flex w-full scroll-mt-[calc(env(safe-area-inset-top,0px)+var(--nn-layout-top-bar)+3rem)] items-center gap-3 px-4 py-3 text-start active:bg-surface-2" data-testid="expense-row">
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

/** Placeholder rows shaped like the screen, shown while the first copy loads. */
function GroupSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <div className="flex flex-col gap-2 px-1" data-vt="group-card">
        <div className="shimmer h-4 w-24 rounded" />
        <div className="shimmer h-14 w-56 rounded-control" />
        <div className="shimmer h-3 w-32 rounded" />
      </div>
      <div className="shimmer h-10 rounded-control" />
      <div className="flex flex-col gap-px overflow-hidden rounded-card">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="flex items-center gap-3 bg-surface px-4 py-3">
            <div className="shimmer h-11 w-11 rounded-row" />
            <div className="flex flex-1 flex-col gap-2">
              <div className="shimmer h-3.5 w-2/3 rounded" />
              <div className="shimmer h-3 w-1/3 rounded" />
            </div>
            <div className="shimmer h-4 w-16 rounded" />
          </div>
        ))}
      </div>
    </div>
  );
}

const nextPeriod = (every: 'week' | 'month') => {
  const d = new Date();
  if (every === 'week') d.setDate(d.getDate() + 7);
  else d.setMonth(d.getMonth() + 1);
  return d.toISOString();
};

export default function GroupPage() {
  const { id } = useParams<{ id: string }>();
  const { ready, me, t, prefs, refreshPlan } = useSession();
  const router = useRouter();
  const toast = useToast();
  const paywall = usePaywall();
  const [g, setG] = useState<GroupDetail | null>(null);
  const [missing, setMissing] = useState(false);
  const [unreachable, setUnreachable] = useState(false);
  const [tab, setTab] = useState<'expenses' | 'settle'>('expenses');
  const [sheet, setSheet] = useState<{ open: boolean; editing: Expense | null }>({ open: false, editing: null });
  const [panel, setPanel] = useState<null | 'share' | 'options' | 'new-circle' | { circle: Circle }>(null);
  const [q, setQ] = useState('');
  const pending = usePending(id);
  const version = useRef(0);

  const apply = useCallback((d: GroupDetail) => {
    version.current = d.version;
    setG(d);
  }, []);

  const load = useCallback(async () => {
    try {
      const d = await api.group(id);
      await cacheGroup(d);
      apply(withPending(d));
      setUnreachable(false);
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) setMissing(true);
      // Offline with no copy on this device yet: say so instead of loading forever.
      else if (isOffline(e)) setUnreachable(true);
    }
  }, [id, apply]);

  useEffect(() => {
    if (ready && !me) router.replace('/');
    if (!ready || !me) return;
    // The copy on this device first, so the screen opens at once, then the server's.
    cachedGroup(id).then((c) => {
      if (c) setG((cur) => cur ?? withPending(c));
    });
    flush().finally(load);
  }, [ready, me, id, load, router]);

  useLiveVersion(g ? id : null, version.current, () => load());

  // Back online, or back on a page the browser kept in memory: send what waited, then show the server's copy.
  useEffect(() => {
    const on = () => flush(undefined, apply).finally(load);
    const shown = (e: PageTransitionEvent) => {
      if (e.persisted) on();
    };
    window.addEventListener('online', on);
    window.addEventListener('pageshow', shown);
    return () => {
      window.removeEventListener('online', on);
      window.removeEventListener('pageshow', shown);
    };
  }, [load, apply]);

  const after = (queued: boolean) => {
    if (queued) toast(t('savedOffline'));
  };

  const save = async (input: ExpenseInput, every: Every) => {
    if (!g) return;
    try {
      const editing = sheet.editing;
      const r = editing
        ? await submit({ kind: 'update', groupId: g.id, expenseId: editing.id, input, title: input.title }, g)
        : await submit({ kind: 'add', groupId: g.id, input: { ...input, id: newId() }, title: input.title }, g);
      apply(r.detail);
      setSheet({ open: false, editing: null });
      play('tap', prefs.sounds);
      if (every !== 'none' && !editing) {
        try {
          apply(await api.addRecurring(g.id, { title: input.title, amount: input.amount, paidBy: input.paidBy, mode: input.mode, items: input.items, category: input.category, every, startAt: nextPeriod(every) }));
          toast(t('repeatSaved'));
        } catch (e) {
          if (isPlusError(e)) paywall.open({ groupId: g.id });
          else toast(isOffline(e) ? t('offline') : (e as Error).message);
        }
      } else after(r.queued);
    } catch (e) {
      toast((e as Error).message);
    }
  };

  const repeat = async (e: Expense) => {
    if (!g) return;
    const input = repeatInput(e);
    setSheet({ open: false, editing: null });
    try {
      const r = await submit({ kind: 'add', groupId: g.id, input, title: input.title }, g);
      apply(r.detail);
      play('tap', prefs.sounds);
      toast(r.queued ? t('savedOffline') : t('repeated'), {
        label: t('undo'),
        run: () =>
          submit({ kind: 'delete', groupId: g.id, expenseId: input.id, title: input.title }, r.detail)
            .then((x) => apply(x.detail))
            .catch(() => toast(t('error'))),
      });
    } catch (err) {
      toast((err as Error).message);
    }
  };

  const remove = async (e: Expense) => {
    if (!g) return;
    setSheet({ open: false, editing: null });
    try {
      const r = await submit({ kind: 'delete', groupId: g.id, expenseId: e.id, title: e.title }, g);
      apply(r.detail);
      toast(r.queued ? t('savedOffline') : t('deleted'), r.queued ? undefined : { label: t('undo'), run: () => api.restoreExpense(e.id).then(apply).catch(() => toast(t('error'))) });
    } catch {
      toast(t('error'));
    }
  };

  const pay = async (tr: Transfer) => {
    if (!g) return;
    const pid = newId();
    try {
      const r = await submit({ kind: 'pay', groupId: g.id, payment: { id: pid, ...tr }, title: t('markPaid') }, g);
      apply(r.detail);
      if (r.detail.transfers.length === 0) play('chime', prefs.sounds);
      toast(r.queued ? t('savedOffline') : t('paidRecorded'), r.queued ? undefined : { label: t('undo'), run: () => api.unpay(pid).then(apply).catch(() => toast(t('error'))) }, { done: !r.queued });
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
  if (!g && unreachable) {
    return (
      <Screen title="" back="/" testId="group-offline">
        <Empty icon={<CloudArrowUp size={36} />} title={t('offline')} body="" />
      </Screen>
    );
  }
  if (!g) {
    return (
      <Screen title="" back="/" testId="group-loading">
        <GroupSkeleton />
      </Screen>
    );
  }

  const lastPayer = g.expenses[0]?.paidBy;
  const last = g.expenses[0];
  return (
    <Screen
      title={`${g.emoji} ${g.name}`}
      back="/"
      testId="group"
      onAdd={() => setSheet({ open: true, editing: null })}
      onAddHold={last ? () => repeat(last) : undefined}
      addLabel={t('addExpense')}
      actions={
        <>
          <BarButton label={t('share')} onClick={() => setPanel('share')} testId="share">
            <ShareNetwork size={22} />
          </BarButton>
          <BarButton label={t('groupMore')} onClick={() => setPanel('options')} testId="group-more">
            <DotsThree size={24} weight="bold" />
          </BarButton>
        </>
      }
      header={<BalanceHero g={g} pending={pending} />}
    >
      <CirclesCard g={g} onOpen={(c) => setPanel({ circle: c })} />
      <Segmented
        label={t('expenses')}
        value={tab}
        onChange={(v) => {
          setTab(v);
          // A new tab starts at its top, like switching tabs on iOS.
          if (window.scrollY > 0) window.scrollTo({ top: 0 });
        }}
        testId="tab"
        options={[
          { key: 'expenses', label: `${t('expenses')} (${g.expenses.length})` },
          { key: 'settle', label: t('settleUp') },
        ]}
      />
      {tab === 'expenses' && g.expenses.length >= 5 ? (
        <label className="flex h-11 items-center gap-2 rounded-full bg-surface px-4 text-text-2 ring-1 ring-separator focus-within:outline focus-within:outline-3 focus-within:outline-[var(--nn-focus)]">
          <MagnifyingGlass size={18} aria-hidden />
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('search')}
            aria-label={t('search')}
            data-testid="expense-search"
            enterKeyHint="search"
            className="min-w-0 flex-1 bg-transparent t-body text-text outline-none placeholder:text-text-2"
          />
        </label>
      ) : null}
      {tab === 'expenses' ? <ExpenseList g={g} q={q} onOpen={(e) => setSheet({ open: true, editing: e })} /> : <SettlePlan group={g} onPay={pay} />}
      <PullToRefresh onRefresh={() => flush(undefined, apply).finally(load)} />
      <ExpenseSheet
        open={sheet.open}
        editing={sheet.editing}
        onClose={() => setSheet({ open: false, editing: null })}
        group={g}
        lastPayer={lastPayer}
        onSave={save}
        onDelete={remove}
        onRepeat={repeat}
      />
      <ShareSheet open={panel === 'share'} onClose={() => setPanel(null)} group={g} />
      <GroupOptions
        open={panel === 'options'}
        onClose={() => setPanel(null)}
        group={g}
        onChange={(d) => {
          apply(d);
          refreshPlan();
        }}
        onOpenCircle={(c) => setPanel({ circle: c })}
        onNewCircle={() => setPanel('new-circle')}
      />
      <NewCircleSheet
        open={panel === 'new-circle'}
        g={g}
        onClose={() => setPanel(null)}
        onCreated={(d) => {
          apply(d);
          const c = d.circles?.[d.circles.length - 1];
          setPanel(c ? { circle: c } : null);
        }}
      />
      <CircleSheet circle={panel && typeof panel === 'object' ? panel.circle : null} g={g} onClose={() => setPanel(null)} onChange={apply} />
    </Screen>
  );
}
