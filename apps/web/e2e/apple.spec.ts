import { expect, test, type Page } from '@playwright/test';

/**
 * The Apple-inspired UI plan, its Glass, Navigation and Motion & haptics sections:
 * three glass levels, solid where glass would sit on glass, tabs that remember where you were,
 * search, the sheet stepping the page back, pull to refresh, the swipe threshold, the error shake.
 */
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
async function start(page: Page, name: string) {
  await page.goto('/');
  await page.getByTestId('name').fill(name);
  await page.getByTestId('start').click();
  await expect(page.getByTestId('new-group-sheet')).toBeVisible();
}
async function group(page: Page, name: string, people: string[]) {
  if (!(await page.getByTestId('new-group-sheet').isVisible())) await page.getByTestId('add').click();
  await page.getByTestId('group-name').fill(name);
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
  for (const d of digits) await page.getByRole('button', { name: d, exact: true }).click();
  await page.getByTestId('title').fill(title);
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
}
const rootVar = (page: Page, name: string) => page.evaluate((n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), name);
const home = /:3000\/$/;

test('glass: Clear, Tinted (the default) and Solid; solid with Increase Contrast; the toast is solid over a sheet', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Rana');
  await group(page, 'Flat 4', ['Mira']);
  const html = page.locator('html');
  await expect(html).not.toHaveAttribute('data-glass', /.+/);
  const tinted = await rootVar(page, '--nn-glass-fill');
  expect(tinted).toContain('color-mix');

  await page.getByTestId('tab-you').click();
  await page.getByTestId('settings-glass-clear').click();
  await expect(html).toHaveAttribute('data-glass', 'clear');
  const clear = await rootVar(page, '--nn-glass-fill');
  await page.getByTestId('settings-glass-frosted').click();
  await expect(html).toHaveAttribute('data-glass', 'frosted');
  const solid = await rootVar(page, '--nn-glass-fill');
  expect(new Set([tinted, clear, solid]).size).toBe(3);
  await page.getByTestId('settings-glass-tinted').click();
  await expect(html).not.toHaveAttribute('data-glass', /.+/);

  // Increase Contrast makes every glass surface solid, whatever was picked.
  await page.getByTestId('settings-glass-clear').click();
  await page.emulateMedia({ contrast: 'more' });
  expect(await rootVar(page, '--nn-glass-fill')).toBe(solid);
  await page.emulateMedia({ contrast: 'no-preference' });
  expect(await rootVar(page, '--nn-glass-fill')).toBe(clear);
  await page.getByTestId('settings-glass-tinted').click();

  // The edge: a light hairline that fades from the top-left corner.
  expect(await rootVar(page, '--nn-glass-edge')).toContain('linear-gradient');

  // Glass never sits on glass: a toast shown over an open sheet is solid.
  await page.getByTestId('tab-home').click();
  await expect(page.getByTestId('group')).toBeVisible();
  await page.getByTestId('add').click();
  await expect(html).toHaveAttribute('data-sheet', /.+/);
  const filter = await page.evaluate(() => {
    const el = document.createElement('div');
    el.className = 'glass toast';
    document.body.append(el);
    const f = getComputedStyle(el).backdropFilter;
    el.remove();
    return f;
  });
  expect(filter).toBe('none');
  done();
});

test('navigation: tabs remember the screen, the active tab goes to the top then back to its start', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Nour');
  await group(page, 'Dubai trip', ['Ali', 'Huda']);
  const groupUrl = page.url();

  await page.getByTestId('tab-you').click();
  await expect(page).toHaveURL(/\/you$/);
  // Back to Groups lands on the group you were in, not the list.
  await page.getByTestId('tab-home').click();
  await expect(page).toHaveURL(groupUrl);
  await expect(page.getByTestId('group')).toBeVisible();
  // Tapping the tab you are on, at the top, goes to its first screen.
  await page.getByTestId('tab-home').click();
  await expect(page).toHaveURL(home);

  // Scrolled down, the first tap goes to the top and stays on the screen.
  await page.getByTestId('tab-you').click();
  await expect(page.getByTestId('settings')).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, 700));
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(100);
  await page.getByTestId('tab-you').click();
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeLessThan(5);
  await expect(page).toHaveURL(/\/you$/);
  done();
});

test('search: groups by name, people and expenses; inside a group by title, payer or amount', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Sami');
  await group(page, 'Flat 9', ['Mira', 'Omar']);
  await expense(page, '30', 'Taxi');
  for (const [d, title] of [
    ['12', 'Coffee'],
    ['48', 'Groceries'],
    ['20', 'Internet'],
    ['75', 'Dinner'],
  ] as const)
    await expense(page, d, title);
  await expect(page.getByTestId('expense-row')).toHaveCount(5);

  // In the group: shown with five or more expenses.
  const search = page.getByTestId('expense-search');
  await expect(search).toBeVisible();
  await search.fill('tax');
  await expect(page.getByTestId('expense-row')).toHaveCount(1);
  await expect(page.getByTestId('expense-row')).toContainText('Taxi');
  await search.fill('75');
  await expect(page.getByTestId('expense-row')).toHaveCount(1);
  await expect(page.getByTestId('expense-row')).toContainText('Dinner');
  await search.fill('Sami');
  await expect(page.getByTestId('expense-row')).toHaveCount(5);
  await search.fill('zzz');
  await expect(page.getByTestId('expense-row')).toHaveCount(0);
  await expect(page.getByText('No results for “zzz”')).toBeVisible();
  await search.fill('');

  // On the groups screen.
  await page.getByTestId('tab-home').click();
  await expect(page).toHaveURL(home);
  await group(page, 'Beach day', ['Lina']);
  await page.getByTestId('tab-home').click();
  await expect(page).toHaveURL(home);
  await expect(page.getByTestId('group-card')).toHaveCount(2);
  const find = page.getByTestId('search');
  await find.fill('lina');
  await expect(page.getByTestId('search-results').getByTestId('group-card')).toHaveCount(1);
  await expect(page.getByTestId('search-results')).toContainText('Beach day');
  await find.fill('grocer');
  await expect(page.getByTestId('search-expense')).toHaveCount(1);
  await expect(page.getByTestId('search-expense')).toContainText('Flat 9');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/a01-search.png` });
  await page.getByTestId('search-expense').click();
  await expect(page.getByTestId('group')).toBeVisible();

  // The search that led somewhere comes back as a recent search.
  await page.getByTestId('tab-home').click();
  await expect(page).toHaveURL(home);
  await page.getByTestId('search').focus();
  await expect(page.getByTestId('recent-search')).toHaveText(['grocer']);
  await page.getByTestId('recent-search').click();
  await expect(page.getByTestId('search')).toHaveValue('grocer');
  await expect(page.getByTestId('search-expense')).toHaveCount(1);
  done();
});

test('motion: the sheet steps the page back, a failed save shakes, pull to refresh, the swipe threshold', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Hala');
  await group(page, 'Lunch club', ['Reem']);
  const html = page.locator('html');

  // The sheet: the page behind steps back to 96%.
  await page.getByTestId('add').click();
  await expect(html).toHaveAttribute('data-sheet', /.+/);
  await expect.poll(() => page.evaluate(() => getComputedStyle(document.querySelector('main')!).transform)).toMatch(/^matrix\(0\.96/);
  // Saving with no amount: the message and the amount shake.
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-error')).toHaveClass(/shake/);
  await expect(page.getByTestId('amount-pad')).toHaveClass(/shake/);
  await page.getByTestId('sheet-close').click();
  await expect(html).not.toHaveAttribute('data-sheet', /.+/);
  await expect.poll(() => page.evaluate(() => getComputedStyle(document.querySelector('main')!).transform)).toBe('none');

  await expense(page, '60', 'Mandi');

  // Pull to refresh: pull down from the top, the coin spins while the group reloads.
  let reloads = 0;
  await page.route(/:4000\/groups\/[^/]+$/, async (r) => {
    reloads++;
    await new Promise((res) => setTimeout(res, 600));
    await r.continue();
  });
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.evaluate(async () => {
    const touch = (y: number) => [new Touch({ identifier: 1, target: document.body, clientX: 180, clientY: y })];
    window.dispatchEvent(new TouchEvent('touchstart', { touches: touch(120) }));
    for (let y = 140; y <= 320; y += 20) {
      window.dispatchEvent(new TouchEvent('touchmove', { touches: touch(y) }));
      await new Promise((r) => setTimeout(r, 16));
    }
    window.dispatchEvent(new TouchEvent('touchend', { touches: [] }));
  });
  await expect(page.getByTestId('pull-refresh')).toHaveAttribute('data-busy', 'true');
  await expect(page.getByTestId('pull-refresh')).not.toHaveAttribute('data-busy', /.+/);
  expect(reloads).toBeGreaterThan(0);
  await page.unroute(/:4000\/groups\/[^/]+$/);

  // Swipe to mark paid: past the threshold the tick pops; letting go marks it paid with a drawn check.
  await page.getByTestId('tab-settle').click();
  const card = page.getByTestId('transfer').first();
  await expect(card).toBeVisible();
  const box = (await card.boundingBox())!;
  const y = box.y + 30;
  await page.mouse.move(box.x + 30, y);
  await page.mouse.down();
  for (let x = 40; x <= 220; x += 20) await page.mouse.move(box.x + x, y);
  await expect(page.getByTestId('swipe-tick')).toHaveAttribute('data-armed', 'true');
  await page.mouse.up();
  await expect(page.getByTestId('toast')).toContainText('Marked as paid');
  await expect(page.getByTestId('toast').getByTestId('draw-check')).toBeVisible();
  done();
});

test('reduce motion: no step back, no shake, the group card opens without a zoom', async ({ page }) => {
  const done = guard(page);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await start(page, 'Yara');
  await group(page, 'Gym', ['Dana']);
  await page.getByTestId('add').click();
  await expect(page.locator('html')).toHaveAttribute('data-sheet', /.+/);
  expect(await page.evaluate(() => getComputedStyle(document.querySelector('main')!).transform)).toBe('none');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-error')).toBeVisible();
  expect(await page.getByTestId('expense-error').evaluate((el) => getComputedStyle(el).animationName)).toBe('none');
  await page.getByTestId('sheet-close').click();

  await page.getByTestId('tab-home').click();
  await expect(page).toHaveURL(home);
  await page.getByTestId('group-card').first().click();
  await expect(page.getByTestId('group')).toBeVisible();
  done();
});
