import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end tests: the real web app against the real API and Postgres.
 *   npm run build -w @nussnuss/api && npm run build -w @nussnuss/web   (NEXT_PUBLIC_API_URL=http://127.0.0.1:4000)
 *   npm run test:e2e -w @nussnuss/web
 * Both servers are started here unless they are already running. CHROME_PATH points at any Chromium if needed.
 */
const launchOptions = {
  executablePath: process.env.CHROME_PATH || undefined,
  args: ['--no-sandbox', '--disable-gpu', '--no-zygote', '--disable-software-rasterizer'],
};

export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  workers: 1,
  reporter: [['list']],
  use: { baseURL: 'http://127.0.0.1:3000', locale: 'en-AE', permissions: ['clipboard-read', 'clipboard-write'], launchOptions },
  projects: [
    { name: 'phone', use: { ...devices['iPhone 15'], defaultBrowserType: 'chromium', launchOptions } },
    { name: 'desktop', use: { viewport: { width: 1280, height: 860 }, launchOptions }, grep: /@desktop/ },
  ],
  webServer: [
    {
      command: 'npm run start -w @nussnuss/api',
      cwd: '../..',
      url: 'http://127.0.0.1:4000/health',
      reuseExistingServer: true,
      timeout: 60_000,
      env: {
        PORT: '4000',
        DATABASE_URL: process.env.DATABASE_URL ?? 'postgres://nussnuss:nussnuss@127.0.0.1:5432/nussnuss_test',
        WEB_ORIGIN: 'http://127.0.0.1:3000,http://localhost:3000',
        RATE_LIMIT_PER_MINUTE: '100000',
        // Test servers only: lets the tests switch Plus on without a store. Never set in production.
        ALLOW_DEV_PURCHASES: 'true',
      },
    },
    { command: 'npm run start', url: 'http://127.0.0.1:3000', reuseExistingServer: true, timeout: 60_000 },
  ],
});
