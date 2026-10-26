'use client';

import { Check, Palette, Receipt, Repeat } from '@phosphor-icons/react';
import { createContext, useCallback, useContext, useMemo, useState, type ComponentType, type ReactNode } from 'react';
import { api } from '@/lib/api';
import { haptic } from '@/lib/feel';
import type { TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { Coin } from './coin';
import { Sheet } from './glass';
import { useToast } from './toast';
import { Button, cx } from './ui';

interface Opts {
  /** Opened from a group: offers the Trip Pass for that group too. */
  groupId?: string;
  onDone?: () => void;
}
const Ctx = createContext<{ open: (o?: Opts) => void } | null>(null);

export function usePaywall() {
  const c = useContext(Ctx);
  if (!c) throw new Error('PaywallProvider missing');
  return c;
}

/** Three benefits, not seven features: what Plus changes for someone who splits a lot. */
const BENEFITS: [ComponentType<{ size?: number; weight?: 'duotone' }>, TKey, TKey][] = [
  [Repeat, 'plusB1T', 'plusB1B'],
  [Receipt, 'plusB2T', 'plusB2B'],
  [Palette, 'plusB3T', 'plusB3B'],
];

/** Store prices, when the operator has set them for the web (the phone apps show the store's own prices). */
const PRICES: Partial<Record<'monthly' | 'yearly' | 'trip', string>> = (() => {
  try {
    return JSON.parse(process.env.NEXT_PUBLIC_PLUS_PRICES ?? '{}');
  } catch {
    return {};
  }
})();

type Product = 'nussnuss.plus.yearly' | 'nussnuss.plus.monthly' | 'nussnuss.trip_pass';
const DEV = process.env.NEXT_PUBLIC_DEV_PURCHASES === 'true';

export const shortDate = (iso: string, lang: string) =>
  new Date(iso).toLocaleDateString(lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

/**
 * The Plus sheet. On the web it explains what Plus adds and that it is bought in the phone app
 * (App Store and Google Play handle payment); test builds can switch it on for review.
 */
export function PaywallProvider({ children }: { children: ReactNode }) {
  const { t, prefs, plan, refreshPlan } = useSession();
  const toast = useToast();
  const [opts, setOpts] = useState<Opts | null>(null);
  const [pick, setPick] = useState<Product>('nussnuss.plus.yearly');
  const [busy, setBusy] = useState(false);
  const open = useCallback((o: Opts = {}) => {
    setPick('nussnuss.plus.yearly');
    setOpts(o);
  }, []);
  const value = useMemo(() => ({ open }), [open]);
  const pass = opts?.groupId ? plan?.tripPasses.find((p) => p.groupId === opts.groupId) : undefined;

  const choices: { id: Product; title: string; price?: string; body?: string; badge?: string }[] = [
    { id: 'nussnuss.plus.yearly', title: t('planYearly'), price: PRICES.yearly ? t('perYear', { price: PRICES.yearly }) : undefined, badge: t('planYearlySave') },
    { id: 'nussnuss.plus.monthly', title: t('planMonthly'), price: PRICES.monthly ? t('perMonth', { price: PRICES.monthly }) : undefined },
    ...(opts?.groupId ? [{ id: 'nussnuss.trip_pass' as Product, title: t('tripPass'), price: PRICES.trip, body: t('tripPassBody') }] : []),
  ];

  const devBuy = async () => {
    setBusy(true);
    try {
      await api.devPurchase(pick, pick === 'nussnuss.trip_pass' ? opts?.groupId : undefined);
      await refreshPlan();
      haptic('success');
      toast(t('plusThanks'));
      opts?.onDone?.();
      setOpts(null);
    } catch (e) {
      toast((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Ctx.Provider value={value}>
      {children}
      <Sheet open={!!opts} onClose={() => setOpts(null)} title={t('plus')} testId="paywall">
        <div className="flex flex-col gap-5 pb-2">
          <div className="flex flex-col items-center gap-2 pt-1 text-center">
            <Coin size={56} />
            <p className="max-w-xs t-subhead text-text-2">{t('plusFree')}</p>
            {plan?.plus && plan.plusUntil ? (
              <p className="rounded-full bg-success-soft px-3 py-1 t-footnote font-semibold text-success" data-testid="plus-on">
                {t('plusOnUntil', { date: shortDate(plan.plusUntil, prefs.lang) })}
              </p>
            ) : pass ? (
              <p className="rounded-full bg-success-soft px-3 py-1 t-footnote font-semibold text-success">{t('tripOnUntil', { date: shortDate(pass.until, prefs.lang) })}</p>
            ) : null}
          </div>
          <ul className="flex flex-col gap-1 rounded-card bg-surface p-2" data-testid="plus-benefits">
            {BENEFITS.map(([Icon, title, body]) => (
              <li key={title} className="flex items-start gap-3 px-2 py-2">
                <span className="grid h-9 w-9 shrink-0 place-items-center rounded-row bg-accent-soft text-on-accent-soft" aria-hidden>
                  <Icon size={20} weight="duotone" />
                </span>
                <span className="flex min-w-0 flex-col">
                  <span className="t-headline text-text">{t(title)}</span>
                  <span className="t-footnote text-text-2">{t(body)}</span>
                </span>
              </li>
            ))}
          </ul>
          <div role="radiogroup" aria-label={t('yourPlan')} className="grid grid-cols-2 gap-2" data-testid="plan-cards">
            {choices.map((c) => (
              <button
                key={c.id}
                type="button"
                role="radio"
                aria-checked={pick === c.id}
                onClick={() => {
                  haptic('selection');
                  setPick(c.id);
                }}
                data-testid={`plan-${c.id}`}
                className={cx(
                  'focus-ring relative flex min-h-24 flex-col items-start gap-1 rounded-card p-3 text-start transition-colors',
                  c.id === 'nussnuss.trip_pass' && 'col-span-2',
                  pick === c.id ? 'bg-accent-soft ring-2 ring-accent' : 'bg-surface ring-1 ring-edge',
                )}
              >
                <span className="flex w-full items-center justify-between gap-2">
                  <span className="t-headline text-text">{c.title}</span>
                  <span className={cx('grid h-6 w-6 shrink-0 place-items-center rounded-full', pick === c.id ? 'bg-accent text-on-accent' : 'ring-2 ring-edge')} aria-hidden>
                    {pick === c.id ? <Check size={14} weight="bold" /> : null}
                  </span>
                </span>
                {c.price ? <span className="t-title-3 text-text num" data-testid="plan-price">{c.price}</span> : null}
                {c.body ? <span className="t-footnote text-text-2">{c.body}</span> : null}
                {c.badge ? <span className="rounded-full bg-highlight px-2 py-0.5 t-caption font-semibold text-on-highlight">{c.badge}</span> : null}
              </button>
            ))}
          </div>
          <p className="rounded-card bg-surface px-4 py-3 t-subhead text-text-2" data-testid="buy-in-app">
            {t('buyInApp')}
          </p>
          {DEV ? (
            <Button block onClick={devBuy} disabled={busy} data-testid="dev-buy">
              {t('devBuy')}
            </Button>
          ) : null}
          <p className="text-center t-footnote text-text-2">{t('billedBy')}</p>
          <div className="flex justify-center gap-4 t-footnote font-semibold">
            <a href="/terms" className="focus-ring tap inline-flex items-center rounded-full px-2 text-accent">
              {t('terms')}
            </a>
            <a href="/privacy" className="focus-ring tap inline-flex items-center rounded-full px-2 text-accent">
              {t('privacy')}
            </a>
          </div>
        </div>
      </Sheet>
    </Ctx.Provider>
  );
}
