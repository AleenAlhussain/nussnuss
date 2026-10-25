// Google Play feature graphic (1024x500) and social share image (1200x630).
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';
const b = await chromium.launch({ executablePath: process.argv[2], args: ['--no-sandbox', '--disable-gpu', '--no-zygote', '--disable-software-rasterizer'] });
const mark = readFileSync('assets/brand/mark-on-dark.png').toString('base64');
const shot = readFileSync('replica/launch/screenshots/raw/en-3.png').toString('base64');
async function make(w, h, out) {
  const c = await b.newContext({ viewport: { width: w, height: h } });
  const p = await c.newPage();
  await p.setContent(`<!doctype html><meta charset="utf-8"><style>
  body{margin:0;width:${w}px;height:${h}px;overflow:hidden;font-family:"DejaVu Sans",sans-serif;background:linear-gradient(120deg,#4F3BD6,#2A1F7A);color:#fff;display:flex;align-items:center}
  .l{flex:1;padding-left:${w*0.06}px}
  .row{display:flex;align-items:center;gap:${w*0.02}px}
  img.m{width:${h*0.2}px}
  .n{font-size:${h*0.13}px;font-weight:800}
  .ar{font-size:${h*0.09}px;font-weight:700;color:#FFD66B;margin-top:${h*0.02}px}
  .t{font-size:${h*0.058}px;margin-top:${h*0.05}px;opacity:.95;line-height:1.35}
  .ph{width:${h*0.62}px;height:${h*1.1}px;margin-right:${w*0.06}px;margin-top:${h*0.25}px;border-radius:${h*0.06}px;overflow:hidden;border:${h*0.015}px solid #15102e;box-shadow:0 20px 60px rgba(0,0,0,.4)}
  .ph img{width:100%;display:block}
  </style><div class="l"><div class="row"><img class="m" src="data:image/png;base64,${mark}"><div class="n">NussNuss</div></div>
  <div class="ar">خلّيها نص نص</div><div class="t">Split any bill with friends.<br>No limits. No ads. No sign-up.</div></div>
  <div class="ph"><img src="data:image/png;base64,${shot}"></div>`);
  await p.waitForTimeout(200);
  await p.screenshot({ path: out });
  await c.close();
}
await make(1024, 500, 'replica/launch/feature-graphic.png');
await make(1200, 630, 'replica/launch/social.png');
await b.close();
console.log('graphics written');
