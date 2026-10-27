// Scenarios from annotations/views/credentials-index.md, and the shared ones
// it inherits.
//
// Who's who: "I" am editor@openfn.org. "amara@example.org" and anyone else
// who owns a credential or belongs to a project are owner@openfn.org. Every
// project, credential and OAuth client is seeded by the test, or created
// through the page, and removed again afterwards.
import { expect, test, type Page } from '@playwright/test';

import {
  actionsOf,
  addEnvironmentButton,
  addEnvironmentLabel,
  addNew,
  addProject,
  addScopes,
  deleteEnvironment,
  dialog,
  enterBody,
  environmentTab,
  openEnvironment,
  forceDeleteNow,
  globalCheckbox,
  namingAnother,
  projectOptions,
  receiverEmail,
  removeProject,
  renameEnvironment,
  row,
  rowAction,
  saveCredential,
  scopeCheckbox,
  sendingGlobal,
  startCredential,
  typeOption,
} from './pages/credentials-index';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import {
  auditEventsOf,
  catalogueUnavailable,
  credentialBodiesOf,
  credentialNamed,
  credentialsNamed,
  credentialsOfJobs,
  field,
  fieldBlock,
  keepAccount,
  mailbox,
  makeSuperuser,
  makeSupportUser,
  markCredentialUsed,
  oauthBody,
  oauthClientsNamed,
  open,
  otherSession,
  projectCredentialId,
  removeCredentialsNamed,
  removeOauthClient,
  removeWorkflowData,
  seedCredential,
  seedOauthClient,
  seedProject,
  seedRun,
  seedWorkspace,
  signInAs,
  sql,
  standInOauth,
  submit,
  submitButton,
  useCredentialInJobs,
  user,
  watchLiveView,
  type CredentialSeed,
  type OauthClientSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PATH = '/credentials';

let cleanups: (() => unknown)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(async () => {
  for (const cleanup of cleanups.reverse()) await cleanup();
});

// Given project <name> exists with these members (removed after the test)
function project(name: string, members: Record<string, 'owner' | 'editor'>) {
  const p = seedProject(name, members);
  cleanups.push(p.remove);
  return p.id;
}

// Given this workspace exists, built by me (removed after the test)
function workspace(seed: WorkspaceSeed) {
  const w = seedWorkspace(seed, ME);
  cleanups.push(w.remove);
  return w;
}

// Given <owner> owns this credential (removed after the test)
function credential(seed: CredentialSeed, owner = ME) {
  const c = seedCredential(owner, seed);
  cleanups.push(c.remove);
  return c.id;
}

// Given <owner> owns this OAuth client (removed after the test)
function oauthClient(seed: OauthClientSeed, owner = ME) {
  const c = seedOauthClient(owner, seed);
  cleanups.push(c.remove);
  return c.id;
}

// Credentials and OAuth clients I create through the page are removed after
function removesCreated(credentials: string[], clients: string[] = []) {
  cleanups.push(() => {
    removeCredentialsNamed(ME, credentials);
    for (const name of clients)
      for (const { id } of oauthClientsNamed(ME, name)) removeOauthClient(id);
  });
}

// Given I am signed in and on "/credentials"
async function onCredentials(page: Page, email = ME) {
  await signInAs(page, email);
  await open(page, PATH);
}

// When I edit credential <name> — returns its form
async function edit(page: Page, name: string) {
  await rowAction(page, row(page, name), 'Edit');
  return dialog(page, `Edit ${name}`);
}

const toast = flashMessages.toast;
const events = (id: string) => auditEventsOf(id).map(e => e.event);

// The mail sent to <email>, newest first
async function mailTo(page: Page, email: string) {
  const address = user(email).email;
  return (await mailbox(page.request)).filter(m => m.to.includes(address));
}

// @S01
// Scenario: The page lists only credentials I own
//   Given I own credential "DHIS2 prod"
//   And credential "Shared Postgres" is owned by someone else and shared with a project I belong to
//   When I open "/credentials"
//   Then I see "DHIS2 prod"
//   And I do not see "Shared Postgres"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('Malawi HIV', { [OTHER]: 'owner', [ME]: 'editor' });
  credential({ name: 'DHIS2 prod' });
  credential({ name: 'Shared Postgres', projects: [malawi] }, OTHER);

  await onCredentials(page);

  await expect(row(page, 'DHIS2 prod')).toBeVisible();
  await expect(page.getByText('Shared Postgres')).toHaveCount(0);
});

// @S02
// Scenario: Owner creates a raw JSON credential and shares it with two projects
//   Given I am a member of projects "Malawi HIV" and "Kenya TB"
//   When I choose "Add new" then "Credential"
//   And I pick "Raw JSON" and continue
//   And I add projects "Malawi HIV" and "Kenya TB"
//   And I enter name "Mailchimp" and a valid JSON body
//   And I save the credential
//   Then I see "Credential created successfully"
//   And "Mailchimp" is listed with both projects
//   And an audit event "created" and two "added_to_project" events are recorded
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  project('Malawi HIV', { [ME]: 'owner' });
  project('Kenya TB', { [ME]: 'owner' });
  removesCreated(['Mailchimp']);
  await onCredentials(page);

  const form = await startCredential(page, 'Raw JSON');
  await addProject(form, 'Malawi HIV');
  await addProject(form, 'Kenya TB');
  await field(form, 'Credential Name').fill('Mailchimp');
  await enterBody(form, '{"apiKey": "abc123"}');
  await saveCredential(form);

  await expect(toast(page, 'Credential created successfully')).toBeVisible();
  await expect(row(page, 'Mailchimp')).toContainText('Malawi HIV');
  await expect(row(page, 'Mailchimp')).toContainText('Kenya TB');
  const stored = credentialNamed(ME, 'Mailchimp');
  expect(stored.projects).toEqual(['Kenya TB', 'Malawi HIV']);
  const recorded = events(stored.id);
  expect(recorded.filter(e => e === 'created')).toHaveLength(1);
  expect(recorded.filter(e => e === 'added_to_project')).toHaveLength(2);
});

// The dhis2 configuration schema the catalogue holds: each field's title and
// whether it is required
function dhis2Schema() {
  const [{ schema }] = sql<{ schema: string }>(
    `select schema_data::text as schema from adaptors
     where name = '@openfn/language-dhis2'`
  );
  let parsed = JSON.parse(schema);
  if (typeof parsed === 'string') parsed = JSON.parse(parsed);
  const { properties, required = [] } = parsed as {
    properties: Record<string, { title?: string }>;
    required?: string[];
  };
  return Object.entries(properties).map(([key, p]) => ({
    title: p.title ?? key,
    required: required.includes(key),
  }));
}

// @S03
// Scenario: Adaptor credentials ask for that adaptor's fields
//   Given the adaptor catalogue includes "dhis2" with a configuration schema
//   When I start a new credential and pick "Dhis2"
//   Then I see an input for each field in the dhis2 schema
//   And a required field I have touched and left empty shows an error
//   And "Save credential" stays disabled until the required fields are valid
// Not on the port: the form checks required fields on Save, not as you type.
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  const fields = dhis2Schema();
  expect(fields.length, 'the dhis2 schema has fields').toBeGreaterThan(0);
  removesCreated(['DHIS2 half done']);
  await onCredentials(page);

  const form = await startCredential(page, 'dhis2');
  for (const { title } of fields)
    await expect(field(form, title)).toBeVisible();

  const required = fields.find(f => f.required);
  expect(required, 'the dhis2 schema has a required field').toBeTruthy();
  const input = field(form, required!.title);
  await input.fill('x');
  await input.fill('');
  await input.blur();
  await expect(fieldBlock(form, required!.title)).toContainText(
    /blank|required/i
  );

  // The Value: a credential missing a required field is never stored
  await field(form, 'Credential Name').fill('DHIS2 half done');
  await submit(form, 'Save Credential');
  await expect(form).toBeVisible();
  expect(credentialsNamed(ME, 'DHIS2 half done')).toHaveLength(0);
});

// @S04
// Scenario: A raw body must be valid JSON
//   Given I am creating a raw JSON credential named "Mailchimp"
//   When I enter "{not json" as the body
//   Then I see "Invalid JSON format"
//   And "Save credential" is disabled
// Not on the port: the form checks the JSON on Save, not as you type.
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  removesCreated(['Mailchimp']);
  await onCredentials(page);
  const form = await startCredential(page, 'Raw JSON');
  await field(form, 'Credential Name').fill('Mailchimp');

  await enterBody(form, '{not json');
  await field(form, 'Credential Body').blur();

  await expect(form.getByText('Invalid JSON format')).toBeVisible();
  // The Value: the malformed secret is never stored
  await submit(form, 'Save Credential');
  await expect(form).toBeVisible();
  expect(credentialsNamed(ME, 'Mailchimp')).toHaveLength(0);
});

// @S05
// Scenario: Two of my credentials cannot share a name
//   Given I own credential "DHIS2 prod"
//   When I create another credential named "DHIS2 prod"
//   Then I see "you have another credential with the same name"
//   And no second credential is created
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  credential({ name: 'DHIS2 prod' });
  removesCreated(['DHIS2 prod']);
  await onCredentials(page);

  const form = await startCredential(page, 'Raw JSON');
  await field(form, 'Credential Name').fill('DHIS2 prod');
  await enterBody(form, '{"password": "another"}');
  await submit(form, 'Save Credential');

  await expect(
    form.getByText('you have another credential with the same name')
  ).toBeVisible();
  expect(credentialsNamed(ME, 'DHIS2 prod')).toHaveLength(1);
});

// @S06
// Scenario: Owner updates a credential's values
//   Given I own credential "DHIS2 prod" shared with "Malawi HIV"
//   When I edit "DHIS2 prod", change its password and save
//   Then I see "Credential updated successfully"
//   And the stored value for environment "main" is the new password
//   And an audit event "updated" is recorded
// @pending on today's Lightning and the port: the port keeps the old save.
test('@S06', { tag: '@pending' }, async ({ page }) => {
  const malawi = project('Malawi HIV', { [ME]: 'owner' });
  const id = credential({
    name: 'DHIS2 prod',
    projects: [malawi],
    bodies: { main: { password: 'old' } },
  });
  await onCredentials(page);

  const form = await edit(page, 'DHIS2 prod');
  await enterBody(form, '{"password": "rotated"}');
  await saveCredential(form);

  await expect(toast(page, 'Credential updated successfully')).toBeVisible();
  expect(credentialBodiesOf(id).main).toEqual({ password: 'rotated' });
  expect(events(id)).toContain('updated');
});

// @S07
// Scenario: A credential keeps separate values per environment
//   Given I am creating a raw JSON credential named "Mailchimp"
//   When I add an environment and rename it "staging"
//   And I enter different bodies on "main" and "staging"
//   And I save the credential
//   Then the credential has bodies named "main" and "staging" with the values I entered
// Fails on today's Lightning: the raw JSON of an environment that isn't open
// when saving is stored empty.
test('@S07', { tag: '@passing-new' }, async ({ page }) => {
  removesCreated(['Mailchimp']);
  await onCredentials(page);
  const form = await startCredential(page, 'Raw JSON');
  await field(form, 'Credential Name').fill('Mailchimp');
  await enterBody(form, '{"key": "production key"}');

  await addEnvironmentButton(form).click();
  await renameEnvironment(form, 'staging');
  await expect(environmentTab(form, 'staging')).toBeVisible();
  await enterBody(form, '{"key": "staging key"}');
  await saveCredential(form);

  await expect(toast(page, 'Credential created successfully')).toBeVisible();
  expect(credentialBodiesOf(credentialNamed(ME, 'Mailchimp').id)).toEqual({
    main: { key: 'production key' },
    staging: { key: 'staging key' },
  });
});

// @S08
// Scenario: Two environments cannot share a name
//   Given I am editing a credential with environments "main" and "staging"
//   When I rename "staging" to "main"
//   Then I see "Environment 'main' already exists"
//   And the environments are still "main" and "staging"
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const id = credential({
    name: 'Mailchimp',
    bodies: { main: { key: 'p' }, staging: { key: 's' } },
  });
  await onCredentials(page);
  const form = await edit(page, 'Mailchimp');

  await openEnvironment(form, 'staging');
  await renameEnvironment(form, 'main');

  await expect(
    form.getByText("Environment 'main' already exists")
  ).toBeVisible();
  await submit(form, 'Save Credential');
  expect(Object.keys(credentialBodiesOf(id)).sort()).toEqual([
    'main',
    'staging',
  ]);
});

// @S09
// Scenario: The sixth environment cannot be added
//   Given I am editing a credential with 5 environments
//   Then the add environment button is disabled
//   And its tooltip reads "Maximum of 5 environments reached"
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  credential({
    name: 'Mailchimp',
    bodies: Object.fromEntries(
      ['main', 'dev', 'qa', 'staging', 'uat'].map(n => [n, { key: n }])
    ),
  });
  await onCredentials(page);
  const form = await edit(page, 'Mailchimp');

  // The limit is the Value, so the button being off is what is checked
  await expect(addEnvironmentButton(form)).toBeDisabled();
  await expect(
    addEnvironmentLabel(form, 'Maximum of 5 environments reached')
  ).toBeAttached();
});

// @S10
// Scenario: Removing an environment deletes its stored values
//   Given I own a credential with environments "main" and "staging"
//   When I edit it, delete environment "staging", confirm, and save
//   Then the credential has no "staging" body
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const id = credential({
    name: 'Mailchimp',
    bodies: { main: { key: 'p' }, staging: { key: 's' } },
  });
  await onCredentials(page);
  const form = await edit(page, 'Mailchimp');

  await openEnvironment(form, 'staging');
  await deleteEnvironment(form);
  await expect(environmentTab(form, 'staging')).toHaveCount(0);
  await saveCredential(form);

  await expect(toast(page, 'Credential updated successfully')).toBeVisible();
  expect(Object.keys(credentialBodiesOf(id))).toEqual(['main']);
});

// @S11
// Scenario: Removing project access warns when workflows use the credential
//   Given I own credential "DHIS2 prod" used by workflow "Daily sync" in project "Malawi HIV"
//   When I edit "DHIS2 prod" and remove "Malawi HIV"
//   Then I am asked to confirm a warning naming "Daily sync"
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = workspace({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    workflows: ['Daily sync'],
  });
  const malawi = w.id('Malawi HIV');
  credential({ name: 'DHIS2 prod', projects: [malawi] });
  useCredentialInJobs(malawi, 'Daily sync', ME, 'DHIS2 prod');
  await onCredentials(page);
  const form = await edit(page, 'DHIS2 prod');

  const asked = await removeProject(form, 'Malawi HIV');

  expect(asked).toContain('Daily sync');
});

// @S12
// Scenario: Removing project access is recorded
//   Given I own credential "DHIS2 prod" shared with "Malawi HIV"
//   When I edit "DHIS2 prod", remove "Malawi HIV" and save
//   Then "DHIS2 prod" no longer lists "Malawi HIV"
//   And an audit event "removed_from_project" is recorded
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('Malawi HIV', { [ME]: 'owner' });
  const id = credential({ name: 'DHIS2 prod', projects: [malawi] });
  await onCredentials(page);
  const form = await edit(page, 'DHIS2 prod');

  await removeProject(form, 'Malawi HIV');
  await saveCredential(form);

  await expect(toast(page, 'Credential updated successfully')).toBeVisible();
  await expect(row(page, 'DHIS2 prod')).not.toContainText('Malawi HIV');
  expect(credentialNamed(ME, 'DHIS2 prod').projects).toEqual([]);
  expect(events(id)).toContain('removed_from_project');
});

// @S13
// Scenario: Sharing with a project also shares with its sandboxes
//   Given project "Malawi HIV" has sandbox "Malawi HIV staging"
//   When I share my credential "DHIS2 prod" with "Malawi HIV"
//   Then "DHIS2 prod" is available in "Malawi HIV staging"
test('@S13', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = workspace({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    // Sandbox names must be URL-safe
    sandboxes: [{ name: 'malawi-hiv-staging' }],
  });
  credential({ name: 'DHIS2 prod' });
  await onCredentials(page);
  const form = await edit(page, 'DHIS2 prod');

  await addProject(form, 'Malawi HIV');
  await saveCredential(form);

  await expect(toast(page, 'Credential updated successfully')).toBeVisible();
  expect(
    projectCredentialId(w.id('malawi-hiv-staging'), 'DHIS2 prod')
  ).toBeTruthy();
});

// @S14
// Scenario: I can only share with projects I belong to
//   Given I am a member of "Malawi HIV" and not of "Kenya TB"
//   When I open the project picker on a new credential
//   Then "Malawi HIV" is offered
//   And "Kenya TB" is not offered
test('@S14', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  project('Malawi HIV', { [ME]: 'editor', [OTHER]: 'owner' });
  project('Kenya TB', { [OTHER]: 'owner' });
  await onCredentials(page);

  const form = await startCredential(page, 'Raw JSON');
  const offered = await projectOptions(form);

  expect(offered).toContain('Malawi HIV');
  expect(offered).not.toContain('Kenya TB');
});

// @S15 @variant:support-user
// Scenario: Support users can also share into projects that allow support access
//   Given I am a support user
//   And project "Kenya TB" allows support access and I am not a member
//   When I create a credential and add "Kenya TB"
//   Then the credential is shared with "Kenya TB"
test('@S15', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  cleanups.push(makeSupportUser(ME));
  const kenya = seedProject(
    'Kenya TB',
    { [OTHER]: 'owner' },
    { allowSupportAccess: true }
  );
  cleanups.push(kenya.remove);
  removesCreated(['Support token']);
  await onCredentials(page);

  const form = await startCredential(page, 'Raw JSON');
  await addProject(form, 'Kenya TB');
  await field(form, 'Credential Name').fill('Support token');
  await enterBody(form, '{"token": "abc"}');
  await saveCredential(form);

  await expect(toast(page, 'Credential created successfully')).toBeVisible();
  expect(credentialNamed(ME, 'Support token').projects).toEqual(['Kenya TB']);
});

// @S16
// Scenario: Owner schedules a credential for deletion
//   Given I own credential "DHIS2 prod" shared with "Malawi HIV" and used by a job there
//   When I delete "DHIS2 prod" and confirm
//   Then I see "Credential scheduled for deletion"
//   And "DHIS2 prod" shows "Cancel deletion" and "Delete now"
//   And "DHIS2 prod" is no longer shared with any project
//   And the job no longer has a credential
//   And the flow "flow-credential-scheduled-deletion" has started for "DHIS2 prod"
test('@S16', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = workspace({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    workflows: ['Daily sync'],
  });
  const malawi = w.id('Malawi HIV');
  credential({ name: 'DHIS2 prod', projects: [malawi] });
  useCredentialInJobs(malawi, 'Daily sync', ME, 'DHIS2 prod');
  await onCredentials(page);

  await rowAction(page, row(page, 'DHIS2 prod'), 'Delete');
  const d = await dialog(page, 'Delete credential');
  await d.getByRole('button', { name: 'Delete credential' }).click();

  await expect(toast(page, 'Credential scheduled for deletion')).toBeVisible();
  const actions = (await actionsOf(page, row(page, 'DHIS2 prod'))).map(a =>
    a.toLowerCase()
  );
  expect(actions).toEqual(
    expect.arrayContaining(['cancel deletion', 'delete now'])
  );
  const stored = credentialNamed(ME, 'DHIS2 prod');
  expect(stored.scheduled_deletion).not.toBeNull();
  expect(stored.projects).toEqual([]);
  expect(credentialsOfJobs(malawi, 'Daily sync')).toEqual([null]);
  // The flow has started: the owner is told how to cancel
  await expect
    .poll(async () =>
      (await mailTo(page, ME)).some(m => m.text?.includes('DHIS2 prod'))
    )
    .toBe(true);
});

// @S17
// Scenario: Owner deletes a scheduled credential for good
//   Given I own credential "Old token" scheduled for deletion and never used in a run
//   When I choose "Delete now" and confirm
//   Then I see "Credential deleted successfully"
//   And "Old token" no longer exists
//   And an audit event "deleted" is recorded
test('@S17', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const id = credential({ name: 'Old token', scheduled: true });
  await onCredentials(page);

  await rowAction(page, row(page, 'Old token'), 'Delete now');
  const d = await dialog(page, 'Delete credential');
  await d.getByRole('button', { name: 'Delete credential' }).click();

  await expect(toast(page, 'Credential deleted successfully')).toBeVisible();
  expect(credentialsNamed(ME, 'Old token')).toHaveLength(0);
  expect(events(id)).toContain('deleted');
});

// @S18
// Scenario: A credential used in runs cannot be deleted now
//   Given I own credential "DHIS2 prod" scheduled for deletion and used in a run step
//   When I choose "Delete now"
//   Then I see "Credential marked for deletion" with only an "Ok, understood" button
//   And forcing the delete shows "Cannot delete a credential that has activities in projects"
//   And "DHIS2 prod" still exists
test('@S18', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const id = credential({ name: 'DHIS2 prod', scheduled: true });
  const malawi = project('Malawi HIV', { [ME]: 'owner' });
  const run = seedRun(malawi, { steps: [{ name: 'Fetch' }] }, ME);
  cleanups.push(() => removeWorkflowData(malawi));
  markCredentialUsed(id, run.steps.Fetch);
  const lv = watchLiveView(page);
  await onCredentials(page);

  await rowAction(page, row(page, 'DHIS2 prod'), 'Delete now');
  const d = await dialog(page, 'Credential marked for deletion');
  await expect(d.getByRole('button', { name: 'Ok, understood' })).toBeVisible();
  await expect(d.getByRole('button', { name: /delete/i })).toHaveCount(0);

  // Forced past the page, the delete is refused: checked by its effect, as
  // one version flashes and the other replies to a request it never sent
  await forceDeleteNow(page, lv, id);
  expect(lv.crashes()).toBe(0);
  expect(credentialsNamed(ME, 'DHIS2 prod')).toHaveLength(1);
});

// @S19
// Scenario: A delete confirmation cannot be pointed at another credential
//   Given I own "DHIS2 prod" and "Other" is owned by someone else
//   When I open the delete modal for "DHIS2 prod" and submit it with the id of "Other"
//   Then I see "You can't perform this action"
//   And neither credential is scheduled for deletion
test('@S19', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  credential({ name: 'DHIS2 prod' });
  const other = credential({ name: 'Other' }, OTHER);
  const lv = watchLiveView(page);
  const tampered = await namingAnother(page, other);
  await onCredentials(page);

  await rowAction(page, row(page, 'DHIS2 prod'), 'Delete');
  const d = await dialog(page, 'Delete credential');
  await tampered(d.getByRole('button', { name: 'Delete credential' }));
  await lv.answered(lv.events());

  // Checked by its effect: the refusal is a flash on one version and a reply
  // in the dialog on the other
  expect(lv.crashes()).toBe(0);
  expect(credentialNamed(ME, 'DHIS2 prod').scheduled_deletion).toBeNull();
  expect(credentialNamed(OTHER, 'Other').scheduled_deletion).toBeNull();
});

// When I start transferring <name> and enter <email>, then leave the field
async function transferTo(page: Page, name: string, email: string) {
  await rowAction(page, row(page, name), 'Transfer');
  const d = await dialog(page, 'Transfer Credential Ownership');
  await receiverEmail(d).fill(user(email).email);
  await receiverEmail(d).blur();
  return d;
}

// @S20
// Scenario: Owner starts a credential transfer
//   Given I own credential "DHIS2 prod" shared with "Malawi HIV"
//   And "amara@example.org" is a member of "Malawi HIV"
//   When I choose "Transfer" on "DHIS2 prod" and submit "amara@example.org"
//   Then I see "Credential transfer initiated. We've sent you a confirmation email."
//   And "DHIS2 prod" shows "Revoke transfer"
//   And the flow "flow-credential-transfer" has started for "DHIS2 prod"
test('@S20', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = project('Malawi HIV', { [ME]: 'owner', [OTHER]: 'editor' });
  credential({ name: 'DHIS2 prod', projects: [malawi] });
  await onCredentials(page);

  const d = await transferTo(page, 'DHIS2 prod', OTHER);
  // Today's form checks the recipient on leaving the field before it turns
  // Transfer on
  await expect(submitButton(d, 'Transfer')).toBeEnabled();
  await submitButton(d, 'Transfer').click();

  await expect(
    toast(
      page,
      "Credential transfer initiated. We've sent you a confirmation email."
    )
  ).toBeVisible();
  const actions = (await actionsOf(page, row(page, 'DHIS2 prod'))).map(a =>
    a.toLowerCase()
  );
  expect(actions).toContain('revoke transfer');
  expect(credentialNamed(ME, 'DHIS2 prod').transfer_status).toBe('pending');
  // The flow has started: the owner (not the recipient) gets the link
  await expect
    .poll(async () =>
      (await mailTo(page, ME)).some(m => m.subject.includes('DHIS2 prod'))
    )
    .toBe(true);
});

// @S21
// Scenario: A transfer to someone outside the credential's projects is refused
//   Given I own credential "DHIS2 prod" shared with "Malawi HIV"
//   And "amara@example.org" is not a member of "Malawi HIV"
//   When I enter "amara@example.org" in the transfer form
//   Then I see "User doesn't have access to these projects: Malawi HIV"
//   And "Transfer" is disabled
// Not on the port: the server checks the recipient on Transfer, not as you type.
test('@S21', { tag: '@passing-old' }, async ({ page }) => {
  const malawi = project('Malawi HIV', { [ME]: 'owner' });
  credential({ name: 'DHIS2 prod', projects: [malawi] });
  await onCredentials(page);

  const d = await transferTo(page, 'DHIS2 prod', OTHER);
  // Today's form checks the recipient on leaving the field, then turns
  // Transfer off; submit only if it is still on
  await expect(
    d.getByText("User doesn't have access to these projects: Malawi HIV")
  ).toBeVisible();
  await submit(d, 'Transfer');
  // The Value: the transfer never starts
  expect(credentialNamed(ME, 'DHIS2 prod').transfer_status).toBeNull();
});

// @S22
// Scenario: Owner revokes a pending transfer
//   Given I own credential "DHIS2 prod" with a pending transfer
//   When I choose "Revoke transfer" and confirm with "Revoke"
//   Then I see "Transfer revoked successfully"
//   And "DHIS2 prod" shows "Transfer"
test('@S22', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  credential({ name: 'DHIS2 prod', transferStatus: 'pending' });
  await onCredentials(page);

  await rowAction(page, row(page, 'DHIS2 prod'), 'Revoke transfer');
  const d = await dialog(page, 'Revoke Credential Transfer');
  await d.getByRole('button', { name: 'Revoke', exact: true }).click();

  await expect(toast(page, 'Transfer revoked successfully')).toBeVisible();
  const actions = (await actionsOf(page, row(page, 'DHIS2 prod'))).map(a =>
    a.toLowerCase()
  );
  expect(actions).toContain('transfer');
  expect(credentialNamed(ME, 'DHIS2 prod').transfer_status).toBeNull();
});

// When I fill in a new OAuth client's required fields
async function fillOauthClient(page: Page, name: string) {
  await addNew(page, 'OAuth client');
  const form = await dialog(page, 'Add an OAuth Client');
  await field(form, 'Name').fill(name);
  await field(form, 'Authorization Endpoint').fill(
    'https://accounts.example.org/oauth2/auth'
  );
  await field(form, 'Token Endpoint').fill(
    'https://accounts.example.org/oauth2/token'
  );
  await field(form, 'Client ID').fill('client-id');
  await field(form, 'Client Secret').fill('client-secret');
  return form;
}

// @S23
// Scenario: User adds an OAuth client
//   Given I am a member of "Malawi HIV"
//   When I choose "Add new" then "OAuth client"
//   And I fill in name, authorization endpoint, token endpoint, client ID and client secret
//   And I add mandatory scopes "read, write" and project "Malawi HIV"
//   And I add the OAuth client
//   Then I see "Oauth client created successfully"
//   And the client is listed with project "Malawi HIV"
//   And an audit event "created" is recorded for the client
test('@S23', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  project('Malawi HIV', { [ME]: 'owner' });
  removesCreated([], ['Sheets app']);
  await onCredentials(page);

  const form = await fillOauthClient(page, 'Sheets app');
  await addScopes(form, 'Mandatory Scopes', ['read', 'write']);
  await addProject(form, 'Malawi HIV');
  await submit(form, 'Add OAuth Client');

  await expect(toast(page, 'Oauth client created successfully')).toBeVisible();
  await expect(row(page, 'Sheets app')).toContainText('Malawi HIV');
  const [stored] = oauthClientsNamed(ME, 'Sheets app');
  expect(stored.projects).toEqual(['Malawi HIV']);
  expect(stored.mandatory_scopes?.split(/[\s,]+/).sort()).toEqual([
    'read',
    'write',
  ]);
  expect(events(stored.id)).toContain('created');
});

// @S24
// Scenario: OAuth client endpoints must be URLs
//   When I enter "oauth2/v2/auth" as the authorization endpoint of a new OAuth client
//   Then I see "must be either a http or https URL"
//   And "Add OAuth Client" is disabled
test('@S24', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  removesCreated([], ['Sheets app']);
  await onCredentials(page);
  const form = await fillOauthClient(page, 'Sheets app');

  await field(form, 'Authorization Endpoint').fill('oauth2/v2/auth');
  await field(form, 'Authorization Endpoint').blur();
  await submit(form, 'Add OAuth Client');

  await expect(
    fieldBlock(form, 'Authorization Endpoint').getByText(
      'must be either a http or https URL'
    )
  ).toBeVisible();
  // The Value: the client with the mistyped endpoint is never stored
  expect(oauthClientsNamed(ME, 'Sheets app')).toHaveLength(0);
});

// @S25
// Scenario: A non-superuser cannot publish a global OAuth client
//   Given I am not a superuser
//   When I add an OAuth client and the request carries global "true"
//   Then the client is saved as not global
//   And I do not see the "Make client global" checkbox
test('@S25', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  expect(user(ME).superuser).toBe(false);
  removesCreated([], ['Sheets app']);
  const tampered = await sendingGlobal(page);
  await onCredentials(page);

  const form = await fillOauthClient(page, 'Sheets app');
  await expect(globalCheckbox(form)).toHaveCount(0);
  await tampered(submitButton(form, 'Add OAuth Client'));

  await expect(toast(page, 'Oauth client created successfully')).toBeVisible();
  const [stored] = oauthClientsNamed(ME, 'Sheets app');
  expect(stored.global).toBe(false);
});

// @S26 @variant:superuser
// Scenario: Superuser makes an OAuth client global
//   Given I am a superuser
//   When I add an OAuth client and tick "Make client global"
//   Then the project picker is hidden
//   And other users see the client in their list as "GLOBAL" and can pick it for a new credential
// A global client shows on every user's page, so this runs alone
test(
  '@S26',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, browser }) => {
    cleanups.push(makeSuperuser(OTHER));
    cleanups.push(() => {
      for (const { id } of oauthClientsNamed(OTHER, 'Instance sheets'))
        removeOauthClient(id);
    });
    await onCredentials(page, OTHER);

    const form = await fillOauthClient(page, 'Instance sheets');
    await globalCheckbox(form).check();
    await expect(
      form.getByRole('option', { name: /^Grant projects access/ })
    ).toHaveCount(0);
    await submit(form, 'Add OAuth Client');
    await expect(
      toast(page, 'Oauth client created successfully')
    ).toBeVisible();

    const other = await otherSession(browser, ME);
    await open(other, PATH);
    await expect(row(other, 'Instance sheets')).toContainText('GLOBAL');
    await addNew(other, 'Credential');
    const picker = await dialog(other, 'Add a credential');
    await expect(typeOption(picker, 'Instance sheets')).toBeVisible();
    await other.context().close();
  }
);

// @S27
// Scenario: Creating an OAuth credential hands off to the provider sign-in
//   Given OAuth client "Google Sheets app" is mine or global
//   When I start a new credential, pick "Google Sheets app" and continue
//   And I choose "Sign in with Google Sheets app"
//   Then the flow "flow-oauth-credential-authorize" has started for environment "main"
test(
  '@S27',
  { tag: ['@passing-old', '@passing-new'] },
  async ({ page, context }) => {
    const provider = await standInOauth();
    cleanups.push(provider.close);
    oauthClient({ name: 'Google Sheets app', base: provider.base });
    await onCredentials(page);

    const form = await startCredential(page, 'Google Sheets app');
    const popup = context.waitForEvent('page');
    await form
      .getByRole('button', { name: 'Sign in with Google Sheets app' })
      .click();

    // The flow has started: the provider's sign-in opens, for this client
    const signIn = new URL((await (await popup).waitForEvent('load')).url());
    expect(`${signIn.origin}${signIn.pathname}`).toBe(
      `${provider.base}/authorize`
    );
    expect(signIn.searchParams.get('client_id')).toBe('scenario-client');
    expect(signIn.searchParams.get('state')).toBeTruthy();
  }
);

// Given I own OAuth credential "Sheets" through a client of the stand-in
// provider with mandatory scope "read" and optional "write", its token
// expiring <inSeconds> from now — returns the provider and the credential
async function givenOauthCredential(inSeconds: number) {
  const provider = await standInOauth();
  cleanups.push(provider.close);
  const client = oauthClient({
    name: 'Sheets app',
    base: provider.base,
    mandatoryScopes: 'read',
    optionalScopes: 'write',
  });
  const id = credential({
    name: 'Sheets',
    schema: 'oauth',
    oauthClient: client,
    bodies: { main: oauthBody('read', inSeconds) },
  });
  return { provider, client, id };
}

// @S28
// Scenario: Changing scopes after authorizing requires signing in again
//   Given I have authorized an OAuth credential with scopes "read"
//   When I tick an extra optional scope "write"
//   Then I am told to reauthorize
//   And "Save credential" is disabled until I do
test('@S28', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = await givenOauthCredential(3600);
  await onCredentials(page);
  const form = await edit(page, 'Sheets');
  await expect(form.getByText('Scenario Person').first()).toBeVisible();

  await scopeCheckbox(form, 'write').click();

  await expect(
    form.getByText(/Reauthentication Required/i).first()
  ).toBeVisible();
  // The Value: the stored token never claims scopes it wasn't granted
  await submit(form, 'Save Credential');
  expect(credentialBodiesOf(id).main.scope).toBe('read');
});

// @S29
// Scenario: Opening an OAuth credential with an expired token refreshes it
//   Given I own an OAuth credential whose access token has expired and whose refresh token is valid
//   When I edit it
//   Then the token is refreshed and the account details are shown
test('@S29', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { provider } = await givenOauthCredential(-60);
  await onCredentials(page);

  const form = await edit(page, 'Sheets');

  // Today the new token is stored on Save, not on opening, so only the
  // refresh request and the account are checked
  await expect(form.getByText('Scenario Person').first()).toBeVisible();
  expect(provider.requests.map(r => r.pathname)).toContain('/token');
});

// @S30
// Scenario: A revoked refresh token asks the owner to reauthorize
//   Given I own an OAuth credential whose refresh token the provider rejects with "invalid_grant"
//   When I edit it
//   Then I see a prompt to reauthorize with the provider
test('@S30', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { provider } = await givenOauthCredential(-60);
  provider.refreshes('invalid_grant');
  await onCredentials(page);

  const form = await edit(page, 'Sheets');

  await expect(
    form.getByRole('button', { name: /reauthori[sz]e|reauthenticate/i })
  ).toBeVisible();
  expect(provider.requests.map(r => r.pathname)).toContain('/token');
});

// @S31
// Scenario: An OAuth credential whose client was deleted shows a warning
//   Given I own an OAuth credential whose OAuth client has been deleted
//   When I edit it
//   Then I see "OAuth client not found"
test('@S31', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { client } = await givenOauthCredential(3600);
  removeOauthClient(client);
  await onCredentials(page);

  const form = await edit(page, 'Sheets');

  await expect(form.getByText('OAuth client not found').first()).toBeVisible();
});

// @S32
// Scenario: The type picker recovers when the adaptor catalogue is unavailable
//   Given the adaptor catalogue cannot answer
//   When I start a new credential
//   Then I see "Couldn't load adaptors. Please try again." with a "Retry" button
//   And "Raw JSON" is still offered
// The catalogue is instance-wide, so this runs alone
// Not on the port: the design-system picker has no unavailable state or Retry.
test('@S32', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  cleanups.push(catalogueUnavailable());
  await onCredentials(page);

  await addNew(page, 'Credential');
  const picker = await dialog(page, 'Add a credential');

  await expect(
    picker.getByText("Couldn't load adaptors. Please try again.")
  ).toBeVisible();
  await expect(picker.getByRole('button', { name: 'Retry' })).toBeVisible();
  await expect(typeOption(picker, 'Raw JSON')).toBeVisible();
});

// ---------------------------------------------------------------------------
// Shared: the credential list (annotations/shared/shared-credential-index-component.md)
// ---------------------------------------------------------------------------

test.describe('shared-credential-index-component', () => {
  // @S01
  // Scenario: Owner sees edit actions on their own credential
  //   Given I own credential "DHIS2 prod"
  //   When I open the credential list
  //   Then I see edit, delete and transfer actions for "DHIS2 prod"
  test(
    'shared-credential-index-component@S01 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      credential({ name: 'DHIS2 prod' });
      await onCredentials(page);

      const actions = (await actionsOf(page, row(page, 'DHIS2 prod'))).map(a =>
        a.toLowerCase()
      );
      expect(actions).toEqual(
        expect.arrayContaining(['edit', 'delete', 'transfer'])
      );
    }
  );

  // S02 (another member's credential in a project's list) can't be reached
  // here: this page lists only my own credentials (S01 above). S03 and S04
  // are about keychains, which load only with a project (the shared
  // annotation's 6.3).

  // @S05
  // Scenario: Owner cancels a scheduled credential deletion
  //   Given I own credential "DHIS2 prod" which is scheduled for deletion
  //   When I cancel its deletion
  //   Then I see "Credential deletion canceled"
  test(
    'shared-credential-index-component@S05 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      credential({ name: 'DHIS2 prod', scheduled: true });
      await onCredentials(page);

      await rowAction(page, row(page, 'DHIS2 prod'), 'Cancel deletion');

      await expect(toast(page, 'Credential deletion canceled')).toBeVisible();
      expect(credentialNamed(ME, 'DHIS2 prod').scheduled_deletion).toBeNull();
    }
  );

  // @S06
  // Scenario: A forged action from a non-owner is refused
  //   Given credential "DHIS2 prod" is owned by someone else
  //   When I send "edit_credential" for "DHIS2 prod"
  //   Then I see "You are not authorized to perform this action"
  // Checked by its effect: the other owner's credential never opens, and its
  // secret never reaches this page
  // Fails on today's Lightning: the page restarts instead of showing the message.
  test(
    'shared-credential-index-component@S06 on credentials-index',
    { tag: '@passing-new' },
    async ({ page }) => {
      credential({ name: 'Mine' });
      const theirs = credential(
        { name: 'DHIS2 prod', bodies: { main: { password: 'their-secret' } } },
        OTHER
      );
      const lv = watchLiveView(page);
      const tampered = await namingAnother(page, theirs);
      await onCredentials(page);

      await page.getByRole('button', { name: 'Actions' }).click();
      await tampered(page.getByRole('menu').getByText('Edit', { exact: true }));
      await lv.answered(lv.events());

      expect(lv.crashes()).toBe(0);
      await expect(page.getByRole('dialog')).toHaveCount(0);
      expect(await page.content()).not.toContain('their-secret');
    }
  );
});

// ---------------------------------------------------------------------------
// Shared: the signed-in session (annotations/shared/shared-authenticated-session.md)
// ---------------------------------------------------------------------------

test.describe('shared-authenticated-session', () => {
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  test(
    'shared-authenticated-session@S01 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, PATH, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PATH, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, PATH, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S07(
        page,
        browser,
        PATH,
        '/projects',
        ME,
        'Credentials'
      );
    }
  );

  // These variants are not configured on this instance
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
      `shared-authenticated-session@${id} on credentials-index`,
      { tag: '@pending' },
      () => {
        test.skip(true, `variant ${variant} is not configured here`);
      }
    );
});

// ---------------------------------------------------------------------------
// Shared: flash messages (annotations/shared/shared-flash-messages.md)
// ---------------------------------------------------------------------------

test.describe('shared-flash-messages', () => {
  const INFO = 'Credential deletion canceled';

  // Given I own a scheduled credential on the page; returns cancelling it
  async function givenScheduled(page: Page) {
    credential({ name: 'DHIS2 prod', scheduled: true });
    await onCredentials(page);
    return () => rowAction(page, row(page, 'DHIS2 prod'), 'Cancel deletion');
  }

  test(
    'shared-flash-messages@S01 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await flashMessages.S01(page, INFO, await givenScheduled(page));
    }
  );

  // A refusal: opening someone else's credential as a tampered client would
  // Fails on today's Lightning: the page restarts instead of showing the message.
  test(
    'shared-flash-messages@S02 on credentials-index',
    { tag: '@passing-new' },
    async ({ page }) => {
      credential({ name: 'Mine' });
      const theirs = credential({ name: 'Theirs' }, OTHER);
      const tampered = await namingAnother(page, theirs);
      await onCredentials(page);

      await flashMessages.S02(
        page,
        'You are not authorized to perform this action',
        async () => {
          await page.getByRole('button', { name: 'Actions' }).click();
          await tampered(
            page.getByRole('menu').getByText('Edit', { exact: true })
          );
        }
      );
    }
  );

  test(
    'shared-flash-messages@S03 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await flashMessages.S03(page, INFO, await givenScheduled(page));
    }
  );

  test(
    'shared-flash-messages@S04 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await flashMessages.S04(
        page,
        INFO,
        await givenScheduled(page),
        async () => {
          // Opening the new credential form makes the page render again
          await addNew(page, 'Credential');
          await dialog(page, 'Add a credential');
        }
      );
    }
  );

  // Scheduling a deletion redirects back to /credentials with the flash
  test(
    'shared-flash-messages@S05 on credentials-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      credential({ name: 'DHIS2 prod' });
      await onCredentials(page);

      await flashMessages.S05(
        page,
        'Credential scheduled for deletion',
        async () => {
          await rowAction(page, row(page, 'DHIS2 prod'), 'Delete');
          const d = await dialog(page, 'Delete credential');
          await d.getByRole('button', { name: 'Delete credential' }).click();
        },
        PATH
      );
    }
  );

  // S06 (a Not Found card) needs a page that can be refused by its URL;
  // /credentials takes no parameters. S07 is on admin pages and S08 on the
  // sign-in and account forms.
});
