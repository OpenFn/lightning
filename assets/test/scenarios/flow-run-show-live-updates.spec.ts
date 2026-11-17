// Scenarios from annotations/flows/flow-run-show-live-updates.md: the run page
// following a run as the worker reports it.
//
// Who's who: "I" am editor@openfn.org, an editor on "Malawi HIV".
// owner@openfn.org owns every project and builds its workflows and runs
// through Lightning. Every project is seeded by the test and removed again
// afterwards, with its runs.
//
// The worker is a stand-in: workerReports (steps.ts) sends each report
// through the functions the worker's run channel calls, so the open page hears
// of it as it would from a real worker. A run seeded "available" is never
// offered to the e2e worker, so nothing else touches it.
import { expect, test, type Locator, type Page } from '@playwright/test';

import {
  cancelButton,
  detail,
  listedSteps,
  onScreen,
  runStep,
  selectStep,
  stepDuration,
} from './pages/run-show';
import * as bodyViewer from './shared/dataclip-body-viewer';
import * as hashTabs from './shared/hash-tabs';
import * as logViewer from './shared/log-viewer';
import * as runComponents from './shared/run-components';
import {
  exec,
  historyRow,
  mailedLinkTo,
  open,
  openHistory,
  removeWorkflowData,
  runPath,
  seedRun,
  seedWorkspace,
  signInAs,
  user,
  workerKeepsLogging,
  workerReports,
  type RunSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old'],
});

// How long an unaffected page is watched for a change that should not come
const QUIET = 3000;

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name>, where I am an editor — returns its id
function givenProject(name = 'Malawi HIV') {
  const w = seedWorkspace(
    { name, members: { [OWNER]: 'owner', [ME]: 'editor' } },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  return id;
}

// Given run "R" of "Intake" (or <seed>'s) in project <projectId>
function givenRun(projectId: string, seed: RunSeed) {
  const run = seedRun(projectId, { workflow: 'Intake', ...seed }, OWNER);
  cleanups.unshift(run.removeCredentials);
  return run;
}

// When I sign in and open run <runId>
async function openRun(page: Page, projectId: string, runId: string) {
  await signInAs(page, ME);
  await open(page, runPath(projectId, runId));
}

const openTab = (page: Page, label: string) =>
  hashTabs.tab(page, label).click();

// The run's state and its own counters
const status = (page: Page) => detail(page, 'Status');

// Whether a duration has stopped counting: it reads the same twice, two
// seconds apart
async function stopped(duration: Locator) {
  const first = await duration.innerText();
  await new Promise(resolve => setTimeout(resolve, 2000));
  return first === (await duration.innerText());
}

// @S01
// Scenario: A claimed run shows it is starting and is no longer cancellable
//   Given I am an editor with run "R" of workflow "Intake" open
//   And "R" is "Enqueued" with a "Cancel" action
//   When a worker claims "R"
//   Then eventually the status reads "Starting"
//   And the "Cancel" action is gone
test('@S01', tags('S01'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, { state: 'available', jobs: ['Fetch'] });
  await openRun(page, id, run.runId);
  await expect(status(page)).toHaveText(/Enqueued/);
  await expect(cancelButton(page)).toBeVisible();

  workerReports(run.runId, { claim: true });

  await expect(status(page)).toHaveText(/Starting/);
  await expect(cancelButton(page)).toHaveCount(0);
});

// @S02
// Scenario: A started run shows when it started and counts its duration
//   Given I have run "R" open while it is "Starting"
//   When the worker sends "run:start" for "R"
//   Then eventually the status reads "Running"
//   And "Started" shows the start time
//   And "Duration" counts up from the start time
test('@S02', tags('S02'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, { state: 'claimed', jobs: ['Fetch'] });
  await openRun(page, id, run.runId);
  await expect(status(page)).toHaveText(/Starting/);
  await expect(detail(page, 'Started')).not.toHaveText(/\d/);

  workerReports(run.runId, { start: true });

  await expect(status(page)).toHaveText(/Running/);
  await expect(detail(page, 'Started')).toHaveText(/\d/);
  await runComponents.S04(page, detail(page, 'Duration'));
});

// @S03
// Scenario: A step appears in the list when it starts
//   Given I have run "R" open while it is "Running" with no steps
//   When the worker starts step "Fetch" and then step "Transform"
//   Then eventually the step list shows "Fetch" then "Transform", in the order they started
//   And each step's duration counts up from its start time
test('@S03', tags('S03'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, { state: 'started', jobs: ['Fetch', 'Transform'] });
  await openRun(page, id, run.runId);
  await expect(status(page)).toHaveText(/Running/);
  expect(await listedSteps(page)).toEqual([]);

  const fetch = workerReports(run.runId, { startStep: 'Fetch' });
  await expect(runStep(page, fetch)).toBeVisible();
  const transform = workerReports(run.runId, { startStep: 'Transform' });

  await expect.poll(() => listedSteps(page)).toEqual(['Fetch', 'Transform']);
  await runComponents.S04(page, stepDuration(page, fetch));
  await runComponents.S04(page, stepDuration(page, transform));
});

// @S04
// Scenario: A completed step shows its outcome
//   Given I have run "R" open with step "Fetch" running
//   When the worker completes "Fetch" with reason "fail"
//   Then eventually "Fetch" shows a failure icon and its final duration
//   And when another step completes with reason "success" it shows a success icon
// "Load" is still running beside them, for shared-run-components S02's
// pending icon.
test('@S04', tags('S04'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, {
    state: 'started',
    jobs: ['Fetch', 'Transform', 'Load'],
  });
  const [fetch, transform, load] = ['Fetch', 'Transform', 'Load'].map(name =>
    workerReports(run.runId, { startStep: name })
  );
  await openRun(page, id, run.runId);
  await expect(runStep(page, fetch)).toBeVisible();

  workerReports(run.runId, { completeStep: fetch, reason: 'fail' });
  workerReports(run.runId, { completeStep: transform, reason: 'success' });

  await expect(async () =>
    runComponents.S02(page, {
      pending: runStep(page, load),
      success: runStep(page, transform),
      failed: runStep(page, fetch),
    })
  ).toPass();
  expect(await stopped(stepDuration(page, fetch))).toBe(true);
  expect(await stopped(stepDuration(page, load))).toBe(false);
});

// @S05
// Scenario: The selected step's output appears when it completes
//   Given I have run "R" open with step "Fetch" running and selected
//   And the "Output" tab shows "Nothing yet"
//   When the worker completes "Fetch" with an output
//   Then eventually the "Output" tab shows that output
test('@S05', tags('S05'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, { state: 'started', jobs: ['Fetch'] });
  const fetch = workerReports(run.runId, { startStep: 'Fetch' });
  await openRun(page, id, run.runId);
  await selectStep(page, fetch, 'Fetch');
  await openTab(page, 'Output');
  await expect(onScreen(page, 'Nothing yet')).toBeVisible();

  workerReports(run.runId, { completeStep: fetch, output: { patients: 12 } });

  await expect
    .poll(() => bodyViewer.viewerText(page))
    .toBe(JSON.stringify({ patients: 12 }, null, 2));
});

// @S06
// Scenario: Log lines appear as the worker sends them
//   Given I have run "R" open while it is "Running" and nothing has been logged
//   When the worker sends the log line "Fetched 12 patients"
//   And then sends "Posted batch 1" and "Posted batch 2" in one batch
//   Then eventually the "Log" tab shows all three lines in time order
test('@S06', tags('S06'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, { state: 'started', jobs: ['Fetch'] });
  const fetch = workerReports(run.runId, { startStep: 'Fetch' });
  await openRun(page, id, run.runId);
  expect(await logViewer.logLines(page)).toEqual([]);

  workerReports(run.runId, { log: 'Fetched 12 patients', step: fetch });
  workerReports(run.runId, {
    logs: ['Posted batch 1', 'Posted batch 2'],
    step: fetch,
  });

  await expect
    .poll(() => logViewer.logLines(page))
    .toEqual([
      'R/T Fetched 12 patients',
      'R/T Posted batch 1',
      'R/T Posted batch 2',
    ]);
});

// @S07
// Scenario: Lines logged while the existing log is loading appear once, in order
//   Given run "R" has already logged 500 lines and is still running
//   When I open the run page while the worker keeps logging
//   Then the "Log" tab shows every line exactly once, in time order
// The worker sends 40 more lines, 50 ms apart, starting just before the page
// opens. The whole log is read by copying it out of the viewer.
test('@S07', tags('S07'), async ({ page }) => {
  const id = givenProject();
  const stored = Array.from({ length: 500 }, (_, i) => `Stored line ${i + 1}`);
  const live = Array.from({ length: 40 }, (_, i) => `Live line ${i + 1}`);
  const run = givenRun(id, {
    state: 'started',
    steps: [{ name: 'Fetch', exit: null, seconds: 30 }],
    logs: stored.map(message => ({ message })),
  });
  await signInAs(page, ME);

  workerKeepsLogging(run.runId, live);
  await open(page, runPath(id, run.runId));

  const expected = [...stored, ...live].map(m => `R/T ${m}`);
  await expect
    .poll(() => logViewer.wholeLog(page), { timeout: 20000 })
    .toEqual(expected);
});

// @S08
// Scenario: A completed run shows its outcome, finish time and final output
//   Given I have run "R" open while it is "Running"
//   When the worker completes "R" with state "success" and a final output
//   Then eventually the status reads "Success"
//   And "Finished" shows the finish time and "Duration" stops counting
//   And "Final Output" links to the stored output
//   And when "R" completes with state "failed" instead, the flow "flow-failure-alert-email" starts
//   And open history pages are updated through "flow-history-live-updates"
// The flows' first hops only: a History tab shows the work order's new
// state, and I (alerted on failures in the project) am mailed a link to the
// failed run.
test('@S08', tags('S08'), async ({ page }) => {
  const id = givenProject();
  exec(`update project_users set failure_alert = true
        where project_id = '${id}' and user_id = '${user(ME).id}'`);
  const run = givenRun(id, { state: 'started', jobs: ['Fetch'] });
  const failing = givenRun(id, {
    workflow: 'Intake failing',
    state: 'started',
    jobs: ['Fetch'],
  });
  await openRun(page, id, run.runId);
  const history = await page.context().newPage();
  await openHistory(history, id);
  await expect(historyRow(history, run.workOrderId)).toContainText(/Running/);

  workerReports(run.runId, { complete: 'success', finalState: { done: 1 } });

  await expect(status(page)).toHaveText(/Success/);
  await expect(detail(page, 'Finished')).toHaveText(/\d/);
  expect(await stopped(detail(page, 'Duration'))).toBe(true);
  await expect(detail(page, 'Final Output').getByRole('link')).toBeVisible();
  await expect(historyRow(history, run.workOrderId)).toContainText(/Success/);

  await open(page, runPath(id, failing.runId));
  workerReports(failing.runId, { complete: 'failed' });

  await expect(status(page)).toHaveText(/Failed/);
  expect(
    await mailedLinkTo(page.request, user(ME).email, runPath(id, failing.runId))
  ).toBe(runPath(id, failing.runId));
});

// @S09
// Scenario: A run that finishes without logging says so
//   Given I have run "R" open while it is "Starting" and nothing has been logged
//   When "R" completes with state "crashed" without sending any log line
//   Then eventually the "Log" tab says "No logs were received for this run."
test('@S09', tags('S09'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, { state: 'claimed', jobs: ['Fetch'] });
  await openRun(page, id, run.runId);
  await expect(status(page)).toHaveText(/Starting/);

  workerReports(run.runId, { complete: 'crashed' });

  await expect(status(page)).toHaveText(/Crashed/);
  await expect(
    onScreen(page, 'No logs were received for this run.')
  ).toBeVisible();
});

// @S10
// Scenario: Another run's progress never reaches this page
//   Given I have run "R" open
//   When a worker starts a step and logs a line for run "S"
//   Then nothing on the page changes
// "S" is a run in another project, of a workflow with the same step names.
test('@S10', tags('S10'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id, { state: 'started', jobs: ['Fetch'] });
  const other = givenRun(givenProject('Kenya TB'), {
    state: 'started',
    jobs: ['Fetch'],
  });
  await openRun(page, id, run.runId);
  await expect(status(page)).toHaveText(/Running/);

  const step = workerReports(other.runId, { startStep: 'Fetch' });
  workerReports(other.runId, { log: 'Not for this page', step });
  await page.waitForTimeout(QUIET);

  expect(await listedSteps(page)).toEqual([]);
  expect(await logViewer.logLines(page)).toEqual([]);
  await expect(status(page)).toHaveText(/Running/);
});
