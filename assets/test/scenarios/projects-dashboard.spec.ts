// Scenarios from annotations/views/projects-dashboard.md.
//
// Who's who: "I" is editor@openfn.org (Esther Editor), an editor on the seeded
// example-project. "project-1", "Malawi HIV" and the rest are projects each
// test seeds and removes again; projects a test creates through the form are
// removed by name. Every test also puts editor's account back as it found it.
import { expect, test, type Locator, type Page } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import {
  expectAt,
  field,
  fieldBlock,
  goBack,
  keepAccount,
  mailbox,
  makeSupportUser,
  manifest,
  open,
  projectsNamed,
  removeProjectsNamed,
  seedProject,
  signInAs,
  sortByColumnNamed,
  sql,
  submitWithExtraField,
  user,
  tagFor,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PAGE = '/projects';
const CREATED = 'my-awesome-project';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  removeProjectsNamed(CREATED);
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project "<name>" exists ... (removed after the test)
function given(...args: Parameters<typeof seedProject>) {
  const project = seedProject(...args);
  cleanups.push(project.remove);
  return project;
}

// Given I am signed in and on "/projects"
async function signedIn(page: Page, email = ME) {
  await signInAs(page, email);
  await open(page, PAGE);
}

// The project rows: rows with cells rather than column headers
const rows = (page: Page) =>
  page.getByRole('row').filter({ has: page.getByRole('cell') });

const row = (page: Page, name: string) =>
  rows(page).filter({ has: page.getByRole('cell', { name, exact: true }) });

// The project names in the order they are listed
const listedNames = async (page: Page) =>
  (await rows(page).allInnerTexts()).map(text => text.split('\t')[0].trim());

// The cell in <name>'s row under the column headed <column>
async function cell(page: Page, name: string, column: string) {
  const headers = await page.getByRole('columnheader').allInnerTexts();
  const index = headers.findIndex(header => header.trim() === column);
  expect(index, `a "${column}" column`).toBeGreaterThanOrEqual(0);
  return row(page, name).getByRole('cell').nth(index);
}

const sortHeader = (page: Page, column: string) =>
  page.getByRole('columnheader').getByRole('link', { name: column });

const createModal = (page: Page) =>
  page.getByRole('dialog', { name: 'Create a new project' });

// When I open "Create project" and enter <name> and <description>
async function fillCreateForm(page: Page, name: string, description?: string) {
  await page.getByRole('button', { name: 'Create project' }).click();
  const modal = createModal(page);
  await expect(modal).toBeVisible();
  await field(modal, 'Name').fill(name);
  if (description !== undefined)
    await field(modal, 'Description').fill(description);
  return modal;
}

// When I create project <name> through the form
async function createProject(page: Page, name = 'My Awesome Project') {
  const modal = await fillCreateForm(page, name);
  await modal.getByRole('button', { name: 'Create project' }).click();
}

const projectCount = () =>
  sql<{ n: number }>(`select count(*)::int as n from projects`)[0].n;

// When I click <button> — a disabled button fails the scenario but lets the
// remaining steps still report what they see
async function clickIfYouCan(button: Locator) {
  await expect
    .soft(button, 'should be clickable')
    .toBeEnabled({ timeout: 5000 });
  if (await button.isEnabled()) await button.click();
}

// Three of my projects whose name order and last-change order differ
function threeProjects() {
  given(
    'aaa-scenario-project',
    { [ME]: 'editor' },
    {
      workflows: [{ updated_at: '2024-01-01 12:00:00' }],
    }
  );
  given(
    'zzz-scenario-project',
    { [ME]: 'editor' },
    {
      workflows: [{ updated_at: '2023-01-01 12:00:00' }],
    }
  );
  // The seeded project's workflow was last changed when the instance was seeded
  const seeded = manifest().projects[0].name;
  return {
    byName: ['aaa-scenario-project', seeded, 'zzz-scenario-project'],
    byLastUpdated: ['zzz-scenario-project', 'aaa-scenario-project', seeded],
  };
}

// @S01
// Scenario: I see the projects I belong to and no others
//   Given I am an owner of "project-1" and an admin of "project-2"
//   And "project-3" exists with only other members
//   When I open "/projects"
//   Then I see rows for "project-1" and "project-2"
//   And I do not see "project-3"
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  given('project-1', { [ME]: 'owner' });
  given('project-2', { [ME]: 'admin' });
  given('project-3', { [OTHER]: 'owner' });

  await signedIn(page);

  await expect(row(page, 'project-1')).toBeVisible();
  await expect(row(page, 'project-2')).toBeVisible();
  await expect(row(page, 'project-3')).toHaveCount(0);
  await expect(page.getByText('project-3')).toHaveCount(0);
});

// @S02
// Scenario: Each row shows my role, counts and last change
//   Given I am an admin of "project-2", which has an owner and me as collaborators
//   And "project-2" has two workflows last updated "2023-10-05 12:00" and "2023-10-03 12:00" and one deleted workflow
//   When I open "/projects"
//   Then the "project-2" row shows role "Admin"
//   And workflows "2"
//   And collaborators "2", linking to "/projects/<project-2 id>/settings#collaboration"
//   And last updated at "2023-10-05 12:00:00 UTC", shown per shared-local-datetime
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  const project2 = given(
    'project-2',
    { [OTHER]: 'owner', [ME]: 'admin' },
    {
      workflows: [
        { updated_at: '2023-10-05 12:00:00' },
        { updated_at: '2023-10-03 12:00:00' },
        // changed later, so it would show if deleted workflows counted
        { updated_at: '2023-10-07 12:00:00', deleted: true },
      ],
    }
  );

  await signedIn(page);

  await expect(await cell(page, 'project-2', 'Role')).toHaveText('Admin');
  await expect(await cell(page, 'project-2', 'Workflows')).toHaveText('2');
  const collaborators = (
    await cell(page, 'project-2', 'Collaborators')
  ).getByRole('link');
  await expect(collaborators).toHaveText('2');
  await expect(collaborators).toHaveAttribute(
    'href',
    `/projects/${project2.id}/settings#collaboration`
  );
  // shared-local-datetime: another year shows the date; hover shows UTC
  const lastUpdated = (await cell(page, 'project-2', 'Last Updated')).getByText(
    /\d/
  );
  await expect(lastUpdated).toHaveText(/^2023-10-05,/);
  await lastUpdated.hover();
  await expect(page.getByRole('tooltip')).toContainText(
    '2023-10-05 12:00:00 UTC'
  );
});

// @S03 @variant:support-user
// Scenario: Support users also see projects that asked for support
//   Given I am a support user and an owner of "project-1"
//   And "project-4" allows support access and I am not a member
//   And "project-3" does not allow support access and I am not a member
//   When I open "/projects"
//   Then I see "project-1" with role "Owner"
//   And I see "project-4" with role "Support"
//   And I do not see "project-3"
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  cleanups.push(makeSupportUser(ME));
  given('project-1', { [ME]: 'owner' });
  given('project-4', { [OTHER]: 'owner' }, { allowSupportAccess: true });
  given('project-3', { [OTHER]: 'owner' });

  await signedIn(page);

  await expect(await cell(page, 'project-1', 'Role')).toHaveText('Owner');
  await expect(await cell(page, 'project-4', 'Role')).toHaveText('Support');
  await expect(row(page, 'project-3')).toHaveCount(0);
});

// @S04
// Scenario: Someone with no projects is offered to create one
//   Given I am not a member of any project
//   When I open "/projects"
//   Then I see "No projects found." and "Create a new one."
//   When I click "Create a new one."
//   Then the "Create a new project" modal opens
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  // super@openfn.org is seeded with no projects
  const NOBODY = 'super@openfn.org';
  expect(
    sql(`select 1 from project_users where user_id = '${user(NOBODY).id}'`)
  ).toEqual([]);

  await signedIn(page, NOBODY);

  await expect(page.getByText('No projects found.')).toBeVisible();
  await expect(page.getByText('Create a new one.')).toBeVisible();
  await page.getByRole('button', { name: /Create a new one\./ }).click();
  await expect(createModal(page)).toBeVisible();
});

// @S05
// Scenario: Sorting by name
//   Given I am a member of three projects
//   When I open "/projects"
//   Then the projects are listed by name, A to Z
//   When I click the "Name" column header
//   Then they are listed Z to A
//   When I click it again
//   Then they are listed A to Z
test('@S05', { tag: '@passing-old' }, async ({ page }) => {
  const { byName } = threeProjects();

  await signedIn(page);
  await expect.poll(() => listedNames(page)).toEqual(byName);

  await sortHeader(page, 'Name').click();
  await expect.poll(() => listedNames(page)).toEqual([...byName].reverse());

  await sortHeader(page, 'Name').click();
  await expect.poll(() => listedNames(page)).toEqual(byName);
});

// @S06
// Scenario: Sorting by last updated
//   Given I am a member of three projects with workflows changed at different times
//   When I click the "Last Updated" column header
//   Then the projects are listed oldest change first
//   When I click it again
//   Then they are listed newest change first
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  const { byLastUpdated } = threeProjects();
  await signedIn(page);

  await sortHeader(page, 'Last Updated').click();
  await expect.poll(() => listedNames(page)).toEqual(byLastUpdated);

  await sortHeader(page, 'Last Updated').click();
  await expect
    .poll(() => listedNames(page))
    .toEqual([...byLastUpdated].reverse());
});

// @S07
// Scenario: A crafted sort request is ignored
//   Given I am on "/projects" with three projects
//   When a "sort" event arrives with a column that does not exist
//   Then the list stays sorted by name, A to Z
//   And the page keeps working
test('@S07', { tag: '@passing-old' }, async ({ page }) => {
  const { byName, byLastUpdated } = threeProjects();
  await signedIn(page);

  await sortByColumnNamed(page, 'Name', 'no_such_column');

  await expect.poll(() => listedNames(page)).toEqual(byName);
  // Still working: the page is connected and another sort takes effect
  await page.reload();
  await page.locator('.phx-connected').first().waitFor();
  await sortHeader(page, 'Last Updated').click();
  await expect.poll(() => listedNames(page)).toEqual(byLastUpdated);
});

// @S08
// Scenario: A row leads into the project
//   Given I am a member of "project-1"
//   When I click anywhere on the "project-1" row
//   Then I am on "/projects/<project-1 id>/w"
//   When I go back and click the collaborators count on that row
//   Then I am on "/projects/<project-1 id>/settings#collaboration"
//   When I go back and click "History" on that row
//   Then I am on "/projects/<project-1 id>/history"
test('@S08', { tag: '@passing-old' }, async ({ page }) => {
  const project1 = given('project-1', { [ME]: 'editor' });
  await signedIn(page);

  await (await cell(page, 'project-1', 'Role')).click();
  await expectAt(page, `/projects/${project1.id}/w`);

  await goBack(page);
  await (await cell(page, 'project-1', 'Collaborators'))
    .getByRole('link')
    .click();
  await expect(page).toHaveURL(
    new RegExp(`/projects/${project1.id}/settings#collaboration$`)
  );

  await goBack(page);
  await row(page, 'project-1').getByRole('link', { name: 'History' }).click();
  await expectAt(page, `/projects/${project1.id}/history`);
});

// @S09
// Scenario: Creating a project makes me its owner
//   Given I am on "/projects"
//   When I open "Create project", enter name "My Awesome Project" and description "This is a really awesome project"
//   And I click "Create project"
//   Then I am on "/projects" and see "Project created successfully"
//   And "my-awesome-project" is listed with role "Owner"
test('@S09', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);

  const modal = await fillCreateForm(
    page,
    'My Awesome Project',
    'This is a really awesome project'
  );
  await modal.getByRole('button', { name: 'Create project' }).click();

  await expectAt(page, PAGE);
  await expect(page.getByText('Project created successfully')).toBeVisible();
  await expect(await cell(page, CREATED, 'Role')).toHaveText('Owner');
  expect(projectsNamed(CREATED)).toEqual([
    expect.objectContaining({ members: [`${user(ME).email}:owner`] }),
  ]);
});

// @S10
// Scenario: I see the stored name before creating
//   Given the "Create a new project" modal is open
//   When I type "My Awesome Project" in "Name"
//   Then I see "Your project will be named my-awesome-project."
test('@S10', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);

  const modal = await fillCreateForm(page, 'My Awesome Project');

  await expect(modal).toContainText(
    'Your project will be named my-awesome-project.'
  );
});

// @S11
// Scenario: A name with no usable characters is refused
//   Given the "Create a new project" modal is open
//   When I enter name "!!!" and submit
//   Then I see "can't be blank" under "Name"
//   And no project is created
// Fails on Lightning: once "!!!" is typed the name is invalid and "Create
// project" is disabled, so the form can't be submitted. The error shows and
// nothing is created.
test('@S11', { tag: ['@pending', '@serial'] }, async ({ page }) => {
  const before = projectCount();
  await signedIn(page);

  const modal = await fillCreateForm(page, '!!!');
  await clickIfYouCan(modal.getByRole('button', { name: 'Create project' }));

  await expect(
    fieldBlock(modal, 'Name').getByText("can't be blank")
  ).toBeVisible();
  expect(projectCount()).toBe(before);
});

// @S12
// Scenario: A description over 240 characters is refused
//   Given the "Create a new project" modal is open
//   When I enter a name and a 241-character description
//   Then I see an error under "Description"
//   And the "Create project" button is disabled
test('@S12', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);

  const modal = await fillCreateForm(
    page,
    'My Awesome Project',
    'x'.repeat(241)
  );

  await expect(
    fieldBlock(modal, 'Description').getByRole('paragraph')
  ).not.toHaveCount(0);
  await expect(
    modal.getByRole('button', { name: 'Create project' })
  ).toBeDisabled();
});

// @S13
// Scenario: Cancelling creates nothing
//   Given I have filled in the "Create a new project" modal
//   When I click "Cancel"
//   Then I am on "/projects"
//   And no project has been created
test('@S13', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const before = projectCount();
  await signedIn(page);
  const modal = await fillCreateForm(
    page,
    'My Awesome Project',
    'This is a really awesome project'
  );

  await modal.getByRole('button', { name: 'Cancel' }).click();

  await expect(modal).toBeHidden();
  await expectAt(page, PAGE);
  expect(projectCount()).toBe(before);
});

// @S14
// Scenario: The form cannot be used to attach a project under someone else's
//   Given "other-project" exists and I have no role on it
//   When I submit the create form with an extra "parent_id" of "other-project"
//   Then a top-level project is created with me as its only member
test('@S14', { tag: '@passing-old' }, async ({ page }) => {
  const other = given('other-project', { [OTHER]: 'owner' });
  await signedIn(page);

  const modal = await fillCreateForm(page, 'My Awesome Project');
  await submitWithExtraField(
    modal.locator('form'),
    'Create project',
    'project[parent_id]',
    other.id
  );

  await expect(page.getByText('Project created successfully')).toBeVisible();
  expect(projectsNamed(CREATED)).toEqual([
    expect.objectContaining({
      parent_id: null,
      members: [`${user(ME).email}:owner`],
    }),
  ]);
  expect(projectsNamed('other-project')).toEqual([
    expect.objectContaining({ members: [`${user(OTHER).email}:owner`] }),
  ]);
});

// @S15
// Scenario: Creating a project does not email me that I was added to it
//   When I create project "my-awesome-project"
//   Then the flow "flow-collaborator-added-email" has not started for me
test('@S15', { tag: '@passing-old' }, async ({ page, request }) => {
  const sentBefore = (await mailbox(request)).length;
  await signedIn(page);

  await createProject(page);
  await expect(page.getByText('Project created successfully')).toBeVisible();

  // The flow starts with a queued "project_addition" notification
  const [project] = projectsNamed(CREATED);
  expect(
    sql(
      `select id from oban_jobs
       where args->>'type' = 'project_addition'
       and args->>'project_user_id' in (
         select id::text from project_users where project_id = '${project.id}')`
    )
  ).toEqual([]);
  const after = await mailbox(request);
  expect(
    after.slice(0, after.length - sentBefore).filter(m => m.to.includes(ME))
  ).toEqual([]);
});

// @S16
// Scenario: The welcome text points to help
//   When I open "/projects"
//   Then I eventually see a greeting with my first name
//   And a link to "docs.openfn.org" and a link to "community.openfn.org", each opening in a new tab
test('@S16', { tag: '@passing-old' }, async ({ page }) => {
  const [{ first_name }] = sql<{ first_name: string }>(
    `select first_name from users where id = '${user(ME).id}'`
  );
  await signedIn(page);

  await expect(
    page.getByRole('heading', { level: 1 }).filter({ hasText: first_name })
  ).toBeVisible({ timeout: 15000 });
  for (const name of ['docs.openfn.org', 'community.openfn.org']) {
    const link = page.getByRole('link', { name });
    await expect(link).toBeVisible({ timeout: 20000 });
    await expect(link).toHaveAttribute('href', `https://${name}`);
    await expect(link).toHaveAttribute('target', '_blank');
  }
});

// @S17
// Scenario: The instance root opens the projects list
//   Given I am logged in
//   When I visit "/"
//   Then I am on "/projects"
test('@S17', { tag: '@passing-old' }, async ({ page }) => {
  await signInAs(page, ME);

  await page.goto('/');

  await expectAt(page, PAGE);
});

// @S18
// Scenario: The owner lands here after scheduling deletion
//   Given the flow "flow-schedule-project-deletion" has been completed by me for "project-1"
//   Then I am on "/projects"
//   And I see "Project scheduled for deletion"
test('@S18', { tag: '@passing-old' }, async ({ page }) => {
  const project1 = given('project-1', { [ME]: 'owner' });
  await signInAs(page, ME);

  // flow-schedule-project-deletion: the owner deletes it from its settings
  await open(page, `/projects/${project1.id}/settings`);
  await page.getByRole('link', { name: 'Delete project' }).click();
  const modal = page.getByRole('dialog', { name: 'Delete project' });
  await field(modal, 'Project name').fill('project-1');
  await field(modal, 'Project name').blur();
  await modal.getByRole('button', { name: 'Delete project' }).click();

  await expectAt(page, PAGE);
  await expect(page.getByText('Project scheduled for deletion')).toBeVisible();
});

// @S19
// Scenario: A newly invited collaborator finds their project here
//   Given the flow "flow-invite-new-collaborator" has added me as an editor of "Malawi HIV"
//   And I have signed in
//   Then I am on "/projects" and see "Malawi HIV" with role "Editor"
test('@S19', { tag: '@passing-old' }, async ({ page }) => {
  // The flow's outcome: I am an editor of "Malawi HIV"
  given('Malawi HIV', { [OTHER]: 'owner', [ME]: 'editor' });

  await signInAs(page, ME);

  await expectAt(page, PAGE);
  await expect(await cell(page, 'Malawi HIV', 'Role')).toHaveText('Editor');
});

// Inherited from shared-authenticated-session, on "/projects".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S07(page, browser, PAGE, '/credentials', ME);
    }
  );

  for (const [id, variant] of [
    ['S04', 'require-email-verification'],
    ['S05', 'require-email-verification'],
    ['S06', 'require-email-verification'],
    ['S08', 'book-demo-banner'],
    ['S09', 'book-demo-banner'],
    ['S10', 'gdpr-banner'],
    ['S11', 'first-setup-open'],
  ])
    test(
      `shared-authenticated-session@${id} on projects-dashboard`,
      { tag: tagFor(id, ['S01', 'S02', 'S03', 'S07']) },
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

// Inherited from shared-project-header: the global picker, the role menu and
// the account menu on a page without a project.
test.describe('shared-project-header', () => {
  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on projects-dashboard`,
      { tag: tagFor(id, ['S11', 'S12', 'S13', 'S18', 'S10', 'S17']) },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test(
    'shared-project-header@S17 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S17(page, PAGE);
    }
  );

  test(
    'shared-project-header@S14 on projects-dashboard',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );
});

// Inherited from shared-local-datetime: the "Last Updated" column.
test.describe('shared-local-datetime', () => {
  // Given one of my projects has a workflow last changed at <utc>, and today
  // is <today>
  async function lastUpdated(
    page: Page,
    { utc, today }: { utc?: string; today?: string }
  ) {
    const name = 'dated-scenario-project';
    given(
      name,
      { [ME]: 'editor' },
      {
        workflows: utc ? [{ updated_at: utc }] : [],
      }
    );
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, PAGE);
    return cell(page, name, 'Last Updated');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on projects-dashboard',
      { tag: '@passing-old' },
      async ({ page }) => {
        await localDatetime.S01(
          page,
          await lastUpdated(page, localDatetime.given.S01)
        );
      }
    );
  });

  // S06 fails on this page: "Last Updated" is read back at whole seconds, so
  // the tooltip and the copy both read "2026-10-14 08:30:07 UTC".
  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on projects-dashboard`,
      { tag: tagFor(id, ['S01', 'S02', 'S04', 'S05']) },
      async ({ page }) => {
        await localDatetime[id](
          page,
          await lastUpdated(page, localDatetime.given[id])
        );
      }
    );

  // A project with no workflows has no last change.
  // Fails on this page: it renders its own "N/A" instead of "--".
  test(
    'shared-local-datetime@S07 on projects-dashboard',
    { tag: '@pending' },
    async ({ page }) => {
      await localDatetime.S07(page, await lastUpdated(page, {}));
    }
  );

  test(
    'shared-local-datetime@S03 on projects-dashboard',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'not reachable here: "Last Updated" always uses the default format, never relative_detailed'
      );
    }
  );
});

// Inherited from shared-flash-messages: the message after creating a project,
// and the Not Found card a refused project link leaves on this page.
test.describe('shared-flash-messages', () => {
  const CREATED_FLASH = 'Project created successfully';
  const create = (page: Page) => () => createProject(page);

  test(
    'shared-flash-messages@S01 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S01(page, CREATED_FLASH, create(page));
    }
  );

  test(
    'shared-flash-messages@S02 on projects-dashboard',
    { tag: '@pending' },
    () => {
      test.skip(true, 'not reachable here: this page puts no error flash');
    }
  );

  test(
    'shared-flash-messages@S03 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S03(page, CREATED_FLASH, create(page));
    }
  );

  test(
    'shared-flash-messages@S04 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S04(page, CREATED_FLASH, create(page), async () => {
        // Sorting makes the list render again
        await sortHeader(page, 'Name').click();
        await expect(row(page, CREATED)).toBeVisible();
      });
    }
  );

  test(
    'shared-flash-messages@S05 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S05(page, CREATED_FLASH, create(page), PAGE);
    }
  );

  test(
    'shared-flash-messages@S06 on projects-dashboard',
    { tag: '@passing-old' },
    async ({ page }) => {
      const notMine = given('not-my-project', { [OTHER]: 'owner' });
      await signInAs(page, ME);
      await open(page, '/profile');

      await flashMessages.S06(
        page,
        () => open(page, `/projects/${notMine.id}/w`),
        PAGE,
        // the list of my projects
        row(page, manifest().projects[0].name)
      );
    }
  );
});
