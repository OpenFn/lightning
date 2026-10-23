// Scenarios from annotations/views/history-work-orders.md.
//
// Who's who: "I" is editor@openfn.org (Esther Editor), a member of the project
// each test seeds ("Malawi HIV") with its workflow "Daily sync" (jobs "Fetch"
// and "Load") and removes again; the role changes with the scenario. "Another
// user" is owner@openfn.org. Work orders, runs and steps are inserted straight
// into the database, so the page has exactly the history a scenario names.
// Every test also puts editor's account back as it found it.
import { randomUUID } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as runComponents from './shared/run-components';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  bulkAction,
  cancelRunButton,
  cancelWorkOrderButton,
  changeRoleOnNode,
  chip,
  chooseStatuses,
  chooseWorkflow,
  claimRun,
  clearChipButton,
  connectJobs,
  daysAgo,
  deleteJobOf,
  disabledRetry,
  elapsedOf,
  exec,
  expandWorkOrder,
  expectHistoryLists,
  expectHistoryOrder,
  exportButton,
  historyCell,
  historyLoaded,
  historyPath,
  historyRoot,
  historyRow,
  historyRun,
  historySearchBox,
  includeInSearch,
  inspectStepLink,
  keepAccount,
  listedWorkOrders,
  lockLogLines,
  manifest,
  markWorkflowDeleted,
  makeSupportUser,
  nearDate,
  obanJobsNaming,
  open,
  postWebhook,
  openHistory,
  otherSession,
  removeMemberOnNode,
  removeMfaOf,
  removeStepsOfJob,
  removeWorkflowData,
  rerunStepIcon,
  rerunStepNaming,
  retryButton,
  runLink,
  runStateOf,
  runTimestamp,
  runsOfWorkOrder,
  scheduleDeletionOnNode,
  searchHistory,
  seedHistoryOrder,
  seedLoggedWorkOrders,
  seedProject,
  seedWorkOrder,
  seedWorkOrders,
  seedWorkflow,
  selectAll,
  selectBox,
  sendEvent,
  setPreferences,
  setLastActivityAfter,
  setReceivedAfter,
  setSupportAccessOnNode,
  shortId,
  signInAs,
  sortHistoryBy,
  sql,
  stepRow,
  stepsOfRun,
  tagFor,
  tipOf,
  user,
  utcStamp,
  type HistoryRunSeed,
  type SeededWorkflow,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const RETRY_JOB = 'Lightning.WorkOrders.RetryManyWorkOrdersJob';
const CANCEL_JOB = 'Lightning.WorkOrders.CancelManyWorkOrdersJob';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Members = Parameters<typeof seedProject>[1];

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

// Given I am an editor on project "Malawi HIV"
// And workflow "Daily sync" has jobs "Fetch" and "Load"
function givenHistory(
  name = 'Malawi HIV',
  members: Members = { [ME]: 'editor' }
) {
  const project = given(name, members);
  const wf = seedWorkflow(project.id);
  return { project, wf, path: historyPath(project.id) };
}

const flash = (page: Page, text: string | RegExp) =>
  page
    .getByRole('alert')
    .or(page.getByRole('status'))
    .filter({ hasText: text });

// The runs of a work order that failed at "Load" after "Fetch" went well
const failedRun = (): HistoryRunSeed => ({
  state: 'failed',
  steps: [{ job: 'Fetch', exit: 'success' }, { job: 'Load' }],
});

// A run no worker has claimed
const waitingRun = (): HistoryRunSeed => ({ state: 'available' });

// Given work order(s) "W" has failed, with one run
function failedWorkOrder(wf: SeededWorkflow, minutesAgo = 60) {
  return seedHistoryOrder(wf, {
    state: 'failed',
    minutesAgo,
    runs: [failedRun()],
  });
}

// Given work order "W" is pending, its run waiting for a worker
function pendingWorkOrder(wf: SeededWorkflow, minutesAgo = 60) {
  return seedHistoryOrder(wf, {
    state: 'pending',
    minutesAgo,
    runs: [waitingRun()],
  });
}

// @S01
// Scenario: A bare visit shows the last 30 days of activity
//   Given I am a viewer on project "Malawi HIV"
//   And work order "A" had activity 5 days ago and work order "B" had activity 40 days ago
//   When I visit "/projects/<project_id>/history"
//   Then I see "A"
//   And I do not see "B"
//   And the last activity chip reads "Last activity after" a date 30 days ago
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory('Malawi HIV', { [ME]: 'viewer' });
  const a = seedWorkOrder(h.wf, { state: 'success', at: utcStamp(daysAgo(5)) });
  const b = seedWorkOrder(h.wf, {
    state: 'success',
    at: utcStamp(daysAgo(40)),
  });
  await signInAs(page, ME);

  await openHistory(page, h.project.id);

  await expectHistoryLists(page, [a], [b]);
  await expect(chip(page, /^Last activity/)).toContainText(/after/);
  await expect(chip(page, /^Last activity/)).toContainText(
    nearDate(daysAgo(30))
  );
});

// @S02
// Scenario: Work orders from other projects never appear
//   Given I am an editor on project "Malawi HIV"
//   And project "Kenya TB" has a work order "K"
//   When I open the history page of "Malawi HIV"
//   Then I do not see "K"
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  const members = { [ME]: 'editor', [OTHER]: 'owner' } as const;
  const h = givenHistory('Malawi HIV', members);
  const kenya = given('Kenya TB', members);
  const own = seedWorkOrder(h.wf, { state: 'success' });
  const k = seedWorkOrder(seedWorkflow(kenya.id), { state: 'success' });
  await signInAs(page, ME);

  await openHistory(page, h.project.id);

  await expectHistoryLists(page, [own], [k]);
});

// @S03
// Scenario: Filter by workflow
//   Given project "Malawi HIV" has workflows "Intake" and "Sync" with work orders
//   When I choose "Intake" from the workflow chip
//   Then the chip reads "Workflow is Intake"
//   And I only see work orders of "Intake"
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  const project = given('Malawi HIV', { [ME]: 'editor' });
  const intake = seedWorkOrder(seedWorkflow(project.id, 'Intake'), {
    state: 'success',
  });
  const sync = seedWorkOrder(seedWorkflow(project.id, 'Sync'), {
    state: 'success',
  });
  await signInAs(page, ME);
  await openHistory(page, project.id);
  await expectHistoryLists(page, [intake, sync], []);

  await chooseWorkflow(page, 'Intake');

  await expect(chip(page, /^Workflow is/)).toContainText('Workflow is Intake');
  await expectHistoryLists(page, [intake], [sync]);
});

// @S04
// Scenario: Filter by several statuses
//   Given project "Malawi HIV" has failed, crashed and successful work orders
//   When I tick "Failed" and "Crashed" in the status chip
//   Then the chip reads "Status in Failed, Crashed"
//   And I see only failed and crashed work orders
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const failed = seedWorkOrder(h.wf, { state: 'failed' });
  const crashed = seedWorkOrder(h.wf, { state: 'crashed' });
  const success = seedWorkOrder(h.wf, { state: 'success' });
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expectHistoryLists(page, [failed, crashed, success], []);

  await chooseStatuses(page, 'Failed', 'Crashed');

  await expect(chip(page, /^Status/)).toContainText(
    'Status in Failed, Crashed'
  );
  await expectHistoryLists(page, [failed, crashed], [success]);
});

// @S05
// Scenario: Filter by when the work order was received
//   Given work orders received on 1 March and 10 March
//   When I set "Received after" to 5 March
//   Then the received chip shows the range
//   And I see only the 10 March work order
// The dates are 20 and 10 days ago, and the bound is 15 days ago, so that all
// of them stay inside the page's 30 day window. The early work order had
// activity yesterday, so only a filter on the received date can leave it out.
test('@S05', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const early = seedWorkOrder(h.wf, {
    state: 'success',
    at: utcStamp(daysAgo(20)),
  });
  exec(`update work_orders set last_activity = now() at time zone 'utc' - interval '1 day'
        where id = '${early}'`);
  const late = seedWorkOrder(h.wf, {
    state: 'success',
    at: utcStamp(daysAgo(10)),
  });
  const bound = daysAgo(15).toISOString().slice(0, 10);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expectHistoryLists(page, [early, late], []);

  await setReceivedAfter(page, `${bound}T00:00`);

  await expect(chip(page, /^Received/)).toContainText(/after/);
  await expect(chip(page, /^Received/)).toContainText(
    nearDate(new Date(`${bound}T00:00:00Z`))
  );
  await expectHistoryLists(page, [late], [early]);
});

// @S06
// Scenario: Clearing a filter chip removes that filter
//   Given I have filtered by workflow "Intake"
//   When I clear the workflow chip
//   Then the chip reads "Workflow is any"
//   And I see work orders of every workflow
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  const project = given('Malawi HIV', { [ME]: 'editor' });
  const intakeWf = seedWorkflow(project.id, 'Intake');
  const intake = seedWorkOrder(intakeWf, { state: 'success' });
  const sync = seedWorkOrder(seedWorkflow(project.id, 'Sync'), {
    state: 'success',
  });
  await signInAs(page, ME);
  await openHistory(page, project.id, { workflow_id: intakeWf.id });
  await expect(chip(page, /^Workflow is/)).toContainText('Workflow is Intake');
  await expectHistoryLists(page, [intake], [sync]);

  await clearChipButton(chip(page, /^Workflow is/)).click();

  await expect(chip(page, /^Workflow is/)).toContainText('Workflow is any');
  await expectHistoryLists(page, [intake, sync], []);
});

// @S07
// Scenario: Search work orders by inputs and logs
//   Given work order "A" has an input containing "eliaswalyba"
//   And work order "B" has a log line containing "qassim"
//   When I search for "eliaswalyba" with inputs and logs included
//   Then I see "A" and not "B"
//   When I search for "qassim" with inputs and logs included
//   Then I see "B" and not "A"
test('@S07', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const a = seedHistoryOrder(h.wf, {
    state: 'success',
    runs: [
      {
        state: 'success',
        steps: [
          {
            job: 'Fetch',
            exit: 'success',
            input: { patient: { name: 'eliaswalyba' } },
          },
        ],
      },
    ],
  }).id;
  const b = seedHistoryOrder(h.wf, {
    state: 'success',
    runs: [
      {
        state: 'success',
        log: 'delivered the record of qassim',
        steps: [{ job: 'Fetch', exit: 'success' }],
      },
    ],
  }).id;
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await includeInSearch(page, 'inputs');

  await searchHistory(page, 'eliaswalyba');

  await expectHistoryLists(page, [a], [b]);

  await searchHistory(page, 'qassim');

  await expectHistoryLists(page, [b], [a]);
});

// @S08
// Scenario: A broad search tells me to narrow it
//   Given 60 work orders have logs containing "error"
//   When I search for "error" in run logs
//   Then I see '50+ work orders with runs matching "error"'
//   And I see "(try more specific filters)"
test('@S08', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  seedLoggedWorkOrders(h.wf, 60, 'error while sending the record');
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  await searchHistory(page, 'error');

  await expect(
    page.getByText('50+ work orders with runs matching "error"')
  ).toBeVisible();
  await expect(page.getByText('(try more specific filters)')).toBeVisible();
});

// @S09
// Scenario: Sort by created date and toggle direction
//   Given work orders created on 1, 2 and 3 March
//   When I click the "Created" column header
//   Then the newest is first
//   When I click it again
//   Then the oldest is first
// The page starts sorted by last activity, which here runs the other way
// round, so that the first click visibly changes the order.
test('@S09', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const [oldest, middle, newest] = [3, 2, 1].map(days =>
    seedWorkOrder(h.wf, { state: 'success', at: utcStamp(daysAgo(days)) })
  );
  [oldest, middle, newest].forEach((id, i) =>
    exec(`update work_orders set last_activity = now() at time zone 'utc' - interval '${(i + 1) * 10} minutes'
          where id = '${id}'`)
  );
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expectHistoryOrder(page, [oldest, middle, newest]);

  await sortHistoryBy(page, 'Created');

  await expectHistoryOrder(page, [newest, middle, oldest]);

  await sortHistoryBy(page, 'Created');

  await expectHistoryOrder(page, [oldest, middle, newest]);
});

// @S10
// Scenario: A link to one work order opens it expanded
//   Given work order "W" has two runs
//   When I visit the history page with "filters[workorder_id]" set to "W"
//   Then I see only "W"
//   And I see a chip "Work order: <short id of W>"
//   And both runs of "W" are shown
test('@S10', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = seedHistoryOrder(h.wf, {
    state: 'failed',
    runs: [failedRun(), failedRun()],
  });
  const other = seedWorkOrder(h.wf, { state: 'success' });
  await signInAs(page, ME);

  await openHistory(page, h.project.id, { workorder_id: w.id });

  await expectHistoryLists(page, [w.id], [other]);
  await expect(chip(page, /^Work order:/)).toContainText(
    `Work order: ${shortId(w.id)}`
  );
  await expect(runLink(page, w.runs[0].id)).toBeVisible();
  await expect(runLink(page, w.runs[1].id)).toBeVisible();
});

// @S11
// Scenario: Expanding a work order shows its latest run, and earlier runs on request
//   Given work order "W" has three runs
//   When I click its row
//   Then I see the latest run labelled "(3/3"
//   And I do not see the earlier runs
//   When I click "show previous"
//   Then I see all three runs
test('@S11', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = seedHistoryOrder(h.wf, {
    state: 'failed',
    runs: [failedRun(), failedRun(), failedRun()],
  });
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  await expandWorkOrder(page, w.id);

  await expect(runLink(page, w.runs[2].id)).toBeVisible();
  await expect(page.getByText('(3/3')).toBeVisible();
  await expect(runLink(page, w.runs[0].id)).toHaveCount(0);
  await expect(runLink(page, w.runs[1].id)).toHaveCount(0);

  await page.getByRole('link', { name: 'show previous' }).click();

  for (const run of w.runs) await expect(runLink(page, run.id)).toBeVisible();
});

// @S12
// Scenario: Steps carried over from an earlier run are marked
//   Given a run that was rerun from its second step
//   When I expand its work order
//   Then its first step is faded with a paperclip whose tooltip says it "was originally executed in a previous run"
test('@S12', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = seedHistoryOrder(h.wf, {
    state: 'failed',
    runs: [
      failedRun(),
      {
        state: 'failed',
        steps: [{ job: 'Fetch', carried: true }, { job: 'Load' }],
      },
    ],
  });
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  await expandWorkOrder(page, w.id);

  await runComponents.S06(
    page,
    stepRow(page, w.runs[1].steps.Fetch),
    stepRow(page, w.runs[1].steps.Load)
  );
});

// @S13
// Scenario: The workflow link opens the version the run executed
//   Given work order "W" ran on workflow version 3 and the workflow is now on version 5
//   When I look at the workflow name in the row
//   Then it links to the workflow editor with "run=<latest run id>" and "v=3"
// The workflow is renamed twice after the run, so it is two versions ahead.
test('@S13', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = seedHistoryOrder(h.wf, {
    state: 'failed',
    runs: [failedRun(), failedRun()],
  });
  h.wf.rename('Load', 'Load again');
  h.wf.rename('Fetch', 'Fetch again');
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  const link = historyCell(historyRow(page, w.id), 'Workflow').getByRole(
    'link'
  );

  await expect(link).toHaveAttribute('href', new RegExp(`/w/${h.wf.id}\\?`));
  const params = new URL((await link.getAttribute('href'))!, 'http://x')
    .searchParams;
  expect(params.get('run')).toBe(w.runs[1].id);
  expect(params.get('v')).toBe('0');
  expect(params.has('as_run')).toBe(false);
});

// @S14
// Scenario: With experimental features the workflow link pins the run itself
//   Given I have experimental features enabled
//   And work order "W" ran on an older workflow version
//   When I look at the workflow name in the row
//   Then it links with "run=<latest run id>" and "as_run=<latest run id>"
test('@S14', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = seedHistoryOrder(h.wf, {
    state: 'failed',
    runs: [failedRun(), failedRun()],
  });
  h.wf.rename('Load', 'Load again');
  setPreferences(ME, { experimental_features: true });
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  const link = historyCell(historyRow(page, w.id), 'Workflow').getByRole(
    'link'
  );

  await expect(link).toHaveAttribute('href', new RegExp(`/w/${h.wf.id}\\?`));
  const params = new URL((await link.getAttribute('href'))!, 'http://x')
    .searchParams;
  expect(params.get('run')).toBe(w.runs[1].id);
  expect(params.get('as_run')).toBe(w.runs[1].id);
  expect(params.has('v')).toBe(false);
});

// @S15
// Scenario: Editor retries a finished work order from the start
//   Given I am an editor and work order "W" has failed
//   When I click its retry button
//   Then I see "New run enqueued for 1 workorder"
//   And a retry of "W" is queued
test('@S15', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = failedWorkOrder(h.wf);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  await retryButton(historyRow(page, w.id)).click();

  await expect(flash(page, 'New run enqueued for 1 workorder')).toBeVisible();
  await expect
    .poll(() => obanJobsNaming(RETRY_JOB, w.id).length)
    .toBeGreaterThan(0);
});

// @S16
// Scenario: Editor reruns a run from a failed step
//   Given I am an editor and a run of work order "W" failed at step "Load"
//   When I expand "W" and click the rerun icon on "Load"
//   Then a new run for "W" is created starting at "Load"
//   And the steps before "Load" are carried over from the original run
test('@S16', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  connectJobs(h.wf, ['Fetch', 'Load']);
  const w = failedWorkOrder(h.wf);
  const [original] = w.runs;
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expandWorkOrder(page, w.id);

  await rerunStepIcon(page, original.steps.Load).click();

  await expect.poll(() => runsOfWorkOrder(w.id).length).toBe(2);
  const created = runsOfWorkOrder(w.id).find(run => run.id !== original.id)!;
  expect(created.starting_job_id).toBe(h.wf.jobs.Load);
  const carried = stepsOfRun(created.id);
  expect(carried).toContain(original.steps.Fetch);
  expect(carried).not.toContain(original.steps.Load);
});

// @S17
// Scenario: A run from another project cannot be rerun
//   Given I am an editor on project "Malawi HIV"
//   And run "R" belongs to project "Kenya TB"
//   When I send "rerun" for run "R"
//   Then I see "Run not found."
//   And no new run is created for "R"'s work order
test('@S17', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const own = failedWorkOrder(h.wf);
  const kenya = given('Kenya TB', { [OTHER]: 'owner' });
  const k = failedWorkOrder(seedWorkflow(kenya.id));
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expandWorkOrder(page, own.id);

  await rerunStepNaming(
    rerunStepIcon(page, own.runs[0].steps.Load),
    k.runs[0].id,
    k.runs[0].steps.Load
  );

  await expect(flash(page, 'Run not found.')).toBeVisible();
  expect(runsOfWorkOrder(k.id)).toHaveLength(1);
  expect(runsOfWorkOrder(own.id)).toHaveLength(1);
});

// @S18
// Scenario: Runs of a deleted workflow cannot be retried
//   Given work order "W" belongs to a deleted workflow
//   When I rerun a step of its run
//   Then I see "Runs for deleted workflows cannot be retried"
test('@S18', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = failedWorkOrder(h.wf);
  markWorkflowDeleted(h.wf);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expandWorkOrder(page, w.id);

  await rerunStepIcon(page, w.runs[0].steps.Load).click();

  await expect(
    flash(page, 'Runs for deleted workflows cannot be retried')
  ).toBeVisible();
  expect(runsOfWorkOrder(w.id)).toHaveLength(1);
});

// @S19
// Scenario: Viewers see no retry, cancel or export controls
//   Given I am a viewer on project "Malawi HIV" with a failed and a pending work order
//   When I open the history page
//   Then the retry icon is disabled with the tooltip "You are not authorized to start runs for this project."
//   And I do not see a cancel button
//   And I do not see the export button
test('@S19', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory('Malawi HIV', { [ME]: 'viewer' });
  const failed = failedWorkOrder(h.wf);
  const pending = pendingWorkOrder(h.wf);
  await signInAs(page, ME);

  await openHistory(page, h.project.id);

  await expectHistoryLists(page, [failed.id, pending.id], []);
  await expect(retryButton(historyRow(page, failed.id))).toHaveCount(0);
  await disabledRetry(page, failed.id).hover();
  await expect(page.getByRole('tooltip')).toContainText(
    'You are not authorized to start runs for this project.'
  );
  await expect(cancelWorkOrderButton(historyRow(page, pending.id))).toHaveCount(
    0
  );
  await expect(exportButton(page)).toHaveCount(0);
});

// @S20
// Scenario: Forged actions from a viewer are refused
//   Given I am a viewer on project "Malawi HIV"
//   When I send "bulk-rerun", "rerun", "cancel", "cancel-run", "bulk-cancel", "show-export-modal" or "confirm-export"
//   Then I see "You are not authorized to perform this action."
//   And no run, cancellation or export is created
// Each event names a real work order or run, so that one the page let through
// would do something.
test('@S20', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory('Malawi HIV', { [ME]: 'viewer' });
  const failed = failedWorkOrder(h.wf);
  const pending = pendingWorkOrder(h.wf);
  const [run] = failed.runs;
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expectHistoryLists(page, [failed.id, pending.id], []);

  const events: [string, Record<string, string>][] = [
    ['rerun', { run_id: run.id, step_id: run.steps.Load }],
    ['bulk-rerun', { type: 'single', workorder_id: failed.id }],
    ['cancel', { workorder_id: pending.id }],
    ['cancel-run', { run_id: pending.runs[0].id }],
    ['bulk-cancel', { type: 'all' }],
    ['show-export-modal', {}],
    ['confirm-export', {}],
  ];
  for (const [event, values] of events) {
    await sendEvent(page, event, values);

    const refused = flashMessages.toast(
      page,
      'You are not authorized to perform this action.'
    );
    await expect(refused, `${event} is refused`).toBeVisible();
    await refused.click();
    await expect(refused).toBeHidden();
  }

  expect(runsOfWorkOrder(failed.id)).toHaveLength(1);
  expect(runStateOf(pending.runs[0].id)).toBe('available');
  expect(obanJobsNaming(RETRY_JOB, failed.id)).toHaveLength(0);
  expect(obanJobsNaming(CANCEL_JOB, pending.id)).toHaveLength(0);
  expect(
    sql(`select id from project_files where project_id = '${h.project.id}'`)
  ).toHaveLength(0);
  await expect(page.getByText('Confirm history export')).toHaveCount(0);
});

// @S21
// Scenario: A work order whose input was wiped cannot be selected or retried
//   Given work order "W" has an input dataclip wiped by the retention policy
//   When I open the history page
//   Then the selection checkbox for "W" is disabled
//   And its input id is not a link
//   And its retry icon is disabled with a tooltip saying "no input data has been stored due to the data retention policy"
//   And selecting all work orders on the page leaves "W" unselected
test('@S21', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const wiped = seedHistoryOrder(h.wf, {
    state: 'failed',
    input: { wiped: true },
    runs: [failedRun()],
  });
  const kept = failedWorkOrder(h.wf);
  await signInAs(page, ME);

  await openHistory(page, h.project.id);

  const row = historyRow(page, wiped.id);
  await expect(selectBox(page, wiped.id)).toBeDisabled();
  await expect(historyCell(row, 'Input')).toContainText(
    shortId(wiped.dataclipId)
  );
  await expect(historyCell(row, 'Input').getByRole('link')).toHaveCount(0);
  await expect(
    historyCell(historyRow(page, kept.id), 'Input').getByRole('link')
  ).toHaveCount(1);
  await disabledRetry(page, wiped.id).hover();
  await expect(page.getByRole('tooltip')).toContainText(
    'no input data has been stored due to the data retention policy'
  );

  await selectAll(page).check();

  await expect(selectBox(page, kept.id)).toBeChecked();
  await expect(selectBox(page, wiped.id)).not.toBeChecked();
  // The checkbox beside a wiped input is a stand-in that is never ticked, so
  // what counts is what the page would retry
  await bulkAction(page, 'Retry').click();
  const rerunOne = page.getByRole('button', {
    name: /^Rerun 1 selected work order/,
  });
  await expect(rerunOne).toBeVisible();
  await expect(
    page.getByRole('button', { name: /^Rerun 2 selected work order/ })
  ).toHaveCount(0);
  await rerunOne.click();
  await expect
    .poll(() => obanJobsNaming(RETRY_JOB, kept.id).length)
    .toBeGreaterThan(0);
  expect(obanJobsNaming(RETRY_JOB, wiped.id)).toHaveLength(0);
});

// @S22
// Scenario: Retention tooltips point admins to the setting and others to an admin
//   Given work order "W" has a wiped input
//   When an admin hovers the disabled retry icon
//   Then the tooltip has a "Go to data storage settings" link to "/projects/<project_id>/settings#data-storage"
//   When an editor hovers it
//   Then the tooltip says "For more information, contact one of your project admins."
test('@S22', { tag: '@passing-old' }, async ({ page, browser }) => {
  const h = givenHistory('Malawi HIV', { [ME]: 'admin', [OTHER]: 'editor' });
  const w = seedHistoryOrder(h.wf, {
    state: 'failed',
    input: { wiped: true },
    runs: [failedRun()],
  });
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  await disabledRetry(page, w.id).hover();

  const adminTip = page.getByRole('tooltip');
  await expect(
    adminTip.getByRole('link', { name: 'Go to data storage settings' })
  ).toHaveAttribute('href', `/projects/${h.project.id}/settings#data-storage`);

  const editor = await otherSession(browser, OTHER);
  await openHistory(editor, h.project.id);
  await disabledRetry(editor, w.id).hover();
  const editorTip = editor.getByRole('tooltip');
  await expect(editorTip).toContainText(
    'For more information, contact one of your project admins.'
  );
  await expect(editorTip.getByRole('link')).toHaveCount(0);
  await editor.context().close();
});

// @S23
// Scenario: Selecting a whole page offers to retry every matching work order
//   Given 25 failed work orders match my filters
//   When I select all on the first page and click "Retry"
//   Then I see "Rerun 10 selected work orders from start"
//   And I see "Rerun all 25 matching work orders from start"
test('@S23', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  seedWorkOrders(h.wf, 'failed', 25);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  await selectAll(page).check();
  await bulkAction(page, 'Retry').click();

  await expect(
    page.getByRole('button', {
      name: 'Rerun 10 selected work orders from start',
    })
  ).toBeVisible();
  await expect(
    page.getByRole('button', {
      name: 'Rerun all 25 matching work orders from start',
    })
  ).toBeVisible();
});

// @S24
// Scenario: Bulk retry reports how many work orders were queued and how many were skipped
//   Given I selected three finished work orders, one of which belongs to a deleted workflow
//   When I confirm "Rerun 3 selected work orders from start"
//   Then I see "New runs enqueued for 2 workorders (1 were discarded due to wiped dataclip/workflow being deleted)"
//   And the page reloads with my filters
test('@S24', { tag: '@passing-old' }, async ({ page }) => {
  const project = given('Malawi HIV', { [ME]: 'editor' });
  const intake = seedWorkflow(project.id, 'Intake');
  const sync = seedWorkflow(project.id, 'Sync');
  const queued = [failedWorkOrder(intake).id, failedWorkOrder(intake).id];
  const skipped = seedHistoryOrder(sync, {
    state: 'failed',
    runs: [{ state: 'failed', steps: [{ job: 'Load' }] }],
  }).id;
  const finished = seedWorkOrder(intake, { state: 'success' });
  markWorkflowDeleted(sync);
  await signInAs(page, ME);
  // A filter the defaults don't have: only failed work orders
  await openHistory(page, project.id, { failed: 'true' });
  await expectHistoryLists(page, [...queued, skipped], [finished]);

  await selectAll(page).check();
  await bulkAction(page, 'Retry').click();
  await page
    .getByRole('button', { name: 'Rerun 3 selected work orders from start' })
    .click();

  await expect(
    flash(
      page,
      'New runs enqueued for 2 workorders (1 were discarded due to wiped dataclip/workflow being deleted)'
    )
  ).toBeVisible();
  await expect(chip(page, /^Status/)).toContainText('Failed');
  await expect(page).toHaveURL(/failed(%5D|\])=true/);
  await expectHistoryLists(page, [...queued, skipped], [finished]);
  for (const id of queued)
    await expect
      .poll(() => obanJobsNaming(RETRY_JOB, id).length)
      .toBeGreaterThan(0);
  expect(obanJobsNaming(RETRY_JOB, skipped)).toHaveLength(0);
});

// @S25
// Scenario: Rerun from a step is only offered for one workflow at a time
//   Given I selected finished work orders from workflows "Intake" and "Sync"
//   Then I do not see "Retry from"
//   When I unselect the "Sync" work orders
//   Then I see "Retry from"
test('@S25', { tag: '@passing-old' }, async ({ page }) => {
  const project = given('Malawi HIV', { [ME]: 'editor' });
  const intake = failedWorkOrder(seedWorkflow(project.id, 'Intake')).id;
  const sync = failedWorkOrder(seedWorkflow(project.id, 'Sync')).id;
  await signInAs(page, ME);
  await openHistory(page, project.id);
  await expectHistoryLists(page, [intake, sync], []);

  await selectAll(page).check();

  await expect(bulkAction(page, 'Retry')).toBeVisible();
  await expect(bulkAction(page, 'Retry from')).toHaveCount(0);

  await selectBox(page, sync).uncheck();

  await expect(bulkAction(page, 'Retry from')).toBeVisible();
});

// @S26
// Scenario: Steps with nothing to rerun are disabled in the rerun-from modal
//   Given the selected work orders' latest runs only have a usable input for job "Load"
//   When I open "Retry from"
//   Then every job of the workflow is listed
//   And every job except "Load" is disabled
//   When I choose "Load" and confirm
//   Then the selected work orders are rerun from "Load"
test('@S26', { tag: '@passing-old' }, async ({ page }) => {
  const project = given('Malawi HIV', { [ME]: 'editor' });
  const wf = seedWorkflow(project.id, 'Daily sync', [
    { name: 'Fetch', adaptor: '@openfn/language-http@latest' },
    { name: 'Transform', adaptor: '@openfn/language-common@latest' },
    { name: 'Load', adaptor: '@openfn/language-dhis2@latest' },
  ]);
  connectJobs(wf, ['Fetch', 'Transform', 'Load']);
  const orders = [1, 2].map(() =>
    seedHistoryOrder(wf, {
      state: 'failed',
      runs: [{ state: 'failed', steps: [{ job: 'Load' }] }],
    })
  );
  // The runs the orders start with; the rerun makes the others
  const original = new Set(orders.map(order => order.runs[0].id));
  await signInAs(page, ME);
  await openHistory(page, project.id);
  await selectAll(page).check();

  await bulkAction(page, 'Retry from').click();

  for (const job of ['Fetch', 'Transform', 'Load'])
    await expect(
      page.getByRole('radio', { name: job, exact: true })
    ).toBeVisible();
  await expect(
    page.getByRole('radio', { name: 'Fetch', exact: true })
  ).toBeDisabled();
  await expect(
    page.getByRole('radio', { name: 'Transform', exact: true })
  ).toBeDisabled();
  await expect(
    page.getByRole('radio', { name: 'Load', exact: true })
  ).toBeEnabled();

  await page.getByRole('radio', { name: 'Load', exact: true }).check();
  await page
    .getByRole('button', {
      name: 'Rerun 2 selected work orders from selected job',
    })
    .click();

  for (const order of orders) {
    await expect.poll(() => runsOfWorkOrder(order.id).length).toBe(2);
    const created = runsOfWorkOrder(order.id).filter(
      run => !original.has(run.id)
    );
    expect(created.map(run => run.starting_job_id)).toEqual([wf.jobs.Load]);
  }
});

// @S27
// Scenario: A mixed selection disables both bulk actions and says why
//   Given I selected one pending and one failed work order
//   Then the bulk "Cancel" button is disabled with "Cancel is only available when all selected work orders are pending"
//   And the bulk "Retry" button is disabled with "Retry is only available when all selected work orders have finished running"
test('@S27', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const pending = pendingWorkOrder(h.wf);
  const failed = failedWorkOrder(h.wf);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expectHistoryLists(page, [pending.id, failed.id], []);

  await selectAll(page).check();

  const cancelTip =
    'Cancel is only available when all selected work orders are pending';
  const retryTip =
    'Retry is only available when all selected work orders have finished running';
  await expect(bulkAction(page, 'Cancel')).toBeDisabled();
  await expect(bulkAction(page, 'Retry')).toBeDisabled();
  await tipOf(page, cancelTip).hover();
  await expect(page.getByRole('tooltip')).toContainText(cancelTip);
  await tipOf(page, retryTip).hover();
  await expect(page.getByRole('tooltip')).toContainText(retryTip);
});

// @S28
// Scenario: Editor cancels a pending work order
//   Given I am an editor and work order "W" is pending
//   When I click its cancel button
//   Then I see "Work order cancelled."
//   And its unclaimed run is cancelled
test('@S28', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = pendingWorkOrder(h.wf);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);

  await cancelWorkOrderButton(historyRow(page, w.id)).click();

  await expect(flash(page, 'Work order cancelled.')).toBeVisible();
  expect(runStateOf(w.runs[0].id)).toBe('cancelled');
});

// @S29
// Scenario: Cancelling never stops a run a worker has already claimed
//   Given work order "W" was pending when I loaded the page
//   And its run has since been claimed by a worker
//   When I click its cancel button
//   Then I see "Work order could not be cancelled"
//   And the run keeps its state
test('@S29', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = pendingWorkOrder(h.wf);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expect(cancelWorkOrderButton(historyRow(page, w.id))).toBeVisible();
  claimRun(w.runs[0].id);

  await cancelWorkOrderButton(historyRow(page, w.id)).click();

  await expect(flash(page, 'Work order could not be cancelled')).toBeVisible();
  expect(runStateOf(w.runs[0].id)).toBe('claimed');
});

// @S30
// Scenario: Editor cancels one enqueued run of a work order
//   Given work order "W" has an enqueued run "R"
//   When I expand "W" and click "Cancel this run" on "R"
//   Then I see "Run cancelled."
//   When I try the same on a run that has been claimed
//   Then I see "it is no longer available"
// The work order has two enqueued runs; the second is claimed after the page
// has loaded.
test('@S30', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const w = seedHistoryOrder(h.wf, {
    state: 'pending',
    runs: [waitingRun(), waitingRun()],
  });
  const [r, claimed] = w.runs;
  await signInAs(page, ME);
  await openHistory(page, h.project.id, { workorder_id: w.id });
  await expect(cancelRunButton(page, r.id)).toBeVisible();

  await cancelRunButton(page, r.id).click();

  await expect(flash(page, 'Run cancelled.')).toBeVisible();
  expect(runStateOf(r.id)).toBe('cancelled');
  await expect(historyRun(page, r.id)).toContainText('cancelled');

  claimRun(claimed.id);
  await cancelRunButton(page, claimed.id).click();

  await expect(flash(page, 'it is no longer available')).toBeVisible();
  expect(runStateOf(claimed.id)).toBe('claimed');
});

// @S31
// Scenario: Editor cancels selected pending work orders
//   Given I selected two pending work orders
//   When I click "Cancel" and confirm "Cancel up to 2 selected"
//   Then I see "Cancelled 2 runs"
test('@S31', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const orders = [pendingWorkOrder(h.wf), pendingWorkOrder(h.wf)];
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await selectAll(page).check();

  await bulkAction(page, 'Cancel').click();
  await page.getByRole('button', { name: 'Cancel up to 2 selected' }).click();

  await expect(flash(page, 'Cancelled 2 runs')).toBeVisible();
  for (const order of orders)
    expect(runStateOf(order.runs[0].id)).toBe('cancelled');
});

// @S32
// Scenario: Cancelling all matching work orders runs in the background
//   Given 3 pending work orders match my filters and I selected all of them
//   When I choose "Cancel up to 3 matching"
//   Then I see "Cancelling runs for 3 work orders in the background..."
//   And a background cancellation job is queued for those work orders
// Two to a page, so that selecting the page leaves one more that matches.
test('@S32', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const orders = [
    pendingWorkOrder(h.wf),
    pendingWorkOrder(h.wf),
    pendingWorkOrder(h.wf),
  ];
  await signInAs(page, ME);
  await openHistory(page, h.project.id, {}, { page_size: '2' });
  await selectAll(page).check();

  await bulkAction(page, 'Cancel').click();
  await page.getByRole('button', { name: 'Cancel up to 3 matching' }).click();

  await expect(
    flash(page, 'Cancelling runs for 3 work orders in the background...')
  ).toBeVisible();
  for (const order of orders)
    await expect
      .poll(() => obanJobsNaming(CANCEL_JOB, order.id).length)
      .toBeGreaterThan(0);
});

// @S33
// Scenario: Reruns over the plan limit are refused with the limiter's message
//   Given the usage limiter refuses new runs with "Runs limit exceeded"
//   When I rerun a step
//   Then I see the error "Runs limit exceeded"
//   And no run is created
// The limiter is application config, fixed when the e2e Lightning starts; a
// test cannot switch it on. Until that instance has a limiting variant, the
// ExUnit test "Project editors can't rerun when limit has been reached"
// (test/lightning_web/live/work_order_live_test.exs:1928) covers the refusal.
test('@S33', { tag: '@pending' }, () => {
  test.skip(true, 'variant usage-limited is not configured on this instance');
});

// @S34
// Scenario: The bulk retry button reports the plan limit instead of opening the modal
//   Given the usage limiter refuses the number of runs my selection would create, with "Runs limit exceeded"
//   When I click "Retry" for my selection
//   Then I see the error "Runs limit exceeded"
//   And the retry modal does not open
// Needs the same limiting instance as @S33, and no other test covers it. When
// there is one: select a finished work order, click bulkAction(page, 'Retry'),
// expect the flash "Runs limit exceeded" and no "Rerun ... from start" button.
test('@S34', { tag: '@pending' }, () => {
  test.skip(true, 'variant usage-limited is not configured on this instance');
});

// @S35
// Scenario: Editor starts a history export
//   Given I am an editor and 12 work orders match my filters
//   When I click the export button and confirm "Export history"
//   Then I see "History export started successfully. You will be notified by email after completion."
//   And the flow "flow-history-export" has started for my filters
// The export is an audit event, a file record and a background job. It mails
// the requester when done, which makes this scenario instance-wide.
test('@S35', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const h = givenHistory();
  cleanups.push(() =>
    exec(`delete from project_files where project_id = '${h.project.id}';
          delete from audit_events where item_id = '${h.project.id}'`)
  );
  seedWorkOrders(h.wf, 'success', 12);
  // More work orders in another workflow, which my filter leaves out
  const elsewhere = seedWorkflow(h.project.id, 'Other flow');
  seedWorkOrders(elsewhere, 'success', 5);
  await signInAs(page, ME);
  await openHistory(page, h.project.id, { workflow_id: h.wf.id });

  await exportButton(page).click();
  await expect(page.getByText(/all 12 work orders/)).toBeVisible();
  await page.getByRole('button', { name: 'Export history' }).click();

  await expect(
    flash(
      page,
      'History export started successfully. You will be notified by email after completion.'
    )
  ).toBeVisible();
  const requested = () =>
    sql(
      `select id from audit_events where item_id = '${h.project.id}'
       and item_type = 'history_export' and event = 'requested'`
    );
  await expect.poll(() => requested().length).toBe(1);
  expect(
    sql(
      `select id from project_files where project_id = '${h.project.id}'
       and created_by_id = '${user(ME).id}' and type = 'export'`
    )
  ).toHaveLength(1);
  // The queued job carries my filter: it names the workflow I filtered by
  const exportJob = 'Lightning.WorkOrders.ExportWorker';
  await expect
    .poll(() => obanJobsNaming(exportJob, h.wf.id).length)
    .toBeGreaterThan(0);
  expect(obanJobsNaming(exportJob, elsewhere.id)).toHaveLength(0);
});

// @S36
// Scenario: No export is offered when nothing matches
//   Given I am an editor and no work orders match my filters
//   Then I do not see the export button
test('@S36', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const emptyWf = seedWorkflow(h.project.id, 'Empty flow');
  seedWorkOrder(h.wf, { state: 'success' });
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expect(exportButton(page)).toBeVisible();

  await openHistory(page, h.project.id, { workflow_id: emptyWf.id });

  expect(await listedWorkOrders(page)).toEqual([]);
  await expect(exportButton(page)).toHaveCount(0);
});

// @S37
// Scenario: A failed search says so
//   Given the work order search fails or times out
//   When I open the history page
//   Then I see "There was an error loading the work orders"
// Another session holds the log lines table locked, so the search of run logs
// waits until the page gives up on it (30 seconds). That fails whatever the
// search term is, so it doesn't depend on how input is escaped. It locks a
// table every search reads, hence @serial.
test('@S37', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  test.setTimeout(120_000);
  const h = givenHistory();
  seedWorkOrder(h.wf, { state: 'success' });
  await signInAs(page, ME);
  cleanups.push(await lockLogLines());

  await open(
    page,
    historyPath(h.project.id, { search_term: 'error', log: 'true' })
  );

  await expect(
    page.getByText('There was an error loading the work orders')
  ).toBeVisible({ timeout: 60_000 });
});

// @S38
// Scenario: Filters from the health page show as chips that can be dropped
//   Given I arrive with "run_status[]=failed", "run_date_after" and "run_date_before" set
//   Then I see a chip "Run status: Failed"
//   And I see a chip starting "Run created" and ending "UTC"
//   When I clear the run status chip
//   Then the run created chip remains
test('@S38', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  await signInAs(page, ME);

  await openHistory(page, h.project.id, {
    run_status: ['failed'],
    run_date_after: '2026-10-20T14:00:00Z',
    run_date_before: '2026-10-20T16:00:00Z',
  });

  await expect(chip(page, 'Run status: Failed')).toBeVisible();
  await expect(chip(page, /^Run created .*UTC$/)).toBeVisible();

  await clearChipButton(chip(page, 'Run status: Failed')).click();

  await expect(page.getByRole('button', { name: /^Run status/ })).toHaveCount(
    0
  );
  await expect(chip(page, /^Run created .*UTC$/)).toBeVisible();
});

// @S39
// Scenario: The error signature chip doesn't reveal another project's job name
//   Given a link with "error_signature_job_id" set to a job in another project
//   When I open it
//   Then the error signature chip shows the short job id, not the job's name
// A job of this project shows its name, so the chip can tell the two apart.
test('@S39', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const kenya = given('Kenya TB', { [OTHER]: 'owner' });
  const secret = seedWorkflow(kenya.id, 'Kenya sync', [
    { name: 'Secret ledger sync', adaptor: '@openfn/language-http@latest' },
  ]);
  await signInAs(page, ME);

  await openHistory(page, h.project.id, {
    error_signature_exit_reason: 'fail',
    error_signature_job_id: h.wf.jobs.Load,
  });
  await expect(chip(page, /\bLoad\b/)).toBeVisible();

  await openHistory(page, h.project.id, {
    error_signature_exit_reason: 'fail',
    error_signature_job_id: secret.jobs['Secret ledger sync'],
  });

  await expect(
    chip(page, new RegExp(shortId(secret.jobs['Secret ledger sync'])))
  ).toBeVisible();
  await expect(page.getByText('Secret ledger sync')).toHaveCount(0);
});

// @S40
// Scenario: An unrecognised error signature matches nothing
//   Given a link with "error_signature_exit_reason" set to "rejected" and no job id
//   When I open it
//   Then I see no work orders
test('@S40', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const failed = failedWorkOrder(h.wf).id;
  await signInAs(page, ME);
  await openHistory(page, h.project.id, { workflow_id: h.wf.id });
  await expectHistoryLists(page, [failed], []);

  await openHistory(page, h.project.id, {
    error_signature_exit_reason: 'rejected',
  });

  expect(await listedWorkOrders(page)).toEqual([]);
});

// @S41
// Scenario: The channel logs tab appears only with experimental features
//   Given I have experimental features enabled
//   When I open the history page
//   Then I see tabs "Work orders" and "Channel logs"
//   And without experimental features I see no tabs
test('@S41', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  await signInAs(page, ME);

  await openHistory(page, h.project.id);

  await expect(page.getByRole('link', { name: 'Channel Logs' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Work Orders' })).toHaveCount(0);

  setPreferences(ME, { experimental_features: true });
  await openHistory(page, h.project.id);

  await expect(page.getByRole('link', { name: 'Work Orders' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Channel Logs' })).toBeVisible();
});

// @S42
// Scenario: The page listens for work order changes in the project
//   Given I have the history page open
//   When a work order or run in the project changes
//   Then the flow "flow-history-live-updates" ends on this page
// Another member cancels the pending work order from their own session, and
// then a webhook request makes a new work order.
test('@S42', { tag: '@passing-old' }, async ({ page, browser }) => {
  const h = givenHistory('Malawi HIV', { [ME]: 'viewer', [OTHER]: 'owner' });
  connectJobs(h.wf, ['Fetch', 'Load']);
  const w = pendingWorkOrder(h.wf);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expect(historyCell(historyRow(page, w.id), 'Status')).toHaveText(
    'Enqueued'
  );

  const other = await otherSession(browser, OTHER);
  await openHistory(other, h.project.id);
  await cancelWorkOrderButton(historyRow(other, w.id)).click();
  await expect(flash(other, 'Work order cancelled.')).toBeVisible();

  await expect(historyCell(historyRow(page, w.id), 'Status')).toHaveText(
    'Cancelled'
  );
  await other.context().close();

  await postWebhook(page, h.wf);

  await expect.poll(async () => (await listedWorkOrders(page)).length).toBe(2);
  const arrived = (await listedWorkOrders(page)).find(id => id !== w.id)!;
  await expect(historyCell(historyRow(page, arrived), 'Status')).toHaveText(
    'Enqueued'
  );
});

// @S43
// Scenario: Filter by last activity and sort by it
//   Given work order "A" received 20 days ago with last activity 2 days ago
//   And work order "B" received 14 days ago with last activity 13 days ago
//   When I set "Activity After" to 8 days ago
//   Then the last activity chip shows that date
//   And I see "A" and not "B"
//   When I clear the last activity chip, sort by "Created", then click the "Last Activity" column header
//   Then "A" is listed above "B"
//   When I click it again
//   Then "B" is listed above "A"
// Both were received before the bound, so a filter on the received date
// would leave out both. Sorting by created first puts "B" on top, so the
// first click on "Last Activity" visibly changes the order.
test('@S43', { tag: '@passing-old' }, async ({ page }) => {
  const h = givenHistory();
  const seed = (received: number, active: number) => {
    const id = seedWorkOrder(h.wf, {
      state: 'success',
      at: utcStamp(daysAgo(received)),
    });
    exec(`update work_orders set last_activity = now() at time zone 'utc' - interval '${active} days'
          where id = '${id}'`);
    return id;
  };
  const a = seed(20, 2);
  const b = seed(14, 13);
  const bound = daysAgo(8).toISOString().slice(0, 10);
  await signInAs(page, ME);
  await openHistory(page, h.project.id);
  await expectHistoryLists(page, [a, b], []);

  await setLastActivityAfter(page, `${bound}T00:00`);

  await expect(chip(page, /^Last activity/)).toContainText(
    nearDate(new Date(`${bound}T00:00:00Z`))
  );
  await expectHistoryLists(page, [a], [b]);

  await clearChipButton(chip(page, /^Last activity/)).click();
  await expectHistoryLists(page, [a, b], []);
  await sortHistoryBy(page, 'Created');
  await expectHistoryOrder(page, [b, a]);

  await sortHistoryBy(page, 'Last Activity');
  await expectHistoryOrder(page, [a, b]);

  await sortHistoryBy(page, 'Last Activity');
  await expectHistoryOrder(page, [b, a]);
});

const HOST = 'History host';

// Inherited from shared-authenticated-session, on the history page.
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S01(page, givenHistory().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, givenHistory().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S03(page, givenHistory().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      const h = givenHistory();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.project.id}/w`,
        ME,
        'History'
      );
    }
  );

  // The page renders the book-a-demo banner slot (S08 and S09), but these
  // variants need instance configuration the e2e Lightning does not have
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
      `shared-authenticated-session@${id} on history-work-orders`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

// Inherited from shared-project-scope, on the history page.
// S11 and S12 are not run: see the list at the end of this file.
test.describe('shared-project-scope', () => {
  test(
    'shared-project-scope@S01 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectScope.S01(page, givenHistory().path);
    }
  );

  test(
    'shared-project-scope@S02 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      await projectScope.S02(page, h.path, ME, historySearchBox(page));
    }
  );

  test(
    'shared-project-scope@S03 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory('Malawi HIV', { [OTHER]: 'owner' });
      await projectScope.S03(page, h.path, ME);
    }
  );

  test(
    'shared-project-scope@S04 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.project.id}'`
      );
      await projectScope.S04(page, h.path, OTHER);
    }
  );

  test(
    'shared-project-scope@S05 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      exec(
        `update projects set requires_mfa = true where id = '${h.project.id}'`
      );
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on history-work-orders',
    { tag: ['@passing-old', '@serial'] },
    async ({ page }) => {
      const h = givenHistory('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.project.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, historySearchBox(page));
    }
  );

  test(
    'shared-project-scope@S07 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory('Malawi HIV', {
        [ME]: 'editor',
        [OTHER]: 'owner',
      });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.project.id, ME, OTHER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory('Malawi HIV', { [ME]: 'admin', [OTHER]: 'owner' });
      await projectScope.S08(
        page,
        `${h.path}?page_size=5`,
        ME,
        () => changeRoleOnNode(h.project.id, ME, 'viewer'),
        historyRoot(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on history-work-orders',
    { tag: ['@passing-old', '@serial'] },
    async ({ page }) => {
      const h = givenHistory('Malawi HIV', { [OTHER]: 'owner' });
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
    'shared-project-scope@S10 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory('Malawi HIV', {
        [ME]: 'editor',
        [OTHER]: 'owner',
      });
      await projectScope.S10(page, h.path, ME, () =>
        scheduleDeletionOnNode(h.project.id)
      );
    }
  );
});

// Inherited from shared-usage-limits-banner: the page renders the banner slot
test.describe('shared-usage-limits-banner', () => {
  test(
    'shared-usage-limits-banner@S01 on history-work-orders',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant usage-limited is not configured on this instance'
      );
    }
  );

  test(
    'shared-usage-limits-banner@S02 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      await usageLimitsBanner.S02(page, h.path, ME, historySearchBox(page));
    }
  );
});

// Inherited from shared-project-header: the breadcrumbs, picker and side menu
// on the history page. The picker scenarios seed their own "Malawi HIV", so
// the project this page belongs to has another name.
test.describe('shared-project-header', () => {
  // shared-project-header S01 opens a run's page; the same breadcrumb
  // contract on this page ends in "History", which is no link
  test(
    'shared-project-header@S01 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory(HOST);
      await projectHeader.S01(page, h.path, ME, HOST, [{ name: 'History' }]);
    }
  );

  test(
    'shared-project-header@S02 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory(HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const parent = given(HOST, { [ME]: 'editor' });
      const sandbox = given('dev', { [ME]: 'editor' });
      exec(`update projects set parent_id = '${parent.id}', color = '#E33D63'
            where id = '${sandbox.id}'`);
      await projectHeader.S03(page, ME, {
        path: historyPath(sandbox.id),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on history-work-orders`,
      { tag: tagFor(id, ['S04', 'S05', 'S06', 'S08']) },
      async ({ page }) => {
        const h = givenHistory(HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on history-work-orders',
    { tag: ['@passing-old', '@serial'] },
    async ({ page }) => {
      const h = givenHistory(HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // shared-project-header S09 starts on a project settings page, whatever
  // page hosts the header (see the shared step)
  test(
    'shared-project-header@S09 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // shared-project-header S10: none of its Examples start on History, which
  // has an equivalent in every project. A History link that names a work
  // order of this project is the nearest case: its id exists only here, and
  // picking another project must land on that project's plain History.
  test(
    'shared-project-header@S10 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory(HOST);
      const w = failedWorkOrder(h.wf);
      await projectHeader.S10(
        page,
        historyPath(h.project.id, { workorder_id: w.id }),
        ME,
        '/history'
      );
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on history-work-orders`,
      { tag: tagFor(id, ['S11', 'S12', 'S13', 'S18']) },
      async ({ page }) => {
        const h = givenHistory(HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test(
    'shared-project-header@S14 on history-work-orders',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );

  // This page highlights "History" in the side menu
  test(
    'shared-project-header@S15 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory(HOST);
      await projectHeader.S15(page, h.path, ME, h.project.id, 'History');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory(HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  // A superuser needs a role on the project to open this page at all
  test(
    'shared-project-header@S17 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory(HOST, {
        [ME]: 'viewer',
        'super@openfn.org': 'viewer',
      });
      await projectHeader.S17(page, h.path);
    }
  );
});

// Inherited from shared-run-components: the state pill, step icons, durations,
// carried-over marker, version links, cancel and retention tooltips of the
// work order rows and the runs under them.
test.describe('shared-run-components', () => {
  // Given a workflow whose jobs have these names
  const jobsNamed = (...names: string[]) =>
    names.map(name => ({ name, adaptor: '@openfn/language-http@latest' }));

  // A work order has a state pill; a run is never "claimed" or "Starting" as a
  // work order, so that half of the scenario is only visible on the run page
  test(
    'shared-run-components@S01 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const labelled = [
        ['pending', 'Enqueued'],
        ['running', 'Running'],
        ['failed', 'Failed'],
      ] as const;
      const orders = labelled.map(([state]) => seedWorkOrder(h.wf, { state }));
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expectHistoryLists(page, orders, []);

      await runComponents.S01(
        page,
        orders.map((id, i) => [
          historyCell(historyRow(page, id), 'Status'),
          labelled[i][1],
        ])
      );
    }
  );

  test(
    'shared-run-components@S02 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const project = given('Malawi HIV', { [ME]: 'editor' });
      const wf = seedWorkflow(
        project.id,
        'Daily sync',
        jobsNamed('Fetch', 'Transform', 'Load')
      );
      const w = seedHistoryOrder(wf, {
        state: 'running',
        runs: [
          {
            state: 'started',
            steps: [
              { job: 'Fetch', exit: 'success' },
              { job: 'Transform', exit: 'fail' },
              { job: 'Load', exit: null },
            ],
          },
        ],
      });
      await signInAs(page, ME);
      await openHistory(page, project.id);
      await expandWorkOrder(page, w.id);

      const steps = w.runs[0].steps;
      await runComponents.S02(page, {
        pending: stepRow(page, steps.Load),
        success: stepRow(page, steps.Fetch),
        failed: stepRow(page, steps.Transform),
      });
    }
  );

  test(
    'shared-run-components@S03 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const project = given('Malawi HIV', { [ME]: 'editor' });
      const wf = seedWorkflow(
        project.id,
        'Daily sync',
        jobsNamed('Timeout', 'Security', 'Memory', 'Size')
      );
      const kill = (job: string, error: string) => ({
        job,
        exit: 'kill',
        error,
      });
      const w = seedHistoryOrder(wf, {
        state: 'killed',
        runs: [
          {
            state: 'killed',
            steps: [
              kill('Timeout', 'TimeoutError'),
              kill('Security', 'SecurityError'),
              kill('Memory', 'OOMError'),
              kill('Size', 'StateTooLargeError'),
            ],
          },
        ],
      });
      await signInAs(page, ME);
      await openHistory(page, project.id);
      await expandWorkOrder(page, w.id);

      const steps = w.runs[0].steps;
      await runComponents.S03(page, {
        timeout: stepRow(page, steps.Timeout),
        security: stepRow(page, steps.Security),
        oom: stepRow(page, steps.Memory),
        tooLarge: stepRow(page, steps.Size),
      });
    }
  );

  test(
    'shared-run-components@S04 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const w = seedHistoryOrder(h.wf, {
        state: 'running',
        runs: [
          {
            state: 'started',
            steps: [{ job: 'Fetch', exit: null, seconds: 20 }],
          },
        ],
      });
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expandWorkOrder(page, w.id);

      await runComponents.S04(
        page,
        elapsedOf(stepRow(page, w.runs[0].steps.Fetch))
      );
    }
  );

  test(
    'shared-run-components@S05 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const ran = seedHistoryOrder(h.wf, {
        state: 'success',
        runs: [
          {
            state: 'success',
            steps: [{ job: 'Fetch', exit: 'success', seconds: 90 }],
          },
        ],
      });
      const waiting = pendingWorkOrder(h.wf);
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expandWorkOrder(page, ran.id);

      await runComponents.S05(
        page,
        elapsedOf(stepRow(page, ran.runs[0].steps.Fetch)),
        elapsedOf(historyCell(historyRow(page, waiting.id), 'Duration'))
      );
    }
  );

  test(
    'shared-run-components@S06 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const w = seedHistoryOrder(h.wf, {
        state: 'failed',
        runs: [
          failedRun(),
          {
            state: 'failed',
            steps: [{ job: 'Fetch', carried: true }, { job: 'Load' }],
          },
        ],
      });
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expandWorkOrder(page, w.id);

      await runComponents.S06(
        page,
        stepRow(page, w.runs[1].steps.Fetch),
        stepRow(page, w.runs[1].steps.Load)
      );
    }
  );

  // The first work order ran on the version before the workflow changed, the
  // second on the version it is on now. The workflow link and the step's
  // inspect link both carry the pin.
  async function olderAndCurrent(page: Page) {
    const h = givenHistory();
    const older = failedWorkOrder(h.wf);
    h.wf.rename('Load', 'Load again');
    const current = seedHistoryOrder(h.wf, {
      state: 'failed',
      minutesAgo: 30,
      runs: [
        {
          state: 'failed',
          steps: [{ job: 'Fetch', exit: 'success' }, { job: 'Load again' }],
        },
      ],
    });
    await signInAs(page, ME);
    await openHistory(page, h.project.id);
    await expandWorkOrder(page, older.id);
    await expandWorkOrder(page, current.id);
    return { h, older, current };
  }

  test(
    'shared-run-components@S07 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const { older, current } = await olderAndCurrent(page);

      await runComponents.S07(page, {
        older: historyCell(historyRow(page, older.id), 'Workflow').getByRole(
          'link'
        ),
        olderRun: older.runs[0].id,
        version: 0,
        current: historyCell(
          historyRow(page, current.id),
          'Workflow'
        ).getByRole('link'),
        currentRun: current.runs[0].id,
      });
      await runComponents.S07(page, {
        older: inspectStepLink(page, older.runs[0].steps.Load),
        olderRun: older.runs[0].id,
        version: 0,
        current: inspectStepLink(page, current.runs[0].steps['Load again']),
        currentRun: current.runs[0].id,
      });
    }
  );

  test(
    'shared-run-components@S08 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const older = failedWorkOrder(h.wf);
      h.wf.rename('Load', 'Load again');
      setPreferences(ME, { experimental_features: true });
      await signInAs(page, ME);
      await openHistory(page, h.project.id);

      await runComponents.S08(
        page,
        historyCell(historyRow(page, older.id), 'Workflow').getByRole('link'),
        older.runs[0].id,
        `/projects/${h.project.id}/w/${h.wf.id}`
      );
    }
  );

  test(
    'shared-run-components@S09 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const w = pendingWorkOrder(h.wf);
      const [run] = w.runs;
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expandWorkOrder(page, w.id);

      await runComponents.S09(
        page,
        cancelRunButton(page, run.id),
        run.id,
        historyRun(page, run.id)
      );
    }
  );

  test(
    'shared-run-components@S10 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const w = pendingWorkOrder(h.wf);
      const [run] = w.runs;
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expandWorkOrder(page, w.id);
      await expect(cancelRunButton(page, run.id)).toBeVisible();

      await runComponents.S10(page, cancelRunButton(page, run.id), run.id, () =>
        claimRun(run.id)
      );
    }
  );

  test(
    'shared-run-components@S11 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const kenya = given('Kenya TB', { [OTHER]: 'owner' });
      const k = pendingWorkOrder(seedWorkflow(kenya.id));
      await signInAs(page, ME);
      await openHistory(page, h.project.id);

      await runComponents.S11(
        page,
        () => sendEvent(page, 'cancel-run', { run_id: k.runs[0].id }),
        k.runs[0].id
      );
    }
  );

  // A viewer sees no cancel button on an available run; an editor sees none
  // on a claimed, a started or a finished one
  test(
    'shared-run-components@S12 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      const h = givenHistory('Malawi HIV', {
        [ME]: 'viewer',
        [OTHER]: 'editor',
      });
      const available = pendingWorkOrder(h.wf);
      const others = seedHistoryOrder(h.wf, {
        state: 'running',
        runs: [{ state: 'claimed' }, { state: 'started' }, failedRun()],
      });
      await signInAs(page, ME);
      await openHistory(page, h.project.id, { workorder_id: available.id });
      await expect(runLink(page, available.runs[0].id)).toBeVisible();

      await runComponents.S12(
        page,
        page.getByRole('button', { name: 'Cancel this run' })
      );

      const editor = await otherSession(browser, OTHER);
      await openHistory(editor, h.project.id, { workorder_id: others.id });
      for (const run of others.runs)
        await expect(runLink(editor, run.id)).toBeVisible();
      await runComponents.S12(
        editor,
        editor.getByRole('button', { name: 'Cancel this run' })
      );
      await editor.context().close();
    }
  );

  test(
    'shared-run-components@S13 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      const h = givenHistory('Malawi HIV', {
        [ME]: 'admin',
        [OTHER]: 'editor',
      });
      const w = seedHistoryOrder(h.wf, {
        state: 'failed',
        runs: [
          {
            state: 'failed',
            steps: [
              { job: 'Fetch', exit: 'success' },
              { job: 'Load', inputWiped: true },
            ],
          },
        ],
      });
      const icon = (p: Page) => rerunStepIcon(p, w.runs[0].steps.Load);
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expandWorkOrder(page, w.id);
      const editor = await otherSession(browser, OTHER);
      await openHistory(editor, h.project.id);
      await expandWorkOrder(editor, w.id);

      await runComponents.S13(
        { page, icon: icon(page) },
        { page: editor, icon: icon(editor) },
        h.project.id
      );
      await editor.context().close();
    }
  );

  test(
    'shared-run-components@S14 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const w = failedWorkOrder(h.wf);
      const loadJob = h.wf.jobs.Load;
      deleteJobOf(h.wf, 'Load');
      cleanups.push(() => removeStepsOfJob(loadJob));
      await signInAs(page, ME);
      await openHistory(page, h.project.id);
      await expandWorkOrder(page, w.id);

      await runComponents.S14(
        page,
        rerunStepIcon(page, w.runs[0].steps.Load),
        () => runsOfWorkOrder(w.id).length
      );
    }
  );
});

// Inherited from shared-local-datetime: the "Created" and "Last Activity"
// columns, and the time a run's header gives.
test.describe('shared-local-datetime', () => {
  // Given work order "W" was created at <utc>, and today is <today>
  async function createdAt(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    const h = givenHistory();
    const id = seedWorkOrder(h.wf, { state: 'success', at: utc });
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    // Filtered to the workflow so the page's 30 day window does not apply
    await openHistory(page, h.project.id, { workflow_id: h.wf.id });
    return historyCell(historyRow(page, id), 'Created');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on history-work-orders',
      { tag: '@passing-old' },
      async ({ page }) => {
        await localDatetime.S01(
          page,
          await createdAt(page, localDatetime.given.S01)
        );
      }
    );
  });

  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on history-work-orders`,
      { tag: tagFor(id, ['S02', 'S04', 'S05', 'S06']) },
      async ({ page }) => {
        await localDatetime[id](
          page,
          await createdAt(page, localDatetime.given[id])
        );
      }
    );

  // The run header says when the run finished in the relative detailed form
  test(
    'shared-local-datetime@S03 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const { utc, today } = localDatetime.given.S03;
      // The run finishes a minute after the work order is created
      const w = seedHistoryOrder(h.wf, {
        state: 'success',
        at: utc.replace('08:30:07', '08:29:07'),
        runs: [
          { state: 'success', steps: [{ job: 'Fetch', exit: 'success' }] },
        ],
      });
      await signInAs(page, ME);
      await page.clock.setFixedTime(today);
      await openHistory(page, h.project.id, { workflow_id: h.wf.id });
      await expandWorkOrder(page, w.id);

      await localDatetime.S03(page, runTimestamp(page, w.runs[0].id));
    }
  );

  // A work order that has had no activity has no last activity to show
  test(
    'shared-local-datetime@S07 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const id = seedWorkOrder(h.wf, { state: 'pending' });
      exec(`update work_orders set last_activity = null where id = '${id}'`);
      await signInAs(page, ME);
      await openHistory(page, h.project.id, { workflow_id: h.wf.id });

      await localDatetime.S07(
        page,
        historyCell(historyRow(page, id), 'Last Activity')
      );
    }
  );
});

// Inherited from shared-flash-messages. The messages are the ones this page
// puts: "Work order cancelled.", "Run not found." and, after a retry, "New
// run enqueued for 1 workorder" on the page it reloads.
test.describe('shared-flash-messages', () => {
  // Given I have the history page open with a pending work order
  async function withPending(page: Page) {
    const h = givenHistory();
    const w = pendingWorkOrder(h.wf);
    await signInAs(page, ME);
    await openHistory(page, h.project.id);
    const cancel = async () =>
      cancelWorkOrderButton(historyRow(page, w.id)).click();
    return { h, w, cancel };
  }

  test(
    'shared-flash-messages@S01 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const { cancel } = await withPending(page);
      await flashMessages.S01(page, 'Work order cancelled.', cancel);
    }
  );

  test(
    'shared-flash-messages@S02 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      await withPending(page);
      await flashMessages.S02(page, 'Run not found.', () =>
        sendEvent(page, 'rerun', {
          run_id: randomUUID(),
          step_id: randomUUID(),
        })
      );
    }
  );

  test(
    'shared-flash-messages@S03 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const { cancel } = await withPending(page);
      await flashMessages.S03(page, 'Work order cancelled.', cancel);
    }
  );

  test(
    'shared-flash-messages@S04 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const { cancel } = await withPending(page);
      await flashMessages.S04(
        page,
        'Work order cancelled.',
        cancel,
        async () => {
          // Sorting makes the table render again
          await sortHistoryBy(page, 'Created');
          await expect.poll(() => page.url()).toContain('sort_by');
          await historyLoaded(page);
        }
      );
    }
  );

  // A retry reloads the page, and the flash goes with it
  test(
    'shared-flash-messages@S05 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const w = failedWorkOrder(h.wf);
      await signInAs(page, ME);
      await openHistory(page, h.project.id);

      await flashMessages.S05(
        page,
        'New run enqueued for 1 workorder',
        async () => retryButton(historyRow(page, w.id)).click(),
        `/projects/${h.project.id}/history`
      );
    }
  );

  test(
    'shared-flash-messages@S06 on history-work-orders',
    { tag: '@passing-old' },
    async ({ page }) => {
      const h = givenHistory();
      const notMine = givenHistory('Kenya TB', { [OTHER]: 'owner' });
      await signInAs(page, ME);
      await openHistory(page, h.project.id);

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

  // shared-flash-messages S07 and S08 are on admin pages and the sign-in form;
  // not_reachable_here does not exclude them, but this page never shows
  // either (see the list below)
});

// Not run on this page, and why (reported as unreachable):
//   shared-project-scope S11: its Given is a workflow open in the editor of a
//     sandbox. On History the archive hook (hooks.ex:296-317) only flashes
//     "Sandbox archived." and goes to the parent's workflow list, since this
//     page holds no workflow (no current_workflow_id).
//   shared-project-scope S12: its Given is a workflow open in the editor. The
//     hook ignores WorkflowDeleted on a page that holds none (hooks.ex:335-337).
//   shared-run-components S15 to S18: the editor run viewer's React ports
//     (RunTabPanel, StatePill, StepIcon, StepItem); they render on the
//     workflow editor page, not on History.
//   shared-flash-messages S07: admin pages only (settings layout).
//   shared-flash-messages S08: sign-in and account forms only.
//   Half of shared-run-components S01: a work order is never "claimed", and
//     a run's state shows as its raw name ("claimed"), not the "Starting"
//     pill (workorder_component.ex:411). "Starting" only shows on the run page.
//   @S33 and @S34 (and shared-usage-limits-banner S01) need an instance whose
//     usage limiter refuses runs, which a test cannot switch on.
