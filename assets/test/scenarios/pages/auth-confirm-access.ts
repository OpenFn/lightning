// Where today's confirm access page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a
// redesign of /auth/confirm_access only changes this file.
import type { Page } from '@playwright/test';

// Today's fields have no label (a heading above names them), so they are
// found inside the form by what they take.
const form = (page: Page) => page.locator('#reauthentication-form');

// The password field
export const passwordBox = (page: Page) =>
  form(page).locator('input[type="password"]');

// The authentication code field
export const codeBox = (page: Page) =>
  form(page).locator('input[autocomplete="one-time-code"]');
