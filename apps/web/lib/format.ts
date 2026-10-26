import { formatMoney } from '@nussnuss/core';
import type { Lang, TKey } from './i18n';

/** Money with a no-break space, so "AED 833.33" never splits across two lines. */
export const money = (minor: number, code: string, lang: Lang) => formatMoney(minor, code, lang).replace(/ /g, ' ');

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

/** How long ago, short: "now", "12 min", "2h", then "Mon", then "12 Oct". */
export function ago(iso: string, lang: Lang): string {
  const ms = Date.now() - new Date(iso).getTime();
  const min = Math.round(ms / 60000);
  const ar = lang === 'ar';
  if (min < 1) return ar ? 'الآن' : 'now';
  if (min < 60) return ar ? `${min} د` : `${min} min`;
  const h = Math.round(min / 60);
  if (h < 24) return ar ? `${h} س` : `${h}h`;
  const d = new Date(iso);
  const loc = ar ? 'ar-u-nu-latn' : 'en-GB';
  if (h < 24 * 6) return d.toLocaleDateString(loc, { weekday: 'short' });
  return d.toLocaleDateString(loc, { day: 'numeric', month: 'short' });
}

/** Which bucket of the Activity timeline a date falls in. */
export function whenBucket(iso: string): 'today' | 'yesterday' | 'thisWeek' | 'earlier' {
  const d = new Date(iso);
  const now = new Date();
  const start = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = Math.round((start(now) - start(d)) / 864e5);
  if (diff <= 0) return 'today';
  if (diff === 1) return 'yesterday';
  if (diff < 7) return 'thisWeek';
  return 'earlier';
}
