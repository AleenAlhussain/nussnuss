'use client';

import { BellRinging, ChartPieSlice, Check, CurrencyCircleDollar, FileCsv, Palette, Receipt, Repeat } from '@phosphor-icons/react';
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

const FEATURES: [ComponentType<{ size?: number; weight?: 'duotone' }>, TKey][] = [
  [Repeat, 'plusF_recurring'],
  [BellRinging, 'plusF_reminders'],
  [CurrencyCircleDollar, 'plusF_rates'],
  [Receipt, 'plusF_items'],
  [ChartPieSlice, 'plusF_charts'],
  [FileCsv, 'plusF_export'],
  [Palette, 'plusF_looks'],
];

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

  const choices: { id: Product; title: string; body?: string; badge?: string }[] = [
    { id: 'nussnuss.plus.yearly', title: t('planYearly'), badge: t('planYearlySave') },
    { id: 'nussnuss.plus.monthly', title: t('planMonthly') },
    ...(opts?.groupId ? [{ id: 'nussnuss.trip_pass' as Product, title: t('tripPass'), body: t('tripPassBody') }] : []),
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
          <div className="flex flex-col items-center gap-3 pt-1 text-center">
            <Coin size={64} />
            <p className="max-w-xs t-title-3 text-text">{t('plusTagline')}</p>
            {plan?.plus && plan.plusUntil ? (
              <p className="rounded-full bg-success-soft px-3 py-1 t-footnote font-semibold text-success" data-testid="plus-on">
                {t('plusOnUntil', { date: shortDate(plan.plusUntil, prefs.lang) })}
              </p>
            ) : pass ? (
              <p className="rounded-full bg-success-soft px-3 py-1 t-footnote font-semibold text-success">{t('tripOnUntil', { date: shortDate(pass.until, prefs.lang) })}</p>
            ) : null}
          </div>
          <ul className="flex flex-col gap-1 rounded-card bg-surface p-2">
            {FEATURES.map(([Icon, key]) => (
              <li key={key} className="flex min-h-11 items-center gap-3 px-2 t-body text-text">
                <span className="grid h-8 w-8 shrink-0 place-items-center rounded-row bg-accent-soft text-on-accent-soft" aria-hidden>
                  <Icon size={20} weight="duotone" />
                </span>
                {t(key)}
              </li>
            ))}
          </ul>
          <div role="radiogroup" aria-label={t('yourPlan')} className="flex flex-col gap-2">
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
                  'focus-ring flex min-h-14 items-center gap-3 rounded-card px-4 py-3 text-start transition-colors',
                  pick === c.id ? 'bg-accent-soft ring-2 ring-accent' : 'bg-surface ring-1 ring-separator',
                )}
              >
                <span className={cx('grid h-6 w-6 shrink-0 place-items-center rounded-full', pick === c.id ? 'bg-accent text-on-accent' : 'ring-2 ring-separator')} aria-hidden>
                  {pick === c.id ? <Check size={14} weight="bold" /> : null}
                </span>
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="t-headline text-text">{c.title}</span>
                  {c.body ? <span className="t-footnote text-text-2">{c.body}</span> : null}
                </span>
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
          <p className="text-center t-footnote text-text-3">{t('cancelAnytime')}</p>
        </div>
      </Sheet>
    </Ctx.Provider>
  );
}
