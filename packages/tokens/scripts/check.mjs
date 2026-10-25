// WCAG contrast check for every token pair, in light and dark, and for text on glass over every backdrop.
// body text needs 4.5:1, ui (focus rings, input borders) 3:1, decor is reported only. Exit 1 on any failure.
import { composite, contrast, tokens } from './lib.mjs';

let failures = 0;
const line = (ok, label, ratio, need) =>
  console.log(`  ${ok ? 'OK  ' : 'FAIL'} ${label.padEnd(44)} ${ratio.toFixed(2).padStart(5)}:1${need ? ` (need ${need})` : ''}`);

for (const mode of ['light', 'dark']) {
  const c = tokens.color[mode];
  console.log(`\n[${mode}] token pairs`);
  for (const [fg, bg, kind] of tokens.pairs) {
    const r = contrast(c[fg], c[bg]);
    const need = kind === 'body' ? 4.5 : kind === 'ui' ? 3 : 0;
    const ok = r >= need;
    if (!ok) failures++;
    line(ok, `${fg} on ${bg}`, r, need || undefined);
  }

  for (const variant of ['regular', 'frosted']) {
    const g = tokens.glass[variant][mode];
    console.log(`\n[${mode}] text on ${variant} glass`);
    for (const backdropKey of tokens.glass.backdrops[mode]) {
      const surface = composite(g.fill, g.fillAlpha, c[backdropKey]);
      for (const fg of tokens.glass.onGlass) {
        const r = contrast(c[fg], surface);
        // Secondary text and tinted icons on glass need 4.5:1 too: the bar is read at a glance.
        const ok = r >= 4.5;
        if (!ok) failures++;
        line(ok, `${fg} on glass over ${backdropKey}`, r, 4.5);
      }
    }
  }
}

console.log(`\n${failures} failure(s)`);
process.exit(failures ? 1 : 0);
