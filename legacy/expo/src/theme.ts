import tokens from './design/tokens.json';

export type Palette = typeof tokens.color.light;
export type AccentName = 'violet' | 'saffron' | 'ocean' | 'rose';
export const ACCENT_NAMES: AccentName[] = ['violet', 'saffron', 'ocean', 'rose'];

/** Plus colour themes override only the accent roles; every combination passes AA (replica/tools/contrast.py). */
export function palette(scheme: 'light' | 'dark', accent: string): Palette {
  const base = tokens.color[scheme];
  const accents = tokens.accents as Record<string, Record<string, Partial<Palette>>>;
  const over = accents[accent]?.[scheme] ?? {};
  return { ...base, ...over } as Palette;
}

export function accentSwatch(accent: AccentName, scheme: 'light' | 'dark'): string {
  return palette(scheme, accent).accent;
}

export const space = tokens.space;
export const radius = tokens.radius;
export const fontSize = tokens.font.size;
export const layout = tokens.layout;
