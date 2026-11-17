// Scenarios from annotations/shared/shared-project-scope.md, run on a host
// page at `path` under a project. The host owns the Given (the project, its
// members, the flags on it) and, for the scenarios about an open page, the
// outside action (`act`) that changes things while the page is open.
import { expect, type Locator, type Page } from '@playwright/test';

import { expectAt, open, signInAs } from '../steps';

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

const eventually = <T>(page: Page, read: (url: URL) => T) =>
  expect.poll(() => read(new URL(page.url())), EVENTUALLY);

const notFound = (page: Page) =>
  expect(page.getByText('Not Found', { exact: true })).toBeVisible();

// @S01 Signed-out visitor is sent to log in
//   Given I am not logged in
//   When I visit "<path>"
//   Then I am on "/users/log_in"
export async function S01(page: Page, path: string) {
  await page.goto(path);

  await expectAt(page, '/users/log_in');
}

// @S02 Member opens a project page
//   Given I am an editor on project "Malawi HIV"
//   When I visit the project's page
//   Then I see the page for project "Malawi HIV"
// `shown` is something only that page shows.
export async function S02(
  page: Page,
  path: string,
  email: string,
  shown: Locator
) {
  await signInAs(page, email);
  await open(page, path);

  await expectAt(page, path);
  await expect(shown).toBeVisible();
}

// @S03 Non-member is told the project was not found
//   Given I am a registered user not on project "Malawi HIV"
//   When I visit the project's page
//   Then I am on "/projects"
//   And I see "Not Found"
export async function S03(page: Page, path: string, email: string) {
  await signInAs(page, email);
  await page.goto(path);

  await expectAt(page, '/projects');
  await notFound(page);
}

// @S04 A project scheduled for deletion is not found
//   Given project "Malawi HIV" is scheduled for deletion
//   And I am its owner
//   When I visit the project's page
//   Then I am on "/projects"
//   And I see "Not Found"
export const S04 = S03;

// @S05 Member without MFA on an MFA-required project is sent to enrol
//   Given project "Malawi HIV" requires MFA
//   And I am an editor who has not enrolled in MFA
//   When I visit the project's page
//   Then I am on "/mfa_required"
export async function S05(page: Page, path: string, email: string) {
  await signInAs(page, email);
  await page.goto(path);

  await expectAt(page, '/mfa_required');
}

// @S06 Support user reaches a project with support access on
//   Given I am a support user with no role on project "Malawi HIV"
//   And project "Malawi HIV" has support access enabled
//   When I visit the project's page
//   Then I see the page for project "Malawi HIV"
export const S06 = S02;

// @S07 Removing a member ends their open session on the project
//   Given I have project "Malawi HIV" open as an editor
//   When an admin removes me from the project in another session
//   Then my page eventually leaves the project
//   And I see "Not Found"
export async function S07(
  page: Page,
  path: string,
  email: string,
  act: () => void
) {
  await signInAs(page, email);
  await open(page, path);

  act();

  await eventually(page, url => url.pathname).toBe('/projects');
  await notFound(page);
}

// @S08 A role change takes effect on an open page
//   Given I have project "Malawi HIV" open as an admin
//   When an owner changes my role to viewer in another session
//   Then my page eventually reloads with viewer permissions, keeping its query string
// `path` carries a query string; `root` is an element only the mounted page
// has. A mark put on it is gone once the page has mounted again.
export async function S08(
  page: Page,
  path: string,
  email: string,
  act: () => void,
  root: Locator
) {
  const [pathname, search] = path.split('?');
  await signInAs(page, email);
  await open(page, path);
  await expect(root).toBeVisible();
  await root.evaluate(el => el.setAttribute('data-mounted-before', 'yes'));

  act();

  await expect(page.locator('[data-mounted-before]')).toHaveCount(
    0,
    EVENTUALLY
  );
  await expect(root).toBeVisible();
  await eventually(page, url => url.pathname + url.search).toBe(
    `${pathname}?${search}`
  );
}

// @S09 Turning off support access ends a support session
//   Given I am a support user with project "Malawi HIV" open through support access only
//   When an owner disables support access
//   Then my page eventually leaves the project
export async function S09(
  page: Page,
  path: string,
  email: string,
  act: () => void
) {
  await signInAs(page, email);
  await open(page, path);

  act();

  await eventually(page, url => url.pathname).toBe('/projects');
}

// @S10 Open pages leave a project scheduled for deletion
//   Given I have project "Malawi HIV" open
//   When an owner schedules the project for deletion
//   Then I am eventually on "/projects"
//   And I see "Project deleted."
export async function S10(
  page: Page,
  path: string,
  email: string,
  act: () => void
) {
  await signInAs(page, email);
  await open(page, path);

  act();

  await eventually(page, url => url.pathname).toBe('/projects');
  await expect(page.getByText('Project deleted.')).toBeVisible();
}

// @S11 Archiving a sandbox moves its open editor to the parent workflow
//   Given I have experimental features enabled
//   And I have workflow "Intake" open in sandbox "dev" of project "Malawi HIV"
//   And project "Malawi HIV" has a workflow named "Intake"
//   When sandbox "dev" is scheduled for deletion
//   Then I am eventually on the editor for "Intake" in "Malawi HIV" with "archived=1"
// The host turned the preference on. `landing` is the parent's editor path.
export async function S11(
  page: Page,
  path: string,
  email: string,
  act: () => void,
  landing: string
) {
  await signInAs(page, email);
  await open(page, path);

  act();

  await eventually(page, url => url.pathname + url.search).toBe(
    `${landing}?archived=1`
  );
}

// @S12 Deleting the open workflow returns the viewer to the workflow list
//   Given I have workflow "Intake" open
//   When another user deletes "Intake"
//   Then I am eventually on the project's workflows page
//   And I see "Workflow deleted."
export async function S12(
  page: Page,
  path: string,
  email: string,
  act: () => void,
  workflowsPath: string
) {
  await signInAs(page, email);
  await open(page, path);

  act();

  await eventually(page, url => url.pathname).toBe(workflowsPath);
  await expect(page.getByText('Workflow deleted.')).toBeVisible();
}
