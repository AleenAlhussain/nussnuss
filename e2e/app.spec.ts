import { test, expect, Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const SHOTS = 'replica/clone-screens';

/** Fail the test on console errors, uncaught exceptions and 5xx responses. */
function guard(page: Page) {
  const problems: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('response', (r) => {
    if (r.status() >= 500) problems.push(`HTTP ${r.status()} ${r.url()}`);
  });
  return () => expect(problems, problems.join('\n')).toEqual([]);
}

async function a11y(page: Page, name: string) {
  const r = await new AxeBuilder({ page }).disableRules(['region', 'landmark-one-main', 'page-has-heading-one']).analyze();
  const bad = r.violations.filter((v) => v.impact === 'critical' || v.impact === 'serious');
  expect(bad.map((v) => `${name}: ${v.id} — ${v.help} (${v.nodes.length})`)).toEqual([]);
}

async function onboard(page: Page, name = 'Talal') {
  await page.goto('./');
  await expect(page.getByTestId('screen-welcome')).toBeVisible();
  await page.getByTestId('name').fill(name);
  await page.getByTestId('start').click();
  await expect(page.getByTestId('screen-home')).toBeVisible();
}

async function createGroup(page: Page, groupName: string, others: string[]) {
  await page.getByTestId('new-group').first().click();
  await page.getByTestId('group-name').fill(groupName);
  for (const n of others) {
    await page.getByTestId('member-name').fill(n);
    await page.getByTestId('add-member').click();
  }
  await page.getByTestId('save-group').click();
  await expect(page.getByTestId('screen-group')).toBeVisible();
}

async function addExpense(page: Page, amount: string, title: string) {
  await page.getByTestId('add-expense').click();
  await page.getByTestId('amount').fill(amount);
  await page.getByTestId('title').fill(title);
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('screen-group')).toBeVisible();
}

test.describe('NussNuss', () => {
  test('F01 first run: name is required, then home is empty', async ({ page }) => {
    const done = guard(page);
    await page.goto('./');
    await page.screenshot({ path: `${SHOTS}/S01-welcome.png` });
    await a11y(page, 'S01');
    await page.getByTestId('start').click();
    await expect(page.getByText('So your friends know who you are')).toBeVisible();
    await page.getByTestId('name').fill('Talal');
    await page.getByTestId('start').click();
    await expect(page.getByText('No groups yet')).toBeVisible();
    await page.screenshot({ path: `${SHOTS}/S02-home-empty.png` });
    done();
  });

  test('F02–F05 group, expenses, balances, settling, undo', async ({ page }) => {
    const done = guard(page);
    await onboard(page);
    // validation: a group needs a name and two people
    await page.getByTestId('new-group').first().click();
    await page.getByTestId('save-group').click();
    await expect(page.getByText('Give the group a name')).toBeVisible();
    await expect(page.getByText('Add at least two people')).toBeVisible();
    await page.getByTestId('group-name').fill('Flat 12');
    await expect(page.getByText('Give the group a name')).toHaveCount(0);
    for (const n of ['Sara', 'Omar']) {
      await page.getByTestId('member-name').fill(n);
      await page.getByTestId('add-member').click();
    }
    await page.getByTestId('member-name').fill('sara');
    await page.getByTestId('add-member').click();
    await expect(page.getByText('Two people have the same name')).toBeVisible();
    await page.getByTestId('member-name').fill('');
    await page.screenshot({ path: `${SHOTS}/S03-group-edit.png` });
    await page.getByTestId('save-group').click();
    await expect(page.getByTestId('screen-group')).toBeVisible();
    await expect(page.getByText('Nothing here yet')).toBeVisible();

    // equal split: 300 between 3
    await addExpense(page, '300', 'Groceries');
    await expect(page.getByTestId('group-total')).toHaveText('AED 300.00');
    await expect(page.getByTestId('my-balance')).toHaveText('You are owed AED 200.00');

    // empty submit shows errors, nothing is saved
    await page.getByTestId('add-expense').click();
    await page.getByTestId('save-expense').click();
    await expect(page.getByTestId('expense-error')).toHaveText('Enter an amount');
    // exact amounts that do not add up
    await page.getByTestId('amount').fill('90');
    await page.getByTestId('title').fill('Taxi');
    await page.getByTestId('mode-exact').click();
    const vals = page.getByTestId('split-value');
    await vals.nth(0).fill('30');
    await vals.nth(1).fill('30');
    await page.getByTestId('save-expense').click();
    await expect(page.getByTestId('expense-error')).toContainText('need AED 90.00');
    await expect(page.getByTestId('remaining')).toHaveText('AED 30.00 left');
    await vals.nth(2).fill('30');
    await expect(page.getByTestId('remaining')).toHaveText('AED 0.00 left');
    await page.screenshot({ path: `${SHOTS}/S05-expense-exact.png` });
    await a11y(page, 'S05');
    await page.getByTestId('save-expense').click();
    await expect(page.getByTestId('group-total')).toHaveText('AED 390.00');

    // Arabic-Indic digits and the Arabic decimal mark are understood
    await page.getByTestId('add-expense').click();
    await page.getByTestId('amount').fill('٤٥٫٥');
    await page.getByTestId('title').fill('Coffee');
    await page.getByTestId('payer').nth(1).click(); // Sara paid
    await page.getByTestId('save-expense').click();
    await expect(page.getByTestId('group-total')).toHaveText('AED 435.50');
    await expect(page.getByTestId('expense-row')).toHaveCount(3);
    await page.screenshot({ path: `${SHOTS}/S04-group-expenses.png` });
    await a11y(page, 'S04');

    // balances and fewest transfers
    await page.getByTestId('tab-balances').click();
    await expect(page.getByTestId('transfer')).toHaveCount(2);
    await page.screenshot({ path: `${SHOTS}/S06-balances.png` });
    await a11y(page, 'S06');
    await page.getByTestId('mark-paid').first().click();
    await expect(page.getByTestId('toast')).toContainText('Payment recorded');
    await expect(page.getByTestId('transfer')).toHaveCount(1);
    await page.getByRole('button', { name: 'Undo' }).click();
    await expect(page.getByTestId('transfer')).toHaveCount(2);
    await page.getByTestId('mark-paid').first().click();
    await page.getByTestId('mark-paid').first().click();
    await expect(page.getByTestId('all-settled')).toBeVisible();
    await expect(page.getByTestId('my-balance')).toHaveText('All settled');

    // delete an expense, then undo it
    await page.getByTestId('tab-expenses').click();
    await page.getByTestId('expense-row').first().click();
    await page.getByTestId('delete-expense').click();
    await page.getByTestId('confirm-yes').click();
    await expect(page.getByTestId('expense-row')).toHaveCount(2);
    await page.getByRole('button', { name: 'Undo' }).click();
    await expect(page.getByTestId('expense-row')).toHaveCount(3);

    // data survives a reload (stored on the device)
    await page.reload();
    await expect(page.getByTestId('group-card')).toHaveCount(1);
    done();
  });

  test('F06–F07 share link opens in a fresh browser and imports', async ({ page, browser, baseURL }) => {
    const done = guard(page);
    await onboard(page);
    await createGroup(page, 'Dubai weekend', ['Sara']);
    await addExpense(page, '120', 'Brunch');
    await page.getByTestId('share').click();
    await expect(page.getByTestId('share-sheet')).toBeVisible();
    await page.waitForTimeout(400);
    await page.screenshot({ path: `${SHOTS}/S07-share.png` });
    await page.getByTestId('copy-link').click();
    await expect(page.getByTestId('toast')).toHaveText('Copied');
    const link = await page.evaluate(() => navigator.clipboard.readText());
    expect(link).toMatch(/^https:\/\/nussnuss\.app\/app\/#g=/);
    const payload = link.split('#g=')[1];

    // a friend with no app and no data opens it
    const friend = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'en-AE' });
    const fp = await friend.newPage();
    const fdone = guard(fp);
    await fp.goto(`${baseURL}#g=${payload}`);
    await expect(fp.getByTestId('screen-shared')).toBeVisible();
    await expect(fp.getByTestId('shared-total')).toHaveText('AED 120.00');
    await expect(fp.getByText('Sara pays Talal')).toBeVisible();
    await fp.screenshot({ path: `${SHOTS}/S08-shared.png` });
    await a11y(fp, 'S08');
    await fp.getByTestId('import-group').click();
    await expect(fp.getByTestId('screen-group')).toBeVisible();
    await expect(fp.getByTestId('toast')).toHaveText('Saved to your groups');
    // the hash is cleared so a reload does not reopen the shared view
    expect(new URL(fp.url()).hash).toBe('');
    fdone();
    await friend.close();

    // a broken link is handled
    await page.goto('./#g=thisisnotvalid');
    await expect(page.getByText('This link looks broken or incomplete. Ask for a new one.')).toBeVisible();
    done();
  });

  test('F08 Arabic: instant right-to-left switch, Arabic labels and currency', async ({ page }) => {
    const done = guard(page);
    await onboard(page, 'طلال');
    await createGroup(page, 'رحلة', ['سارة']);
    await addExpense(page, '100', 'عشاء');
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByTestId('open-settings').click();
    await page.getByTestId('settings-lang-ar').click();
    await expect(page.getByText('الإعدادات')).toBeVisible();
    // the back arrow moves to the right edge in Arabic
    const back = await page.getByRole('button', { name: 'رجوع' }).boundingBox();
    expect(back!.x).toBeGreaterThan(300);
    await page.screenshot({ path: `${SHOTS}/S09-settings-ar.png` });
    await page.getByRole('button', { name: 'رجوع' }).click();
    await expect(page.getByText('مجموعاتك')).toBeVisible();
    await expect(page.getByText('لك 50.00 د.إ')).toBeVisible();
    await page.getByTestId('group-card').click();
    await page.getByTestId('tab-balances').click();
    await expect(page.getByText('مين يدفع لمين')).toBeVisible();
    await page.screenshot({ path: `${SHOTS}/S06-balances-ar.png` });
    await a11y(page, 'S06-ar');
    done();
  });

  test('F03 draft is kept when you leave the form', async ({ page }) => {
    const done = guard(page);
    await onboard(page);
    await createGroup(page, 'Office lunch', ['Mona']);
    await page.getByTestId('add-expense').click();
    await page.getByTestId('amount').fill('12');
    await page.getByTestId('title').fill('Shawarma');
    await page.waitForTimeout(500);
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByTestId('add-expense').click();
    await expect(page.getByText('We kept what you typed last time.')).toBeVisible();
    await expect(page.getByTestId('amount')).toHaveValue('12');
    await expect(page.getByTestId('title')).toHaveValue('Shawarma');
    await page.getByTestId('save-expense').click();
    await page.getByTestId('add-expense').click();
    await expect(page.getByText('We kept what you typed last time.')).toHaveCount(0);
    done();
  });

  test('Demo trip, 3-decimal currency, Plus on web', async ({ page }) => {
    const done = guard(page);
    await onboard(page, 'Ahmed');
    await page.getByTestId('try-demo').click();
    await expect(page.getByTestId('expense-row')).toHaveCount(5);
    await expect(page.getByTestId('group-total')).toHaveText('OMR 244.650');
    await page.screenshot({ path: `${SHOTS}/S04-demo.png` });
    // a foreign currency needs Plus
    await page.getByTestId('add-expense').click();
    await page.getByTestId('expense-currency').click();
    await expect(page.getByTestId('screen-plus')).toBeVisible();
    await expect(page.getByTestId('plus-unavailable')).toHaveText('Plus can be bought in the iPhone and Android app.');
    await expect(page.getByTestId('buy-plus')).toBeDisabled();
    await page.screenshot({ path: `${SHOTS}/S10-plus.png` });
    await a11y(page, 'S10');
    done();
  });
});
