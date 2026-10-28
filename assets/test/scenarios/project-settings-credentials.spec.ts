// Scenarios from annotations/views/project-settings-credentials.md, and the
// credential list's shared ones as this tab shows them. The shared session,
// scope, banner, header, flash and tab chrome scenarios run once for every
// settings tab, in project-settings-setup.spec.ts. The credential and OAuth
// client forms are credentials-index's; here only what the tab changes.
//
// Who's who: "I" am editor@openfn.org; each test gives me the role its Given
// names. "amara@example.org", and anyone else who owns a credential or the
// project, is owner@openfn.org.
import { expect, test, type Locator, type Page } from '@playwright/test';

import {
  actionsOf,
  dialog,
  enterBody,
  expectEnvironment,
  projectChip,
  receiverEmail,
  row,
  rowAction,
  saveCredential,
  startCredential,
  typeOption,
} from './pages/credentials-index';
import {
  addKeychain,
  addNewOption,
  checkKeychain,
  craftingDefaultCredential,
  defaultCredentialPicker,
  expectRefusal,
  fillKeychain,
  keychainForm,
  keychainSaveButton,
  openSettings,
  optionDisabled,
  panel,
  sendCredentialEdit,
  sendKeychainEdit,
  sendNewCredentialRequest,
  settingsPath,
} from './pages/project-settings';
import * as flashMessages from './shared/flash-messages';
import {
  credentialNamed,
  credentialsNamed,
  expectAt,
  field,
  fieldBlock,
  keychainsOf,
  mailbox,
  makeSupportUser,
  oauthClientsNamed,
  removeCredentialsNamed,
  removeOauthClient,
  seedCredential,
  seedKeychain,
  seedOauthClient,
  seedWorkspace,
  signInAs,
  standInOauth,
  submit,
  submitButton,
  user,
  watchLiveView,
  type CredentialSeed,
  type KeychainSeed,
  type OauthClientSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PROJECT = 'Malawi HIV';

const PENDING = { tag: '@pending' };
const NEW_ONLY = { tag: '@passing-new' };
const PASSING_BOTH = { tag: ['@passing-old', '@passing-new'] };

let cleanups: (() => unknown)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(async () => {
  for (const cleanup of cleanups.reverse()) await cleanup();
});

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given this workspace exists (removed after the test)
function given(seed: WorkspaceSeed, by: string) {
  const w = seedWorkspace(seed, by);
  cleanups.push(w.remove);
  return w;
}

// Given I am a <role> on project <name> (owner@openfn.org owns it unless I
// do); null makes me no member at all
function givenProject(
  role: Role | null,
  extra: Partial<WorkspaceSeed> = {},
  name = PROJECT
) {
  const members: Record<string, Role | null> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const by = role === 'owner' ? ME : OTHER;
  return given({ name, members, ...extra }, by).id(name);
}

// Given <owner> owns this credential (removed after the test)
function credential(seed: CredentialSeed, owner = OTHER) {
  const c = seedCredential(owner, seed);
  cleanups.push(c.remove);
  return c.id;
}

// Given <owner> owns this OAuth client (removed after the test)
function oauthClient(seed: OauthClientSeed, owner = OTHER) {
  const c = seedOauthClient(owner, seed);
  cleanups.push(c.remove);
  return c.id;
}

// Given project <projectId> has this keychain, made by its owner
const keychain = (projectId: string, seed: KeychainSeed) =>
  seedKeychain(projectId, seed, OTHER);

// Credentials and OAuth clients I create through the page are removed after
function removesCreated(credentials: string[], clients: string[] = []) {
  cleanups.push(() => {
    removeCredentialsNamed(ME, credentials);
    for (const name of clients)
      for (const { id } of oauthClientsNamed(ME, name)) removeOauthClient(id);
  });
}

// Given I am signed in and on project <id>'s Credentials tab
async function onCredentials(page: Page, id: string) {
  await signInAs(page, ME);
  const lv = watchLiveView(page);
  await openSettings(page, id, 'Credentials');
  return lv;
}

// Back on project <id>'s Credentials tab. Today a save patches to the tab's
// path with its fragment.
async function expectBackOnTab(page: Page, id: string) {
  await expectAt(page, new RegExp(`${settingsPath(id)}(#credentials)?$`));
  await expect(panel(page, 'Credentials')).toBeVisible();
}

const toast = flashMessages.toast;
const NOT_AUTHORIZED = /You are not authori[sz]ed to perform this action/;

// The mail sent to <email>
async function mailTo(page: Page, email: string) {
  const address = user(email).email;
  return (await mailbox(page.request)).filter(m => m.to.includes(address));
}

// The actions <name>'s row offers, lower case
const actionsOn = async (page: Page, name: string) =>
  (await actionsOf(page, row(page, name))).map(a => a.toLowerCase());

// @S01
// Scenario: Members see the project's credentials and who owns them
//   Given I am a viewer on project "Malawi HIV"
//   And "amara@example.org" owns credential "DHIS2 prod" shared with "Malawi HIV"
//   And "amara@example.org" owns credential "Personal sandbox" not shared with "Malawi HIV"
//   When I open the project's settings on the "Credentials" tab
//   Then I see "DHIS2 prod" with type, owner "amara@example.org" and its environments
//   And I do not see "Personal sandbox"
test('@S01', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  credential({
    name: 'DHIS2 prod',
    projects: [id],
    bodies: { production: { password: 'p' }, staging: { password: 's' } },
  });
  credential({ name: 'Personal sandbox' });
  await onCredentials(page, id);

  const dhis2 = row(page, 'DHIS2 prod');
  await expect(dhis2).toContainText(/raw/i);
  await expect(dhis2).toContainText(user(OTHER).email);
  await expectEnvironment(page, dhis2, 'production');
  await expectEnvironment(page, dhis2, 'staging');
  await expect(page.getByText('Personal sandbox')).toHaveCount(0);
});

// @S02
// Scenario: Members see the OAuth clients the project can use
//   Given OAuth client "Google" is shared with "Malawi HIV"
//   And OAuth client "Salesforce" is global
//   And OAuth client "Other" is shared only with another project
//   When I open the "Credentials" tab of "Malawi HIV"
//   Then I see "Google" and "Salesforce"
//   And I do not see "Other"
test('@S02', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  const elsewhere = givenProject('owner', {}, 'Kenya TB');
  oauthClient({ name: 'Google', projects: [id] });
  oauthClient({ name: 'Salesforce', global: true });
  oauthClient({ name: 'Other', projects: [elsewhere] });
  await onCredentials(page, id);

  await expect(row(page, 'Google')).toBeVisible();
  await expect(row(page, 'Salesforce')).toBeVisible();
  await expect(row(page, 'Other')).toHaveCount(0);
});

// @S03
// Scenario: Members see only this project's keychains
//   Given project "Malawi HIV" has keychain "By district" with path "$.organization.id"
//   And another project I belong to has keychain "Other keychain"
//   When I open the "Credentials" tab of "Malawi HIV"
//   Then I see "By district" and "$.organization.id"
//   And I do not see "Other keychain"
test('@S03', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  const elsewhere = givenProject('viewer', {}, 'Kenya TB');
  keychain(id, { name: 'By district', path: '$.organization.id' });
  keychain(elsewhere, { name: 'Other keychain' });
  await onCredentials(page, id);

  await expect(row(page, 'By district')).toContainText('$.organization.id');
  await expect(page.getByText('Other keychain')).toHaveCount(0);
});

// When I start a raw JSON credential from the tab — returns its form
const startRaw = (page: Page) => startCredential(page, 'Raw JSON');

// When I name the open credential form <name>, give it a body and save
async function completeCredential(f: Locator, name: string) {
  await field(f, 'Credential Name').fill(name);
  await enterBody(f, '{"apiKey": "abc123"}');
  await saveCredential(f);
}

// @S04
// Scenario: Editor creates a credential that is shared with this project
//   Given I am an editor on project "Malawi HIV"
//   When I choose "Add new" then "Credential"
//   Then the credential form opens with "Malawi HIV" already selected under projects access
//   When I complete and save the credential "HTTP API"
//   Then I am back on the "Credentials" tab of "Malawi HIV"
//   And "HTTP API" is listed
test('@S04', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  removesCreated(['HTTP API']);
  await onCredentials(page, id);

  const form = await startRaw(page);
  await expect(projectChip(form, PROJECT)).toBeVisible();
  await completeCredential(form, 'HTTP API');

  await expectBackOnTab(page, id);
  await expect(row(page, 'HTTP API')).toBeVisible();
  expect(credentialNamed(ME, 'HTTP API').projects).toEqual([PROJECT]);
});

// @S05 @variant:sandbox
// Scenario: A credential created in a sandbox is shared with the sandbox only
//   Given I am an admin on project "root" and its nested sandbox "sandbox-project"
//   When I choose "Add new" then "Credential" on the "Credentials" tab of "sandbox-project"
//   Then "sandbox-project" is selected under projects access
//   And neither "root" nor the intermediate project is selected
test('@S05', PASSING_BOTH, async ({ page }) => {
  const w = given(
    {
      name: 'root',
      members: { [ME]: 'admin', [OTHER]: 'owner' },
      sandboxes: [
        {
          name: 'intermediate',
          members: { [ME]: 'admin' },
          sandboxes: [{ name: 'sandbox-project', members: { [ME]: 'admin' } }],
        },
      ],
    },
    OTHER
  );
  await onCredentials(page, w.id('sandbox-project'));

  const form = await startRaw(page);
  await expect(projectChip(form, 'sandbox-project')).toBeVisible();
  await expect(projectChip(form, 'root')).toHaveCount(0);
  await expect(projectChip(form, 'intermediate')).toHaveCount(0);
});

// @S06 @variant:support-user
// Scenario: Support user creates a credential in a project that allows support access
//   Given I am a support user with no membership on "Malawi HIV"
//   And "Malawi HIV" allows support access
//   When I choose "Add new" then "Credential", complete and save it
//   Then I am back on the "Credentials" tab and the credential is listed
test('@S06', PASSING_BOTH, async ({ page }) => {
  cleanups.push(makeSupportUser(ME));
  const id = givenProject(null, { allowSupportAccess: true });
  removesCreated(['Support fix']);
  await onCredentials(page, id);

  await completeCredential(await startRaw(page), 'Support fix');

  await expectBackOnTab(page, id);
  await expect(row(page, 'Support fix')).toBeVisible();
  expect(credentialNamed(ME, 'Support fix').projects).toEqual([PROJECT]);
});

// @S07
// Scenario: Viewer cannot create anything on this tab
//   Given I am a viewer on project "Malawi HIV"
//   When I open "Add new" on the "Credentials" tab
//   Then "Credential", "Keychain" and "OAuth client" are disabled
//   When I send "show_modal" with target "new_credential" anyway
//   Then I see "You are not authorized to perform this action"
//   And no credential form is open
test('@S07', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  const lv = await onCredentials(page, id);

  for (const item of ['Credential', 'Keychain', 'OAuth client'] as const)
    expect(
      await optionDisabled(await addNewOption(page, item)),
      `${item} is disabled`
    ).toBe(true);
  await page.keyboard.press('Escape');

  await sendNewCredentialRequest(page, lv, 'new_credential');

  await expectRefusal(page, lv, NOT_AUTHORIZED);
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(credentialsNamed(ME, 'Crafted')).toHaveLength(0);
});

// @S08
// Scenario: Editor sees the keychain option disabled
//   Given I am an editor on project "Malawi HIV"
//   When I open "Add new" on the "Credentials" tab
//   Then "Credential" and "OAuth client" are enabled
//   And "Keychain" is disabled
test('@S08', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  await onCredentials(page, id);

  expect(await optionDisabled(await addNewOption(page, 'Credential'))).toBe(
    false
  );
  expect(await optionDisabled(await addNewOption(page, 'OAuth client'))).toBe(
    false
  );
  expect(await optionDisabled(await addNewOption(page, 'Keychain'))).toBe(true);
});

// When I fill in a new OAuth client's required fields — returns its form
async function fillOauthClient(page: Page, name: string) {
  await (await addNewOption(page, 'OAuth client')).click();
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

// @S09
// Scenario: Editor creates an OAuth client shared with this project
//   Given I am an editor on project "Malawi HIV"
//   When I choose "Add new" then "OAuth client"
//   Then the OAuth client form opens with "Malawi HIV" already selected under projects access
//   When I complete and save it
//   Then I am back on the "Credentials" tab with "Oauth client created successfully"
test('@S09', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  removesCreated([], ['Sheets app']);
  await onCredentials(page, id);

  const form = await fillOauthClient(page, 'Sheets app');
  await expect(projectChip(form, PROJECT)).toBeVisible();
  // the form checks itself as I type; the button is off until it is valid
  await expect(submitButton(form, 'Add OAuth Client')).toBeEnabled();
  await submit(form, 'Add OAuth Client');

  await expect(toast(page, 'Oauth client created successfully')).toBeVisible();
  await expectBackOnTab(page, id);
  await expect(row(page, 'Sheets app')).toBeVisible();
  expect(oauthClientsNamed(ME, 'Sheets app')[0].projects).toEqual([PROJECT]);
});

// @S10
// Scenario: New OAuth credentials are offered the project's OAuth clients
//   Given OAuth client "Google" owned by someone else is shared with "Malawi HIV"
//   And OAuth client "Mine only" is owned by me and not shared with "Malawi HIV"
//   When I choose "Add new" then "Credential" on the "Credentials" tab of "Malawi HIV"
//   Then the type picker offers "Google"
//   And it does not offer "Mine only"
test('@S10', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  oauthClient({ name: 'Google', projects: [id] });
  oauthClient({ name: 'Mine only' }, ME);
  await onCredentials(page, id);

  await (await addNewOption(page, 'Credential')).click();
  const picker = await dialog(page, 'Add a credential');

  await expect(typeOption(picker, 'Google')).toBeVisible();
  await expect(typeOption(picker, 'Mine only')).toHaveCount(0);
});

// @S11
// Scenario: Admin creates a keychain
//   Given I am an admin on project "Malawi HIV"
//   And credential "DHIS2 prod" is shared with "Malawi HIV"
//   When I choose "Add new" then "Keychain"
//   And I enter name "By district", JSONPath "$.user_id" and default credential "DHIS2 prod"
//   And I choose "Create"
//   Then I see "Keychain credential created successfully"
//   And "By district" is listed with me as its creator
// Fails on today's Lightning: the keychain is saved but this tab shows no message.
test('@S11', NEW_ONLY, async ({ page }) => {
  const id = givenProject('admin');
  credential({ name: 'DHIS2 prod', projects: [id] });
  await onCredentials(page, id);

  const form = await addKeychain(page);
  await fillKeychain(form, {
    name: 'By district',
    path: '$.user_id',
    defaultCredential: 'DHIS2 prod',
  });
  await keychainSaveButton(form).click();

  await expect(
    toast(page, 'Keychain credential created successfully')
  ).toBeVisible();
  await expect(row(page, 'By district')).toContainText(user(ME).email);
  expect(keychainsOf(id)).toEqual([
    expect.objectContaining({
      name: 'By district',
      path: '$.user_id',
      default_credential: 'DHIS2 prod',
      created_by: user(ME).email,
    }),
  ]);
});

// @S12
// Scenario: A keychain needs a name and a JSONPath starting with "$"
//   Given I am creating a keychain on "Malawi HIV"
//   When I submit it with an empty name and path
//   Then I see "can't be blank"
//   When I enter path "user_id"
//   Then I see "JSONPath must start with '$'"
//   And "Create" is disabled
test('@S12', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onCredentials(page, id);
  const form = await addKeychain(page);

  // Today "Create" stays disabled until the form is valid, so a blank name
  // is reached by clearing it
  await fillKeychain(form, { name: 'x', path: '$.x' });
  await fillKeychain(form, { name: '', path: '' });
  await submit(form, 'Create');
  await expect(fieldBlock(form, 'Name')).toContainText("can't be blank");

  await fillKeychain(form, { name: 'By district', path: 'user_id' });
  await checkKeychain(form);

  await expect(fieldBlock(form, 'JSONPath Expression')).toContainText(
    "JSONPath must start with '$'"
  );
  expect(keychainsOf(id)).toEqual([]);
});

// @S13
// Scenario: A keychain's default credential must be shared with the project
//   Given credential "DHIS2 prod" is shared with "Malawi HIV"
//   And credential "Elsewhere" is not
//   When I create a keychain on "Malawi HIV"
//   Then the default credential choices are "No default credential" and "DHIS2 prod"
//   When I submit it with the id of "Elsewhere" as default anyway
//   Then I see "must belong to the same project"
//   And no keychain is created
test('@S13', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  credential({ name: 'DHIS2 prod', projects: [id] });
  const elsewhere = credential({ name: 'Elsewhere' });
  await onCredentials(page, id);
  const crafted = await craftingDefaultCredential(page, elsewhere);

  const form = await addKeychain(page);
  const choices = (
    await defaultCredentialPicker(form).getByRole('option').allInnerTexts()
  ).map(c => c.trim());
  expect(choices).toEqual(['No default credential', 'DHIS2 prod']);

  await fillKeychain(form, { name: 'By district', path: '$.user_id' });
  await crafted(keychainSaveButton(form));

  await expect(form).toContainText('must belong to the same project');
  expect(keychainsOf(id)).toEqual([]);
});

// @S14
// Scenario: Two keychains in a project cannot share a name
//   Given "Malawi HIV" has keychain "By district"
//   When I create another keychain named "By district" on "Malawi HIV"
//   Then I see an error on the name
//   And only one "By district" exists
test('@S14', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  keychain(id, { name: 'By district' });
  await onCredentials(page, id);

  const form = await addKeychain(page);
  await fillKeychain(form, { name: 'By district', path: '$.user_id' });
  await keychainSaveButton(form).click();

  await expect(fieldBlock(form, 'Name')).toContainText(
    /unique|already|taken|exists/i
  );
  expect(keychainsOf(id).map(k => k.name)).toEqual(['By district']);
});

// @S15
// Scenario: Admin edits a keychain
//   Given "Malawi HIV" has keychain "Original Name" with path "$.org_id"
//   When I edit it to name "Updated Name" and path "$.updated_path" and choose "Save changes"
//   Then I see "Keychain credential updated successfully"
//   And the keychain is stored with the new name and path
// Fails on today's Lightning: the keychain is saved but this tab shows no message.
test('@S15', NEW_ONLY, async ({ page }) => {
  const id = givenProject('admin');
  keychain(id, { name: 'Original Name', path: '$.org_id' });
  await onCredentials(page, id);

  await rowAction(page, row(page, 'Original Name'), 'Edit');
  const form = keychainForm(page, /Edit Original Name/i);
  await fillKeychain(form, { name: 'Updated Name', path: '$.updated_path' });
  await keychainSaveButton(form).click();

  await expect(
    toast(page, 'Keychain credential updated successfully')
  ).toBeVisible();
  await expect(row(page, 'Updated Name')).toContainText('$.updated_path');
  expect(keychainsOf(id)).toEqual([
    expect.objectContaining({ name: 'Updated Name', path: '$.updated_path' }),
  ]);
});

// @S16
// Scenario: A forged keychain edit from a viewer is refused
//   Given I am a viewer on "Malawi HIV" with keychain "Protected"
//   When I send "edit_keychain_credential" for "Protected"
//   Then I see "You are not authorized to perform this action"
//   And no keychain form is open
test('@S16', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  const protectedId = keychain(id, { name: 'Protected' });
  const lv = await onCredentials(page, id);

  await sendKeychainEdit(page, lv, protectedId);

  await expectRefusal(page, lv, NOT_AUTHORIZED);
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(keychainsOf(id).map(k => k.name)).toEqual(['Protected']);
});

// @S17
// Scenario: Owner schedules a credential for deletion from project settings
//   Given I own credential "DHIS2 prod" shared with "Malawi HIV"
//   When I delete "DHIS2 prod" from the "Credentials" tab of "Malawi HIV" and confirm
//   Then I am back on the "Credentials" tab with "Credential scheduled for deletion"
//   And "DHIS2 prod" is no longer listed on this tab
//   And the flow "flow-credential-scheduled-deletion" has started for "DHIS2 prod"
test('@S17', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  credential({ name: 'DHIS2 prod', projects: [id] }, ME);
  await onCredentials(page, id);

  await rowAction(page, row(page, 'DHIS2 prod'), 'Delete');
  const d = await dialog(page, 'Delete credential');
  await d.getByRole('button', { name: 'Delete credential' }).click();

  await expect(toast(page, 'Credential scheduled for deletion')).toBeVisible();
  await expectBackOnTab(page, id);
  await expect(row(page, 'DHIS2 prod')).toHaveCount(0);
  expect(credentialNamed(ME, 'DHIS2 prod').scheduled_deletion).not.toBeNull();
  // The flow has started: the owner is told how to cancel
  await expect
    .poll(async () =>
      (await mailTo(page, ME)).some(m => m.text?.includes('DHIS2 prod'))
    )
    .toBe(true);
});

// @S18
// Scenario: Owner starts a credential transfer from project settings
//   Given I own credential "DHIS2 prod" shared with "Malawi HIV"
//   When I choose "Transfer" on "DHIS2 prod" on the "Credentials" tab
//   Then the transfer modal opens for "DHIS2 prod"
//   And submitting it returns me to the "Credentials" tab
//   And the flow "flow-credential-transfer" has started for "DHIS2 prod"
test('@S18', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  credential({ name: 'DHIS2 prod', projects: [id] }, ME);
  await onCredentials(page, id);

  await rowAction(page, row(page, 'DHIS2 prod'), 'Transfer');
  const d = await dialog(page, 'Transfer Credential Ownership');
  await receiverEmail(d).fill(user(OTHER).email);
  await receiverEmail(d).blur();
  await expect(submitButton(d, 'Transfer')).toBeEnabled();
  await submitButton(d, 'Transfer').click();

  await expectBackOnTab(page, id);
  expect(credentialNamed(ME, 'DHIS2 prod').transfer_status).toBe('pending');
  // The flow has started: the owner gets the confirmation link
  await expect
    .poll(async () =>
      (await mailTo(page, ME)).some(m => m.subject.includes('DHIS2 prod'))
    )
    .toBe(true);
});

// @S19
// Scenario: OAuth sign-in started on this tab returns to this tab
//   Given I am an editor on "Malawi HIV" and OAuth client "Google" is shared with it
//   When I start a new credential of type "Google" on the "Credentials" tab and sign in with the provider
//   Then the flow "flow-oauth-credential-authorize" has started
//   And the provider's answer is delivered to the credential form on this tab
test('@S19', PASSING_BOTH, async ({ page, context }) => {
  const provider = await standInOauth();
  cleanups.push(provider.close);
  const id = givenProject('editor');
  oauthClient({ name: 'Google', projects: [id], base: provider.base });
  await onCredentials(page, id);

  const form = await startCredential(page, 'Google');
  const popup = context.waitForEvent('page');
  await form.getByRole('button', { name: 'Sign in with Google' }).click();
  const signIn = await (await popup).waitForEvent('load');
  const state = new URL(signIn.url()).searchParams.get('state');
  expect(state, 'the flow has started').toBeTruthy();

  // The provider sends me back with a code, as it would after I sign in
  await page.request.get(
    `${new URL(page.url()).origin}/authenticate/callback?state=${state}&code=scenario-code`
  );

  // The answer reached this tab's form: it asked for the token and who I am
  await expect
    .poll(() => provider.requests.map(r => r.pathname))
    .toEqual(expect.arrayContaining(['/token', '/userinfo']));
  await expect(form).toContainText('Scenario Person');
  await expectBackOnTab(page, id);
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
    'shared-credential-index-component@S01 on project-settings',
    PASSING_BOTH,
    async ({ page }) => {
      const id = givenProject('viewer');
      credential({ name: 'DHIS2 prod', projects: [id] }, ME);
      await onCredentials(page, id);

      expect(await actionsOn(page, 'DHIS2 prod')).toEqual(
        expect.arrayContaining(['edit', 'delete', 'transfer'])
      );
    }
  );

  // @S02
  // Scenario: Another member's credential has no edit actions
  //   Given credential "DHIS2 prod" is owned by someone else and shared with project "Malawi HIV"
  //   When I open the project's credential list
  //   Then I see "DHIS2 prod"
  //   And I see no edit, delete or transfer actions for it
  test(
    'shared-credential-index-component@S02 on project-settings',
    PASSING_BOTH,
    async ({ page }) => {
      const id = givenProject('admin');
      credential({ name: 'DHIS2 prod', projects: [id] });
      await onCredentials(page, id);

      await expect(row(page, 'DHIS2 prod')).toBeVisible();
      const actions = await actionsOn(page, 'DHIS2 prod');
      for (const a of ['edit', 'delete', 'transfer'])
        expect(actions).not.toContain(a);
    }
  );

  // @S03
  // Scenario: Editor cannot manage keychains
  //   Given I am an editor on project "Malawi HIV" with keychain "By district"
  //   When I open the project's credential list
  //   Then I see "By district"
  //   And I see no edit or delete actions for it
  test(
    'shared-credential-index-component@S03 on project-settings',
    PASSING_BOTH,
    async ({ page }) => {
      const id = givenProject('editor');
      keychain(id, { name: 'By district' });
      await onCredentials(page, id);

      await expect(row(page, 'By district')).toBeVisible();
      const actions = await actionsOn(page, 'By district');
      expect(actions).not.toContain('edit');
      expect(actions).not.toContain('delete');
    }
  );

  // @S04
  // Scenario: Admin deletes a keychain
  //   Given I am an admin on project "Malawi HIV" with keychain "By district"
  //   When I delete keychain "By district" and confirm
  //   Then I see "Keychain credential deleted"
  //   And "By district" is no longer listed
  test(
    'shared-credential-index-component@S04 on project-settings',
    PASSING_BOTH,
    async ({ page }) => {
      const id = givenProject('admin');
      keychain(id, { name: 'By district' });
      await onCredentials(page, id);

      await rowAction(page, row(page, 'By district'), 'Delete');
      const d = await dialog(page, 'Delete Keychain Credential');
      await d.getByRole('button', { name: 'Delete', exact: true }).click();

      await expect(toast(page, 'Keychain credential deleted')).toBeVisible();
      await expect(row(page, 'By district')).toHaveCount(0);
      expect(keychainsOf(id)).toEqual([]);
    }
  );

  // S05 (cancel a scheduled deletion) can't be reached on this tab:
  // scheduling a deletion takes the credential out of every project, so it
  // is no longer listed here (S17). It runs on credentials-index.
  test(
    'shared-credential-index-component@S05 on project-settings',
    PENDING,
    () => {
      test.skip(true, 'a scheduled credential is not listed on this tab');
    }
  );

  // @S06
  // Scenario: A forged action from a non-owner is refused
  //   Given credential "DHIS2 prod" is owned by someone else
  //   When I send "edit_credential" for "DHIS2 prod"
  //   Then I see "You are not authorized to perform this action"
  // Checked by its effect too: no form opens, the credential is unchanged
  // and its secret never reaches this page
  test(
    'shared-credential-index-component@S06 on project-settings',
    PASSING_BOTH,
    async ({ page }) => {
      const id = givenProject('admin');
      const theirs = credential({
        name: 'DHIS2 prod',
        projects: [id],
        bodies: { main: { password: 'their-secret' } },
      });
      const lv = await onCredentials(page, id);

      await sendCredentialEdit(page, lv, theirs);

      await expectRefusal(page, lv, NOT_AUTHORIZED);
      await expect(page.getByRole('dialog')).toHaveCount(0);
      expect(credentialNamed(OTHER, 'DHIS2 prod').id).toBe(theirs);
      expect(await page.content()).not.toContain('their-secret');
    }
  );
});
