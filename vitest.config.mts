import { defineConfig } from 'vitest/config';

export default defineConfig({
  cacheDir: process.env.SLOTH_VITE_CACHE_DIR,
  test: {
    include: ['test/typescript/**/*.test.ts'],
    fileParallelism: false,
    fsModuleCachePath: process.env.SLOTH_MODULE_CACHE_DIR,
    testTimeout: 60_000,
    hookTimeout: 60_000,
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      reportsDirectory: process.env.SLOTH_COVERAGE_DIR,
      reporter: ['text', 'json-summary', 'lcov'],
      thresholds: { lines: 100, statements: 100, functions: 100, branches: 100 },
    },
  },
});
