'use client';

import { Bell, MagnifyingGlass, UsersThree, X } from '@phosphor-icons/react';
import { expenseInGroupCurrency } from '@nussnuss/core';
import { motion } from 'motion/react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { SignInSheet } from '@/components/account';
import { Coin } from '@/components/coin';
import { BarButton, Screen, Sheet } from '@/components/glass';
import { NewGroupSheet } from '@/components/group-sheets';
import { PullToRefresh } from '@/components/pull';
import { Button, Empty, Field, Segmented } from '@/components/ui';
import { api, type GroupDetail, type GroupSummary, type Notice } from '@/lib/api';
import { spring } from '@/lib/feel';
import { money } from '@/lib/format';
import type { Lang } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { cacheGroup, cachedGroup, cachedGroups, cacheGroups } from '@/lib/sync';
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
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-between gap-10 px-6" style={{ paddingTop: 'calc(env(safe-area-inset-top, 0px) + 24px)', paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 24px)' }} data-testid="welcome">
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
      <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={spring} className="flex flex-col items-start gap-6">
        <Coin size={76} label={t('appName')} />
        <h1 className="t-large-title text-text" style={{ fontSize: 'clamp(2.25rem, 9vw, 3rem)' }}>
          {t('welcomeTitle')}
        </h1>
        <p className="t-body text-text-2">{t('welcomeBody')}</p>
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
                <span className="grid h-11 w-11 shrink-0 place-items-center rounded-row bg-surface-2 text-2xl" aria-hidden>
                  {n.data.emoji ?? '🔔'}
                </span>
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

function GroupsSkeleton() {
  return (
    <div className="flex flex-col gap-3" aria-busy="true" data-testid="groups-loading">
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

/**
 * Search across groups (name and people) and the expenses of every group saved on this device. The field
 * floats on glass and pins under the top bar as the list scrolls.
 */
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

function GroupList({ groups }: { groups: GroupSummary[] }) {
  const { t, prefs } = useSession();
  const router = useRouter();
  return (
    <ul className="flex flex-col gap-3">
      {groups.map((g, i) => (
        <motion.li
          key={g.id}
          layout
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          // Rows arrive one after another, 30 ms apart, all within 400 ms.
          transition={{ ...spring, delay: Math.min(i * 0.03, 0.12) }}
          className="list-none"
        >
          <Link
            href={`/g/${g.id}`}
            onClick={(e) => {
              if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
              e.preventDefault();
              openWith(router, `/g/${g.id}`, e.currentTarget, 'group-card');
            }}
            className="press focus-ring flex items-center gap-4 rounded-card bg-surface p-4"
            data-testid="group-card"
          >
            <span className="grid h-14 w-14 shrink-0 place-items-center rounded-row bg-surface-2 text-3xl" aria-hidden>
              {g.emoji}
            </span>
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="truncate t-headline text-text">{g.name}</span>
              <span className="truncate t-footnote text-text-2">{g.memberNames.join(prefs.lang === 'ar' ? '، ' : ', ')}</span>
            </span>
            <span className="flex flex-col items-end text-end">
              {g.myBalance === 0 ? (
                <span className="t-subhead font-semibold text-text-2">{g.total ? t('allSettled') : money(0, g.currency, prefs.lang)}</span>
              ) : (
                <>
                  <span className="t-caption text-text-2">{g.myBalance > 0 ? t('youAreOwed') : t('youOwe')}</span>
                  <span className={`t-headline num ${g.myBalance > 0 ? 'text-success' : 'text-danger'}`}>{money(Math.abs(g.myBalance), g.currency, prefs.lang)}</span>
                </>
              )}
            </span>
          </Link>
        </motion.li>
      ))}
    </ul>
  );
}

function Groups() {
  const { t, prefs, firstRun, endFirstRun } = useSession();
  const router = useRouter();
  const [groups, setGroups] = useState<GroupSummary[] | null>(null);
  const [creating, setCreating] = useState(false);
  const [inbox, setInbox] = useState<Notice[]>([]);
  const [showInbox, setShowInbox] = useState(false);
  const [q, setQ] = useState('');
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
      api
        .groups()
        .then((g) => {
          setGroups(g);
          cacheGroups(g);
        })
        .catch(() => setGroups((g) => g ?? [])),
    [],
  );
  useEffect(() => {
    cachedGroups().then((c) => {
      if (c) setGroups((g) => g ?? c);
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
  // First run: straight from the welcome to making the first group.
  useEffect(() => {
    if (firstRun) {
      setCreating(true);
      endFirstRun();
    }
  }, [firstRun, endFirstRun]);
  const unread = inbox.filter((n) => !n.read).length;

  return (
    <Screen
      title={t('groups')}
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
        <GroupsSkeleton />
      ) : groups.length === 0 ? (
        <Empty icon={<UsersThree size={36} />} title={t('noGroupsTitle')} body={t('noGroupsBody')}>
          <Button block onClick={() => setCreating(true)} data-testid="new-group">
            {t('newGroup')}
          </Button>
        </Empty>
      ) : (
        <>
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
                    className="tap press focus-ring inline-flex h-11 items-center gap-2 rounded-full bg-surface px-4 t-subhead font-medium text-text ring-1 ring-separator"
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
                          <span className="grid h-10 w-10 shrink-0 place-items-center rounded-row bg-surface-2 text-xl" aria-hidden>
                            {d.emoji}
                          </span>
                          <span className="flex min-w-0 flex-1 flex-col">
                            <span className="truncate t-headline text-text">{e.title}</span>
                            <span className="truncate t-footnote text-text-2">{d.name}</span>
                          </span>
                          <span className="t-subhead text-text num">{money(expenseInGroupCurrency(e, d.currency), d.currency, prefs.lang)}</span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                </section>
              ) : null}
              {!found.groups.length && !found.expenses.length ? <p className="py-8 text-center t-subhead text-text-2">{t('noResults', { q: q.trim() })}</p> : null}
            </div>
          ) : (
            <GroupList groups={groups} />
          )}
        </>
      )}
      <PullToRefresh onRefresh={() => Promise.all([load(), api.notifications().then(setInbox).catch(() => {})])} />
      <NewGroupSheet open={creating} onClose={() => setCreating(false)} onCreated={(g) => cacheGroup(g).finally(() => router.push(`/g/${g.id}`))} />
      <Notices open={showInbox} onClose={() => setShowInbox(false)} items={inbox} />
    </Screen>
  );
}

export default function Home() {
  const { ready, me } = useSession();
  if (!ready) return <div className="grid min-h-dvh place-items-center"><Coin size={56} /></div>;
  return me ? <Groups /> : <Welcome />;
}
