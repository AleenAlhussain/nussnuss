'use client';

import type { GroupDetail } from '@/lib/api';
import { money } from '@/lib/format';
import type { Lang } from '@/lib/i18n';

/**
 * The "who owes who" card people post in their group chat: 1080 × 1350 (a portrait post), the brand coin,
 * the group, each transfer, and the NussNuss line at the bottom, so every share shows where it came from.
 * Drawn on a canvas in the night palette, right to left in Arabic.
 */
const W = 1080;
const H = 1350;
const C = { bg: '#0D0A1C', card: '#18132E', text: '#FFFFFF', text2: '#B4ADD0', text3: '#9D96BC', violet: '#9B8BFF', saffron: '#FFC93D', line: '#3A3160' };

function coin(ctx: CanvasRenderingContext2D, x: number, y: number, size: number, joined = false) {
  const half = size / 2;
  const gap = joined ? 0 : size * 0.07;
  ctx.fillStyle = C.violet;
  ctx.beginPath();
  ctx.arc(x + half, y + half, half, Math.PI / 2, (Math.PI * 3) / 2);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = C.saffron;
  ctx.beginPath();
  ctx.arc(x + half + gap, y + half + (joined ? 0 : size * 0.08), half, -Math.PI / 2, Math.PI / 2);
  ctx.closePath();
  ctx.fill();
}

function fit(ctx: CanvasRenderingContext2D, text: string, max: number) {
  if (ctx.measureText(text).width <= max) return text;
  let t = text;
  while (t.length > 1 && ctx.measureText(`${t}…`).width > max) t = t.slice(0, -1);
  return `${t}…`;
}

export async function summaryCard(g: GroupDetail, lang: Lang, t: (k: 'summaryTitle' | 'summaryMade' | 'allSettled' | 'total' | 'you' | 'pays') => string): Promise<Blob> {
  const rtl = lang === 'ar';
  const display = '"Readex Pro", system-ui, sans-serif';
  try {
    await Promise.all([document.fonts.load(`700 64px ${display}`), document.fonts.load(`500 40px ${display}`)]);
  } catch {}
  const canvas = document.createElement('canvas');
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext('2d')!;
  ctx.direction = rtl ? 'rtl' : 'ltr';
  const pad = 88;
  const start = rtl ? W - pad : pad;
  const end = rtl ? pad : W - pad;
  const align = (side: 'start' | 'end') => (ctx.textAlign = side === 'start' ? (rtl ? 'right' : 'left') : rtl ? 'left' : 'right');

  ctx.fillStyle = C.bg;
  ctx.fillRect(0, 0, W, H);
  // A soft saffron glow behind the coin, the one warm light on the card.
  const glow = ctx.createRadialGradient(rtl ? W - 150 : 150, 150, 10, rtl ? W - 150 : 150, 150, 420);
  glow.addColorStop(0, 'rgba(255,201,61,0.16)');
  glow.addColorStop(1, 'rgba(255,201,61,0)');
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, W, H);

  const settled = g.transfers.length === 0;
  coin(ctx, rtl ? W - pad - 104 : pad, 96, 96, settled);

  ctx.textBaseline = 'alphabetic';
  align('start');
  ctx.fillStyle = C.text2;
  ctx.font = `500 40px ${display}`;
  ctx.fillText(t('summaryTitle'), start, 300);
  ctx.fillStyle = C.text;
  ctx.font = `700 76px ${display}`;
  ctx.fillText(fit(ctx, `${g.emoji} ${g.name}`.trim(), W - pad * 2), start, 392);
  ctx.fillStyle = C.text2;
  ctx.font = `500 36px ${display}`;
  ctx.fillText(`${t('total')} · ${money(g.total, g.currency, lang)}`, start, 452);

  const name = (id: string) => {
    const m = g.members.find((x) => x.id === id);
    return m ? m.name : '?';
  };
  const top = 530;
  const rowH = 132;
  const rows = settled ? [] : g.transfers.slice(0, 5);
  ctx.fillStyle = C.card;
  const boxH = settled ? 260 : rows.length * rowH + (g.transfers.length > 5 ? 70 : 0) + 24;
  ctx.beginPath();
  ctx.roundRect(pad - 24, top, W - (pad - 24) * 2, boxH, 44);
  ctx.fill();

  if (settled) {
    ctx.textAlign = 'center';
    ctx.fillStyle = C.saffron;
    ctx.font = `700 64px ${display}`;
    ctx.fillText(t('allSettled'), W / 2, top + 150);
  } else {
    rows.forEach((tr, i) => {
      const y = top + 12 + i * rowH;
      if (i > 0) {
        ctx.fillStyle = C.line;
        ctx.fillRect(pad, y, W - pad * 2, 2);
      }
      const amount = money(tr.amount, g.currency, lang);
      ctx.font = `700 46px ${display}`;
      const aw = ctx.measureText(amount).width;
      align('end');
      ctx.fillStyle = C.saffron;
      ctx.fillText(amount, end, y + 82);
      align('start');
      ctx.fillStyle = C.text;
      ctx.font = `600 40px ${display}`;
      const arrow = rtl ? '←' : '→';
      ctx.fillText(fit(ctx, `${name(tr.from)} ${arrow} ${name(tr.to)}`, W - pad * 2 - aw - 40), start, y + 80);
    });
    if (g.transfers.length > 5) {
      align('start');
      ctx.fillStyle = C.text3;
      ctx.font = `500 34px ${display}`;
      ctx.fillText(`+${g.transfers.length - 5}`, start, top + rows.length * rowH + 64);
    }
  }

  // The brand line: every shared card says where it came from.
  coin(ctx, rtl ? W - pad - 46 : pad, H - 140, 42, true);
  align('start');
  ctx.fillStyle = C.text3;
  ctx.font = `500 34px ${display}`;
  ctx.fillText(t('summaryMade'), rtl ? W - pad - 66 : pad + 66, H - 106);

  return new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('no image'))), 'image/png'));
}
