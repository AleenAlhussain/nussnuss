'use client';

import { Bell, UsersThree } from '@phosphor-icons/react';
import { motion } from 'motion/react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { SignInSheet } from '@/components/account';
import { Coin } from '@/components/coin';
import { BarButton, Screen, Sheet } from '@/components/glass';
import { NewGroupSheet } from '@/components/group-sheets';
import { Button, Empty, Field, Segmented } from '@/components/ui';
import { api, type GroupSummary, type Notice } from '@/lib/api';
import { spring } from '@/lib/feel';
import { money } from '@/lib/format';
import type { Lang } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { cachedGroups, cacheGroups } from '@/lib/sync';

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
    <div className="flex flex-col gap-3" aria-busy="true">
      {[0, 1, 2].map((i) => (
        <div key={i} className="flex items-center gap-4 rounded-card bg-surface p-4">
          <div className="h-14 w-14 animate-pulse rounded-row bg-surface-2" />
          <div className="flex flex-1 flex-col gap-2">
            <div className="h-4 w-1/2 animate-pulse rounded bg-surface-2" />
            <div className="h-3 w-2/3 animate-pulse rounded bg-surface-2" />
          </div>
          <div className="h-5 w-16 animate-pulse rounded bg-surface-2" />
        </div>
      ))}
    </div>
  );
}

function Groups() {
  const { t, prefs, firstRun, endFirstRun } = useSession();
  const router = useRouter();
  const [groups, setGroups] = useState<GroupSummary[] | null>(null);
  const [creating, setCreating] = useState(false);
  const [inbox, setInbox] = useState<Notice[]>([]);
  const [showInbox, setShowInbox] = useState(false);
  const load = useCallback(
    () =>
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
        <ul className="flex flex-col gap-3">
          {groups.map((g) => (
            <motion.li key={g.id} layout transition={spring} className="list-none">
              <Link href={`/g/${g.id}`} className="focus-ring flex items-center gap-4 rounded-card bg-surface p-4 transition-transform active:scale-[0.99]" data-testid="group-card">
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
      )}
      <NewGroupSheet open={creating} onClose={() => setCreating(false)} onCreated={(g) => router.push(`/g/${g.id}`)} />
      <Notices open={showInbox} onClose={() => setShowInbox(false)} items={inbox} />
    </Screen>
  );
}

export default function Home() {
  const { ready, me } = useSession();
  if (!ready) return <div className="grid min-h-dvh place-items-center"><Coin size={56} /></div>;
  return me ? <Groups /> : <Welcome />;
}
