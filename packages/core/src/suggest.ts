import type { CategoryId } from './types.js';

/** Words the apps translate: `sug_${key}` in the i18n files. */
export type SuggestionKey =
  | 'breakfast'
  | 'coffee'
  | 'lunch'
  | 'dinner'
  | 'groceries'
  | 'taxi'
  | 'fuel'
  | 'hotel'
  | 'tickets'
  | 'rent'
  | 'internet'
  | 'electricity'
  | 'iftar'
  | 'suhoor'
  | 'gift';

export interface Suggestion {
  /** A title used in this group before, shown as it was typed. */
  title?: string;
  /** Or an idea to translate. */
  key?: SuggestionKey;
  category: CategoryId;
}

const IDEAS: Record<SuggestionKey, CategoryId> = {
  breakfast: 'food',
  coffee: 'food',
  lunch: 'food',
  dinner: 'food',
  groceries: 'groceries',
  taxi: 'transport',
  fuel: 'transport',
  hotel: 'stay',
  tickets: 'fun',
  rent: 'bills',
  internet: 'bills',
  electricity: 'bills',
  iftar: 'food',
  suhoor: 'food',
  gift: 'shopping',
};

const TRIP = ['✈️', '🏖️', '🏝️', '🏔️', '🚗', '🏕️', '🌍', '🧳'];
const HOME = ['🏠', '🏡', '🏢', '🛋️'];
const RAMADAN = ['🌙', '🕌', '🏮'];
const GIFTS = ['🎁', '🎉', '💍', '🎂'];

function meals(hour: number): SuggestionKey[] {
  if (hour >= 5 && hour < 11) return ['breakfast', 'coffee'];
  if (hour >= 11 && hour < 16) return ['lunch', 'coffee'];
  if (hour >= 16 && hour < 18) return ['coffee', 'groceries'];
  return ['dinner', 'groceries'];
}

/** Ideas for the kind of group and the time of day, most likely first. */
export function contextIdeas(hour: number, emoji = ''): SuggestionKey[] {
  if (RAMADAN.some((e) => emoji.includes(e))) return hour >= 0 && hour < 5 ? ['suhoor', 'iftar', 'groceries'] : ['iftar', 'suhoor', 'groceries'];
  if (TRIP.some((e) => emoji.includes(e))) return [...meals(hour).slice(0, 1), 'taxi', 'hotel', 'tickets', 'fuel'];
  if (HOME.some((e) => emoji.includes(e))) return ['groceries', 'rent', 'internet', 'electricity'];
  if (GIFTS.some((e) => emoji.includes(e))) return ['gift', ...meals(hour).slice(0, 1)];
  return [...meals(hour), 'taxi'];
}

/**
 * Up to `n` suggestions for an expense title: this group's most recent distinct titles first
 * (people repeat themselves), then ideas for the time of day and the kind of group.
 */
export function suggestTitles(opts: {
  recent: { title: string; category: string }[];
  hour: number;
  emoji?: string;
  n?: number;
  /** Translates an idea, so an idea that matches a recent title is not offered twice. */
  label?: (key: SuggestionKey) => string;
}): Suggestion[] {
  const n = opts.n ?? 4;
  const out: Suggestion[] = [];
  const seen = new Set<string>();
  for (const e of opts.recent) {
    const k = e.title.trim().toLocaleLowerCase();
    if (!k || seen.has(k)) continue;
    seen.add(k);
    out.push({ title: e.title.trim(), category: e.category as CategoryId });
    if (out.length >= Math.min(2, n)) break;
  }
  for (const key of contextIdeas(opts.hour, opts.emoji)) {
    if (out.length >= n) break;
    const k = (opts.label?.(key) ?? key).trim().toLocaleLowerCase();
    if (seen.has(k)) continue;
    seen.add(k);
    out.push({ key, category: IDEAS[key] });
  }
  return out;
}
