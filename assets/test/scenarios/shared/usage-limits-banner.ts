// Scenarios from annotations/shared/shared-usage-limits-banner.md, run on a
// host page at `path` under a project. `shown` is something only that page
// shows.
import { expect, type Locator, type Page } from '@playwright/test';

import { open, signInAs } from '../steps';

// @S01 Over-limit project shows the limiter's banner (variant usage-limited)
//   Given the usage limiter reports project "Malawi HIV" is over its run limit
//   When I open the project's page
//   Then I see the limiter's banner text
// Needs an instance whose limiter refuses runs; the host skips it otherwise.
export async function S01(
  page: Page,
  path: string,
  email: string,
  text: string
) {
  await signInAs(page, email);
  await open(page, path);

  await expect(page.getByText(text)).toBeVisible();
}

// @S02 Within-limit project shows no banner
//   Given the default usage limiter
//   When I open the project's page
//   Then I see no limits banner
// A banner sits above the page's top bar, so with none nothing does.
export async function S02(
  page: Page,
  path: string,
  email: string,
  shown: Locator
) {
  await signInAs(page, email);
  await open(page, path);

  await expect(shown).toBeVisible();
  await expect(
    page.getByTestId('top-bar').locator('xpath=preceding-sibling::*')
  ).toHaveCount(0);
}
