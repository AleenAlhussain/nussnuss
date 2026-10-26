'use client';

import { Airplane, Copy, CloudArrowUp, DotsThree, MagnifyingGlass, PencilSimple, ShareNetwork, Tag, Trash } from '@phosphor-icons/react';
import { CATEGORIES, expenseInGroupCurrency, memberStats, minorToInput, type Transfer } from '@nussnuss/core';
import { AnimatePresence, motion, useMotionValue, animate } from 'motion/react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ExpenseSheet, isPlusError, repeatInput, type Every } from '@/components/expense-sheet';
import { BarButton, Screen } from '@/components/glass';
import { CircleSheet, CirclesCard, GroupOptions, NewCircleSheet } from '@/components/group-options';
import { ShareSheet } from '@/components/group-sheets';
import { CATEGORY_LOOK, CategoryTile, CoverTile, FitLine } from '@/components/identity';
import { useContextMenu } from '@/components/menu';
import { usePaywall } from '@/components/paywall';
import { PullToRefresh } from '@/components/pull';
import { Rolling } from '@/components/rolling';
import { SettlePlan } from '@/components/settle';
import { useToast } from '@/components/toast';
import { Button, Empty, Segmented } from '@/components/ui';
import { api, ApiError, newId, type Circle, type Expense, type ExpenseInput, type GroupDetail } from '@/lib/api';
import { haptic, spring } from '@/lib/feel';
import { dayKey, dayLabel, money } from '@/lib/format';
import { catKey } from '@/lib/i18n';
import { useLiveVersion } from '@/lib/live';
import { useSession } from '@/lib/session';
import { play } from '@/lib/sound';
import { cacheGroup, cachedGroup, flush, isOffline, submit, usePending, withPending } from '@/lib/sync';
import { timeEnd, timeStart } from '@/lib/timing';

/** Colours for the who-paid bar, in member order (cover tones, so they work in light and dark). */
const BAR_TONES = ['violet', 'saffron', 'mint', 'coral', 'sky', 'rose', 'slate'] as const;

function BalanceHero({ g, pending }: { g: GroupDetail; pending: number }) {
  const { t, prefs } = useSession();
  const mine = g.balances[g.me] ?? 0;
  const label = mine > 0 ? t('youAreOwed') : mine < 0 ? t('youOwe') : t('allSettled');
  // Getting money back is good news (green); owing is plain text, never red.
  const tone = mine > 0 ? 'text-success' : 'text-text';
  const core = { currency: g.currency, members: g.members, expenses: g.expenses, payments: [] };
  const paid = g.members.map((m, i) => ({ m, i, v: memberStats(core, m.id).paid })).filter((x) => x.v > 0);
  const names = g.members.map((m) => (m.isMe ? t('you') : m.name)).join(prefs.lang === 'ar' ? '، ' : ', ');
  return (
    <section className="flex flex-col gap-1 px-1 pb-2" aria-label={label} data-vt="group-card">
      <span className="flex items-center gap-2 t-footnote text-text-2">
        <CoverTile cover={g.cover} emoji={g.emoji} size={28} testId="group-cover" />
        <span className="truncate">
          {names} · {g.currency}
        </span>
      </span>
      <span className="mt-1 t-subhead font-medium text-text-2">{label}</span>
      <div className="min-w-0">
        <FitLine className={`t-amount-hero ${tone}`} min={22}>
          <Rolling text={money(Math.abs(mine), g.currency, prefs.lang)} testId="my-balance" />
        </FitLine>
      </div>
      {paid.length > 1 ? (
        <div className="mt-1 flex flex-col gap-1.5" data-testid="who-paid">
          <div className="flex h-2 overflow-hidden rounded-full bg-surface-2" aria-hidden dir="ltr">
            {paid.map(({ m, i, v }) => (
              <span key={m.id} style={{ flexGrow: v, background: `var(--nn-cover-${BAR_TONES[i % BAR_TONES.length]}-fg)` }} className="h-full" />
            ))}
          </div>
          <span className="flex flex-wrap gap-x-3 t-footnote text-text-2">
            {paid.map(({ m, i, v }) => (
              <span key={m.id} className="inline-flex items-center gap-1 num whitespace-nowrap">
                <span aria-hidden className="h-2 w-2 rounded-full" style={{ background: `var(--nn-cover-${BAR_TONES[i % BAR_TONES.length]}-fg)` }} />
                {m.isMe ? t('youPaid') : m.name} {money(v, g.currency, prefs.lang)}
              </span>
            ))}
          </span>
        </div>
      ) : null}
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

/** Only one row shows its actions at a time. */
let closeOpenRow: (() => void) | null = null;
const ACTION_W = 76;

/**
 * An expense row. Swipe it towards the start to show Duplicate and Delete; press and hold (or right-click)
 * for a menu with a preview; tap its tile to change the category in one go; tap it to open it.
 */
function ExpenseRow({
  e,
  g,
  first,
  n,
  onOpen,
  onDuplicate,
  onDelete,
  onCategory,
}: {
  e: Expense;
  g: GroupDetail;
  first: boolean;
  n: number;
  onOpen: (e: Expense) => void;
  onDuplicate: (e: Expense) => void;
  onDelete: (e: Expense) => void;
  onCategory: (e: Expense, c: string) => void;
}) {
  const { t, prefs } = useSession();
  const rtl = prefs.lang === 'ar';
  const x = useMotionValue(0);
  const dragged = useRef(false);
  const [openRow, setOpenRow] = useState(false);
  const width = ACTION_W * 2;
  const shut = useCallback(() => {
    animate(x, 0, spring);
    setOpenRow(false);
  }, [x]);
  const name = (id: string) => {
    const m = g.members.find((m2) => m2.id === id);
    return m?.isMe ? t('you') : (m?.name ?? '?');
  };
  const shareCount = e.items.filter((i) => i.value > 0).length;
  const amount = money(expenseInGroupCurrency(e, g.currency), g.currency, prefs.lang);
  const menu = useContextMenu(
    () => [
      { label: t('edit'), icon: <PencilSimple size={18} />, run: () => onOpen(e), testId: 'menu-edit' },
      { label: t('duplicate'), icon: <Copy size={18} />, run: () => onDuplicate(e), testId: 'menu-duplicate' },
      { label: t('changeCategory'), icon: <Tag size={18} />, run: () => setTimeout(() => tile.current && cats.show(tile.current), 50), testId: 'menu-category' },
      { label: t('delete'), icon: <Trash size={18} />, danger: true, run: () => onDelete(e), testId: 'menu-delete' },
    ],
    () => (
      <div className="flex items-center gap-3">
        <CategoryTile category={e.category} size={44} />
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="truncate t-headline text-text">{e.title}</span>
          <span className="truncate t-footnote text-text-2">{t('paidByName', { name: name(e.paidBy) })}</span>
        </span>
        <span className="t-headline num whitespace-nowrap text-text">{amount}</span>
      </div>
    ),
  );
  const tile = useRef<HTMLButtonElement>(null);
  const cats = useContextMenu(() =>
    CATEGORIES.map((c) => {
      const L = CATEGORY_LOOK[c];
      return { label: t(catKey(c)), icon: <L.icon size={18} weight={c === e.category ? 'fill' : 'regular'} />, run: () => c !== e.category && onCategory(e, c), testId: `pick-cat-${c}` };
    }),
  );
  const { swallow, ...hold } = menu.bind;
  return (
    <motion.li
      layout
      initial={{ opacity: 0, y: first ? 8 : -6 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, height: 0 }}
      transition={{ ...spring, delay: first ? Math.min(n * 0.03, 0.12) : 0 }}
      className="relative overflow-hidden"
    >
      {/* The actions behind the row, revealed by swiping. */}
      <div className="absolute inset-y-0 end-0 flex" style={{ width }} aria-hidden={!openRow}>
        <button
          type="button"
          tabIndex={openRow ? 0 : -1}
          onClick={() => {
            shut();
            onDuplicate(e);
          }}
          className="focus-ring flex flex-1 flex-col items-center justify-center gap-1 bg-accent t-caption font-semibold text-on-accent"
          data-testid="swipe-duplicate"
        >
          <Copy size={20} />
          {t('duplicate')}
        </button>
        <button
          type="button"
          tabIndex={openRow ? 0 : -1}
          onClick={() => {
            shut();
            onDelete(e);
          }}
          className="focus-ring flex flex-1 flex-col items-center justify-center gap-1 bg-danger t-caption font-semibold text-white"
          data-testid="swipe-delete"
        >
          <Trash size={20} />
          {t('delete')}
        </button>
      </div>
      <motion.div
        drag="x"
        dragDirectionLock
        dragConstraints={rtl ? { left: 0, right: width } : { left: -width, right: 0 }}
        dragElastic={0.12}
        style={{ x }}
        onDragStart={() => {
          dragged.current = true;
          if (closeOpenRow && closeOpenRow !== shut) closeOpenRow();
        }}
        onDragEnd={(_, info) => {
          const far = rtl ? info.offset.x > width / 3 : info.offset.x < -width / 3;
          if (far) {
            animate(x, rtl ? width : -width, spring);
            setOpenRow(true);
            closeOpenRow = shut;
            haptic('selection');
          } else shut();
          setTimeout(() => (dragged.current = false), 0);
        }}
        className="relative flex items-center gap-3 bg-surface px-4 py-3"
        data-testid="expense-row-wrap"
        data-open={openRow ? 'true' : undefined}
      >
        <button
          ref={tile}
          type="button"
          aria-label={`${t('categoryFor', { title: e.title })}: ${t(catKey(e.category))}`}
          onClick={(ev) => {
            if (dragged.current) return;
            cats.show(ev.currentTarget);
          }}
          className="focus-ring shrink-0 rounded-row"
          data-testid="category-tile"
        >
          <CategoryTile category={e.category} size={44} />
        </button>
        <button
          type="button"
          {...hold}
          onClick={() => {
            if (swallow() || dragged.current) return;
            if (openRow) return shut();
            onOpen(e);
          }}
          className="focus-ring flex min-w-0 flex-1 scroll-mt-[calc(env(safe-area-inset-top,0px)+var(--nn-layout-top-bar)+3rem)] items-center gap-3 text-start"
          data-testid="expense-row"
        >
          <span className="flex min-w-0 flex-1 flex-col">
            <span className="line-clamp-2 t-headline text-text">{e.title}</span>
            <span className="truncate t-footnote text-text-2">
              {t('paidByName', { name: name(e.paidBy) })} · {shareCount === g.members.length ? t('everyone') : t('forN', { n: shareCount })}
            </span>
          </span>
          <span className="shrink-0 t-headline text-text num whitespace-nowrap">{amount}</span>
        </button>
      </motion.div>
      {menu.menu}
      {cats.menu}
    </motion.li>
  );
}

/** One continuous list with day headings: the balance first and large, then everything that happened. */
function ExpenseList({
  g,
  onOpen,
  onAdd,
  onDuplicate,
  onDelete,
  onCategory,
  q = '',
}: {
  g: GroupDetail;
  onOpen: (e: Expense) => void;
  onAdd: () => void;
  onDuplicate: (e: Expense) => void;
  onDelete: (e: Expense) => void;
  onCategory: (e: Expense, c: string) => void;
  q?: string;
}) {
  const { t, prefs } = useSession();
  const lang = prefs.lang;
  // The first time the list appears its rows arrive one after another (30 ms apart, within 400 ms).
  const first = useRef(true);
  useEffect(() => {
    first.current = false;
  }, []);
  const shown = useMemo(() => {
    const k = q.trim().toLocaleLowerCase();
    if (!k) return g.expenses;
    return g.expenses.filter((e) => {
      const who = g.members.find((m) => m.id === e.paidBy)?.name ?? '';
      const amount = money(expenseInGroupCurrency(e, g.currency), g.currency, lang).replace(/ /g, ' ').toLocaleLowerCase();
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

  if (!g.expenses.length)
    return (
      <Empty title={t('noExpensesTitle')} body={t('noExpensesBody')}>
        <Button block onClick={onAdd} data-testid="empty-add">
          {t('addFirst')}
        </Button>
      </Empty>
    );
  if (!shown.length) return <p className="py-8 text-center t-subhead text-text-2">{t('noResults', { q: q.trim() })}</p>;
  let row = 0;
  // overflow-clip, not hidden: hidden would make the list its own scroll box and break the sticky day headings.
  return (
    <div className="overflow-clip rounded-card bg-surface">
      {days.map((d) => (
        <section key={d.key}>
          <h2 className="sticky top-[calc(env(safe-area-inset-top,0px)+var(--nn-layout-top-bar))] z-10 bg-surface/95 px-4 pb-1 pt-3 t-footnote font-semibold text-text-2 backdrop-blur">{d.label}</h2>
          <ul className="divide-y divide-separator/60">
            <AnimatePresence>
              {d.items.map((e) => (
                <ExpenseRow key={e.id} e={e} g={g} first={first.current} n={row++} onOpen={onOpen} onDuplicate={onDuplicate} onDelete={onDelete} onCategory={onCategory} />
              ))}
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

function GroupScreen() {
  const { id } = useParams<{ id: string }>();
  const params = useSearchParams();
  const { ready, me, t, prefs, refreshPlan } = useSession();
  const router = useRouter();
  const toast = useToast();
  const paywall = usePaywall();
  const [g, setG] = useState<GroupDetail | null>(null);
  const [missing, setMissing] = useState(false);
  const [unreachable, setUnreachable] = useState(false);
  const [tab, setTab] = useState<'expenses' | 'settle'>(params.get('settle') === '1' ? 'settle' : 'expenses');
  const [sheet, setSheet] = useState<{ open: boolean; editing: Expense | null; every?: Every }>({ open: false, editing: null });
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

  // Links from Home: ?add=1 opens the add sheet, ?invite=1 the invite sheet, ?settle=1 Settle up.
  const opened = useRef(false);
  useEffect(() => {
    if (!g || opened.current) return;
    opened.current = true;
    if (params.get('add') === '1') {
      timeStart('add_expense');
      setSheet({ open: true, editing: null });
    } else if (params.get('invite') === '1') setPanel('share');
    if (params.get('settle') === '1') timeStart('settle');
    if ([...params.keys()].length) router.replace(`/g/${id}`, { scroll: false });
  }, [g, params, router, id]);

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

  const openAdd = (every?: Every) => {
    timeStart('add_expense');
    setSheet({ open: true, editing: null, every });
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
      if (!editing) timeEnd('add_expense', true);
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

  /** Repeat (hold +) and Duplicate (swipe or menu): the same bill again, today, with Undo. */
  const again = async (e: Expense, word: 'repeated' | 'duplicated') => {
    if (!g) return;
    const input = repeatInput(e);
    setSheet({ open: false, editing: null });
    try {
      const r = await submit({ kind: 'add', groupId: g.id, input, title: input.title }, g);
      apply(r.detail);
      play('tap', prefs.sounds);
      toast(r.queued ? t('savedOffline') : t(word), {
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
      haptic('warning');
      toast(r.queued ? t('savedOffline') : t('deleted'), r.queued ? undefined : { label: t('undo'), run: () => api.restoreExpense(e.id).then(apply).catch(() => toast(t('error'))) });
    } catch {
      toast(t('error'));
    }
  };

  const recategorize = async (e: Expense, category: string) => {
    if (!g) return;
    const input: ExpenseInput = { title: e.title, amount: e.amount, currency: e.currency, rate: e.rate, paidBy: e.paidBy, mode: e.mode, items: e.items, category, spentAt: e.spentAt };
    try {
      const r = await submit({ kind: 'update', groupId: g.id, expenseId: e.id, input, title: e.title }, g);
      apply(r.detail);
      haptic('success');
      toast(r.queued ? t('savedOffline') : t('categoryChanged'));
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
      timeEnd('settle', true);
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
      title={g.name}
      back="/"
      testId="group"
      onAdd={() => openAdd()}
      onAddHold={last ? () => again(last, 'repeated') : undefined}
      addLabel={t('addExpense')}
      actions={
        <>
          <BarButton label={t('inviteFriends')} onClick={() => setPanel('share')} testId="share">
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
          if (v === 'settle') timeStart('settle');
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
        <label className="flex h-11 items-center gap-2 rounded-full bg-surface px-4 text-text-2 ring-1 ring-edge focus-within:ring-2 focus-within:ring-accent">
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
      {tab === 'expenses' ? (
        <ExpenseList
          g={g}
          q={q}
          onOpen={(e) => setSheet({ open: true, editing: e })}
          onAdd={() => openAdd()}
          onDuplicate={(e) => again(e, 'duplicated')}
          onDelete={remove}
          onCategory={recategorize}
        />
      ) : (
        <SettlePlan group={g} onPay={pay} />
      )}
      <PullToRefresh onRefresh={() => flush(undefined, apply).finally(load)} />
      <ExpenseSheet
        open={sheet.open}
        editing={sheet.editing}
        startEvery={sheet.every}
        onClose={() => setSheet({ open: false, editing: null })}
        group={g}
        lastPayer={lastPayer}
        onSave={save}
        onDelete={remove}
        onRepeat={(e) => again(e, 'repeated')}
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
        onAddRepeating={() => {
          setPanel(null);
          openAdd('month');
        }}
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

export default function GroupPage() {
  return (
    <Suspense>
      <GroupScreen />
    </Suspense>
  );
}
