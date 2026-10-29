// Scenarios from annotations/views/workflow-editor-run-viewer.md, and the
// shared scenarios the run viewer hosts.
//
// Who's who: "I" is editor@openfn.org, an editor unless a test says
// otherwise. owner@openfn.org owns every project and builds its runs through
// Lightning; super@openfn.org stands in for "amara@example.org", who starts a
// run by hand. Every project ("Malawi HIV", "Kenya TB") is seeded by the test
// and removed again afterwards, with its workflows and runs. A run's workflow
// is built with it: a webhook trigger and a job per step, named after the
// step ("Fetch", "Transform", ...), plus any job the test says did not run.
//
// The steps, data and logs only show in the full-screen IDE, so most tests
// open the IDE on a job with run=<id>; S10 and S12 look at the canvas.
//
// The editor is not being ported: these record what today's run viewer does,
// through pages/workflow-editor-run-viewer.ts, so a rebuild that keeps the
// Value passes.
//
// Stand-ins: S04 and shared-run-components S18 mark a step as carried over by
// giving it a creation time before its run's (what a rerun from a later step
// leaves); S06 drops a step's input in the database (a step whose input could
// not be saved); S08 puts a finished run back to "started" (a run still
// going); S10 adds copies of a step to its run (a job that ran three times);
// S07 sends the first log line through Lightning, as a worker would.
//
// shared-authenticated-session, shared-project-scope, shared-editor-session
// and shared-flash-messages belong to the route /projects/:id/w/:id and run
// on it once, in workflow-editor-canvas.spec.ts. shared-run-retry-controls S04
// for a loaded run already runs in the IDE (workflow-editor-ide.spec.ts); S02
// runs here on the IDE's header. shared-log-viewer S04 (the remembered level)
// is the run page's.
import { randomUUID } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import { inspectLink, detail as runPageDetail } from './pages/run-show';
import { editorQuery, node, openEditor } from './pages/workflow-editor';
import {
  codeText,
  ideHeader,
  ideReady,
  inputChoice,
  jobSelector,
  markedLogLines,
  openIde,
  openRunPanel,
  pickJob,
  runChip,
  runTab,
  runViewer,
  setJobBody,
  tabShowing,
} from './pages/workflow-editor-ide';
import { connectRunWorkflow } from './pages/workflow-editor-manual-run';
import {
  bodyText,
  carriedMarker,
  chipLook,
  chooseLevel,
  copiedSignal,
  copyButton,
  dropStepInput,
  fadeOf,
  jobsOf,
  levelFilter,
  logLines,
  nodeFade,
  nodeTips,
  panelFade,
  pathFade,
  pointAtChip,
  preloadedRun,
  reopenRun,
  repeatStep,
  runDetail,
  runDuration,
  selectedStep,
  stepDuration,
  stepRow,
  stepRows,
  statusPill,
  timesRun,
  typeIntoBody,
  waitingHint,
  waitingMessage,
} from './pages/workflow-editor-run-viewer';
import * as bodyViewer from './shared/dataclip-body-viewer';
import * as logViewer from './shared/log-viewer';
import * as runComponents from './shared/run-components';
import * as runRetry from './shared/run-retry-controls';
import {
  keepAccount,
  lookOf,
  open,
  redeliverLogLine,
  removeWorkflowData,
  runPath,
  seedEditorWorkflow,
  seedRun,
  seedWorkspace,
  signInAs,
  user,
  workerReports,
  type RunSeed,
  type SeededRunIds,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const AMARA = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };

// A page that has to react to something done elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it)
// — removed after the test with its workflows and runs
function givenProject(
  members: Record<string, Role> = { [ME]: 'editor' },
  name = 'Malawi HIV'
) {
  const w = seedWorkspace(
    { name, members: { ...members, [OWNER]: 'owner' } },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  return id;
}

// Given project <projectId> has run <seed> of a workflow "Intake" (or the
// seed's), whose steps "Fetch" then "Transform" ran unless it says otherwise
function runIn(projectId: string, seed: RunSeed = {}) {
  const run = seedRun(
    projectId,
    {
      workflow: 'Intake',
      steps: [{ name: 'Fetch' }, { name: 'Transform' }],
      ...seed,
    },
    OWNER
  );
  cleanups.unshift(run.removeCredentials);
  return run;
}

// Given project "Malawi HIV", where I am an editor, has run <seed>
function givenRun(seed: RunSeed = {}) {
  const id = givenProject();
  return { id, run: runIn(id, seed) };
}

// When I open the IDE on job <job> of <run>'s workflow with the run loaded
// (signed in already), and the run viewer has shown it
async function openRun(
  page: Page,
  projectId: string,
  run: SeededRunIds,
  job: string,
  extra: Record<string, string> = {}
) {
  await openIde(page, projectId, run.workflowId, jobsOf(run.workflowId)[job], {
    run: run.runId,
    ...extra,
  });
  await expect(statusPill(page)).toBeVisible(EVENTUALLY);
}

// The link labelled <label> in the run's details, as path and params
async function detailLink(page: Page, label: string) {
  const href = await runDetail(page, label)
    .getByRole('link')
    .getAttribute('href');
  const url = new URL(href!, 'http://lightning.test');
  return { path: url.pathname, params: url.searchParams };
}

// Given run "R2" retried from "Transform" of an earlier run: "Fetch" is
// carried over
const RETRIED: RunSeed = {
  steps: [{ name: 'Fetch', carried: true }, { name: 'Transform' }],
};

// Given a run still going whose steps ended every way a step can, the last
// one still running
const OUTCOMES: RunSeed = {
  state: 'started',
  steps: [
    { name: 'Fetch' },
    { name: 'Transform', exit: 'fail' },
    { name: 'Timeout', exit: 'kill', errorType: 'TimeoutError' },
    { name: 'Security', exit: 'kill', errorType: 'SecurityError' },
    { name: 'Memory', exit: 'kill', errorType: 'OOMError' },
    { name: 'Too large', exit: 'kill', errorType: 'StateTooLargeError' },
    { name: 'Load', exit: null },
  ],
};

// When I look at the step outcomes of an OUTCOMES run
async function expectOutcomeIcons(page: Page) {
  await runComponents.S02(page, {
    pending: stepRow(page, 'Load'),
    success: stepRow(page, 'Fetch'),
    failed: stepRow(page, 'Transform'),
  });
  await runComponents.S03(page, {
    timeout: stepRow(page, 'Timeout'),
    security: stepRow(page, 'Security'),
    oom: stepRow(page, 'Memory'),
    tooLarge: stepRow(page, 'Too large'),
  });
}

// When I look at a step carried over (<carried>) and one that ran (<ran>)
async function expectCarriedMarked(page: Page, carried: string, ran: string) {
  await expect(stepRow(page, ran)).toBeVisible();
  expect(await fadeOf(stepRow(page, carried))).toBeLessThan(
    await fadeOf(stepRow(page, ran))
  );
  await expect(carriedMarker(stepRow(page, carried))).toHaveCount(1);
  await carriedMarker(stepRow(page, carried)).hover();
  await expect(page.getByRole('tooltip').first()).toContainText(
    'was originally executed in a previous run'
  );
  await expect(carriedMarker(stepRow(page, ran))).toHaveCount(0);
}

// Run states and the labels they read
const STATE_LABELS = [
  ['available', 'Enqueued'],
  ['claimed', 'Starting'],
  ['started', 'Running'],
  ['failed', 'Failed'],
] as const;

// Given a run in <state>; a failed one ran "Fetch", the others no step yet
const runInState = (projectId: string, state: string) =>
  runIn(projectId, {
    workflow: `Intake ${state}`,
    state,
    steps: state === 'failed' ? [{ name: 'Fetch', exit: 'fail' }] : [],
    jobs: state === 'failed' ? [] : ['Fetch'],
  });

// ---------------------------------------------------------------------------
// The run and its steps
// ---------------------------------------------------------------------------

// @S01
// Scenario: The run viewer shows the run's summary and its steps
//   Given run "R" of "Intake" was started manually by "amara@example.org"
//   And steps "Fetch" then "Transform" ran in "R", "Fetch" for 3 seconds
//   When I open the IDE on "Fetch" with "run=<R id>"
//   Then the right panel shows a chip "Run <first 7 characters of R id>" and the tabs "Logs", "Input" and "Output"
//   And the run details show "Work Order", "Run", "Status", "Duration", "Started" and "Started by" "amara@example.org"
//   And "Run Steps" lists "Fetch" then "Transform", "Fetch" with a duration of "3 s"
test('@S01', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun({
    createdBy: AMARA,
    steps: [{ name: 'Fetch', seconds: 3 }, { name: 'Transform' }],
  });
  await signInAs(page, ME);

  await openRun(page, id, run, 'Fetch');

  await expect(runChip(page, run.runId)).toBeVisible();
  for (const tab of ['Logs', 'Input', 'Output'] as const)
    await expect(runTab(page, tab)).toBeVisible();
  for (const label of ['Work Order', 'Run', 'Status', 'Duration', 'Started'])
    await expect(runDetail(page, label)).toBeVisible();
  await expect(runDetail(page, 'Started by')).toHaveText(user(AMARA).email);
  await expect(stepRows(page)).toHaveText([/Fetch/, /Transform/]);
  await expect(stepDuration(page, 'Fetch')).toHaveText('3 s');
});

// @S02
// Scenario Outline: Run state reads in plain words
//   Given the loaded run is in state "<state>"
//   Then the status pill reads "<label>"
//   Examples: available Enqueued; claimed Starting; started Running; failed Failed
test('@S02', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await signInAs(page, ME);

  for (const [state, label] of STATE_LABELS)
    await test.step(`a run in state "${state}"`, async () => {
      await openRun(page, id, runInState(id, state), 'Fetch');
      await runComponents.S01(page, [[statusPill(page), label]]);
    });
});

// @S03
// Scenario: Step outcome and duration are shown per step
//   Given the loaded run has a step that succeeded, one that failed, one killed with "TimeoutError" and one still running
//   Then the steps show a green check, a red cross, a clock and a grey pending icon
//   And the running step's duration counts up each second while the run has not started any step reads "Not started"
// The kill family is told apart as shared-run-components S03 does. "Not
// started" is the duration of a run no worker has started.
test('@S03', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun(OUTCOMES);
  const waiting = runIn(id, {
    workflow: 'Intake waiting',
    state: 'available',
    steps: [],
    jobs: ['Fetch'],
  });
  await signInAs(page, ME);
  await openRun(page, id, run, 'Fetch');

  await expectOutcomeIcons(page);
  await runComponents.S04(page, stepDuration(page, 'Load'));

  await openRun(page, id, waiting, 'Fetch');
  await expect(runDuration(page)).toHaveText('Not started');
});

// @S04
// Scenario: Steps carried over from an earlier run are marked
//   Given run "R2" was retried from "Transform" of run "R1"
//   When I load "R2" in the run viewer
//   Then "Fetch" is faded with a paperclip whose tooltip says it "was originally executed in a previous run"
//   And "Transform" has no paperclip
test('@S04', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun(RETRIED);
  await signInAs(page, ME);

  await openRun(page, id, run, 'Transform');

  await expectCarriedMarked(page, 'Fetch', 'Transform');
});

// @S05
// Scenario: Picking a step opens its job and shows that step's data and logs
//   Given I have the IDE open on "Fetch" with run "R" loaded
//   When I click step "Transform" in "Run Steps"
//   Then the URL has "job=<Transform id>", "step=<Transform step id>" and still "run=<R id>" and "panel=editor"
//   And the IDE shows the code of "Transform"
//   And "Transform" is highlighted in the step list
//   And the "Input" and "Output" tabs show "Transform"'s data and the "Logs" tab marks its lines (shared-log-viewer S05)
// "Transform"'s input is "Fetch"'s output.
// Still pending, old: picking a step marks its log lines from one line early, so the line before it is marked too
test('@S05', PENDING, async ({ page }) => {
  const { id, run } = givenRun({
    steps: [
      { name: 'Fetch', output: { fetched: 12 } },
      { name: 'Transform', output: { transformed: 12 } },
    ],
    logs: [
      { message: 'fetching patients', step: 'Fetch' },
      { message: 'transforming patients', step: 'Transform' },
    ],
  });
  const jobs = jobsOf(run.workflowId);
  setJobBody(jobs.Transform, '// transforms patients\nfn(s => s);');
  await signInAs(page, ME);
  await openRun(page, id, run, 'Fetch');

  await stepRow(page, 'Transform').click();

  await expect
    .poll(() => editorQuery(page))
    .toMatchObject({
      job: jobs.Transform,
      step: run.steps.Transform,
      run: run.runId,
      panel: 'editor',
    });
  await expect.poll(() => codeText(page)).toContain('// transforms patients');
  await expect.poll(() => selectedStep(page)).toBe('Transform');
  await runTab(page, 'Logs').click();
  await expect
    .poll(() => markedLogLines(page), EVENTUALLY)
    .toEqual([expect.stringContaining('transforming patients')]);
  await runTab(page, 'Input').click();
  await expect.poll(() => bodyText(page)).toContain('"fetched": 12');
  await runTab(page, 'Output').click();
  await expect.poll(() => bodyText(page)).toContain('"transformed": 12');
});

// @S06
// Scenario Outline: Input and output tabs say why there is no data
//   Given the loaded run is "<run state>"
//   And the selected step "<step>"
//   When I open the "<tab>" tab
//   Then I see "<message>"
//   Examples:
//     | started | is not chosen          | Input  | Select a step to view input data             |
//     | started | has no output yet      | Output | Nothing yet                                  |
//     | failed  | has no input dataclip  | Input  | No input state could be saved for this run.  |
//     | failed  | has no output dataclip | Output | No output state could be saved for this run. |
// A run picks its first step by itself, so no step is chosen only while the
// run has none.
test('@S06', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  const noStep = runIn(id, {
    workflow: 'Intake no step',
    state: 'started',
    steps: [],
    jobs: ['Fetch'],
  });
  const running = runIn(id, {
    workflow: 'Intake running',
    state: 'started',
    steps: [{ name: 'Fetch', exit: null }],
  });
  const failed = runIn(id, {
    workflow: 'Intake failed',
    state: 'failed',
    steps: [{ name: 'Fetch', exit: 'fail' }],
  });
  dropStepInput(failed.steps.Fetch);
  await signInAs(page, ME);

  const rows = [
    [noStep, 'Input', 'Select a step to view input data'],
    [running, 'Output', 'Nothing yet'],
    [failed, 'Input', 'No input state could be saved for this run.'],
    [failed, 'Output', 'No output state could be saved for this run.'],
  ] as const;
  for (const [run, tab, message] of rows)
    await test.step(`${tab}: ${message}`, async () => {
      await openRun(page, id, run, 'Fetch');
      await runTab(page, tab).click();
      await expect(runViewer(page).getByText(message)).toBeVisible();
    });
});

// @S07
// Scenario Outline: The log says what a run is waiting for before it logs anything
//   Given the loaded run is in state "<state>" and has no log lines
//   When I open the "Logs" tab
//   Then "<first message>" is typed out
//   And hints about that state cycle below it
//   When the first log line arrives
//   Then the waiting text disappears and the log is shown
//   Examples:
//     | available | Waiting for a worker to establish a secure claim...     |
//     | claimed   | Creating an isolated runtime and installing adaptors... |
// The hints' wording is not checked: it has typos (annotation 6.1).
test('@S07', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await signInAs(page, ME);
  const rows = [
    ['available', 'Waiting for a worker to establish a secure claim...'],
    ['claimed', 'Creating an isolated runtime and installing adaptors...'],
  ] as const;

  for (const [state, first] of rows)
    await test.step(`a run in state "${state}"`, async () => {
      const run = runIn(id, {
        workflow: `Intake ${state}`,
        state,
        steps: [],
        jobs: ['Fetch'],
      });
      await openRun(page, id, run, 'Fetch');
      await runTab(page, 'Logs').click();

      await expect(waitingMessage(page, first)).toBeVisible(EVENTUALLY);
      await expect
        .poll(() => waitingHint(page, first), EVENTUALLY)
        .not.toBe('');

      workerReports(run.runId, { log: 'Worker says hello' });

      await expect(waitingMessage(page, first)).toHaveCount(0, EVENTUALLY);
      await expect
        .poll(() => logLines(page))
        .toContain('R/T Worker says hello');
    });
});

// @S08
// Scenario: A job that did not run in the loaded run is flagged
//   Given run "R" has finished and did not run job "Notify"
//   When I select "Notify" in the IDE with "R" loaded
//   Then the run panel is faded and the run chip turns to its warning style
//   And the chip's tooltip reads "Notify was not part of this run. Pick another job or deselect the run."
//   But while "R" is still running the panel is not faded
// Still pending, old: the warning run chip never opens its tooltip
test('@S08', PENDING, async ({ page }) => {
  const { id, run } = givenRun({ jobs: ['Notify'] });
  await signInAs(page, ME);
  await openRun(page, id, run, 'Fetch');
  const plain = await chipLook(page, run.runId);
  expect(await panelFade(page)).toBe(1);

  await pickJob(page, 'Notify');

  await expect.poll(() => panelFade(page)).toBeLessThan(1);
  await expect.poll(() => chipLook(page, run.runId)).not.toBe(plain);
  await pointAtChip(page, run.runId);
  await expect(page.getByRole('tooltip').first()).toHaveText(
    'Notify was not part of this run. Pick another job or deselect the run.'
  );

  reopenRun(run.runId, 'started');
  await openRun(page, id, run, 'Notify');
  await page.waitForTimeout(1000);
  expect(await panelFade(page)).toBe(1);
});

// @S09
// Scenario: The run links to its work order and to the full run page
//   Given run "R" of work order "W" is loaded with step "S" selected
//   Then "Work Order" links to "/projects/<project id>/history?filters[workorder_id]=<W id>"
//   And "Run" links to "/projects/<project id>/runs/<R id>?step=<S id>"
test('@S09', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun();
  await signInAs(page, ME);

  await openRun(page, id, run, 'Transform');

  const workOrder = await detailLink(page, 'Work Order');
  expect(workOrder.path).toBe(`/projects/${id}/history`);
  expect(workOrder.params.get('filters[workorder_id]')).toBe(run.workOrderId);
  await expect
    .poll(async () => (await detailLink(page, 'Run')).params.get('step'))
    .toBe(run.steps.Transform);
  expect((await detailLink(page, 'Run')).path).toBe(runPath(id, run.runId));
});

// ---------------------------------------------------------------------------
// The run on the canvas
// ---------------------------------------------------------------------------

// @S10
// Scenario: The canvas shows the path a run took
//   Given run "R" of "Intake" started at job "Fetch" by "amara@example.org", "Fetch" succeeded in 2 seconds and "Transform" failed
//   And job "Notify" did not run
//   When I open "Intake" on the canvas with "run=<R id>"
//   Then "Fetch" shows a success badge and its duration, and "Transform" a failure badge with its error type as tooltip
//   And "Notify" and the edge into it are faded
//   And "Fetch" carries a start badge whose tooltip reads "Started by amara@example.org"
//   And a job that ran three times shows a "3" badge
// "Fetch" is the job that ran three times. Annotation 6.1 expects today's
// page to read "Started by unknown" for a run opened by its URL.
// Still pending, old: a run opened by its URL reads "Started by unknown" on its start badge
test('@S10', PENDING, async ({ page }) => {
  const { id, run } = givenRun({
    createdBy: AMARA,
    steps: [
      { name: 'Fetch', seconds: 2 },
      { name: 'Transform', exit: 'fail', errorType: 'RuntimeError' },
    ],
    jobs: ['Notify'],
  });
  connectRunWorkflow(run.workflowId, id, ['Fetch', 'Transform', 'Notify']);
  repeatStep(run.runId, run.steps.Fetch, 3);
  await signInAs(page, ME);

  await openEditor(page, id, run.workflowId, `?run=${run.runId}`);

  await expect
    .poll(() => nodeTips(page, 'Transform'), EVENTUALLY)
    .toContain('RuntimeError');
  const fetchTips = await nodeTips(page, 'Fetch');
  expect(fetchTips).toContainEqual(expect.stringMatching(/success/i));
  expect(fetchTips).toContain(`Started by ${user(AMARA).email}`);
  await expect(node(page, 'Fetch')).toContainText(/2(\.\d+)?\s?s/);
  expect(await nodeFade(page, 'Notify')).toBeLessThan(
    await nodeFade(page, 'Fetch')
  );
  expect(await pathFade(page, 'Transform', 'Notify')).toBeLessThan(
    await pathFade(page, 'Fetch', 'Transform')
  );
  await expect(timesRun(page, 'Fetch')).toHaveText('3');
});

// ---------------------------------------------------------------------------
// Runs that cannot be shown
// ---------------------------------------------------------------------------

// @S11
// Scenario: A run that cannot be loaded says why
//   Given run id "X" does not exist
//   When I open the IDE with "run=<X>"
//   Then the run panel shows "Error loading run" and "Failed to connect: not_found"
//   And for a run in a project I cannot access it shows "Failed to connect: unauthorized"
test('@S11', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  const wf = seedEditorWorkflow(id, OWNER, { steps: ['Fetch'] });
  const kenya = givenProject({}, 'Kenya TB');
  const theirs = runIn(kenya);
  await signInAs(page, ME);

  const rows = [
    [randomUUID(), 'Failed to connect: not_found'],
    [theirs.runId, 'Failed to connect: unauthorized'],
  ] as const;
  for (const [runId, reason] of rows)
    await test.step(reason, async () => {
      await openIde(page, id, wf.id, wf.steps.Fetch, { run: runId });
      await expect(runViewer(page).getByText('Error loading run')).toBeVisible(
        EVENTUALLY
      );
      await expect(runViewer(page).getByText(reason)).toBeVisible();
    });
});

// @S12
// Scenario: A run from another project is not painted onto this workflow
//   Given run "R" belongs to a project other than the editor's
//   When I open "Intake" with "run=<R id>"
//   Then no step data for "R" is preloaded into the page
//   And the canvas paints nothing for "R"
// I am a member of both projects, so only the editor's project scope keeps
// "R" off this canvas. Had it been painted, every step would fade: none of
// its jobs is in "Intake".
test('@S12', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  const wf = seedEditorWorkflow(id, OWNER, { steps: ['Fetch', 'Load'] });
  const kenya = givenProject({ [ME]: 'editor' }, 'Kenya TB');
  const theirs = runIn(kenya);
  await signInAs(page, ME);

  await openEditor(page, id, wf.id, `?run=${theirs.runId}`);

  expect(await preloadedRun(page)).toBeNull();
  await page.waitForTimeout(3000);
  for (const step of ['Fetch', 'Load']) {
    expect(await nodeFade(page, step)).toBe(1);
    expect(await nodeTips(page, step)).toEqual([]);
  }
});

// ---------------------------------------------------------------------------
// Ways in
// ---------------------------------------------------------------------------

// @S13
// Scenario: A run started or opened elsewhere lands in the run viewer
//   When the flow "flow-manual-run-live-follow" starts run "R" from the IDE's run panel
//   Then the run viewer follows "R" with the "Logs" tab
//   When the flow "flow-open-run-in-editor" follows a step inspect link for "R"
//   Then the run viewer shows "R" with that step's job open
// The inspect link is the run page's. The step's own data is not checked:
// annotation 6.1 expects today's viewer to select the run's first step.
test('@S13', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  const wf = seedEditorWorkflow(id, OWNER, { steps: ['Fetch', 'Load'] });
  const seeded = runIn(id, { workflow: 'Intake seeded' });
  await signInAs(page, ME);

  await test.step('a run started from the IDE', async () => {
    await openIde(page, id, wf.id, wf.steps.Fetch);
    await openRunPanel(page);
    await inputChoice(page, 'Empty').click();
    await page.keyboard.press('ControlOrMeta+Enter');

    await expect.poll(() => runRetry.runsOfWorkflow(wf.id).length).toBe(1);
    const [started] = runRetry.runsOfWorkflow(wf.id);
    await expect.poll(() => editorQuery(page).run).toBe(started.id);
    await expect(runChip(page, started.id)).toBeVisible();
    await expect.poll(() => tabShowing(runTab(page, 'Logs'))).toBe(true);
  });

  await test.step("a step's inspect link on the run page", async () => {
    await open(page, runPath(id, seeded.runId));
    const href = await inspectLink(page, seeded.steps.Transform).getAttribute(
      'href'
    );

    await open(page, href!);

    await ideReady(page);
    await expect(jobSelector(page)).toHaveText(/Transform/);
    await expect(runChip(page, seeded.runId)).toBeVisible(EVENTUALLY);
    await expect(statusPill(page)).toBeVisible(EVENTUALLY);
  });
});

// ---------------------------------------------------------------------------
// shared-log-viewer: the "Logs" tab (S01, S02, S03, S05, S06). Read through
// the run viewer's own log, since the IDE's code editor is on screen too.
// ---------------------------------------------------------------------------

test.describe('shared-log-viewer', () => {
  const name = (id: string) =>
    `shared-log-viewer@${id} on workflow-editor-run-viewer`;

  // When I open the Logs tab of <run>
  async function openLog(page: Page, projectId: string, run: SeededRunIds) {
    await signInAs(page, ME);
    await openRun(page, projectId, run, 'Fetch');
    await runTab(page, 'Logs').click();
  }

  // "Posted batch 1" is stored first but logged a second later
  test(name('S01'), PASSING_OLD, async ({ page }) => {
    const { source, lines, shown } = logViewer.given.S01;
    const { id, run } = givenRun({
      steps: [{ name: 'Fetch', seconds: 3 }],
      logs: lines.map(line => ({ ...line, source })),
    });
    await openLog(page, id, run);
    await expect.poll(() => logLines(page), EVENTUALLY).toEqual(shown);

    redeliverLogLine(run.runId, 'Fetched 12 patients');
    await page.waitForTimeout(1500);

    expect(await logLines(page)).toEqual(shown);
  });

  test(name('S02'), PASSING_OLD, async ({ page }) => {
    const { json, notJson } = logViewer.given.S02;
    const { id, run } = givenRun({
      steps: [{ name: 'Fetch' }],
      logs: [{ message: json }, { message: notJson }],
    });
    await openLog(page, id, run);

    await expect
      .poll(() => logLines(page), EVENTUALLY)
      .toEqual([
        'R/T {',
        '  "patients": 12,',
        '  "status": "ok"',
        '}',
        `R/T ${notJson}`,
      ]);
  });

  test(name('S03'), PASSING_OLD, async ({ page }) => {
    const { debug, info } = logViewer.given.S03;
    const { id, run } = givenRun({
      steps: [{ name: 'Fetch' }],
      logs: [
        { message: debug, level: 'debug' },
        { message: info, level: 'info' },
      ],
    });
    await openLog(page, id, run);

    await expect(levelFilter(page)).toHaveText(/^\s*info\s*$/);
    await expect
      .poll(() => logLines(page), EVENTUALLY)
      .toEqual([`R/T ${info}`]);
    await chooseLevel(page, 'debug');
    await expect
      .poll(() => logLines(page))
      .toEqual([`R/T ${debug}`, `R/T ${info}`]);
    await chooseLevel(page, 'warn');
    await expect
      .poll(async () => (await logLines(page)).join(''))
      .not.toMatch(new RegExp(`${debug}|${info}`));
  });

  // Steps are chosen in "Run Steps". The editor has no way to clear a step
  // without choosing another, so the last When picks "Fetch" instead, and
  // only "Fetch"'s lines are then marked.
  // Still pending, old: picking a step marks its log lines from one line early
  test(name('S05'), PENDING, async ({ page }) => {
    const lines = {
      // Short lines: the log panel is narrow and wraps long ones
      Fetch: ['Fetching', 'Fetched 12'],
      Transform: ['Mapping 12', 'Mapped 12'],
    };
    const { id, run } = givenRun({
      steps: [
        { name: 'Fetch', seconds: 2 },
        { name: 'Transform', seconds: 2 },
      ],
      logs: [
        { message: lines.Fetch[0], step: 'Fetch', at: 0.5 },
        { message: lines.Fetch[1], step: 'Fetch', at: 1.5 },
        { message: lines.Transform[0], step: 'Transform', at: 2.5 },
        { message: lines.Transform[1], step: 'Transform', at: 3.5 },
      ],
    });
    await openLog(page, id, run);
    await expect.poll(async () => (await logLines(page)).length).toBe(4);

    await stepRow(page, 'Transform').click();
    await expect
      .poll(() => markedLogLines(page))
      .toEqual(lines.Transform.map(l => `R/T ${l}`));

    await stepRow(page, 'Fetch').click();
    await expect
      .poll(() => markedLogLines(page))
      .toEqual(lines.Fetch.map(l => `R/T ${l}`));
  });

  // The level control stays on the editor's log; only the run page hides it
  test(name('S06'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun({ state: 'lost', steps: [], jobs: ['Fetch'] });
    await openLog(page, id, run);

    await expect(
      runViewer(page).getByText('No logs were received for this run.')
    ).toBeVisible(EVENTUALLY);
  });
});

// ---------------------------------------------------------------------------
// shared-dataclip-body-viewer: the "Input" and "Output" tabs (S01, S02, S04)
// ---------------------------------------------------------------------------

test.describe('shared-dataclip-body-viewer', () => {
  const name = (id: string) =>
    `shared-dataclip-body-viewer@${id} on workflow-editor-run-viewer`;
  const body = { patients: [{ id: 1 }] };
  const formatted = JSON.stringify(body, null, 2);

  // "Fetch"'s input
  test(name('S01'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun({
      input: { type: 'global', body },
      steps: [{ name: 'Fetch' }],
    });
    await signInAs(page, ME);
    await openRun(page, id, run, 'Fetch');
    await runTab(page, 'Input').click();
    await expect.poll(() => bodyText(page), EVENTUALLY).toBe(formatted);

    await typeIntoBody(page, 'typed');

    expect(await bodyText(page)).toBe(formatted);
  });

  // "Fetch"'s output
  test(name('S02'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun({ steps: [{ name: 'Fetch', output: body }] });
    await page
      .context()
      .grantPermissions(['clipboard-read', 'clipboard-write']);
    await signInAs(page, ME);
    await openRun(page, id, run, 'Fetch');
    await runTab(page, 'Output').click();
    await expect.poll(() => bodyText(page), EVENTUALLY).toBe(formatted);

    await copyButton(page).click();

    await expect
      .poll(() => page.evaluate(() => navigator.clipboard.readText()))
      .toBe(formatted);
    await expect(copiedSignal(page)).toBeVisible();
    await expect(copiedSignal(page)).toBeHidden({ timeout: 4000 });
    await expect(copyButton(page)).toBeVisible();
  });

  // "Fetch"'s output, with "Fetch" picked in "Run Steps"
  test(name('S04'), PASSING_OLD, async ({ page }) => {
    const { Login, Fetch, Post, output } = bodyViewer.given.S04;
    const { id, run } = givenRun({
      steps: [
        { name: 'Login', credential: Login },
        { name: 'Fetch', credential: Fetch, output },
        { name: 'Post', credential: Post },
      ],
    });
    await signInAs(page, ME);
    await openRun(page, id, run, 'Login');
    await stepRow(page, 'Fetch').click();
    await runTab(page, 'Output').click();

    const flat = async () => (await bodyText(page)).replace(/\n/g, '');
    await expect.poll(flat, EVENTUALLY).toContain('12***34');
    const text = await flat();
    expect(text).not.toContain('123456');
    expect(text).not.toContain('125534');
    expect(text).toMatch(/"integer":\s*\*\*\*/);
    expect(text).toContain('some-***s');
    expect(text).toMatch(/"bool":\s*true/);
  });
});

// ---------------------------------------------------------------------------
// shared-run-retry-controls: S02 on the IDE header, with the run loaded here.
// S04 runs in workflow-editor-ide.spec.ts.
// ---------------------------------------------------------------------------

test.describe('shared-run-retry-controls', () => {
  test(
    'shared-run-retry-controls@S02 on workflow-editor-run-viewer',
    PASSING_OLD,
    async ({ page }) => {
      const { id, run } = givenRun();
      await signInAs(page, ME);
      await openRun(page, id, run, 'Fetch');

      await runRetry.S02(page, ideHeader(page), run);
    }
  );
});

// ---------------------------------------------------------------------------
// shared-run-components: the React ports the run viewer draws (S15 to S18)
// ---------------------------------------------------------------------------

test.describe('shared-run-components', () => {
  const name = (id: string) =>
    `shared-run-components@${id} on workflow-editor-run-viewer`;

  // Each pill also has the text colour the run page gives it
  test(name('S15'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    const colourOf = async (pill: ReturnType<typeof statusPill>) =>
      (await lookOf(pill)).split(' @ ')[0];

    for (const [state, label] of STATE_LABELS)
      await test.step(`a run in state "${state}"`, async () => {
        const run = runInState(id, state);
        await openRun(page, id, run, 'Fetch');
        await runComponents.S01(page, [[statusPill(page), label]]);
        // The pill is the element holding the label, not the detail around it
        const pill = new RegExp(`^\\s*${label}\\s*$`, 'i');
        const inEditor = await colourOf(
          statusPill(page).getByText(pill).first()
        );

        await open(page, runPath(id, run.runId));
        expect(
          await colourOf(runPageDetail(page, 'Status').getByText(pill).first())
        ).toBe(inEditor);
      });
  });

  // The crashed step's orange is not checked: the shared icon reader only
  // tells green, red and grey apart
  test(name('S16'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun(OUTCOMES);
    await signInAs(page, ME);
    await openRun(page, id, run, 'Fetch');

    await expectOutcomeIcons(page);
  });

  // The run that finishes after 90 seconds is a second step of the same run
  test(name('S17'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun({
      state: 'started',
      steps: [
        { name: 'Fetch', seconds: 90 },
        { name: 'Load', exit: null, seconds: 5 },
      ],
    });
    const waiting = runIn(id, {
      workflow: 'Intake waiting',
      state: 'available',
      steps: [],
      jobs: ['Fetch'],
    });
    await signInAs(page, ME);
    await openRun(page, id, run, 'Fetch');

    await runComponents.S04(page, stepDuration(page, 'Load'));
    await expect(stepDuration(page, 'Fetch')).toHaveText('1 m');
    await page.waitForTimeout(1500);
    await expect(stepDuration(page, 'Fetch')).toHaveText('1 m');

    await openRun(page, id, waiting, 'Fetch');
    await expect(runDuration(page)).toHaveText('Not started');
  });

  test(name('S18'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun(RETRIED);
    await signInAs(page, ME);
    await openRun(page, id, run, 'Transform');

    await expectCarriedMarked(page, 'Fetch', 'Transform');
  });
});
