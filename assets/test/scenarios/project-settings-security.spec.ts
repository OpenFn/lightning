// Scenarios from annotations/views/project-settings-security.md. The shared
// session, scope, banner, header, flash and tab chrome scenarios run once for
// every settings tab, in project-settings-setup.spec.ts.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns the projects I don't. The colleague without MFA
// is a new account made for the test.
import { expect, test, type Page } from '@playwright/test';

import {
  mfaSwitch,
  openSettings,
  panel,
  sendMfaChange,
} from './pages/project-settings';
import {
  addMember,
  expectAt,
  expectTooltip,
  makeSupportUser,
  otherSession,
  removeMfaOf,
  seedMfaFor,
  seedUser,
  seedWorkspace,
  signInAs,
  exec,
  sql,
  user,
  watchLiveView,
  withLimiterRefusing,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';

const PASSING_BOTH = { tag: ['@passing-old', '@passing-new'] };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given I am a <role> on project "Malawi HIV" (owner@openfn.org owns it
// unless I do); null makes me no member at all
function givenProject(role: Role | null, extra: Partial<WorkspaceSeed> = {}) {
  const name = 'Malawi HIV';
  const members: Record<string, Role | null> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const by = role === 'owner' ? ME : OTHER;
  const w = seedWorkspace({ name, members, ...extra }, by);
  cleanups.push(w.remove);
  return w.id(name);
}

const setRequiresMfa = (id: string, on: boolean) =>
  exec(`update projects set requires_mfa = ${on} where id = '${id}'`);

const requiresMfa = (id: string) =>
  sql<{ requires_mfa: boolean }>(
    `select requires_mfa from projects where id = '${id}'`
  )[0].requires_mfa;

// The audit trail of the MFA requirement on project <id>, newest first
const mfaAudits = (id: string) =>
  sql<{ actor_id: string; before: unknown; after: unknown }>(
    `select actor_id, changes->'before'->'requires_mfa' as before,
            changes->'after'->'requires_mfa' as after
     from audit_events where item_id = '${id}' and event = 'requires_mfa_updated'
     order by inserted_at desc`
  );

// Given I have enrolled in MFA (after signing in, so no second factor is
// asked for)
function enrolled() {
  seedMfaFor(ME);
  cleanups.push(() => removeMfaOf(ME));
}

// Given I am signed in and on project <id>'s Security tab. Returns the
// watch on the tab's LiveView, set up before the tab opened.
async function onSecurity(page: Page, id: string) {
  await signInAs(page, ME);
  const lv = watchLiveView(page);
  await openSettings(page, id, 'Security');
  return lv;
}

const UPDATED = 'Project MFA requirement updated successfully';
const OPTIONAL = '(currently optional for this project)';
const REQUIRED = '(currently required for this project)';
const NO_PERMISSION = 'You do not have permission to perform this action';
const NOT_AUTHORIZED = /You are not authori[sz]ed to perform this action/;

// @S01
// Scenario: Admin turns on the MFA requirement
//   Given project "Malawi HIV" does not require MFA
//   And I am an admin on project "Malawi HIV" who has enrolled in MFA
//   When I open the "Security" tab
//   Then I see "(currently optional for this project)"
//   When I click the "Require MFA?" switch
//   Then I see "Project MFA requirement updated successfully"
//   And I see "(currently required for this project)"
//   And project "Malawi HIV" requires MFA
//   And an audit event "requires_mfa_updated" is recorded with me as the actor, before false and after true
test('@S01', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await signInAs(page, ME);
  enrolled();
  await openSettings(page, id, 'Security');
  await expect(panel(page, 'Security')).toContainText(OPTIONAL);

  await mfaSwitch(page).click();

  await expect(page.getByText(UPDATED)).toBeVisible();
  await expect(panel(page, 'Security')).toContainText(REQUIRED);
  await expect.poll(() => requiresMfa(id)).toBe(true);
  expect(mfaAudits(id)).toEqual([
    { actor_id: user(ME).id, before: false, after: true },
  ]);
});

// @S02
// Scenario: Admin turns off the MFA requirement
//   Given project "Malawi HIV" requires MFA
//   And I am an owner on project "Malawi HIV" who has enrolled in MFA
//   When I click the "Require MFA?" switch on the "Security" tab
//   Then I see "Project MFA requirement updated successfully"
//   And I see "(currently optional for this project)"
//   And project "Malawi HIV" does not require MFA
//   And an audit event "requires_mfa_updated" is recorded with me as the actor, before true and after false
test('@S02', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  setRequiresMfa(id, true);
  await signInAs(page, ME);
  enrolled();
  await openSettings(page, id, 'Security');
  await expect(panel(page, 'Security')).toContainText(REQUIRED);

  await mfaSwitch(page).click();

  await expect(page.getByText(UPDATED)).toBeVisible();
  await expect(panel(page, 'Security')).toContainText(OPTIONAL);
  await expect.poll(() => requiresMfa(id)).toBe(false);
  expect(mfaAudits(id)).toEqual([
    { actor_id: user(ME).id, before: true, after: false },
  ]);
});

// @S03
// Scenario Outline: Every member can see whether MFA is required
//   Given project "Malawi HIV" does not require MFA
//   And I am a <role> on project "Malawi HIV"
//   When I open the "Security" tab
//   Then I see "Multi-Factor Authentication"
//   And I see "(currently optional for this project)"
for (const role of ['viewer', 'editor', 'admin', 'owner'] as const) {
  test(`@S03 ${role}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject(role);
    await onSecurity(page, id);

    await expect(panel(page, 'Security')).toContainText(
      /Multi-Factor Authentication/i
    );
    await expect(panel(page, 'Security')).toContainText(OPTIONAL);
  });
}

// @S04
// Scenario Outline: Members who aren't admins can't change the requirement
//   Given project "Malawi HIV" does not require MFA
//   And I am a <role> on project "Malawi HIV"
//   When I open the "Security" tab
//   Then the "Require MFA?" switch shows the tooltip "You do not have permission to perform this action"
//   When I click the "Require MFA?" switch
//   Then I see "You are not authorized to perform this action."
//   And project "Malawi HIV" still does not require MFA
const S04: [string, () => string][] = [
  ['editor', () => givenProject('editor')],
  ['viewer', () => givenProject('viewer')],
  [
    'support user with no row, access on',
    () => {
      cleanups.push(makeSupportUser(ME));
      return givenProject(null, { allowSupportAccess: true });
    },
  ],
];
for (const [who, seed] of S04) {
  test(`@S04 ${who}`, PASSING_BOTH, async ({ page }) => {
    const id = seed();
    const lv = await onSecurity(page, id);

    await expectTooltip(page, mfaSwitch(page), NO_PERMISSION);
    // A switch that still takes the click says why nothing changed
    if (await mfaSwitch(page).isEnabled()) {
      await mfaSwitch(page).click();
      await expect(page.getByText(NOT_AUTHORIZED)).toBeVisible();
    }
    await sendMfaChange(page, lv, true);

    expect(requiresMfa(id)).toBe(false);
    expect(lv.crashes()).toBe(0);
  });
}

// @S05
// Scenario: An admin demoted while the page is open can't change the requirement
//   Given I am an admin on project "Malawi HIV" with the "Security" tab open
//   And my role is changed to viewer without the page being told
//   When I click the "Require MFA?" switch
//   Then I see "You are not authorized to perform this action"
//   And project "Malawi HIV" still does not require MFA
test('@S05', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onSecurity(page, id);
  // Without the page being told: no role-change event is broadcast
  exec(
    `update project_users set role = 'viewer'
     where project_id = '${id}' and user_id = '${user(ME).id}'`
  );

  await mfaSwitch(page).click();

  await expect(page.getByText(NOT_AUTHORIZED)).toBeVisible();
  expect(requiresMfa(id)).toBe(false);
});

// @S06 @variant:mfa-limited
// Scenario: The plan doesn't include requiring MFA
//   Given the usage limiter refuses ":require_mfa" for project "Malawi HIV" with the message "MFA Feature is disabled"
//   And I am an admin on project "Malawi HIV"
//   When I open the "Security" tab
//   Then I see "MFA Feature is disabled"
//   And the "Require MFA?" switch is disabled
//   When "toggle-mfa" is sent directly
//   Then I see "You are not authorized to perform this action"
//   And project "Malawi HIV" still does not require MFA
test(
  '@S06',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    cleanups.push(
      withLimiterRefusing('require_mfa', 'MFA Feature is disabled', {
        banner: true,
      })
    );
    const id = givenProject('admin');
    const lv = await onSecurity(page, id);

    // A plan-limit banner: the design-system page draws it beside the panel
    await expect(page.getByText('MFA Feature is disabled')).toBeVisible();
    // The plan limit is the Value, so the switch is off
    await expect(mfaSwitch(page)).toBeDisabled();
    await sendMfaChange(page, lv, true);

    expect(requiresMfa(id)).toBe(false);
    expect(lv.crashes()).toBe(0);
  }
);

// @S07 @variant:sandbox
// Scenario: The requirement can't be changed from a sandbox
//   Given sandbox "dev" of project "Malawi HIV"
//   And I am an owner of sandbox "dev"
//   When I open the settings of sandbox "dev" on the "Security" tab
//   Then the "Require MFA?" switch is disabled
//   And clicking it sends nothing
test('@S07', PASSING_BOTH, async ({ page }) => {
  const w = seedWorkspace(
    {
      name: 'Malawi HIV',
      members: { [ME]: 'owner' },
      sandboxes: [{ name: 'dev' }],
    },
    ME
  );
  cleanups.push(w.remove);
  const id = w.id('dev');
  const lv = await onSecurity(page, id);
  const before = lv.events();

  await expect(mfaSwitch(page)).toBeDisabled();
  await mfaSwitch(page).click({ force: true });

  expect(lv.events()).toBe(before);
  expect(requiresMfa(id)).toBe(false);
});

// @S08
// Scenario: Turning on the requirement hands off to MFA enforcement
//   Given I am an admin on project "Malawi HIV"
//   And "bob@example.org" is an editor on the project who has not enrolled in MFA
//   When I turn on the MFA requirement
//   Then the flow "flow-require-project-mfa" has started for "bob@example.org"
test('@S08', PASSING_BOTH, async ({ page, browser }) => {
  const bob = seedUser('bob', { firstName: 'Bob' });
  cleanups.push(bob.remove);
  const id = givenProject('admin');
  cleanups.push(addMember(id, bob.id, 'editor').remove);
  await signInAs(page, ME);
  enrolled();
  await openSettings(page, id, 'Security');

  await mfaSwitch(page).click();
  await expect.poll(() => requiresMfa(id)).toBe(true);

  // The hand-off: bob's next visit to the project is sent to enrol
  const elsewhere = await otherSession(browser, bob.email);
  await elsewhere.goto(`/projects/${id}/w`);
  await expectAt(elsewhere, '/mfa_required');
  await elsewhere.context().close();
});
