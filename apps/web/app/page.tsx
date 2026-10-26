'use client';

import { Bell, BellRinging, CaretDown, Check, CloudArrowUp, HandCoins, MagnifyingGlass, Plus, UserPlus, X } from '@phosphor-icons/react';
import { expenseInGroupCurrency } from '@nussnuss/core';
import { AnimatePresence, motion } from 'motion/react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { SignInSheet } from '@/components/account';
import { Coin } from '@/components/coin';
import { BarButton, Screen, Sheet } from '@/components/glass';
import { NewGroupSheet } from '@/components/group-sheets';
import { Avatar, CoverTile, FitLine } from '@/components/identity';
import { useContextMenu } from '@/components/menu';
import { PullToRefresh } from '@/components/pull';
import { shareText } from '@/components/settle';
import { useToast } from '@/components/toast';
import { Button, Empty, Field, Segmented } from '@/components/ui';
import { api, type GroupDetail, type GroupSummary, type NextStep, type Notice, type Overview, type PersonSummary } from '@/lib/api';
import { setUnread } from '@/lib/badge';
import { spring } from '@/lib/feel';
import { ago, money } from '@/lib/format';
import type { Lang, TKey } from '@/lib/i18n';
import { kvGet, kvSet } from '@/lib/kv';
import { useSession } from '@/lib/session';
import { cacheGroup, cachedGroup, cachedGroups, cacheGroups, usePending } from '@/lib/sync';
import { balanceShown } from '@/lib/timing';
import { openWith } from '@/lib/transition';

function Welcome() {
  const { t, prefs, setPrefs, start } = useSession();
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [signIn, setSignIn] = useState(false);
  const go = async () => {
    if (!name.trim()) return setError(t('yourNameHint'));
    setBusy(true);
    try {
      await start(name.trim().slice(0, 40));
    } catch {
      setError(t('error'));
      setBusy(false);
    }
  };
  // What the app does, before it asks for anything: add, settle, join.
  const cards: { icon: typeof Plus; title: TKey; body: TKey }[] = [
    { icon: Plus, title: 'welcome1T', body: 'welcome1B' },
    { icon: HandCoins, title: 'welcome2T', body: 'welcome2B' },
    { icon: UserPlus, title: 'welcome3T', body: 'welcome3B' },
  ];
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-between gap-8 px-6" style={{ paddingTop: 'calc(env(safe-area-inset-top, 0px) + 24px)', paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 24px)' }} data-testid="welcome">
      <div className="flex justify-end">
        <div className="w-48">
          <Segmented<Lang>
            label="Language"
            value={prefs.lang}
            testId="lang"
            onChange={(l) => setPrefs({ lang: l })}
            options={[
              { key: 'en', label: 'English' },
              { key: 'ar', label: 'العربية' },
            ]}
          />
        </div>
      </div>
      <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={spring} className="flex flex-col items-start gap-5">
        <Coin size={68} label={t('appName')} />
        <h1 className="t-large-title text-text" style={{ fontSize: 'clamp(2.25rem, 9vw, 3rem)' }}>
          {t('welcomeTitle')}
        </h1>
        <p className="t-body text-text-2">{t('welcomeBody')}</p>
        <ul className="flex w-full flex-col gap-2" data-testid="welcome-cards">
          {cards.map((c, i) => (
            <motion.li
              key={c.title}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ ...spring, delay: 0.08 + i * 0.05 }}
              className="flex items-start gap-3 rounded-card bg-surface p-4"
            >
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-row bg-accent-soft text-on-accent-soft" aria-hidden>
                <c.icon size={22} weight="bold" />
              </span>
              <span className="flex min-w-0 flex-col">
                <span className="t-headline text-text">{t(c.title)}</span>
                <span className="t-subhead text-text-2">{t(c.body)}</span>
              </span>
            </motion.li>
          ))}
        </ul>
      </motion.div>
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          go();
        }}
      >
        <Field label={t('yourName')} hint={t('yourNameHint')} error={error} value={name} maxLength={40} autoComplete="given-name" onChange={(e) => { setName(e.target.value); setError(null); }} data-testid="name" />
        <Button type="submit" block disabled={busy} data-testid="start">
          {t('start')}
        </Button>
        <Button variant="plain" block onClick={() => setSignIn(true)} data-testid="have-account">
          {t('haveAccount')}
        </Button>
      </form>
      <SignInSheet open={signIn} onClose={() => setSignIn(false)} />
    </main>
  );
}

/** The inbox: reminders the app sent me. Opening it marks them read. */
function Notices({ open, onClose, items }: { open: boolean; onClose: () => void; items: Notice[] }) {
  const { t, prefs } = useSession();
  return (
    <Sheet open={open} onClose={onClose} title={t('notifications')} testId="notifications">
      {items.length ? (
        <ul className="flex flex-col gap-2 pb-2">
          {items.map((n) => (
            <li key={n.id}>
              <Link href={n.groupId ? `/g/${n.groupId}` : '/'} onClick={onClose} className="focus-ring flex items-center gap-3 rounded-card bg-surface p-4">
                <CoverTile emoji={n.data.emoji} size={44} />
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate t-headline text-text">{n.data.group}</span>
                  <span className="t-subhead text-text-2">
                    {t('n_reminder', { to: n.data.to ?? '', amount: n.data.amount != null && n.data.currency ? money(n.data.amount, n.data.currency, prefs.lang) : '' })}
                  </span>
                </span>
                {!n.read ? <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-accent" aria-hidden /> : null}
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <p className="py-10 text-center t-subhead text-text-2">{t('noNotifications')}</p>
      )}
    </Sheet>
  );
}

function HomeSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true" data-testid="groups-loading">
      <div className="flex flex-col gap-2 px-1">
        <div className="shimmer h-4 w-40 rounded" />
        <div className="shimmer h-14 w-56 rounded-control" />
      </div>
      {[0, 1, 2].map((i) => (
        <div key={i} className="flex items-center gap-4 rounded-card bg-surface p-4">
          <div className="shimmer h-14 w-14 rounded-row" />
          <div className="flex flex-1 flex-col gap-2">
            <div className="shimmer h-4 w-1/2 rounded" />
            <div className="shimmer h-3 w-2/3 rounded" />
          </div>
          <div className="shimmer h-5 w-16 rounded" />
        </div>
      ))}
    </div>
  );
}

/** Search across groups (name and people) and the expenses of every group saved on this device. */
function useSearch(groups: GroupSummary[] | null, q: string) {
  const [details, setDetails] = useState<GroupDetail[]>([]);
  useEffect(() => {
    if (!q.trim() || !groups?.length) return;
    let live = true;
    Promise.all(groups.map((g) => cachedGroup(g.id))).then((all) => {
      if (live) setDetails(all.filter((d): d is GroupDetail => !!d));
    });
    return () => {
      live = false;
    };
  }, [q, groups]);
  return useMemo(() => {
    const k = q.trim().toLocaleLowerCase();
    if (!k || !groups) return null;
    const hit = (s: string) => s.toLocaleLowerCase().includes(k);
    const matchGroups = groups.filter((g) => hit(g.name) || g.memberNames.some(hit));
    const matchExpenses = details.flatMap((d) => d.expenses.filter((e) => hit(e.title)).map((e) => ({ e, d }))).slice(0, 30);
    return { groups: matchGroups, expenses: matchExpenses };
  }, [q, groups, details]);
}

/** "Overall, you get back AED 230.00 · and OMR 12.500 · Across 3 groups". */
function OverallHero({ o }: { o: Overview }) {
  const { t, prefs } = useSession();
  const [first, ...rest] = o.totals;
  if (!first) {
    return (
      <section className="flex flex-col gap-1 px-1" data-testid="overall">
        <span className="t-subhead font-medium text-text-2">{o.groups === 1 ? t('acrossOne') : t('acrossN', { n: o.groups })}</span>
        <span className="t-title-1 text-text">{t('overallEven')}</span>
        <span className="t-subhead text-text-2">{t('overallEvenBody')}</span>
      </section>
    );
  }
  const back = first.amount > 0;
  return (
    <section className="flex flex-col gap-1 px-1" data-testid="overall">
      <span className="t-subhead font-medium text-text-2">{back ? t('overallBack') : t('overallOwe')}</span>
      <div className="min-w-0">
        <FitLine className={`t-amount-hero ${back ? 'text-success' : 'text-text'}`} testId="overall-amount" min={22}>
          {money(Math.abs(first.amount), first.currency, prefs.lang)}
        </FitLine>
      </div>
      <span className="flex flex-wrap gap-x-2 t-footnote text-text-2">
        {rest.map((m) => (
          <span key={m.currency} className="num whitespace-nowrap" data-testid="overall-more">
            {t('andAmount', { amount: `${m.amount > 0 ? '+' : '−'}${money(Math.abs(m.amount), m.currency, prefs.lang)}` })}
          </span>
        ))}
        <span>{o.groups === 1 ? t('acrossOne') : t('acrossN', { n: o.groups })}</span>
      </span>
    </section>
  );
}

/** The one thing worth doing next, with its buttons. */
function NextStepCard({ next, onDone }: { next: NextStep; onDone: () => void }) {
  const { t, prefs } = useSession();
  const router = useRouter();
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const markPaid = async (key: string, groupId: string) => {
    setBusy(true);
    try {
      const r = await api.settleAll(key, [groupId]);
      toast(t('paidRecorded'), { label: t('undo'), run: () => api.undoPayments(r.payments.map((p) => p.id)).then(onDone).catch(() => toast(t('error'))) }, { done: true });
      onDone();
    } catch {
      toast(t('error'));
    } finally {
      setBusy(false);
    }
  };
  let line = '';
  let actions: ReactNode = null;
  if (next.kind === 'pay' || next.kind === 'collect') {
    const amount = money(next.amount, next.currency, prefs.lang);
    line = next.kind === 'pay' ? t('next_pay', { name: next.person.name, amount }) : t('next_collect', { name: next.person.name, amount });
    actions = (
      <>
        {next.kind === 'pay' ? (
          <Button className="flex-1" onClick={() => router.push(`/g/${next.group.id}?settle=1`)} data-testid="next-pay">
            {t('payName', { name: next.person.name })}
          </Button>
        ) : (
          <Button className="flex-1" icon={<BellRinging size={18} />} data-testid="next-remind" onClick={() => shareText(t('remindMessage', { name: next.person.name, amount, group: next.group.name }))}>
            {t('remindName', { name: next.person.name })}
          </Button>
        )}
        <Button variant="secondary" className="flex-1" icon={<Check size={18} weight="bold" />} disabled={busy} onClick={() => markPaid(next.person.key, next.group.id)} data-testid="next-mark-paid">
          {t('markPaid')}
        </Button>
      </>
    );
  } else if (next.kind === 'first') {
    line = t('next_first', { group: next.group.name });
    actions = (
      <Button className="flex-1" icon={<Plus size={18} weight="bold" />} onClick={() => router.push(`/g/${next.group.id}?add=1`)} data-testid="next-first">
        {t('addFirst')}
      </Button>
    );
  } else {
    line = t('next_invite', { group: next.group.name });
    actions = (
      <Button className="flex-1" icon={<UserPlus size={18} weight="bold" />} onClick={() => router.push(`/g/${next.group.id}?invite=1`)} data-testid="next-invite">
        {t('inviteFriends')}
      </Button>
    );
  }
  return (
    <motion.section layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={spring} className="flex flex-col gap-3 rounded-card bg-surface p-4" data-testid="next-step" data-kind={next.kind} aria-label={t('nextStep')}>
      <span className="t-footnote font-semibold text-text-2">{t('nextStep')}</span>
      <div className="flex items-center gap-3">
        {'person' in next ? <Avatar name={next.person.name} avatar={next.person.avatar} size={44} /> : <CoverTile cover={next.group.cover} size={44} />}
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="t-headline text-text">{line}</span>
          <span className="truncate t-footnote text-text-2">{next.group.name}</span>
        </span>
      </div>
      {/* Side by side when they fit, one above the other on a narrow phone or with large text. */}
      <div className="flex flex-wrap gap-2 [&>button]:min-w-[min(100%,10rem)] [&>button]:grow [&>button]:basis-40 [&>button]:whitespace-nowrap">{actions}</div>
    </motion.section>
  );
}

function PeopleStrip({ people }: { people: PersonSummary[] }) {
  const { t, prefs } = useSession();
  if (!people.length) return null;
  return (
    <section className="flex flex-col gap-2" aria-labelledby="people-h">
      <div className="flex items-center justify-between px-1">
        <h2 id="people-h" className="t-title-3 text-text">
          {t('people')}
        </h2>
        <Link href="/people" className="tap focus-ring inline-flex items-center rounded-full px-2 t-subhead font-semibold text-accent" data-testid="people-all">
          {t('seeAll')}
        </Link>
      </div>
      <ul className="-mx-5 flex gap-1 overflow-x-auto px-4 pb-1" data-testid="people-strip">
        {people.map((p) => {
          const b = p.balances[0];
          return (
            <li key={p.key} className="shrink-0">
              <Link href={`/p/${p.key}`} className="press focus-ring flex w-[84px] flex-col items-center gap-1.5 rounded-card px-1 py-2 text-center" data-testid="person">
                <Avatar name={p.name} avatar={p.avatar} size={52} />
                <span className="w-full truncate t-footnote font-semibold text-text">{p.name}</span>
                <span className={`t-caption num whitespace-nowrap font-semibold ${b && b.amount > 0 ? 'text-success' : 'text-text-2'}`} data-testid="person-amount">
                  {b ? `${b.amount > 0 ? '+' : '−'}${money(Math.abs(b.amount), b.currency, prefs.lang)}` : t('personEven')}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/** "Sara added Lunch · 2h" under a group's name. */
function activityLine(g: GroupSummary, t: (k: TKey, p?: Record<string, string | number>) => string, lang: Lang) {
  const a = g.lastActivity;
  if (!a) return g.memberNames.join(lang === 'ar' ? '، ' : ', ');
  const when = ago(a.at, lang);
  if (a.kind === 'expense') {
    const text = a.who?.me ? t('act_youAdded', { title: a.title }) : t('act_nameAdded', { name: a.who?.name ?? '?', title: a.title });
    return `${text} · ${when}`;
  }
  const n = (w: typeof a.from) => (w?.me ? t('you') : (w?.name ?? '?'));
  return `${t('act_paidLine', { from: n(a.from), to: n(a.to) })} · ${when}`;
}

function GroupCard({ g, i }: { g: GroupSummary; i: number }) {
  const { t, prefs } = useSession();
  const router = useRouter();
  const menu = useContextMenu(
    () => [
      { label: t('bodyCanOpen', { name: g.name }), run: () => router.push(`/g/${g.id}`), testId: 'menu-open' },
      { label: t('addExpense'), icon: <Plus size={18} />, run: () => router.push(`/g/${g.id}?add=1`), testId: 'menu-add' },
      { label: t('inviteFriends'), icon: <UserPlus size={18} />, run: () => router.push(`/g/${g.id}?invite=1`), testId: 'menu-invite' },
    ],
    () => (
      <div className="flex items-center gap-3">
        <CoverTile cover={g.cover} emoji={g.emoji} size={44} />
        <span className="flex min-w-0 flex-col">
          <span className="truncate t-headline text-text">{g.name}</span>
          <span className="truncate t-footnote text-text-2">{g.memberNames.join(prefs.lang === 'ar' ? '، ' : ', ')}</span>
        </span>
      </div>
    ),
  );
  const { swallow, ...bind } = menu.bind;
  return (
    <motion.li
      layout
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      // Rows arrive one after another, 30 ms apart, all within 400 ms.
      transition={{ ...spring, delay: Math.min(i * 0.03, 0.12) }}
      className="list-none"
    >
      <Link
        href={`/g/${g.id}`}
        {...bind}
        onClick={(e) => {
          if (swallow()) return e.preventDefault();
          if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
          e.preventDefault();
          openWith(router, `/g/${g.id}`, e.currentTarget, 'group-card');
        }}
        className="press focus-ring flex items-center gap-4 rounded-card bg-surface p-4"
        data-testid="group-card"
      >
        <CoverTile cover={g.cover} emoji={g.emoji} size={52} />
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="line-clamp-2 t-headline text-text">{g.name}</span>
          <span className="truncate t-footnote text-text-2" data-testid="group-activity">
            {activityLine(g, t, prefs.lang)}
          </span>
        </span>
        <span className="flex shrink-0 flex-col items-end text-end">
          {g.myBalance === 0 ? (
            <span className="t-subhead font-semibold text-text-2">{g.total ? t('allSettled') : money(0, g.currency, prefs.lang)}</span>
          ) : (
            <>
              <span className="t-caption text-text-2">{g.myBalance > 0 ? t('youAreOwed') : t('youOwe')}</span>
              {/* Owing is plain text, not red: red is for errors, deleting and late payments. */}
              <span className={`t-headline num whitespace-nowrap ${g.myBalance > 0 ? 'text-success' : 'text-text'}`} data-testid="group-balance">
                {money(Math.abs(g.myBalance), g.currency, prefs.lang)}
              </span>
            </>
          )}
        </span>
      </Link>
      {menu.menu}
    </motion.li>
  );
}

function GroupList({ groups }: { groups: GroupSummary[] }) {
  return (
    <ul className="flex flex-col gap-3">
      {groups.map((g, i) => (
        <GroupCard key={g.id} g={g} i={i} />
      ))}
    </ul>
  );
}

function Home() {
  const { t, prefs, firstRun, endFirstRun } = useSession();
  const router = useRouter();
  const params = useSearchParams();
  const [groups, setGroups] = useState<GroupSummary[] | null>(null);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [creating, setCreating] = useState(false);
  const [inbox, setInbox] = useState<Notice[]>([]);
  const [showInbox, setShowInbox] = useState(false);
  const [showSettled, setShowSettled] = useState(false);
  const [q, setQ] = useState('');
  const pending = usePending();
  const found = useSearch(groups, q);
  // Recent searches: the last five that led somewhere, shown while the empty field has focus.
  const [focus, setFocus] = useState(false);
  const [recent, setRecent] = useState<string[]>([]);
  useEffect(() => {
    try {
      setRecent(JSON.parse(localStorage.getItem('nn:recent-search') ?? '[]'));
    } catch {}
  }, []);
  const remember = () => {
    const k = q.trim();
    if (!k) return;
    const next = [k, ...recent.filter((r) => r.toLocaleLowerCase() !== k.toLocaleLowerCase())].slice(0, 5);
    setRecent(next);
    try {
      localStorage.setItem('nn:recent-search', JSON.stringify(next));
    } catch {}
  };
  const load = useCallback(
    (): Promise<void> =>
      Promise.all([
        api
          .groups()
          .then((g) => {
            setGroups(g);
            cacheGroups(g);
          })
          .catch(() => setGroups((g) => g ?? [])),
        api
          .overview()
          .then((o) => {
            setOverview(o);
            setUnread(o.unread);
            kvSet('overview', o);
          })
          .catch(() => {}),
      ]).then(() => {}),
    [],
  );
  useEffect(() => {
    cachedGroups().then((c) => {
      if (c) setGroups((g) => g ?? c);
    });
    kvGet<Overview>('overview').then((o) => {
      if (o) setOverview((x) => x ?? o);
    });
    load();
    api
      .notifications()
      .then(setInbox)
      .catch(() => {});
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [load]);
  useEffect(() => {
    if (overview) balanceShown();
  }, [overview]);
  // First run: straight from the welcome to making the first group.
  useEffect(() => {
    if (firstRun) {
      setCreating(true);
      endFirstRun();
    }
  }, [firstRun, endFirstRun]);
  // The "Add expense" shortcut on the home screen opens the group used last.
  useEffect(() => {
    if (params.get('add') !== '1' || !groups) return;
    if (groups[0]) router.replace(`/g/${groups[0].id}?add=1`);
    else setCreating(true);
  }, [params, groups, router]);
  const unread = inbox.filter((n) => !n.read).length;
  const open = groups?.filter((g) => !g.settled) ?? [];
  const settled = groups?.filter((g) => g.settled) ?? [];

  return (
    <Screen
      title={t('tabHome')}
      onAdd={() => setCreating(true)}
      addLabel={t('newGroup')}
      testId="groups"
      actions={
        <BarButton
          label={unread ? `${t('notifications')} (${unread})` : t('notifications')}
          testId="inbox"
          onClick={() => {
            setShowInbox(true);
            if (unread) api.markRead().then(() => setInbox((x) => x.map((n) => ({ ...n, read: true })))).catch(() => {});
          }}
        >
          <span className="relative">
            <Bell size={22} />
            {unread ? <span className="absolute -end-0.5 -top-0.5 h-2.5 w-2.5 rounded-full bg-danger ring-2 ring-bg" aria-hidden /> : null}
          </span>
        </BarButton>
      }
    >
      {groups === null ? (
        <HomeSkeleton />
      ) : groups.length === 0 ? (
        <Empty title={t('noGroupsTitle')} body={t('noGroupsBody')} testId="home-empty">
          <Button block onClick={() => setCreating(true)} data-testid="new-group">
            {t('startGroup')}
          </Button>
        </Empty>
      ) : (
        <>
          {!q && overview ? <OverallHero o={overview} /> : null}
          {pending ? (
            <p className="inline-flex items-center gap-2 self-start rounded-full bg-accent-soft px-3 py-1 t-footnote font-semibold text-on-accent-soft" data-testid="home-pending">
              <CloudArrowUp size={16} weight="bold" aria-hidden />
              {t('waitingHome', { n: pending })}
            </p>
          ) : null}
          {!q && overview?.next ? <NextStepCard next={overview.next} onDone={load} /> : null}
          <div className="sticky z-20 -mx-1 px-1" style={{ top: 'calc(env(safe-area-inset-top, 0px) + var(--nn-layout-top-bar) + 4px)' }}>
            <label className="glass flex h-11 items-center gap-2 rounded-full px-4 text-text-2 focus-within:outline focus-within:outline-3 focus-within:outline-[var(--nn-focus)]">
              <MagnifyingGlass size={18} aria-hidden />
              <input
                type="search"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                onFocus={() => setFocus(true)}
                onBlur={() => setTimeout(() => setFocus(false), 150)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') remember();
                }}
                placeholder={t('searchGroups')}
                aria-label={t('search')}
                data-testid="search"
                enterKeyHint="search"
                className="min-w-0 flex-1 bg-transparent t-body font-semibold text-text outline-none placeholder:font-normal placeholder:text-text-2 [&::-webkit-search-cancel-button]:hidden"
              />
              {q ? (
                <button type="button" onClick={() => setQ('')} aria-label={t('close')} className="tap press grid place-items-center rounded-full text-text-2">
                  <X size={16} />
                </button>
              ) : null}
            </label>
          </div>
          {focus && !q && recent.length ? (
            <div className="flex flex-col gap-2" data-testid="recent-searches">
              <h2 className="t-subhead font-semibold text-text-2 ps-1">{t('recentSearches')}</h2>
              <div className="flex flex-wrap gap-2">
                {recent.map((r) => (
                  <button
                    key={r}
                    type="button"
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => setQ(r)}
                    className="tap press focus-ring inline-flex h-11 items-center gap-2 rounded-full bg-surface px-4 t-subhead font-medium text-text ring-1 ring-edge"
                    data-testid="recent-search"
                  >
                    <MagnifyingGlass size={16} className="text-text-2" aria-hidden />
                    {r}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
          {found ? (
            <div className="flex flex-col gap-5" data-testid="search-results" onClickCapture={remember}>
              {found.groups.length ? <GroupList groups={found.groups} /> : null}
              {found.expenses.length ? (
                <section className="flex flex-col gap-2">
                  <h2 className="t-subhead font-semibold text-text-2 ps-1">{t('searchExpenses')}</h2>
                  <ul className="overflow-hidden rounded-card bg-surface">
                    {found.expenses.map(({ e, d }) => (
                      <li key={e.id} className="border-b border-separator/60 last:border-0">
                        <Link href={`/g/${d.id}`} className="focus-ring flex items-center gap-3 px-4 py-3" data-testid="search-expense">
                          <CoverTile cover={d.cover} emoji={d.emoji} size={40} />
                          <span className="flex min-w-0 flex-1 flex-col">
                            <span className="truncate t-headline text-text">{e.title}</span>
                            <span className="truncate t-footnote text-text-2">{d.name}</span>
                          </span>
                          <span className="t-subhead text-text num whitespace-nowrap">{money(expenseInGroupCurrency(e, d.currency), d.currency, prefs.lang)}</span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                </section>
              ) : null}
              {!found.groups.length && !found.expenses.length ? <p className="py-8 text-center t-subhead text-text-2">{t('noResults', { q: q.trim() })}</p> : null}
            </div>
          ) : (
            <>
              {overview ? <PeopleStrip people={overview.people} /> : null}
              <section className="flex flex-col gap-3" aria-labelledby="groups-h">
                <h2 id="groups-h" className="t-title-3 text-text ps-1">
                  {t('groups')}
                </h2>
                {open.length ? <GroupList groups={open} /> : null}
                {settled.length ? (
                  <div className="flex flex-col gap-3">
                    <button
                      type="button"
                      aria-expanded={showSettled}
                      onClick={() => setShowSettled((s) => !s)}
                      className="tap focus-ring inline-flex items-center gap-2 self-start rounded-full px-3 t-subhead font-semibold text-text-2"
                      data-testid="show-settled"
                    >
                      <motion.span animate={{ rotate: showSettled ? 180 : 0 }} transition={spring} aria-hidden>
                        <CaretDown size={16} />
                      </motion.span>
                      {showSettled ? t('hideSettled') : t('showSettled', { n: settled.length })}
                    </button>
                    <AnimatePresence initial={false}>
                      {showSettled ? (
                        <motion.div key="settled" initial={{ height: 0, opacity: 0 }} animate={{ height: 'auto', opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={spring} className="overflow-hidden">
                          <GroupList groups={settled} />
                        </motion.div>
                      ) : null}
                    </AnimatePresence>
                  </div>
                ) : null}
              </section>
            </>
          )}
        </>
      )}
      <PullToRefresh onRefresh={() => Promise.all([load(), api.notifications().then(setInbox).catch(() => {})])} />
      <NewGroupSheet open={creating} onClose={() => setCreating(false)} onCreated={(g) => cacheGroup(g).finally(() => router.push(`/g/${g.id}`))} />
      <Notices open={showInbox} onClose={() => setShowInbox(false)} items={inbox} />
    </Screen>
  );
}

export default function Page() {
  const { ready, me } = useSession();
  if (!ready) return <div className="grid min-h-dvh place-items-center"><Coin size={56} /></div>;
  return me ? (
    <Suspense>
      <Home />
    </Suspense>
  ) : (
    <Welcome />
  );
}
