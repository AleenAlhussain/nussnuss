'use client';

import { CaretLeft, CaretRight, Check, MagnifyingGlass } from '@phosphor-icons/react';
import { CURRENCIES } from '@nussnuss/core';
import { useEffect, useMemo, useRef, useState } from 'react';
import { haptic } from '@/lib/feel';
import { useSession } from '@/lib/session';
import { cx } from './ui';

/** The currency of the person's region, a good first guess. */
export function guessCurrency(): string {
  try {
    const region = new Intl.Locale(navigator.language).maximize().region;
    const map: Record<string, string> = { AE: 'AED', SA: 'SAR', KW: 'KWD', QA: 'QAR', BH: 'BHD', OM: 'OMR', EG: 'EGP', JO: 'JOD', SY: 'SYP', LB: 'LBP', IQ: 'IQD', MA: 'MAD', TR: 'TRY', GB: 'GBP', US: 'USD', DE: 'EUR', FR: 'EUR', IN: 'INR' };
    if (region && map[region]) return map[region];
  } catch {}
  return 'AED';
}

const nameOf = (code: string, lang: string) => {
  const c = CURRENCIES.find((x) => x.code === code);
  return c ? (lang === 'ar' ? c.ar : c.en) : code;
};

/** The row that shows the chosen currency and opens the picker (the same on the web and in the phone app). */
export function CurrencyButton({ value, onClick, label, testId, compact }: { value: string; onClick: () => void; label: string; testId?: string; compact?: boolean }) {
  const { prefs } = useSession();
  return (
    <div className="flex flex-col gap-1.5">
      {!compact ? <span className="t-footnote font-medium text-text-2 ps-1">{label}</span> : null}
      <button
        type="button"
        onClick={() => {
          haptic('selection');
          onClick();
        }}
        className="field flex h-12 items-center gap-3 rounded-control bg-surface px-4 text-start"
        data-testid={testId}
        data-value={value}
      >
        <span className="sr-only">{label}: </span>
        <span className="t-headline text-text num">{value}</span>
        {!compact ? <span className="min-w-0 flex-1 truncate t-body text-text-2">{nameOf(value, prefs.lang)}</span> : <span className="flex-1" />}
        <CaretRight size={18} className="text-text-3 rtl:-scale-x-100" aria-hidden />
      </button>
    </div>
  );
}

/**
 * The currency list, shown in place of a sheet's content (never a sheet over a sheet): a search field,
 * the likely ones first, then every currency.
 */
export function CurrencyList({ value, onPick, onBack, extra = [] }: { value: string; onPick: (code: string) => void; onBack: () => void; extra?: string[] }) {
  const { t, prefs } = useSession();
  const [q, setQ] = useState('');
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const id = setTimeout(() => input.current?.focus(), 80);
    return () => clearTimeout(id);
  }, []);
  const suggested = useMemo(() => [...new Set([value, guessCurrency(), ...extra])].filter((c) => CURRENCIES.some((x) => x.code === c)), [value, extra]);
  const k = q.trim().toLocaleLowerCase();
  const list = CURRENCIES.filter((c) => !k || c.code.toLowerCase().includes(k) || c.en.toLocaleLowerCase().includes(k) || c.ar.includes(q.trim()));
  const row = (code: string) => (
      <button
        key={code}
        type="button"
        role="option"
        aria-selected={code === value}
        onClick={() => {
          haptic('selection');
          onPick(code);
        }}
        className="focus-ring flex min-h-12 w-full items-center gap-3 border-b border-separator/60 px-4 py-2 text-start last:border-0"
        data-testid={`currency-${code}`}
      >
        <span className="w-12 t-headline text-text num">{code}</span>
        <span className="min-w-0 flex-1 truncate t-body text-text-2">{nameOf(code, prefs.lang)}</span>
        {code === value ? <Check size={18} weight="bold" className="text-accent" aria-hidden /> : null}
      </button>
  );
  return (
    <div className="flex flex-col gap-3" data-testid="currency-list">
      <button type="button" onClick={onBack} className="tap focus-ring inline-flex items-center gap-1 self-start rounded-full pe-3 t-subhead font-semibold text-accent" data-testid="currency-back">
        <CaretLeft size={18} className="rtl:-scale-x-100" aria-hidden />
        {t('back')}
      </button>
      <label className="flex h-11 items-center gap-2 rounded-full bg-surface px-4 text-text-2 ring-1 ring-edge focus-within:ring-2 focus-within:ring-accent">
        <MagnifyingGlass size={18} aria-hidden />
        <input
          ref={input}
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t('search')}
          aria-label={`${t('search')} ${t('currency')}`}
          className="min-w-0 flex-1 bg-transparent t-body text-text outline-none placeholder:text-text-2"
          data-testid="currency-search"
        />
      </label>
      {!k ? (
        <div role="listbox" aria-label={t('currency')} className={cx('flex flex-col overflow-hidden rounded-card bg-surface')}>
          {suggested.map(row)}
        </div>
      ) : null}
      <div role="listbox" aria-label={t('currency')} className="flex flex-col overflow-hidden rounded-card bg-surface">
        {list.filter((c) => k || !suggested.includes(c.code)).map((c) => row(c.code))}
      </div>
    </div>
  );
}
