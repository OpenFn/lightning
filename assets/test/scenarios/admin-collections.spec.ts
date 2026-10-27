// Scenarios from annotations/views/admin-collections.md.
//
// Who's who: "I" am owner@openfn.org, made a superuser for each test (the
// role is put back afterwards) and a member of none of the seeded projects.
// editor@openfn.org is the regular user. The projects a scenario names
// ("Malawi HIV", "Kenya TB") are seeded per test with a fresh name
// ("malawi-hiv-<hex>"), and collections get a fresh name too
// ("patients-<hex>"), since every worker's test sees every collection on the
// instance. Removing a project removes its collections and their records.
import { randomUUID } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import {
  chosenOption,
  createFirstButton,
  rowAction,
} from './pages/admin-collections';
import * as adminSpace from './shared/admin-space';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import {
  clickable,
  collectionById,
  collectionsCalled,
  field,
  keepAccount,
  makeSuperuser,
  modal,
  modalTitle,
  open,
  recordsOfCollection,
  seedCollection,
  seedProjectWith,
  signInAs,
  sql,
  submit,
  submitButton,
  tagFor,
  withCollectionLimit,
} from './steps';

const ME = 'owner@openfn.org';
const REGULAR = 'editor@openfn.org';
const PAGE = '/settings/collections';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), makeSuperuser(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

const hex = () => randomUUID().slice(0, 8);

// Given project "<base>-<hex>", with no members (removed after the test)
function project(base: string) {
  const seeded = seedProjectWith(`${base}-${hex()}`, {});
  cleanups.push(seeded.remove);
  return seeded;
}

const collectionsOnInstance = () =>
  sql<{ n: number }>('select count(*)::int as n from collections')[0].n;

// Given I am a superuser, signed in and on the collections page
async function signedIn(page: Page) {
  await signInAs(page, ME);
  await open(page, PAGE);
}

// The rows of collection <name>, or only the one in project <projectName>
const row = (page: Page, name: string, projectName?: string) => {
  const rows = page.getByRole('row').filter({ hasText: name });
  return projectName
    ? rows.filter({
        has: page.getByRole('cell', { name: projectName, exact: true }),
      })
    : rows;
};

// Where the column headed <header> sits
async function columnOf(page: Page, header: string) {
  const headers = (await page.getByRole('columnheader').allInnerTexts()).map(
    h => h.trim()
  );
  const column = headers.indexOf(header);
  expect(column, `a "${header}" column`).toBeGreaterThanOrEqual(0);
  return column;
}

// The cell of <name>'s only row under the column headed <header>
const cells = async (page: Page, name: string, header: string) =>
  row(page, name)
    .getByRole('cell')
    .nth(await columnOf(page, header));

// The projects listed for collection <name>, one per row, sorted
async function projectsListedFor(page: Page, name: string) {
  const column = await columnOf(page, 'Project');
  const texts = await Promise.all(
    (await row(page, name).all()).map(r =>
      r.getByRole('cell').nth(column).innerText()
    )
  );
  return texts.map(t => t.trim()).sort();
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

const createDialog = (page: Page) => modal(page, 'Create Collection');
const editDialog = (page: Page) => modal(page, 'Edit Collection');
const deleteDialog = (page: Page) => modal(page, 'Delete collection');

// When I click "Create collection" (or "Create a new one." when the list is
// empty: other tests' collections come and go)
async function openCreate(page: Page) {
  await clickable(page, 'Create collection', { exact: true })
    .or(createFirstButton(page))
    .first()
    .click();
  await expect(modalTitle(page, 'Create Collection')).toBeVisible();
  return createDialog(page);
}

// When I click "Edit" on <name> (in <projectName>)
async function openEdit(page: Page, name: string, projectName?: string) {
  await rowAction(row(page, name, projectName), 'Edit').click();
  await expect(modalTitle(page, 'Edit Collection')).toBeVisible();
  return editDialog(page);
}

// When I fill the create form with <rawName> in <projectName>
async function fillCreate(page: Page, rawName: string, projectName: string) {
  const d = await openCreate(page);
  await field(d, 'Name').fill(rawName);
  await field(d, 'Project').selectOption({ label: projectName });
  return d;
}

// When I create a collection named <rawName> in <projectName>. The name is
// valid, so "Save" is on once the form has checked it.
async function createIn(page: Page, rawName: string, projectName: string) {
  const d = await fillCreate(page, rawName, projectName);
  await expect(submitButton(d, 'Save')).toBeEnabled();
  await submit(d, 'Save');
  return d;
}

// Then I see "This collection will be named <slug>."
const expectNamedAs = (d: ReturnType<typeof modal>, slug: string) =>
  expect(d).toContainText(
    new RegExp(`This collection will be named\\s*${slug}\\s*\\.`)
  );

const ALREADY_EXISTS = 'A collection with this name already exists';

// @S01
// Scenario: Superuser sees every collection on the instance with its project and storage
//   Given I am a superuser who is not a member of "Malawi HIV" or "Kenya TB"
//   And "Malawi HIV" has a collection "patients" using 2500000 bytes
//   And "Kenya TB" has a collection "visits" using 100 bytes
//   When I open "/settings/collections"
//   Then I see "Collections (2)"
//   And I see a row "patients" with project "Malawi HIV" and "2.5 MB"
//   And I see a row "visits" with project "Kenya TB" and "100 B"
// The count covers every collection on the instance, so this runs alone and
// expects whatever else the instance already holds on top of these two.
test(
  '@S01',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const malawi = project('malawi-hiv');
    const kenya = project('kenya-tb');
    const patients = `patients-${hex()}`;
    const visits = `visits-${hex()}`;
    seedCollection(malawi.id, patients, { bytes: 2500000 });
    seedCollection(kenya.id, visits, { bytes: 100 });
    const total = collectionsOnInstance();

    await signedIn(page);

    await expect(
      page.getByRole('heading', {
        name: new RegExp(`Collections\\s*\\(${total}\\)`),
      })
    ).toBeVisible();
    await expect(await cells(page, patients, 'Project')).toHaveText(
      malawi.name
    );
    await expect(await cells(page, patients, 'Used storage')).toHaveText(
      '2.5 MB'
    );
    await expect(await cells(page, visits, 'Project')).toHaveText(kenya.name);
    await expect(await cells(page, visits, 'Used storage')).toHaveText('100 B');
  }
);

// @S02
// Scenario: An instance with no collections offers to create one
//   Given I am a superuser
//   And no collection exists on the instance
//   When I open "/settings/collections"
//   Then I see "No collection found."
//   And I do not see the collections table
//   When I click "Create a new one."
//   Then I see the "Create Collection" form
// Needs an instance with no collections at all, so it runs alone.
test(
  '@S02',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    expect(collectionsOnInstance(), 'no collection on the instance').toBe(0);

    await signedIn(page);

    await expect(page.getByText('No collection found.')).toBeVisible();
    await expect(page.getByRole('table')).toHaveCount(0);

    await createFirstButton(page).click();

    await expect(modalTitle(page, 'Create Collection')).toBeVisible();
    await expect(field(createDialog(page), 'Name')).toBeVisible();
  }
);

// @S03
// Scenario: Superuser creates a collection in a project they are not a member of
//   Given I am a superuser who is not a member of "Malawi HIV"
//   When I click "Create collection"
//   And I enter "New Collection" as the name
//   Then I see "This collection will be named new-collection."
//   When I choose "Malawi HIV" as the project
//   And I click "Save"
//   Then I see "Collection created successfully"
//   And I see a row "new-collection" with project "Malawi HIV"
//   And the flow "flow-admin-collection-reaches-project" has started for "new-collection"
// The flow has started when the collection belongs to the project: that is
// what the project's collections tab reads.
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const h = hex();
  const slug = `new-collection-${h}`;

  await signedIn(page);
  const d = await openCreate(page);
  await field(d, 'Name').fill(`New Collection ${h}`);

  await expectNamedAs(d, slug);

  await field(d, 'Project').selectOption({ label: malawi.name });
  await submit(d, 'Save');

  await expect(
    flashMessages.toast(page, 'Collection created successfully')
  ).toBeVisible();
  await expect(await cells(page, slug, 'Project')).toHaveText(malawi.name);
  await expect
    .poll(() => collectionsCalled(slug).map(c => c.project_id))
    .toEqual([malawi.id]);
});

// @S04
// Scenario: A name that isn't URL safe can't be saved
//   Given I am a superuser
//   When I click "Create collection"
//   And I enter "Café data" as the name
//   Then I see "Collection name must be URL safe" under the name
//   And the "Save" button is disabled
// One version turns "Save" off, the other refuses on save: submit() covers
// both, and the Then checks the message and that nothing was created.
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');

  await signedIn(page);
  const d = await fillCreate(page, 'Café data', malawi.name);
  await submit(d, 'Save');

  await expect(d.getByText('Collection name must be URL safe')).toBeVisible();
  expect(
    sql(`select 1 from collections where project_id = '${malawi.id}'`)
  ).toHaveLength(0);
});

// @S05
// Scenario: Two collections in a project can't share a name
//   Given I am a superuser
//   And "Malawi HIV" has a collection "patients"
//   When I create a collection named "patients" in "Malawi HIV"
//   Then I see "A collection with this name already exists" under the name
//   And "Malawi HIV" still has one collection named "patients"
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const patients = `patients-${hex()}`;
  seedCollection(malawi.id, patients);

  await signedIn(page);
  const d = await createIn(page, patients, malawi.name);

  await expect(d.getByText(ALREADY_EXISTS)).toBeVisible();
  expect(collectionsCalled(patients).map(c => c.project_id)).toEqual([
    malawi.id,
  ]);
});

// @S06
// Scenario: The same name can be used in another project
//   Given I am a superuser
//   And "Kenya TB" has a collection "patients"
//   When I create a collection named "patients" in "Malawi HIV"
//   Then I see "Collection created successfully"
//   And I see two rows "patients", one for "Malawi HIV" and one for "Kenya TB"
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const kenya = project('kenya-tb');
  const patients = `patients-${hex()}`;
  seedCollection(kenya.id, patients);

  await signedIn(page);
  await createIn(page, patients, malawi.name);

  await expect(
    flashMessages.toast(page, 'Collection created successfully')
  ).toBeVisible();
  await expect
    .poll(() => projectsListedFor(page, patients))
    .toEqual([kenya.name, malawi.name].sort());
});

// @S07 @variant:collection-limited
// Scenario: Creating a collection past the plan's limit is refused
//   Given "Malawi HIV" is at its plan's collection limit, with the message "Some error message"
//   And I am a superuser
//   When I create a collection named "some-name" in "Malawi HIV"
//   Then I see "Some error message"
//   And no collection "some-name" exists
// The limit is set for this test's project only, so other tests are not
// refused.
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const name = `some-name-${hex()}`;
  cleanups.push(withCollectionLimit(malawi.id, 'Some error message'));

  await signedIn(page);
  await createIn(page, name, malawi.name);

  // One version shows it as a toast after the page reloads, the other in the
  // form and as a toast, so any one of them will do.
  await expect(page.getByText('Some error message').first()).toBeVisible();
  expect(collectionsCalled(name)).toHaveLength(0);
});

// @S08
// Scenario: Superuser renames a collection and keeps its records
//   Given I am a superuser
//   And "Malawi HIV" has a collection "old-collection" with 3 records
//   When I click "Edit" on "old-collection"
//   And I change the name to "Updated Collection"
//   Then I see "This collection will be named updated-collection."
//   When I click "Save"
//   Then I see "Collection updated successfully"
//   And I see a row "updated-collection" with project "Malawi HIV"
//   And "updated-collection" still has its 3 records
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const h = hex();
  const id = seedCollection(malawi.id, `old-collection-${h}`, { records: 3 });
  const slug = `updated-collection-${h}`;

  await signedIn(page);
  const d = await openEdit(page, `old-collection-${h}`);
  await field(d, 'Name').fill(`Updated Collection ${h}`);

  await expectNamedAs(d, slug);

  await submit(d, 'Save');

  await expect(
    flashMessages.toast(page, 'Collection updated successfully')
  ).toBeVisible();
  await expect(await cells(page, slug, 'Project')).toHaveText(malawi.name);
  expect(collectionById(id)).toEqual({
    name: slug,
    project_id: malawi.id,
    records: 3,
  });
});

// @S09
// Scenario: Superuser moves a collection to another project
//   Given I am a superuser
//   And "Malawi HIV" has a collection "patients" with 3 records
//   When I click "Edit" on "patients"
//   Then the "Project" field shows "Malawi HIV"
//   When I choose "Kenya TB" as the project
//   And I click "Save"
//   Then I see "Collection updated successfully"
//   And I see a row "patients" with project "Kenya TB"
//   And "patients" still has its 3 records
//   And the flow "flow-admin-collection-reaches-project" has started for "patients"
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const kenya = project('kenya-tb');
  const patients = `patients-${hex()}`;
  const id = seedCollection(malawi.id, patients, { records: 3 });

  await signedIn(page);
  const d = await openEdit(page, patients);

  await expect.poll(() => chosenOption(field(d, 'Project'))).toBe(malawi.name);

  await field(d, 'Project').selectOption({ label: kenya.name });
  await submit(d, 'Save');

  await expect(
    flashMessages.toast(page, 'Collection updated successfully')
  ).toBeVisible();
  await expect(await cells(page, patients, 'Project')).toHaveText(kenya.name);
  expect(collectionById(id)).toEqual({
    name: patients,
    project_id: kenya.id,
    records: 3,
  });
});

// @S10
// Scenario: A move into a project that already has that name is refused
//   Given I am a superuser
//   And "Malawi HIV" and "Kenya TB" each have a collection "patients"
//   When I move the "Malawi HIV" collection "patients" to "Kenya TB"
//   Then I see "A collection with this name already exists" under the name
//   And each project still has its own "patients"
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const kenya = project('kenya-tb');
  const patients = `patients-${hex()}`;
  const malawiId = seedCollection(malawi.id, patients);
  const kenyaId = seedCollection(kenya.id, patients);

  await signedIn(page);
  const d = await openEdit(page, patients, malawi.name);
  await field(d, 'Project').selectOption({ label: kenya.name });
  await submit(d, 'Save');

  await expect(d.getByText(ALREADY_EXISTS)).toBeVisible();
  expect(collectionById(malawiId)?.project_id).toBe(malawi.id);
  expect(collectionById(kenyaId)?.project_id).toBe(kenya.id);
});

// @S11
// Scenario: Superuser deletes a collection after confirming
//   Given I am a superuser
//   And "Malawi HIV" has a collection "patients" with 3 records
//   When I click "Delete" on "patients"
//   Then I see "Are you sure you want to delete the collection patients"
//   When I click "Delete" in the confirmation
//   Then I see "Collection deleted"
//   And "patients" is not in the list
//   And none of its records remain
//   And the flow "flow-admin-collection-reaches-project" has started for "patients"
// The flow has started when the collection is gone from the project.
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const patients = `patients-${hex()}`;
  const id = seedCollection(malawi.id, patients, { records: 3 });

  await signedIn(page);
  await rowAction(row(page, patients), 'Delete').click();

  const d = deleteDialog(page);
  await expect(d).toContainText(
    new RegExp(`Are you sure you want to delete the collection\\s+${patients}`)
  );

  await d.getByRole('button', { name: 'Delete', exact: true }).click();

  await expect(flashMessages.toast(page, 'Collection deleted')).toBeVisible();
  await expect(row(page, patients)).toHaveCount(0);
  expect(collectionById(id)).toBeUndefined();
  expect(recordsOfCollection(id)).toBe(0);
});

// @S12
// Scenario Outline: Cancelling a form or confirmation changes nothing
//   Given I am a superuser
//   And "Malawi HIV" has a collection "patients"
//   When I click "<open>"
//   And I type "changed" into any name field shown
//   And I click "Cancel"
//   Then the dialog is closed
//   And collection "patients" is unchanged
//   And no collection "changed" exists
//   Examples:
//     | open                 |
//     | Create collection    |
//     | Edit on "patients"   |
//     | Delete on "patients" |
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('malawi-hiv');
  const patients = `patients-${hex()}`;
  const id = seedCollection(malawi.id, patients);
  const changed = `changed-${hex()}`;

  const examples = [
    { title: 'Create Collection', open: () => openCreate(page) },
    { title: 'Edit Collection', open: () => openEdit(page, patients) },
    {
      title: 'Delete collection',
      open: async () => {
        await rowAction(row(page, patients), 'Delete').click();
        await expect(modalTitle(page, 'Delete collection')).toBeVisible();
        return deleteDialog(page);
      },
    },
  ];

  await signInAs(page, ME);
  for (const { title, open: openDialog } of examples) {
    await open(page, PAGE);
    const d = await openDialog();
    const name = field(d, 'Name');
    if (await name.count()) await name.fill(changed);

    await d.getByRole('button', { name: 'Cancel', exact: true }).click();

    await expect(modalTitle(page, title), title).toBeHidden();
    expect(collectionById(id), title).toEqual({
      name: patients,
      project_id: malawi.id,
      records: 0,
    });
    expect(collectionsCalled(changed), title).toHaveLength(0);
  }
});

// @S13
// Scenario: Superuser sorts the list by name or used storage
//   Given I am a superuser
//   And collections "tiny" (100 B), "huge" (5 GB) and "medium" (2.5 MB) exist in any projects
//   When I open "/settings/collections"
//   Then the rows read "huge", "medium", "tiny"
//   When I click the "Name" header
//   Then the rows read "tiny", "medium", "huge"
//   When I click the "Used storage" header
//   Then the rows read "tiny", "medium", "huge"
//   When I click the "Used storage" header again
//   Then the rows read "huge", "medium", "tiny"
// Only these three rows' order is checked: other tests' collections share
// the list.
test('@S13', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const p = project('project');
  const h = hex();
  const [tiny, huge, medium] = ['tiny', 'huge', 'medium'].map(n => `${n}-${h}`);
  seedCollection(p.id, tiny, { bytes: 100 });
  seedCollection(p.id, huge, { bytes: 5_000_000_000 });
  seedCollection(p.id, medium, { bytes: 2_500_000 });

  await signedIn(page);
  await inOrder(page, [huge, medium, tiny]);

  await sortBy(page, 'Name');
  await inOrder(page, [tiny, medium, huge]);

  await sortBy(page, 'Used storage');
  await inOrder(page, [tiny, medium, huge]);

  await sortBy(page, 'Used storage');
  await inOrder(page, [huge, medium, tiny]);
});
// Inherited from shared-admin-space: the gate, and the settings layout and
// side menu with "Collections" current.
test.describe('shared-admin-space', () => {
  test(
    'shared-admin-space@S01 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S01(page, PAGE, ME, 'Collections');
    }
  );

  test(
    'shared-admin-space@S02 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S02(page, PAGE, REGULAR);
    }
  );

  test(
    'shared-admin-space@S03 on admin-collections',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'needs a socket mount that skips the HTTP check, which no browser action produces; the page cannot be reached with a forged mount'
      );
    }
  );

  for (const id of ['S04', 'S05'])
    test(
      `shared-admin-space@${id} on admin-collections`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: it is about "/dashboard"; the inherits line names only S01, S02, S03 and S06'
        );
      }
    );

  test(
    'shared-admin-space@S06 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await adminSpace.S06(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-admin-space@S07 on admin-collections',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant settings-menu-extension is not configured on this instance'
      );
    }
  );
});

// Inherited from shared-authenticated-session, on "/settings/collections".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on admin-collections',
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
      `shared-authenticated-session@${id} on admin-collections`,
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
      `shared-authenticated-session@${id} on admin-collections`,
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
      `shared-project-header@${id} on admin-collections`,
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test(
    'shared-project-header@S14 on admin-collections',
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
      `shared-project-header@${id} on admin-collections`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line takes only the no-project parts (S04, S06, S08, S10 to S14, S18)'
        );
      }
    );
});

// Inherited from shared-flash-messages. This page is on the settings layout,
// whose toast is S07; saving a collection carries a flash back to the list
// (S05).
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S05 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const malawi = project('malawi-hiv');
      await signedIn(page);
      await flashMessages.S05(
        page,
        'Collection created successfully',
        async () => {
          await createIn(page, `patients-${hex()}`, malawi.name);
        },
        PAGE
      );
    }
  );

  test(
    'shared-flash-messages@S07 on admin-collections',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const malawi = project('malawi-hiv');
      await flashMessages.S07(
        page,
        'Collection created successfully',
        async () => {
          await signedIn(page);
          await createIn(page, `patients-${hex()}`, malawi.name);
        }
      );
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
      `shared-flash-messages@${id} on admin-collections`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(true, `not reachable here: ${why}`);
      }
    );
});
