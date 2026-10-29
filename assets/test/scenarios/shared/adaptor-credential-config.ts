// Scenarios from annotations/shared/shared-adaptor-credential-config.md: the
// adaptor box, the adaptor picker, "Change Adaptor?", "Configure connection"
// and the credential form it opens. Hosts: workflow-editor-inspectors (the
// step inspector) and workflow-editor-ide (the IDE header) reach them all;
// workflow-editor-canvas reaches the picker only (S08, S09, S10's adaptor).
//
// The host owns the Given: it seeds (seedCredential, seedKeychain from
// steps.ts; jobUses below), signs in, opens "Fetch" in its surface and hands
// over the adaptor box: the element showing the step's adaptor, version and
// credential with its buttons. Where a Then is about what the step stores,
// the host also hands over <save>, which saves the workflow.
import { expect, type Locator, type Page } from '@playwright/test';

import {
  credentialsNamed,
  exec,
  field,
  keychainsOf,
  modal,
  modalTitle,
  pointAt,
  pushEvent,
  sql,
  submit,
  submitButton,
  user,
  type watchLiveView,
} from '../steps';

// ---------------------------------------------------------------------------
// How the editor is built. Everything that knows the dialogs' shape and the
// LiveView events behind the credential form lives here.
// ---------------------------------------------------------------------------

// In the adaptor box: the adaptor button, and "Edit" or "Connect"
const changeAdaptor = (box: Locator) =>
  box.getByRole('button', { name: /^Change( adaptor)?$/ });
export const configureButton = (box: Locator) =>
  box.getByRole('button', { name: /^(Edit|Connect)\b/ });

const configure = (page: Page) => modal(page, 'Configure connection');
const configureTitle = (page: Page) => modalTitle(page, 'Configure connection');

// A credential's choice in "Configure connection", and the row holding it
const credentialChoice = (page: Page, name: string) =>
  configure(page).getByRole('radio', { name: new RegExp(`\\b${name}\\b`) });
const credentialRow = (page: Page, name: string) =>
  configure(page)
    .locator('label')
    .filter({
      has: page.getByRole('radio', { name: new RegExp(`\\b${name}\\b`) }),
    });

const versionBox = (page: Page) =>
  configure(page).getByRole('combobox', { name: 'Version' });

// The adaptor picker: a search box and a list of adaptors
const pickerSearch = (page: Page) =>
  page.getByPlaceholder('Search for an adaptor to connect...');
const adaptorOption = (page: Page, name: RegExp) =>
  page.getByRole('option', { name });

const confirmChange = (page: Page) => modal(page, 'Change Adaptor?');
const confirmChangeTitle = (page: Page) => modalTitle(page, 'Change Adaptor?');

// The LiveView credential form the editor opens, while it is on its first
// page: the dialog with "Save Credential"
const credentialForm = (page: Page) =>
  page.getByRole('button', { name: 'Save Credential', exact: true });
const credentialDialog = (page: Page) =>
  page.getByRole('dialog').filter({ has: credentialForm(page) });

// The event "New Credential" and a credential's edit button send
const OPEN_CREDENTIAL_FORM = 'open_credential_modal';

// ---------------------------------------------------------------------------

export type Step = { projectId: string; jobId: string };

type StoredJob = {
  adaptor: string;
  credential: string | null;
  keychain: string | null;
};

// What step <jobId> stores: its adaptor, and the names of its project
// credential and keychain credential
export const jobOf = (jobId: string) =>
  sql<StoredJob>(
    `select j.adaptor, c.name as credential, k.name as keychain from jobs j
     left join project_credentials pc on pc.id = j.project_credential_id
     left join credentials c on c.id = pc.credential_id
     left join keychain_credentials k on k.id = j.keychain_credential_id
     where j.id = '${jobId}'`
  )[0];

async function openConfigure(page: Page, box: Locator) {
  await configureButton(box).click();
  await expect(configureTitle(page)).toBeVisible();
}

async function closeConfigure(page: Page) {
  await configure(page)
    .getByRole('button', { name: 'Close', exact: true })
    .click();
  await expect(configureTitle(page)).toBeHidden();
}

async function pick(page: Page, adaptor: RegExp) {
  await adaptorOption(page, adaptor).first().click();
}

// The version list's choices, in order
async function versionsListed(page: Page) {
  await versionBox(page).click();
  return page.getByRole('listbox').getByRole('option').allInnerTexts();
}

export const given = {
  S01: [
    {
      adaptor: '@openfn/language-dhis2@latest',
      button: 'Connect',
    },
    { adaptor: '@openfn/language-http@latest', button: 'Edit' },
  ],
  S02: {
    tip: 'Credential not found. It may have been deleted or you no longer have access.',
  },
  S07: {
    versions: ['4.2.0', '4.10.0', '4.9.1'],
    listed: ['latest', '4.10.0', '4.9.1', '4.2.0'],
  },
  S10: { adaptor: '@openfn/language-old', version: '4.1.0' },
  S13: {
    tip: (owner: string) =>
      `This credential can only be edited by the owner: ${user(owner).email}`,
  },
};

// @S01 A step without a credential is flagged when its adaptor needs one
//   Given "Fetch" uses <adaptor> and has no credential
//   Then the adaptor box offers "<button>"
export async function S01(
  _page: Page,
  box: Locator,
  button: (typeof given.S01)[number]['button']
) {
  await expect(configureButton(box)).toHaveText(new RegExp(`^\\s*${button}`));
}

// @S02 A step whose credential has gone says so
//   Given "Fetch" references a project credential that is not in the project's credential list
//   Then the adaptor box shows "Not found" with "Credential not found. It may have been deleted or you no longer have access."
export async function S02(page: Page, box: Locator) {
  const notFound = box.getByText('Not found', { exact: true });
  await expect(notFound).toBeVisible();
  await page.mouse.move(0, 0);
  await notFound.hover();
  await expect(
    page.getByRole('tooltip').filter({ hasText: given.S02.tip })
  ).toBeVisible();
}

// @S03 Picking a credential attaches it to the step, and only one kind at a time
//   Given "Fetch" uses the DHIS2 adaptor
//   And the project has DHIS2 credential "DHIS2 prod" and keychain "Per facility"
//   When I open "Configure connection" and choose "DHIS2 prod"
//   Then "Fetch" shows a "DHIS2 prod" credential badge
//   And the step's project credential is set and its keychain credential is empty
//   When I choose "Per facility" under "Other credentials"
//   Then the step's keychain credential is set and its project credential is empty
//   When I clear the selection
//   Then "Fetch" has no credential
export async function S03(
  page: Page,
  box: Locator,
  step: Step,
  save: () => Promise<void>
) {
  const choose = async (name: string, other = false) => {
    await openConfigure(page, box);
    if (other)
      await configure(page)
        .getByRole('button', { name: 'Other credentials' })
        .click();
    await credentialChoice(page, name).check();
    await closeConfigure(page);
    await save();
  };

  await choose('DHIS2 prod');
  await expect(box).toContainText('DHIS2 prod');
  await expect
    .poll(() => jobOf(step.jobId))
    .toMatchObject({ credential: 'DHIS2 prod', keychain: null });

  await choose('Per facility', true);
  await expect
    .poll(() => jobOf(step.jobId))
    .toMatchObject({ credential: null, keychain: 'Per facility' });

  await openConfigure(page, box);
  const other = configure(page).getByRole('button', {
    name: 'Other credentials',
  });
  if (await other.isVisible()) await other.click();
  await configure(page)
    .getByRole('button', { name: 'Clear credential selection' })
    .click();
  await closeConfigure(page);
  await save();
  await expect
    .poll(() => jobOf(step.jobId))
    .toMatchObject({ credential: null, keychain: null });
}

// @S04 Credentials that match the adaptor are offered first
//   Given "Fetch" uses the Salesforce adaptor
//   And the project has a Salesforce credential, a raw credential and a keychain credential
//   When I open "Configure connection"
//   Then I see only the Salesforce credential
//   When I click "Other credentials"
//   Then I see the raw one under "Generic Credentials" and the keychain under "Keychain Credentials"
export async function S04(
  page: Page,
  box: Locator,
  names: { salesforce: string; raw: string; keychain: string }
) {
  await openConfigure(page, box);
  const choices = configure(page).getByRole('radio');
  await expect(choices).toHaveCount(1);
  await expect(credentialChoice(page, names.salesforce)).toBeVisible();

  await configure(page)
    .getByRole('button', { name: 'Other credentials' })
    .click();

  const top = async (l: Locator) => (await l.boundingBox())?.y ?? NaN;
  const generic = configure(page).getByText('Generic Credentials');
  const keychains = configure(page).getByText('Keychain Credentials');
  await expect(credentialChoice(page, names.raw)).toBeVisible();
  await expect(credentialChoice(page, names.keychain)).toBeVisible();
  const order = [
    await top(generic),
    await top(credentialChoice(page, names.raw)),
    await top(keychains),
    await top(credentialChoice(page, names.keychain)),
  ];
  expect(order).toEqual([...order].sort((a, b) => a - b));
  await expect(credentialChoice(page, names.salesforce)).toBeHidden();
}

// @S05 Changing adaptor on a step with a credential asks first and clears it
//   Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
//   When I pick "DHIS2" again in the adaptor picker
//   Then no warning appears, "Configure connection" opens and "DHIS2 prod" is still selected
//   When I pick "Salesforce" in the adaptor picker
//   Then I see "Change Adaptor?" warning that the credential will be reset
//   When I click "Continue"
//   Then "Fetch" uses Salesforce and has no credential
//   And "Configure connection" opens
export async function S05(
  page: Page,
  box: Locator,
  step: Step,
  save: () => Promise<void>
) {
  await changeAdaptor(box).click();
  await pick(page, /dhis2/i);
  await expect(configureTitle(page)).toBeVisible();
  await expect(confirmChangeTitle(page)).toBeHidden();
  await expect(credentialChoice(page, 'DHIS2 prod')).toBeChecked();
  await closeConfigure(page);

  await changeAdaptor(box).click();
  await pick(page, /salesforce/i);
  await expect(confirmChangeTitle(page)).toBeVisible();
  await expect(confirmChange(page)).toContainText(/reset the credential/);
  await confirmChange(page).getByRole('button', { name: 'Continue' }).click();

  await expect(configureTitle(page)).toBeVisible();
  await closeConfigure(page);
  await expect(box).toContainText(/salesforce/i);
  await expect(box).not.toContainText('DHIS2 prod');
  await save();
  await expect
    .poll(() => jobOf(step.jobId))
    .toMatchObject({
      adaptor: expect.stringMatching(/language-salesforce/),
      credential: null,
      keychain: null,
    });
}

// @S06 Backing out of an adaptor change keeps everything as it was
//   Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
//   When I pick "Salesforce" and then click "Cancel" on the warning
//   Then "Fetch" still uses DHIS2 with "DHIS2 prod"
//   And the adaptor picker is open again
export async function S06(page: Page, box: Locator) {
  await changeAdaptor(box).click();
  await pick(page, /salesforce/i);
  await confirmChange(page).getByRole('button', { name: 'Cancel' }).click();

  await expect(pickerSearch(page)).toBeVisible();
  await expect(box).toContainText(/dhis2/i);
  await expect(box).toContainText('DHIS2 prod');
}

// @S07 A step can be pinned to an adaptor version
//   Given the DHIS2 adaptor has versions "4.2.0", "4.10.0" and "4.9.1"
//   When I open "Configure connection" on "Fetch"
//   Then the version list reads "latest", "4.10.0", "4.9.1", "4.2.0"
//   When I choose "4.9.1"
//   Then "Fetch" shows "v4.9.1"
// The catalogue may list more versions; the given ones keep this order.
export async function S07(page: Page, box: Locator) {
  await openConfigure(page, box);
  const listed = (await versionsListed(page)).map(v => v.trim());
  expect(listed.filter(v => given.S07.listed.includes(v))).toEqual(
    given.S07.listed
  );

  await page.getByRole('option', { name: '4.9.1', exact: true }).click();
  await closeConfigure(page);
  await expect(box).toContainText('v4.9.1');
}

// @S08 Searching for an adaptor that does not exist suggests HTTP
//   When I search the adaptor picker for "zzz-unknown"
//   Then I see "No adaptor found" and the HTTP adaptor
//   When I press Enter
//   Then the HTTP adaptor is chosen
// <openPicker> opens the picker (the box's adaptor button, or the canvas's
// new step); <chosen> is where the chosen adaptor shows.
export async function S08(
  page: Page,
  openPicker: () => Promise<void>,
  chosen: Locator
) {
  await openPicker();
  await pickerSearch(page).fill('zzz-unknown');
  await expect(page.getByText('No adaptor found')).toBeVisible();
  await expect(adaptorOption(page, /http/i)).toBeVisible();

  await pickerSearch(page).press('Enter');

  await expect(pickerSearch(page)).toBeHidden();
  await expect(chosen).toContainText(/http/i);
}

// @S09 A catalogue that has not loaded can be retried
//   Given the adaptor catalogue answers 503 "adaptor catalogue unavailable"
//   When I open the adaptor picker
//   Then I see "Couldn't load adaptors. Please try again." and "Retry"
//   When the catalogue becomes available and I click "Retry"
//   Then the adaptor list appears
// The host makes it unavailable with catalogueUnavailable() from steps.ts and
// passes the function it returns as <makeAvailable>.
export async function S09(
  page: Page,
  openPicker: () => Promise<void>,
  makeAvailable: () => void
) {
  await openPicker();
  await expect(page.getByText(/Couldn.t load adaptors/)).toBeVisible();
  await expect(adaptorOption(page, /./)).toHaveCount(0);

  makeAvailable();
  await page.getByRole('button', { name: 'Retry' }).click();

  await expect(adaptorOption(page, /./).first()).toBeVisible();
}

// @S10 Retired adaptors and versions are not offered
//   Given the DHIS2 adaptor's version "4.1.0" is deprecated and adaptor "@openfn/language-old" is deprecated
//   When I open the adaptor picker and "Configure connection" for a DHIS2 step
//   Then "@openfn/language-old" is not listed and "4.1.0" is not in the version list
// The host retires them with withRetiredAdaptors() below (@serial).
// <box> is left out on the canvas, which has no versions.
export async function S10(
  page: Page,
  openPicker: () => Promise<void>,
  box?: Locator
) {
  await openPicker();
  await expect(adaptorOption(page, /./).first()).toBeVisible();
  await pickerSearch(page).fill('old');
  await expect(adaptorOption(page, /\bold\b/i)).toHaveCount(0);
  await page.keyboard.press('Escape');
  await expect(pickerSearch(page)).toBeHidden();
  if (!box) return;

  await openConfigure(page, box);
  const listed = (await versionsListed(page)).map(v => v.trim());
  expect(listed.length).toBeGreaterThan(0);
  expect(listed).not.toContain(given.S10.version);
}

// @S11 A credential created from a step is attached to it
//   Given I am an editor and "Fetch" uses DHIS2
//   When I click "New Credential" in "Configure connection"
//   Then the credential form opens with the DHIS2 schema and "Malawi HIV" preselected
//   When I save a DHIS2 credential "DHIS2 test"
//   Then "Fetch" has "DHIS2 test" as its project credential
//   And "Configure connection" opens again with "DHIS2 test" selected
//   And "credentials_updated" is broadcast on "workflow:collaborate:<Intake id>"
// The broadcast is flow-editor-credentials-broadcast's to prove.
export async function S11(
  page: Page,
  box: Locator,
  step: Step & { projectName: string },
  save: () => Promise<void>
) {
  await openConfigure(page, box);
  await configure(page)
    .getByRole('button', { name: 'New Credential' })
    .first()
    .click();

  await expect(credentialForm(page)).toBeVisible();
  const form = credentialDialog(page);
  await expect(field(form, 'Host URL')).toBeVisible();
  await expect(form).toContainText(step.projectName);
  await field(form, 'Credential Name').fill('DHIS2 test');
  await field(form, 'Username').fill('admin');
  await field(form, 'Password').fill('district');
  await field(form, 'Host URL').fill('https://play.dhis2.example.org');
  // The form checks each change before Save is on
  await expect(submitButton(form, 'Save Credential')).toBeEnabled();
  await submit(form, 'Save Credential');

  await expect(configureTitle(page)).toBeVisible();
  await expect(credentialChoice(page, 'DHIS2 test')).toBeChecked();
  await closeConfigure(page);
  await save();
  await expect
    .poll(() => jobOf(step.jobId))
    .toMatchObject({ credential: 'DHIS2 test' });
}

// @S12 A viewer cannot save a credential from the editor
//   Given I am a viewer on "Malawi HIV"
//   When "open_credential_modal" is sent with schema "raw" and I submit the form
//   Then no credential is created
// <lv> is watchLiveView(page), started before the editor opened.
export async function S12(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  viewer: string
) {
  const name = 'Viewer raw';
  await pushEvent(page, lv, OPEN_CREDENTIAL_FORM, { schema: 'raw' });
  await expect(credentialForm(page)).toBeVisible();
  const form = credentialDialog(page);
  await field(form, 'Credential Name').fill(name);
  await field(form, 'Credential Body').fill('{"token": "abc"}');
  const sent = lv.events();

  await submit(form, 'Save Credential');

  await lv.answered(sent + 1);
  expect(credentialsNamed(viewer, name)).toHaveLength(0);
  expect(lv.crashes()).toBe(0);
}

// @S13 Only a credential's owner can edit it from a step
//   Given "DHIS2 prod" is owned by "amara@example.org" and shared with "Malawi HIV"
//   When I open "Configure connection" on "Fetch"
//   Then the edit button on "DHIS2 prod" is disabled with "This credential can only be edited by the owner: amara@example.org"
//   When "open_credential_modal" is sent with the id of "DHIS2 prod"
//   Then no credential form opens and nothing of "DHIS2 prod" is rendered
//   And "credential_modal_closed" is pushed back and "Configure connection" reopens
// <credential> is the seeded one, with a <secret> in its body. A pushed
// event has no React caller waiting, so the reopening is not checked.
export async function S13(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  box: Locator,
  credential: { id: string; owner: string; secret: string }
) {
  await openConfigure(page, box);
  const edit = credentialRow(page, 'DHIS2 prod').getByRole('button', {
    name: /edit credential/i,
  });
  await expect(edit).toBeDisabled();
  await page.mouse.move(0, 0);
  await pointAt(edit);
  await expect(
    page
      .getByRole('tooltip')
      .filter({ hasText: given.S13.tip(credential.owner) })
  ).toBeVisible();
  await closeConfigure(page);

  await pushEvent(page, lv, OPEN_CREDENTIAL_FORM, {
    schema: 'dhis2',
    credential_id: credential.id,
  });

  await page.waitForTimeout(500);
  await expect(credentialForm(page)).toHaveCount(0);
  expect(await page.content()).not.toContain(credential.secret);
  expect(lv.crashes()).toBe(0);
}

// The keychain page of the credential form: "Advanced", then "Keychain"
async function fillKeychain(page: Page, name: string, path: string) {
  await page.getByRole('button', { name: 'Advanced', exact: true }).click();
  await page.getByRole('button', { name: /^Keychain/ }).click();
  await page.getByRole('button', { name: 'Continue', exact: true }).click();
  await field(page, 'Name').fill(name);
  await field(page, 'JSONPath Expression').fill(path);
}

// @S14 An admin creates a keychain credential from a step
//   Given I am an admin on "Malawi HIV"
//   When I open a new credential from "Fetch", click "Advanced", choose "Keychain" and save "Per facility" with path "$.facility_id"
//   Then the keychain credential exists on "Malawi HIV"
//   And "Fetch" has "Per facility" as its keychain credential
export async function S14(
  page: Page,
  box: Locator,
  step: Step,
  save: () => Promise<void>
) {
  await openConfigure(page, box);
  await configure(page)
    .getByRole('button', { name: 'New Credential' })
    .first()
    .click();
  await expect(credentialForm(page)).toBeVisible();
  await fillKeychain(page, 'Per facility', '$.facility_id');

  await submit(page, 'Create');

  await expect
    .poll(() => keychainsOf(step.projectId).map(k => [k.name, k.path]))
    .toContainEqual(['Per facility', '$.facility_id']);
  if (await configureTitle(page).isVisible()) await closeConfigure(page);
  await save();
  await expect
    .poll(() => jobOf(step.jobId))
    .toMatchObject({ keychain: 'Per facility' });
}

// @S15 People below admin cannot create a keychain credential from a step
//   Given I am a viewer on "Malawi HIV"
//   When I submit a keychain credential "Planted" from the step's advanced credential setup
//   Then no keychain credential "Planted" exists
// A viewer has no "New Credential", so the form is opened with the event it
// sends.
export async function S15(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  projectId: string
) {
  await pushEvent(page, lv, OPEN_CREDENTIAL_FORM, { schema: 'raw' });
  await expect(credentialForm(page)).toBeVisible();
  await fillKeychain(page, 'Planted', '$.org_id');
  const sent = lv.events();

  await submit(page, 'Create');

  await lv.answered(sent + 1);
  expect(keychainsOf(projectId).map(k => k.name)).not.toContain('Planted');
  expect(lv.crashes()).toBe(0);
}

// @S17 Escape and Back close one dialog at a time
//   Given "Configure connection" is open over "Fetch"
//   When I click "New Credential" and then press Escape in the credential form
//   Then the credential form closes and "Configure connection" is shown again
//   When I click "Change", pick "Salesforce" and press Escape on "Change Adaptor?"
//   Then the adaptor picker is shown
//   When I press Escape
//   Then the picker closes and "Fetch" is still open
// "Fetch" has a credential, so "Change Adaptor?" asks.
export async function S17(page: Page, box: Locator) {
  await openConfigure(page, box);
  await configure(page).getByRole('button', { name: 'New Credential' }).click();
  await expect(credentialForm(page)).toBeVisible();

  await page.keyboard.press('Escape');
  await expect(credentialForm(page)).toHaveCount(0);
  await expect(configureTitle(page)).toBeVisible();

  await changeAdaptor(configure(page)).click();
  await pick(page, /salesforce/i);
  await expect(confirmChangeTitle(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(confirmChangeTitle(page)).toBeHidden();
  await expect(pickerSearch(page)).toBeVisible();

  await page.keyboard.press('Escape');
  await expect(pickerSearch(page)).toBeHidden();
  await expect(box).toBeVisible();
}

// @S18 Read-only viewers see the configuration but cannot change it
//   Given I am a viewer on "Malawi HIV" and "Fetch" uses DHIS2 with "DHIS2 prod"
//   Then I see the DHIS2 adaptor, its version and a "DHIS2 prod" badge
//   And I see no "Change adaptor", "Edit" or "Connect" button
export async function S18(_page: Page, box: Locator, version = 'latest') {
  await expect(box).toContainText(/dhis2/i);
  await expect(box).toContainText(version);
  await expect(box).toContainText('DHIS2 prod');
  await expect(changeAdaptor(box)).toHaveCount(0);
  await expect(configureButton(box)).toHaveCount(0);
}

// Seeding for hosts

// Given step <jobId> uses <adaptor> and the project credential of
// <credentialId> in project <projectId>, or none
export function jobUses(
  jobId: string,
  adaptor: string,
  credential?: { projectId: string; credentialId: string }
) {
  exec(`update jobs set adaptor = $a$${adaptor}$a$, keychain_credential_id = null,
          project_credential_id = ${
            credential
              ? `(select id from project_credentials
                  where project_id = '${credential.projectId}'
                    and credential_id = '${credential.credentialId}')`
              : 'null'
          }
        where id = '${jobId}'`);
}

// Given adaptor "@openfn/language-old" and DHIS2 version <version> are
// retired (deprecated) in the instance's adaptor catalogue. Instance-wide: a
// test that uses it is @serial. Returns a function that puts it back.
export function withRetiredAdaptors(version = '4.1.0') {
  const v = `'${version}'`;
  const dhis2 = sql<{ id: string; had: boolean | null }>(
    `select a.id, v.deprecated as had from adaptors a
     left join adaptor_versions v on v.adaptor_id = a.id and v.version = ${v}
     where a.name = '@openfn/language-dhis2'`
  );
  exec(`insert into adaptors (id, name, source, latest_version, deprecated, checked_at, inserted_at, updated_at)
        select gen_random_uuid(), '@openfn/language-old', source, '1.0.0', true, now(), now(), now()
        from adaptors where name = '@openfn/language-dhis2'`);
  for (const { id, had } of dhis2)
    exec(
      had === null
        ? `insert into adaptor_versions (id, adaptor_id, version, deprecated, inserted_at)
           values (gen_random_uuid(), '${id}', ${v}, true, now())`
        : `update adaptor_versions set deprecated = true where adaptor_id = '${id}' and version = ${v}`
    );
  return () => {
    exec(`delete from adaptors where name = '@openfn/language-old'`);
    for (const { id, had } of dhis2)
      exec(
        had === null
          ? `delete from adaptor_versions where adaptor_id = '${id}' and version = ${v}`
          : `update adaptor_versions set deprecated = ${had} where adaptor_id = '${id}' and version = ${v}`
      );
  };
}

// Given the DHIS2 adaptor has versions <versions> (given.S07's) in the
// instance's adaptor catalogue, adding the ones it lacks. Instance-wide: a
// test that uses it is @serial. Returns a function that removes what it added.
export function withAdaptorVersions(versions = given.S07.versions) {
  const list = versions.map(v => `'${v}'`).join(', ');
  const missing = sql<{ id: string; version: string }>(
    `select a.id, v.version from adaptors a
     cross join unnest(array[${list}]) as v(version)
     where a.name = '@openfn/language-dhis2'
       and not exists (select 1 from adaptor_versions av
                       where av.adaptor_id = a.id and av.version = v.version)`
  );
  for (const { id, version } of missing)
    exec(`insert into adaptor_versions (id, adaptor_id, version, deprecated, inserted_at)
          values (gen_random_uuid(), '${id}', '${version}', false, now())`);
  return () => {
    for (const { id, version } of missing)
      exec(
        `delete from adaptor_versions where adaptor_id = '${id}' and version = '${version}'`
      );
  };
}
