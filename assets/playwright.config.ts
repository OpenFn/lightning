import { defineConfig, devices } from "@playwright/test";

import { binPath, checkServerRunning } from "./test/e2e/e2e-helper";

const serverAlreadyRunning = checkServerRunning();

if (serverAlreadyRunning) {
  console.log("🔄 Detected existing e2e server, will reuse it");
}

/**
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: "./test/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "list",
  use: {
    baseURL: `http://localhost:${process.env.PORT || 4003}`,
    trace: "on-first-retry",
  },

  projects: [
    {
      name: "setup",
      testMatch: /global\.setup\.ts/,
    },
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
      dependencies: ["setup"],
    },
  ],

  /* Run your local dev server before starting the tests */
  webServer: {
    command: `${binPath} server`,
    url: `http://localhost:${process.env.PORT || 4003}`,
    reuseExistingServer: serverAlreadyRunning || !process.env.CI,
    timeout: 60 * 1000,
  },
});
