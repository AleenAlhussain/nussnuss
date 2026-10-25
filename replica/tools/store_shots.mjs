// Store screenshots from the real web build (same UI as the phone app).
// Usage: npm run build:site && node replica/tools/store_shots.mjs <chromium-path>   (serves ./site on :8098)
// Writes replica/launch/screenshots/{ios-6.9,android}/{en,ar}-N.png
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';

const exe = process.argv[2];
const BASE = 'http://127.0.0.1:8098/app';
const OUT = 'replica/launch/screenshots';
const RAW = `${OUT}/raw`;
for (const d of [RAW, `${OUT}/ios-6.9`, `${OUT}/android`]) mkdirSync(d, { recursive: true });

const server = spawn('python3', ['-m', 'http.server', '8098', '--bind', '127.0.0.1', '--directory', 'site'], { stdio: 'ignore' });
await new Promise((r) => setTimeout(r, 1200));

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox', '--disable-gpu', '--no-zygote', '--disable-software-rasterizer'] });

const CAPTIONS = {
  en: [
    ['Split any bill.', 'No limits. No sign-up.'],
    ['No ads. No wait screens.', 'Add as many expenses as you like.'],
    ['Who pays whom,', 'in the fewest transfers.'],
    ['Equally, by amount,', 'by % or by shares.'],
    ['Share it on WhatsApp.', 'Friends need no app, no account.'],
  ],
  ar: [
    ['قسّم أي فاتورة', 'بلا حدود وبلا تسجيل'],
    ['بلا إعلانات وبلا انتظار', 'أضف مصاريف قد ما تبي'],
    ['مين يدفع لمين', 'بأقل عدد تحويلات'],
    ['بالتساوي، بالمبلغ', 'بالنسبة أو بالحصص'],
    ['شاركها على واتساب', 'أصحابك ما يحتاجون تطبيق ولا حساب'],
  ],
};

async function run(lang) {
  const ctx = await browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 3, locale: 'en-AE', permissions: ['clipboard-read', 'clipboard-write'] });
  const p = await ctx.newPage();
  const shot = async (n) => {
    await p.waitForTimeout(450);
    await p.screenshot({ path: `${RAW}/${lang}-${n}.png` });
  };
  const back = () => p.getByRole('button', { name: lang === 'ar' ? 'رجوع' : 'Back' }).click();
  await p.goto(BASE + '/');
  if (lang === 'ar') await p.getByTestId('lang-ar').click();
  await p.getByTestId('name').fill(lang === 'ar' ? 'أحمد' : 'Ahmed');
  await p.getByTestId('start').click();
  await p.getByTestId('try-demo').click(); // demo trip (OMR, 3 decimals)
  await back();
  // second group
  await p.getByTestId('new-group').first().click();
  await p.getByTestId('group-name').fill(lang === 'ar' ? 'سكن الجامعة' : 'Flat 12');
  for (const n of lang === 'ar' ? ['خالد', 'يوسف'] : ['Khalid', 'Yusuf']) {
    await p.getByTestId('member-name').fill(n);
    await p.getByTestId('add-member').click();
  }
  await p.getByTestId('group-currency').click();
  await p.getByTestId('currency-AED').click();
  await p.getByTestId('save-group').click();
  await p.getByTestId('add-expense').click();
  await p.getByTestId('amount').fill('360');
  await p.getByTestId('title').fill(lang === 'ar' ? 'فاتورة الإنترنت' : 'Internet bill');
  await p.getByTestId('cat-bills').click();
  await p.getByTestId('payer').nth(1).click();
  await p.getByTestId('save-expense').click();
  await back();
  await shot(1); // home with two groups
  await p.getByTestId('group-card').nth(1).click(); // demo trip
  await shot(2); // expenses
  await p.getByTestId('tab-balances').click();
  await shot(3); // who pays whom
  await p.getByTestId('tab-expenses').click();
  await p.getByTestId('add-expense').click();
  await p.getByTestId('amount').fill('24');
  await p.getByTestId('title').fill(lang === 'ar' ? 'كرك وشاي' : 'Karak & snacks');
  await p.getByTestId('cat-food').click();
  await p.getByTestId('mode-shares').click();
  const v = p.getByTestId('split-value');
  await v.nth(2).fill('2');
  await v.nth(3).fill('0');
  await p.getByTestId('title').click();
  await shot(4); // split by shares
  await back();
  await p.getByTestId('share').click();
  await p.getByTestId('copy-link').click();
  const link = await p.evaluate(() => navigator.clipboard.readText());
  const payload = link.split('#g=')[1];
  const f = await browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 3, locale: 'en-AE' });
  const fp = await f.newPage();
  await fp.goto(BASE + '/');
  if (lang === 'ar') {
    await fp.getByTestId('lang-ar').click();
  }
  await fp.goto(`${BASE}/#g=${payload}`);
  await fp.waitForTimeout(500);
  await fp.screenshot({ path: `${RAW}/${lang}-5.png` });
  await f.close();
  await ctx.close();
}

async function compose(lang, n, w, h, dir) {
  const [l1, l2] = CAPTIONS[lang][n - 1];
  const img = readFileSync(`${RAW}/${lang}-${n}.png`).toString('base64');
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  const shotH = Math.round(h * 0.74);
  const shotW = Math.round((shotH * 430) / 932);
  await p.setContent(`<!doctype html><html dir="${lang === 'ar' ? 'rtl' : 'ltr'}"><head><meta charset="utf-8"><style>
    html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden;font-family:"DejaVu Sans",system-ui,sans-serif}
    body{background:linear-gradient(170deg,#4F3BD6 0%,#3A2AA8 70%,#2A1F7A 100%);display:flex;flex-direction:column;align-items:center}
    .cap{margin-top:${Math.round(h * 0.06)}px;text-align:center;color:#fff;padding:0 ${Math.round(w * 0.07)}px}
    .l1{font-size:${Math.round(w * 0.06)}px;font-weight:800;line-height:1.15}
    .l2{font-size:${Math.round(w * 0.045)}px;font-weight:500;color:#FFD66B;margin-top:${Math.round(h * 0.012)}px;line-height:1.25}
    .phone{margin-top:${Math.round(h * 0.035)}px;width:${shotW}px;height:${shotH}px;border-radius:${Math.round(shotW * 0.09)}px;overflow:hidden;
      box-shadow:0 30px 80px rgba(0,0,0,.35);border:${Math.max(6, Math.round(w * 0.012))}px solid #15102e;background:#15102e}
    .phone img{width:100%;height:100%;object-fit:cover;object-position:top;display:block;border-radius:${Math.round(shotW * 0.075)}px}
  </style></head><body><div class="cap"><div class="l1">${l1}</div><div class="l2">${l2}</div></div>
  <div class="phone"><img src="data:image/png;base64,${img}"></div></body></html>`);
  await p.waitForTimeout(200);
  await p.screenshot({ path: `${OUT}/${dir}/${lang}-${n}.png` });
  await ctx.close();
}

try {
  for (const lang of ['en', 'ar']) await run(lang);
  for (const lang of ['en', 'ar']) {
    for (let n = 1; n <= 5; n++) {
      await compose(lang, n, 1290, 2796, 'ios-6.9');
      await compose(lang, n, 1080, 1920, 'android');
    }
  }
  console.log('screenshots written');
} finally {
  await browser.close();
  server.kill();
}
