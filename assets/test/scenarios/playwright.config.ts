import { defineConfig, devices } from '@playwright/test';

// Runs annotation scenarios against an already-running Lightning (the
// verify-lightning e2e instance on :4003). It never starts a server.
// Each worker has its own seeded users and projects (global-setup.ts), so
// tests run in parallel. Tests that read or change instance-wide state (the
// audit log, the mailbox, every project) are tagged @serial, and admin-audit
// is serial as a whole: they run afterwards, alone. Use ./run, which runs
// the two groups one after the other; plain `playwright test` runs both at once.
// TARGET=demo runs them against the openfn-ia-demo Vite app instead.
const baseURL =
  process.env.TARGET === 'demo'
    ? 'http://localhost:5173/openfn-ia-demo/'
    : process.env.LIGHTNING_URL || 'http://localhost:4003';

const use = {
  ...devices['Desktop Chrome'],
  baseURL,
  timezoneId: 'UTC',
  locale: 'en-US',
};

export default defineConfig({
  testDir: new URL('.', import.meta.url).pathname,
  testMatch: /\.spec\.ts$/,
  globalSetup: new URL('./global-setup.ts', import.meta.url).pathname,
  workers: Number(process.env.SCENARIO_WORKERS || 4),
  fullyParallel: false,
  reporter: 'list',
  use,
  projects: [
    {
      name: 'parallel',
      grepInvert: /@serial/,
      testIgnore: /admin-audit/,
      fullyParallel: true,
    },
    { name: 'serial', grep: /@serial/, testIgnore: /admin-audit/ },
    { name: 'admin', testMatch: /admin-audit\.spec\.ts$/ },
  ],
});
