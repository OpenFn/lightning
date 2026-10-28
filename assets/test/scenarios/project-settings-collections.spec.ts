// Scenarios from annotations/views/project-settings-collections.md. The
// shared session, scope, banner, header, flash and tab chrome scenarios run
// once for every settings tab, in project-settings-setup.spec.ts. The
// preview is not the dataclip body viewer (it shows a record the server
// sends, not a dataclip), so that shared annotation's scenarios don't run
// here; the preview's own copy is S15.
//
// Who's who: "I" am editor@openfn.org; each test gives me the role its Given
// names. Anyone else who owns the project is owner@openfn.org.
import { expect, test, type Page } from '@playwright/test';

import {
  createCollectionButton,
  editCollection,
  openSettings,
  panel,
  previewText,
  sendCollectionRequest,
  settingsPath,
  type CollectionRequest,
} from './pages/project-settings';
import { copyButton } from './shared/dataclip-body-viewer';
import * as flashMessages from './shared/flash-messages';
import {
  clickable,
  collectionById,
  collectionNamesIn,
  collectionsCalled,
  expectAt,
  field,
  modal,
  recordsOfCollection,
  removeCollection,
  seedCollection,
  seedWorkspace,
  signInAs,
  submit,
  watchLiveView,
  withCollectionLimit,
  type CollectionSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PROJECT = 'Malawi HIV';

const PASSING_OLD = { tag: '@passing-old' };
const PASSING_BOTH = { tag: ['@passing-old', '@passing-new'] };

let cleanups: (() => unknown)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(async () => {
  for (const cleanup of cleanups.reverse()) await cleanup();
});

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given I am a <role> on project <name> (owner@openfn.org owns it unless I
// do); null makes me no member at all. Removing the project removes its
// collections.
function givenProject(role: Role | null, name = PROJECT) {
  const members: Record<string, Role | null> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const seed: WorkspaceSeed = { name, members };
  const w = seedWorkspace(seed, role === 'owner' ? ME : OTHER);
  cleanups.push(w.remove);
  return w.id(name);
}

// Given project <projectId> has collection <name>
const collection = (projectId: string, name: string, seed?: CollectionSeed) =>
  seedCollection(projectId, name, seed);

// Given I am signed in and on project <id>'s Collections tab
async function onCollections(page: Page, id: string) {
  await signInAs(page, ME);
  await openSettings(page, id, 'Collections');
}

// Back on project <id>'s Collections tab
async function expectBackOnTab(page: Page, id: string) {
  await expectAt(page, new RegExp(`${settingsPath(id)}(#collections)?$`));
  await expect(panel(page, 'Collections')).toBeVisible();
}

const toast = flashMessages.toast;

// The row of collection <name> (its name cell, exactly)
const row = (page: Page, name: string) =>
  panel(page, 'Collections')
    .getByRole('row')
    .filter({ has: page.getByRole('cell', { name, exact: true }) });

// <name>'s row control <control>: "Preview collection", "Download", "Edit"
// or "Delete"
const rowControl = (page: Page, name: string, control: string) =>
  clickable(row(page, name), control, { exact: true });

// The collection names the list shows, top to bottom
async function listed(page: Page) {
  const rows = panel(page, 'Collections').getByRole('row');
  const texts = await rows.allInnerTexts();
  return texts.map(t => t.trim().split(/\s/)[0]).filter(Boolean);
}

const expectListed = (page: Page, names: string[]) =>
  expect
    .poll(async () => (await listed(page)).filter(n => names.includes(n)))
    .toEqual(names);

// When I click the "<header>" header
const sortBy = (page: Page, header: string) =>
  clickable(panel(page, 'Collections').getByRole('columnheader'), header, {
    exact: true,
  }).click();

// The open dialog titled <title>; its content tells whether it is open (the
// design system's dialog wrapper is 0x0)
const dialog = (page: Page, title: string) => modal(page, title);
const expectOpen = (page: Page, title: string) =>
  expect(dialog(page, title).getByText(title).first()).toBeVisible();
const expectClosed = (page: Page, title: string) =>
  expect(dialog(page, title)).toHaveCount(0);

// When I open the create form and name the collection <name> — returns the
// form's dialog
async function startCreate(page: Page, name: string) {
  await createCollectionButton(page).click();
  await expectOpen(page, 'Create Collection');
  const form = dialog(page, 'Create Collection');
  await field(form, 'Name').fill(name);
  return form;
}

// When I create a collection named <name>
async function create(page: Page, name: string) {
  const form = await startCreate(page, name);
  await expect(form).toContainText(new RegExp(`will be named\\s*${name}`));
  await submit(form, 'Save');
}

// @S01
// Scenario: Every member sees the project's collections and their storage
//   Given I am a viewer on project "Malawi HIV"
//   And the project has collections "alpha" using 5000000000 bytes, "bravo" using 2500000 bytes and "charlie" using 100 bytes
//   When I open the project's settings on the "Collections" tab
//   Then I see the rows "alpha" with "5 GB", "bravo" with "2.5 MB" and "charlie" with "100 B", in that order
test('@S01', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  collection(id, 'charlie', { bytes: 100 });
  collection(id, 'alpha', { bytes: 5_000_000_000 });
  collection(id, 'bravo', { bytes: 2_500_000 });
  await onCollections(page, id);

  await expect(row(page, 'alpha')).toContainText('5 GB');
  await expect(row(page, 'bravo')).toContainText('2.5 MB');
  await expect(row(page, 'charlie')).toContainText('100 B');
  await expectListed(page, ['alpha', 'bravo', 'charlie']);
});

// @S02
// Scenario: A project with no collections offers to create one
//   Given I am an admin on project "Malawi HIV"
//   And the project has no collections
//   When I open the project's settings on the "Collections" tab
//   Then I see "No collections found."
//   And I see an enabled "Create a new collection" button
//   When I click "Create a new collection"
//   Then I see the "Create Collection" form
test('@S02', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onCollections(page, id);

  const tab = panel(page, 'Collections');
  await expect(tab.getByText('No collections found.')).toBeVisible();
  const first = clickable(tab, /Create a new collection/);
  await expect(first).toBeEnabled();
  await first.click();
  await expectOpen(page, 'Create Collection');
  await expect(field(dialog(page, 'Create Collection'), 'Name')).toBeVisible();
});

// @S03
// Scenario: Admin creates a collection
//   Given I am an admin on project "Malawi HIV"
//   When I click "Create collection"
//   And I enter "Test collection 0" as the name
//   Then I see "Your collection will be named test-collection-0."
//   When I click "Save"
//   Then I see "Collection created"
//   And I am on the "Collections" tab of the project's settings
//   And "test-collection-0" is in the list
test('@S03', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onCollections(page, id);

  const form = await startCreate(page, 'Test collection 0');
  await expect(form).toContainText(
    /Your collection will be named\s*test-collection-0\./
  );
  await submit(form, 'Save');

  await expect(toast(page, 'Collection created')).toBeVisible();
  await expectBackOnTab(page, id);
  await expect(row(page, 'test-collection-0')).toBeVisible();
  expect(collectionNamesIn(id)).toEqual(['test-collection-0']);
});

// @S04
// Scenario: A name that isn't URL safe can't be saved
//   Given I am an admin on project "Malawi HIV"
//   When I click "Create collection"
//   And I enter "Café data" as the name
//   Then I see "Collection name must be URL safe" under the name
//   And the "Save" button is disabled
// Checks that nothing is saved rather than the button: one version turns
// Save off, another refuses on save.
test('@S04', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onCollections(page, id);

  const form = await startCreate(page, 'Café data');
  await submit(form, 'Save');

  await expect(
    form.getByText('Collection name must be URL safe')
  ).toBeVisible();
  expect(collectionNamesIn(id)).toEqual([]);
});

// @S05
// Scenario: Two collections in a project can't share a name
//   Given I am an owner on project "Malawi HIV"
//   And the project has a collection "patients"
//   When I create a collection named "patients"
//   Then I see "A collection with this name already exists"
//   And the project still has one collection named "patients"
test('@S05', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  collection(id, 'patients');
  await onCollections(page, id);

  await create(page, 'patients');

  await expect(
    page.getByText('A collection with this name already exists').first()
  ).toBeVisible();
  expect(collectionNamesIn(id)).toEqual(['patients']);
});

// @S06
// Scenario: The same name can be used in another project
//   Given I am an admin on project "Malawi HIV"
//   And project "Kenya TB" has a collection "patients"
//   When I create a collection named "patients"
//   Then I see "Collection created"
//   And "patients" is in the list
//   And the flow "flow-collection-api-name-resolution" has started for "patients"
// The flow is the Collections API's; here only that both projects now hold
// a "patients".
test('@S06', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const kenya = givenProject(null, 'Kenya TB');
  collection(kenya, 'patients');
  await onCollections(page, id);

  await create(page, 'patients');

  await expect(toast(page, 'Collection created')).toBeVisible();
  await expect(row(page, 'patients')).toBeVisible();
  const holders = collectionsCalled('patients').map(c => c.project_id);
  expect(holders).toContain(id);
  expect(holders).toContain(kenya);
});

// @S07 @variant:collection-limited
// Scenario: Creating a collection past the plan's limit is refused
//   Given project "Malawi HIV" is at its plan's collection limit, with the message "Some error message"
//   And I am an owner on the project
//   When I create a collection named "some-name"
//   Then I see "Some error message"
//   And no collection "some-name" exists
// Serial: it swaps the instance's collection hook.
test(
  '@S07',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const id = givenProject('owner');
    cleanups.push(withCollectionLimit(id, 'Some error message'));
    await onCollections(page, id);

    await create(page, 'some-name');

    await expect(page.getByText('Some error message').first()).toBeVisible();
    expect(collectionNamesIn(id)).toEqual([]);
  }
);

// @S08
// Scenario Outline: Members who can't manage collections see the controls disabled
//   Given I am a <role> on project "Malawi HIV"
//   And the project has a collection "patients"
//   When I open the project's settings on the "Collections" tab
//   Then the "Create collection" button is disabled
//   And the "Edit" and "Delete" buttons on "patients" are disabled
//   And the "Preview collection" button and the "Download" link on "patients" are enabled
//   Examples: viewer, editor
for (const role of ['viewer', 'editor'] as const)
  test(`@S08 ${role}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject(role);
    collection(id, 'patients');
    await onCollections(page, id);

    await expect(createCollectionButton(page)).toBeDisabled();
    await expect(rowControl(page, 'patients', 'Edit')).toBeDisabled();
    await expect(rowControl(page, 'patients', 'Delete')).toBeDisabled();
    await expect(
      rowControl(page, 'patients', 'Preview collection')
    ).toBeEnabled();
    await expect(rowControl(page, 'patients', 'Download')).toBeVisible();
  });

// @S09
// Scenario Outline: A non-admin's create, edit or delete request is refused
//   Given I am an editor on project "Malawi HIV"
//   And the project has a collection "patients"
//   When the page receives "toggle_action" with action "<action>" for "patients"
//   Then I see "You are not authorized to perform this action"
//   And I am on the "Collections" tab of the project's settings
//   And collection "patients" is unchanged
//   Examples: new, edit, delete
// Checked by what is stored and that the page didn't crash: one version
// flashes the refusal, another answers the request.
for (const action of ['new', 'edit', 'delete'] as const)
  test(`@S09 ${action}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject('editor');
    const cid = collection(id, 'patients', { records: 1 });
    const lv = watchLiveView(page);
    await onCollections(page, id);

    await sendCollectionRequest(page, lv, action, {
      id: cid,
      name: 'patients',
    });

    await expect(panel(page, 'Collections')).toBeVisible();
    expect(lv.crashes()).toBe(0);
    expect(collectionNamesIn(id)).toEqual(['patients']);
    expect(collectionById(cid)).toMatchObject({ name: 'patients', records: 1 });
    for (const title of ['Create Collection', 'Edit Collection'])
      await expectClosed(page, title);
  });

// @S10
// Scenario: Admin renames a collection
//   Given I am an admin on project "Malawi HIV"
//   And the project has a collection "patients" with 3 records
//   When I click "Edit" on "patients"
//   And I change the name to "patients-2024"
//   Then I see "Your collection will be named patients-2024."
//   When I click "Save"
//   Then I see "Collection updated"
//   And "patients-2024" is in the list with its 3 records
//   And "patients" is not in the list
test('@S10', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const cid = collection(id, 'patients', { records: 3 });
  await onCollections(page, id);

  await rowControl(page, 'patients', 'Edit').click();
  await expectOpen(page, 'Edit Collection');
  const form = dialog(page, 'Edit Collection');
  await field(form, 'Name').fill('patients-2024');
  await expect(form).toContainText(
    /Your collection will be named\s*patients-2024\./
  );
  await submit(form, 'Save');

  await expect(toast(page, 'Collection updated')).toBeVisible();
  await expect(row(page, 'patients-2024')).toBeVisible();
  await expect(row(page, 'patients')).toHaveCount(0);
  expect(collectionById(cid)).toMatchObject({
    name: 'patients-2024',
    project_id: id,
    records: 3,
  });
});

// @S11
// Scenario: Admin deletes a collection after confirming
//   Given I am an owner on project "Malawi HIV"
//   And the project has a collection "patients" with 3 records
//   When I click "Delete" on "patients"
//   Then I see "Are you sure you want to delete the collection patients"
//   When I click "Delete" in the confirmation
//   Then I see "Collection deleted"
//   And "patients" is not in the list
//   And none of its records remain
test('@S11', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  const cid = collection(id, 'patients', { records: 3 });
  await onCollections(page, id);

  await rowControl(page, 'patients', 'Delete').click();
  const confirm = dialog(page, 'Delete collection');
  await expect(confirm).toContainText(
    'Are you sure you want to delete the collection patients'
  );
  await confirm.getByRole('button', { name: 'Delete', exact: true }).click();

  await expect(toast(page, 'Collection deleted')).toBeVisible();
  await expect(row(page, 'patients')).toHaveCount(0);
  expect(collectionById(cid)).toBeUndefined();
  expect(recordsOfCollection(cid)).toBe(0);
});

// @S12
// Scenario Outline: Cancelling a form or confirmation changes nothing
//   Given I am an admin on project "Malawi HIV"
//   And the project has a collection "patients"
//   When I click "<open>"
//   And I click "Cancel"
//   Then the dialog is closed
//   And collection "patients" is unchanged
//   Examples: Create collection, Edit on "patients", Delete on "patients"
const S12_ROWS = [
  ['Create collection', 'Create Collection'],
  ['Edit', 'Edit Collection'],
  ['Delete', 'Delete collection'],
] as const;
for (const [open, title] of S12_ROWS)
  test(`@S12 ${open}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject('admin');
    const cid = collection(id, 'patients', { records: 1 });
    await onCollections(page, id);

    await (
      open === 'Create collection'
        ? createCollectionButton(page)
        : rowControl(page, 'patients', open)
    ).click();
    await expectOpen(page, title);
    await dialog(page, title)
      .getByRole('button', { name: 'Cancel', exact: true })
      .click();

    await expectClosed(page, title);
    expect(collectionNamesIn(id)).toEqual(['patients']);
    expect(collectionById(cid)).toMatchObject({ name: 'patients', records: 1 });
  });

// When I click "Preview collection" on <name> — returns the preview
async function preview(page: Page, name: string) {
  await rowControl(page, name, 'Preview collection').click();
  const title = `Collection Preview: ${name}`;
  await expectOpen(page, title);
  return dialog(page, title);
}

// @S13
// Scenario Outline: Any member previews the first record of a collection
//   Given I am a <role> on project "Malawi HIV"
//   And collection "patients" holds a record with key "my-key" and value "my-value"
//   When I click "Preview collection" on "patients"
//   Then I see "Collection Preview: patients"
//   And I see "Showing first record"
//   And I see "my-key" and "my-value"
//   Examples: viewer, editor, admin, owner
for (const role of ['viewer', 'editor', 'admin', 'owner'] as const)
  test(`@S13 ${role}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject(role);
    collection(id, 'patients', { items: [['my-key', 'my-value']] });
    await onCollections(page, id);

    const shown = await preview(page, 'patients');

    await expect(shown).toContainText('Showing first record');
    await expect.poll(() => previewText(shown)).toContain('my-key');
    expect(await previewText(shown)).toContain('my-value');
  });

// @S14
// Scenario: Previewing an empty collection says it is empty
//   Given I am an owner on project "Malawi HIV"
//   And collection "patients" has no records
//   When I click "Preview collection" on "patients"
//   Then I see "This collection is empty."
test('@S14', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  collection(id, 'patients');
  await onCollections(page, id);

  const shown = await preview(page, 'patients');

  await expect(shown.getByText('This collection is empty.')).toBeVisible();
});

// @S15
// Scenario: The preview stays readable and copies the full record
//   Given I am an owner on project "Malawi HIV"
//   And collection "patients" holds a record whose value is a JSON object with a 300-character string field
//   When I click "Preview collection" on "patients"
//   Then the value is shown as an expanded JSON object, with "key" first
//   And the long string is cut to 140 characters followed by "…"
//   When I click the copy button
//   Then the clipboard holds the full record, including all 300 characters
// Old only: the design-system preview shows the record as stored, with no
// copy button.
test('@S15', PASSING_OLD, async ({ page }) => {
  const long = 'x'.repeat(300);
  const id = givenProject('owner');
  collection(id, 'patients', {
    items: [['long-record', JSON.stringify({ note: long })]],
  });
  await onCollections(page, id);

  const shown = await preview(page, 'patients');

  await expect.poll(() => previewText(shown)).toContain('"note"');
  const text = await previewText(shown);
  expect(text.indexOf('"key"')).toBeGreaterThanOrEqual(0);
  expect(text.indexOf('"key"')).toBeLessThan(text.indexOf('"value"'));
  // Today's viewer wraps the long line; the wrap adds no characters.
  const unwrapped = text.replace(/\s+/g, '');
  expect(unwrapped).toContain(`"note":"${'x'.repeat(140)}…"`);
  expect(unwrapped).not.toContain('x'.repeat(141));

  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await copyButton(page).click();
  await expect
    .poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toContain(long);
  expect(await page.evaluate(() => navigator.clipboard.readText())).toContain(
    'long-record'
  );
});

// @S16
// Scenario Outline: A collection in another project can't be reached from this tab
//   Given I am an owner on project "Malawi HIV"
//   And project "Kenya TB", which I am not on, has a collection "secret"
//   When the page receives "<event>" for "secret"
//   Then I see "Collection not found"
//   And collection "secret" is unchanged
//   Examples: preview_collection, toggle_action with "edit", toggle_action with "delete"
// Checked by what is stored, what is shown and that the page didn't crash,
// not by the message (one version flashes, another answers the request).
const S16_ROWS: [string, CollectionRequest][] = [
  ['preview_collection', 'preview'],
  ['toggle_action with "edit"', 'edit'],
  ['toggle_action with "delete"', 'delete'],
];
for (const [event, kind] of S16_ROWS)
  test(`@S16 ${event}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject('owner');
    const kenya = givenProject(null, 'Kenya TB');
    const cid = collection(kenya, 'secret', {
      items: [['hidden-key', 'hidden-value']],
    });
    const lv = watchLiveView(page);
    await onCollections(page, id);

    await sendCollectionRequest(page, lv, kind, { id: cid, name: 'secret' });

    expect(lv.crashes()).toBe(0);
    await expect(page.getByText('hidden-value')).toHaveCount(0);
    await expectClosed(page, 'Edit Collection');
    await expectClosed(page, 'Delete collection');
    expect(collectionById(cid)).toMatchObject({
      name: 'secret',
      project_id: kenya,
      records: 1,
    });
    expect(collectionNamesIn(id)).toEqual([]);
  });

// @S17
// Scenario: A collection removed since the page loaded is reported as not found
//   Given I am an admin on project "Malawi HIV" with the "Collections" tab open
//   And collection "patients" has since been deleted
//   When I click "Edit" on "patients"
//   Then I see "Collection not found"
//   And "patients" is no longer in the list
test('@S17', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const cid = collection(id, 'patients');
  await onCollections(page, id);
  await expect(row(page, 'patients')).toBeVisible();

  removeCollection(cid);
  await editCollection(page, rowControl(page, 'patients', 'Edit'));

  await expect(page.getByText('Collection not found')).toBeVisible();
  await expect(row(page, 'patients')).toHaveCount(0);
});

// @S18
// Scenario: Members sort the list by name or used storage
//   Given I am an owner on project "Malawi HIV"
//   And the project has collections "alpha" (5 GB), "bravo" (2.5 MB) and "charlie" (100 B)
//   When I click the "Name" header
//   Then the rows read "charlie", "bravo", "alpha"
//   When I click the "Used storage" header
//   Then the rows read "charlie", "bravo", "alpha"
//   When I click the "Used storage" header again
//   Then the rows read "alpha", "bravo", "charlie"
test('@S18', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  collection(id, 'alpha', { bytes: 5_000_000_000 });
  collection(id, 'bravo', { bytes: 2_500_000 });
  collection(id, 'charlie', { bytes: 100 });
  await onCollections(page, id);
  await expectListed(page, ['alpha', 'bravo', 'charlie']);

  await sortBy(page, 'Name');
  await expectListed(page, ['charlie', 'bravo', 'alpha']);

  await sortBy(page, 'Used storage');
  await expectListed(page, ['charlie', 'bravo', 'alpha']);

  await sortBy(page, 'Used storage');
  await expectListed(page, ['alpha', 'bravo', 'charlie']);
});

// @S19
// Scenario: Every member can start a download of a collection
//   Given I am a viewer on project "Malawi HIV"
//   And the project has a collection "patients"
//   When I open the project's settings on the "Collections" tab
//   Then the "Download" link on "patients" points to "/download/collections/<project_id>/patients"
//   And following it starts the flow "flow-download-collection"
// The flow is the download's; here only that the link answers with the
// collection's records.
test('@S19', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  collection(id, 'patients', { items: [['my-key', 'my-value']] });
  await onCollections(page, id);

  const href = `/download/collections/${id}/patients`;
  await expect(rowControl(page, 'patients', 'Download')).toHaveAttribute(
    'href',
    href
  );
  const response = await page.request.get(href);
  expect(response.ok()).toBe(true);
  expect(await response.text()).toContain('my-value');
});
