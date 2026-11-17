// Scenarios from annotations/flows/flow-manual-run-live-follow.md: the editor
// following a run started by hand, until it finishes.
//
// Who's who: "I" am editor@openfn.org, an editor on "Malawi HIV".
// super@openfn.org stands in for "amara@example.org", a second editor with
// the workflow open in a browser of her own. owner@openfn.org owns the
// project, builds its workflows and seeded runs through Lightning, and
// removes members. Every project is seeded by the test and removed again
// afterwards, with its runs. "Intake" is a webhook trigger leading to
// "Fetch", then "Load".
//
// Runs started from the editor (S01 to S03, S06) are run by the e2e worker
// for real. Runs whose progress a scenario sets (S04, S05, S07, S08) are
// seeded where the worker never takes them, and their progress is sent
// through the functions the worker's run channel calls (workerReports).
import { expect, test, type Page } from '@playwright/test';

import {
  editorQuery,
  header,
  openEditor,
  watchEditorSocket,
} from './pages/workflow-editor';
import {
  ideHeader,
  ideReady,
  inputChoice,
  openIde,
  openRunPanel,
  runChip,
  runPanelInput,
  runTab,
  replaceCode,
  tabShowing,
} from './pages/workflow-editor-ide';
import {
  connectRunWorkflow,
  runPanel,
  runPanelQuery,
  setCustomInput,
} from './pages/workflow-editor-manual-run';
import {
  canvasRunChip,
  logLines,
  nodeTips,
  reopenRun,
  statusPill,
  stepRows,
  wholeRunLog,
} from './pages/workflow-editor-run-viewer';
import {
  expandHistory,
  listedWorkOrders,
  seedRunOn,
  workOrderRow,
} from './pages/workflow-editor-versions-and-promote';
import * as runRetry from './shared/run-retry-controls';
import {
  exec,
  mailedLinkTo,
  otherSession,
  removeMemberOnNode,
  removeWorkflowData,
  runPath,
  seedDataclip,
  seedEditorWorkflow,
  seedRun,
  seedWorkspace,
  signInAs,
  sql,
  user,
  workerReports,
  type RunSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const AMARA = 'super@openfn.org';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {
  S01: 'unconfirmed: passes on a fresh seed, but after other editor runs the editor opens with ?panel=run; some state outlives the test',
};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old'],
});

// A run the e2e worker runs, or a page reacting to one, gets this long
const EVENTUALLY = { timeout: 30000 };
// How long a page is watched for a change that should not come
const QUIET = 3000;

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name>, where Amara and I are editors — returns its id
function givenProject(name = 'Malawi HIV') {
  const w = seedWorkspace(
    {
      name,
      members: { [OWNER]: 'owner', [ME]: 'editor', [AMARA]: 'editor' },
    },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  return id;
}

// Given project "Malawi HIV" with workflow "Intake"
const givenIntake = () => seedEditorWorkflow(givenProject(), OWNER);

// Given run "R" of an "Intake" (trigger, "Fetch", then "Load") in project
// <projectId>, seeded as <seed> says — returns the run and the workflow as
// the editor sees it
function givenRun(projectId: string, seed: RunSeed) {
  const run = seedRun(
    projectId,
    {
      workflow: 'Intake',
      // The jobs no step of the run has run yet
      jobs: ['Fetch', 'Load'].filter(
        j => !(seed.steps ?? []).some(s => s.name === j)
      ),
      ...seed,
    },
    OWNER
  );
  cleanups.unshift(run.removeCredentials);
  const wf = connectRunWorkflow(run.workflowId, projectId, ['Fetch', 'Load']);
  return { run, wf };
}

// When I sign in and open <wf> with <query>
async function openAs(
  page: Page,
  wf: { projectId: string; id: string },
  query = ''
) {
  await signInAs(page, ME);
  await openEditor(page, wf.projectId, wf.id, query);
}

// The run created after <before> runs of workflow <id>
async function newRun(workflowId: string, before: number) {
  await expect
    .poll(() => runRetry.runsOfWorkflow(workflowId).length)
    .toBe(before + 1);
  return runRetry.runsOfWorkflow(workflowId)[before];
}

// @S01
// Scenario: A run started from the panel is followed on the canvas
//   Given I am an editor on project "Malawi HIV" with workflow "Intake" open
//   And the run panel is open for step "Fetch" over the canvas
//   When I click "Run From Here"
//   Then a work order and run "R" are created starting at "Fetch"
//   And the panel closes and the URL has "run=<R id>" and no "panel"
//   And the run history list shows R's work order at the top with "R" selected
//   When the worker starts and then completes "Fetch"
//   Then eventually the "Fetch" node shows it ran and how it ended, without a reload
test('@S01', tags('S01'), async ({ page }) => {
  const wf = givenIntake();
  await openAs(page, wf, runPanelQuery({ job: wf.steps.Fetch }));

  await runRetry.runButton(runPanel(page)).click();

  const r = await newRun(wf.id, 0);
  expect(r.starting_job_id).toBe(wf.steps.Fetch);
  await expect.poll(() => editorQuery(page).run).toBe(r.id);
  expect(editorQuery(page).panel).toBeUndefined();
  // The collapsed history panel names the selected run
  await expect(canvasRunChip(page, r.id)).toBeVisible();
  await expandHistory(page);
  await expect.poll(() => listedWorkOrders(page)).toEqual([r.work_order_id]);

  await expect
    .poll(() => nodeTips(page, 'Fetch'), EVENTUALLY)
    .toContainEqual(expect.stringMatching(/success/i));
});

// @S02
// Scenario: A run started in the code editor opens its logs there
//   Given I have the IDE open on job "Fetch" with the embedded run panel
//   When I click "Run From Here"
//   Then the right panel switches to the run viewer for the new run "R"
//   And the URL has "run=<R id>"
//   When the worker logs "Fetched 12 patients" for "R"
//   Then eventually the "Log" tab shows "Fetched 12 patients"
// The IDE's run control is its header's "Run". The job logs the line itself:
// I write it so, in a workflow that allows console.log(), and the run saves
// it first.
test('@S02', tags('S02'), async ({ page }) => {
  const wf = givenIntake();
  exec(`update workflows set enable_job_logs = true where id = '${wf.id}'`);
  await signInAs(page, ME);
  await openIde(page, wf.projectId, wf.id, wf.steps.Fetch);
  await replaceCode(
    page,
    "fn(state => { console.log('Fetched 12 patients'); return state; })"
  );
  await openRunPanel(page);
  await inputChoice(page, 'Empty').click();

  await runRetry.runButton(ideHeader(page)).click();

  const r = await newRun(wf.id, 0);
  await expect.poll(() => editorQuery(page).run).toBe(r.id);
  await expect(runChip(page, r.id)).toBeVisible();
  await expect.poll(() => tabShowing(runTab(page, 'Logs'))).toBe(true);
  await expect
    .poll(() => wholeRunLog(page), EVENTUALLY)
    .toContainEqual(expect.stringContaining('Fetched 12 patients'));
});

// @S03
// Scenario: A custom input becomes the input to retry with
//   Given I have the IDE open on job "Fetch" with the embedded run panel on the "Custom" tab
//   When I run with {"patient": "123"}
//   Then the run viewer follows the new run
//   And the panel's input is the saved input holding {"patient": "123"}, on the existing inputs tab
//   And once the run's "Fetch" step has that input, the run button offers "Retry"
// The panel's input is read off the run and its stored input; the panel
// itself is behind the run viewer while it follows the run.
test('@S03', tags('S03'), async ({ page }) => {
  const wf = givenIntake();
  await signInAs(page, ME);
  await openIde(page, wf.projectId, wf.id, wf.steps.Fetch);
  await openRunPanel(page);
  await inputChoice(page, 'Custom').click();
  await setCustomInput(page, '{"patient": "123"}', runPanelInput(page));

  await runRetry.runButton(ideHeader(page)).click();

  const r = await newRun(wf.id, 0);
  await expect(runChip(page, r.id)).toBeVisible();
  expect(r.input).toEqual({ patient: '123' });
  expect(
    sql<{ type: string }>(
      `select type::text from dataclips where id = '${r.dataclip_id}'`
    )[0].type
  ).toBe('saved_input');
  await expect(runRetry.runButton(ideHeader(page))).toHaveText(
    /Retry/,
    EVENTUALLY
  );
});

// @S04
// Scenario: Progress made before the editor connects is not lost
//   Given a worker claims and starts run "R" before my editor has joined "run:<R id>"
//   When the editor joins
//   Then the run viewer shows "R" as started with the steps it has already begun
//   And later step and state changes are applied on top
test('@S04', tags('S04'), async ({ page }) => {
  const { run, wf } = givenRun(givenProject(), { state: 'available' });
  workerReports(run.runId, { claim: true });
  workerReports(run.runId, { start: true });
  const fetch = workerReports(run.runId, { startStep: 'Fetch' });
  await signInAs(page, ME);

  await openIde(page, wf.projectId, wf.id, wf.steps.Fetch, {
    run: run.runId,
  });
  await ideReady(page);

  await expect(statusPill(page)).toHaveText(/Running/, EVENTUALLY);
  await expect(stepRows(page)).toHaveText([/Fetch/]);

  workerReports(run.runId, { completeStep: fetch });
  workerReports(run.runId, { startStep: 'Load' });
  await expect(stepRows(page)).toHaveText([/Fetch/, /Load/], EVENTUALLY);
  workerReports(run.runId, { complete: 'success' });
  await expect(statusPill(page)).toHaveText(/Success/, EVENTUALLY);
});

// @S05
// Scenario: The followed run finishing shows its outcome and frees the controls
//   Given the editor is following run "R" while it is running
//   When the worker completes "R" with state "failed"
//   Then eventually the run history list shows "R" as failed
//   And the canvas shows each step's final outcome
//   And the run controls stop showing "Processing"
//   And the flow "flow-failure-alert-email" starts for "R"
// The alert's first hop: I (alerted on failures in the project) am mailed a
// link to "R".
test('@S05', tags('S05'), async ({ page }) => {
  const id = givenProject();
  exec(`update project_users set failure_alert = true
        where project_id = '${id}' and user_id = '${user(ME).id}'`);
  const { run, wf } = givenRun(id, { state: 'available' });
  workerReports(run.runId, { claim: true });
  workerReports(run.runId, { start: true });
  const fetch = workerReports(run.runId, { startStep: 'Fetch' });
  await openAs(page, wf, `?run=${run.runId}`);
  await expandHistory(page);
  await expect(workOrderRow(page, run.workOrderId)).toBeVisible();

  workerReports(run.runId, {
    completeStep: fetch,
    reason: 'fail',
    errorType: 'RuntimeError',
  });
  workerReports(run.runId, { complete: 'failed' });
  expect(
    sql<{ exit_reason: string }>(
      `select exit_reason from steps where id = '${fetch}'`
    )
  ).toEqual([{ exit_reason: 'fail' }]);

  await expect(workOrderRow(page, run.workOrderId)).toContainText(
    /failed/i,
    EVENTUALLY
  );
  await expect
    .poll(() => nodeTips(page, 'Fetch'), EVENTUALLY)
    .toContain('RuntimeError');
  await expect(runRetry.runButton(header(page))).not.toHaveText(/Processing/);
  expect(
    await mailedLinkTo(page.request, user(ME).email, runPath(id, run.runId))
  ).toBe(runPath(id, run.runId));
});

// @S06
// Scenario: A collaborator sees the new run without being moved to it
//   Given "amara@example.org" has "Intake" open, following run "Q"
//   When I start run "R" from the panel
//   Then eventually her run history list shows R's work order
//   And her editor still follows "Q" and her URL is unchanged
test('@S06', tags('S06'), async ({ page, browser }) => {
  const wf = givenIntake();
  const q = seedRunOn(wf, {
    inputId: seedDataclip(wf.projectId, { type: 'http_request' }),
  });
  const amara = await otherSession(browser, AMARA);
  await openEditor(amara, wf.projectId, wf.id, `?run=${q.runId}`);
  await expect(canvasRunChip(amara, q.runId)).toBeVisible();
  await expandHistory(amara);
  const herUrl = amara.url();
  await openAs(page, wf, runPanelQuery({ job: wf.steps.Fetch }));

  await runRetry.runButton(runPanel(page)).click();

  const r = await newRun(wf.id, 1);
  await expect
    .poll(() => listedWorkOrders(amara), EVENTUALLY)
    .toContain(r.work_order_id);
  expect(amara.url()).toBe(herUrl);
  expect(editorQuery(amara).run).toBe(q.runId);
});

// @S07
// Scenario: Another run's progress never shows on the followed run
//   Given the editor is following run "R"
//   When a worker starts a step and logs a line for run "S" of the same workflow
//   Then the run viewer and the canvas still show only R's steps and logs
//   And "S" appears only as its own entry in the run history list
// "S" is an earlier run of the same workflow, put back to running.
test('@S07', tags('S07'), async ({ page }) => {
  const { run, wf } = givenRun(givenProject(), {
    state: 'started',
    steps: [{ name: 'Fetch' }],
    logs: [{ message: 'Fetched for R', step: 'Fetch' }],
  });
  const s = seedRunOn(wf, { inputId: run.inputId, minutesAgo: 5 });
  reopenRun(s.runId, 'started');
  await signInAs(page, ME);
  await openIde(page, wf.projectId, wf.id, wf.steps.Fetch, { run: run.runId });
  await expect(stepRows(page)).toHaveText([/Fetch/], EVENTUALLY);
  await expect
    .poll(() => logLines(page), EVENTUALLY)
    .toEqual(['R/T Fetched for R']);

  const step = workerReports(s.runId, { startStep: 'Load' });
  workerReports(s.runId, { log: 'Logged for S', step });
  await page.waitForTimeout(QUIET);

  await expect(stepRows(page)).toHaveText([/Fetch/]);
  expect(await logLines(page)).toEqual(['R/T Fetched for R']);
  expect(editorQuery(page).run).toBe(run.runId);
});

// @S08
// Scenario: Losing access stops the run's data reaching the editor
//   Given I am an editor following run "R" of "Malawi HIV"
//   When an admin removes me from "Malawi HIV"
//   Then the run channel for "R" is closed
//   And log lines written for "R" afterwards are not sent to me
//   And removing a different member, or me from another project, leaves it open
// The channel is watched on the page's own socket. The harmless removals
// come first.
test('@S08', tags('S08'), async ({ page }) => {
  const id = givenProject();
  const other = givenProject('Kenya TB');
  const { run, wf } = givenRun(id, {
    state: 'started',
    steps: [{ name: 'Fetch', exit: null }],
  });
  const sock = await watchEditorSocket(page);
  await signInAs(page, ME);
  await openIde(page, wf.projectId, wf.id, wf.steps.Fetch, { run: run.runId });
  await expect(statusPill(page)).toHaveText(/Running/, EVENTUALLY);
  const topic = `run:${run.runId}`;
  expect(sock.eventsOn(topic)).toContain('phx_reply');

  removeMemberOnNode(id, AMARA, OWNER);
  removeMemberOnNode(other, ME, OWNER);
  await page.waitForTimeout(QUIET);
  expect(sock.eventsOn(topic)).not.toContain('phx_close');

  removeMemberOnNode(id, ME, OWNER);
  await expect
    .poll(() => sock.eventsOn(topic), EVENTUALLY)
    .toContain('phx_close');
  const seen = sock.eventsOn(topic).length;
  workerReports(run.runId, { log: 'After the removal', step: run.steps.Fetch });
  await page.waitForTimeout(QUIET);
  expect(sock.eventsOn(topic).length).toBe(seen);
});
