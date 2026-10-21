// Scenarios from annotations/views/workflows-index.md.
//
// Who's who: "I" is editor@openfn.org (Esther Editor), an editor on the project
// each test seeds ("Malawi HIV") unless the scenario says viewer. "Another
// user" is owner@openfn.org. The project has workflows "Intake", "Sync DHIS2"
// and "Weekly report", each with one webhook trigger that is on and a live
// state; work orders are inserted straight into the database, so the list has
// exactly the numbers a scenario names. Every test also puts editor's account
// back as it found it.
import { expect, test, type Locator, type Page } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  auditEventsOf,
  changeRoleOnNode,
  clearWorkflowSearch,
  createWorkflowOnNode,
  confirmNextPrompt,
  createWorkflowButton,
  daysAgo,
  deleteWorkflowOnNode,
  exec,
  expectAt,
  expectHistoryLists,
  expectTooltip,
  healthPath,
  historyLoaded,
  hoverDisabled,
  keepAccount,
  listedWorkflows,
  lookOf,
  makeSupportUser,
  manifest,
  metricCard,
  open,
  queryOf,
  removeMemberOnNode,
  removeMfaOf,
  removeWorkflowData,
  scheduleDeletionOnNode,
  seedDashboardWorkflow,
  seedHistoryOrder,
  seedProject,
  sendEventFrom,
  setPreferences,
  setSupportAccessOnNode,
  signInAs,
  sql,
  tagFor,
  typeInWorkflowSearch,
  user,
  utcStamp,
  workflowCell,
  workflowRow,
  workflowStored,
  workflowSwitch,
  workflowSwitchInput,
  workflowsHeading,
  workflowsPath,
  withRefusingLimiter,
  type SeededWorkflow,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Members = Parameters<typeof seedProject>[1];
type WorkflowOptions = Parameters<typeof seedDashboardWorkflow>[2];

// Given project "<name>" exists with these members (removed after the test,
// with the work orders seeded for it)
function given(
  name: string,
  members: Members,
  options?: Parameters<typeof seedProject>[2]
) {
  const project = seedProject(name, members, options);
  cleanups.push(() => {
    removeWorkflowData(project.id);
    project.remove();
  });
  return project;
}

// Given project "Malawi HIV" has workflows "Intake", "Sync DHIS2" and
// "Weekly report" (each live with its trigger on, unless said)
function givenWorkflows(
  name = 'Malawi HIV',
  members: Members = { [ME]: 'editor' },
  options: {
    intake?: WorkflowOptions;
    sync?: WorkflowOptions;
    weekly?: WorkflowOptions;
  } = {}
) {
  const project = given(name, members);
  const intake = seedDashboardWorkflow(project.id, 'Intake', options.intake);
  const sync = seedDashboardWorkflow(project.id, 'Sync DHIS2', options.sync);
  const weekly = seedDashboardWorkflow(
    project.id,
    'Weekly report',
    options.weekly
  );
  return { project, intake, sync, weekly, path: workflowsPath(project.id) };
}
type Dashboard = ReturnType<typeof givenWorkflows>;

// Given project "<name>" has workflows with these names, created in this order
function givenNamed(names: string[], members: Members = { [ME]: 'viewer' }) {
  const project = given('Malawi HIV', members);
  for (const name of names) seedDashboardWorkflow(project.id, name);
  return { project };
}

// When I open the workflows page — waits for the list
async function openWorkflows(page: Page, h: Pick<Dashboard, 'path'>) {
  await signInAs(page, ME);
  await open(page, h.path);
  await expect(workflowsHeading(page)).toBeVisible();
}

// Given "<wf>" had a successful work order, with one successful step
const succeeded = (wf: SeededWorkflow, minutesAgo: number) =>
  seedHistoryOrder(wf, {
    state: 'success',
    minutesAgo,
    runs: [{ state: 'success', steps: [{ job: 'Fetch', exit: 'success' }] }],
  }).id;

// Given "<wf>" had a work order that ended in <state>, with one failed step
const failed = (wf: SeededWorkflow, minutesAgo: number, state = 'failed') =>
  seedHistoryOrder(wf, {
    state,
    minutesAgo,
    runs: [{ state, steps: [{ job: 'Fetch' }] }],
  }).id;

// Given "<wf>" has a work order still waiting for a worker
const waiting = (wf: SeededWorkflow, minutesAgo: number) =>
  seedHistoryOrder(wf, {
    state: 'pending',
    minutesAgo,
    runs: [{ state: 'available' }],
  }).id;

// Given "<wf>" had a work order 40 days ago, outside the last 30 days
const longAgo = (wf: SeededWorkflow) =>
  seedHistoryOrder(wf, { state: 'success', at: utcStamp(daysAgo(40)) }).id;

// When I click the "<name>" switch
const flip = (page: Page, name: string) =>
  workflowSwitch(workflowRow(page, name)).click();

const NOT_AUTHORIZED = 'You are not authorized to perform this action.';

// @S01
// Scenario: Member sees the project's workflows with recent activity
//   Given I am a viewer on project "Malawi HIV"
//   And "Intake" had 4 work orders in the last 30 days, 1 of them failed
//   When I open the workflows page
//   Then I see "Workflows (3)"
//   And the "Intake" row shows its latest work order state and time
//   And the "Intake" row shows 4 work orders with its step count and success rate
//   And the "Intake" row shows 1 work order in a failed state with the time of the latest failure
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows('Malawi HIV', { [ME]: 'viewer' });
  for (const minutes of [300, 200, 100]) succeeded(h.intake, minutes);
  failed(h.intake, 10);

  await openWorkflows(page, h);

  await expect(workflowsHeading(page, 3)).toBeVisible();
  const row = workflowRow(page, 'Intake');
  await expect(workflowCell(row, 'latest')).toContainText('Failed');
  await expect(workflowCell(row, 'count')).toContainText(
    /4\s+\(4 steps, 75(\.0)?% success\)/
  );
  // It also shows when: some time follows the label (shared-local-datetime owns the format)
  await expect(workflowCell(row, 'failed')).toContainText(
    /1\s+Latest failure[\s\S]*\d/
  );
});

// @S02
// Scenario: Workflow with no recent activity says so
//   Given "Weekly report" has had no work orders in the last 30 days
//   When I open the workflows page
//   Then the "Weekly report" row shows "Nothing last 30 days"
//   And its work order and failed counts show 0 and "N/A"
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  // A work order from before the window does not count as activity
  longAgo(h.weekly);

  await openWorkflows(page, h);

  const row = workflowRow(page, 'Weekly report');
  await expect(workflowCell(row, 'latest')).toContainText(
    'Nothing last 30 days'
  );
  await expect(workflowCell(row, 'count')).toHaveText(/^\s*0\s+N\/A\s*$/);
  await expect(workflowCell(row, 'failed')).toHaveText(/^\s*0\s+N\/A\s*$/);
});

// @S03
// Scenario: Member sees project totals
//   Given the project had 10 work orders in the last 30 days, 6 pending and 2 failed
//   And 10 runs, 6 pending and 2 successful out of 4 finished
//   When I open the workflows page
//   Then the "Work Orders" card shows 10 and "6 pending"
//   And the "Runs" card shows 10 and "6 pending"
//   And the "Successful Runs" card shows 2 and "50.0%"
//   And the "Work Orders in failed state" card shows 2 and "20.0%"
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  // Across two workflows, so the totals are sums
  for (const wf of [h.intake, h.sync]) {
    for (const minutes of [10, 20, 30]) waiting(wf, minutes);
    failed(wf, 40);
    succeeded(wf, 50);
  }

  await openWorkflows(page, h);

  await expect(metricCard(page, 'Work Orders')).toContainText(/10\s+6 pending/);
  await expect(metricCard(page, 'Runs')).toContainText(/10\s+6 pending/);
  await expect(metricCard(page, 'Successful Runs')).toContainText(
    /2\s+50(\.0)?%/
  );
  await expect(metricCard(page, 'Work Orders in failed state')).toContainText(
    /2\s+20(\.0)?%/
  );
});

// @S04
// Scenario: Search narrows the list by name
//   When I type "sync" in the search box
//   Then I see "Sync DHIS2"
//   And I do not see "Intake"
//   And the URL query has "q=sync"
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  await openWorkflows(page, h);

  await typeInWorkflowSearch(page, 'sync');

  await expect(workflowRow(page, 'Sync DHIS2')).toBeVisible();
  await expect(workflowRow(page, 'Intake')).toHaveCount(0);
  await expect.poll(() => queryOf(page).q).toBe('sync');
});

// @S05
// Scenario: A search with no matches offers to create a workflow
//   When I search for "nonexistent"
//   Then I see 'No workflows found matching "nonexistent". Try a different search term or create a new one.'
//   And "create a new one" links to "/projects/<project_id>/w/new"
test('@S05', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  await openWorkflows(page, h);

  await typeInWorkflowSearch(page, 'nonexistent');

  // The link's own spacing may put a gap before the full stop
  await expect(
    page.getByText(
      /No workflows found matching "nonexistent"\. Try a different search term or\s+create a new one\s*\./
    )
  ).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'create a new one' })
  ).toHaveAttribute('href', `/projects/${h.project.id}/w/new`);
});

// @S06
// Scenario: Clearing the search restores the full list
//   Given I am on the workflows page with "q=api"
//   When I click the clear search button
//   Then I see all three workflows
//   And the URL is "/projects/<project_id>/w?sort=name&dir=asc"
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  // "sync" stands in for "api": it narrows this project's list to one row
  await signInAs(page, ME);
  await open(page, workflowsPath(h.project.id, 'q=sync'));
  await expect(workflowRow(page, 'Sync DHIS2')).toBeVisible();
  await expect(workflowRow(page, 'Intake')).toHaveCount(0);

  await clearWorkflowSearch(page);

  await expect
    .poll(() => listedWorkflows(page))
    .toEqual(['Intake', 'Sync DHIS2', 'Weekly report']);
  await expectAt(page, `/projects/${h.project.id}/w`);
  expect(queryOf(page)).toEqual({ sort: 'name', dir: 'asc' });
});

// @S07
// Scenario: A project with no workflows invites the first one
//   Given project "Empty" has no workflows
//   When I open its workflows page
//   Then I see "No workflows found. Create one to start automating."
//   And "Create one" links to the new workflow page
test('@S07', { tag: '@passing-old' }, async ({ page }) => {
  const project = given('Empty', { [ME]: 'viewer' });

  await signInAs(page, ME);
  await open(page, workflowsPath(project.id));

  await expect(
    page.getByText(/No workflows found\.\s+Create one\s+to start automating\./)
  ).toBeVisible();
  await expect(page.getByRole('link', { name: 'Create one' })).toHaveAttribute(
    'href',
    `/projects/${project.id}/w/new`
  );
});

// @S08
// Scenario Outline: Sorting by a column
//   When I click the "<column>" header
//   Then the list is sorted ascending by <column>
//   And the URL query has "sort=<key>&dir=asc"
//   When I click the "<column>" header again
//   Then the list is sorted descending by <column>
//   Examples:
//     | column                        | key                       |
//     | Name                          | name                      |
//     | Latest Work Order             | last_workorder_updated_at |
//     | Work Orders                   | workorders_count          |
//     | Work Orders in a failed state | failed_workorders_count   |
//     | Enabled                       | enabled                   |
test('@S08', { tag: '@passing-old' }, async ({ page }) => {
  // "Intake": 3 work orders, 1 failed, the latest 50 minutes ago.
  // "Sync DHIS2": 2 work orders, both failed, the latest a day ago.
  // "Weekly report": no work orders, and its trigger is off.
  const h = givenWorkflows(
    'Malawi HIV',
    { [ME]: 'viewer' },
    {
      weekly: { triggers: 'off' },
    }
  );
  succeeded(h.intake, 200);
  succeeded(h.intake, 100);
  failed(h.intake, 50);
  failed(h.sync, 1500);
  failed(h.sync, 1440);
  await signInAs(page, ME);

  const header = (name: string) =>
    page.getByRole('columnheader').getByRole('link', { name, exact: true });
  const expectSort = async (key: string, dir: string, order?: string[]) => {
    await expect.poll(() => queryOf(page)).toMatchObject({ sort: key, dir });
    if (order) await expect.poll(() => listedWorkflows(page)).toEqual(order);
  };
  const reversed = (order: string[]) => [...order].reverse();
  const columns: [string, string, string[], string][] = [
    // the first click sorts ascending, so each starts from another sort
    [
      'Name',
      'name',
      ['Intake', 'Sync DHIS2', 'Weekly report'],
      'sort=workorders_count&dir=desc',
    ],
    [
      'Latest Work Order',
      'last_workorder_updated_at',
      ['Weekly report', 'Sync DHIS2', 'Intake'],
      '',
    ],
    [
      'Work Orders',
      'workorders_count',
      ['Weekly report', 'Sync DHIS2', 'Intake'],
      '',
    ],
    [
      'Work Orders in a failed state',
      'failed_workorders_count',
      ['Weekly report', 'Intake', 'Sync DHIS2'],
      '',
    ],
  ];
  for (const [column, key, ascending, from] of columns) {
    await open(page, workflowsPath(h.project.id, from));
    await expect(workflowsHeading(page, 3)).toBeVisible();

    await header(column).click();
    await expectSort(key, 'asc', ascending);

    await header(column).click();
    await expectSort(key, 'desc', reversed(ascending));
  }

  // Enabled: the one workflow that is off goes first, then last
  await open(page, workflowsPath(h.project.id));
  await expect(workflowsHeading(page, 3)).toBeVisible();
  await header('Enabled').click();
  await expectSort('enabled', 'asc');
  await expect
    .poll(async () => (await listedWorkflows(page))[0])
    .toBe('Weekly report');
  await header('Enabled').click();
  await expectSort('enabled', 'desc');
  await expect
    .poll(async () => (await listedWorkflows(page))[2])
    .toBe('Weekly report');
});

// @S09
// Scenario: Search and sort combine and survive in the URL
//   When I open "/projects/<project_id>/w?q=api&sort=name&dir=desc"
//   Then I see only workflows matching "api", in reverse name order
test('@S09', { tag: '@passing-old' }, async ({ page }) => {
  const { project } = givenNamed(['Api import', 'Intake', 'Weekly api sync']);

  await signInAs(page, ME);
  await open(page, workflowsPath(project.id, 'q=api&sort=name&dir=desc'));

  await expect
    .poll(() => listedWorkflows(page))
    .toEqual(['Weekly api sync', 'Api import']);
});

// @S10
// Scenario: Unknown sort parameters fall back to the default
//   When I open "/projects/<project_id>/w?sort=bogus&dir=bogus"
//   Then the page loads sorted by name ascending
test('@S10', { tag: '@passing-old' }, async ({ page }) => {
  // Created in the opposite order, so only sorting by name puts them right
  const { project } = givenNamed(['Weekly report', 'Sync DHIS2', 'Intake']);

  await signInAs(page, ME);
  await open(page, workflowsPath(project.id, 'sort=bogus&dir=bogus'));

  await expect(workflowsHeading(page, 3)).toBeVisible();
  await expect
    .poll(() => listedWorkflows(page))
    .toEqual(['Intake', 'Sync DHIS2', 'Weekly report']);
});

// @S11
// Scenario: Editor switches a workflow on
//   Given I am an editor on project "Malawi HIV"
//   And "Intake" is a draft with its webhook trigger disabled
//   When I click the "Intake" switch
//   Then I see "Workflow updated"
//   And the "Intake" switch is on with tooltip "This workflow is active (webhook trigger enabled)"
//   And "Intake" is live with its trigger enabled
//   And an audit event "enabled" is recorded
//   And the flow "flow-toggle-workflow-open-editor" has started for "Intake"
// The flow is checked by its own flow test.
test('@S11', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const h = givenWorkflows(
    'Malawi HIV',
    { [ME]: 'editor' },
    {
      intake: { triggers: 'off' },
    }
  );
  await openWorkflows(page, h);
  const row = workflowRow(page, 'Intake');
  const toggle = workflowSwitch(row);
  const state = workflowSwitchInput(row);
  await expect(state).not.toBeChecked();

  await toggle.click();

  await expect(flashMessages.toast(page, 'Workflow updated')).toBeVisible();
  await expect(state).toBeChecked();
  await expectTooltip(
    page,
    toggle,
    'This workflow is active (webhook trigger enabled)'
  );
  expect(workflowStored(h.intake.id)).toMatchObject({
    state: 'live',
    triggers: [true],
  });
  await expect
    .poll(() => auditEventsOf(h.intake.id).map(e => e.event))
    .toContain('enabled');
});

// @S12
// Scenario: Editor switches a workflow off
//   Given I am an editor on project "Malawi HIV"
//   And "Intake" is live with its webhook trigger enabled
//   When I click the "Intake" switch
//   Then I see "Workflow updated"
//   And "Intake" is a draft with its trigger disabled
//   And the "Intake" switch is off with tooltip "This workflow is inactive (manual runs only)"
//   And an audit event "disabled" is recorded
test('@S12', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const h = givenWorkflows();
  await openWorkflows(page, h);
  const row = workflowRow(page, 'Intake');
  const toggle = workflowSwitch(row);
  const state = workflowSwitchInput(row);
  await expect(state).toBeChecked();

  await toggle.click();

  await expect(flashMessages.toast(page, 'Workflow updated')).toBeVisible();
  await expect(state).not.toBeChecked();
  await expectTooltip(
    page,
    toggle,
    'This workflow is inactive (manual runs only)'
  );
  expect(workflowStored(h.intake.id)).toMatchObject({
    state: 'draft',
    triggers: [false],
  });
  await expect
    .poll(() => auditEventsOf(h.intake.id).map(e => e.event))
    .toContain('disabled');
});

// @S13 @variant:activation-limited
// Scenario: The plan limit can refuse switching a workflow on
//   Given I am an editor on project "Malawi HIV"
//   And the usage limiter refuses workflow activation with "No more workflows"
//   And "Intake" has its trigger disabled
//   When I click the "Intake" switch
//   Then I see "No more workflows"
//   And "Intake" still has its trigger disabled
test('@S13', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const h = givenWorkflows(
    'Malawi HIV',
    { [ME]: 'editor' },
    { intake: { triggers: 'off' } }
  );
  cleanups.push(withRefusingLimiter('No more workflows'));
  await openWorkflows(page, h);

  await flip(page, 'Intake');

  await expect(flashMessages.toast(page, 'No more workflows')).toBeVisible();
  expect(workflowStored(h.intake.id).triggers).toEqual([false]);
});

// @S14 @variant:activation-limited
// Scenario: Re-confirming an already enabled workflow is not counted against the limit
//   Given the usage limiter refuses workflow activation
//   And "Sync DHIS2" has all its triggers enabled
//   When "toggle_workflow_state" is sent for "Sync DHIS2" with state true
//   Then I see "Workflow updated"
//   And the usage limiter was not consulted
// A refusing limiter would have answered "No more workflows", so "Workflow
// updated" shows it was not asked.
test('@S14', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const h = givenWorkflows();
  cleanups.push(withRefusingLimiter('No more workflows'));
  await openWorkflows(page, h);

  await sendEventFrom(page, 'Name', 'toggle_workflow_state', {
    workflow_state: 'true',
    value_key: h.sync.id,
  });

  await expect(flashMessages.toast(page, 'Workflow updated')).toBeVisible();
  await expect(flashMessages.toast(page, 'No more workflows')).toHaveCount(0);
  expect(workflowStored(h.sync.id).triggers).toEqual([true]);
});

// @S15
// Scenario: Viewer cannot switch a workflow
//   Given I am a viewer on project "Malawi HIV"
//   And "Intake" has its trigger disabled
//   When I click the "Intake" switch
//   Then I see "You are not authorized to perform this action."
//   And "Intake" still has its trigger disabled
test('@S15', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows(
    'Malawi HIV',
    { [ME]: 'viewer' },
    {
      intake: { triggers: 'off' },
    }
  );
  await openWorkflows(page, h);

  // The switch may be disabled, or refuse on click: either way nothing changes
  const toggle = workflowSwitch(workflowRow(page, 'Intake'));
  if (await toggle.isEnabled()) {
    await toggle.click();
    await expect(flashMessages.toast(page, NOT_AUTHORIZED)).toBeVisible();
  }
  // The server refuses the event whatever the page offers
  await expect(flashMessages.toast(page, NOT_AUTHORIZED)).toBeHidden({
    timeout: 8000,
  });
  await sendEventFrom(page, 'Name', 'toggle_workflow_state', {
    workflow_state: 'true',
    value_key: h.intake.id,
  });

  await expect(flashMessages.toast(page, NOT_AUTHORIZED)).toBeVisible();
  expect(workflowStored(h.intake.id)).toMatchObject({
    state: 'draft',
    triggers: [false],
  });
});

// @S16
// Scenario Outline: Actions on a workflow outside the project are refused
//   Given I am an editor on project "Malawi HIV"
//   And workflow "Foreign" belongs to a project I am not on
//   When "<event>" is sent with the id of "Foreign"
//   Then I see "Workflow not found."
//   And "Foreign" is unchanged
//   Examples:
//     | event                 |
//     | toggle_workflow_state |
//     | delete_workflow       |
test('@S16', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  const kenya = given('Kenya TB', { [OTHER]: 'owner' });
  const foreign = seedDashboardWorkflow(kenya.id, 'Foreign');
  await openWorkflows(page, h);

  const refused = flashMessages.toast(page, 'Workflow not found.');
  const events: [string, Record<string, string>][] = [
    // "false" would switch it off if the id were accepted
    [
      'toggle_workflow_state',
      { workflow_state: 'false', value_key: foreign.id },
    ],
    ['delete_workflow', { id: foreign.id }],
  ];
  for (const [event, values] of events) {
    await sendEventFrom(page, 'Name', event, values);

    await expect(refused).toBeVisible();
    expect(workflowStored(foreign.id)).toEqual({
      state: 'live',
      name: 'Foreign',
      deleted_at: null,
      triggers: [true],
    });
    // The next refusal must be a new toast, not this one
    await expect(refused).toBeHidden({ timeout: 8000 });
  }
});

// @S17
// Scenario: Editor deletes a workflow
//   Given I am an editor on project "Malawi HIV"
//   When I click "Delete" on "Weekly report"
//   And I confirm "Are you sure you'd like to delete this workflow?"
//   Then I see "Workflow successfully deleted."
//   And "Weekly report" is no longer listed
//   And every trigger of "Weekly report" is disabled
//   And an audit event "marked_for_deletion" is recorded with me as actor
//   And the flow "flow-delete-open-workflow" has started for "Weekly report"
// The flow is checked by its own flow test.
test('@S17', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const h = givenWorkflows();
  await openWorkflows(page, h);

  const asked = confirmNextPrompt(page);
  await workflowRow(page, 'Weekly report')
    .getByText('Delete', { exact: true })
    .click();
  expect(await asked).toBe("Are you sure you'd like to delete this workflow?");

  await expect(
    flashMessages.toast(page, 'Workflow successfully deleted.')
  ).toBeVisible();
  await expect(workflowRow(page, 'Weekly report')).toHaveCount(0);
  const stored = workflowStored(h.weekly.id);
  expect(stored.deleted_at).not.toBeNull();
  expect(stored.triggers).toEqual([false]);
  await expect
    .poll(
      () =>
        auditEventsOf(h.weekly.id).find(e => e.event === 'marked_for_deletion')
          ?.actor_id
    )
    .toBe(user(ME).id);
});

// @S18
// Scenario: A deleted workflow's name can be reused
//   Given I deleted "Weekly report"
//   Then no active workflow in the project holds the name "Weekly report"
test('@S18', { tag: '@passing-old' }, () => {
  const h = givenWorkflows();
  deleteWorkflowOnNode(h.weekly.id, ME);

  expect(
    sql(
      `select id from workflows where project_id = '${h.project.id}' and name = 'Weekly report' and deleted_at is null`
    )
  ).toEqual([]);
  // A new workflow can take the name (changeset and index both allow it)
  expect(() =>
    createWorkflowOnNode(h.project.id, 'Weekly report', ME)
  ).not.toThrow();
});

// @S19
// Scenario: Viewer cannot delete a workflow
//   Given I am a viewer on project "Malawi HIV"
//   When I open the workflows page
//   Then I see no "Delete" action on any row
//   When "delete_workflow" is sent for "Intake"
//   Then I see "You are not authorized to perform this action."
test('@S19', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows('Malawi HIV', { [ME]: 'viewer' });
  await openWorkflows(page, h);

  await expect(workflowsHeading(page, 3)).toBeVisible();
  await expect(
    page.locator('tr').getByText('Delete', { exact: true })
  ).toHaveCount(0);

  await sendEventFrom(page, 'Name', 'delete_workflow', { id: h.intake.id });

  await expect(flashMessages.toast(page, NOT_AUTHORIZED)).toBeVisible();
  expect(workflowStored(h.intake.id).deleted_at).toBeNull();
});

// @S20
// Scenario: Viewer sees the create button disabled with a reason
//   Given I am a viewer on project "Malawi HIV"
//   When I open the workflows page
//   Then the "Create new workflow" button is disabled
//   And it has the tooltip "You are not authorized to perform this action."
test('@S20', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows('Malawi HIV', { [ME]: 'viewer' });
  await openWorkflows(page, h);

  await expect(createWorkflowButton(page)).toBeDisabled();
  await hoverDisabled(createWorkflowButton(page));
  await expect(
    page.getByRole('tooltip').filter({ hasText: NOT_AUTHORIZED })
  ).toBeVisible();
});

// @S21
// Scenario: Editor starts a new workflow
//   Given I am an editor on project "Malawi HIV"
//   When I click "Create new workflow"
//   Then I am on "/projects/<project_id>/w/new"
test('@S21', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  await openWorkflows(page, h);
  await expect(createWorkflowButton(page)).toBeEnabled();

  await createWorkflowButton(page).click();

  await expectAt(page, `/projects/${h.project.id}/w/new`);
});

// @S22
// Scenario: Clicking a workflow name opens it in the editor
//   When I click "Intake"
//   Then I am on "/projects/<project_id>/w/<intake_id>"
test('@S22', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  await openWorkflows(page, h);

  await workflowRow(page, 'Intake')
    .getByText('Intake', { exact: true })
    .click();

  await expectAt(page, `/projects/${h.project.id}/w/${h.intake.id}`);
});

// @S23
// Scenario: Each row links to the workflow's health page
//   Then the "Intake" row has a "Health" link to "/projects/<project_id>/w/<intake_id>/health"
test('@S23', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  await openWorkflows(page, h);
  const health = workflowRow(page, 'Intake').getByRole('link', {
    name: 'Health',
    exact: true,
  });

  await expect(health).toHaveAttribute(
    'href',
    healthPath(h.project.id, h.intake.id)
  );
  await health.click();
  await expectAt(page, healthPath(h.project.id, h.intake.id));
});

// @S24
// Scenario: Counts link to the work orders behind them
//   Given "Intake" had 4 work orders in the last 30 days, 1 of them failed
//   Then the "Intake" work order count links to history filtered by workflow "Intake" and the last 30 days
//   And the "Intake" failed count links to history filtered by workflow "Intake", the last 30 days and every failure state
//   And the "Work Orders" card's pending link filters pending and running work orders in the last 30 days
//   And the failed card's "View all" link filters every failure state in the last 30 days
//   And the flow "flow-dashboard-history-drilldown" starts from each link
// Each link is followed and History's list is read; the flow is checked by its
// own flow test.
test('@S24', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  const fine = [300, 200, 100].map(minutes => succeeded(h.intake, minutes));
  const broken = failed(h.intake, 10);
  // Outside the last 30 days, and another workflow's
  const old = longAgo(h.intake);
  const syncFailed = failed(h.sync, 20);
  const syncCrashed = failed(h.sync, 30, 'crashed');
  const syncWaiting = waiting(h.sync, 40);
  const syncRunning = seedHistoryOrder(h.sync, {
    state: 'running',
    minutesAgo: 50,
    runs: [{ state: 'started' }],
  }).id;
  const everyOther = (...except: string[]) =>
    [
      ...fine,
      broken,
      old,
      syncFailed,
      syncCrashed,
      syncWaiting,
      syncRunning,
    ].filter(id => !except.includes(id));
  const intake = workflowRow(page, 'Intake');
  const followed = async (link: () => Locator) => {
    await open(page, h.path);
    await expect(workflowsHeading(page, 3)).toBeVisible();
    await link().click();
    await historyLoaded(page);
  };
  await signInAs(page, ME);

  await followed(() => workflowCell(intake, 'count').getByRole('link'));
  await expectHistoryLists(
    page,
    [...fine, broken],
    everyOther(...fine, broken)
  );

  await followed(() => workflowCell(intake, 'failed').getByRole('link'));
  await expectHistoryLists(page, [broken], everyOther(broken));

  await followed(() =>
    metricCard(page, 'Work Orders').getByRole('link', { name: /pending$/ })
  );
  await expectHistoryLists(
    page,
    [syncWaiting, syncRunning],
    everyOther(syncWaiting, syncRunning)
  );

  await followed(() =>
    metricCard(page, 'Work Orders in failed state').getByRole('link', {
      name: 'View all',
    })
  );
  await expectHistoryLists(
    page,
    [broken, syncFailed, syncCrashed],
    everyOther(broken, syncFailed, syncCrashed)
  );
});

// @S25
// Scenario: A workflow with no count has no history link
//   Given "Weekly report" has had no work orders in the last 30 days
//   Then the "Weekly report" row has no history link
test('@S25', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  longAgo(h.weekly);
  // Intake has some, so a link is possible on this page at all
  succeeded(h.intake, 10);
  failed(h.intake, 20);

  await openWorkflows(page, h);

  await expect(
    workflowCell(workflowRow(page, 'Intake'), 'count').getByRole('link')
  ).toHaveCount(1);
  const row = workflowRow(page, 'Weekly report');
  await expect(workflowCell(row, 'count').getByRole('link')).toHaveCount(0);
  await expect(workflowCell(row, 'failed').getByRole('link')).toHaveCount(0);
});

// @S26
// Scenario: A workflow with every trigger off is shown as disabled
//   Given "Intake" has all its triggers disabled
//   When I open the workflows page
//   Then the "Intake" name is greyed out with the tooltip "Intake (disabled)"
//   And the "Intake" switch is off with tooltip "This workflow is inactive (manual runs only)"
test('@S26', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows(
    'Malawi HIV',
    { [ME]: 'editor' },
    {
      intake: { triggers: 'off' },
    }
  );

  await openWorkflows(page, h);

  const name = (workflow: string) =>
    workflowRow(page, workflow).getByText(workflow, { exact: true });
  // Greyed out means it looks different from the name of a workflow that is on
  expect(await lookOf(name('Intake'))).not.toBe(
    await lookOf(name('Sync DHIS2'))
  );
  await expectTooltip(page, name('Intake'), 'Intake (disabled)');
  const row = workflowRow(page, 'Intake');
  const toggle = workflowSwitch(row);
  const state = workflowSwitchInput(row);
  await expect(state).not.toBeChecked();
  await expectTooltip(
    page,
    toggle,
    'This workflow is inactive (manual runs only)'
  );
});

// @S27 @variant:experimental-features
// Scenario: Lifecycle mode shows state instead of a switch
//   Given I have experimental features enabled
//   And "Intake" is live
//   When I open the workflows page of project "Malawi HIV"
//   Then the state column is headed "State"
//   And the "Intake" row shows "Live"
//   And no row has an on/off switch
test('@S27', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  setPreferences(ME, { experimental_features: true });

  await openWorkflows(page, h);

  await expect(
    page.getByRole('columnheader', { name: 'State', exact: true })
  ).toBeVisible();
  await expect(workflowRow(page, 'Intake')).toContainText('Live');
  await expect(page.getByRole('switch')).toHaveCount(0);
});

// @S28 @variant:experimental-features
// Scenario: Lifecycle mode keeps the switch inside a sandbox
//   Given I have experimental features enabled
//   And I own sandbox "dev" with a workflow
//   When I open the workflows page of sandbox "dev"
//   Then the state column is headed "Turn on"
//   And each row has an on/off switch
test('@S28', { tag: '@passing-old' }, async ({ page }) => {
  const parent = given('Malawi HIV', { [ME]: 'editor' });
  const dev = given('dev', { [ME]: 'owner' });
  exec(`update projects set parent_id = '${parent.id}' where id = '${dev.id}'`);
  seedDashboardWorkflow(dev.id, 'Intake');
  seedDashboardWorkflow(dev.id, 'Sync DHIS2');
  setPreferences(ME, { experimental_features: true });

  await signInAs(page, ME);
  await open(page, workflowsPath(dev.id));

  await expect(
    page.getByRole('columnheader', { name: 'Turn on', exact: true })
  ).toBeVisible();
  await expect(page.getByRole('switch')).toHaveCount(2);
});

// @S29
// Scenario: Without experimental features the column is "Enabled" with a switch
//   Given I do not have experimental features enabled
//   When I open the workflows page
//   Then the state column is headed "Enabled"
//   And each row has an on/off switch
test('@S29', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenWorkflows();
  setPreferences(ME, { experimental_features: false });

  await openWorkflows(page, h);

  await expect(
    page.getByRole('columnheader', { name: 'Enabled', exact: true })
  ).toBeVisible();
  await expect(page.getByRole('switch')).toHaveCount(3);
});

// Inherited from shared-authenticated-session, on the workflows page.
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on workflows-index',
    { tag: tagFor('S01', ['S01', 'S02', 'S03', 'S07']) },
    async ({ page }) => {
      await authenticatedSession.S01(page, givenWorkflows().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on workflows-index',
    { tag: tagFor('S02', ['S01', 'S02', 'S03', 'S07']) },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, givenWorkflows().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on workflows-index',
    { tag: tagFor('S03', ['S01', 'S02', 'S03', 'S07']) },
    async ({ page }) => {
      await authenticatedSession.S03(page, givenWorkflows().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on workflows-index',
    { tag: tagFor('S07', ['S01', 'S02', 'S03', 'S07']) },
    async ({ page, browser }) => {
      const h = givenWorkflows();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.project.id}/history`,
        ME,
        'History'
      );
    }
  );

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
      `shared-authenticated-session@${id} on workflows-index`,
      { tag: tagFor(id, ['S01', 'S02', 'S03', 'S07']) },
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

// Inherited from shared-project-scope, on the workflows page.
test.describe('shared-project-scope', () => {
  test(
    'shared-project-scope@S01 on workflows-index',
    {
      tag: tagFor('S01', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      await projectScope.S01(page, givenWorkflows().path);
    }
  );

  test(
    'shared-project-scope@S02 on workflows-index',
    {
      tag: tagFor('S02', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows();
      await projectScope.S02(page, h.path, ME, workflowsHeading(page));
    }
  );

  test(
    'shared-project-scope@S03 on workflows-index',
    {
      tag: tagFor('S03', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows('Malawi HIV', { [OTHER]: 'owner' });
      await projectScope.S03(page, h.path, ME);
    }
  );

  test(
    'shared-project-scope@S04 on workflows-index',
    {
      tag: tagFor('S04', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.project.id}'`
      );
      await projectScope.S04(page, h.path, OTHER);
    }
  );

  test(
    'shared-project-scope@S05 on workflows-index',
    {
      tag: tagFor('S05', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows();
      exec(
        `update projects set requires_mfa = true where id = '${h.project.id}'`
      );
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on workflows-index',
    {
      tag: [
        tagFor('S06', [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
        ]),
        '@serial',
      ],
    },
    async ({ page }) => {
      const h = givenWorkflows('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.project.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, workflowsHeading(page));
    }
  );

  test(
    'shared-project-scope@S07 on workflows-index',
    {
      tag: tagFor('S07', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows('Malawi HIV', {
        [ME]: 'editor',
        [OTHER]: 'owner',
      });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.project.id, ME, OTHER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on workflows-index',
    {
      tag: tagFor('S08', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows('Malawi HIV', {
        [ME]: 'admin',
        [OTHER]: 'owner',
      });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.project.id, ME, 'viewer'),
        workflowsHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on workflows-index',
    {
      tag: [
        tagFor('S09', [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
        ]),
        '@serial',
      ],
    },
    async ({ page }) => {
      const h = givenWorkflows('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.project.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S09(page, h.path, ME, () =>
        setSupportAccessOnNode(h.project.id, false)
      );
    }
  );

  test(
    'shared-project-scope@S10 on workflows-index',
    {
      tag: tagFor('S10', [
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows('Malawi HIV', {
        [ME]: 'editor',
        [OTHER]: 'owner',
      });
      await projectScope.S10(page, h.path, ME, () =>
        scheduleDeletionOnNode(h.project.id)
      );
    }
  );

  // shared-project-scope S11 and S12 are not run on this page:
  // not_reachable_here does not exclude them, but the page holds no workflow
  // open (it sets no current_workflow_id), so the workflow deleted event does
  // nothing here, and an archived sandbox sends it to the parent's workflow
  // list with the flash "Sandbox archived.", not to an editor (hooks.ex).
});

// Inherited from shared-usage-limits-banner: the page renders the banner slot.
test.describe('shared-usage-limits-banner', () => {
  test(
    'shared-usage-limits-banner@S01 on workflows-index',
    { tag: tagFor('S01', ['S02']) },
    () => {
      test.skip(
        true,
        'variant usage-limited is not configured on this instance'
      );
    }
  );

  test(
    'shared-usage-limits-banner@S02 on workflows-index',
    { tag: tagFor('S02', ['S02']) },
    async ({ page }) => {
      const h = givenWorkflows();
      await usageLimitsBanner.S02(page, h.path, ME, workflowsHeading(page));
    }
  );
});

// Inherited from shared-project-header: the breadcrumbs, picker and side menu
// on the workflows page. The picker scenarios seed their own "Malawi HIV", so
// the project this page belongs to has another name.
test.describe('shared-project-header', () => {
  const HOST = 'Workflows host';

  // shared-project-header S01 is not run on this page: it checks the crumbs
  // after the picker, and this page has none (its breadcrumbs are the picker
  // alone), so there is no last crumb to check.

  test(
    'shared-project-header@S02 on workflows-index',
    {
      tag: tagFor('S02', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows(HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on workflows-index',
    {
      tag: tagFor('S03', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    async ({ page }) => {
      const parent = given(HOST, { [ME]: 'editor' });
      const sandbox = given('dev', { [ME]: 'editor' });
      exec(`update projects set parent_id = '${parent.id}', color = '#E33D63'
            where id = '${sandbox.id}'`);
      await projectHeader.S03(page, ME, {
        path: workflowsPath(sandbox.id),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on workflows-index`,
      {
        tag: tagFor(id, [
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ]),
      },
      async ({ page }) => {
        const h = givenWorkflows(HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on workflows-index',
    {
      tag: [
        tagFor('S07', [
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ]),
        '@serial',
      ],
    },
    async ({ page }) => {
      const h = givenWorkflows(HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // shared-project-header S09 starts on a project settings page, whatever
  // page hosts the header (see the shared step)
  test(
    'shared-project-header@S09 on workflows-index',
    {
      tag: tagFor('S09', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // The Examples row "the projects list or my profile | the workflows page":
  // this page is the workflows page, and the picker lands on the other
  // project's
  test(
    'shared-project-header@S10 on workflows-index',
    {
      tag: tagFor('S10', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows(HOST);
      await projectHeader.S10(page, h.path, ME, '/w');
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on workflows-index`,
      {
        tag: tagFor(id, [
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ]),
      },
      async ({ page }) => {
        const h = givenWorkflows(HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test(
    'shared-project-header@S14 on workflows-index',
    {
      tag: tagFor('S14', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );

  // This page highlights "Workflows" in the side menu
  test(
    'shared-project-header@S15 on workflows-index',
    {
      tag: tagFor('S15', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows(HOST);
      await projectHeader.S15(page, h.path, ME, h.project.id, 'Workflows');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on workflows-index',
    {
      tag: tagFor('S16', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows(HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  test(
    'shared-project-header@S17 on workflows-index',
    {
      tag: tagFor('S17', [
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10',
        'S11',
        'S12',
        'S13',
        'S15',
        'S16',
        'S17',
        'S18',
      ]),
    },
    async ({ page }) => {
      const h = givenWorkflows(HOST, {
        [ME]: 'viewer',
        'super@openfn.org': 'viewer',
      });
      await projectHeader.S17(page, h.path);
    }
  );
});

// Inherited from shared-local-datetime: the "Latest Work Order" column.
test.describe('shared-local-datetime', () => {
  // Given "Intake"'s latest work order was last changed at <utc> (it is
  // recent as far as the 30 day window goes), and today is <today>
  async function latestWorkOrder(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    const h = givenWorkflows();
    const id = succeeded(h.intake, 5);
    exec(`update work_orders set updated_at = '${utc}' where id = '${id}'`);
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, h.path);
    return workflowCell(workflowRow(page, 'Intake'), 'latest');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on workflows-index',
      { tag: tagFor('S01', ['S01', 'S02', 'S04', 'S05', 'S06']) },
      async ({ page }) => {
        await localDatetime.S01(
          page,
          await latestWorkOrder(page, localDatetime.given.S01)
        );
      }
    );
  });

  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on workflows-index`,
      { tag: tagFor(id, ['S01', 'S02', 'S04', 'S05', 'S06']) },
      async ({ page }) => {
        await localDatetime[id](
          page,
          await latestWorkOrder(page, localDatetime.given[id])
        );
      }
    );

  // shared-local-datetime S03 and S07 are not run on this page:
  // not_reachable_here does not exclude them, but every timestamp here uses
  // the default format (never relative_detailed), and a timestamp is only
  // shown for a work order that exists, so none is ever missing.
});

// Inherited from shared-flash-messages. The page puts the flashes "Workflow
// updated" (info) and "You are not authorized to perform this action."
// (error) itself, and shows the one the editor sends it after a workflow is
// deleted.
test.describe('shared-flash-messages', () => {
  // Given "Intake" is off, and I switch it on
  const INFO = 'Workflow updated';
  async function givenSwitchable(page: Page, role: 'editor' | 'viewer') {
    const h = givenWorkflows(
      'Malawi HIV',
      { [ME]: role },
      {
        intake: { triggers: 'off' },
      }
    );
    await openWorkflows(page, h);
    return { h, switchOn: () => flip(page, 'Intake') };
  }

  test(
    'shared-flash-messages@S01 on workflows-index',
    { tag: tagFor('S01', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06']) },
    async ({ page }) => {
      const { switchOn } = await givenSwitchable(page, 'editor');
      await flashMessages.S01(page, INFO, switchOn);
    }
  );

  test(
    'shared-flash-messages@S02 on workflows-index',
    { tag: tagFor('S02', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06']) },
    async ({ page }) => {
      const { switchOn } = await givenSwitchable(page, 'viewer');
      await flashMessages.S02(page, NOT_AUTHORIZED, switchOn);
    }
  );

  test(
    'shared-flash-messages@S03 on workflows-index',
    { tag: tagFor('S03', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06']) },
    async ({ page }) => {
      const { switchOn } = await givenSwitchable(page, 'editor');
      await flashMessages.S03(page, INFO, switchOn);
    }
  );

  test(
    'shared-flash-messages@S04 on workflows-index',
    { tag: tagFor('S04', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06']) },
    async ({ page }) => {
      const { switchOn } = await givenSwitchable(page, 'editor');
      await flashMessages.S04(page, INFO, switchOn, async () => {
        // Sorting makes the list render again
        await page
          .getByRole('columnheader')
          .getByRole('link', { name: 'Name' })
          .click();
        await expect.poll(() => queryOf(page).dir).toBe('desc');
      });
    }
  );

  // Given I have the health page of "Intake" open and another user deletes
  // it: the workflow list I land on shows the info flash "Workflow deleted."
  test(
    'shared-flash-messages@S05 on workflows-index',
    { tag: tagFor('S05', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06']) },
    async ({ page }) => {
      const h = givenWorkflows();
      await signInAs(page, ME);
      await open(page, healthPath(h.project.id, h.intake.id));
      await expect(
        page.getByRole('heading', { name: 'Outcomes', exact: true })
      ).toBeVisible();

      await flashMessages.S05(
        page,
        'Workflow deleted.',
        () => Promise.resolve(deleteWorkflowOnNode(h.intake.id, OTHER)),
        `/projects/${h.project.id}/w`
      );
    }
  );

  test(
    'shared-flash-messages@S06 on workflows-index',
    { tag: tagFor('S06', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06']) },
    async ({ page }) => {
      const h = givenWorkflows();
      const notMine = givenWorkflows('Kenya TB', { [OTHER]: 'owner' });
      await openWorkflows(page, h);

      await flashMessages.S06(
        page,
        () => open(page, notMine.path),
        '/projects',
        // the list of my projects
        page.getByRole('cell', {
          name: manifest().projects[0].name,
          exact: true,
        })
      );
    }
  );

  // shared-flash-messages S07 and S08 are not run on this page:
  // not_reachable_here does not exclude them, but S07 is on admin pages
  // (settings layout) and S08 on the sign-in and account forms.
});
