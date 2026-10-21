// Scenarios from annotations/shared/shared-authenticated-session.md (not
// published yet), run on a host page at `path`. The host restores the account
// afterwards (keepAccount in steps.ts).
import { expect, type Browser, type Page } from '@playwright/test';

import {
  disableAccountAsAdmin,
  enrolInMfa,
  expectAt,
  open,
  otherSession,
  signInAs,
} from '../steps';

// @S01 Signed-out visitor to a non-project page is sent to log in
//   Given I am not logged in
//   When I visit "<path>"
//   Then I am on "/users/log_in"
//   And the flow "flow-login-return-to" has started for "<path>"
export async function S01(page: Page, path: string, email: string) {
  await page.goto(path);

  await expectAt(page, '/users/log_in');
  // The flow has started when logging in from here lands on <path>
  await signInAs(page, email);
  await expectAt(page, path);
}

// @S02 A disabled account's existing session no longer opens pages
//   Given I am logged in
//   And an administrator disables my account
//   When I reload "<path>"
//   Then I am on "/users/log_in"
export async function S02(
  page: Page,
  browser: Browser,
  path: string,
  email: string
) {
  await signInAs(page, email);
  await open(page, path);
  await disableAccountAsAdmin(browser, email);

  await page.reload();

  await expectAt(page, '/users/log_in');
}

// @S03 A session waiting on its second factor is sent to finish it
//   Given I have entered my password for an account with MFA enabled
//   And I have not entered my authentication code
//   When I visit "<path>"
//   Then I am on "/users/two-factor"
export async function S03(page: Page, path: string, email: string) {
  await signInAs(page, email);
  await enrolInMfa(page);
  await expect(page).toHaveURL(/\/profile\/auth\/backup_codes/);
  await page.context().clearCookies();
  await signInAs(page, email);
  await expectAt(page, '/users/two-factor');

  await page.goto(path);

  await expectAt(page, '/users/two-factor');
}

// The sidebar is collapsed when its menu labels are folded away (`menuLabel`
// is an item the host page's menu has). It also expands while hovered, so the
// pointer is moved off it first.
async function expectSidebarCollapsed(
  page: Page,
  collapsed: boolean,
  menuLabel: string
) {
  await page.mouse.move(800, 400);
  // first navigation is the side menu; later ones are breadcrumbs
  const label = page.getByRole('navigation').first().getByText(menuLabel, {
    exact: true,
  });
  if (collapsed) await expect(label).toBeHidden();
  else await expect(label).toBeVisible();
}

// @S07 Collapsing the sidebar is remembered
//   Given I am logged in with the sidebar expanded
//   When I click "Toggle sidebar"
//   Then the sidebar is collapsed
//   When I open another page, or log in again later
//   Then the sidebar is still collapsed
export async function S07(
  page: Page,
  browser: Browser,
  path: string,
  otherPath: string,
  email: string,
  menuLabel = 'Credentials'
) {
  await signInAs(page, email);
  await open(page, path);
  await expectSidebarCollapsed(page, false, menuLabel);

  await page.getByRole('button', { name: 'Toggle sidebar' }).click();
  await expectSidebarCollapsed(page, true, menuLabel);

  await open(page, otherPath);
  await expectSidebarCollapsed(page, true, menuLabel);

  const later = await otherSession(browser, email);
  await open(later, path);
  await expectSidebarCollapsed(later, true, menuLabel);
  await later.context().close();
}

// @S11 An instance with no superuser sends pages to first setup
//   Given first setup is allowed
//   And there is no superuser
//   When I visit "<path>"
//   Then I am on "/first_setup"
export async function S11(page: Page, path: string) {
  await page.goto(path);

  await expectAt(page, '/first_setup');
}
