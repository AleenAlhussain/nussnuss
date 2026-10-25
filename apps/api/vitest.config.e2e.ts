import { defineConfig } from 'vitest/config';

// End-to-end tests run against a real Postgres: DATABASE_URL (default: the local test database).
export default defineConfig({
  test: {
    globals: true,
    root: './',
    include: ['test/**/*.e2e-spec.ts'],
    fileParallelism: false,
    testTimeout: 30000,
    hookTimeout: 60000,
  },
});
