// Scenarios from annotations/views/admin-projects.md.
//
// Who's who: "I" am owner@openfn.org, made a superuser for each test (the
// role is put back afterwards). editor@openfn.org is the regular user. The
// people a scenario names ("Amara Banda", "Bob Jones", …) are seeded per test
// with a fresh email, and the projects with a fresh name ("malawi-hiv-<hex>"),
// since every worker's test sees every project and account on the instance.
// All are removed again afterwards.
import { randomUUID } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import {
  clearFilterButton,
  menuAction,
  newProjectButton,
  openActions,
  sendProjectDeletion,
  sendSaveWithoutMembers,
  setRole,
} from './pages/admin-projects';
import * as adminSpace from './shared/admin-space';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as projectDeletionModal from './shared/project-deletion-modal';
import * as projectHeader from './shared/project-header';
import {
  clickable,
  exec,
  expectAt,
  field,
  keepAccount,
  makeSuperuser,
  modal,
  modalTitle,
  open,
  removeProject,
  scheduledDeletionOf,
  seedProjectWith,
  seedUser,
  signInAs,
  sql,
  submit,
  tagFor,
  user,
  watchLiveView,
  type UserSeed,
} from './steps';

const ME = 'owner@openfn.org';
const REGULAR = 'editor@openfn.org';
const PAGE = '/settings/projects';
const deletePath = (id: string) => `${PAGE}/${id}/delete`;
const SCHEDULED = '2027-10-21 09:30:00';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), makeSuperuser(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

const hex = () => randomUUID().slice(0, 8);

// Given "<first> <last>" is a registered user (removed after the test)
function person(first: string, last: string, seed: UserSeed = {}) {
  const account = seedUser(first.toLowerCase(), {
    firstName: first,
    lastName: last,
    ...seed,
  });
  cleanups.push(account.remove);
  return account;
}

// Given project "<base>-<hex>" with these members (removed after the test)
function project(
  base: string,
  members: Record<string, Role> = {},
  extra: Parameters<typeof seedProjectWith>[2] = {}
) {
  const seeded = seedProjectWith(`${base}-${hex()}`, members, extra);
  cleanups.push(seeded.remove);
  return seeded;
}

// Removes, after the test, every project the page created as "<name>"
function removeAfter(name: string) {
  cleanups.push(() => {
    for (const { id } of projectsCalled(name)) removeProject(id);
  });
}

const projectsCalled = (name: string) =>
  sql<{ id: string }>(`select id from projects where name = '${name}'`);

// The members of project <id>, as "<user id>:<role>", sorted
const membersOf = (id: string) =>
  sql<{ m: string }>(
    `select user_id || ':' || role as m from project_users
     where project_id = '${id}' order by 1`
  ).map(r => r.m);

const member = (u: { id: string }, role: Role) => `${u.id}:${role}`;

// The project-addition emails queued for <userId> on project <projectId>
const additionEmailsTo = (userId: string, projectId: string) =>
  sql(
    `select 1 from oban_jobs j join project_users pu
       on pu.id::text = j.args->>'project_user_id'
     where j.worker = 'Lightning.Accounts.UserNotifier'
       and j.args->>'type' = 'project_addition'
       and pu.user_id = '${userId}' and pu.project_id = '${projectId}'`
  );

// Given I am a superuser, signed in and on <path>
async function signedIn(page: Page, path = PAGE) {
  await signInAs(page, ME);
  await open(page, path);
}

const row = (page: Page, text: string) =>
  page.getByRole('row').filter({ hasText: text });

// The cell of <name>'s row under the column headed <header>
async function cell(page: Page, name: string, header: string) {
  const headers = (await page.getByRole('columnheader').allInnerTexts()).map(
    h => h.trim()
  );
  const column = headers.indexOf(header);
  expect(column, `a "${header}" column`).toBeGreaterThanOrEqual(0);
  return row(page, name).getByRole('cell').nth(column);
}

// Where each of <names> is listed, top to bottom (-1 when it isn't)
async function positions(page: Page, names: string[]) {
  const rows = await page.getByRole('row').allInnerTexts();
  return names.map(n => rows.findIndex(r => r.includes(n)));
}

const inOrder = (page: Page, names: string[]) =>
  expect
    .poll(async () => {
      const at = await positions(page, names);
      return at.every((x, i) => x >= 0 && (i === 0 || x > at[i - 1]));
    })
    .toBe(true);

// When I click the "<header>" header
const sortBy = (page: Page, header: string) =>
  clickable(page.getByRole('columnheader'), header, { exact: true }).click();

const filterBox = (page: Page) => page.getByPlaceholder('Filter projects...');

// When I type "<text>" in "Filter projects..."
async function typeFilter(page: Page, text: string) {
  await filterBox(page).fill('');
  await filterBox(page).pressSequentially(text);
}

// When I open "Edit" for "<name>" from the list
async function edit(page: Page, p: { id: string; name: string }) {
  await signedIn(page);
  const menu = await openActions(page, p.name);
  await menuAction(menu, 'Edit').click();
  await expectAt(page, `${PAGE}/${p.id}`);
}

const ONE_OWNER =
  'Every project must have exactly one owner. Please specify one below.';
const TWO_OWNERS = 'A project can have only one owner.';

// @S01
// Scenario: Superuser sees every project on the instance
//   Given I am a superuser who is not a member of project "malawi-hiv"
//   And project "malawi-hiv" was created on 3 March, has description "HIV programme" and owner "Amara Banda"
//   When I open "/settings/projects"
//   Then I see a row for "malawi-hiv" with "03 Mar", "HIV programme" and "Amara Banda"
//   And the row has an "Actions" menu with "Edit" and "Delete"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = person('Amara', 'Banda');
  const malawi = project(
    'malawi-hiv',
    { [amara.id]: 'owner' },
    { description: 'HIV programme', insertedAt: '2026-03-03 09:30:00' }
  );

  await signedIn(page);

  await expect(await cell(page, malawi.name, 'Created At')).toHaveText(
    /03 Mar/
  );
  await expect(await cell(page, malawi.name, 'Description')).toHaveText(
    'HIV programme'
  );
  await expect(await cell(page, malawi.name, 'Owner')).toHaveText(
    'Amara Banda'
  );
  const menu = await openActions(page, malawi.name);
  await expect(menuAction(menu, 'Edit')).toBeVisible();
  await expect(menuAction(menu, 'Delete')).toBeVisible();
});

// @S02
// Scenario: A project without an owner is called out
//   Given project "legacy-sync" has members but none with role owner
//   When I open "/settings/projects"
//   Then the owner column for "legacy-sync" says "No owner"
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const bob = person('Bob', 'Jones');
  const legacy = project('legacy-sync', { [bob.id]: 'admin' });

  await signedIn(page);
  await expect(await cell(page, legacy.name, 'Owner')).toHaveText('No owner');
});

// @S03
// Scenario: Superuser filters the list by name, description or owner
//   Given projects "alpha-project" (description "First project", owner "John Owner") and "beta-project" (description "Second project")
//   When I type "alpha" in "Filter projects..."
//   Then I see "alpha-project" and not "beta-project"
//   When I type "First" in "Filter projects..."
//   Then I see "alpha-project" and not "beta-project"
//   When I type "John" in "Filter projects..."
//   Then I see "alpha-project" and not "beta-project"
//   When I clear the filter
//   Then I see both projects
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const john = person('John', 'Owner');
  const alpha = project(
    'alpha-project',
    { [john.id]: 'owner' },
    { description: 'First project' }
  );
  const beta = project('beta-project', {}, { description: 'Second project' });

  await signedIn(page);
  await expect(row(page, beta.name)).toBeVisible();

  for (const text of ['alpha', 'First', 'John']) {
    await typeFilter(page, text);
    await expect(row(page, alpha.name)).toBeVisible();
    await expect(row(page, beta.name)).toHaveCount(0);
  }

  await clearFilterButton(page).click();
  await expect(row(page, alpha.name)).toBeVisible();
  await expect(row(page, beta.name)).toBeVisible();
});

// @S04
// Scenario: Superuser sorts the list by a column
//   Given projects "alpha-project", "beta-project" and "charlie-project"
//   When I click the "Name" header
//   Then the projects are listed "charlie-project", "beta-project", "alpha-project"
//   When I click the "Name" header again
//   Then the projects are listed "alpha-project", "beta-project", "charlie-project"
//   When I click the "Created at" header
//   Then the oldest project is listed first
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  // Created in an order unlike either name order: beta, charlie, alpha
  const suffix = hex();
  const [alpha, beta, charlie] = (
    [
      ['alpha', '2022-01-01 00:00:00'],
      ['beta', '2020-01-01 00:00:00'],
      ['charlie', '2021-01-01 00:00:00'],
    ] as const
  ).map(([base, insertedAt]) => {
    const p = seedProjectWith(`${base}-project-${suffix}`, {}, { insertedAt });
    cleanups.push(p.remove);
    return p.name;
  });

  await signedIn(page);
  await inOrder(page, [alpha, beta, charlie]);

  await sortBy(page, 'Name');
  await inOrder(page, [charlie, beta, alpha]);

  await sortBy(page, 'Name');
  await inOrder(page, [alpha, beta, charlie]);

  await sortBy(page, 'Created At');
  await inOrder(page, [beta, charlie, alpha]);
});

// @S05
// Scenario: Superuser creates a project for a team without joining it
//   Given users "1st user" and "another person" exist
//   When I click "New Project"
//   And I enter "some name" as the name
//   And I set "1st user" to owner and "another person" to editor
//   And I click "Save"
//   Then I am on "/settings/projects"
//   And I see "Project created successfully"
//   And project "some-name" has exactly those two members and not me
//   And the flow "flow-collaborator-added-email" has started for "1st user" and for "another person"
// The flow has started when each member's access email is queued.
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const first = person('First', 'User');
  const another = person('Another', 'Person');
  const suffix = hex();
  const name = `some-name-${suffix}`;
  removeAfter(name);

  await signedIn(page);
  await newProjectButton(page).click();
  await expectAt(page, `${PAGE}/new`);
  await field(page, 'Name').fill(`Some name ${suffix}`);
  await setRole(page, first.email, 'owner');
  await setRole(page, another.email, 'editor');
  await submit(page, 'Save');

  await expectAt(page, PAGE);
  await expect(
    flashMessages.toast(page, 'Project created successfully')
  ).toBeVisible();
  const created = projectsCalled(name);
  expect(created).toHaveLength(1);
  const { id } = created[0];
  expect(membersOf(id)).toEqual(
    [member(first, 'owner'), member(another, 'editor')].sort()
  );
  expect(membersOf(id).some(m => m.startsWith(user(ME).id))).toBe(false);
  expect(additionEmailsTo(first.id, id)).toHaveLength(1);
  expect(additionEmailsTo(another.id, id)).toHaveLength(1);
});

// @S06
// Scenario: A project cannot be saved without exactly one owner
//   Given I am on "/settings/projects/new"
//   Then I do not see "Every project must have exactly one owner. Please specify one below."
//   And "Save" is disabled
//   When I change the form without choosing an owner
//   Then I see "Every project must have exactly one owner. Please specify one below."
//   When I set two users to owner
//   Then I see "A project can have only one owner."
//   When I submit with no owner
//   Then no project is created
// "Save" being off is how one version refuses; the other refuses on press.
// What both keep is the message and that nothing is created, so the last
// When also sends the save past the form.
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = person('Amara', 'Banda');
  const bob = person('Bob', 'Jones');
  const name = `no-owner-${hex()}`;
  removeAfter(name);
  const lv = watchLiveView(page);

  await signedIn(page, `${PAGE}/new`);
  await expect(page.getByText(ONE_OWNER)).toHaveCount(0);

  await field(page, 'Name').fill(name);
  await expect(page.getByText(ONE_OWNER)).toBeVisible();

  await setRole(page, amara.email, 'owner');
  await setRole(page, bob.email, 'owner');
  await expect(page.getByText(TWO_OWNERS)).toBeVisible();

  await setRole(page, amara.email, '');
  await setRole(page, bob.email, '');
  await submit(page, 'Save');
  await expect(page.getByText(ONE_OWNER)).toBeVisible();
  await sendSaveWithoutMembers(page, lv, name);
  expect(projectsCalled(name)).toEqual([]);
  expect(lv.crashes()).toBe(0);
});

// @S07
// Scenario: The saved name is shown before saving, and a name with no usable characters is refused
//   Given I am on "/settings/projects/new"
//   When I type "Malawi HIV 2025" as the name
//   Then I see "Note that this project will be named: malawi-hiv-2025."
//   When I type "!!!" as the name and save
//   Then I see "can't be blank"
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await signedIn(page, `${PAGE}/new`);

  await field(page, 'Name').fill('Malawi HIV 2025');
  await expect(page.getByRole('main')).toContainText(
    /Note that this project will be named:\s*malawi-hiv-2025/
  );

  await field(page, 'Name').fill('!!!');
  await submit(page, 'Save');
  // Today's page shows the message twice
  await expect(page.getByText("can't be blank").first()).toBeVisible();
});

// @S08
// Scenario: Superuser changes a project's members
//   Given project "malawi-hiv" has owner "Alice Smith", editor "Bob Jones" and viewer "Charlie Brown"
//   And "Dana Ray" is a registered user not on the project
//   When I open "Edit" for "malawi-hiv"
//   And I set "Bob Jones" to admin, "Charlie Brown" to "No access" and "Dana Ray" to viewer
//   And I click "Save"
//   Then I am on "/settings/projects"
//   And I see "Project updated successfully"
//   And "malawi-hiv" has owner "Alice Smith", admin "Bob Jones" and viewer "Dana Ray"
//   And the flow "flow-collaborator-added-email" has started for "Dana Ray" only
//   And "Charlie Brown"'s and "Bob Jones"'s open pages on the project are handed to shared-project-scope S07 and S08
// The last Then is shared-project-scope's to test, on the project's pages.
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const alice = person('Alice', 'Smith');
  const bob = person('Bob', 'Jones');
  const charlie = person('Charlie', 'Brown');
  const dana = person('Dana', 'Ray');
  const malawi = project('malawi-hiv', {
    [alice.id]: 'owner',
    [bob.id]: 'editor',
    [charlie.id]: 'viewer',
  });

  await edit(page, malawi);
  await setRole(page, bob.email, 'admin');
  await setRole(page, charlie.email, '');
  await setRole(page, dana.email, 'viewer');
  await submit(page, 'Save');

  await expectAt(page, PAGE);
  await expect(
    flashMessages.toast(page, 'Project updated successfully')
  ).toBeVisible();
  expect(membersOf(malawi.id)).toEqual(
    [
      member(alice, 'owner'),
      member(bob, 'admin'),
      member(dana, 'viewer'),
    ].sort()
  );
  expect(additionEmailsTo(dana.id, malawi.id)).toHaveLength(1);
  expect(additionEmailsTo(alice.id, malawi.id)).toEqual([]);
  expect(additionEmailsTo(bob.id, malawi.id)).toEqual([]);
});

// @S09
// Scenario: Removing a member withdraws their credentials from the project
//   Given "Charlie Brown" is a viewer on "malawi-hiv" and owns credential "DHIS2 play" shared with it
//   When I set "Charlie Brown" to "No access" on the admin project form and save
//   Then "DHIS2 play" is no longer shared with "malawi-hiv"
//   And "DHIS2 play" still belongs to "Charlie Brown"
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const alice = person('Alice', 'Smith');
  const charlie = person('Charlie', 'Brown');
  const malawi = project('malawi-hiv', {
    [alice.id]: 'owner',
    [charlie.id]: 'viewer',
  });
  const credential = randomUUID();
  exec(`insert into credentials (id, name, user_id, schema, inserted_at, updated_at)
          values ('${credential}', 'DHIS2 play', '${charlie.id}', 'raw', now(), now());
        insert into project_credentials (id, project_id, credential_id, inserted_at, updated_at)
          values (gen_random_uuid(), '${malawi.id}', '${credential}', now(), now());`);
  cleanups.push(() =>
    exec(`delete from credentials where id = '${credential}'`)
  );

  await edit(page, malawi);
  await setRole(page, charlie.email, '');
  await submit(page, 'Save');

  await expectAt(page, PAGE);
  expect(
    sql(
      `select 1 from project_credentials where project_id = '${malawi.id}'
       and credential_id = '${credential}'`
    )
  ).toEqual([]);
  expect(
    sql(`select user_id from credentials where id = '${credential}'`)
  ).toEqual([{ user_id: charlie.id }]);
});

// @S10
// Scenario: Membership changes made here are audited against the superuser
//   Given I am superuser "root@example.org"
//   When I change "Bob Jones" from editor to admin on "malawi-hiv" and save
//   Then an audit event "collaborator_role_changed" is recorded for "malawi-hiv" with actor "root@example.org", before role "editor" and after role "admin"
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const alice = person('Alice', 'Smith');
  const bob = person('Bob', 'Jones');
  const malawi = project('malawi-hiv', {
    [alice.id]: 'owner',
    [bob.id]: 'editor',
  });

  await edit(page, malawi);
  await setRole(page, bob.email, 'admin');
  await submit(page, 'Save');

  await expectAt(page, PAGE);
  expect(
    sql(
      `select actor_id, changes->'before'->>'role' as before,
              changes->'after'->>'role' as after
       from audit_events where item_id = '${malawi.id}'
       and event = 'collaborator_role_changed'`
    )
  ).toEqual([{ actor_id: user(ME).id, before: 'editor', after: 'admin' }]);
});

// @S11
// Scenario: Cancel leaves the project form without saving
//   Given I am on "Edit" for "malawi-hiv"
//   When I set "Bob Jones" to "No access" and click "Cancel"
//   Then I am on "/settings/projects"
//   And "Bob Jones" is still a member of "malawi-hiv"
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const alice = person('Alice', 'Smith');
  const bob = person('Bob', 'Jones');
  const malawi = project('malawi-hiv', {
    [alice.id]: 'owner',
    [bob.id]: 'editor',
  });

  await edit(page, malawi);
  await setRole(page, bob.email, '');
  await clickable(page, 'Cancel', { exact: true }).click();

  await expectAt(page, PAGE);
  expect(membersOf(malawi.id)).toEqual(
    [member(alice, 'owner'), member(bob, 'editor')].sort()
  );
});

// @S12
// Scenario: Only a project already scheduled for deletion can be purged now
//   Given project "alpha-project" is not scheduled for deletion
//   And project "beta-project" is scheduled for deletion on 21 October
//   When I open the "Actions" menu on each row
//   Then "alpha-project" offers "Delete" and neither "Cancel deletion" nor "Delete now"
//   And "beta-project" offers "Cancel deletion" and "Delete now" and not "Delete"
//   And the scheduled deletion column for "beta-project" shows "21 Oct"
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const alpha = project('alpha-project');
  const beta = project('beta-project', {}, { scheduledDeletion: SCHEDULED });

  await signedIn(page);
  await expect(await cell(page, beta.name, 'Scheduled Deletion')).toHaveText(
    /21 Oct/
  );
  await expect(await cell(page, alpha.name, 'Scheduled Deletion')).toHaveText(
    /^\s*$/
  );

  let menu = await openActions(page, alpha.name);
  await expect(menuAction(menu, 'Delete')).toBeVisible();
  await expect(menuAction(menu, 'Cancel deletion')).toHaveCount(0);
  await expect(menuAction(menu, 'Delete now')).toHaveCount(0);

  await open(page, PAGE);
  menu = await openActions(page, beta.name);
  await expect(menuAction(menu, 'Cancel deletion')).toBeVisible();
  await expect(menuAction(menu, 'Delete now')).toBeVisible();
  await expect(menuAction(menu, 'Delete')).toHaveCount(0);
});

// @S13
// Scenario: Delete starts the schedule-deletion flow
//   Given project "alpha-project" is not scheduled for deletion
//   When I click "Delete" on "alpha-project"
//   Then I am on "/settings/projects/<alpha-project id>/delete" with the deletion modal over the list
//   And the flow "flow-schedule-project-deletion" has started (its S10)
// What the dialog does is shared-project-deletion-modal's.
test('@S13', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const alpha = project('alpha-project');
  const other = project('other-project');

  await signedIn(page);
  const menu = await openActions(page, alpha.name);
  await menuAction(menu, 'Delete').click();

  await expectAt(page, deletePath(alpha.id));
  await expect(modalTitle(page, 'Delete project')).toBeVisible();
  // The dialog hides the list from the accessibility tree, so look for text:
  // another project's row, which the dialog doesn't mention
  await expect(
    page.getByText(other.name, { exact: true }).filter({ visible: true })
  ).toBeVisible();
});

// @S14
// Scenario: Cancel deletion hands off to the schedule-deletion flow
//   Given project "beta-project" is scheduled for deletion
//   When I click "Cancel deletion" on "beta-project"
//   Then I see "Project deletion canceled"
//   And the row for "beta-project" offers "Delete" again
//   And the rest is flow "flow-schedule-project-deletion" S11
test('@S14', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const beta = project('beta-project', {}, { scheduledDeletion: SCHEDULED });

  await signedIn(page);
  let menu = await openActions(page, beta.name);
  await menuAction(menu, 'Cancel deletion').click();

  await expect(
    flashMessages.toast(page, 'Project deletion canceled')
  ).toBeVisible();
  await expect.poll(() => scheduledDeletionOf(beta.id)).toBeNull();
  menu = await openActions(page, beta.name);
  await expect(menuAction(menu, 'Delete')).toBeVisible();
  await expect(menuAction(menu, 'Delete now')).toHaveCount(0);
});

// @S15
// Scenario: Delete now hands off to the schedule-deletion flow
//   Given project "beta-project" is scheduled for deletion
//   When I click "Delete now" on "beta-project"
//   Then I am on "/settings/projects/<beta-project id>/delete"
//   And the flow "flow-schedule-project-deletion" has started (its S12, through shared-project-deletion-modal S04)
test('@S15', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const beta = project('beta-project', {}, { scheduledDeletion: SCHEDULED });

  await signedIn(page);
  const menu = await openActions(page, beta.name);
  await menuAction(menu, 'Delete now').click();

  await expectAt(page, deletePath(beta.id));
  // What confirming does is shared-project-deletion-modal S04
  await expect(modalTitle(page, 'Delete project')).toBeVisible();
});

// Inherited from shared-admin-space: the gate, and the settings layout and
// side menu with "Projects" current.
test.describe('shared-admin-space', () => {
  test(
    'shared-admin-space@S01 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S01(page, PAGE, ME, 'Projects');
    }
  );

  test(
    'shared-admin-space@S02 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S02(page, PAGE, REGULAR);
    }
  );

  test('shared-admin-space@S03 on admin-projects', { tag: '@pending' }, () => {
    test.skip(
      true,
      'needs a socket mount that skips the HTTP check, which no browser action produces; the page cannot be reached with a forged mount'
    );
  });

  for (const id of ['S04', 'S05'])
    test(
      `shared-admin-space@${id} on admin-projects`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: it is about "/dashboard"; the inherits line names only S01, S02, S03 and S06'
        );
      }
    );

  test(
    'shared-admin-space@S06 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await adminSpace.S06(page, browser, PAGE, ME);
    }
  );

  test('shared-admin-space@S07 on admin-projects', { tag: '@pending' }, () => {
    test.skip(
      true,
      'variant settings-menu-extension is not configured on this instance'
    );
  });
});

// Inherited from shared-authenticated-session, on "/settings/projects".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      // The admin menu has no "Credentials"; "Audit" is a label it does have
      await authenticatedSession.S07(
        page,
        browser,
        PAGE,
        '/settings/audit',
        ME,
        'Audit'
      );
    }
  );

  for (const id of ['S04', 'S05', 'S06'])
    test(
      `shared-authenticated-session@${id} on admin-projects`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'variant require-email-verification is not configured on this instance'
        );
      }
    );

  for (const id of ['S08', 'S09', 'S10', 'S11'])
    test(
      `shared-authenticated-session@${id} on admin-projects`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line says S08 to S10 are not on the settings layout, and S11 is a first-setup redirect before any page'
        );
      }
    );
});

// Inherited from shared-project-header: the global picker, the confirmation
// banner and the account menu (no-project parts).
test.describe('shared-project-header', () => {
  for (const id of ['S04', 'S06', 'S08', 'S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on admin-projects`,
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test(
    'shared-project-header@S14 on admin-projects',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );

  for (const id of [
    'S01',
    'S02',
    'S03',
    'S05',
    'S07',
    'S09',
    'S15',
    'S16',
    'S17',
  ])
    test(
      `shared-project-header@${id} on admin-projects`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line takes only the no-project parts (S04, S06, S08, S10 to S14, S18)'
        );
      }
    );
});

// Inherited from shared-project-deletion-modal, on the admin host:
// "/settings/projects/<id>/delete", returning to "/settings/projects" both
// after a delete and on backing out. The "Cancel" row of S05's Examples
// returns to project settings, so it belongs to that host.
test.describe('shared-project-deletion-modal', () => {
  // Given the modal is open on "/settings/projects/<id>/delete"
  const deletionOf = (page: Page) => async (id: string) => {
    await open(page, deletePath(id));
  };

  test(
    'shared-project-deletion-modal@S01 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const p = project('project');
      await signInAs(page, ME);
      await projectDeletionModal.S01(page, p, deletionOf(page));
    }
  );

  test(
    'shared-project-deletion-modal@S02 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const p = project('project');
      const lv = watchLiveView(page);
      await signInAs(page, ME);
      await projectDeletionModal.S02(page, p, deletionOf(page), typed =>
        sendProjectDeletion(page, lv, typed)
      );
    }
  );

  test(
    'shared-project-deletion-modal@S03 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const p = project('project');
      await signInAs(page, ME);
      await projectDeletionModal.S03(page, p, deletionOf(page), PAGE);
    }
  );

  test(
    'shared-project-deletion-modal@S04 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const p = project('project', {}, { scheduledDeletion: SCHEDULED });
      await signInAs(page, ME);
      await projectDeletionModal.S04(page, p, deletionOf(page), PAGE);
    }
  );

  test(
    'shared-project-deletion-modal@S05 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const p = project('project');
      await signInAs(page, ME);
      await projectDeletionModal.S05(page, p, deletionOf(page), 'Close', PAGE);
    }
  );
});

// Inherited from shared-flash-messages. This page is on the settings layout,
// whose toast is S07; the deletion dialog's redirect carries a flash (S05).
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S05 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const p = project('project');
      await signInAs(page, ME);
      await flashMessages.S05(
        page,
        'Project scheduled for deletion',
        async () => {
          await open(page, deletePath(p.id));
          const d = modal(page, 'Delete project');
          await expect(modalTitle(page, 'Delete project')).toBeVisible();
          await field(d, 'Project name').fill(p.name);
          await field(d, 'Project name').blur();
          await submit(d, 'Delete project');
        },
        PAGE
      );
    }
  );

  test(
    'shared-flash-messages@S07 on admin-projects',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const beta = project(
        'beta-project',
        {},
        { scheduledDeletion: SCHEDULED }
      );
      await flashMessages.S07(page, 'Project deletion canceled', async () => {
        await signedIn(page);
        const menu = await openActions(page, beta.name);
        await menuAction(menu, 'Cancel deletion').click();
      });
    }
  );

  for (const [id, why] of [
    ['S01', 'it is about the live layout; the settings layout toast is S07'],
    ['S02', 'it is about the live layout; the settings layout toast is S07'],
    ['S03', 'it is about the live layout; the settings layout toast is S07'],
    ['S04', 'it is about the live layout; the settings layout toast is S07'],
    [
      'S06',
      'nothing on this page sends a "not found" or "no access" nav flash',
    ],
    ['S08', 'it is about the sign-in and account forms'],
  ])
    test(
      `shared-flash-messages@${id} on admin-projects`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(true, `not reachable here: ${why}`);
      }
    );
});
