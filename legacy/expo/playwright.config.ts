import { defineConfig } from '@playwright/test';

/**
 * End-to-end tests against the web build (same code as the iOS/Android app).
 *   npm run build:site && npx playwright test   (the app is served under /app/, like production)
 * CHROME_PATH lets you point at any Chromium if Playwright's own download is not available.
 */
export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:8099/app/',
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: false,
    hasTouch: false,
    locale: 'en-AE',
    permissions: ['clipboard-read', 'clipboard-write'],
    launchOptions: {
      executablePath: process.env.CHROME_PATH || undefined,
      args: ['--no-sandbox', '--disable-gpu', '--no-zygote', '--disable-software-rasterizer'],
    },
  },
  webServer: {
    command: 'python3 -m http.server 8099 --bind 127.0.0.1 --directory site',
    url: 'http://127.0.0.1:8099',
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
