import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('landing page: splitter adds up, Arabic switch, links, accessibility', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => m.type() === 'error' && !/fonts\.g|ERR_TUNNEL_CONNECTION_FAILED/.test(m.text()) && errors.push(m.text()));
  await page.goto('http://127.0.0.1:8099/');
  await expect(page.locator('h1 .en')).toHaveText('Split any bill. No limits.');
  // 100.000 OMR between 3: the extra baisa goes to the first person, total matches
  await expect(page.locator('#shares li')).toHaveCount(3);
  await expect(page.locator('#shares li').first()).toContainText('OMR 33.334');
  await expect(page.locator('#sum')).toHaveText('OMR 100.000');
  await page.locator('#plus').click();
  await expect(page.locator('#shares li')).toHaveCount(4);
  await page.locator('#cur').selectOption('AED:2');
  await page.locator('#amt').fill('٤٥٫٥');
  await expect(page.locator('#sum')).toHaveText('AED 45.50');
  await page.locator('#amt').fill('1.234');
  await expect(page.locator('#note')).toContainText('up to 2 decimal places');
  await page.screenshot({ path: 'replica/clone-screens/landing-en.png', fullPage: false });
  const r = await new AxeBuilder({ page }).disableRules(['region', 'landmark-one-main']).analyze();
  expect(r.violations.filter((v) => v.impact === 'critical' || v.impact === 'serious').map((v) => v.id)).toEqual([]);
  await page.locator('#lang-ar').click();
  await expect(page.locator('#page')).toHaveAttribute('dir', 'rtl');
  await expect(page.locator('h1 .ar')).toBeVisible();
  await page.screenshot({ path: 'replica/clone-screens/landing-ar.png', fullPage: false });
  await expect(page.locator('a.btn.primary').first()).toHaveAttribute('href', './app/');
  await page.goto('http://127.0.0.1:8099/privacy.html');
  await expect(page.locator('h1').first()).toHaveText('NussNuss — Privacy Policy');
  expect(errors).toEqual([]);
});
