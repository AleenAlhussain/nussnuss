import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Browser, type Page } from '@playwright/test';

/**
 * The UI/UX inspection plan, checked end to end: the standards fixes (phase 1), Home, people and Activity
 * (phase 2), identity and touch (phase 3), and Plus and shortcuts (phase 4).
 */
const SHOTS = process.env.SHOTS_DIR ?? 'test-results/screens';

function guard(page: Page) {
  const problems: string[] = [];
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error' && !/favicon|ERR_TUNNEL|ERR_INTERNET_DISCONNECTED|Failed to fetch|net::ERR|status of 40[1349]/.test(m.text())) problems.push(`console: ${m.text()}`);
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
async function group(page: Page, name: string, people: string[], opts: { currency?: string; cover?: string } = {}) {
  if (!(await page.getByTestId('new-group-sheet').isVisible())) {
    await page.goto('/');
    await page.getByTestId('add').click();
  }
  await page.getByTestId('group-name').fill(name);
  if (opts.cover) await page.getByTestId(`cover-${opts.cover}`).click();
  if (opts.currency) {
    await page.getByTestId('group-currency').click();
    await page.getByTestId(`currency-${opts.currency}`).click();
  }
  for (const p of people) {
    await page.getByTestId('person-name').fill(p);
    await page.getByTestId('add-person').click();
  }
  await page.getByTestId('create-group').click();
  await expect(page.getByTestId('group')).toBeVisible();
}
async function expense(page: Page, digits: string, title: string) {
  await page.getByTestId('add').click();
  await expect(page.getByTestId('expense-sheet')).toBeVisible();
  for (const d of digits) await page.getByRole('button', { name: d === '.' ? 'Decimal point' : d, exact: true }).click();
  await page.getByTestId('title').fill(title);
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
}
/** A friend joins from the invite link in their own browser. */
async function friendJoins(page: Page, browser: Browser, pickIndex: number) {
  await page.getByTestId('share').click();
  const link = (await page.getByTestId('invite-qr').getAttribute('data-text'))!;
  await page.keyboard.press('Escape');
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const fp = await ctx.newPage();
  await fp.goto(link);
  await fp.getByTestId('who').nth(pickIndex).check();
  await fp.getByTestId('join-btn').click();
  await expect(fp.getByTestId('group')).toBeVisible();
  return { ctx, fp, link };
}
const color = (page: Page, sel: string, prop = 'color') => page.locator(sel).first().evaluate((el, p) => getComputedStyle(el).getPropertyValue(p), prop);
const rgbOfVar = (page: Page, name: string) =>
  page.evaluate((n) => {
    const d = document.createElement('div');
    d.style.color = `var(${n})`;
    document.body.append(d);
    const c = getComputedStyle(d).color;
    d.remove();
    return c;
  }, name);

test('phase 1: field edges, owing not red, scroll edge, transfers, glossary, currency picker', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Rami');
  // Text fields have a visible edge at rest (the edge token) and a 2 pt accent outline while typing.
  const edge = await rgbOfVar(page, '--nn-edge');
  const accent = await rgbOfVar(page, '--nn-accent');
  expect(await page.getByTestId('person-name').evaluate((el) => getComputedStyle(el).boxShadow)).toContain(edge);
  await page.getByTestId('person-name').focus();
  // (after the 120 ms transition settles)
  await expect.poll(() => page.getByTestId('person-name').evaluate((el) => getComputedStyle(el).boxShadow)).toBe(`${accent} 0px 0px 0px 2px inset`);
  // The same currency picker as the phone app: a searchable list in the sheet.
  await page.getByTestId('group-currency').click();
  await expect(page.getByTestId('currency-list')).toBeVisible();
  await page.getByTestId('currency-search').fill('omani');
  await expect(page.getByTestId('currency-OMR')).toBeVisible();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i01-currency-picker.png` });
  await a11y(page, 'currency picker');
  await page.getByTestId('currency-OMR').click();
  await expect(page.getByTestId('group-currency')).toHaveAttribute('data-value', 'OMR');
  await page.getByTestId('group-name').fill('Flat 3');
  await page.getByTestId('person-name').fill('Nadia');
  await page.getByTestId('add-person').click();
  await page.getByTestId('create-group').click();
  await expect(page.getByTestId('group')).toBeVisible();

  // Nadia pays, so I owe: shown in the text colour, not red.
  await page.getByTestId('add').click();
  for (const d of '30') await page.getByRole('button', { name: d, exact: true }).click();
  await page.getByTestId('title').fill('Groceries');
  await page.getByTestId('details').click();
  await page.getByTestId('payer').nth(1).click();
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
  const text = await rgbOfVar(page, '--nn-text');
  expect(await color(page, '[data-testid="my-balance"]')).toBe(text);
  await page.getByTestId('tab-home').click();
  await expect(page.getByTestId('group-balance')).toHaveText(/OMR\s15\.000/);
  expect(await color(page, '[data-testid="group-balance"]')).toBe(text);

  // Transfers: names on the first line, the amount on its own line below.
  await page.getByTestId('group-card').click();
  await page.getByTestId('tab-settle').click();
  const names = await page.getByTestId('transfer-names').boundingBox();
  const amount = await page.getByTestId('transfer-amount').boundingBox();
  expect(amount!.y).toBeGreaterThanOrEqual(names!.y + names!.height - 1);

  // The scroll edge: once the title scrolls under the bar, a soft band fades the content out.
  await page.evaluate(() => {
    document.querySelector('main')!.style.minHeight = '3000px';
    window.scrollTo(0, 400);
  });
  await expect(page.locator('header[data-collapsed]')).toBeVisible();
  await expect.poll(() => page.getByTestId('scroll-edge').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  expect(await page.getByTestId('scroll-edge').evaluate((el) => getComputedStyle(el).backgroundImage)).toContain('linear-gradient');

  // One glossary: Home, Activity, You; the first look is "Default".
  await expect(page.getByTestId('tab-home')).toHaveAccessibleName('Home');
  await expect(page.getByTestId('tab-activity')).toHaveAccessibleName(/^Activity/);
  await expect(page.getByTestId('tab-you')).toHaveAccessibleName('You');
  await page.getByTestId('tab-you').click();
  await expect(page.getByTestId('look-default')).toContainText('Default');
  await page.goto('/settings');
  await expect(page).toHaveURL(/\/you$/);
  done();
});

test('phase 1: at 200% text the bars keep their size, hold shows the large label, amounts stay on one line', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Abdulrahman');
  await group(page, 'Weekend in Hatta with the whole family', ['Mohammed', 'Fatima']);
  await expense(page, '1250', 'Chalet');
  const bar = async () => (await page.getByTestId('tab-bar').boundingBox())!;
  const add = async () => (await page.getByTestId('add').boundingBox())!;
  const before = { bar: await bar(), add: await add() };
  await page.evaluate(() => (document.documentElement.style.fontSize = '200%'));
  await still(page);
  const after = { bar: await bar(), add: await add() };
  expect(Math.abs(after.bar.height - before.bar.height)).toBeLessThanOrEqual(2);
  expect(Math.abs(after.add.width - before.add.width)).toBeLessThanOrEqual(2);
  // The balance shrinks to fit one line instead of breaking "AED / 833.33".
  const hero = page.locator('[data-vt="group-card"] .t-amount-hero');
  const h = await hero.evaluate((el) => ({ h: el.getBoundingClientRect().height, line: parseFloat(getComputedStyle(el).lineHeight) || parseFloat(getComputedStyle(el).fontSize) * 1.1 }));
  expect(h.h).toBeLessThan(h.line * 1.6);
  // Press and hold a tab: its name, large, in the middle of the screen.
  const tab = page.getByTestId('tab-activity');
  const box = (await tab.boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await expect(page.getByTestId('large-content')).toContainText('Activity');
  await page.screenshot({ path: `${SHOTS}/i02-large-content.png` });
  await page.mouse.up();
  await expect(page.getByTestId('large-content')).toBeHidden();
  // Letting go after the viewer showed doesn't switch tabs.
  await expect(page.getByTestId('group')).toBeVisible();
  const over = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(over).toBeLessThanOrEqual(1);
  done();
});

test('phase 2: Home shows where you stand, the next step and people; a person view settles everything', async ({ page, browser }) => {
  const done = guard(page);
  await start(page, 'Talal');
  await group(page, 'Salalah trip', ['Sara', 'Omar'], { cover: 'beach' });
  await expense(page, '300', 'Hotel');
  await page.getByTestId('tab-home').click();
  await expect(page.getByTestId('overall')).toContainText('Overall, you get back');
  await expect(page.getByTestId('overall-amount')).toHaveText(/AED\s200\.00/);
  await expect(page.getByTestId('next-step')).toHaveAttribute('data-kind', 'collect');
  await expect(page.getByTestId('person')).toHaveCount(2);
  await expect(page.getByTestId('group-card')).toHaveAttribute('href', /\/g\//);
  await expect(page.getByTestId('group-card').getByTestId('cover')).toHaveAttribute('data-cover', /^beach:/);
  await expect(page.getByTestId('group-activity')).toContainText('You added Hotel');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i03-home.png` });
  await a11y(page, 'home');

  // The next step's "Mark as paid" settles that one pair, with Undo.
  await page.getByTestId('next-mark-paid').click();
  await expect(page.getByTestId('toast')).toContainText('Marked as paid');
  await expect(page.getByTestId('overall-amount')).toHaveText(/AED\s100\.00/);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(page.getByTestId('overall-amount')).toHaveText(/AED\s200\.00/);

  // A person across groups: Settle everything, with Undo.
  await page.getByTestId('person').first().click();
  await expect(page.getByTestId('person-screen')).toBeVisible();
  await expect(page.getByTestId('person-amount')).toHaveText(/AED\s100\.00/);
  await expect(page.getByTestId('between-you')).toContainText('Hotel');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i04-person.png` });
  await a11y(page, 'person');
  await page.getByTestId('settle-everything').click();
  await expect(page.getByTestId('settle-everything-sheet')).toBeVisible();
  await page.getByTestId('confirm-settle-everything').click();
  await expect(page.getByTestId('toast')).toContainText('Settled with');
  await expect(page.getByTestId('settle-everything')).toBeHidden();
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(page.getByTestId('settle-everything')).toBeVisible();

  // People: see all.
  await page.getByTestId('tab-home').click();
  await page.getByTestId('people-all').click();
  await expect(page.getByTestId('people-row')).toHaveCount(2);

  // Activity: a friend adds something; the tab shows a badge; the row says who and your share.
  await page.getByTestId('tab-home').click();
  await page.getByTestId('group-card').click();
  const { ctx, fp } = await friendJoins(page, browser, 1);
  await fp.getByTestId('add').click();
  for (const d of '45') await fp.getByRole('button', { name: d, exact: true }).click();
  await fp.getByTestId('title').fill('Lunch at the souq');
  await fp.getByTestId('save-expense').click();
  await expect(fp.getByTestId('expense-sheet')).toBeHidden();
  await ctx.close();
  await page.getByTestId('tab-home').click();
  await expect(page).toHaveURL(/:3000\/$/);
  await page.reload();
  await expect(page.getByTestId('activity-badge')).toBeVisible();
  await page.getByTestId('tab-activity').click();
  await expect(page.getByTestId('activity-row').first()).toContainText('Sara added Lunch at the souq');
  // Sara added it; the payer defaulted to the last payer (Talal), so Talal lent the other two their shares.
  await expect(page.getByTestId('activity-row').first()).toContainText('you lent AED 30.00');
  await expect(page.getByTestId('unread-dot').first()).toBeVisible();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i05-activity.png` });
  await a11y(page, 'activity');
  await page.getByTestId('mark-all-read').click();
  await expect(page.getByTestId('unread-dot')).toHaveCount(0);
  await expect(page.getByTestId('activity-badge')).toHaveCount(0);
  done();
});

test('phase 2 and 3: You with a profile look, covers, swipe and hold on rows, one-tap category, a repeating bill', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Lina');
  await page.getByTestId('sheet-close').click();
  await expect(page.getByTestId('new-group-sheet')).toBeHidden();
  // You: profile first; an emoji on a tone, shown everywhere.
  await page.getByTestId('tab-you').click();
  await page.getByTestId('profile-row').click();
  await page.getByTestId('avatar-kind-emoji').click();
  await page.getByTestId('avatar-emoji').nth(4).click();
  await page.getByTestId('avatar-tone-mint').click();
  await expect(page.getByTestId('profile-preview').locator('[data-avatar="emoji"]')).toBeVisible();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i06-profile.png` });
  await a11y(page, 'profile');
  await page.getByTestId('save-profile').click();
  await expect(page.getByTestId('profile-row').locator('[data-avatar="emoji"]')).toBeVisible();
  await expect(page.getByTestId('appearance-preview')).toBeVisible();
  await a11y(page, 'you');

  await group(page, 'Office lunches', ['Mona', 'Huda'], { cover: 'work' });
  await expense(page, '45', 'Shawarma');
  await expense(page, '12', 'Fuel');
  // "Fuel" is transport, not a tag.
  await expect(page.getByTestId('category-tile').first().locator('[data-category]')).toHaveAttribute('data-category', 'transport');

  // One tap on the tile changes the category.
  await page.getByTestId('category-tile').first().click();
  await page.getByTestId('pick-cat-bills').click();
  await expect(page.getByTestId('toast')).toContainText('Category changed');
  await expect(page.getByTestId('category-tile').first().locator('[data-category]')).toHaveAttribute('data-category', 'bills');

  // Swipe a row to reveal Duplicate and Delete (once the toast has gone, so it isn't under the finger).
  await expect(page.getByTestId('toast')).toBeHidden({ timeout: 6000 });
  const row = page.getByTestId('expense-row-wrap').first();
  const b = (await row.boundingBox())!;
  await page.mouse.move(b.x + b.width - 20, b.y + b.height / 2);
  await page.mouse.down();
  await page.mouse.move(b.x + b.width - 120, b.y + b.height / 2, { steps: 8 });
  await page.mouse.move(b.x + b.width - 200, b.y + b.height / 2, { steps: 8 });
  await page.mouse.up();
  await expect(row).toHaveAttribute('data-open', 'true');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i07-swipe.png` });
  await page.getByTestId('swipe-duplicate').first().click();
  await expect(page.getByTestId('toast')).toContainText('Duplicated');
  await expect(page.getByTestId('expense-row')).toHaveCount(3);

  // Press and hold a row: a preview and the same actions.
  const r2 = (await page.getByTestId('expense-row').nth(1).boundingBox())!;
  await page.mouse.move(r2.x + 40, r2.y + r2.height / 2);
  await page.mouse.down();
  await expect(page.getByTestId('context-menu')).toBeVisible();
  await page.mouse.up();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i08-menu.png` });
  await a11y(page, 'row menu');
  await page.getByTestId('menu-delete').click();
  await expect(page.getByTestId('toast').last()).toContainText('Expense deleted');
  await expect(page.getByTestId('expense-row')).toHaveCount(2);

  // Cover and name, changed from the group options.
  await page.getByTestId('group-more').click();
  await page.getByTestId('edit-cover').click();
  await page.getByTestId('cover-coffee').click();
  await page.getByTestId('cover-tone-rose').click();
  await page.getByTestId('save-cover').click();
  await expect(page.getByTestId('group-cover')).toHaveAttribute('data-cover', 'coffee:rose');
  // Repeating bills: an action and an empty state, behind Plus.
  await expect(page.getByTestId('no-repeating')).toBeVisible();
  await page.getByTestId('add-repeating').click();
  await expect(page.getByTestId('paywall')).toBeVisible();
  await expect(page.getByTestId('plus-benefits').locator('li')).toHaveCount(3);
  await expect(page.getByTestId('plan-cards').getByRole('radio')).toHaveCount(3);
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i09-plus.png` });
  await a11y(page, 'plus');
  done();
});

test('phase 3: Equally or Unequally, drag a share onto someone; invite with QR and a short link', async ({ page, browser }) => {
  const done = guard(page);
  await start(page, 'Huda');
  await group(page, 'Dinner out', ['Sami', 'Rua']);
  await page.getByTestId('add').click();
  for (const d of '60') await page.getByRole('button', { name: d, exact: true }).click();
  await page.getByTestId('title').fill('Mandi');
  await page.getByTestId('details').click();
  // Two choices, not five; the ways to split unevenly sit behind Unequally.
  await expect(page.getByTestId('split-how').getByRole('tab')).toHaveCount(2);
  await expect(page.getByTestId('mode')).toHaveCount(0);
  await page.getByTestId('split-how-unequal').click();
  await expect(page.getByTestId('mode').getByRole('tab')).toHaveCount(4);
  await expect(page.getByTestId('drag-shares')).toBeVisible();
  await page.getByTestId('drag-shares').scrollIntoViewIfNeeded();
  // Measure once the sheet has stopped moving (it animates open and may still be scrolling).
  await still(page);
  // Drag "+1 share" onto Sami: Sami now has two shares (30 of 60), the buttons still work too.
  const token = (await page.getByTestId('share-token').boundingBox())!;
  const target = (await page.getByTestId('share-drop').nth(1).boundingBox())!;
  await page.mouse.move(token.x + token.width / 2, token.y + token.height / 2);
  await page.mouse.down();
  await page.mouse.move(target.x + target.width / 2, target.y + target.height / 2, { steps: 12 });
  await expect(page.getByTestId('share-drop').nth(1)).toHaveClass(/ring-accent/);
  await page.mouse.up();
  await expect(page.getByTestId('share-count').nth(1)).toHaveText('2');
  await expect(page.getByTestId('split-legend')).toContainText('Sami');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i10-split.png` });
  await a11y(page, 'split');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-sheet')).toBeHidden();

  // Invite: a preview of the group, a QR code and a short readable link.
  await page.getByTestId('share').click();
  await expect(page.getByTestId('invite-preview')).toContainText('Dinner out');
  await expect(page.getByTestId('invite-qr')).toBeVisible();
  await expect(page.getByTestId('invite-link')).toHaveText(/\/j\/[2-9a-hjkmnp-z]{10}$/);
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i11-invite.png` });
  await a11y(page, 'invite');
  const link = (await page.getByTestId('invite-qr').getAttribute('data-text'))!;
  await page.keyboard.press('Escape');
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const fp = await ctx.newPage();
  await fp.goto(link);
  await expect(fp.getByTestId('join-meta')).toContainText('Huda invited you');
  await expect(fp.getByTestId('join-cover')).toBeVisible();
  await still(fp);
  await fp.screenshot({ path: `${SHOTS}/i12-join.png` });
  await a11y(fp, 'join');
  await ctx.close();

  // Settle up: the swipe hint shows the first time only.
  await page.getByTestId('tab-settle').click();
  await expect(page.getByTestId('swipe-hint')).toHaveAttribute('data-shown', 'true');
  await page.getByTestId('tab-expenses').click();
  await page.reload();
  await page.getByTestId('tab-settle').click();
  await expect(page.getByTestId('swipe-hint')).not.toHaveAttribute('data-shown', 'true');
  done();
});

test('phase 3 and 4: welcome cards, empty states, shortcuts, recovery code to Passwords', async ({ page, request }) => {
  const done = guard(page);
  await page.goto('/');
  await expect(page.getByTestId('welcome-cards').locator('li')).toHaveCount(3);
  await page.getByTestId('name').fill('Maya');
  await page.getByTestId('start').click();
  await expect(page.getByTestId('new-group-sheet')).toBeVisible();
  await page.getByTestId('sheet-close').click();
  await expect(page.getByTestId('new-group-sheet')).toBeHidden();
  // An empty Home: the coin halves apart, one line, one button.
  await expect(page.getByTestId('home-empty').getByTestId('apart-coin')).toBeVisible();
  await expect(page.getByTestId('new-group')).toHaveText('Start a group');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/i13-empty.png` });
  // The home-screen shortcuts.
  const m = await (await request.get('/manifest.webmanifest')).json();
  expect(m.shortcuts.map((s: { url: string }) => s.url)).toEqual(['/?add=1', '/activity']);
  // Recovery code: Save to Passwords where the browser offers it.
  await page.getByTestId('tab-you').click();
  await page.getByTestId('make-recovery').click();
  await expect(page.getByTestId('code-sheet')).toBeVisible();
  await expect(page.getByTestId('save-to-passwords')).toBeVisible();
  done();
});
