/** Unit tests for the pure logic (money, splits, share links). UI is tested with Playwright in e2e/. */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  transform: {
    '^.+\\.tsx?$': ['ts-jest', { tsconfig: { module: 'commonjs', esModuleInterop: true, strict: true, target: 'es2020', isolatedModules: true, rootDir: '.' , types: ['jest', 'node'] } }],
  },
};
