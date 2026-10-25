'use client';

import { LinkBreak } from '@phosphor-icons/react';
import { useParams, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Coin } from '@/components/coin';
import { Avatar, Button, Empty, ErrorText, Field } from '@/components/ui';
import { api, type InvitePreview } from '@/lib/api';
import { useSession } from '@/lib/session';
import { cacheGroup } from '@/lib/sync';

/** What a friend sees from a WhatsApp link: the group, the names, "which one are you?". No app, no sign-up form. */
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
      router.replace(`/g/${d.id}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  };

  if (bad) return <Empty icon={<LinkBreak size={36} />} title={t('badLink')} body="" />;
  if (!ready || !preview) return <div className="grid min-h-dvh place-items-center"><Coin size={56} /></div>;

  const open = preview.members.filter((m) => !m.claimed);
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col gap-8 px-5" style={{ paddingTop: 'calc(env(safe-area-inset-top, 0px) + 32px)', paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 24px)' }} data-testid="join">
      <div className="flex flex-col items-center gap-3 text-center">
        <span className="grid h-20 w-20 place-items-center rounded-card bg-surface text-5xl" aria-hidden>
          {preview.group.emoji}
        </span>
        <p className="t-subhead text-text-2">{t('joinTitle')}</p>
        <h1 className="t-title-1 text-text">{preview.group.name}</h1>
      </div>

      <fieldset className="flex flex-col gap-2">
        <legend className="mb-2 t-headline text-text">{t('joinWho')}</legend>
        <div className="overflow-hidden rounded-card bg-surface">
          {preview.members.map((m, i) => (
            <label key={m.id} className={`flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 last:border-0 ${m.claimed ? 'opacity-50' : 'cursor-pointer'}`}>
              <input type="radio" name="who" value={m.id} disabled={m.claimed} checked={pick === m.id} onChange={() => setPick(m.id)} className="h-5 w-5 accent-[var(--nn-accent)]" data-testid="who" />
              <Avatar name={m.name} index={i} size={32} />
              <span className="flex-1 t-body text-text">{m.name}</span>
              {m.claimed ? <span className="t-footnote text-text-2">{t('joinTaken')}</span> : null}
            </label>
          ))}
          <label className="flex min-h-14 cursor-pointer items-center gap-3 px-4">
            <input type="radio" name="who" value="new" checked={pick === 'new'} onChange={() => setPick('new')} className="h-5 w-5 accent-[var(--nn-accent)]" data-testid="who-new" />
            <span className="t-body text-accent">{t('joinNew')}</span>
          </label>
        </div>
        {pick === 'new' ? <Field label={t('joinNewName')} value={newName} maxLength={40} onChange={(e) => setNewName(e.target.value)} data-testid="join-name" autoFocus /> : null}
      </fieldset>

      <div className="mt-auto flex flex-col gap-2">
        <ErrorText>{error}</ErrorText>
        <Button block disabled={!pick || busy || (pick !== 'new' && !open.some((m) => m.id === pick))} onClick={join} data-testid="join-btn">
          {pick && pick !== 'new' ? t('joinAs', { name: preview.members.find((m) => m.id === pick)?.name ?? '' }) : t('joinBtn')}
        </Button>
      </div>
    </main>
  );
}
