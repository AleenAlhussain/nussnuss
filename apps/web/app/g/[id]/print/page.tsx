'use client';

import { expenseInGroupCurrency } from '@nussnuss/core';
import { useParams, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Coin } from '@/components/coin';
import { groupHasPlus } from '@/components/expense-sheet';
import { Button } from '@/components/ui';
import { api, type GroupDetail } from '@/lib/api';
import { money } from '@/lib/format';
import { catKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';

/** A printable summary of a group (Plus): every expense, each balance, and the transfers to settle. */
export default function PrintGroup() {
  const { id } = useParams<{ id: string }>();
  const { ready, me, t, prefs, plan } = useSession();
  const router = useRouter();
  const [g, setG] = useState<GroupDetail | null>(null);
  useEffect(() => {
    if (ready && !me) router.replace('/');
    if (ready && me) api.group(id).then(setG).catch(() => router.replace(`/g/${id}`));
  }, [ready, me, id, router]);
  useEffect(() => {
    if (g && groupHasPlus(g, plan)) {
      const h = setTimeout(() => window.print(), 400);
      return () => clearTimeout(h);
    }
  }, [g, plan]);
  if (!g) return null;
  const lang = prefs.lang;
  const name = (mid: string) => g.members.find((m) => m.id === mid)?.name ?? '?';
  const date = (iso: string) => new Date(iso).toLocaleDateString(lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  return (
    <main className="mx-auto flex max-w-3xl flex-col gap-8 bg-bg px-6 py-10 text-text print:bg-white print:text-black" data-testid="print">
      <div className="no-print flex gap-2">
        <Button variant="secondary" onClick={() => router.back()}>
          {t('back')}
        </Button>
        <Button onClick={() => window.print()}>{t('print')}</Button>
      </div>
      <header className="flex items-center gap-4">
        <Coin size={44} />
        <div>
          <h1 className="t-title-1">
            {g.emoji} {g.name}
          </h1>
          <p className="t-subhead text-text-2 print:text-black">
            {t('total')} · {money(g.total, g.currency, lang)} · {t('members', { n: g.members.length })}
          </p>
        </div>
      </header>
      <section className="flex flex-col gap-2">
        <h2 className="t-headline">{t('settleUp')}</h2>
        {g.transfers.length ? (
          <ul className="flex flex-col gap-1">
            {g.transfers.map((tr) => (
              <li key={`${tr.from}-${tr.to}`} className="flex justify-between border-b border-separator py-1 t-body">
                <span>
                  {name(tr.from)} {t('pays')} {name(tr.to)}
                </span>
                <span className="num font-semibold">{money(tr.amount, g.currency, lang)}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="t-body">{t('allSettled')}</p>
        )}
      </section>
      <section className="flex flex-col gap-2">
        <h2 className="t-headline">{t('expenses')}</h2>
        <table className="w-full border-collapse t-footnote">
          <thead>
            <tr className="border-b-2 border-separator text-start">
              <th className="py-1 text-start" aria-label="Date" />
              <th className="py-1 text-start">{t('whatFor')}</th>
              <th className="py-1 text-start">{t('paidBy')}</th>
              <th className="py-1 text-start">{t('category')}</th>
              <th className="py-1 text-end">{t('amount')}</th>
            </tr>
          </thead>
          <tbody>
            {g.expenses.map((e) => (
              <tr key={e.id} className="border-b border-separator">
                <td className="py-1 pe-2 num whitespace-nowrap">{date(e.spentAt)}</td>
                <td className="py-1 pe-2">{e.title}</td>
                <td className="py-1 pe-2">{name(e.paidBy)}</td>
                <td className="py-1 pe-2">{t(catKey(e.category))}</td>
                <td className="py-1 text-end num whitespace-nowrap">
                  {money(expenseInGroupCurrency(e, g.currency), g.currency, lang)}
                  {e.currency !== g.currency ? ` (${money(e.amount, e.currency, lang)})` : ''}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
      <section className="flex flex-col gap-2">
        <h2 className="t-headline">{t('people')}</h2>
        <ul className="flex flex-col gap-1">
          {g.members.map((m) => {
            const b = g.balances[m.id] ?? 0;
            return (
              <li key={m.id} className="flex justify-between border-b border-separator py-1 t-body">
                <span>{m.name}</span>
                <span className="num">{b > 0 ? t('getsBack', { amount: money(b, g.currency, lang) }) : b < 0 ? t('owes', { amount: money(-b, g.currency, lang) }) : t('even')}</span>
              </li>
            );
          })}
        </ul>
      </section>
      <footer className="t-footnote text-text-2 print:text-black">{t('summaryMade')}</footer>
    </main>
  );
}
