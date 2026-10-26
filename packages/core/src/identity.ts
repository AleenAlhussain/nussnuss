/**
 * Identity: how groups and people look. Groups get a drawn icon on a two-tone cover; people get a
 * photo, an emoji or their initial on a tone chosen once. The same rules run in the Dart port
 * (apps/mobile/lib/core/identity.dart), checked by the parity test.
 */

/** Drawn icons for group covers. Each app draws them itself (no emoji in the interface). */
export const COVER_ICONS = [
  'plane',
  'beach',
  'mountain',
  'car',
  'home',
  'food',
  'coffee',
  'moon',
  'party',
  'gift',
  'cart',
  'heart',
  'ball',
  'work',
  'book',
  'music',
] as const;
export type CoverIcon = (typeof COVER_ICONS)[number];

/** Tones shared by covers and avatars (tokens.json → covers). */
export const COVER_TONES = ['violet', 'saffron', 'mint', 'coral', 'sky', 'rose', 'slate'] as const;
export type CoverTone = (typeof COVER_TONES)[number];

export interface Cover {
  icon: CoverIcon;
  tone: CoverTone;
}

const ICONS = new Set<string>(COVER_ICONS);
const TONES = new Set<string>(COVER_TONES);

export const isCoverIcon = (s: string): s is CoverIcon => ICONS.has(s);
export const isCoverTone = (s: string): s is CoverTone => TONES.has(s);

/** "plane:sky" → { icon, tone }, or null when it isn't a cover. */
export function parseCover(s: string | null | undefined): Cover | null {
  if (!s) return null;
  const [icon, tone] = s.split(':');
  return icon && tone && isCoverIcon(icon) && isCoverTone(tone) ? { icon, tone } : null;
}

export const coverKey = (c: Cover): string => `${c.icon}:${c.tone}`;

/** FNV-1a over UTF-16 code units: a stable, cheap hash both apps compute the same way. */
export function stableHash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** A tone picked from a name, so someone without a chosen colour always gets the same one. */
export function toneFor(seed: string): CoverTone {
  return COVER_TONES[stableHash(seed.trim().toLowerCase()) % COVER_TONES.length];
}

/** Groups made before covers had an emoji; this is the drawn icon that stands for it. */
const EMOJI_ICONS: Record<string, CoverIcon> = {
  '✈️': 'plane',
  '🧳': 'plane',
  '🌍': 'plane',
  '🏖️': 'beach',
  '🏝️': 'beach',
  '🏔️': 'mountain',
  '🏕️': 'mountain',
  '🚗': 'car',
  '🏠': 'home',
  '🏡': 'home',
  '🏢': 'home',
  '🛋️': 'home',
  '🍽️': 'food',
  '🍕': 'food',
  '🍔': 'food',
  '🥘': 'food',
  '☕': 'coffee',
  '🌙': 'moon',
  '🕌': 'moon',
  '🏮': 'moon',
  '🎉': 'party',
  '🎂': 'party',
  '🎁': 'gift',
  '💍': 'gift',
  '🛒': 'cart',
  '🛍️': 'cart',
  '❤️': 'heart',
  '⚽': 'ball',
  '🏀': 'ball',
  '💼': 'work',
  '📚': 'book',
  '🎵': 'music',
  '🎶': 'music',
};

const STRIPPED = new Map(Object.entries(EMOJI_ICONS).map(([k, v]) => [k.replace(/\uFE0F/g, ''), v]));

const ICON_TONE: Record<CoverIcon, CoverTone> = {
  plane: 'sky',
  beach: 'saffron',
  mountain: 'mint',
  car: 'slate',
  home: 'violet',
  food: 'coral',
  coffee: 'saffron',
  moon: 'violet',
  party: 'rose',
  gift: 'rose',
  cart: 'mint',
  heart: 'rose',
  ball: 'mint',
  work: 'slate',
  book: 'sky',
  music: 'coral',
};

/** The cover a group shows: its own, or one drawn from its old emoji. */
export function groupCover(g: { cover?: string | null; emoji?: string | null }): Cover {
  const own = parseCover(g.cover);
  if (own) return own;
  const e = (g.emoji ?? '').trim();
  const icon = EMOJI_ICONS[e] ?? STRIPPED.get(e.replace(/\uFE0F/g, '')) ?? 'food';
  return { icon, tone: ICON_TONE[icon] };
}

/** The default tone for an icon, used when someone picks an icon and hasn't chosen a colour. */
export const toneOfIcon = (icon: CoverIcon): CoverTone => ICON_TONE[icon];

/** The first letter of a name, as an avatar shows it ("omar" → "O", "مها" → "م"). */
export function initialOf(name: string): string {
  const first = Array.from(name.trim())[0] ?? '?';
  return first.toLocaleUpperCase('en');
}

/** How a person looks. Photos are served by the API at `url`. */
export type Avatar =
  | { kind: 'initial'; tone: CoverTone }
  | { kind: 'emoji'; value: string; tone: CoverTone }
  | { kind: 'photo'; url: string; tone: CoverTone };

/** Emoji people can pick for themselves (avatars only; the interface itself uses drawn icons). */
export const AVATAR_EMOJI = ['😀', '😎', '🤓', '🥳', '🦊', '🐱', '🐼', '🦁', '🐢', '🐙', '🌵', '🌻', '⚽', '🎧', '☕', '🌙'] as const;
