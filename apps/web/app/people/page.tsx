'use client';

import { CaretRight } from '@phosphor-icons/react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Screen } from '@/components/glass';
import { Avatar } from '@/components/identity';
import { Empty } from '@/components/ui';
import { api, type Overview } from '@/lib/api';
import { money } from '@/lib/format';
import { kvGet } from '@/lib/kv';
import { useSession } from '@/lib/session';

/** Everyone you split with, the ones you owe or who owe you first. */
export default function PeoplePage() {
  const { ready, me, t, prefs } = useSession();
  const router = useRouter();
  const [o, setO] = useState<Overview | null>(null);
  useEffect(() => {
    if (ready && !me) router.replace('/');
    if (!ready || !me) return;
    kvGet<Overview>('overview').then((c) => c && setO((x) => x ?? c));
    api.overview().then(setO).catch(() => {});
  }, [ready, me, router]);
  return (
    <Screen title={t('people')} back="/" testId="people">
      {o && !o.people.length ? <Empty title={t('noPeople')} /> : null}
      {o?.people.length ? (
        <ul className="overflow-hidden rounded-card bg-surface">
          {o.people.map((p) => (
            <li key={p.key} className="border-b border-separator/60 last:border-0">
              <Link href={`/p/${p.key}`} className="focus-ring flex min-h-16 items-center gap-3 px-4 py-2" data-testid="people-row">
                <Avatar name={p.name} avatar={p.avatar} size={44} />
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate t-headline text-text">{p.name}</span>
                  <span className="t-footnote text-text-2">{p.groups === 1 ? t('acrossOne') : t('acrossN', { n: p.groups })}</span>
                </span>
                <span className="flex flex-col items-end">
                  {p.balances.length ? (
                    p.balances.map((b) => (
                      <span key={b.currency} className={`t-subhead font-semibold num whitespace-nowrap ${b.amount > 0 ? 'text-success' : 'text-text'}`}>
                        {b.amount > 0 ? '+' : '−'}
                        {money(Math.abs(b.amount), b.currency, prefs.lang)}
                      </span>
                    ))
                  ) : (
                    <span className="t-subhead text-text-2">{t('personEven')}</span>
                  )}
                </span>
                <CaretRight size={18} className="text-text-3 rtl:-scale-x-100" aria-hidden />
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
    </Screen>
  );
}
