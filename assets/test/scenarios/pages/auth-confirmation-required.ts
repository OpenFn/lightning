// Where today's confirm-your-email page (HEEx) and the design-system one
// differ. Everything that knows how either version is built lives here, so a
// redesign of /users/confirm-required only changes this file.
import type { Page } from '@playwright/test';

// The credential the page hands the browser for the user socket. Both
// versions share the root layout, which writes it to `window.userToken`.
export const socketToken = (page: Page) =>
  page.evaluate(() => (window as unknown as { userToken?: string }).userToken);
