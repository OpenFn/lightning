// Scenarios from annotations/shared/shared-admin-space.md, run
// on an admin page at `path`. The host makes `email` a superuser and restores
// the account afterwards (makeSuperuser and keepAccount in steps.ts).
import { expect, type Browser, type Page } from '@playwright/test';

import { demoteAsAdmin, expectAt, open, signInAs, sql, user } from '../steps';

// @S01 The admin side menu leads to each admin area and marks the current one
//   Given I am a superuser
//   When I open "<path>"
//   Then the side menu shows "Projects", "Users", "Authentication", "Audit", "Collections", "Maintenance" and "Back"
//   And "<current>" is marked as current
//   When I click "Back"
//   Then I am on "/projects"
export async function S01(
  page: Page,
  path: string,
  email: string,
  current: string
) {
  await signInAs(page, email);
  await open(page, path);

  const menu = page.getByRole('navigation');
  for (const name of [
    'Projects',
    'Users',
    'Authentication',
    'Audit',
    'Collections',
    'Maintenance',
    'Back',
  ])
    await expect(menu.getByRole('link', { name, exact: true })).toBeVisible();
  await expect(
    menu.getByRole('link', { name: current, exact: true })
  ).toHaveAttribute('aria-current', 'page');

  await menu.getByRole('link', { name: 'Back', exact: true }).click();

  await expectAt(page, '/projects');
}

// @S02 A non-superuser is turned away from every admin page
//   Given I am signed in as a regular user
//   When I visit "<path>"
//   Then I am on "/projects"
//   And I see "No Access" and "Sorry, you don't have access to that."
//   And I see a "Back" button
export async function S02(page: Page, path: string, email: string) {
  await signInAs(page, email);

  await page.goto(path);

  await expectAt(page, '/projects');
  await expect(page.getByText('No Access', { exact: true })).toBeVisible();
  await expect(
    page.getByText("Sorry, you don't have access to that.")
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Back' })).toBeVisible();
}

// @S06 Demoting a superuser hands off to the revocation flow
//   Given "<email>" is a superuser with "<path>" open
//   When another superuser changes her role to user and saves
//   Then the flow "flow-account-revocation-teardown" has started for "<email>"
// The flow has started when her sessions are gone, so the open page can no
// longer be reloaded.
export async function S06(
  page: Page,
  browser: Browser,
  path: string,
  email: string
) {
  await signInAs(page, email);
  await open(page, path);
  const sessions = () =>
    sql<{ n: number }>(
      `select count(*)::int as n from user_tokens
       where context = 'session' and user_id = '${user(email).id}'`
    )[0].n;
  expect(sessions()).toBeGreaterThan(0);

  await demoteAsAdmin(browser, email);

  await expect.poll(sessions).toBe(0);
  await page.reload();
  await expectAt(page, '/users/log_in');
}
