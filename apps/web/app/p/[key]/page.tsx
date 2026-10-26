'use client';

import { BellRinging, CaretRight, HandCoins } from '@phosphor-icons/react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { Sheet, Screen } from '@/components/glass';
import { Avatar, CategoryTile, CoverTile, FitLine } from '@/components/identity';
import { shareText } from '@/components/settle';
import { useToast } from '@/components/toast';
import { Button, Empty } from '@/components/ui';
import { api, ApiError, type PersonDetail } from '@/lib/api';
import { haptic } from '@/lib/feel';
import { money } from '@/lib/format';
import { useSession } from '@/lib/session';
import { play } from '@/lib/sound';
import { timeEnd, timeStart } from '@/lib/timing';

/** One person across every group you share: what you owe each other, settle it all at once, what you split. */
export default function PersonPage() {
  const { key } = useParams<{ key: string }>();
  const { ready, me, t, prefs } = useSession();
  const router = useRouter();
  const toast = useToast();
  const [p, setP] = useState<PersonDetail | null>(null);
  const [missing, setMissing] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const lang = prefs.lang;

  const load = useCallback(
    () =>
      api
        .person(key)
        .then(setP)
        .catch((e) => {
          if (e instanceof ApiError && e.status === 404) setMissing(true);
        }),
    [key],
  );
  useEffect(() => {
    if (ready && !me) router.replace('/');
    if (ready && me) {
      timeStart('settle');
      load();
    }
  }, [ready, me, load, router]);

  if (missing) {
    return (
      <Screen title="" back="/" testId="person-screen">
        <Empty title={t('personNotFound')} />
      </Screen>
    );
  }
  if (!p) {
    return (
      <Screen title="" back="/" testId="person-loading">
        <div className="flex flex-col items-center gap-3 py-6" aria-busy="true">
          <div className="shimmer h-20 w-20 rounded-full" />
          <div className="shimmer h-5 w-32 rounded" />
          <div className="shimmer h-12 w-48 rounded-control" />
        </div>
      </Screen>
    );
  }

  const [first, ...rest] = p.balances;
  const open = p.groups.filter((g) => g.amount !== 0);
  const settle = async () => {
    setBusy(true);
    try {
      const r = await api.settleAll(p.key);
      setP(r.person);
      setConfirm(false);
      haptic('success');
      play('chime', prefs.sounds);
      timeEnd('settle', true);
      toast(t('settledWith', { name: p.name }), {
        label: t('undo'),
        run: () =>
          api
            .undoPayments(r.payments.map((x) => x.id))
            .then(load)
            .catch(() => toast(t('error'))),
      }, { done: true });
    } catch {
      toast(t('error'));
    } finally {
      setBusy(false);
    }
  };
  const owesMe = p.balances.filter((b) => b.amount > 0);
  const remind = () => {
    haptic('light');
    const amounts = owesMe.map((b) => money(b.amount, b.currency, lang)).join(lang === 'ar' ? ' و' : ' and ');
    shareText(t('remindAllMessage', { name: p.name, amounts }));
  };

  return (
    <Screen title={p.name} back="/" testId="person-screen">
      <section className="flex flex-col items-center gap-2 text-center" data-testid="person-hero">
        <Avatar name={p.name} avatar={p.avatar} size={88} />
        <span className="t-subhead font-medium text-text-2">
          {!first ? t('personEvenTitle', { name: p.name }) : first.amount > 0 ? t('personOwesYou', { name: p.name }) : t('personYouOwe', { name: p.name })}
        </span>
        {first ? (
          <div className="w-full min-w-0">
            <FitLine className={`t-amount-hero ${first.amount > 0 ? 'text-success' : 'text-text'}`} testId="person-amount" min={22}>
              {money(Math.abs(first.amount), first.currency, lang)}
            </FitLine>
          </div>
        ) : null}
        {rest.map((m) => (
          <span key={m.currency} className="t-subhead text-text-2 num whitespace-nowrap">
            {t('andAmount', { amount: `${m.amount > 0 ? '+' : '−'}${money(Math.abs(m.amount), m.currency, lang)}` })}
          </span>
        ))}
        {open.length ? (
          <div className="mt-2 flex w-full max-w-sm gap-2">
            <Button className="flex-1" icon={<HandCoins size={20} />} onClick={() => setConfirm(true)} data-testid="settle-everything">
              {t('settleEverything')}
            </Button>
            {owesMe.length ? (
              <Button variant="secondary" icon={<BellRinging size={20} />} onClick={remind} data-testid="remind-person">
                {t('remind')}
              </Button>
            ) : null}
          </div>
        ) : null}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="t-subhead font-semibold text-text-2 ps-4">{t('groupsShared')}</h2>
        <ul className="overflow-hidden rounded-card bg-surface">
          {p.groups.map((g) => (
            <li key={g.id} className="border-b border-separator/60 last:border-0">
              <Link href={`/g/${g.id}`} className="focus-ring flex min-h-16 items-center gap-3 px-4 py-2" data-testid="person-group">
                <CoverTile cover={g.cover} emoji={g.emoji} size={40} />
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="line-clamp-2 t-headline text-text">{g.name}</span>
                  <span className="t-footnote text-text-2">{g.amount > 0 ? t('owesYouX', { amount: '' }).trim() : g.amount < 0 ? t('youOweX', { amount: '' }).trim() : t('personEven')}</span>
                </span>
                {g.amount ? (
                  <span className={`t-headline num whitespace-nowrap ${g.amount > 0 ? 'text-success' : 'text-text'}`}>{money(Math.abs(g.amount), g.currency, lang)}</span>
                ) : null}
                <CaretRight size={18} className="text-text-3 rtl:-scale-x-100" aria-hidden />
              </Link>
            </li>
          ))}
        </ul>
      </section>

      {p.shared.length ? (
        <section className="flex flex-col gap-2">
          <h2 className="t-subhead font-semibold text-text-2 ps-4">{t('betweenYou')}</h2>
          <ul className="overflow-hidden rounded-card bg-surface" data-testid="between-you">
            {p.shared.map((s) => (
              <li key={s.id} className="flex min-h-16 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
                <CategoryTile category={s.category} size={40} />
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate t-headline text-text">{s.title}</span>
                  <span className="truncate t-footnote text-text-2">
                    {s.paidByMe ? t('youPaidOn', { date: new Date(s.at).toLocaleDateString(lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'short' }) }) : t('namePaidOn', { name: p.name, date: new Date(s.at).toLocaleDateString(lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'short' }) })}{' '}
                    · {s.group.name}
                  </span>
                </span>
                <span className={`t-subhead font-semibold num whitespace-nowrap ${s.amount > 0 ? 'text-success' : 'text-text'}`}>
                  {s.amount > 0 ? '+' : '−'}
                  {money(Math.abs(s.amount), s.currency, lang)}
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <Sheet open={confirm} onClose={() => setConfirm(false)} title={t('settleEverything')} testId="settle-everything-sheet">
        <div className="flex flex-col gap-4 pb-2">
          <p className="t-subhead text-text-2">{t('settleEverythingBody', { name: p.name })}</p>
          <ul className="overflow-hidden rounded-card bg-surface">
            {open.map((g) => (
              <li key={g.id} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
                <CoverTile cover={g.cover} emoji={g.emoji} size={36} />
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate t-body text-text">{g.name}</span>
                  <span className="t-footnote text-text-2">{g.amount > 0 ? t('paysYou', { name: p.name }) : t('youPayTo', { name: p.name })}</span>
                </span>
                <span className="t-headline num whitespace-nowrap text-text">{money(Math.abs(g.amount), g.currency, lang)}</span>
              </li>
            ))}
          </ul>
          <Button block onClick={settle} disabled={busy} data-testid="confirm-settle-everything">
            {t('settleConfirm')}
          </Button>
          <Button block variant="plain" onClick={() => setConfirm(false)}>
            {t('cancel')}
          </Button>
        </div>
      </Sheet>
    </Screen>
  );
}
