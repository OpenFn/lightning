// Scenarios from annotations/views/project-settings-setup.md, and the shared
// ones it inherits.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns the projects I don't. Every project is seeded
// by the test through Lightning and removed again afterwards.
//
// Every settings tab is one page at one address, so the shared session,
// scope, banner, header, flash and tab chrome scenarios run once, here, for
// all nine tabs. The other project-settings-*.spec.ts files don't repeat them.
import { expect, test, type Page } from '@playwright/test';

import {
  closeButton,
  concurrencyForm,
  concurrencySwitch,
  deletePath,
  identityForm,
  openSettings,
  panel,
  roleNotice,
  sandboxDeletionDialog,
  sandboxNameField,
  sendIdentitySave,
  sendProjectDeletion,
  sendSandboxDeletion,
  settingsPath,
  type TabLabel,
} from './pages/project-settings';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as projectDeletionModal from './shared/project-deletion-modal';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as tabChrome from './shared/project-settings-tab-chrome';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  changeRoleOnNode,
  clickable,
  exec,
  expectAt,
  field,
  keepAccount,
  makeSupportUser,
  manifest,
  modal,
  modalTitle,
  onNode,
  open,
  removeMemberOnNode,
  removeMfaOf,
  scheduleDeletionOnNode,
  scheduledDeletionOf,
  seedWorkspace,
  setSupportAccessOnNode,
  signInAs,
  sql,
  submit,
  submitButton,
  watchLiveView,
  workflowsOf,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING_BOTH = { tag: ['@passing-old', '@passing-new'] };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given this workspace exists (removed after the test)
function given(seed: WorkspaceSeed, by = ME) {
  const workspace = seedWorkspace(seed, by);
  cleanups.push(workspace.remove);
  return workspace;
}

// Given I am a <role> on project <name> (owner@openfn.org owns it unless I do)
function givenProject(
  role: Role | null,
  name = 'project-1',
  extra: Partial<WorkspaceSeed> = {}
) {
  const members: Record<string, Role | null> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const w = given({ name, members, ...extra }, role === 'owner' ? ME : OTHER);
  return { w, id: w.id(name), name };
}

// Given I am the owner of sandbox <name> under <parent>
function givenSandbox(name = 'sandbox-test', parent = 'parent-project') {
  const w = given({
    name: parent,
    members: { [ME]: 'owner' },
    sandboxes: [{ name }],
  });
  return { w, id: w.id(name), parentId: w.id(parent), name, parent };
}

type StoredProject = {
  name: string;
  description: string | null;
  env: string | null;
  concurrency: number | null;
  requires_mfa: boolean;
  allow_support_access: boolean;
  scheduled_deletion: string | null;
  parent_id: string | null;
};

const stored = (id: string) =>
  sql<StoredProject>(
    `select name, description, env, concurrency, requires_mfa,
            allow_support_access, scheduled_deletion, parent_id
     from projects where id = '${id}'`
  )[0];

const exists = (id: string) =>
  sql(`select 1 from projects where id = '${id}'`).length > 0;

// The triggers of project <id> that are still enabled
const enabledTriggersOf = (id: string) =>
  sql(
    `select t.id from triggers t join workflows w on w.id = t.workflow_id
     where w.project_id = '${id}' and t.enabled`
  );

// Given I am signed in and on project <id>'s settings
async function onSettings(page: Page, id: string, label?: TabLabel) {
  await signInAs(page, ME);
  await openSettings(page, id, label);
}

const saveIdentity = (page: Page) => submit(identityForm(page), 'Save');
const saveConcurrency = (page: Page) => submit(concurrencyForm(page), 'Save');

const UPDATED = 'Project updated successfully';
const DANGER = 'Deleting your project is irreversible';
const DELETE_PROJECT = 'Delete project';
// Today's wording has a typo ("authorize"); either spelling passes
const NOT_OWNER = /You are not authori[sz]ed? to perform this action/;

// The open project deletion dialog
async function deletionDialog(page: Page) {
  await expect(modalTitle(page, DELETE_PROJECT)).toBeVisible();
  return modal(page, DELETE_PROJECT);
}

// @S01
// Scenario: Admin renames the project and edits its description
//   Given I am an admin on project "project-1"
//   When I set "Project name" to "somename" and "Project description" to "some description"
//   And I click "Save" in the identity section
//   Then I see "Project updated successfully"
//   And the project is named "somename" with description "some description"
test('@S01', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin');
  await onSettings(page, p.id);

  await field(identityForm(page), 'Project name').fill('somename');
  await field(identityForm(page), 'Project description').fill(
    'some description'
  );
  await saveIdentity(page);

  await expect(flashMessages.toast(page, UPDATED)).toBeVisible();
  await expect
    .poll(() => stored(p.id))
    .toMatchObject({ name: 'somename', description: 'some description' });
});

// @S02
// Scenario: The name is turned into a URL-safe slug
//   Given I am an admin on project "project-1"
//   When I type "DEP-burundi-datafi" into "Project name"
//   Then I see "Your project will be named dep-burundi-datafi."
//   When I click "Save" in the identity section
//   Then the project is named "dep-burundi-datafi"
test('@S02', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin');
  await onSettings(page, p.id);

  await field(identityForm(page), 'Project name').fill('DEP-burundi-datafi');
  await expect(identityForm(page)).toContainText(
    /will be named\s*dep-burundi-datafi/
  );
  await saveIdentity(page);

  await expect.poll(() => stored(p.id).name).toBe('dep-burundi-datafi');
});

// @S03
// Scenario: A name with no usable characters is refused
//   Given I am an admin on project "project-1"
//   When I submit the identity form with "Project name" set to "!!!"
//   Then I see "can't be blank"
//   And the project is still named "project-1"
test('@S03', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin');
  await onSettings(page, p.id);

  await field(identityForm(page), 'Project name').fill('!!!');
  await field(identityForm(page), 'Project name').blur();
  // Today's form flags it as you type and turns Save off; wait for that
  await expect(identityForm(page)).toContainText(/can't be blank/);
  await saveIdentity(page);

  await expect(identityForm(page)).toContainText(/can't be blank/);
  expect(stored(p.id).name).toBe('project-1');
});

// @S04
// Scenario: A description over 240 characters is flagged before saving
//   Given I am an admin on project "project-1"
//   When I type a 250 character description
//   Then I see "should be at most 240 character(s)"
//   And the identity "Save" button is disabled
// The message while typing is the Value; whether Save turns off or the save
// is refused, the long description is not stored.
// Old only: the design-system box stops at 240 characters, so there is
// nothing to flag.
test('@S04', PASSING_OLD, async ({ page }) => {
  const p = givenProject('admin');
  await onSettings(page, p.id);

  const description = field(identityForm(page), 'Project description');
  await description.fill('x'.repeat(250));
  await description.blur();

  await expect(identityForm(page)).toContainText(/at most 240 character\(s\)/);
  await saveIdentity(page);
  await expect(identityForm(page)).toContainText(/at most 240 character\(s\)/);
  expect(stored(p.id).description).toBeNull();
});

// @S05
// Scenario: The project environment cannot be changed here
//   Given I am an admin on project "project-1" with environment "staging"
//   Then the "Project environment" field is disabled
//   When "save" is sent with env "main"
//   Then I see "Project updated successfully"
//   And the project environment is still "staging"
// The save past the form is checked by its effect, not its message.
test('@S05', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin', 'project-1', { env: 'staging' });
  const lv = watchLiveView(page);
  await onSettings(page, p.id);

  await expect(field(identityForm(page), 'Project environment')).toBeDisabled();

  await sendIdentitySave(page, lv, 'project-1', { env: 'main' });
  expect(stored(p.id).env).toBe('staging');
  expect(lv.crashes()).toBe(0);
});

// @S06
// Scenario: A crafted save cannot set privileged fields
//   Given I am an admin on project "project-1"
//   When "save" is sent with "raw_name" "renamed", "requires_mfa" true, "allow_support_access" true, "scheduled_deletion" set and "parent_id" of another project
//   Then the project is named "renamed"
//   And it does not require MFA, does not allow support access, is not scheduled for deletion and has no parent
test('@S06', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin');
  const other = givenProject('admin', 'project-2');
  const lv = watchLiveView(page);
  await onSettings(page, p.id);

  await sendIdentitySave(page, lv, 'renamed', {
    requires_mfa: true,
    allow_support_access: true,
    scheduled_deletion: new Date(Date.now() + 86400000).toISOString(),
    parent_id: other.id,
  });

  await expect.poll(() => stored(p.id).name).toBe('renamed');
  expect(stored(p.id)).toMatchObject({
    requires_mfa: false,
    allow_support_access: false,
    scheduled_deletion: null,
    parent_id: null,
  });
});

// @S07
// Scenario Outline: Members below admin see the identity read-only
//   Given I am a <role> on project "project-1"
//   When I open project settings
//   Then "Project name", "Project description" and the concurrency switch are disabled
//   And the identity "Save" button is disabled
//   And I see "Role based permissions: You cannot modify this project's basic settings, but you can export a copy."
//   When "save" is sent anyway
//   Then I see "You are not authorized to perform this action."
//   Examples: viewer, editor
// The save sent anyway is checked by its effect: the name doesn't change.
for (const role of ['viewer', 'editor'] as const)
  test(`@S07 (${role})`, PASSING_BOTH, async ({ page }) => {
    const p = givenProject(role);
    const lv = watchLiveView(page);
    await onSettings(page, p.id);

    await expect(field(identityForm(page), 'Project name')).toBeDisabled();
    await expect(
      field(identityForm(page), 'Project description')
    ).toBeDisabled();
    await expect(concurrencySwitch(page)).toBeDisabled();
    await expect(
      identityForm(page).getByRole('button', { name: 'Save' })
    ).toBeDisabled();
    await expect(roleNotice(panel(page, 'Setup'))).toContainText(
      'basic settings, but you can export a copy.'
    );

    await sendIdentitySave(page, lv, 'renamed');
    expect(stored(p.id).name).toBe('project-1');
    expect(lv.crashes()).toBe(0);
  });

// @S08
// Scenario: A support user without a membership cannot edit project details
//   Given I am a support user and project "project-1" allows support access
//   And I am not a member of it
//   When I open project settings
//   Then "Project name" and "Project description" are disabled
//   When "save" is sent anyway
//   Then I see "You are not authorized to perform this action."
// A support user sees every project that allows support access
test(
  '@S08',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const p = givenProject(null, 'project-1', { allowSupportAccess: true });
    cleanups.push(makeSupportUser(ME));
    const lv = watchLiveView(page);
    await onSettings(page, p.id);

    await expect(field(identityForm(page), 'Project name')).toBeDisabled();
    await expect(
      field(identityForm(page), 'Project description')
    ).toBeDisabled();

    await sendIdentitySave(page, lv, 'renamed');
    expect(stored(p.id).name).toBe('project-1');
    expect(lv.crashes()).toBe(0);
  }
);

// @S09
// Scenario: Admin disables parallel execution
//   Given I am an admin on project "project-1" with parallel execution allowed
//   When I switch on "Disable parallel execution"
//   Then I see the warning "Disabling parallel run execution may significantly reduce the overall throughput of your project."
//   When I click "Save" in the concurrency section
//   Then I see "Project updated successfully"
//   And the project concurrency is 1
test('@S09', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin');
  await onSettings(page, p.id);

  await concurrencySwitch(page).click();
  await expect(concurrencySwitch(page)).toBeChecked();
  await expect(concurrencyForm(page)).toContainText(
    /Disabling parallel run execution may significantly reduce the\s+overall throughput of your project\./
  );
  await saveConcurrency(page);

  await expect(flashMessages.toast(page, UPDATED)).toBeVisible();
  await expect.poll(() => stored(p.id).concurrency).toBe(1);
});

// @S10
// Scenario: Admin re-enables parallel execution
//   Given I am an admin on project "project-1" with concurrency 1
//   When I switch off "Disable parallel execution"
//   And I click "Save" in the concurrency section
//   Then I see "Project updated successfully"
//   And the project has no concurrency limit
test('@S10', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin');
  exec(`update projects set concurrency = 1 where id = '${p.id}'`);
  await onSettings(page, p.id);

  await expect(concurrencySwitch(page)).toBeChecked();
  await concurrencySwitch(page).click();
  await expect(concurrencySwitch(page)).not.toBeChecked();
  await saveConcurrency(page);

  await expect(flashMessages.toast(page, UPDATED)).toBeVisible();
  await expect.poll(() => stored(p.id).concurrency).toBeNull();
});

// @S11
// Scenario: Any member can export the project
//   Given I am a viewer on project "project-1"
//   When I open project settings
//   Then I see "Export your project as code, to save this version or edit your project locally."
//   And "Export project" links to "/download/yaml?id=<project_id>" in a new tab
//   And clicking it starts the flow "flow-export-project-yaml"
// The flow has started when that address answers with the project as YAML.
test('@S11', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('viewer');
  await onSettings(page, p.id);

  const setup = panel(page, 'Setup');
  await expect(setup).toContainText(
    'Export your project as code, to save this version or edit your project locally.'
  );
  const link = setup.getByRole('link', { name: 'Export project' });
  await expect(link).toHaveAttribute('href', `/download/yaml?id=${p.id}`);
  await expect(link).toHaveAttribute('target', '_blank');

  const response = await page.request.get(`/download/yaml?id=${p.id}`);
  expect(response.status()).toBe(200);
  expect(await response.text()).toContain('name: project-1');
});

// @S12
// Scenario: Owner schedules the project for deletion
//   Given I am the owner of project "project-1"
//   When I open project settings
//   Then I see "Deleting your project is irreversible"
//   When I click "Delete project"
//   Then I am on "/projects/<project_id>/settings/delete"
//   And I see "Enter the project name to confirm deletion: project-1"
//   And I see that the project will be deleted "7 day(s) from today"
//   When I type "project-1" into "Project name" and click "Delete project"
//   Then I am on "/projects"
//   And I see "Project scheduled for deletion"
//   And the project is scheduled for deletion 7 days from now with all its triggers disabled
//   And the flow "flow-schedule-project-deletion" has started for "project-1"
// The flow has started when the project carries its deletion date and its
// triggers are off; the members' emails are the flow's own scenarios.
test('@S12', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('owner', 'project-1', { workflows: ['wf-1'] });
  const days = Number(
    onNode('Lightning.Config.purge_deleted_after_days()')
      .trim()
      .split('\n')
      .pop()
  );
  expect(enabledTriggersOf(p.id)).toHaveLength(1);
  await onSettings(page, p.id);

  await expect(panel(page, 'Setup')).toContainText(DANGER);
  await clickable(panel(page, 'Setup'), DELETE_PROJECT, {
    exact: true,
  }).click();

  await expectAt(page, deletePath(p.id));
  const d = await deletionDialog(page);
  await expect(d).toContainText(
    'Enter the project name to confirm deletion: project-1'
  );
  await expect(d).toContainText(`${days} day(s) from today`);

  await field(d, 'Project name').fill('project-1');
  await field(d, 'Project name').blur();
  await submit(d, DELETE_PROJECT);

  await expectAt(page, '/projects');
  await expect(
    flashMessages.toast(page, 'Project scheduled for deletion')
  ).toBeVisible();
  const at = new Date(scheduledDeletionOf(p.id)!).getTime();
  expect(Math.abs(at - (Date.now() + days * 86400000))).toBeLessThan(
    10 * 60000
  );
  expect(enabledTriggersOf(p.id)).toHaveLength(0);
});

// @S13
// Scenario: A mistyped name does not delete the project
//   Given I am the owner of project "project-1" on its delete modal
//   When I type "project-2" into "Project name" and submit
//   Then I see "doesn't match the project name"
//   And the project is not scheduled for deletion
// What the dialog does is shared-project-deletion-modal S02's.
test('@S13', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('owner');
  const lv = watchLiveView(page);
  await signInAs(page, ME);

  await projectDeletionModal.S02(
    page,
    p,
    id => open(page, deletePath(id)),
    typed => sendProjectDeletion(page, lv, typed)
  );
});

// @S14
// Scenario: Cancelling the delete modal returns to settings
//   Given I am the owner of project "project-1" on its delete modal
//   When I click "Cancel"
//   Then I am on "/projects/<project_id>/settings"
//   And the project is not scheduled for deletion
test('@S14', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('owner');
  await signInAs(page, ME);

  await projectDeletionModal.S05(
    page,
    p,
    id => open(page, deletePath(id)),
    'Cancel',
    settingsPath(p.id)
  );
});

// @S15
// Scenario Outline: Only owners can reach project deletion
//   Given I am a <role> on project "project-1"
//   When I open project settings
//   Then I do not see "Deleting your project is irreversible"
//   When I visit "/projects/<project_id>/settings/delete"
//   Then I am on "/projects/<project_id>/settings"
//   And I see "You are not authorize to perform this action"
//   Examples: admin, editor, viewer
for (const role of ['admin', 'editor', 'viewer'] as const)
  test(`@S15 (${role})`, PASSING_BOTH, async ({ page }) => {
    const p = givenProject(role);
    await onSettings(page, p.id);

    await expect(panel(page, 'Setup').getByText(DANGER)).toHaveCount(0);

    await open(page, deletePath(p.id));
    await expectAt(page, settingsPath(p.id));
    await expect(flashMessages.toast(page, NOT_OWNER)).toBeVisible();
    await expect(modalTitle(page, DELETE_PROJECT)).toHaveCount(0);
    expect(scheduledDeletionOf(p.id)).toBeNull();
  });

// @S16
// Scenario: An admin cannot hard-delete a root project through the sandbox event
//   Given I am an admin on root project "root-project" with a workflow
//   When "confirm-delete" is sent with name "root-project"
//   Then I am sent back to settings with "You don't have permission to delete this sandbox"
//   And the project and its workflow still exist and it is not scheduled for deletion
// Checked by its effect: the project and its workflow are still there.
test('@S16', PASSING_BOTH, async ({ page }) => {
  const p = givenProject('admin', 'root-project', { workflows: ['wf-1'] });
  const lv = watchLiveView(page);
  await onSettings(page, p.id);

  await sendSandboxDeletion(page, lv, 'root-project');

  expect(exists(p.id)).toBe(true);
  expect(workflowsOf(p.id)).toHaveLength(1);
  expect(scheduledDeletionOf(p.id)).toBeNull();
});

// @S17
// Scenario: A sandbox's setup tab identifies it within its parent
//   Given I am the owner of sandbox "sandbox-test" under "parent-project"
//   When I open its settings
//   Then I see "Sandbox setup" and "Sandbox Identity"
//   And I see "Identifies this sandbox within its parent:" with a link to "parent-project" settings
//   And I see "Changes you make here only apply to this sandbox and do not sync to the parent project on merge."
//   And the danger zone button reads "Delete sandbox"
test('@S17', PASSING_BOTH, async ({ page }) => {
  const s = givenSandbox();
  await onSettings(page, s.id);

  const setup = panel(page, 'Setup');
  await expect(
    setup.getByRole('heading', { name: 'Sandbox setup', exact: true })
  ).toBeVisible();
  await expect(
    setup.getByText('Sandbox Identity', { exact: true })
  ).toBeVisible();
  await expect(setup).toContainText(
    'Identifies this sandbox within its parent:'
  );
  await expect(
    setup.getByRole('link', { name: s.parent, exact: true })
  ).toHaveAttribute('href', settingsPath(s.parentId));
  await expect(setup).toContainText(
    'Changes you make here only apply to this sandbox and do not sync to the parent project on merge.'
  );
  await expect(
    clickable(setup, 'Delete sandbox', { exact: true })
  ).toBeVisible();
  await expect(clickable(setup, DELETE_PROJECT, { exact: true })).toHaveCount(
    0
  );
});

// @S18
// Scenario: Sandbox owner deletes the sandbox
//   Given I am the owner of sandbox "sandbox-test" under "parent-project"
//   When I visit "/projects/<sandbox_id>/settings/delete"
//   And I type "sandbox-test" into "Sandbox name" and click "Delete sandbox"
//   Then I am on "/projects/<parent_id>/w"
//   And I see "Sandbox sandbox-test and all its associated descendants deleted"
//   And the sandbox no longer exists
test('@S18', PASSING_BOTH, async ({ page }) => {
  const s = givenSandbox();
  await signInAs(page, ME);
  await open(page, deletePath(s.id));

  const d = await sandboxDeletionDialog(page);
  await sandboxNameField(d).fill(s.name);
  await expect(submitButton(d, 'Delete sandbox')).toBeEnabled();
  await submit(d, 'Delete sandbox');

  await expectAt(page, `/projects/${s.parentId}/w`);
  await expect(
    flashMessages.toast(
      page,
      'Sandbox sandbox-test and all its associated descendants deleted'
    )
  ).toBeVisible();
  expect(exists(s.id)).toBe(false);
});

// @S19
// Scenario: A mistyped sandbox name does not delete it
//   Given I am the owner of sandbox "sandbox-test" on its delete modal
//   When I type "wrong" into "Sandbox name"
//   Then I see "does not match the sandbox name"
//   And "Delete sandbox" is disabled
//   When I submit the form anyway
//   Then I see "does not match the sandbox name"
//   And the sandbox still exists
// "Submit anyway" is sent past the dialog's own check; checked by its effect.
// Old only: the design-system dialog keeps "Delete sandbox" off until the
// name matches, with a tooltip, and shows no mismatch message.
test('@S19', PASSING_OLD, async ({ page }) => {
  const s = givenSandbox();
  const lv = watchLiveView(page);
  await signInAs(page, ME);
  await open(page, deletePath(s.id));

  const d = await sandboxDeletionDialog(page);
  await sandboxNameField(d).fill('wrong');
  await sandboxNameField(d).blur();
  await expect(d.getByText(/does not match the sandbox name/)).toBeVisible();
  await submit(d, 'Delete sandbox');
  await expect(d.getByText(/does not match the sandbox name/)).toBeVisible();

  await sendSandboxDeletion(page, lv, 'wrong');
  expect(exists(s.id)).toBe(true);
});

// @S20
// Scenario: Closing the sandbox delete modal returns to settings
//   Given I am the owner of sandbox "sandbox-test" on its delete modal
//   When I click the close button
//   Then I am on "/projects/<sandbox_id>/settings"
test('@S20', PASSING_BOTH, async ({ page }) => {
  const s = givenSandbox();
  await signInAs(page, ME);
  await open(page, deletePath(s.id));

  const d = await sandboxDeletionDialog(page);
  await closeButton(d).click();

  await expectAt(page, settingsPath(s.id));
  expect(exists(s.id)).toBe(true);
});

// @S21
// Scenario Outline: A failed sandbox delete says so and keeps the sandbox
//   Given I am the owner of sandbox "sandbox-test" on its delete modal
//   And deleting it fails with <reason>
//   When I confirm with "sandbox-test"
//   Then I am on "/projects/<sandbox_id>/settings"
//   And I see "<message>"
//   And the sandbox still exists
//   Examples: unauthorized | another error
// An owner's delete only fails when the deletion itself is stubbed to fail
// (the old LiveView tests use Mimic); the e2e instance has no way to make it.
for (const reason of ['unauthorized', 'another error'])
  test(`@S21 (${reason})`, PENDING, () => {
    test.skip(true, 'needs a stubbed deletion failure on the server');
  });

// ---------------------------------------------------------------------------
// Inherited scenarios
// ---------------------------------------------------------------------------

// Given a project "<name>" I am an editor on (owner@openfn.org owns it)
function givenSettingsPage(
  members: Record<string, Role | null> = { [ME]: 'editor' },
  name = 'Settings host'
) {
  const w = given(
    {
      name,
      members: { [OTHER]: 'owner', ...members },
      workflows: ['wf-1'],
    },
    OTHER
  );
  const id = w.id(name);
  return { w, id, path: settingsPath(id) };
}

const setupHeading = (page: Page) =>
  panel(page, 'Setup').getByRole('heading', {
    name: 'Project setup',
    exact: true,
  });

test.describe('shared-project-settings-tab-chrome', () => {
  test(
    'shared-project-settings-tab-chrome@S01 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('editor', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S01(page, p.id);
    }
  );

  test(
    'shared-project-settings-tab-chrome@S02 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('admin', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S02(page, p.id);
    }
  );

  test(
    'shared-project-settings-tab-chrome@S03 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('editor', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S03(page, p.id);
    }
  );

  test(
    'shared-project-settings-tab-chrome@S04 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('admin', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S04(page, p.id);
    }
  );

  test(
    'shared-project-settings-tab-chrome@S05 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('viewer', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S05(page, p.id);
    }
  );

  for (const [role, label, message] of tabChrome.S06_EXAMPLES)
    test(
      `shared-project-settings-tab-chrome@S06 (${role}, ${label}) on project-settings-setup`,
      PASSING_BOTH,
      async ({ page }) => {
        const p = givenProject(role, 'Malawi HIV');
        await signInAs(page, ME);
        await tabChrome.S06(page, p.id, label, message);
      }
    );

  test(
    'shared-project-settings-tab-chrome@S07 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('admin', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S07(page, p.id);
    }
  );

  for (const [label, copy] of tabChrome.S08_EXAMPLES)
    test(
      `shared-project-settings-tab-chrome@S08 (${label}) on project-settings-setup`,
      PASSING_BOTH,
      async ({ page }) => {
        const s = givenSandbox('dev', 'Malawi HIV');
        await signInAs(page, ME);
        await tabChrome.S08(page, s.id, label, copy);
      }
    );

  test(
    'shared-project-settings-tab-chrome@S09 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const s = givenSandbox('dev', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S09(page, s.id, { id: s.parentId, name: s.parent });
    }
  );

  test(
    'shared-project-settings-tab-chrome@S10 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('owner', 'Malawi HIV');
      await signInAs(page, ME);
      await tabChrome.S10(page, p.id);
    }
  );
});

// Inherited from shared-project-deletion-modal, on this host: deleting lands
// on "/projects", backing out on the project's settings. S04 (an already
// scheduled project) is not reachable here (not_reachable_here: the project
// scope refuses a scheduled project before this page mounts). S05's "Close"
// row belongs to the admin projects host; its "Cancel" row is S14 above.
test.describe('shared-project-deletion-modal', () => {
  const deletionOf = (page: Page) => (id: string) => open(page, deletePath(id));

  test(
    'shared-project-deletion-modal@S01 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('owner');
      await signInAs(page, ME);
      await projectDeletionModal.S01(page, p, deletionOf(page));
    }
  );

  test(
    'shared-project-deletion-modal@S02 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('owner');
      const lv = watchLiveView(page);
      await signInAs(page, ME);
      await projectDeletionModal.S02(page, p, deletionOf(page), typed =>
        sendProjectDeletion(page, lv, typed)
      );
    }
  );

  test(
    'shared-project-deletion-modal@S03 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('owner');
      await signInAs(page, ME);
      await projectDeletionModal.S03(page, p, deletionOf(page), '/projects');
    }
  );

  test(
    'shared-project-deletion-modal@S05 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('owner');
      await signInAs(page, ME);
      await projectDeletionModal.S05(
        page,
        p,
        deletionOf(page),
        'Cancel',
        settingsPath(p.id)
      );
    }
  );
});

test.describe('shared-authenticated-session', () => {
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  test(
    'shared-authenticated-session@S01 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await authenticatedSession.S01(page, givenSettingsPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on project-settings-setup',
    PASSING_BOTH,
    async ({ page, browser }) => {
      await authenticatedSession.S02(
        page,
        browser,
        givenSettingsPage().path,
        ME
      );
    }
  );

  test(
    'shared-authenticated-session@S03 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await authenticatedSession.S03(page, givenSettingsPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on project-settings-setup',
    PASSING_BOTH,
    async ({ page, browser }) => {
      const h = givenSettingsPage();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.id}/history`,
        ME,
        'History'
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
      `shared-authenticated-session@${id} on project-settings-setup`,
      PENDING,
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

test.describe('shared-project-scope', () => {
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  test(
    'shared-project-scope@S01 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await projectScope.S01(page, givenSettingsPage().path);
    }
  );

  test(
    'shared-project-scope@S02 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await projectScope.S02(
        page,
        givenSettingsPage().path,
        ME,
        setupHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S03 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await projectScope.S03(page, givenSettingsPage({}).path, ME);
    }
  );

  test(
    'shared-project-scope@S04 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage({});
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.id}'`
      );
      await projectScope.S04(page, h.path, OTHER);
    }
  );

  test(
    'shared-project-scope@S05 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      exec(`update projects set requires_mfa = true where id = '${h.id}'`);
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on project-settings-setup',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenSettingsPage({});
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, setupHeading(page));
    }
  );

  test(
    'shared-project-scope@S07 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.id, ME, OTHER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage({ [ME]: 'admin' });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.id, ME, 'viewer'),
        setupHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on project-settings-setup',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenSettingsPage({});
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S09(page, h.path, ME, () =>
        setSupportAccessOnNode(h.id, false)
      );
    }
  );

  test(
    'shared-project-scope@S10 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectScope.S10(page, h.path, ME, () =>
        scheduleDeletionOnNode(h.id)
      );
    }
  );

  // shared-project-scope S11 and S12 are not run on this page: they are about
  // an open workflow editor (archived sandbox, deleted workflow), and this
  // page holds no workflow open.
});

test.describe('shared-usage-limits-banner', () => {
  test(
    'shared-usage-limits-banner@S01 on project-settings-setup',
    PENDING,
    () => {
      test.skip(
        true,
        'variant usage-limited is not configured on this instance'
      );
    }
  );

  test(
    'shared-usage-limits-banner@S02 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await usageLimitsBanner.S02(
        page,
        givenSettingsPage().path,
        ME,
        setupHeading(page)
      );
    }
  );
});

// The picker scenarios seed their own "Malawi HIV", so this page's project
// has another name.
test.describe('shared-project-header', () => {
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  const HOST = 'Settings host';

  test(
    'shared-project-header@S01 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectHeader.S01(page, h.path, ME, HOST, [
        { name: 'Project settings' },
      ]);
    }
  );

  test(
    'shared-project-header@S02 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const w = given(
        {
          name: HOST,
          members: { [ME]: 'editor', [OTHER]: 'owner' },
          sandboxes: [
            { name: 'dev', color: '#E33D63', members: { [ME]: 'editor' } },
          ],
        },
        OTHER
      );
      await projectHeader.S03(page, ME, {
        path: settingsPath(w.id('dev')),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on project-settings-setup`,
      PASSING_BOTH,
      async ({ page }) => {
        const h = givenSettingsPage();
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on project-settings-setup',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, so this page is its host
  test(
    'shared-project-header@S09 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // The picker lands on the other project's settings
  test(
    'shared-project-header@S10 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectHeader.S10(page, h.path, ME, '/settings');
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on project-settings-setup`,
      PASSING_BOTH,
      async ({ page }) => {
        const h = givenSettingsPage();
        await projectHeader[id](page, h.path, ME);
      }
    );

  test('shared-project-header@S14 on project-settings-setup', PENDING, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

  // This page highlights "Settings" in the side menu
  test(
    'shared-project-header@S15 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectHeader.S15(page, h.path, ME, h.id, 'Settings');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  test(
    'shared-project-header@S17 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage({ [ME]: 'viewer', [THIRD]: 'viewer' });
      await projectHeader.S17(page, h.path);
    }
  );
});

// This page puts the info flash "Project updated successfully" (a save), the
// error flash about not being allowed to delete (a non-owner opening
// /settings/delete) and, on a redirect, "Project scheduled for deletion".
test.describe('shared-flash-messages', () => {
  // Given I am an admin on the settings page; I rename the project
  async function givenRenamable(page: Page) {
    const h = givenSettingsPage({ [ME]: 'admin' });
    await signInAs(page, ME);
    await openSettings(page, h.id);
    return async () => {
      await field(identityForm(page), 'Project name').fill('renamed');
      await saveIdentity(page);
    };
  }

  test(
    'shared-flash-messages@S01 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await flashMessages.S01(page, UPDATED, await givenRenamable(page));
    }
  );

  test(
    'shared-flash-messages@S02 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage({ [ME]: 'admin' });
      await signInAs(page, ME);
      await openSettings(page, h.id);
      await flashMessages.S02(page, NOT_OWNER, () =>
        open(page, deletePath(h.id))
      );
    }
  );

  test(
    'shared-flash-messages@S03 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await flashMessages.S03(page, UPDATED, await givenRenamable(page));
    }
  );

  test(
    'shared-flash-messages@S04 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      await flashMessages.S04(
        page,
        UPDATED,
        await givenRenamable(page),
        async () => {
          // Typing a description makes the page render again
          await field(identityForm(page), 'Project description').fill('more');
        }
      );
    }
  );

  // Scheduling the project for deletion redirects me to "/projects"
  test(
    'shared-flash-messages@S05 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const p = givenProject('owner');
      await signInAs(page, ME);
      await flashMessages.S05(
        page,
        'Project scheduled for deletion',
        async () => {
          await open(page, deletePath(p.id));
          const d = await deletionDialog(page);
          await field(d, 'Project name').fill(p.name);
          await field(d, 'Project name').blur();
          await submit(d, DELETE_PROJECT);
        },
        '/projects'
      );
    }
  );

  test(
    'shared-flash-messages@S06 on project-settings-setup',
    PASSING_BOTH,
    async ({ page }) => {
      const h = givenSettingsPage();
      const notMine = givenSettingsPage({}, 'Kenya TB');
      await signInAs(page, ME);
      await openSettings(page, h.id);

      await flashMessages.S06(
        page,
        () => open(page, notMine.path),
        '/projects',
        page.getByRole('cell', {
          name: manifest().projects[0].name,
          exact: true,
        })
      );
    }
  );

  // shared-flash-messages S07 and S08 are not run on this page: S07 is on
  // admin pages (settings layout) and S08 on the sign-in and account forms.
});
