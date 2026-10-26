import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

/** The currency picker: a list in the sheet, the same as in the phone app. */
async function pickCurrency(page: Page, code: string) {
  await page.getByTestId('group-currency').click();
  await page.getByTestId(`currency-${code}`).click();
  await expect(page.getByTestId('currency-list')).toBeHidden();
}

const SHOTS = process.env.SHOTS_DIR ?? 'test-results/screens';

function guard(page: Page) {
  const problems: string[] = [];
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error' && !/favicon|ERR_TUNNEL/.test(m.text())) problems.push(`console: ${m.text()}`);
  });
  return () => expect(problems, problems.join('\n')).toEqual([]);
}

/** Let springs finish so screenshots show the resting state. */
async function still(page: Page) {
  await page.waitForTimeout(700);
}

async function a11y(page: Page, where: string) {
  const r = await new AxeBuilder({ page }).analyze();
  const bad = r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  expect(bad.map((v) => `${where}: ${v.id} (${v.nodes.length}) ${v.nodes[0]?.target}`)).toEqual([]);
}

async function start(page: Page, name: string) {
  await page.goto('/');
  await expect(page.getByTestId('welcome')).toBeVisible();
  await page.getByTestId('name').fill(name);
  await page.getByTestId('start').click();
  await expect(page.getByTestId('groups')).toBeVisible();
  // First run goes straight to making the first group.
  await expect(page.getByTestId('new-group-sheet')).toBeVisible();
}

async function newGroup(page: Page, name: string, people: string[]) {
  if (!(await page.getByTestId('new-group-sheet').isVisible())) await page.getByTestId('add').click();
  await expect(page.getByTestId('new-group-sheet')).toBeVisible();
  await page.getByTestId('group-name').fill(name);
  await pickCurrency(page, 'OMR');
  for (const p of people) {
    await page.getByTestId('person-name').fill(p);
    await page.getByTestId('add-person').click();
  }
  await page.getByTestId('create-group').click();
  await expect(page.getByTestId('group')).toBeVisible();
}

async function typeAmount(page: Page, digits: string) {
  for (const d of digits) await page.getByRole('button', { name: d === '.' ? 'Decimal point' : d === '+' ? 'Plus' : d, exact: true }).click();
}

test('welcome, first group, expenses with the keypad, settle up, undo', async ({ page }) => {
  const done = guard(page);
  await page.goto('/');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/01-welcome.png` });
  await a11y(page, 'welcome');
  await page.getByTestId('start').click();
  await expect(page.getByText('This is how your friends will see you.')).toBeVisible();
  await page.getByTestId('name').fill('Talal');
  await page.getByTestId('start').click();
  await expect(page.getByTestId('new-group-sheet')).toBeVisible();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/02-first-group.png` });
  await a11y(page, 'new group');

  await newGroup(page, 'Salalah trip', ['Sara', 'Omar']);
  await expect(page.getByText('Nothing spent yet')).toBeVisible();

  // Amount keypad with a sum: 100 + 20.5 = OMR 120.500, split equally between 3
  await page.getByTestId('add').click();
  await expect(page.getByTestId('expense-sheet')).toBeVisible();
  await typeAmount(page, '100+20.5');
  await expect(page.getByTestId('amount-sum')).toHaveText('= OMR 120.500');
  await page.getByTestId('title').fill('Chalet');
  await page.getByTestId('details').click();
  await page.getByTestId('cat-stay').click();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/03-add-expense.png` });
  await a11y(page, 'add expense');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
  await expect(page.getByTestId('group-total')).toContainText('OMR 120.500');
  await expect(page.getByTestId('my-balance')).toHaveText('OMR 80.333');

  // Shares: Sara paid 30, Omar counts double
  await page.getByTestId('add').click();
  await typeAmount(page, '30');
  await page.getByTestId('title').fill('Fuel');
  await page.getByTestId('details').click();
  await page.getByTestId('payer').nth(1).click();
  await page.getByTestId('split-how-unequal').click();
  await page.getByTestId('mode-shares').click();
  await page.getByRole('button', { name: 'Omar +' }).click();
  await expect(page.getByTestId('share-count').nth(2)).toHaveText('2');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-row')).toHaveCount(2);
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
  await still(page);
  await page.screenshot({ path: `${SHOTS}/04-group.png` });
  await a11y(page, 'group');

  // Validation: an empty save explains itself
  await page.getByTestId('add').click();
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-error')).toHaveText('Enter an amount.');
  await page.keyboard.press('Escape');
  await expect(page.getByTestId('expense-sheet')).toBeHidden();

  // Settle up: mark paid, undo, then settle everything
  await page.getByTestId('tab-settle').click();
  await expect(page.getByTestId('transfer')).toHaveCount(2);
  await still(page);
  await page.screenshot({ path: `${SHOTS}/05-settle.png` });
  await a11y(page, 'settle');
  await page.getByTestId('mark-paid').first().click();
  await expect(page.getByTestId('toast')).toContainText('Marked as paid');
  await expect(page.getByTestId('transfer')).toHaveCount(1);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(page.getByTestId('transfer')).toHaveCount(2);
  await page.getByTestId('mark-paid').first().click();
  await expect(page.getByTestId('transfer')).toHaveCount(1);
  await page.getByTestId('mark-paid').first().click();
  await expect(page.getByTestId('all-settled')).toBeVisible();
  await page.waitForTimeout(700);
  await still(page);
  await page.screenshot({ path: `${SHOTS}/06-settled.png` });

  // Edit and delete with undo
  await page.getByTestId('tab-expenses').click();
  await page.getByTestId('expense-row').first().click();
  await page.getByTestId('delete-expense').click();
  await expect(page.getByTestId('expense-row')).toHaveCount(1);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(page.getByTestId('expense-row')).toHaveCount(2);
  done();
});

test('a friend joins from the link without the app, in Arabic', async ({ page, browser }) => {
  const done = guard(page);
  await start(page, 'Talal');
  await newGroup(page, 'Flat 12', ['Sara']);
  await page.getByTestId('share').click();
  await expect(page.getByTestId('invite-link')).toContainText('/j/');
  const link = (await page.getByTestId('invite-qr').getAttribute('data-text'))!;
  await still(page);
  await page.screenshot({ path: `${SHOTS}/07-share.png` });

  const friend = await browser.newContext({ locale: 'ar', viewport: { width: 390, height: 844 }, permissions: ['clipboard-read', 'clipboard-write'] });
  const fp = await friend.newPage();
  await fp.goto(link);
  await expect(fp.getByTestId('join')).toBeVisible();
  await expect(fp.locator('html')).toHaveAttribute('dir', 'rtl');
  await fp.getByTestId('who').nth(1).check();
  await still(fp);
  await fp.screenshot({ path: `${SHOTS}/08-join-ar.png` });
  await a11y(fp, 'join');
  await fp.getByTestId('join-btn').click();
  await expect(fp.getByTestId('group')).toBeVisible();
  await expect(fp.getByText('Flat 12').first()).toBeVisible();
  await still(fp);
  await fp.screenshot({ path: `${SHOTS}/09-group-ar.png` });
  await friend.close();
  done();
});

test('settings: frosted glass and dark mode @desktop', async ({ page }) => {
  const done = guard(page);
  await start(page, 'Lina');
  await newGroup(page, 'Office lunch', ['Mona', 'Huda']);
  await page.getByTestId('add').click();
  await typeAmount(page, '45');
  await page.getByTestId('title').fill('Shawarma');
  await page.getByTestId('save-expense').click();
  await expect(page.getByTestId('expense-sheet')).toBeHidden();
  await page.emulateMedia({ colorScheme: 'dark' });
  await still(page);
  await page.screenshot({ path: `${SHOTS}/10-group-dark-${test.info().project.name}.png` });
  await a11y(page, 'group dark');
  await page.goto('/you');
  await page.getByTestId('settings-glass-frosted').click();
  await expect(page.locator('html')).toHaveAttribute('data-glass', 'frosted');
  await still(page);
  await page.screenshot({ path: `${SHOTS}/11-settings-dark-${test.info().project.name}.png` });
  done();
});
