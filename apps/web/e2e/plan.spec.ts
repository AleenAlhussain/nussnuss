import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

/** The enhancement plan, end to end: three-tap add, nudges, sharing, accounts, offline, Plus, circles. */
const SHOTS = process.env.SHOTS_DIR ?? 'test-results/screens';

function guard(page: Page) {
  const problems: string[] = [];
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error' && !/favicon|ERR_TUNNEL|ERR_INTERNET_DISCONNECTED|Failed to fetch|net::ERR|status of 40[13]/.test(m.text())) problems.push(`console: ${m.text()}`);
  });
  return () => expect(problems, problems.join('\n')).toEqual([]);
}
const still = (page: Page) => page.waitForTimeout(700);
async function a11y(page: Page, where: string) {
  const r = await new AxeBuilder({ page }).analyze();
  const bad = r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  expect(bad.map((v) => `${where}: ${v.id} (${v.nodes.length}) ${v.nodes[0]?.target}`)).toEqual([]);
}
async function start(page: Page, name: string) {
  await page.goto('/');
  await page.getByTestId('name').fill(name);
  await page.getByTestId('start').click();
  await expect(page.getByTestId('new-group-sheet')).toBeVisible();
}
async function group(page: Page, name: string, people: string[], currency = 'AED') {
  if (!(await page.getByTestId('new-group-sheet').isVisible())) await page.getByTestId('add').click();
  await page.getByTestId('group-name').fill(name);
  await page.getByTestId('group-currency').selectOption(currency);
  for (const p of people) {
    await page.getByTestId('person-name').fill(p);
    await page.getByTestId('add-person').click();
  }
  await page.getByTestId('create-group').click();
  await expect(page.getByTestId('group')).toBeVisible();
}
async function amount(page: Page, digits: string) {
  for (const d of digits) await page.getByRole('button', { name: d === '.' ? 'Decimal point' : d, exact: true }).click();
}
async function plus(page: Page) {
  await page.goto('/settings');
  await page.getByTestId('plan-row').click();
  await page.getByTestId('dev-buy').click();
  await expect(page.getByTestId('toast')).toContainText('Plus is on');
}

test('three taps: amount, suggested title, save; details folded; repeat by holding +', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Talal');
  await page.getByTestId('tpl-trip').click();
  await group(page, 'Muscat', ['Sara', 'Omar']);

  await page.getByTestId('add').click();
  await expect(page.getByTestId('expense-sheet')).toBeVisible();
  await amount(page, '45');
  const suggested = await page.getByTestId('title').getAttribute('placeholder');
  expect(suggested).toBeTruthy();
  await expect(page.getByTestId('suggestion').first()).toHaveText(suggested!);
  await expect(page.getByTestId('details-summary')).toHaveText(/^You paid · split equally · /);
  await expect(page.getByTestId('cat-food')).toHaveCount(0);
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p01-three-tap.png` });
  await a11y(page, 'three-tap sheet');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
  await expect(page.getByTestId('expense-row')).toHaveCount(1);
  await expect(page.getByTestId('expense-row').first()).toContainText(suggested!);
  await expect(page.getByTestId('my-balance')).toHaveText('AED 30.00');

  // The title chips: recent titles come first next time.
  await page.getByTestId('add').click();
  await expect(page.getByTestId('suggestion').first()).toHaveText(suggested!);
  await expect(page.getByTestId('repeat-last')).toContainText(suggested!);
  await page.getByTestId('repeat-last').click();
  await expect(page.getByTestId('expense-row')).toHaveCount(2);
  await expect(page.getByTestId('toast')).toContainText('Added again');

  // Press and hold + repeats the last one without opening the sheet.
  const add = page.getByTestId('add');
  await add.hover();
  await page.mouse.down();
  await page.waitForTimeout(800);
  await page.mouse.up();
  await expect(page.getByTestId('expense-row')).toHaveCount(3);
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
  await page.getByRole('button', { name: 'Undo' }).last().click();
  await expect(page.getByTestId('expense-row')).toHaveCount(2);
  await expect(page.getByTestId('my-balance')).toHaveText('AED 60.00');

  // Plus-only choices open the Plus sheet.
  await page.getByTestId('add').click();
  await page.getByTestId('details').click();
  await page.getByTestId('every-month').click();
  await expect(page.getByTestId('paywall')).toBeVisible();
  await expect(page.getByTestId('buy-in-app')).toBeVisible();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p02-paywall.png` });
  await a11y(page, 'paywall');
  done();
});

test('settle up: remind, pay with, and the share card; a friend pays with my IBAN', async ({ page, browser }) => {
  const done = guard(page);
  await start(page, 'Huda');
  await page.keyboard.press('Escape');
  await page.goto('/settings');
  await page.getByTestId('add-pay-to').click();
  await page.getByTestId('pay-kind-iban').click();
  await page.getByTestId('pay-value').fill('ae07 0331 2345 6789 0123 456');
  await page.getByTestId('save-pay-to').click();
  await expect(page.getByTestId('pay-to-row')).toContainText('AE070331234567890123456');
  await page.goto('/');
  await group(page, 'Flat 7', ['Ali']);
  await page.getByTestId('add').click();
  await amount(page, '100');
  await page.getByTestId('title').fill('Internet');
  await page.getByTestId('save-expense').click();
  await page.getByTestId('tab-settle').click();
  await expect(page.getByTestId('remind')).toBeVisible();
  await expect(page.getByTestId('pay-with')).toHaveCount(0);
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByTestId('share-summary').click()]);
  expect(download.suggestedFilename()).toMatch(/\.png$/);
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p03-settle-remind.png` });
  await a11y(page, 'settle with remind');

  await page.getByTestId('share').click();
  await expect(page.getByTestId('invite-link')).toContainText('/join/');
  const link = (await page.getByTestId('invite-link').textContent())!.trim();
  const friend = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'], viewport: { width: 390, height: 844 } });
  const fp = await friend.newPage();
  await fp.goto(link);
  await fp.getByTestId('who').nth(1).check();
  await fp.getByTestId('join-btn').click();
  await expect(fp.getByTestId('group')).toBeVisible();
  await fp.getByTestId('tab-settle').click();
  await expect(fp.getByTestId('pay-with')).toBeVisible();
  await expect(fp.getByTestId('remind')).toHaveCount(0);
  await fp.getByRole('button', { name: 'Pay with Bank (IBAN)' }).click();
  await expect(fp.getByTestId('toast')).toContainText('Bank (IBAN) copied');
  expect(await fp.evaluate(() => navigator.clipboard.readText())).toBe('AE070331234567890123456');
  await still(fp);
  await fp.screenshot({ path: `${SHOTS}/p04-pay-with.png` });

  // Live: the friend's new expense reaches the first screen within seconds, with no reload.
  await page.keyboard.press('Escape');
  await page.getByTestId('tab-expenses').click();
  await fp.getByTestId('tab-expenses').click();
  await fp.getByTestId('add').click();
  for (const d of '30') await fp.getByRole('button', { name: d, exact: true }).click();
  await fp.getByTestId('title').fill('Snacks');
  await fp.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-row')).toHaveCount(2, { timeout: 5_000 });
  await friend.close();
  done();
});

test('accounts: a recovery code and a device code bring the account to a new browser', async ({ page, browser }) => {
  const done = guard(page);
  await start(page, 'Mona');
  await group(page, 'Gym', ['Rana']);
  await page.goto('/settings');
  await expect(page.getByTestId('account-status')).toContainText('Keep your groups');
  await page.getByTestId('make-recovery').click();
  const recovery = (await page.getByTestId('shown-code').textContent())!.trim();
  expect(recovery).toMatch(/^[0-9A-Z]{5}(-[0-9A-Z]{5}){3}$/);
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p05-recovery.png` });
  await page.getByRole('button', { name: 'Done' }).click();
  await expect(page.getByTestId('account-status')).toContainText('Your account is saved');
  await a11y(page, 'settings');

  const other = await browser.newContext();
  const op = await other.newPage();
  await op.goto('/');
  await op.getByTestId('have-account').click();
  await op.getByTestId('code').fill(recovery.toLowerCase());
  await op.getByTestId('code-continue').click();
  await expect(op.getByTestId('groups')).toBeVisible();
  await expect(op.getByText('Gym')).toBeVisible();

  await page.getByTestId('link-device').click();
  const short = (await page.getByTestId('shown-code').textContent())!.trim();
  expect(short).toMatch(/^[0-9A-Z]{4}-[0-9A-Z]{4}$/);
  await page.getByRole('button', { name: 'Done' }).click();
  const third = await browser.newContext();
  const tp = await third.newPage();
  await tp.goto('/');
  await tp.getByTestId('have-account').click();
  await tp.getByTestId('code').fill(short);
  await tp.getByTestId('code-continue').click();
  await expect(tp.getByText('Gym')).toBeVisible();
  // Used once: the same code no longer works.
  const fourth = await browser.newContext();
  const fp = await fourth.newPage();
  await fp.goto('/');
  await fp.getByTestId('have-account').click();
  await fp.getByTestId('code').fill(short);
  await fp.getByTestId('code-continue').click();
  await expect(fp.getByText('That code doesn’t work')).toBeVisible();
  await Promise.all([other.close(), third.close(), fourth.close()]);
  done();
});

test('offline: an expense added without a connection waits, shows, and syncs', async ({ page, context }) => {
  const done = guard(page);
  await start(page, 'Sami');
  await group(page, 'Desert camp', ['Nora']);
  await context.setOffline(true);
  await page.getByTestId('add').click();
  await amount(page, '80');
  await page.getByTestId('title').fill('Firewood');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('toast')).toContainText('Saved on this device');
  await expect(page.getByTestId('expense-row')).toHaveCount(1);
  await expect(page.getByTestId('pending')).toContainText('1 waiting to sync');
  await expect(page.getByTestId('my-balance')).toHaveText('AED 40.00');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p06-offline.png` });
  await context.setOffline(false);
  await expect(page.getByTestId('pending')).toHaveCount(0, { timeout: 15_000 });
  await page.reload();
  await expect(page.getByTestId('expense-row')).toHaveCount(1);
  await expect(page.getByTestId('my-balance')).toHaveText('AED 40.00');
  done();
});

test('Plus: recurring bills, items, spending, CSV, reminders, looks', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Lina');
  await page.getByTestId('tpl-flat').click();
  await expect(page.getByTestId('group-name')).toHaveValue('Our flat');
  await group(page, 'Our flat', ['Mona', 'Huda']);
  await plus(page);
  await page.goBack();
  await expect(page.getByTestId('group')).toBeVisible();

  await page.getByTestId('add').click();
  await amount(page, '3000');
  await page.getByTestId('title').fill('Rent');
  await page.getByTestId('details').click();
  await page.getByTestId('every-month').click();
  await expect(page.getByTestId('details-summary')).toContainText('Every month');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('toast')).toContainText('It will repeat');

  // A receipt by item: 100 with a 40 burger for me and 45 shared, 15 tax and service by item.
  await page.getByTestId('add').click();
  await amount(page, '100');
  await page.getByTestId('title').fill('Dinner');
  await page.getByTestId('details').click();
  await page.getByTestId('mode-items').click();
  await page.getByTestId('item-price').first().fill('45');
  await page.getByTestId('add-item').click();
  await page.getByTestId('item-price').nth(1).fill('40');
  const second = page.getByTestId('receipt').locator('> div').nth(1);
  await second.getByRole('button', { name: 'Mona' }).click();
  await second.getByRole('button', { name: 'Huda' }).click();
  await expect(page.getByTestId('receipt')).toContainText('AED 15.00 tax and service');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p07-items.png` });
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-row')).toHaveCount(2);

  await page.getByTestId('group-more').click();
  await expect(page.getByTestId('recurring-list')).toContainText('Rent');
  await page.getByTestId('weekly-reminders').click();
  await expect(page.getByTestId('weekly-reminders')).toHaveAttribute('aria-checked', 'true');
  await page.getByTestId('open-spending').click();
  await expect(page.getByTestId('spending')).toContainText('Bills');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p08-options.png` });
  await a11y(page, 'group options');
  const [csv] = await Promise.all([page.waitForEvent('download'), page.getByTestId('export-csv').click()]);
  expect(csv.suggestedFilename()).toBe('Our flat.csv');
  await page.keyboard.press('Escape');

  await page.goto('/settings');
  await page.getByTestId('look-night').click();
  await expect(page.locator('html')).toHaveAttribute('data-look', 'night');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p09-night.png` });
  await a11y(page, 'night look');
  done();
});

test('money circles: turns, who paid, the card on the group', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Rami');
  await group(page, 'Family', ['Dana', 'Zaid']);
  await page.getByTestId('group-more').click();
  await page.getByTestId('new-circle').click();
  await page.getByTestId('circle-name').fill('Family circle');
  await page.getByTestId('circle-amount').fill('500');
  await page.getByTestId('create-circle').click();
  await expect(page.getByTestId('circle-sheet')).toBeVisible();
  await expect(page.getByTestId('circle-sheet')).toContainText('Pot AED 1,500.00');
  await page.getByTestId('circle-member').first().click();
  await expect(page.getByTestId('circle-member').first()).toHaveAttribute('aria-pressed', 'true');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/p10-circle.png` });
  await a11y(page, 'circle');
  await page.keyboard.press('Escape');
  await expect(page.getByTestId('circle-card')).toContainText('1 of 2 paid');
  done();
});

test('install and app links: manifest, association files, privacy in Arabic', async ({ page, request }) => {
  const m = await (await request.get('/manifest.webmanifest')).json();
  expect(m.display).toBe('standalone');
  expect(m.icons.some((i: { purpose: string }) => i.purpose === 'maskable')).toBe(true);
  expect((await request.get('/.well-known/apple-app-site-association')).headers()['content-type']).toContain('application/json');
  expect(await (await request.get('/.well-known/assetlinks.json')).json()).toEqual([]);
  await page.goto('/');
  await page.getByTestId('lang-ar').click();
  await page.goto('/privacy');
  await expect(page.getByRole('heading', { name: 'ما نحتفظ به' })).toBeVisible();
  await a11y(page, 'privacy');
});

test('large text: at 200% nothing spills sideways on the main screens', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Abdulrahman');
  await group(page, 'Weekend in Hatta with the whole family', ['Mohammed', 'Fatima']);
  await page.getByTestId('add').click();
  await amount(page, '1250');
  await page.getByTestId('save-expense').click();
  const big = async (where: string) => {
    await page.evaluate(() => (document.documentElement.style.fontSize = '200%'));
    await still(page);
    const over = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(over, `${where} is ${over}px wider than the screen`).toBeLessThanOrEqual(1);
    await page.screenshot({ path: `${SHOTS}/p11-large-${where}.png` });
  };
  await big('group');
  await page.getByTestId('tab-settle').click();
  await big('settle');
  await page.getByTestId('add').click();
  await page.getByTestId('details').click();
  await big('add');
  await page.keyboard.press('Escape');
  await page.goto('/settings');
  await big('settings');
  done();
});
