'use client';

import { UsersThree } from '@phosphor-icons/react';
import { motion } from 'motion/react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { Coin } from '@/components/coin';
import { Screen } from '@/components/glass';
import { NewGroupSheet } from '@/components/group-sheets';
import { Button, Empty, Field, Segmented } from '@/components/ui';
import { api, type GroupSummary } from '@/lib/api';
import { spring } from '@/lib/feel';
import { money } from '@/lib/format';
import type { Lang } from '@/lib/i18n';
import { useSession } from '@/lib/session';

function Welcome() {
  const { t, prefs, setPrefs, start } = useSession();
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
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
      </form>
    </main>
  );
}

function Groups() {
  const { t, prefs } = useSession();
  const router = useRouter();
  const [groups, setGroups] = useState<GroupSummary[] | null>(null);
  const [creating, setCreating] = useState(false);
  const load = useCallback(() => api.groups().then(setGroups).catch(() => setGroups((g) => g ?? [])), []);
  useEffect(() => {
    load();
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [load]);

  return (
    <Screen title={t('groups')} onAdd={() => setCreating(true)} addLabel={t('newGroup')} testId="groups">
      {groups === null ? (
        <div className="flex flex-col gap-3" aria-busy>
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-20 animate-pulse rounded-card bg-surface" />
          ))}
        </div>
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
    </Screen>
  );
}

export default function Home() {
  const { ready, me } = useSession();
  if (!ready) return <div className="grid min-h-dvh place-items-center"><Coin size={56} /></div>;
  return me ? <Groups /> : <Welcome />;
}
