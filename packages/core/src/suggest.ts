import { isCoverIcon, type CoverIcon } from './identity.js';
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

const TRIP_ICONS = new Set<CoverIcon>(['plane', 'beach', 'mountain', 'car']);

/** Ideas for the kind of group and the time of day, most likely first. `kind` is the cover icon (or an old emoji). */
export function contextIdeas(hour: number, kind = ''): SuggestionKey[] {
  const icon = isCoverIcon(kind) ? kind : null;
  if (icon === 'moon' || RAMADAN.some((e) => kind.includes(e))) return hour >= 0 && hour < 5 ? ['suhoor', 'iftar', 'groceries'] : ['iftar', 'suhoor', 'groceries'];
  if ((icon && TRIP_ICONS.has(icon)) || TRIP.some((e) => kind.includes(e))) return [...meals(hour).slice(0, 1), 'taxi', 'hotel', 'tickets', 'fuel'];
  if (icon === 'home' || HOME.some((e) => kind.includes(e))) return ['groceries', 'rent', 'internet', 'electricity'];
  if (icon === 'gift' || icon === 'party' || GIFTS.some((e) => kind.includes(e))) return ['gift', ...meals(hour).slice(0, 1)];
  return [...meals(hour), 'taxi'];
}

/** Words that name a category, in English and Arabic (normalised: lower case, no diacritics, plain alef). */
const KEYWORDS: Record<Exclude<CategoryId, 'other'>, string[]> = {
  food: [
    'breakfast', 'brunch', 'lunch', 'dinner', 'supper', 'coffee', 'cafe', 'café', 'restaurant', 'pizza', 'burger', 'burgers', 'shawarma',
    'sushi', 'kebab', 'falafel', 'snack', 'snacks', 'dessert', 'desserts', 'juice', 'tea', 'karak', 'bakery', 'iftar', 'suhoor', 'sohour',
    'food', 'meal', 'takeaway', 'delivery', 'bbq', 'grill', 'mandi', 'kabsa',
    'فطور', 'افطار', 'غداء', 'غدا', 'عشاء', 'عشا', 'سحور', 'قهوه', 'كافيه', 'مطعم', 'بيتزا', 'برجر', 'برغر', 'شاورما', 'سوشي',
    'كباب', 'فلافل', 'حلويات', 'حلا', 'عصير', 'شاي', 'كرك', 'مخبز', 'فطاير', 'مشاوي', 'مندي', 'كبسه', 'اكل', 'وجبه', 'طلبات',
  ],
  groceries: [
    'groceries', 'grocery', 'supermarket', 'hypermarket', 'market', 'vegetables', 'veggies', 'fruit', 'fruits', 'milk', 'bread', 'water',
    'eggs', 'meat', 'chicken',
    'بقاله', 'سوبرماركت', 'ماركت', 'هايبر', 'خضار', 'خضروات', 'فواكه', 'فاكهه', 'حليب', 'خبز', 'ماي', 'مويه', 'بيض', 'لحم', 'دجاج',
    'مقاضي', 'تموين',
  ],
  transport: [
    'taxi', 'cab', 'fuel', 'petrol', 'gas', 'diesel', 'parking', 'toll', 'tolls', 'bus', 'metro', 'train', 'tram', 'flight', 'flights',
    'airline', 'airport', 'car', 'rental', 'ride', 'ferry', 'transport',
    'تاكسي', 'تكسي', 'بنزين', 'وقود', 'ديزل', 'موقف', 'مواقف', 'باركينج', 'باص', 'حافله', 'مترو', 'قطار', 'طيران', 'مطار', 'سياره',
    'توصيل', 'مواصلات', 'عباره',
  ],
  stay: [
    'hotel', 'hostel', 'motel', 'apartment', 'resort', 'room', 'rooms', 'chalet', 'villa', 'camp', 'camping', 'lodge', 'stay',
    'فندق', 'شقه', 'منتجع', 'غرفه', 'شاليه', 'فيلا', 'استراحه', 'مخيم', 'سكن',
  ],
  fun: [
    'tickets', 'ticket', 'cinema', 'movie', 'movies', 'concert', 'museum', 'park', 'zoo', 'game', 'games', 'bowling', 'karaoke', 'show',
    'theatre', 'theater', 'boat', 'diving', 'safari', 'match', 'gym', 'spa',
    'سينما', 'فيلم', 'حفله', 'متحف', 'حديقه', 'ملاهي', 'العاب', 'بولينج', 'مسرح', 'قارب', 'غوص', 'سفاري', 'تذاكر', 'تذكره', 'مباراه',
    'نادي',
  ],
  bills: [
    'rent', 'internet', 'wifi', 'electricity', 'power', 'phone', 'mobile', 'subscription', 'cleaning', 'cleaner', 'maintenance',
    'insurance', 'bill', 'bills', 'utilities',
    'ايجار', 'انترنت', 'كهرباء', 'كهربا', 'فاتوره', 'فواتير', 'جوال', 'موبايل', 'اشتراك', 'تنظيف', 'صيانه', 'تامين',
  ],
  shopping: [
    'gift', 'gifts', 'present', 'presents', 'clothes', 'shoes', 'mall', 'shopping', 'souvenir', 'souvenirs', 'electronics', 'pharmacy',
    'medicine', 'flowers',
    'هديه', 'هدايا', 'ملابس', 'احذيه', 'مول', 'تسوق', 'صيدليه', 'دواء', 'ورد', 'عطور',
  ],
};

/** Phrases checked before single words ("water bill" is a bill, "water" is groceries). */
const PHRASES: [string, CategoryId][] = [
  ['water bill', 'bills'],
  ['gas bill', 'bills'],
  ['car rental', 'transport'],
  ['rental car', 'transport'],
  ['ice cream', 'food'],
  ['فاتوره ماء', 'bills'],
  ['فاتوره مويه', 'bills'],
  ['واي فاي', 'bills'],
  ['ايجار سياره', 'transport'],
];

const WORD_CATEGORY = new Map<string, CategoryId>();
for (const [cat, words] of Object.entries(KEYWORDS) as [CategoryId, string[]][]) for (const w of words) if (!WORD_CATEGORY.has(w)) WORD_CATEGORY.set(w, cat);

/** Lower case, Arabic diacritics and tatweel removed, alef/ya/ta marbuta made plain, Arabic digits made Latin. */
export function normalizeWords(s: string): string {
  return s
    .toLowerCase()
    .replace(/[\u064B-\u0652\u0670\u0640]/g, '')
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/ؤ/g, 'و')
    .replace(/ئ/g, 'ي')
    .trim();
}

/** The category a title names, or null when no word gives it away. "Fuel" → transport, "عشاء" → food. */
export function categoryFromTitle(title: string): CategoryId | null {
  const s = normalizeWords(title);
  if (!s) return null;
  for (const [p, cat] of PHRASES) if (s.includes(p)) return cat;
  for (const raw of s.split(/[^\p{L}\p{N}]+/u)) {
    if (!raw) continue;
    const hit = WORD_CATEGORY.get(raw) ?? (raw.startsWith('ال') && raw.length > 3 ? WORD_CATEGORY.get(raw.slice(2)) : undefined);
    if (hit) return hit;
  }
  return null;
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
