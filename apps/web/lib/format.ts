import { formatMoney } from '@nussnuss/core';
import type { Lang, TKey } from './i18n';

export const money = (minor: number, code: string, lang: Lang) => formatMoney(minor, code, lang);

/** "Today", "Yesterday", or "Mon 20 Oct", in the person's language with Western digits. */
export function dayLabel(iso: string, lang: Lang, t: (k: TKey) => string): string {
  const d = new Date(iso);
  const today = new Date();
  const start = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = Math.round((start(today) - start(d)) / 864e5);
  if (diff === 0) return t('today');
  if (diff === 1) return t('yesterday');
  return d.toLocaleDateString(lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
}

export function dayKey(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}
