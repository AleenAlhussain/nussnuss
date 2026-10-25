'use client';

import { Backspace } from '@phosphor-icons/react';
import { decimalsOf, normalizeDigits, parseAmountExpression } from '@nussnuss/core';
import { useEffect } from 'react';
import { haptic } from '@/lib/feel';
import { money } from '@/lib/format';
import type { Lang } from '@/lib/i18n';

const KEYS = ['7', '8', '9', '4', '5', '6', '1', '2', '3', '.', '0', 'back'] as const;

/**
 * The amount keypad: big number on top, keys below, simple sums (12 + 8.5). Physical keyboards work too.
 * The value is the raw text; the parent parses it with parseAmountExpression.
 */
export function Keypad({ value, onChange, currency, lang, label }: { value: string; onChange: (v: string) => void; currency: string; lang: Lang; label: string }) {
  const decimals = decimalsOf(currency);
  const parsed = parseAmountExpression(value, currency);
  const isSum = /[+-]/.test(value.slice(1));

  const press = (k: string) => {
    haptic('selection');
    if (k === 'back') return onChange(value.slice(0, -1));
    if (k === '+' || k === '-') {
      if (!value || /[+-]$/.test(value)) return;
      return onChange(value + k);
    }
    const term = value.split(/[+-]/).pop() ?? '';
    if (k === '.') {
      if (decimals === 0 || term.includes('.')) return;
      return onChange(value + (term ? '.' : '0.'));
    }
    const frac = term.split('.')[1];
    if (frac !== undefined && frac.length >= decimals) return;
    if (term.replace('.', '').length >= 12) return;
    onChange(value + k);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return;
      const k = normalizeDigits(e.key).replace(',', '.');
      if (/^[0-9.+-]$/.test(k)) {
        e.preventDefault();
        press(k);
      } else if (e.key === 'Backspace') {
        e.preventDefault();
        press('back');
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const shown = value ? value.replace(/-/g, ' − ').replace(/\+/g, ' + ') : decimals ? `0.${'0'.repeat(decimals)}` : '0';
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col items-center gap-1 py-2" aria-live="polite">
        <span className="sr-only">{label}</span>
        <output data-testid="amount" className={`t-amount-hero ${value ? 'text-text' : 'text-text-3'}`} dir="ltr">
          {shown}
        </output>
        <span className="h-5 t-subhead text-text-2 num" data-testid="amount-sum">
          {isSum && parsed ? `= ${money(parsed, currency, lang)}` : currency}
        </span>
      </div>
      <div className="grid grid-cols-4 gap-2" dir="ltr">
        <div className="col-span-3 grid grid-cols-3 gap-2">
          {KEYS.map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => press(k)}
              disabled={k === '.' && decimals === 0}
              aria-label={k === 'back' ? 'Delete' : k === '.' ? 'Decimal point' : k}
              className="focus-ring h-14 rounded-control bg-surface t-title-2 text-text transition-transform active:scale-95 active:bg-surface-2 disabled:opacity-30"
            >
              {k === 'back' ? <Backspace size={24} className="mx-auto" /> : k}
            </button>
          ))}
        </div>
        <div className="grid grid-rows-2 gap-2">
          <button type="button" onClick={() => press('+')} aria-label="Plus" className="focus-ring rounded-control bg-accent-soft t-title-2 text-on-accent-soft active:scale-95">
            +
          </button>
          <button type="button" onClick={() => press('-')} aria-label="Minus" className="focus-ring rounded-control bg-accent-soft t-title-2 text-on-accent-soft active:scale-95">
            −
          </button>
        </div>
      </div>
    </div>
  );
}
