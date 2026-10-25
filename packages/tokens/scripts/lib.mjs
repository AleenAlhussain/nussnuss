import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = join(dirname(fileURLToPath(import.meta.url)), '..');
export const tokens = JSON.parse(readFileSync(join(root, 'tokens.json'), 'utf8'));

export function hexToRgb(hex) {
  const h = hex.replace('#', '');
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
}

export function rgbToHex([r, g, b]) {
  return '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();
}

/** `top` at `alpha` over an opaque `bottom`. */
export function composite(top, alpha, bottom) {
  const t = hexToRgb(top);
  const b = hexToRgb(bottom);
  return rgbToHex(t.map((v, i) => v * alpha + b[i] * (1 - alpha)));
}

function luminance(hex) {
  const f = (c) => {
    const v = c / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  const [r, g, b] = hexToRgb(hex).map(f);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a, b) {
  const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

export function rgba(hex, alpha) {
  const [r, g, b] = hexToRgb(hex);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export const kebab = (s) => s.replace(/[A-Z0-9]/g, (m) => '-' + m.toLowerCase()).replace(/^-/, '');

/** SwiftUI-style spring → Flutter stiffness (mass 1). */
export function stiffness(response) {
  return Math.round(((2 * Math.PI) / response) ** 2 * 10) / 10;
}
