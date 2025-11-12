import { defineConfig, devices } from '@playwright/test';
import { binPath } from './test/e2e/e2e-helper';

const testDir = new URL('./test/e2e', import.meta.url).pathname;

/**
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'list',
  use: {
    baseURL: `http://localhost:${process.env.PORT || 4003}`,
    trace: 'on-first-retry',
  },

  projects: [
    {
      name: 'setup',
      testMatch: /global\.setup\.ts/,
    },
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
      dependencies: ['setup'],
    },
  ],

  /* Run your local dev server before starting the tests */
  webServer: {
    command: `${binPath} start`,
    url: `http://localhost:${process.env.PORT || 4003}`,
    reuseExistingServer: !process.env.CI, // Always reuse in dev, never in CI
    timeout: 60 * 1000,
  },
});
