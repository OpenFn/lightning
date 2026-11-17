// Scenarios from annotations/views/sandboxes-index.md.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org and super@openfn.org are the other members a test
// needs. Every workspace ("Malawi HIV", "parent" and their sandboxes) is
// seeded by the test through Lightning and removed again afterwards, with
// anything created in it through the page.
import { expect, test, type Locator, type Page } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  addCollectionOnNode,
  addWorkflowOnNode,
  changeWorkflowOnNode,
  chooseMergeTarget,
  changeRoleOnNode,
  chosenMergeTarget,
  clickable,
  exec,
  expectAt,
  expectTooltip,
  field,
  hoverDisabled,
  keepAccount,
  makeSupportUser,
  manifest,
  mergeRow,
  mergeTargets,
  modal,
  modalTitle,
  onNode,
  open,
  removeMemberOnNode,
  removeMfaOf,
  scheduleDeletionOnNode,
  setSupportAccessOnNode,
  projectIdIn,
  restoreButton,
  sandboxAction,
  sandboxActionTarget,
  sandboxCard,
  sandboxesPath,
  sandboxName,
  scheduledDeletionOf,
  seedWorkspace,
  sendSandboxRequest,
  signInAs,
  sql,
  submit,
  submitButton,
  toggleMergeRow,
  user,
  watchLiveView,
  withLimiterRefusing,
  withSandboxNestingDepth,
  workflowsOf,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given this workspace exists (removed after the test)
function given(seed: WorkspaceSeed, by = ME) {
  const workspace = seedWorkspace(seed, by);
  cleanups.push(workspace.remove);
  return workspace;
}

// Given a Lightning setting or limiter for this test (put back after it)
function withSetting(putBack: () => unknown) {
  cleanups.push(() => void putBack());
}

// Given I am signed in and on the sandboxes page of <projectId>
async function onSandboxes(page: Page, projectId: string, email = ME) {
  await signInAs(page, email);
  await open(page, sandboxesPath(projectId));
}

const CREATE = 'Create a new sandbox';
const EDIT = 'Edit sandbox';
const DELETE = 'Delete sandbox';
const MERGE = 'Merge sandbox';

const createButton = (page: Page) =>
  page.getByRole('button', { name: 'Create Sandbox', exact: true });

// The open modal titled <title>, once it shows
async function dialog(page: Page, title: string) {
  await expect(modalTitle(page, title)).toBeVisible();
  return modal(page, title);
}

// When I start creating a sandbox and type <name>
async function startCreating(page: Page, name: string) {
  await createButton(page).click();
  const d = await dialog(page, CREATE);
  await field(d, 'Name').fill(name);
  await field(d, 'Name').blur();
  return d;
}

// When I pick a colour other than the one selected — returns the one picked
async function pickAnotherColour(d: Locator) {
  const radios = d.getByRole('radio');
  await expect(radios.first()).toBeAttached();
  for (const radio of await radios.all()) {
    if (await radio.isChecked()) continue;
    // The radio itself is visually hidden behind its swatch, so it can't
    // take a pointer click
    await radio.dispatchEvent('click');
    await expect(radio).toBeChecked();
    return (await radio.getAttribute('aria-label')) as string;
  }
  throw new Error('no other colour to pick');
}

// When I click the <action> action on sandbox <id> and its modal opens
async function openAction(
  page: Page,
  id: string,
  action: 'merge' | 'delete',
  title: string
) {
  await sandboxAction(page, id, action).click();
  return dialog(page, title);
}

// When I delete <name> (<id>) by typing its name
async function deleteByName(page: Page, id: string, name: string) {
  const d = await openAction(page, id, 'delete', DELETE);
  await field(d, 'Sandbox name').fill(name);
  await submitButton(d, 'Delete sandbox').click();
}

// When I open the merge modal for <id>, once it shows its target
async function openMerge(page: Page, id: string, target?: string) {
  const d = await openAction(page, id, 'merge', MERGE);
  if (target) await expect.poll(() => chosenMergeTarget(d)).toBe(target);
  return d;
}

const checkbox = (d: Locator, name: string) =>
  mergeRow(d, name).getByRole('checkbox');

const selectAll = (d: Locator, list: string) =>
  d.getByRole('checkbox', { name: new RegExp(list) });

const workflowNames = (projectId: string) =>
  workflowsOf(projectId).map(w => w.name);

const membersOf = (projectId: string) =>
  Object.fromEntries(
    sql<{ email: string; role: string }>(
      `select u.email, pu.role from project_users pu join users u on u.id = pu.user_id
       where pu.project_id = '${projectId}'`
    ).map(m => [m.email, m.role])
  );

const projectRow = (id: string) =>
  sql<{
    name: string;
    env: string | null;
    color: string | null;
    allow_support_access: boolean;
  }>(
    `select name, env, color, allow_support_access from projects where id = '${id}'`
  )[0];

const triggersOf = (projectId: string) =>
  sql<{ enabled: boolean }>(
    `select t.enabled from triggers t join workflows w on w.id = t.workflow_id
     where w.project_id = '${projectId}'`
  ).map(t => t.enabled);

const collectionsOf = (projectId: string) =>
  sql<{ name: string }>(
    `select name from collections where project_id = '${projectId}' order by name`
  ).map(c => c.name);

const credentialsOf = (projectId: string) =>
  sql<{ name: string }>(
    `select c.name from project_credentials pc join credentials c on c.id = pc.credential_id
     where pc.project_id = '${projectId}' order by c.name`
  ).map(c => c.name);

// @S01
// Scenario: Members see their workspace with the current project marked
//   Given I am an owner on project "Malawi HIV" with sandboxes "sb-1" and "sb-2"
//   When I open the sandboxes page of "Malawi HIV"
//   Then I see a card for "Malawi HIV" with the badges "main" and "active"
//   And I see cards for "sb-1" and "sb-2"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'sb-1' }, { name: 'sb-2' }],
  });

  await onSandboxes(page, w.id('Malawi HIV'));

  const root = sandboxCard(page, 'Malawi HIV');
  await expect(root).toContainText('main');
  await expect(root).toContainText('active');
  await expect(sandboxCard(page, 'sb-1')).toBeVisible();
  await expect(sandboxCard(page, 'sb-2')).toBeVisible();
});

// @S02
// Scenario: Environment badges tell a sandbox from the live project
//   Given project "Malawi HIV" has env "production"
//   And it has sandbox "sb-1" with env "staging" and sandbox "sb-2" with no env
//   When I open the sandboxes page of "Malawi HIV"
//   Then the "Malawi HIV" card shows "production"
//   And the "sb-1" card shows "staging"
//   And the "sb-2" card shows no environment badge
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    env: 'production',
    members: { [ME]: 'owner' },
    sandboxes: [
      { name: 'sb-1', env: 'staging' },
      { name: 'sb-2', env: null },
    ],
  });

  await onSandboxes(page, w.id('Malawi HIV'));

  await expect(sandboxCard(page, 'Malawi HIV')).toContainText('production');
  await expect(sandboxCard(page, 'Malawi HIV')).not.toContainText('main');
  await expect(sandboxCard(page, 'sb-1')).toContainText('staging');
  await expect(sandboxCard(page, 'sb-2')).toHaveText(/^\s*sb-2\s*$/);
});

// @S03
// Scenario: A sandbox I have no membership on is not listed
//   Given I am an owner on project "Malawi HIV"
//   And "Malawi HIV" has sandbox "with-me" where I am an owner and sandbox "without-me" where I have no role
//   When I open the sandboxes page of "Malawi HIV"
//   Then I see "with-me"
//   And I do not see "without-me"
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner', [OTHER]: 'admin' },
    sandboxes: [
      { name: 'with-me' },
      { name: 'without-me', members: { [ME]: null } },
    ],
  });

  await onSandboxes(page, w.id('Malawi HIV'));

  await expect(sandboxName(page, 'with-me')).toBeVisible();
  await expect(page.getByText('without-me')).toHaveCount(0);
});

// @S04
// Scenario: A sandbox-only member does not see the projects above them
//   Given project "Hidden root" has sandbox "team-space", which has sandbox "leaf"
//   And I am an admin on "team-space" and "leaf" only
//   When I open the sandboxes page of "team-space"
//   Then I see "team-space" and "leaf"
//   And I do not see "Hidden root"
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given(
    {
      name: 'Hidden root',
      members: { [OTHER]: 'owner' },
      sandboxes: [
        {
          name: 'team-space',
          members: { [ME]: 'admin' },
          sandboxes: [{ name: 'leaf', members: { [ME]: 'admin' } }],
        },
      ],
    },
    OTHER
  );

  await onSandboxes(page, w.id('team-space'));

  await expect(sandboxName(page, 'team-space')).toBeVisible();
  await expect(sandboxName(page, 'leaf')).toBeVisible();
  await expect(page.getByText('Hidden root')).toHaveCount(0);
});

// @S05
// Scenario: An empty workspace invites me to create a sandbox
//   Given I am an editor on project "Malawi HIV", which has no sandboxes
//   When I open the sandboxes page of "Malawi HIV"
//   Then I see "No sandboxes found"
//   And I see a "Create your first sandbox" link
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({ name: 'Malawi HIV', members: { [ME]: 'editor' } });

  await onSandboxes(page, w.id('Malawi HIV'));

  await expect(page.getByText('No sandboxes found')).toBeVisible();
  await clickable(page, 'Create your first sandbox').click();
  await expect(modalTitle(page, CREATE)).toBeVisible();
});

// @S06
// Scenario: Clicking a sandbox opens it
//   Given project "Malawi HIV" has sandbox "sb-1" that I belong to
//   When I click the "sb-1" card
//   Then I am on the workflows page of "sb-1"
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'sb-1' }],
  });

  await onSandboxes(page, w.id('Malawi HIV'));
  await sandboxName(page, 'sb-1').click();

  await expectAt(page, `/projects/${w.id('sb-1')}/w`);
});

// @S07
// Scenario: Editor creates a sandbox and lands in it
//   Given I am an editor on project "Malawi HIV"
//   When I click "Create Sandbox"
//   And I enter the name "Test Sandbox" and pick a colour
//   Then I see "Your sandbox will be named test-sandbox."
//   When I click "Create sandbox"
//   Then I am on the workflows page of sandbox "test-sandbox"
//   And I see "Sandbox created"
//   And sandbox "test-sandbox" has env "dev" and the colour I picked
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({ name: 'Malawi HIV', members: { [ME]: 'editor' } });
  const root = w.id('Malawi HIV');

  await onSandboxes(page, root);
  const d = await startCreating(page, 'Test Sandbox');
  const colour = await pickAnotherColour(d);
  await expect(d).toContainText('test-sandbox');
  await submitButton(d, 'Create sandbox').click();

  await expect.poll(() => projectIdIn(root, 'test-sandbox')).toBeTruthy();
  const id = projectIdIn(root, 'test-sandbox')!;
  await expectAt(page, `/projects/${id}/w`);
  await expect(flashMessages.toast(page, 'Sandbox created')).toBeVisible();
  expect(projectRow(id)).toMatchObject({ env: 'dev', color: colour });
});

// @S08
// Scenario: A new sandbox brings the team along, with the creator in charge
//   Given "owner@example.org" is the owner, I am an admin and "ed@example.org" is an editor on project "Malawi HIV"
//   When I create sandbox "admin-test-sandbox"
//   Then on "admin-test-sandbox" I am an owner, "owner@example.org" is an admin and "ed@example.org" is an editor
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [OTHER]: 'owner', [ME]: 'admin', [THIRD]: 'editor' },
  });
  const root = w.id('Malawi HIV');

  await onSandboxes(page, root);
  const d = await startCreating(page, 'admin-test-sandbox');
  await submitButton(d, 'Create sandbox').click();

  await expect.poll(() => projectIdIn(root, 'admin-test-sandbox')).toBeTruthy();
  expect(membersOf(projectIdIn(root, 'admin-test-sandbox')!)).toEqual({
    [user(ME).email]: 'owner',
    [user(OTHER).email]: 'admin',
    [user(THIRD).email]: 'editor',
  });
});

// @S09
// Scenario: A new sandbox keeps the parent's support access setting
//   Given project "Malawi HIV" allows support access
//   When I create sandbox "test-sandbox"
//   Then "test-sandbox" allows support access
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    allowSupportAccess: true,
  });
  const root = w.id('Malawi HIV');

  await onSandboxes(page, root);
  const d = await startCreating(page, 'test-sandbox');
  await submitButton(d, 'Create sandbox').click();

  await expect.poll(() => projectIdIn(root, 'test-sandbox')).toBeTruthy();
  expect(
    projectRow(projectIdIn(root, 'test-sandbox')!).allow_support_access
  ).toBe(true);
});

// @S10
// Scenario: A new sandbox copies workflows with their triggers off
//   Given project "Malawi HIV" has workflow "Intake" with an enabled cron trigger
//   When I create sandbox "test-sandbox"
//   Then "test-sandbox" has a workflow "Intake"
//   And its trigger is disabled
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    workflows: ['Intake'],
  });
  const root = w.id('Malawi HIV');
  expect(triggersOf(root)).toEqual([true]);

  await onSandboxes(page, root);
  const d = await startCreating(page, 'test-sandbox');
  await submitButton(d, 'Create sandbox').click();

  await expect.poll(() => projectIdIn(root, 'test-sandbox')).toBeTruthy();
  const id = projectIdIn(root, 'test-sandbox')!;
  expect(workflowNames(id)).toEqual(['Intake']);
  expect(triggersOf(id)).toEqual([false]);
});

// @S11
// Scenario: A sandbox name already used under the same parent is refused
//   Given project "Malawi HIV" has sandbox "test-sandbox"
//   When I start creating a sandbox and type "Test Sandbox"
//   Then I see "Sandbox name already exists"
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'test-sandbox' }],
  });
  const root = w.id('Malawi HIV');

  await onSandboxes(page, root);
  const d = await startCreating(page, 'Test Sandbox');
  await submit(d, 'Create sandbox');

  await expect(d.getByText('Sandbox name already exists')).toBeVisible();
  expect(
    sql(
      `select 1 from projects where parent_id = '${root}' and name = 'test-sandbox'`
    )
  ).toHaveLength(1);
});

// @S12
// Scenario: A blank name cannot be submitted
//   When I start creating a sandbox and clear the name
//   Then I see "can't be blank" once
//   And the "Create sandbox" button is disabled
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({ name: 'Malawi HIV', members: { [ME]: 'owner' } });
  const root = w.id('Malawi HIV');

  await onSandboxes(page, root);
  const d = await startCreating(page, 'x');
  await field(d, 'Name').fill('');
  await field(d, 'Name').blur();
  await submit(d, 'Create sandbox');

  await expect(d.getByText("can't be blank")).toHaveCount(1);
  await expect(d.getByText("can't be blank")).toBeVisible();
  expect(sql(`select 1 from projects where parent_id = '${root}'`)).toEqual([]);
});

// @S13
// Scenario: A viewer cannot create a sandbox
//   Given I am a viewer on project "Malawi HIV"
//   When I open the sandboxes page of "Malawi HIV"
//   Then the "Create Sandbox" button is disabled with "You are not authorized to create sandboxes in this workspace"
//   When I go to "/projects/<Malawi HIV>/sandboxes/new"
//   Then I am on the sandboxes page of "Malawi HIV"
//   And I see "You are not authorized to create sandboxes in this workspace"
test('@S13', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const NOT_AUTHORIZED =
    'You are not authorized to create sandboxes in this workspace';
  const w = given({ name: 'Malawi HIV', members: { [ME]: 'viewer' } }, OTHER);
  const root = w.id('Malawi HIV');

  await onSandboxes(page, root);
  await expect(createButton(page)).toBeDisabled();
  await hoverDisabled(createButton(page));
  await expect(
    page.getByRole('tooltip').filter({ hasText: NOT_AUTHORIZED })
  ).toBeVisible();

  await open(page, `${sandboxesPath(root)}/new`);
  await expectAt(page, sandboxesPath(root));
  await expect(flashMessages.toast(page, NOT_AUTHORIZED)).toBeVisible();
  await expect(modalTitle(page, CREATE)).toHaveCount(0);
});

// @S14 @variant:usage-limited
// Scenario: The plan's sandbox limit blocks creating one
//   Given the usage limiter refuses a new sandbox on "Malawi HIV" with "Sandbox limit reached"
//   When I open the sandboxes page of "Malawi HIV"
//   Then the "Create Sandbox" button is disabled and I see "Sandbox limit reached"
//   When I go to "/projects/<Malawi HIV>/sandboxes/new"
//   Then I am on the sandboxes page of "Malawi HIV" with the error "Sandbox limit reached"
test(
  '@S14',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const LIMIT = 'Sandbox limit reached';
    const w = given({ name: 'Malawi HIV', members: { [ME]: 'owner' } });
    const root = w.id('Malawi HIV');
    withSetting(withLimiterRefusing('new_sandbox', LIMIT));

    await onSandboxes(page, root);
    await expect(createButton(page)).toBeDisabled();
    await hoverDisabled(createButton(page));
    await expect(
      page.getByRole('tooltip').filter({ hasText: LIMIT })
    ).toBeVisible();

    await open(page, `${sandboxesPath(root)}/new`);
    await expectAt(page, sandboxesPath(root));
    await expect(flashMessages.toast(page, LIMIT)).toBeVisible();
  }
);

// @S15 @variant:nesting-capped
// Scenario: The create button is off at the nesting limit
//   Given the maximum sandbox nesting depth is 1
//   And I own sandbox "deep-sb-1" under project "deep-root"
//   When I open the sandboxes page of "deep-sb-1"
//   Then the "Create Sandbox" button is disabled
//   And I see "Maximum sandbox nesting depth reached"
test(
  '@S15',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const w = given({
      name: 'deep-root',
      members: { [ME]: 'owner' },
      sandboxes: [{ name: 'deep-sb-1' }],
    });
    withSetting(withSandboxNestingDepth(1));

    await onSandboxes(page, w.id('deep-sb-1'));

    await expect(createButton(page)).toBeDisabled();
    await hoverDisabled(createButton(page));
    await expect(
      page
        .getByRole('tooltip')
        .filter({ hasText: 'Maximum sandbox nesting depth reached' })
    ).toBeVisible();
  }
);

// @S16
// Scenario: Admin renames a sandbox
//   Given I am an admin on sandbox "sb-1" of project "Malawi HIV"
//   When I click the edit action on "sb-1"
//   Then I see "Edit sandbox" with the current colour selected
//   When I change the name to "sb-2" and click "Save changes"
//   Then I am on the sandboxes page
//   And I see "Sandbox updated"
// Also recolours it in the same save, so the colour is checked to be stored.
test('@S16', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given(
    {
      name: 'Malawi HIV',
      members: { [ME]: 'editor', [OTHER]: 'owner' },
      sandboxes: [
        { name: 'sb-1', color: '#E33D63', members: { [ME]: 'admin' } },
      ],
    },
    OTHER
  );
  const root = w.id('Malawi HIV');
  const sb = w.id('sb-1');

  await onSandboxes(page, root);
  await sandboxAction(page, sb, 'edit').click();
  const d = await dialog(page, EDIT);
  await expect(d.getByRole('radio', { name: '#E33D63' })).toBeChecked();
  await field(d, 'Name').fill('sb-2');
  const colour = await pickAnotherColour(d);
  await submitButton(d, 'Save changes').click();

  await expect(flashMessages.toast(page, 'Sandbox updated')).toBeVisible();
  await expectAt(page, sandboxesPath(root));
  await expect(sandboxName(page, 'sb-2')).toBeVisible();
  expect(projectRow(sb)).toMatchObject({ name: 'sb-2', color: colour });
});

// @S17
// Scenario: Renaming to a sibling's name is refused, keeping the same name is fine
//   Given project "Malawi HIV" has sandboxes "sb-1" and "sb-2"
//   When I edit "sb-1" and type "sb-2"
//   Then I see "Sandbox name already exists"
//   When I type "sb-1"
//   Then I see no name error
test('@S17', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'sb-1' }, { name: 'sb-2' }],
  });
  const sb = w.id('sb-1');

  await onSandboxes(page, w.id('Malawi HIV'));
  await sandboxAction(page, sb, 'edit').click();
  const d = await dialog(page, EDIT);
  await field(d, 'Name').fill('sb-2');
  await field(d, 'Name').blur();
  await submit(d, 'Save changes');
  await expect(d.getByText('Sandbox name already exists')).toBeVisible();
  expect(projectRow(sb).name).toBe('sb-1');

  await field(d, 'Name').fill('sb-1');
  await field(d, 'Name').blur();
  await expect(d.getByText('Sandbox name already exists')).toHaveCount(0);
  await submit(d, 'Save changes');
  await expect(flashMessages.toast(page, 'Sandbox updated')).toBeVisible();
  expect(projectRow(sb).name).toBe('sb-1');
});

// @S18
// Scenario: Non-admins see the sandbox actions disabled
//   Given I am a viewer on project "Malawi HIV" and on its sandbox "test-sandbox"
//   When I open the sandboxes page of "Malawi HIV"
//   Then the merge, edit and delete actions on "test-sandbox" are disabled
//   And their tooltips say "You are not authorized to merge this sandbox", "You are not authorized to edit this sandbox" and "You are not authorized to delete this sandbox"
// And a delete or merge request from me is refused.
test('@S18', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given(
    {
      name: 'Malawi HIV',
      members: { [OTHER]: 'owner', [ME]: 'viewer' },
      sandboxes: [{ name: 'test-sandbox', workflows: ['Beta flow'] }],
    },
    OTHER
  );
  const root = w.id('Malawi HIV');
  const sb = w.id('test-sandbox');
  const lv = watchLiveView(page);

  await onSandboxes(page, root);
  for (const [action, text] of [
    ['merge', 'You are not authorized to merge this sandbox'],
    ['edit', 'You are not authorized to edit this sandbox'],
    ['delete', 'You are not authorized to delete this sandbox'],
  ] as const) {
    await expect(sandboxAction(page, sb, action)).toBeDisabled();
    await expectTooltip(page, sandboxActionTarget(page, sb, action), text);
  }

  await sendSandboxRequest(page, lv, {
    kind: 'delete',
    id: sb,
    name: 'test-sandbox',
  });
  await sendSandboxRequest(page, lv, {
    kind: 'merge',
    id: sb,
    targetId: root,
    workflowIds: workflowsOf(sb).map(wf => wf.id),
  });

  expect(scheduledDeletionOf(sb)).toBeNull();
  expect(workflowNames(root)).toEqual([]);
  expect(lv.crashes()).toBe(0);
});

// @S19
// Scenario: A non-admin following an edit link is sent back
//   Given I am a viewer on project "Malawi HIV" and on its sandbox "test-sandbox"
//   When I go to "/projects/<Malawi HIV>/sandboxes/<test-sandbox>/edit"
//   Then I am on the sandboxes page of "Malawi HIV"
//   And I see "You are not authorized to edit this sandbox"
test('@S19', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given(
    {
      name: 'Malawi HIV',
      members: { [OTHER]: 'owner', [ME]: 'viewer' },
      sandboxes: [{ name: 'test-sandbox' }],
    },
    OTHER
  );
  const root = w.id('Malawi HIV');

  await signInAs(page, ME);
  await open(page, `${sandboxesPath(root)}/${w.id('test-sandbox')}/edit`);

  await expectAt(page, sandboxesPath(root));
  await expect(
    flashMessages.toast(page, 'You are not authorized to edit this sandbox')
  ).toBeVisible();
  await expect(modalTitle(page, EDIT)).toHaveCount(0);
});

// @S20
// Scenario: The workspace root can't be edited, deleted or merged from here
//   Given I am an admin on project "workspace-root" with an enabled trigger
//   When I open the sandboxes page of "workspace-root"
//   Then the "workspace-root" card has no edit, delete or merge actions
//   And a delete or merge request for "workspace-root" says "You are not authorized to delete this sandbox" or "You are not authorized to merge this sandbox"
//   And "workspace-root" is not scheduled for deletion and its trigger is still enabled
test('@S20', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given(
    {
      name: 'workspace-root',
      members: { [OTHER]: 'owner', [ME]: 'admin' },
      workflows: ['Intake'],
      sandboxes: [{ name: 'sb-1' }],
    },
    OTHER
  );
  const root = w.id('workspace-root');
  const lv = watchLiveView(page);

  await onSandboxes(page, root);
  await expect(sandboxCard(page, 'workspace-root')).toBeVisible();
  for (const action of ['merge', 'edit', 'delete'] as const)
    await expect(sandboxActionTarget(page, root, action)).toHaveCount(0);

  await sendSandboxRequest(page, lv, {
    kind: 'delete',
    id: root,
    name: 'workspace-root',
  });
  await sendSandboxRequest(page, lv, {
    kind: 'merge',
    id: root,
    targetId: w.id('sb-1'),
    workflowIds: workflowsOf(root).map(wf => wf.id),
  });

  expect(scheduledDeletionOf(root)).toBeNull();
  expect(triggersOf(root)).toEqual([true]);
  expect(lv.crashes()).toBe(0);
});

// @S21
// Scenario: Requests for a sandbox I can't see are refused
//   Given project "Malawi HIV" has sandbox "hidden-sandbox" where I have no role
//   When a delete, restore or merge request for "hidden-sandbox" reaches the page
//   Then I see "Sandbox not found"
//   And no modal opens
test('@S21', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner', [OTHER]: 'admin' },
    sandboxes: [
      {
        name: 'hidden-sandbox',
        members: { [ME]: null },
        workflows: ['Beta flow'],
      },
      { name: 'hidden-scheduled', members: { [ME]: null }, scheduledInDays: 3 },
    ],
  });
  const root = w.id('Malawi HIV');
  const hidden = w.id('hidden-sandbox');
  const scheduled = w.id('hidden-scheduled');
  const lv = watchLiveView(page);

  await onSandboxes(page, root);
  await sendSandboxRequest(page, lv, {
    kind: 'delete',
    id: hidden,
    name: 'hidden-sandbox',
  });
  await sendSandboxRequest(page, lv, { kind: 'restore', id: scheduled });
  await sendSandboxRequest(page, lv, {
    kind: 'merge',
    id: hidden,
    targetId: root,
    workflowIds: workflowsOf(hidden).map(wf => wf.id),
  });

  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(scheduledDeletionOf(hidden)).toBeNull();
  expect(scheduledDeletionOf(scheduled)).not.toBeNull();
  expect(workflowNames(root)).toEqual([]);
  expect(lv.crashes()).toBe(0);
});

// @S22
// Scenario: Admin deletes a sandbox by typing its name
//   Given I am an owner on project "Malawi HIV" and its sandbox "sb-1"
//   When I click the delete action on "sb-1"
//   Then I see "Delete sandbox" and "To confirm, type the sandbox name below."
//   When I type "sb-1" and click "Delete sandbox"
//   Then I see "Sandbox sb-1 scheduled for deletion."
//   And "sb-1" is listed under "Scheduled for deletion" with a "Restore" button
test('@S22', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'sb-1' }],
  });
  const sb = w.id('sb-1');

  await onSandboxes(page, w.id('Malawi HIV'));
  const d = await openAction(page, sb, 'delete', DELETE);
  await expect(d).toContainText('To confirm, type the sandbox name below.');
  await field(d, 'Sandbox name').fill('sb-1');
  await submitButton(d, 'Delete sandbox').click();

  await expect(
    flashMessages.toast(page, 'Sandbox sb-1 scheduled for deletion.')
  ).toBeVisible();
  await expect(
    page.getByRole('heading', { name: 'Scheduled for deletion' })
  ).toBeVisible();
  await expect(restoreButton(page, sb)).toBeVisible();
  expect(scheduledDeletionOf(sb)).not.toBeNull();
});

// @S23
// Scenario: A mistyped name keeps the delete button off
//   Given the delete modal is open for "sb-1"
//   When I type "wrong"
//   Then the "Delete sandbox" button is disabled with "Type the sandbox name to enable"
// And a delete request with the wrong name deletes nothing.
test('@S23', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'sb-1' }],
  });
  const sb = w.id('sb-1');
  const lv = watchLiveView(page);

  await onSandboxes(page, w.id('Malawi HIV'));
  const d = await openAction(page, sb, 'delete', DELETE);
  await field(d, 'Sandbox name').fill('wrong');
  await field(d, 'Sandbox name').blur();

  const button = submitButton(d, 'Delete sandbox');
  await expect(button).toBeDisabled();
  await hoverDisabled(button);
  await expect(
    page
      .getByRole('tooltip')
      .filter({ hasText: 'Type the sandbox name to enable' })
  ).toBeVisible();

  await sendSandboxRequest(page, lv, { kind: 'delete', id: sb, name: 'wrong' });
  expect(scheduledDeletionOf(sb)).toBeNull();
});

// @S24
// Scenario: The delete modal says how many child sandboxes go with it
//   Given sandbox "sb-1" has three active child sandboxes and one already scheduled for deletion
//   When I open the delete modal for "sb-1"
//   Then I see "Its 3 child sandboxes will also be deleted."
test('@S24', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [
      {
        name: 'sb-1',
        sandboxes: [
          { name: 'c-1' },
          { name: 'c-2' },
          { name: 'c-3' },
          { name: 'c-4', scheduledInDays: 3 },
        ],
      },
    ],
  });

  await onSandboxes(page, w.id('Malawi HIV'));
  const d = await openAction(page, w.id('sb-1'), 'delete', DELETE);

  await expect(d).toContainText('Its 3 child sandboxes will also be deleted.');
});

// @S25
// Scenario: The delete modal states the grace period
//   Given sandboxes are kept for 7 days after deletion
//   When I open the delete modal for "sb-1"
//   Then I see "This sandbox will be retained for 7 days before being permanently removed."
test('@S25', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  expect(onNode('Lightning.Config.purge_deleted_after_days()').trim()).toBe(
    '7'
  );
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'sb-1' }],
  });

  await onSandboxes(page, w.id('Malawi HIV'));
  const d = await openAction(page, w.id('sb-1'), 'delete', DELETE);

  await expect(d).toContainText(
    'This sandbox will be retained for 7 days before being permanently removed.'
  );
});

// @S26
// Scenario: Deleting a sandbox stops its work and its children's
//   Given sandbox "sb-1" has child sandbox "child" and both have enabled triggers
//   When I delete "sb-1"
//   Then "sb-1" and "child" are scheduled for deletion with the same date
//   And every trigger in "sb-1" and "child" is disabled
//   And the flow "flow-sandbox-scheduled-deletion" has started for "sb-1"
test('@S26', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    workflows: ['Intake'],
    sandboxes: [{ name: 'sb-1', sandboxes: [{ name: 'child' }] }],
  });
  const sb = w.id('sb-1');
  const child = w.id('child');
  exec(`update triggers set enabled = true where workflow_id in
          (select id from workflows where project_id in ('${sb}', '${child}'))`);
  expect([...triggersOf(sb), ...triggersOf(child)]).toEqual([true, true]);

  await onSandboxes(page, w.id('Malawi HIV'));
  await deleteByName(page, sb, 'sb-1');
  await expect(
    flashMessages.toast(page, 'Sandbox sb-1 scheduled for deletion.')
  ).toBeVisible();

  const at = scheduledDeletionOf(sb);
  expect(at).not.toBeNull();
  expect(scheduledDeletionOf(child)).toBe(at);
  expect([...triggersOf(sb), ...triggersOf(child)]).toEqual([false, false]);
});

// @S27
// Scenario: Deleting the sandbox I'm in sends me to its parent
//   Given I am on the sandboxes page of "grandchild", a child of "child-sandbox" under "parent"
//   And the delete modal warns "You are currently viewing this project" when I open it for my current project
//   When I delete "child-sandbox"
//   Then I am on the sandboxes page of "parent"
test('@S27', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'child-sandbox', sandboxes: [{ name: 'grandchild' }] }],
  });

  await onSandboxes(page, w.id('grandchild'));
  const d = await openAction(page, w.id('grandchild'), 'delete', DELETE);
  await expect(d).toContainText('You are currently viewing this project');
  await d.getByRole('button', { name: 'Cancel' }).click();
  await expect(modalTitle(page, DELETE)).toHaveCount(0);

  await deleteByName(page, w.id('child-sandbox'), 'child-sandbox');

  await expectAt(page, sandboxesPath(w.id('parent')));
});

// @S28
// Scenario: A scheduled sandbox shows when it will be removed
//   Given sandbox "later" is scheduled for deletion in 5 days
//   When I open the sandboxes page
//   Then "later" is struck through and can't be opened
//   And hovering it shows "Scheduled for deletion on <date> (in 5 days). Cancel the deletion to restore it."
test('@S28', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'later', scheduledInDays: 5 }],
  });
  const path = sandboxesPath(w.id('Malawi HIV'));

  await onSandboxes(page, w.id('Malawi HIV'));
  const name = sandboxName(page, 'later');
  expect(
    await name.evaluate(el => getComputedStyle(el).textDecorationLine)
  ).toContain('line-through');
  await expect(sandboxCard(page, 'later')).toHaveCount(0);
  await name.click();
  await page.waitForTimeout(500);
  await expectAt(page, path);

  await expectTooltip(page, name, 'Scheduled for deletion on');
  const tip = page
    .getByRole('tooltip')
    .filter({ hasText: 'Scheduled for deletion on' });
  await expect(tip).toContainText('(in 5 days)');
  await expect(tip).toContainText('Cancel the deletion to restore it.');
});

// @S29
// Scenario: Admin restores a scheduled sandbox
//   Given sandbox "scheduled" is scheduled for deletion and I am its owner
//   When I click "Restore" on "scheduled"
//   Then I see "Cancelled deletion of sandbox scheduled."
//   And "scheduled" is back in the active list with its actions
test('@S29', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'Malawi HIV',
    members: { [ME]: 'owner' },
    sandboxes: [{ name: 'scheduled', scheduledInDays: 3 }],
  });
  const sb = w.id('scheduled');

  await onSandboxes(page, w.id('Malawi HIV'));
  // Today's Lightning puts the Restore button inside a card marked
  // aria-disabled, so the button reads as disabled although it works; force
  // the click so the restore itself is still tested there.
  await restoreButton(page, sb).click({ force: true });

  await expect(
    flashMessages.toast(page, 'Cancelled deletion of sandbox scheduled.')
  ).toBeVisible();
  await expect(sandboxCard(page, 'scheduled')).toBeVisible();
  await expect(sandboxAction(page, sb, 'edit')).toBeEnabled();
  await expect(restoreButton(page, sb)).toHaveCount(0);
  expect(scheduledDeletionOf(sb)).toBeNull();
});

// @S30
// Scenario: A viewer can't restore a scheduled sandbox
//   Given sandbox "scheduled" is scheduled for deletion and I am a viewer on it
//   When I open the sandboxes page
//   Then the "Restore" button on "scheduled" is disabled with "You are not authorized to cancel deletion of this sandbox"
// And a restore request from me is refused.
test('@S30', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given(
    {
      name: 'Malawi HIV',
      members: { [OTHER]: 'owner', [ME]: 'viewer' },
      sandboxes: [{ name: 'scheduled', scheduledInDays: 3 }],
    },
    OTHER
  );
  const sb = w.id('scheduled');
  const lv = watchLiveView(page);

  await onSandboxes(page, w.id('Malawi HIV'));
  await expect(restoreButton(page, sb)).toBeDisabled();
  await hoverDisabled(restoreButton(page, sb));
  await expect(
    page.getByRole('tooltip').filter({
      hasText: 'You are not authorized to cancel deletion of this sandbox',
    })
  ).toBeVisible();

  await sendSandboxRequest(page, lv, { kind: 'restore', id: sb });
  expect(scheduledDeletionOf(sb)).not.toBeNull();
});

// @S31 @variant:usage-limited
// Scenario: The sandbox limit blocks restoring
//   Given the usage limiter refuses a new sandbox with "stub-blocked-message"
//   And sandbox "scheduled" is scheduled for deletion
//   When I open the sandboxes page
//   Then the "Restore" button on "scheduled" is disabled and I see "stub-blocked-message"
test(
  '@S31',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const w = given({
      name: 'Malawi HIV',
      members: { [ME]: 'owner' },
      sandboxes: [{ name: 'scheduled', scheduledInDays: 3 }],
    });
    const sb = w.id('scheduled');
    withSetting(withLimiterRefusing('new_sandbox', 'stub-blocked-message'));

    await onSandboxes(page, w.id('Malawi HIV'));
    await expect(restoreButton(page, sb)).toBeDisabled();
    await hoverDisabled(restoreButton(page, sb));
    await expect(
      page.getByRole('tooltip').filter({ hasText: 'stub-blocked-message' })
    ).toBeVisible();
  }
);

// Given I own "parent" and its sandbox "test-sandbox", which has a workflow
// "Beta flow" the parent doesn't
function parentAndSandbox(extra: Partial<WorkspaceSeed> = {}) {
  return given({
    name: 'parent',
    members: { [ME]: 'owner' },
    workflows: ['Alpha flow'],
    sandboxes: [{ name: 'test-sandbox', workflows: ['Beta flow'], ...extra }],
  });
}

// @S32
// Scenario: Admin merges a sandbox into its parent
//   Given I am an owner on project "parent" and its sandbox "test-sandbox"
//   When I click the merge action on "test-sandbox"
//   Then the merge target is "parent"
//   When I click "Merge"
//   Then I am on the workflows page of "parent"
//   And I see "Successfully merged test-sandbox into parent. Sandbox scheduled for deletion."
//   And the flow "flow-sandbox-merge" has started for "test-sandbox" into "parent"
test('@S32', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = parentAndSandbox();
  const parent = w.id('parent');
  const sb = w.id('test-sandbox');

  await onSandboxes(page, parent);
  const d = await openMerge(page, sb, 'parent');
  await submitButton(d, 'Merge').click();

  await expectAt(page, `/projects/${parent}/w`);
  await expect(
    flashMessages.toast(
      page,
      'Successfully merged test-sandbox into parent. Sandbox scheduled for deletion.'
    )
  ).toBeVisible();
  expect(workflowNames(parent)).toEqual(['Alpha flow', 'Beta flow']);
  expect(scheduledDeletionOf(sb)).not.toBeNull();
});

// @S33
// Scenario: Merge targets are limited to projects I can change
//   Given "child1" is a sandbox of "root" with children "grandchild1" and "grandchild2"
//   And "root" has sandboxes "child2", "child3", "viewer-only" where I am a viewer, and "retiring" scheduled for deletion
//   When I open the merge modal for "child1"
//   Then the target options are "root", "child2" and "child3"
test('@S33', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'root',
    members: { [ME]: 'owner', [OTHER]: 'admin' },
    workflows: ['Alpha flow'],
    sandboxes: [
      {
        name: 'child1',
        sandboxes: [{ name: 'grandchild1' }, { name: 'grandchild2' }],
      },
      { name: 'child2' },
      { name: 'child3' },
      { name: 'viewer-only', members: { [ME]: 'viewer' } },
      { name: 'retiring', scheduledInDays: 3 },
    ],
  });

  await onSandboxes(page, w.id('root'));
  const d = await openMerge(page, w.id('child1'), 'root');

  expect((await mergeTargets(d)).sort()).toEqual(['child2', 'child3', 'root']);
});

// @S34
// Scenario: A target I wasn't offered is refused at merge time
//   Given the merge modal is open for "test-sandbox"
//   When a merge request names "retiring", "test-sandbox" itself, or an unknown project
//   Then I see "Target project not found"
//   When a merge request names "restricted-target" where I am a viewer
//   Then I see "You are not authorized to merge into this project"
//   And nothing is merged
test('@S34', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner', [OTHER]: 'admin' },
    workflows: ['Alpha flow'],
    sandboxes: [
      { name: 'test-sandbox', workflows: ['Beta flow'] },
      { name: 'retiring', scheduledInDays: 3 },
      { name: 'restricted-target', members: { [ME]: 'viewer' } },
    ],
  });
  const sb = w.id('test-sandbox');
  const workflowIds = workflowsOf(sb).map(wf => wf.id);
  const lv = watchLiveView(page);

  await onSandboxes(page, w.id('parent'));
  await openMerge(page, sb, 'parent');
  for (const targetId of [
    w.id('retiring'),
    sb,
    '00000000-0000-4000-8000-000000000000',
    w.id('restricted-target'),
  ])
    await sendSandboxRequest(page, lv, {
      kind: 'merge',
      id: sb,
      targetId,
      workflowIds,
    });

  for (const name of ['retiring', 'restricted-target'])
    expect(workflowNames(w.id(name))).toEqual(['Alpha flow']);
  expect(scheduledDeletionOf(sb)).toBeNull();
  expect(lv.crashes()).toBe(0);
});

// @S35
// Scenario: Changed and new workflows are preselected, unchanged ones are not
//   Given "parent" and "test-sandbox" both have "Unchanged" at the same version
//   And "test-sandbox" has a changed "Changed" and a new "Beta"
//   When I open the merge modal for "test-sandbox"
//   Then "Changed" is checked and labelled "Changed"
//   And "Beta" is checked and labelled "New"
//   And "Unchanged" is not checked
test('@S35', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner' },
    workflows: ['Same flow', 'Edited flow'],
    sandboxes: [{ name: 'test-sandbox', workflows: ['Beta flow'] }],
  });
  const sb = w.id('test-sandbox');
  changeWorkflowOnNode(sb, 'Edited flow', ME);

  await onSandboxes(page, w.id('parent'));
  const d = await openMerge(page, sb, 'parent');

  await expect(checkbox(d, 'Edited flow')).toBeChecked();
  await expect(mergeRow(d, 'Edited flow')).toContainText('Changed');
  await expect(checkbox(d, 'Beta flow')).toBeChecked();
  await expect(mergeRow(d, 'Beta flow')).toContainText('New');
  await expect(checkbox(d, 'Same flow')).not.toBeChecked();
});

// @S36
// Scenario: Workflows changed in the target since the fork are flagged
//   Given "Test Workflow" was changed in both "parent" and "test-sandbox" since the fork
//   When I open the merge modal for "test-sandbox"
//   Then "Test Workflow" is labelled "Diverged"
//   And I see "Any conflicting changes in the target are lost."
test('@S36', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner' },
    workflows: ['Test Workflow'],
    sandboxes: [{ name: 'test-sandbox' }],
  });
  const sb = w.id('test-sandbox');
  changeWorkflowOnNode(sb, 'Test Workflow', ME);
  changeWorkflowOnNode(w.id('parent'), 'Test Workflow', ME);

  await onSandboxes(page, w.id('parent'));
  const d = await openMerge(page, sb, 'parent');

  await expect(mergeRow(d, 'Test Workflow')).toContainText('Diverged');
  await expect(d).toContainText(
    'Any conflicting changes in the target are lost.'
  );
});

// @S37
// Scenario: Deleting a workflow from the target is opt-in
//   Given "Gamma" existed in "parent" before "test-sandbox" was created and is not in "test-sandbox"
//   When I open the merge modal for "test-sandbox"
//   Then "Gamma" is listed as "Deleted in sandbox" and not checked
//   When I merge without checking it
//   Then "Gamma" still exists in "parent"
//   When instead I check "Gamma" and merge
//   Then "Gamma" is deleted from "parent"
// The "instead" merge uses a second sandbox in the same position, "sb-b".
test('@S37', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner' },
    workflows: ['Alpha flow'],
    sandboxes: [
      { name: 'test-sandbox', workflows: ['A flow'] },
      { name: 'sb-b', workflows: ['B flow'] },
    ],
  });
  const parent = w.id('parent');
  addWorkflowOnNode(parent, 'Gamma', ME, { daysAgo: 30 });

  await onSandboxes(page, parent);
  let d = await openMerge(page, w.id('test-sandbox'), 'parent');
  await expect(mergeRow(d, 'Gamma')).toContainText('Deleted in sandbox');
  await expect(checkbox(d, 'Gamma')).not.toBeChecked();
  await submitButton(d, 'Merge').click();
  await expectAt(page, `/projects/${parent}/w`);
  expect(workflowNames(parent)).toContain('Gamma');

  await open(page, sandboxesPath(parent));
  d = await openMerge(page, w.id('sb-b'), 'parent');
  await toggleMergeRow(d, 'Gamma');
  await expect(checkbox(d, 'Gamma')).toBeChecked();
  await submitButton(d, 'Merge').click();
  await expectAt(page, `/projects/${parent}/w`);
  expect(workflowNames(parent)).not.toContain('Gamma');
});

// @S38
// Scenario: Workflows added to the target after the fork are left out of the merge
//   Given "Added Later" was created in "parent" after "test-sandbox" was created
//   When I open the merge modal for "test-sandbox"
//   Then "Added Later" is not listed
//   And a request to select it is ignored and it survives the merge
test('@S38', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = parentAndSandbox();
  const parent = w.id('parent');
  const sb = w.id('test-sandbox');
  // Lightning keeps the fork time to the second; an hour back keeps "after
  // the fork" true however fast the seeding runs
  exec(
    `update projects set inserted_at = inserted_at - interval '1 hour' where id = '${sb}'`
  );
  addWorkflowOnNode(parent, 'Added Later', ME);
  const addedLater = workflowsOf(parent).find(wf => wf.name === 'Added Later')!;
  const lv = watchLiveView(page);

  await onSandboxes(page, parent);
  const d = await openMerge(page, sb, 'parent');
  await expect(mergeRow(d, 'Beta flow')).toBeVisible();
  await expect(d.getByText('Added Later')).toHaveCount(0);

  await sendSandboxRequest(page, lv, {
    kind: 'merge',
    id: sb,
    targetId: parent,
    workflowIds: workflowsOf(sb).map(wf => wf.id),
    deletedWorkflowIds: [addedLater.id],
  });

  await expect.poll(() => workflowNames(parent)).toContain('Beta flow');
  expect(workflowNames(parent)).toContain('Added Later');
});

// @S39
// Scenario: Selecting workflows, and merging nothing is not possible
//   Given the merge modal lists 2 workflows, both checked
//   When I click the "Workflows to merge" select-all
//   Then I see "0 of 2 selected"
//   And the "Merge" button is disabled with "No workflows selected"
//   When I click it again
//   Then I see "2 of 2 selected"
test('@S39', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner' },
    workflows: ['One flow', 'Two flow'],
    sandboxes: [{ name: 'test-sandbox' }],
  });
  const sb = w.id('test-sandbox');
  changeWorkflowOnNode(sb, 'One flow', ME);
  changeWorkflowOnNode(sb, 'Two flow', ME);

  await onSandboxes(page, w.id('parent'));
  const d = await openMerge(page, sb, 'parent');
  await expect(checkbox(d, 'One flow')).toBeChecked();
  await expect(checkbox(d, 'Two flow')).toBeChecked();

  await selectAll(d, 'Workflows to merge').click();
  await expect(d).toContainText('0 of 2 selected');
  const merge = submitButton(d, 'Merge');
  await expect(merge).toBeDisabled();
  await hoverDisabled(merge);
  await expect(
    page.getByRole('tooltip').filter({ hasText: 'No workflows selected' })
  ).toBeVisible();

  await selectAll(d, 'Workflows to merge').click();
  await expect(d).toContainText('2 of 2 selected');
  await expect(merge).toBeEnabled();
});

// @S40
// Scenario: Changing the target recomputes the workflow list
//   Given the merge modal for "test-sandbox" is open with target "parent"
//   When I choose "sibling" as the target
//   Then the "Diverged", "New" and "Deleted in sandbox" labels reflect "sibling"
//   And workflows I had unchecked stay unchecked
test('@S40', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner' },
    workflows: ['Alpha flow', 'Bravo flow'],
    sandboxes: [{ name: 'test-sandbox' }, { name: 'sibling' }],
  });
  const sb = w.id('test-sandbox');
  changeWorkflowOnNode(sb, 'Alpha flow', ME);
  changeWorkflowOnNode(sb, 'Bravo flow', ME);
  changeWorkflowOnNode(w.id('sibling'), 'Alpha flow', ME);

  await onSandboxes(page, w.id('parent'));
  const d = await openMerge(page, sb, 'parent');
  await expect(mergeRow(d, 'Alpha flow')).not.toContainText('Diverged');
  await toggleMergeRow(d, 'Bravo flow');
  await expect(checkbox(d, 'Bravo flow')).not.toBeChecked();

  await chooseMergeTarget(d, 'sibling');
  await expect.poll(() => chosenMergeTarget(d)).toBe('sibling');
  await expect(mergeRow(d, 'Alpha flow')).toContainText('Diverged');
  await expect(checkbox(d, 'Bravo flow')).not.toBeChecked();
  await expect(checkbox(d, 'Alpha flow')).toBeChecked();
});

// @S41
// Scenario: Credentials only the sandbox has are offered and preselected
//   Given "test-sandbox" has credential "sandbox-only-cred" that "parent" lacks
//   When I open the merge modal for "test-sandbox"
//   Then I see "Credentials to add" with "sandbox-only-cred" checked
//   When I uncheck it, change the target back to "parent" and merge
//   Then "parent" does not have "sandbox-only-cred"
test('@S41', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'parent',
    members: { [ME]: 'owner' },
    workflows: ['Alpha flow'],
    sandboxes: [
      {
        name: 'test-sandbox',
        workflows: ['Beta flow'],
        credentials: ['sandbox-only-cred'],
      },
      { name: 'sibling' },
    ],
  });
  const parent = w.id('parent');

  await onSandboxes(page, parent);
  const d = await openMerge(page, w.id('test-sandbox'), 'parent');
  await expect(selectAll(d, 'Credentials to add')).toBeVisible();
  await expect(checkbox(d, 'sandbox-only-cred')).toBeChecked();

  await toggleMergeRow(d, 'sandbox-only-cred');
  await expect(checkbox(d, 'sandbox-only-cred')).not.toBeChecked();
  await chooseMergeTarget(d, 'sibling');
  await expect.poll(() => chosenMergeTarget(d)).toBe('sibling');
  await chooseMergeTarget(d, 'parent');
  await expect.poll(() => chosenMergeTarget(d)).toBe('parent');
  await expect(checkbox(d, 'sandbox-only-cred')).not.toBeChecked();
  await submitButton(d, 'Merge').click();

  await expectAt(page, `/projects/${parent}/w`);
  expect(workflowNames(parent)).toContain('Beta flow');
  expect(credentialsOf(parent)).not.toContain('sandbox-only-cred');
});

// @S42
// Scenario: Collections only the sandbox has are created empty; target collections are never removed
//   Given "test-sandbox" has collections "col-a" and "col-b" and "parent" has "parent-only"
//   When I open the merge modal for "test-sandbox"
//   Then I see "Collections to add" with "2 of 2 selected" and no mention of "parent-only"
//   When I uncheck "col-b" and merge
//   Then "parent" has "col-a" and "parent-only" and not "col-b"
test('@S42', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = parentAndSandbox({ collections: ['col-a', 'col-b'] });
  const parent = w.id('parent');
  addCollectionOnNode(parent, 'parent-only');

  await onSandboxes(page, parent);
  const d = await openMerge(page, w.id('test-sandbox'), 'parent');
  await expect(selectAll(d, 'Collections to add')).toBeChecked();
  await expect(checkbox(d, 'col-a')).toBeChecked();
  await expect(checkbox(d, 'col-b')).toBeChecked();
  await expect(d.getByText('parent-only')).toHaveCount(0);

  await toggleMergeRow(d, 'col-b');
  await expect(checkbox(d, 'col-b')).not.toBeChecked();
  await submitButton(d, 'Merge').click();

  await expectAt(page, `/projects/${parent}/w`);
  expect(collectionsOf(parent)).toEqual(['col-a', 'parent-only']);
});

// @S43
// Scenario: The merge modal warns that the sandbox and its children will be deleted
//   Given "child1" has one active child sandbox
//   When I open the merge modal for "child1"
//   Then I see "This sandbox will be deleted after merging"
//   And I see "Its child sandbox will also be deleted."
test('@S43', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'root',
    members: { [ME]: 'owner' },
    workflows: ['Alpha flow'],
    sandboxes: [{ name: 'child1', sandboxes: [{ name: 'grandchild' }] }],
  });

  await onSandboxes(page, w.id('root'));
  const d = await openMerge(page, w.id('child1'), 'root');

  await expect(d).toContainText('This sandbox will be deleted after merging');
  await expect(d).toContainText('Its child sandbox will also be deleted.');
});

// @S44
// Scenario: A failed merge says so without exposing internals
//   Given the merge will fail validation
//   When I merge "child1" into "root"
//   Then I see "Couldn't merge this sandbox. Please try again."
//   And the merge modal is closed
//   And nothing in "root" has changed
// The merge is made to fail validation by a job in the sandbox that has lost
// its name, which the target can't accept.
test('@S44', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'root',
    members: { [ME]: 'owner' },
    workflows: ['Alpha flow'],
    sandboxes: [{ name: 'child1', workflows: ['Beta flow'] }],
  });
  const root = w.id('root');
  exec(`update jobs set name = '' where workflow_id in
          (select id from workflows where project_id = '${w.id('child1')}')`);

  await onSandboxes(page, root);
  const d = await openMerge(page, w.id('child1'), 'root');
  await submitButton(d, 'Merge').click();

  await expect(
    page.getByText("Couldn't merge this sandbox. Please try again.")
  ).toBeVisible();
  expect(workflowNames(root)).toEqual(['Alpha flow']);
  expect(scheduledDeletionOf(w.id('child1'))).toBeNull();
});

// @S45 @variant:usage-limited
// Scenario: A plan limit hit during the merge shows the limiter's message
//   Given the usage limiter refuses the merge with "Custom import error message"
//   When I merge "child1" into "root"
//   Then I see "Custom import error message"
test('@S45', { tag: '@pending' }, () => {
  test.skip(
    true,
    "not reachable here: the merge's only limiter refusal with its own message is the GitHub sync limit, which needs a GitHub-connected target; workflow and collection limits come back as validation errors (S44)"
  );
});

// @S46
// Scenario: A merge that can't schedule the sandbox for deletion still reports success
//   Given the sandbox can't be scheduled for deletion after the merge
//   When I merge "child1" into "root"
//   Then I am on the workflows page of "root"
//   And I see "Successfully merged child1 into root, but could not schedule the sandbox for deletion."
// Scheduling fails because another session scheduled it first, while the
// merge modal was open.
test('@S46', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const w = given({
    name: 'root',
    members: { [ME]: 'owner' },
    workflows: ['Alpha flow'],
    sandboxes: [{ name: 'child1', workflows: ['Beta flow'] }],
  });
  const root = w.id('root');

  await onSandboxes(page, root);
  const d = await openMerge(page, w.id('child1'), 'root');
  exec(`update projects set scheduled_deletion = now() + interval '7 days'
        where id = '${w.id('child1')}'`);
  await submitButton(d, 'Merge').click();

  await expectAt(page, `/projects/${root}/w`);
  await expect(
    flashMessages.toast(
      page,
      'Successfully merged child1 into root, but could not schedule the sandbox for deletion.'
    )
  ).toBeVisible();
});

// @S47 @variant:github-sync
// Scenario: Merging into a GitHub-synced project commits before and after
//   Given "parent" is synced to GitHub branch "main"
//   When I merge "test-sandbox" into "parent"
//   Then the flow "flow-github-sync-actions" has started for "parent" with commit message "pre-merge commit"
//   And it has started again with commit message "Merged sandbox test-sandbox"
test('@S47', { tag: '@pending' }, () => {
  test.skip(
    true,
    'variant github-sync: needs a GitHub app and repository the e2e Lightning does not have'
  );
});

// @S48
// Scenario: A sandbox-only member with no other project to merge into is told so
//   Given project "Hidden root" has sandbox "team-space"
//   And I am an admin on "team-space" only
//   When I open the merge modal for "team-space"
//   Then the merge target shows "Select a project"
//   And the "Merge" button is disabled
//   And nothing is merged
test('@S48', { tag: '@passing-new' }, async ({ page }) => {
  const w = given(
    {
      name: 'Hidden root',
      members: { [OTHER]: 'owner' },
      workflows: ['Alpha flow'],
      sandboxes: [
        {
          name: 'team-space',
          members: { [ME]: 'admin' },
          workflows: ['Beta flow'],
        },
      ],
    },
    OTHER
  );
  const lv = watchLiveView(page);

  await onSandboxes(page, w.id('team-space'));
  const d = await openAction(page, w.id('team-space'), 'merge', MERGE);

  await expect.poll(() => chosenMergeTarget(d)).toBe('Select a project');
  expect(await mergeTargets(d)).toEqual([]);
  await expect(submitButton(d, 'Merge')).toBeDisabled();
  expect(lv.crashes()).toBe(0);
  expect(workflowNames(w.id('Hidden root'))).toEqual(['Alpha flow']);
});

// Inherited shared annotations, run on the sandboxes page
const PENDING = { tag: '@pending' };

// Given project "Malawi HIV" (or <name>) has sandbox "sb-1", with these members
function givenSandboxesPage(
  members: Record<string, 'owner' | 'admin' | 'editor' | 'viewer'> = {
    [ME]: 'owner',
  },
  name = 'Malawi HIV'
) {
  // The sandbox is provisioned by an owner, so there has to be one
  const owner = Object.entries(members).find(([, r]) => r === 'owner')?.[0];
  const w = given(
    {
      name,
      members: owner ? members : { ...members, [OTHER]: 'owner' },
      sandboxes: [{ name: 'sb-1' }],
    },
    owner ?? OTHER
  );
  const root = w.id(name);
  return { w, root, path: sandboxesPath(root) };
}

const sandboxesHeading = (page: Page) =>
  page.getByRole('heading', { name: 'Sandboxes', exact: true });

test.describe('shared-authenticated-session', () => {
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  test(
    'shared-authenticated-session@S01 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, givenSandboxesPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(
        page,
        browser,
        givenSandboxesPage().path,
        ME
      );
    }
  );

  test(
    'shared-authenticated-session@S03 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, givenSandboxesPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      const h = givenSandboxesPage();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.root}/history`,
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
      `shared-authenticated-session@${id} on sandboxes-index`,
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
    'shared-project-scope@S01 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectScope.S01(page, givenSandboxesPage().path);
    }
  );

  test(
    'shared-project-scope@S02 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectScope.S02(
        page,
        givenSandboxesPage().path,
        ME,
        sandboxesHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S03 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectScope.S03(
        page,
        givenSandboxesPage({ [OTHER]: 'owner' }).path,
        ME
      );
    }
  );

  test(
    'shared-project-scope@S04 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [OTHER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.root}'`
      );
      await projectScope.S04(page, h.path, OTHER);
    }
  );

  test(
    'shared-project-scope@S05 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage();
      exec(`update projects set requires_mfa = true where id = '${h.root}'`);
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [OTHER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.root}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, sandboxesHeading(page));
    }
  );

  test(
    'shared-project-scope@S07 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor', [OTHER]: 'owner' });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.root, ME, OTHER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'admin', [OTHER]: 'owner' });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.root, ME, 'viewer'),
        sandboxesHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [OTHER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.root}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S09(page, h.path, ME, () =>
        setSupportAccessOnNode(h.root, false)
      );
    }
  );

  test(
    'shared-project-scope@S10 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor', [OTHER]: 'owner' });
      await projectScope.S10(page, h.path, ME, () =>
        scheduleDeletionOnNode(h.root)
      );
    }
  );

  // shared-project-scope S11 and S12 are not run on this page: they are about
  // an open workflow editor (archived sandbox, deleted workflow), and this
  // page holds no workflow open.
});

test.describe('shared-usage-limits-banner', () => {
  test('shared-usage-limits-banner@S01 on sandboxes-index', PENDING, () => {
    test.skip(true, 'variant usage-limited is not configured on this instance');
  });

  test(
    'shared-usage-limits-banner@S02 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await usageLimitsBanner.S02(
        page,
        givenSandboxesPage().path,
        ME,
        sandboxesHeading(page)
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

  const HOST = 'Sandboxes host';

  test(
    'shared-project-header@S01 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S01(page, h.path, ME, HOST, [{ name: 'Sandboxes' }]);
    }
  );

  test(
    'shared-project-header@S02 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
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
        path: sandboxesPath(w.id('dev')),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on sandboxes-index`,
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, whatever page hosts the header
  test(
    'shared-project-header@S09 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // This page is the sandboxes page, and the picker lands on the other
  // project's
  test(
    'shared-project-header@S10 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S10(page, h.path, ME, '/sandboxes');
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on sandboxes-index`,
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test('shared-project-header@S14 on sandboxes-index', PENDING, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

  // This page highlights "Sandboxes" in the side menu
  test(
    'shared-project-header@S15 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S15(page, h.path, ME, h.root, 'Sandboxes');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on sandboxes-index',
    { tag: '@passing-new' },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  test(
    'shared-project-header@S17 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage({ [ME]: 'viewer', [THIRD]: 'viewer' }, HOST);
      await projectHeader.S17(page, h.path);
    }
  );
});

// This page puts the info flash "Sandbox <name> scheduled for deletion." and
// the error flash "You are not authorized to create sandboxes in this
// workspace" (a viewer going to /new) itself.
test.describe('shared-flash-messages', () => {
  const INFO = 'Sandbox sb-1 scheduled for deletion.';
  const DENIED = 'You are not authorized to create sandboxes in this workspace';

  // Given I am on the sandboxes page; I delete "sb-1"
  async function givenDeletable(page: Page) {
    const h = givenSandboxesPage();
    await onSandboxes(page, h.root);
    await expect(sandboxCard(page, 'sb-1')).toBeVisible();
    return { h, remove: () => deleteByName(page, h.w.id('sb-1'), 'sb-1') };
  }

  // Given I am a viewer on the sandboxes page; I go to /new
  async function givenViewer(page: Page) {
    const h = givenSandboxesPage({ [ME]: 'viewer' });
    await onSandboxes(page, h.root);
    return () => open(page, `${h.path}/new`);
  }

  test(
    'shared-flash-messages@S01 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const { remove } = await givenDeletable(page);
      await flashMessages.S01(page, INFO, remove);
    }
  );

  test(
    'shared-flash-messages@S02 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await flashMessages.S02(page, DENIED, await givenViewer(page));
    }
  );

  test(
    'shared-flash-messages@S03 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const { remove } = await givenDeletable(page);
      await flashMessages.S03(page, INFO, remove);
    }
  );

  test(
    'shared-flash-messages@S04 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const { remove } = await givenDeletable(page);
      await flashMessages.S04(page, INFO, remove, async () => {
        // Opening the create form makes the page render again
        await createButton(page).click();
        await dialog(page, CREATE);
      });
    }
  );

  // Deleting the sandbox I am in redirects me to its parent's sandboxes page
  test(
    'shared-flash-messages@S05 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage();
      await onSandboxes(page, h.w.id('sb-1'));
      await flashMessages.S05(
        page,
        INFO,
        () => deleteByName(page, h.w.id('sb-1'), 'sb-1'),
        h.path
      );
    }
  );

  test(
    'shared-flash-messages@S06 on sandboxes-index',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const h = givenSandboxesPage();
      const notMine = givenSandboxesPage({ [OTHER]: 'owner' }, 'Kenya TB');
      await onSandboxes(page, h.root);

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
