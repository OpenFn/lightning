// Scenarios from annotations/views/project-settings-webhook-security.md. The
// shared session, scope, banner, header, flash and tab chrome scenarios run
// once for every settings tab, in project-settings-setup.spec.ts.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns the projects I don't.
import { expect, test, type Page } from '@playwright/test';

import {
  authMethodDialog,
  authMethodRow,
  chooseAuthType,
  expectMismatchRefused,
  expectOpen,
  newAuthMethod,
  openSettings,
  panel,
  sendAuthMethodRequest,
  settingsPath,
} from './pages/project-settings';
import {
  addWebhookAuthMethodOnNode,
  attachmentsOf,
  auditEventsOf,
  clickable,
  field,
  fieldBlock,
  PASSWORD,
  removeMfaOf,
  seedChannel,
  seedMfaFor,
  seedWorkspace,
  signInAs,
  storedAuthMethod,
  submit,
  submitButton,
  totpCode,
  watchLiveView,
  webhookTriggerOf,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PROJECT = 'Malawi HIV';

const PASSING_BOTH = { tag: ['@passing-old', '@passing-new'] };

// The secret seedMfaFor stores, in base32
const TOTP_SECRET = 'VOV2XK5LVOV2XK5LVOV2XK5LVOV2XK5L';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given I am a <role> on project <name> (owner@openfn.org owns it unless I do)
function givenProject(
  role: Role,
  name = PROJECT,
  extra: Partial<WorkspaceSeed> = {}
) {
  const members: Record<string, Role> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const w = seedWorkspace({ name, members, ...extra }, OTHER);
  cleanups.push(w.remove);
  return w.id(name);
}

const KOBO = { username: 'kobo', password: 'koboPassword123' };

// Given project <id> has basic auth method <name>
const givenBasic = (id: string, name: string, triggers: string[] = []) =>
  addWebhookAuthMethodOnNode(id, name, OTHER, { basic: KOBO, triggers });

// Given project <id> has API key method <name>
const givenApi = (id: string, name: string) =>
  addWebhookAuthMethodOnNode(id, name, OTHER);

// The names of project <id>'s auth methods not scheduled for deletion
const liveMethods = (id: string, names: string[]) =>
  names.filter(n => {
    const m = storedAuthMethod(id, n);
    return m && !m.scheduled_deletion;
  });

// Given I am signed in and on project <id>'s Webhook Security tab. Returns
// the watch on the tab's LiveView, set up before the tab opened.
async function onWebhookSecurity(page: Page, id: string) {
  await signInAs(page, ME);
  const lv = watchLiveView(page);
  await openSettings(page, id, 'Webhook Security');
  return lv;
}

// When I create basic auth method <name> with the form
async function createBasic(
  page: Page,
  name: string,
  password = 'testpassword123'
) {
  await newAuthMethod(page).click();
  await fillBasic(page, name, password);
}

// When I fill in basic auth method <name> in the open dialog
async function fillBasic(page: Page, name: string, password: string) {
  await chooseAuthType(page, 'Basic HTTP Authentication');
  await field(page, 'Auth method name').fill(name);
  await field(page, 'Username').fill('kobo');
  await field(page, 'Password').fill(password);
}

const CREATED = 'Webhook auth method created successfully';
const UPDATED = 'Webhook auth method updated successfully';
const DELETED = 'Your Webhook Authentication method has been deleted.';
const DELETE_TITLE = /Delete Authentication Method/i;

// @S01
// Scenario: Every member sees the project's auth methods
//   Given project "Malawi HIV" has auth methods "Kobo basic" (basic) and "DHIS2 key" (API)
//   And I am a viewer on project "Malawi HIV"
//   When I open the project's settings on the "Webhook Security" tab
//   Then I see "Kobo basic" with type "Basic"
//   And I see "DHIS2 key" with type "API"
test('@S01', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  givenBasic(id, 'Kobo basic');
  givenApi(id, 'DHIS2 key');
  await onWebhookSecurity(page, id);

  await expect(
    authMethodRow(page, 'Kobo basic').getByText('Basic', { exact: true })
  ).toBeVisible();
  await expect(
    authMethodRow(page, 'DHIS2 key').getByText('API', { exact: true })
  ).toBeVisible();
});

// @S02
// Scenario: Members can see what an auth method protects
//   Given auth method "Kobo basic" is attached to the trigger of workflow "Intake" and to channel "Lab results"
//   And I am a viewer on project "Malawi HIV"
//   When I open the "Webhook Security" tab
//   Then the row for "Kobo basic" shows "1 trigger, 1 channel"
//   When I click "1 trigger, 1 channel"
//   Then I see "Workflow triggers (1)" listing "Intake"
//   And I see "Channels (1)" listing "Lab results"
//   And "Intake" links to the workflow editor with the trigger selected
//   And "Lab results" links to "/projects/<project_id>/channels/<channel_id>/edit"
test('@S02', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  givenBasic(id, 'Kobo basic', ['Intake']);
  const channel = seedChannel(
    id,
    { name: 'Lab results', clients: ['Kobo basic'] },
    OTHER
  );
  const trigger = webhookTriggerOf(id, 'Intake');
  await onWebhookSecurity(page, id);

  const row = authMethodRow(page, 'Kobo basic');
  await expect(row).toContainText('1 trigger, 1 channel');
  await clickable(row, '1 trigger, 1 channel').click();

  const dialog = authMethodDialog(page, 'Workflow triggers (1)');
  await expect(dialog).toContainText('Channels (1)');
  await expect(clickable(dialog, 'Intake')).toHaveAttribute(
    'href',
    new RegExp(`/projects/${id}/w/[^?#]+\\?.*\\b${trigger}\\b`)
  );
  await expect(clickable(dialog, 'Lab results')).toHaveAttribute(
    'href',
    `/projects/${id}/channels/${channel}/edit`
  );
});

// @S03
// Scenario: An unused auth method says so
//   Given auth method "Old key" is attached to nothing
//   When I open the "Webhook Security" tab as an owner
//   Then the row for "Old key" shows "No associated triggers or channels..."
//   And there is no usage link for "Old key"
test('@S03', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  givenApi(id, 'Old key');
  await onWebhookSecurity(page, id);

  const row = authMethodRow(page, 'Old key');
  await expect(row).toContainText(/No associated triggers or channels/);
  await expect(clickable(row, /trigger|channel/)).toHaveCount(0);
});

// @S04
// Scenario: A project with no auth methods offers to create one
//   Given project "Malawi HIV" has no auth methods
//   And I am an admin on project "Malawi HIV"
//   When I open the "Webhook Security" tab
//   Then I see "No auth methods found."
//   And I see an enabled "Create a new auth method" button
test('@S04', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onWebhookSecurity(page, id);

  const tab = panel(page, 'Webhook Security');
  await expect(tab).toContainText('No auth methods found.');
  const create = tab.getByRole('button', { name: 'Create a new auth method' });
  await expect(create).toBeEnabled();
  await create.click();
  await expectOpen(authMethodDialog(page, 'Basic HTTP Authentication'));
});

// @S05
// Scenario: Admin creates a basic auth method
//   Given I am an admin on project "Malawi HIV"
//   When I click "New auth method"
//   Then I see "Basic HTTP Authentication (username & password)" and "API Key Authentication (‘x-api-key’ header)"
//   When I choose "Basic HTTP Authentication" and click "Next"
//   Then I see "Create a \"basic auth\" method"
//   When I fill "Auth method name" with "Kobo basic", "Username" with "kobo", "Password" with "testpassword123"
//   And I click "Create auth method"
//   Then I see "Webhook auth method created successfully"
//   And the modal closes
//   And "Kobo basic" appears in the list with type "Basic"
//   And an audit event "created" is recorded for "Kobo basic"
test('@S05', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onWebhookSecurity(page, id);

  await newAuthMethod(page).click();
  const choice = authMethodDialog(page, 'Basic HTTP Authentication');
  await expect(choice).toContainText('API Key Authentication');
  await fillBasic(page, 'Kobo basic', 'testpassword123');
  await page.getByRole('button', { name: 'Create auth method' }).click();

  await expect(page.getByText(CREATED)).toBeVisible();
  await expect(field(page, 'Auth method name')).toBeHidden();
  await expect(
    authMethodRow(page, 'Kobo basic').getByText('Basic', { exact: true })
  ).toBeVisible();
  const stored = storedAuthMethod(id, 'Kobo basic')!;
  expect(stored).toMatchObject({
    auth_type: 'basic',
    username: 'kobo',
    password: 'testpassword123',
  });
  expect(auditEventsOf(stored.id).map(e => e.event)).toContain('created');
});

// @S06
// Scenario: Admin creates an API key method and can copy the key before saving
//   Given I am an admin on project "Malawi HIV"
//   When I click "New auth method", choose "API Key Authentication" and click "Next"
//   Then I see "Create an \"API token\" method"
//   And the "API Key" field shows a 64-character key in full with a "Copy" button
//   When I fill "Auth method name" with "DHIS2 key" and click "Create auth method"
//   Then I see "Webhook auth method created successfully"
//   And "DHIS2 key" appears in the list with type "API"
//   And its stored key equals the key that was shown
test('@S06', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onWebhookSecurity(page, id);

  await newAuthMethod(page).click();
  await chooseAuthType(page, 'API Key Authentication');
  const key = await field(page, 'API Key').inputValue();
  expect(key).toMatch(/^[0-9a-f]{64}$/);
  await expect(clickable(page.getByRole('dialog'), 'Copy')).toBeVisible();
  await field(page, 'Auth method name').fill('DHIS2 key');
  await page.getByRole('button', { name: 'Create auth method' }).click();

  await expect(page.getByText(CREATED)).toBeVisible();
  await expect(
    authMethodRow(page, 'DHIS2 key').getByText('API', { exact: true })
  ).toBeVisible();
  expect(storedAuthMethod(id, 'DHIS2 key')?.api_key).toBe(key);
});

// @S07
// Scenario: A basic auth password must be 8 to 72 characters
//   Given I am creating a basic auth method on project "Malawi HIV"
//   When I fill "Password" with "short"
//   Then I see a length error on "Password"
//   And "Create auth method" is disabled
test('@S07', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onWebhookSecurity(page, id);

  await createBasic(page, 'Kobo basic', 'short');
  await field(page, 'Password').blur();
  await submit(page.getByRole('dialog'), 'Create auth method');

  await expect(fieldBlock(page.getByRole('dialog'), 'Password')).toContainText(
    /\b8\b/
  );
  expect(storedAuthMethod(id, 'Kobo basic')).toBeUndefined();
});

// @S08
// Scenario: Two auth methods in a project cannot share a name
//   Given project "Malawi HIV" has an auth method "Kobo basic"
//   And I am creating a basic auth method on project "Malawi HIV"
//   When I submit the name "Kobo basic" with a valid username and password
//   Then I see "must be unique within the project"
//   And the project still has one method named "Kobo basic"
test('@S08', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const existing = givenApi(id, 'Kobo basic');
  await onWebhookSecurity(page, id);

  await createBasic(page, 'Kobo basic');
  await submit(page.getByRole('dialog'), 'Create auth method');

  await expect(page.getByRole('dialog')).toContainText(
    'must be unique within the project'
  );
  expect(storedAuthMethod(id, 'Kobo basic')?.id).toBe(existing);
});

// @S09
// Scenario: Admin renames an auth method without changing its secret
//   Given basic auth method "Kobo basic" with username "kobo"
//   And I am an admin on project "Malawi HIV"
//   When I click "View" on "Kobo basic"
//   Then the "Username" field is disabled
//   And the password is masked behind a "Show" button
//   When I change "Auth method name" to "Kobo intake" and click "Save changes"
//   Then I see "Webhook auth method updated successfully"
//   And "Kobo intake" appears in the list
//   And the method's username and password are unchanged
//   And an audit event "updated" is recorded
test('@S09', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const method = givenBasic(id, 'Kobo basic');
  await onWebhookSecurity(page, id);

  await clickable(authMethodRow(page, 'Kobo basic'), 'View').click();
  const dialog = page.getByRole('dialog');
  await expect(field(dialog, 'Username')).toBeDisabled();
  await expect(clickable(dialog, 'Show')).toBeVisible();
  await expect(dialog).not.toContainText(KOBO.password);
  await field(dialog, 'Auth method name').fill('Kobo intake');
  await dialog.getByRole('button', { name: 'Save changes' }).click();

  await expect(page.getByText(UPDATED)).toBeVisible();
  await expect(authMethodRow(page, 'Kobo intake')).toBeVisible();
  expect(storedAuthMethod(id, 'Kobo intake')).toMatchObject({
    id: method,
    ...KOBO,
  });
  expect(auditEventsOf(method).map(e => e.event)).toContain('updated');
});

// @S10
// Scenario Outline: A stored secret is hidden until the admin re-enters their password
//   Given <type> auth method "<name>" exists on project "Malawi HIV"
//   And I am an admin on project "Malawi HIV"
//   When I open "<name>" with "View"
//   Then the page does not contain the stored <secret>
//   And the <secret> field shows "Show"
//   When I click "Show"
//   Then I see "You're required to reauthenticate yourself before viewing the webhook <label>"
//   When I submit the password "wrongpass"
//   Then I see "Invalid! Please try again"
//   When I submit my account password
//   Then the <secret> is displayed with a "Copy" button
const S10 = [
  { type: 'API', name: 'DHIS2 key', label: 'API Key' },
  { type: 'basic', name: 'Kobo basic', label: 'Password' },
] as const;
for (const row of S10) {
  test(`@S10 ${row.type}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject('admin');
    if (row.type === 'API') givenApi(id, row.name);
    else givenBasic(id, row.name);
    const stored = storedAuthMethod(id, row.name)!;
    const secret = (row.type === 'API' ? stored.api_key : stored.password)!;
    await onWebhookSecurity(page, id);

    await clickable(authMethodRow(page, row.name), 'View').click();
    expect(await page.content()).not.toContain(secret);
    await clickable(page.getByRole('dialog'), 'Show').click();
    await expect(page.getByRole('dialog')).toContainText(
      `reauthenticate yourself before viewing the webhook ${row.label}`
    );
    await field(page.getByRole('dialog'), 'Password').fill('wrongpass');
    await page
      .getByRole('dialog')
      .getByRole('button', { name: 'Done' })
      .click();
    await expect(page.getByRole('dialog')).toContainText(
      'Invalid! Please try again'
    );
    expect(await page.content()).not.toContain(secret);
    await field(page.getByRole('dialog'), 'Password').fill(PASSWORD);
    await page
      .getByRole('dialog')
      .getByRole('button', { name: 'Done' })
      .click();

    await expect(field(page.getByRole('dialog'), row.label)).toHaveValue(
      secret
    );
    await expect(clickable(page.getByRole('dialog'), 'Copy')).toBeVisible();
  });
}

// @S11
// Scenario: A 2FA code also unlocks a stored secret
//   Given I am an admin on project "Malawi HIV" with an authenticator app enrolled
//   And I am viewing API key method "DHIS2 key" and clicked "Show"
//   When I submit a valid 6-digit code in "2FA Code" and leave "Password" empty
//   Then the API key is displayed with a "Copy" button
test('@S11', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  givenApi(id, 'DHIS2 key');
  const key = storedAuthMethod(id, 'DHIS2 key')!.api_key!;
  await signInAs(page, ME);
  // Enrolled after signing in, so no second factor is asked for
  seedMfaFor(ME);
  cleanups.push(() => removeMfaOf(ME));
  await openSettings(page, id, 'Webhook Security');

  await clickable(authMethodRow(page, 'DHIS2 key'), 'View').click();
  await clickable(page.getByRole('dialog'), 'Show').click();
  await field(page.getByRole('dialog'), '2FA Code').fill(totpCode(TOTP_SECRET));
  await page.getByRole('dialog').getByRole('button', { name: 'Done' }).click();

  await expect(field(page.getByRole('dialog'), 'API Key')).toHaveValue(key);
  await expect(clickable(page.getByRole('dialog'), 'Copy')).toBeVisible();
});

// @S12
// Scenario: Admin deletes an auth method after confirming
//   Given auth method "Old key" exists on project "Malawi HIV"
//   And I am an owner on project "Malawi HIV"
//   When I click "Delete" on "Old key"
//   Then I see "Delete Authentication Method"
//   When I type "diel" in the confirmation field
//   Then I see "Please type DELETE to confirm"
//   And "Delete authentication method" is disabled
//   When I type "DELETE" and submit
//   Then I see "Your Webhook Authentication method has been deleted."
//   And "Old key" is no longer listed
//   And "Old key" is no longer attached to any trigger or channel
//   And an audit event "deleted" is recorded
test('@S12', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  const method = givenBasic(id, 'Old key', ['Intake']);
  seedChannel(id, { name: 'Lab results', clients: ['Old key'] }, OTHER);
  await onWebhookSecurity(page, id);

  await clickable(authMethodRow(page, 'Old key'), 'Delete').click();
  const dialog = authMethodDialog(page, DELETE_TITLE);
  const confirm = field(dialog, "Type in 'DELETE' to confirm the deletion");
  await confirm.fill('diel');
  await confirm.blur();
  await expectMismatchRefused(dialog, 'Delete authentication method');
  expect(liveMethods(id, ['Old key'])).toEqual(['Old key']);

  await confirm.fill('DELETE');
  await expect(
    submitButton(dialog, 'Delete authentication method')
  ).toBeEnabled();
  await submit(dialog, 'Delete authentication method');

  await expect(page.getByText(DELETED)).toBeVisible();
  await expect(authMethodRow(page, 'Old key')).toHaveCount(0);
  expect(attachmentsOf(method)).toEqual([]);
  expect(auditEventsOf(method).map(e => e.event)).toContain('deleted');
});

// @S13
// Scenario: The delete modal warns which triggers and channels lose the method
//   Given auth method "Kobo basic" is attached to the trigger of workflow "My Workflow" and to channel "My Channel"
//   And I am an owner on project "Malawi HIV"
//   When I click "Delete" on "Kobo basic"
//   Then I see "1 workflow trigger will stop requiring authentication" listing "My Workflow"
//   And I see "1 channel will accept unauthenticated requests" listing "My Channel"
//   And "My Channel" links to "/projects/<project_id>/channels/<channel_id>/edit"
//   And I see "These channels stay enabled and keep forwarding requests to their destination with the project credential attached."
test('@S13', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  givenBasic(id, 'Kobo basic', ['My Workflow']);
  const channel = seedChannel(
    id,
    { name: 'My Channel', clients: ['Kobo basic'] },
    OTHER
  );
  await onWebhookSecurity(page, id);

  await clickable(authMethodRow(page, 'Kobo basic'), 'Delete').click();
  const dialog = authMethodDialog(page, DELETE_TITLE);

  await expect(dialog).toContainText(
    '1 workflow trigger will stop requiring authentication'
  );
  await expect(dialog).toContainText('My Workflow');
  await expect(dialog).toContainText(
    '1 channel will accept unauthenticated requests'
  );
  await expect(
    dialog.getByRole('link', { name: 'My Channel' })
  ).toHaveAttribute('href', `/projects/${id}/channels/${channel}/edit`);
  await expect(dialog).toContainText(
    'These channels stay enabled and keep forwarding requests to their destination with the project credential attached.'
  );
});

// @S14
// Scenario: The delete modal says when nothing depends on the method
//   Given auth method "Old key" is attached to nothing
//   When I click "Delete" on "Old key" as an owner
//   Then I see "which is used by no workflows or channels"
//   And I do not see "will accept unauthenticated requests"
test('@S14', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  givenApi(id, 'Old key');
  await onWebhookSecurity(page, id);

  await clickable(authMethodRow(page, 'Old key'), 'Delete').click();
  const dialog = authMethodDialog(page, DELETE_TITLE);

  await expect(dialog).toContainText(
    'which is used by no workflows or channels'
  );
  await expect(dialog).not.toContainText('will accept unauthenticated');
  await expect(dialog).not.toContainText('will stop requiring');
});

// @S15
// Scenario Outline: Members who aren't admins can't change auth methods
//   Given auth method "Kobo basic" exists on project "Malawi HIV"
//   And I am a <role> on project "Malawi HIV"
//   When I open the "Webhook Security" tab
//   Then the "New auth method" button is disabled
//   And the "Edit" and "Delete" links on "Kobo basic" do nothing
//   When I send the "show_modal" event for "<target>" directly
//   Then I see "You are not authorized to perform this action"
//   And no auth method modal opens
const S15 = [
  ['editor', 'create'],
  ['viewer', 'create'],
  ['editor', 'rename'],
  ['viewer', 'rename'],
  ['editor', 'delete'],
  ['viewer', 'delete'],
] as const;
for (const [role, kind] of S15) {
  test(`@S15 ${role} ${kind}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject(role);
    const method = givenBasic(id, 'Kobo basic');
    const lv = await onWebhookSecurity(page, id);

    // Not being allowed to add a method is what the user sees here
    await expect(newAuthMethod(page)).toBeDisabled();
    const row = authMethodRow(page, 'Kobo basic');
    for (const name of [/^(Edit|View)$/, /^Delete$/]) {
      const link = clickable(row, name);
      if (await link.isEnabled()) await link.click();
    }
    await expect(page.getByRole('dialog')).toHaveCount(0);

    await sendAuthMethodRequest(page, lv, kind, method);

    await expect(page.getByRole('dialog')).toHaveCount(0);
    expect(storedAuthMethod(id, 'Kobo basic')).toMatchObject({
      id: method,
      scheduled_deletion: null,
    });
    expect(storedAuthMethod(id, 'crafted-method')).toBeUndefined();
    expect(lv.crashes()).toBe(0);
  });
}

// @S16
// Scenario: An admin can't reach another project's auth method by id
//   Given auth method "someone-elses-auth" belongs to a different project
//   And I am an admin on project "Malawi HIV"
//   When I send "show_modal" for edit, delete or linked usage with that method's id
//   Then I see "Webhook auth method not found"
//   And I do not see "someone-elses-auth"
for (const kind of ['rename', 'delete', 'usage'] as const) {
  test(`@S16 ${kind}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject('admin');
    const elsewhere = seedWorkspace(
      { name: 'elsewhere', members: { [OTHER]: 'owner' } },
      OTHER
    );
    cleanups.push(elsewhere.remove);
    const otherId = elsewhere.id('elsewhere');
    const foreign = givenBasic(otherId, 'someone-elses-auth', ['Theirs']);
    const lv = await onWebhookSecurity(page, id);

    await sendAuthMethodRequest(page, lv, kind, foreign);

    await expect(page.getByText('someone-elses-auth')).toHaveCount(0);
    expect(storedAuthMethod(otherId, 'someone-elses-auth')).toMatchObject({
      id: foreign,
      scheduled_deletion: null,
    });
    expect(attachmentsOf(foreign)).toEqual(['Theirs']);
    expect(lv.crashes()).toBe(0);
  });
}

// @S17 @variant:sandbox
// Scenario: A sandbox points to the parent for webhook security
//   Given sandbox "dev" of project "Malawi HIV"
//   And I am an owner of sandbox "dev"
//   When I open the settings of sandbox "dev" on the "Webhook Security" tab
//   Then I see "Webhook authentication is managed in the parent project"
//   And I see "Manage them in the parent project (Malawi HIV)" linking to "/projects/<parent_id>/settings#webhook_security"
//   And I do not see "New auth method" or an auth method table
test('@S17', PASSING_BOTH, async ({ page }) => {
  const w = seedWorkspace(
    { name: PROJECT, members: { [ME]: 'owner' }, sandboxes: [{ name: 'dev' }] },
    ME
  );
  cleanups.push(w.remove);
  givenBasic(w.id(PROJECT), 'Kobo basic');
  await onWebhookSecurity(page, w.id('dev'));

  const tab = panel(page, 'Webhook Security');
  await expect(tab).toContainText(
    'Webhook authentication is managed in the parent project'
  );
  await expect(
    clickable(tab, `Manage them in the parent project (${PROJECT})`)
  ).toHaveAttribute('href', settingsPath(w.id(PROJECT), 'Webhook Security'));
  await expect(newAuthMethod(page)).toHaveCount(0);
  await expect(tab.getByRole('table')).toHaveCount(0);
});

// @S18
// Scenario: Creating, renaming or deleting a method hands off to webhook enforcement
//   Given I am an admin on project "Malawi HIV"
//   When I create, rename or delete an auth method
//   Then the flow "flow-webhook-auth-method-enforcement" reflects that method's current state
test('@S18', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  givenBasic(id, 'Kobo basic', ['Intake']);
  const webhook = `/i/${webhookTriggerOf(id, 'Intake')}`;
  const basic = `Basic ${Buffer.from(`${KOBO.username}:${KOBO.password}`).toString('base64')}`;
  const post = (headers: Record<string, string> = {}) =>
    page.request.post(webhook, { data: {}, headers }).then(r => r.ok());
  await onWebhookSecurity(page, id);

  // The method protects the webhook, under its new name too
  expect(await post()).toBe(false);
  await clickable(authMethodRow(page, 'Kobo basic'), 'View').click();
  await field(page.getByRole('dialog'), 'Auth method name').fill('Kobo intake');
  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect(authMethodRow(page, 'Kobo intake')).toBeVisible();
  expect(await post()).toBe(false);
  expect(await post({ authorization: basic })).toBe(true);

  // Once deleted, the webhook no longer asks for it
  await clickable(authMethodRow(page, 'Kobo intake'), 'Delete').click();
  const dialog = authMethodDialog(page, DELETE_TITLE);
  await field(dialog, "Type in 'DELETE' to confirm the deletion").fill(
    'DELETE'
  );
  await expect(
    submitButton(dialog, 'Delete authentication method')
  ).toBeEnabled();
  await submit(dialog, 'Delete authentication method');
  await expect(authMethodRow(page, 'Kobo intake')).toHaveCount(0);
  expect(await post()).toBe(true);
});

// Shared scenarios from annotations/shared/shared-webhook-auth-method-form.md.
// The page's own scenarios already run most of them on this host: shared
// S01=S05, S02=S06, S03=S07, S04=S08, S06=S09, S07=S10, S08=S11, S09=S12,
// S10=S13, S11=S14. Shared S12 is the workflow editor host, not this page.
test.describe('webhook-auth-method-form', () => {
  // @S05
  // Scenario: Cancelling the form creates nothing
  //   Given I am creating a basic auth method on project "Malawi HIV" with name "Draft"
  //   When I click "Cancel"
  //   Then the auth method form closes
  //   And project "Malawi HIV" has no method named "Draft"
  test('@S05', PASSING_BOTH, async ({ page }) => {
    const id = givenProject('admin');
    await onWebhookSecurity(page, id);

    await createBasic(page, 'Draft');
    await page
      .getByRole('dialog')
      .getByRole('button', { name: 'Cancel' })
      .click();

    await expect(field(page, 'Auth method name')).toBeHidden();
    await expect(authMethodRow(page, 'Draft')).toHaveCount(0);
    expect(storedAuthMethod(id, 'Draft')).toBeUndefined();
  });
});
