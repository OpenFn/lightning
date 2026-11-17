// Scenarios from annotations/views/project-settings-data-storage.md. The
// shared session, scope, banner, header, flash and tab chrome scenarios run
// once for every settings tab, in project-settings-setup.spec.ts.
//
// Who's who: "I" am editor@openfn.org; each test gives me the role its Given
// names. "amara@example.org", and anyone else who owns the project, is
// owner@openfn.org.
import { expect, test, type Page } from '@playwright/test';

import {
  choosePeriod,
  formChecked,
  historySelect,
  ioSelect,
  offeredPeriods,
  openSettings,
  panel,
  sendDataStorageSave,
  shownPeriod,
} from './pages/project-settings';
import * as flashMessages from './shared/flash-messages';
import {
  auditEventsOf,
  changeRoleOnNode,
  mailbox,
  makeSupportUser,
  retentionOf,
  seedWorkspace,
  setRetention,
  signInAs,
  submit,
  user,
  watchLiveView,
  withRetentionPeriods,
  type Retention,
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

// Given I am a <role> on project "Malawi HIV" (owner@openfn.org owns it
// unless I do), with these data storage settings; null makes me no member
// at all
function givenProject(
  role: Role | null,
  retention: Partial<Retention> = {},
  { allowSupportAccess = false } = {}
) {
  const members: Record<string, Role | null> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const w = seedWorkspace(
    { name: PROJECT, members, allowSupportAccess },
    role === 'owner' ? ME : OTHER
  );
  cleanups.push(w.remove);
  const id = w.id(PROJECT);
  if (Object.keys(retention).length) setRetention(id, retention);
  return id;
}

// Given I am signed in and on project <id>'s Data Storage tab
async function onDataStorage(page: Page, id: string) {
  await signInAs(page, ME);
  await openSettings(page, id, 'Data Storage');
}

const toast = flashMessages.toast;
const NOT_AUTHORIZED = /You are not authori[sz]ed to perform this action/;
const SAVED = 'Project updated successfully';
const TOO_LONG =
  'dataclip retention period must be less or equal to the history retention period';
const RETAIN_ALL = 'Retain all input/output data';
const NEVER_RETAIN = 'Never retain input/output data (zero-persistence)';

const tab = (page: Page) => panel(page, 'Data Storage');
const policy = (page: Page, name: string) =>
  tab(page).getByRole('radio', { name, exact: true });
const button = (page: Page, name: string) =>
  tab(page).getByRole('button', { name, exact: true });

// The audit events project <id> has of kind <event>, by who
const audited = (id: string, event: string) =>
  auditEventsOf(id)
    .filter(e => e.event === event)
    .map(e => e.actor_id);

// @S01
// Scenario: A new project keeps everything until an admin decides otherwise
//   Given project "Malawi HIV" has never had its data storage settings changed
//   And I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   Then "Retain all input/output data" is selected
//   And the "History Retention Period" select shows "Select Period"
//   And the "Input/Output Data Retention Period" select is disabled
//   And I do not see "Heads Up!"
test('@S01', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onDataStorage(page, id);

  await expect(policy(page, RETAIN_ALL)).toBeChecked();
  expect(await shownPeriod(historySelect(page))).toBe('Select Period');
  await expect(ioSelect(page)).toBeDisabled();
  await expect(tab(page).getByText('Heads Up!')).toHaveCount(0);
});

// @S02
// Scenario: Admin sets the history retention period
//   Given I am an admin on project "Malawi HIV"
//   And "amara@example.org" is an owner on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   And I choose "7 Days" for "History Retention Period"
//   And I click "Save"
//   Then I see "Project updated successfully"
//   And project "Malawi HIV" keeps history for 7 days
//   And an audit event "history_retention_period_updated" is recorded with me as the actor
//   And the flow "flow-data-retention-change-email" has started for "amara@example.org"
// Serial: it reads the mailbox.
test(
  '@S02',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const id = givenProject('admin');
    await onDataStorage(page, id);

    await choosePeriod(historySelect(page), '7 Days');
    await submit(tab(page), 'Save');

    await expect(toast(page, SAVED)).toBeVisible();
    expect(retentionOf(id).history_retention_period).toBe(7);
    expect(audited(id, 'history_retention_period_updated')).toEqual([
      user(ME).id,
    ]);
    const owner = user(OTHER).email;
    await expect
      .poll(async () =>
        (await mailbox(page.request)).some(
          m =>
            m.to.includes(owner) &&
            /data retention policy .* has been modified/.test(m.subject)
        )
      )
      .toBe(true);
  }
);

// @S03
// Scenario: Admin sets the I/O retention period once a history period is chosen
//   Given I am an admin on project "Malawi HIV" with no history retention period
//   When I open the "Data Storage" tab
//   Then the "Input/Output Data Retention Period" select is disabled
//   When I choose "14 Days" for "History Retention Period"
//   Then the "Input/Output Data Retention Period" select is enabled
//   When I choose "7 Days" for "Input/Output Data Retention Period"
//   And I click "Save"
//   Then I see "Project updated successfully"
//   And project "Malawi HIV" keeps I/O data for 7 days
//   And an audit event "dataclip_retention_period_updated" is recorded with me as the actor
test('@S03', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onDataStorage(page, id);

  await expect(ioSelect(page)).toBeDisabled();
  await choosePeriod(historySelect(page), '14 Days');
  await expect(ioSelect(page)).toBeEnabled();
  await choosePeriod(ioSelect(page), '7 Days');
  await submit(tab(page), 'Save');

  await expect(toast(page, SAVED)).toBeVisible();
  expect(retentionOf(id)).toMatchObject({
    history_retention_period: 14,
    dataclip_retention_period: 7,
  });
  expect(audited(id, 'dataclip_retention_period_updated')).toEqual([
    user(ME).id,
  ]);
});

// @S04
// Scenario: I/O data can't be kept longer than run history
//   Given I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   And I choose "7 Days" for "History Retention Period"
//   And I choose "14 Days" for "Input/Output Data Retention Period"
//   Then I see "dataclip retention period must be less or equal to the history retention period"
//   And the "Save" button is disabled
// Checks that nothing is saved rather than the button: one version turns
// Save off, another refuses on save.
test('@S04', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onDataStorage(page, id);

  await choosePeriod(historySelect(page), '7 Days');
  await choosePeriod(ioSelect(page), '14 Days');
  await formChecked(tab(page), TOO_LONG);
  await submit(tab(page), 'Save');

  await expect(tab(page).getByText(TOO_LONG)).toBeVisible();
  expect(retentionOf(id)).toMatchObject({
    history_retention_period: null,
    dataclip_retention_period: null,
  });
});

// @S05
// Scenario: Shortening history below the current I/O period is refused
//   Given project "Malawi HIV" keeps history for 30 days and I/O data for 30 days
//   And I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   And I choose "7 Days" for "History Retention Period"
//   Then I see "dataclip retention period must be less or equal to the history retention period"
//   And the "Save" button is disabled
//   And project "Malawi HIV" still keeps history for 30 days
// Fails on today's Lightning: Save turns off but no message shows until
// the I/O period is touched.
test('@S05', NEW_ONLY, async ({ page }) => {
  const id = givenProject('admin', {
    history_retention_period: 30,
    dataclip_retention_period: 30,
  });
  await onDataStorage(page, id);

  await choosePeriod(historySelect(page), '7 Days');
  await formChecked(tab(page), TOO_LONG);
  await submit(tab(page), 'Save');

  await expect(tab(page).getByText(TOO_LONG)).toBeVisible();
  expect(retentionOf(id).history_retention_period).toBe(30);
});

// @S06
// Scenario: Admin switches the project to never storing I/O data
//   Given project "Malawi HIV" keeps history for 14 days and I/O data for 7 days
//   And I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   And I choose "Never retain input/output data (zero-persistence)"
//   Then I see "Heads Up!"
//   And I see "When enabled, you will no longer be able to retry workflow runs, and channel request/response payloads will not be stored."
//   And the "Input/Output Data Retention Period" select is disabled and shows no period
//   When I click "Save"
//   Then I see "Project updated successfully"
//   And when I reload the "Data Storage" tab "Never retain input/output data (zero-persistence)" is selected
//   And the flow "flow-zero-persistence-runs" has started for project "Malawi HIV"
// The flow is the runs'; here only that the project now stores no I/O data.
test('@S06', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin', {
    history_retention_period: 14,
    dataclip_retention_period: 7,
  });
  await onDataStorage(page, id);

  await policy(page, NEVER_RETAIN).check();

  await expect(tab(page).getByText('Heads Up!')).toBeVisible();
  await expect(
    tab(page).getByText(
      'When enabled, you will no longer be able to retry workflow runs, and channel request/response payloads will not be stored.'
    )
  ).toBeVisible();
  await expect(ioSelect(page)).toBeDisabled();
  await expect.poll(() => shownPeriod(ioSelect(page))).not.toBe('7 Days');

  await submit(tab(page), 'Save');
  await expect(toast(page, SAVED)).toBeVisible();

  await openSettings(page, id, 'Data Storage');
  await expect(policy(page, NEVER_RETAIN)).toBeChecked();
  expect(retentionOf(id).retention_policy).toBe('erase_all');
});

// @S07
// Scenario: Admin switches back to retaining all I/O data
//   Given project "Malawi HIV" never retains I/O data
//   And I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   And I choose "Retain all input/output data"
//   Then I do not see "Heads Up!"
//   When I click "Save"
//   Then I see "Project updated successfully"
//   And when I reload the "Data Storage" tab "Retain all input/output data" is selected
test('@S07', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin', { retention_policy: 'erase_all' });
  await onDataStorage(page, id);

  await policy(page, RETAIN_ALL).check();
  await expect(tab(page).getByText('Heads Up!')).toHaveCount(0);
  await submit(tab(page), 'Save');
  await expect(toast(page, SAVED)).toBeVisible();

  await openSettings(page, id, 'Data Storage');
  await expect(policy(page, RETAIN_ALL)).toBeChecked();
  expect(retentionOf(id).retention_policy).toBe('retain_all');
});

// @S08
// Scenario: Cancel discards unsaved changes
//   Given project "Malawi HIV" retains all I/O data
//   And I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   And I choose "Never retain input/output data (zero-persistence)"
//   And I click "Cancel"
//   Then "Retain all input/output data" is selected
//   And project "Malawi HIV" still retains all I/O data
test('@S08', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onDataStorage(page, id);

  await policy(page, NEVER_RETAIN).check();
  await expect(tab(page).getByText('Heads Up!')).toBeVisible();
  await button(page, 'Cancel').click();

  await expect(policy(page, RETAIN_ALL)).toBeChecked();
  expect(retentionOf(id).retention_policy).toBe('retain_all');
});

// @S09
// Scenario Outline: Non-admins see the policy but can't change it
//   Given project "Malawi HIV" keeps history for 30 days
//   And I am a <role> on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   Then I see "Input/Output Data Storage Policy"
//   And the "History Retention Period" select shows "30 Days" and is disabled
//   And both I/O storage radio buttons are disabled
//   And the "Input/Output Data Retention Period" select is disabled
//   And the "Cancel" and "Save" buttons are disabled
//   Examples: viewer, editor, support user with no membership row
const S09_ROWS = ['viewer', 'editor', 'support user'] as const;
for (const role of S09_ROWS)
  test(`@S09 ${role}`, PASSING_BOTH, async ({ page }) => {
    const support = role === 'support user';
    if (support) cleanups.push(makeSupportUser(ME));
    const id = givenProject(
      support ? null : role,
      { history_retention_period: 30 },
      { allowSupportAccess: support }
    );
    await onDataStorage(page, id);

    await expect(
      tab(page).getByText('Input/Output Data Storage Policy')
    ).toBeVisible();
    expect(await shownPeriod(historySelect(page))).toBe('30 Days');
    await expect(historySelect(page)).toBeDisabled();
    await expect(policy(page, RETAIN_ALL)).toBeDisabled();
    await expect(policy(page, NEVER_RETAIN)).toBeDisabled();
    await expect(ioSelect(page)).toBeDisabled();
    await expect(button(page, 'Cancel')).toBeDisabled();
    await expect(button(page, 'Save')).toBeDisabled();
  });

// @S10
// Scenario Outline: A save from a non-admin is refused on the server
//   Given I am a <role> on project "Malawi HIV"
//   And project "Malawi HIV" has no history retention period
//   When I submit the data storage form with history "14", I/O period "7" and policy "Retain all"
//   Then I see "You are not authorized to perform this action."
//   And project "Malawi HIV" still has no history retention period
//   Examples: editor, viewer
// Checked by what is stored and that the page didn't crash: one version
// flashes the refusal, another answers the request.
for (const role of ['editor', 'viewer'] as const)
  test(`@S10 ${role}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject(role);
    const lv = watchLiveView(page);
    await onDataStorage(page, id);

    await sendDataStorageSave(page, lv, {
      history: 14,
      io: 7,
      policy: 'retain_all',
    });

    expect(lv.crashes()).toBe(0);
    expect(retentionOf(id)).toMatchObject({
      history_retention_period: null,
      dataclip_retention_period: null,
    });
  });

// @S11
// Scenario: An admin demoted while the page is open can't save
//   Given I am an admin on project "Malawi HIV" with the "Data Storage" tab open
//   And my role is changed to viewer without the page reloading
//   When I choose "Never retain input/output data (zero-persistence)" and click "Save"
//   Then I see "You are not authorized to perform this action"
//   And project "Malawi HIV" still retains all I/O data
test('@S11', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onDataStorage(page, id);

  changeRoleOnNode(id, ME, 'viewer', { quietly: true });
  await policy(page, NEVER_RETAIN).check();
  await submit(tab(page), 'Save');

  await expect(toast(page, NOT_AUTHORIZED)).toBeVisible();
  expect(retentionOf(id).retention_policy).toBe('retain_all');
});

// @S12
// Scenario: The data storage form can't change other project settings
//   Given I am an admin on project "Malawi HIV"
//   When I submit the data storage form with history "14" and also a name "renamed" and requires MFA "true"
//   Then I see "Project updated successfully"
//   And project "Malawi HIV" keeps history for 14 days
//   And its name and MFA requirement are unchanged
test('@S12', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const before = retentionOf(id);
  const lv = watchLiveView(page);
  await onDataStorage(page, id);

  await sendDataStorageSave(
    page,
    lv,
    { history: 14, io: null, policy: 'retain_all' },
    { name: 'renamed', raw_name: 'renamed', requires_mfa: 'true' }
  );

  expect(lv.crashes()).toBe(0);
  await expect.poll(() => retentionOf(id).history_retention_period).toBe(14);
  expect(retentionOf(id)).toMatchObject({
    name: before.name,
    requires_mfa: before.requires_mfa,
  });
});

// @S13 @variant:retention-limited
// Scenario: A plan that limits retention offers only its periods and says why
//   Given project "Malawi HIV" is on a plan that allows history periods of 7 and 14 days
//   And I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   Then the "History Retention Period" select offers "7 Days" and "14 Days"
//   And it does not offer "30 Days", "90 Days", "180 Days" or "365 Days"
//   And the "Input/Output Data Retention Period" select offers the same periods
//   And the plan's retention message is shown next to the history select
// Serial: it swaps the instance's usage limiter.
test(
  '@S13',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const id = givenProject('admin');
    const message = 'Upgrade for longer retention';
    cleanups.push(withRetentionPeriods(id, [7, 14], message));
    await onDataStorage(page, id);

    expect(await offeredPeriods(historySelect(page))).toEqual([
      '7 Days',
      '14 Days',
    ]);
    expect(await offeredPeriods(ioSelect(page))).toEqual(['7 Days', '14 Days']);
    await expect(tab(page).getByText(message)).toBeVisible();
  }
);

// @S14 @variant:retention-single-option
// Scenario: A plan with a single period can't change history retention
//   Given project "Malawi HIV" is on a plan that allows only a 7 day history period
//   And I am an admin on project "Malawi HIV"
//   When I open the "Data Storage" tab
//   Then the "History Retention Period" select is disabled
// Serial: it swaps the instance's usage limiter.
test(
  '@S14',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const id = givenProject('admin');
    cleanups.push(withRetentionPeriods(id, [7]));
    await onDataStorage(page, id);

    await expect(historySelect(page)).toBeDisabled();
  }
);

// @S15
// Scenario: A failed save is reported
//   Given I am an admin on project "Malawi HIV"
//   And recording the audit event will fail
//   When I choose "7 Days" for "History Retention Period" and click "Save"
//   Then I see "Changes couldn't be saved, please try again"
//   And project "Malawi HIV" still has no history retention period
// Skipped: the audit write only fails when it is stubbed (the old LiveView
// tests use Mimic). Any failure the e2e instance can cause raises instead of
// returning the error this message answers.
test.skip('@S15', PENDING, () => {});
