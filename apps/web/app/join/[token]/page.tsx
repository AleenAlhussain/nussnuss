'use client';

import { Check, LinkBreak } from '@phosphor-icons/react';
import { useParams, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Coin } from '@/components/coin';
import { Avatar, CoverTile } from '@/components/identity';
import { Button, cx, Empty, ErrorText, Field } from '@/components/ui';
import { api, type InvitePreview } from '@/lib/api';
import { haptic } from '@/lib/feel';
import { useSession } from '@/lib/session';
import { cacheGroup } from '@/lib/sync';

/** What a friend sees from a link: the group, who invited them, "which one are you?". No app, no sign-up form. */
export default function JoinPage() {
  const { token } = useParams<{ token: string }>();
  const { ready, me, t, start } = useSession();
  const router = useRouter();
  const [preview, setPreview] = useState<InvitePreview | null>(null);
  const [bad, setBad] = useState(false);
  const [pick, setPick] = useState<string | 'new' | null>(null);
  const [newName, setNewName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.preview(token).then(setPreview).catch(() => setBad(true));
  }, [token]);

  const join = async () => {
    if (!preview || !pick) return;
    const chosen = pick === 'new' ? newName.trim() : preview.members.find((m) => m.id === pick)?.name ?? '';
    if (!chosen) return setError(t('yourNameHint'));
    setBusy(true);
    setError(null);
    try {
      if (!me) await start(chosen);
      const d = await api.join(token, pick === 'new' ? { name: chosen } : { memberId: pick });
      await cacheGroup(d);
      haptic('success');
      router.replace(`/g/${d.id}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  };

  if (bad) return <Empty icon={<LinkBreak size={36} />} title={t('badLink')} body="" />;
  if (!ready || !preview) return <div className="grid min-h-dvh place-items-center"><Coin size={56} /></div>;

  const open = preview.members.filter((m) => !m.claimed);
  const meta = t('joinMeta', { n: preview.members.length, currency: preview.group.currency });
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col gap-7 px-5" style={{ paddingTop: 'calc(env(safe-area-inset-top, 0px) + 32px)', paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 24px)' }} data-testid="join">
      <div className="flex flex-col items-center gap-3 text-center">
        <CoverTile cover={preview.group.cover} emoji={preview.group.emoji} size={80} testId="join-cover" />
        <h1 className="t-title-1 text-text">{t('joinGroupX', { name: preview.group.name })}</h1>
        <p className="flex items-center gap-2 t-subhead text-text-2" data-testid="join-meta">
          {preview.invitedBy ? (
            <>
              <Avatar name={preview.invitedBy.name} avatar={preview.invitedBy.avatar} size={22} />
              {t('invitedYou', { name: preview.invitedBy.name })} ·{' '}
            </>
          ) : null}
          {meta}
        </p>
      </div>

      <fieldset className="flex flex-col gap-2">
        <legend className="mb-2 t-headline text-text">{t('joinWho')}</legend>
        <div role="radiogroup" aria-label={t('joinWho')} className="flex flex-col gap-2">
          {preview.members.map((m) => {
            const on = pick === m.id;
            return (
              <label
                key={m.id}
                className={cx(
                  'relative flex min-h-16 items-center gap-3 rounded-card px-4 py-2 transition-colors has-[input:focus-visible]:outline-3 has-[input:focus-visible]:outline-offset-2 has-[input:focus-visible]:outline-[var(--nn-focus)] has-[input:focus-visible]:outline',
                  m.claimed ? 'bg-surface opacity-60' : on ? 'cursor-pointer bg-accent-soft ring-2 ring-accent' : 'cursor-pointer bg-surface ring-1 ring-edge',
                )}
              >
                <input type="radio" name="who" value={m.id} disabled={m.claimed} checked={on} onChange={() => setPick(m.id)} className="absolute inset-0 h-full w-full cursor-pointer opacity-0 disabled:cursor-default" data-testid="who" />
                <Avatar name={m.name} avatar={m.avatar} size={44} />
                <span className="flex-1 t-headline text-text">{m.name}</span>
                {m.claimed ? <span className="t-footnote text-text-2">{t('alreadyJoined')}</span> : on ? <Check size={22} weight="bold" className="text-accent" aria-hidden /> : null}
              </label>
            );
          })}
          <label className={cx('relative flex min-h-14 cursor-pointer items-center gap-3 rounded-card px-4 has-[input:focus-visible]:outline has-[input:focus-visible]:outline-3 has-[input:focus-visible]:outline-offset-2 has-[input:focus-visible]:outline-[var(--nn-focus)]', pick === 'new' ? 'bg-accent-soft ring-2 ring-accent' : 'bg-surface ring-1 ring-edge')}>
            <input type="radio" name="who" value="new" checked={pick === 'new'} onChange={() => setPick('new')} className="absolute inset-0 h-full w-full cursor-pointer opacity-0" data-testid="who-new" />
            <span className="t-body font-semibold text-accent">{t('someoneElse')}</span>
          </label>
        </div>
        {pick === 'new' ? <Field label={t('joinNewName')} value={newName} maxLength={40} onChange={(e) => setNewName(e.target.value)} data-testid="join-name" autoFocus /> : null}
      </fieldset>

      <div className="mt-auto flex flex-col gap-2">
        <ErrorText>{error}</ErrorText>
        <Button block disabled={!pick || busy || (pick !== 'new' && !open.some((m) => m.id === pick))} onClick={join} data-testid="join-btn">
          {pick && pick !== 'new' ? t('joinAs', { name: preview.members.find((m) => m.id === pick)?.name ?? '' }) : t('joinBtn')}
        </Button>
        <p className="text-center t-footnote text-text-2">
          {t('worksInBrowser')} {t('getAppLine')}
        </p>
      </div>
    </main>
  );
}
