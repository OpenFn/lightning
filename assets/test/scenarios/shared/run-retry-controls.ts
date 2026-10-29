// Scenarios from annotations/shared/shared-run-retry-controls.md: the Run and
// Retry controls of the workflow editor's header, step inspector, run panel
// and full-screen IDE. Hosts: workflow-editor-canvas (header: S01 to S03,
// S07, S10, S11, S13), workflow-editor-inspectors ("Run From Here": S10),
// workflow-editor-manual-run (panel: S04 to S10, S13) and workflow-editor-ide
// (S04 to S10, S13); S12 is the retry endpoint and needs no surface. S11 and
// S12 need only a page signed in as the person the Given names.
//
// The host owns the Given: it seeds (seedRun from steps.ts for a workflow with
// a run; finishRun and wipeInput below), signs in, opens the editor with the
// surface showing, and hands over that surface: the element holding the
// control (the header, the step inspector, the run panel, the IDE header).
// The functions find the control in it by name, act, and read the database.
import { expect, type Locator, type Page } from '@playwright/test';

import { lastLine, onNode, pointAt, runsOfWorkOrder, sql } from '../steps';

// ---------------------------------------------------------------------------
// How the editor is built. Everything that knows the controls' shape, the
// toasts, the URL and the endpoints lives here.
// ---------------------------------------------------------------------------

// The main run control, whatever it reads now: the header's "Run" or
// "Retry", the inspector's "Run From Here", the panel's "Run From Here" or
// "Retry", the IDE's "Run" or "Retry", and "Processing" while busy
export const runButton = (surface: Locator) =>
  surface.getByRole('button', {
    name: /^\s*(Run|Run From Here|Run Workflow|Retry|Processing)\s*$/,
  });

// The chevron beside a split run control
export const runOptions = (surface: Locator) =>
  surface.getByRole('button', { name: /^Open (run )?options$/ });

// The chevron's "Run (New Work Order)"
const newWorkOrderItem = (page: Page) =>
  page
    .getByRole('button', { name: 'Run (New Work Order)' })
    .or(page.getByRole('menuitem', { name: 'Run (New Work Order)' }));

const RUN_KEYS = 'ControlOrMeta+Enter';
const NEW_WORK_ORDER_KEYS = 'ControlOrMeta+Shift+Enter';

// A toast with <text>. Today they are sonner's, listed in a region named
// "Notifications".
export const toast = (page: Page, text: string | RegExp) =>
  page
    .getByRole('region', { name: /^Notifications/ })
    .getByRole('listitem')
    .or(page.getByRole('status'))
    .or(page.getByRole('alert'))
    .filter({ hasText: text })
    .first();

const searchParam = (page: Page, name: string) =>
  new URL(page.url()).searchParams.get(name);

// The URL params a pinned view carries
const PINNED_PARAMS = ['release', 'v', 'as_run', 'step'];

// The text of the focused code or input editor. Today both are Monaco.
const focusedEditorText = (page: Page) =>
  page
    .locator('.monaco-editor.focused .view-lines')
    .innerText()
    .catch(() => '');

// What the run and retry endpoints answer to a request sent as the page
// would send it, past every control: the page's cookies and CSRF token
export async function postAsPage(
  page: Page,
  path: string,
  data: Record<string, unknown>
) {
  const token = await page
    .locator('meta[name="csrf-token"]')
    .getAttribute('content');
  return page.request.post(path, {
    headers: { 'x-csrf-token': token ?? '' },
    data,
    maxRedirects: 0,
  });
}

const createRunPath = (projectId: string, workflowId: string) =>
  `/projects/${projectId}/workflows/${workflowId}/runs`;
const retryPath = (projectId: string, runId: string) =>
  `/projects/${projectId}/runs/${runId}/retry`;

// ---------------------------------------------------------------------------

type StoredRun = {
  id: string;
  work_order_id: string;
  starting_trigger_id: string | null;
  starting_job_id: string | null;
  dataclip_id: string;
  input: unknown;
};

// The runs of a workflow, oldest first
export const runsOfWorkflow = (workflowId: string) =>
  sql<StoredRun>(
    `select r.id, r.work_order_id, r.starting_trigger_id, r.starting_job_id,
            r.dataclip_id, d.body as input
     from runs r join work_orders w on w.id = r.work_order_id
     left join dataclips d on d.id = r.dataclip_id
     where w.workflow_id = '${workflowId}' order by r.inserted_at`
  );

const workOrdersOf = (workflowId: string) =>
  sql<{ id: string }>(
    `select id from work_orders where workflow_id = '${workflowId}'`
  ).length;

const lockVersionOf = (workflowId: string) =>
  sql<{ lock_version: number }>(
    `select lock_version from workflows where id = '${workflowId}'`
  )[0].lock_version;

// The job of the first step run <runId> ran
const firstJobOf = (runId: string) =>
  sql<{ job_id: string }>(
    `select s.job_id from run_steps rs join steps s on s.id = rs.step_id
     where rs.run_id = '${runId}' order by s.started_at limit 1`
  )[0].job_id;

// Waits for exactly one run more than <before> and returns it
// The body of input <dataclipId>
const inputBody = (dataclipId: string) =>
  sql<{ body: unknown }>(
    `select body from dataclips where id = '${dataclipId}'`
  )[0]?.body;

async function newRun(workflowId: string, before: number) {
  await expect
    .poll(() => runsOfWorkflow(workflowId).length, 'a run is created')
    .toBe(before + 1);
  const runs = runsOfWorkflow(workflowId);
  return runs[runs.length - 1];
}

// Then nothing is created, once the control's request has had time to land
async function expectNoNewRun(workflowId: string, before: number) {
  await new Promise(resolve => setTimeout(resolve, 2000));
  expect(runsOfWorkflow(workflowId)).toHaveLength(before);
}

async function start(page: Page, surface: Locator, how: 'click' | 'keys') {
  if (how === 'click') await runButton(surface).click();
  else await page.keyboard.press(RUN_KEYS);
}

export type Workflow = { id: string; projectId: string };
export type FollowedRun = {
  workflowId: string;
  workOrderId: string;
  runId: string;
};

// @S01 Quick run from the header
//   Given I am an editor with "Intake" open, a trigger "Webhook" and no run loaded
//   When I click "Run" in the header, or press Ctrl+Enter with no panel or IDE open
//   Then the workflow is saved and a run starts from "Webhook" with an empty input
//   And I see "Run started" with "Saved latest changes and created new work order"
//   And the run panel does not open
//   And the URL has "run=<new run id>" and the flow "flow-manual-run-live-follow" has started
// Saving first is S08's to prove. The live follow is its own flow's.
export async function S01(
  page: Page,
  header: Locator,
  workflow: Workflow & { triggerId: string },
  how: 'click' | 'keys' = 'click'
) {
  const runs = runsOfWorkflow(workflow.id).length;
  const workOrders = workOrdersOf(workflow.id);
  await expect(runButton(header)).toHaveText(/^\s*Run\s*$/);

  await start(page, header, how);

  const run = await newRun(workflow.id, runs);
  expect(workOrdersOf(workflow.id)).toBe(workOrders + 1);
  // Starting from the trigger may be stored as the step the trigger leads to
  const [after] = sql<{ id: string }>(
    `select target_job_id as id from workflow_edges
       where source_trigger_id = '${workflow.triggerId}'`
  );
  expect([workflow.triggerId, null]).toContain(run.starting_trigger_id);
  if (!run.starting_trigger_id) expect(run.starting_job_id).toBe(after?.id);
  expect([null, {}]).toContainEqual(run.input);
  await expect(toast(page, 'Run started')).toBeVisible();
  await expect.poll(() => searchParam(page, 'run')).toBe(run.id);
  expect(searchParam(page, 'panel')).toBeNull();
}

// @S02 Retry a finished run from the header
//   Given run "R" of "Intake" has finished and is loaded with "run=<R id>"
//   When I look at the header
//   Then the run button reads "Retry"
//   When I click it, or press Ctrl+Enter
//   Then the workflow is saved and a new run is created on R's work order from R's first step
//   And no new work order is created
//   And I see "Retry started" with "Saved latest changes and re-running this input on <version>."
//   And the URL has "run=<new run id>"
export async function S02(
  page: Page,
  header: Locator,
  run: FollowedRun,
  how: 'click' | 'keys' = 'click'
) {
  const runs = runsOfWorkflow(run.workflowId).length;
  const workOrders = workOrdersOf(run.workflowId);
  await expect(runButton(header)).toHaveText(/Retry/);

  await start(page, header, how);

  const retry = await newRun(run.workflowId, runs);
  expect(retry.work_order_id).toBe(run.workOrderId);
  expect(retry.starting_job_id).toBe(firstJobOf(run.runId));
  expect(workOrdersOf(run.workflowId)).toBe(workOrders);
  await expect(toast(page, 'Retry started')).toBeVisible();
  await expect.poll(() => searchParam(page, 'run')).toBe(retry.id);
}

// @S03 Retrying from an older version runs the latest version and says so
//   Given I am viewing "Intake" pinned to v2 with finished run "R" loaded, and v3 is current
//   Then a fresh run is refused with "You are viewing a pinned version of this workflow"
//   But the header offers "Retry" with the tooltip "Runs this input on the latest version (v3), not v2."
//   When I click "Retry"
//   Then the workflow is not saved
//   And the URL loses "release", "v", "as_run" and "step" and has "run=<new run id>"
// Experimental features on. The fresh-run refusal is S10's pinned row.
export async function S03(
  page: Page,
  header: Locator,
  run: FollowedRun,
  _versions: { pinned: number; latest: number }
) {
  const runs = runsOfWorkflow(run.workflowId).length;
  const version = lockVersionOf(run.workflowId);
  await expect(runButton(header)).toHaveText(/Retry/);
  await page.mouse.move(0, 0);
  await runButton(header).hover();
  await expect(
    // The version numbers are the app's own (releases or lock versions), so
    // only the wording is checked
    page.getByRole('tooltip').filter({
      hasText: /Runs this input on the latest version.*, not v\d+\./,
    })
  ).toBeVisible();

  await runButton(header).click();

  const retry = await newRun(run.workflowId, runs);
  expect(retry.work_order_id).toBe(run.workOrderId);
  await expect.poll(() => searchParam(page, 'run')).toBe(retry.id);
  for (const name of PINNED_PARAMS) expect(searchParam(page, name)).toBeNull();
  expect(lockVersionOf(run.workflowId)).toBe(version);
}

// @S04 Retry is offered only for the input the run used
//   Given run "R" is followed and its "Fetch" step took input "D", not wiped
//   When the run panel or the IDE is on "Fetch" with "D" selected
//   Then the button reads "Retry" with a chevron
//   When I select a different input, or "D" has been wiped
//   Then the button reads "Run" without a chevron
// <change> selects another input, or wipes D (wipeInput) and reopens.
export async function S04(
  _page: Page,
  surface: Locator,
  change: () => Promise<void>
) {
  await expect(runButton(surface)).toHaveText(/Retry/);
  await expect(runOptions(surface)).toBeVisible();

  await change();

  await expect(runButton(surface)).toHaveText(/^\s*Run/);
  await expect(runOptions(surface)).toHaveCount(0);
}

// @S05 Retry continues the work order, the chevron starts a new one
//   Given the panel or the IDE offers "Retry" for run "R"
//   When I click "Retry"
//   Then a new run is created on R's work order and the upstream steps are attached, not executed again
//   When I instead open the chevron and choose "Run (New Work Order)", or press Ctrl+Shift+Enter
//   Then a new work order is created with the same input
//   And R's work order gets no new run
// <upstream> are the ids of R's steps before the retried one. <reopen> puts
// the surface back on R (a retry leaves it following the new run).
export async function S05(
  page: Page,
  surface: Locator,
  run: FollowedRun & { upstream: string[] },
  reopen: () => Promise<void>,
  how: 'menu' | 'keys' = 'menu'
) {
  const runs = runsOfWorkflow(run.workflowId).length;
  const workOrders = workOrdersOf(run.workflowId);
  await expect(runButton(surface)).toHaveText(/Retry/);
  await runButton(surface).click();

  const retry = await newRun(run.workflowId, runs);
  expect(retry.work_order_id).toBe(run.workOrderId);
  expect(workOrdersOf(run.workflowId)).toBe(workOrders);
  const carried = sql<{ step_id: string }>(
    `select step_id from run_steps where run_id = '${retry.id}'`
  ).map(r => r.step_id);
  expect(carried).toEqual(expect.arrayContaining(run.upstream));

  await reopen();
  const onR = runsOfWorkOrder(run.workOrderId).length;
  await expect(runButton(surface)).toHaveText(/Retry/);
  if (how === 'menu') {
    await runOptions(surface).click();
    await newWorkOrderItem(page).click();
  } else {
    await page.keyboard.press(NEW_WORK_ORDER_KEYS);
  }

  const fresh = await newRun(run.workflowId, runs + 1);
  expect(fresh.work_order_id).not.toBe(run.workOrderId);
  expect(workOrdersOf(run.workflowId)).toBe(workOrders + 1);
  // The same input: the new work order may store it as a copy
  expect(inputBody(fresh.dataclip_id)).toEqual(inputBody(retry.dataclip_id));
  expect(runsOfWorkOrder(run.workOrderId)).toHaveLength(onR);
}

// @S06 Run and retry from the keyboard while typing
//   Given the run panel or the IDE has a valid input and I can run
//   When I press Ctrl+Enter, or Cmd+Enter on a Mac, with my cursor in the code or input editor
//   Then a run starts, or a retry when one is offered
//   And the browser's default action for the keys does not happen
// <focus> puts the cursor in the code or input editor.
export async function S06(
  page: Page,
  workflowId: string,
  focus: () => Promise<void>
) {
  const runs = runsOfWorkflow(workflowId).length;
  await focus();
  const text = await focusedEditorText(page);

  await page.keyboard.press(RUN_KEYS);

  await newRun(workflowId, runs);
  expect(await focusedEditorText(page)).toBe(text);
}

// @S07 The shortcut acts on the surface in front of me
//   Given the run panel for "Fetch" is open over the canvas
//   When I press Ctrl+Enter
//   Then the run starts from "Fetch", not from the first trigger
//   And the header's Run button is disabled
//   When the IDE is open instead
//   Then Ctrl+Enter is handled by the IDE and the header does nothing
// The host opens the panel for <fetchJobId>; <openIde> opens the IDE on the
// same step instead (a fresh page, so the panel's run is not followed).
export async function S07(
  page: Page,
  header: Locator,
  workflowId: string,
  fetchJobId: string,
  openIde?: () => Promise<void>
) {
  const runsFromFetch = async () => {
    const runs = runsOfWorkflow(workflowId).length;
    await expect(runButton(header)).toBeDisabled();

    await page.keyboard.press(RUN_KEYS);

    const run = await newRun(workflowId, runs);
    expect(run.starting_job_id).toBe(fetchJobId);
    expect(run.starting_trigger_id).toBeNull();
    await expectNoNewRun(workflowId, runs + 1);
  };

  await runsFromFetch();
  if (!openIde) return;
  await openIde();
  await runsFromFetch();
}

// @S08 A run never starts if the workflow can't be saved first
//   Given "Intake" has a change the server will not save
//   When I start a run or a retry from any run control
//   Then no work order and no run is created
//   And I see "Failed to submit run" or "Retry failed" with the save error
// The host makes the change (for example a step pointed at a credential
// outside the project, as adaptor-credential-config S16 does).
export async function S08(page: Page, surface: Locator, workflowId: string) {
  const runs = runsOfWorkflow(workflowId).length;
  const workOrders = workOrdersOf(workflowId);

  await runButton(surface).click();

  await expect(toast(page, /Failed to submit run|Retry failed/)).toBeVisible();
  await expectNoNewRun(workflowId, runs);
  expect(workOrdersOf(workflowId)).toBe(workOrders);
}

// @S09 A live workflow runs without saving
//   Given "Intake" is live and content-locked
//   When I start a run from any run control
//   Then the workflow is not saved
//   And I see "Run started" with "Created new work order"
// Experimental features on.
export async function S09(page: Page, surface: Locator, workflowId: string) {
  const runs = runsOfWorkflow(workflowId).length;
  const version = lockVersionOf(workflowId);

  await runButton(surface).click();

  await newRun(workflowId, runs);
  await expect(toast(page, 'Run started')).toBeVisible();
  await expect(toast(page, 'Saved latest changes')).toHaveCount(0);
  expect(lockVersionOf(workflowId)).toBe(version);
}

export const given = {
  S10: {
    disconnected: 'You are disconnected. Reconnecting...',
    viewer: 'You do not have permission to run workflows',
    deleted: 'Workflow has been deleted',
    pinned: 'You are viewing a pinned version of this workflow',
    unsaved: 'Create this workflow before running it',
  },
  S11: { limit: 'Run limit reached' },
  S12: { viewer: 401, otherProject: 422, signedOut: 302 },
};

// @S10 A disabled run control says why
//   Given <state>
//   When I look at the header Run, the step inspector's "Run From Here", the panel's run button and the IDE's run button
//   Then each is disabled with the reason <reason>
// One surface per call; <reason> is a value of given.S10.
export async function S10(page: Page, surface: Locator, reason: string) {
  const control = runButton(surface);
  await expect(control).toBeDisabled();
  await page.mouse.move(0, 0);
  await pointAt(control);
  await expect(
    page.getByRole('tooltip').filter({ hasText: reason })
  ).toBeVisible();
}

// @S11 Run limits refuse up front and on the server
//   Given the usage limiter refuses new runs in "Malawi HIV" with "Run limit reached"
//   When I open "Intake"
//   Then the run controls are disabled with the reason "Run limit reached"
//   When a run or a retry is posted anyway
//   Then the response is 400 with "Run limit reached" and no run is created
//   And a control that sent it shows the refusal in its failure toast
// The host refuses with withLimiterRefusing('new_run', given.S11.limit) from
// steps.ts before opening. The controls are disabled, so none sends; the
// refusal is checked on the posts.
export async function S11(
  page: Page,
  surface: Locator,
  workflow: Workflow & { triggerId: string },
  retry?: { runId: string; stepId: string }
) {
  await S10(page, surface, given.S11.limit);
  const runs = runsOfWorkflow(workflow.id).length;

  const posts = [
    postAsPage(page, createRunPath(workflow.projectId, workflow.id), {
      trigger_id: workflow.triggerId,
    }),
  ];
  if (retry)
    posts.push(
      postAsPage(page, retryPath(workflow.projectId, retry.runId), {
        step_id: retry.stepId,
      })
    );
  for (const response of await Promise.all(posts)) {
    expect(response.status()).toBe(400);
    expect(await response.text()).toContain(given.S11.limit);
  }
  await expectNoNewRun(workflow.id, runs);
}

// @S12 The server retries only for people who may run, inside the project
//   Given run "R" belongs to "Intake" in project "Malawi HIV"
//   And <who>
//   When a retry of "R" is posted through <project>
//   Then no new run is created and the response is <status>
// <page> is signed in as <who> (or signed out, on any page carrying a CSRF
// token); <status> is a value of given.S12.
export async function S12(
  page: Page,
  run: FollowedRun & { stepId: string },
  throughProjectId: string,
  status: number
) {
  const runs = runsOfWorkflow(run.workflowId).length;

  const response = await postAsPage(
    page,
    retryPath(throughProjectId, run.runId),
    { step_id: run.stepId }
  );

  expect(response.status()).toBe(status);
  await expectNoNewRun(run.workflowId, runs);
}

// @S13 One click starts one run
//   Given I start a run or a retry from any run control
//   Then while it is being submitted the control reads "Processing" with a spinner and is disabled
//   And a second click or Ctrl+Enter starts nothing
//   And while the followed run has not finished the control stays "Processing"
//   When the run reaches a final state
//   Then the control is enabled again
// Lightning must have no worker taking runs, so the run stays unfinished
// until finishRun.
export async function S13(page: Page, surface: Locator, workflowId: string) {
  const runs = runsOfWorkflow(workflowId).length;

  await runButton(surface).click({ clickCount: 2 });
  await page.keyboard.press(RUN_KEYS);

  await expect(runButton(surface)).toHaveText(/Processing/);
  await expect(runButton(surface)).toBeDisabled();
  const run = await newRun(workflowId, runs);
  await expectNoNewRun(workflowId, runs + 1);
  await expect(runButton(surface)).toHaveText(/Processing/);

  finishRun(run.id);

  await expect(runButton(surface)).not.toHaveText(/Processing/);
  await expect(runButton(surface)).toBeEnabled();
}

// Seeding for hosts

// When run <runId> finishes, as a worker would finish it: claimed, started
// and completed through Lightning, which tells the editor
export function finishRun(runId: string, state = 'success') {
  const out = onNode(`
      run = Lightning.Repo.get!(Lightning.Run, ${JSON.stringify(runId)})
      # The e2e worker may have finished it already
      if run.state in Lightning.Run.final_states(), do: IO.puts(":finished"), else: :ok
      run =
        if run.state == :available,
          do: run |> Ecto.Changeset.change(state: :claimed, claimed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)) |> Lightning.Repo.update!(),
          else: run
      {:ok, run} = if run.state == :claimed, do: Lightning.Runs.start_run(run), else: {:ok, run}
      {:ok, run} =
        if run.state in Lightning.Run.final_states(),
          do: {:ok, run},
          else: Lightning.Runs.complete_run(run, %{"state" => ${JSON.stringify(state)}})
      run.state`);
  if (!out.includes(':finished')) expect(lastLine(out)).toBe(`:${state}`);
}

// Given input <dataclipId> has been wiped by the project's retention policy
export function wipeInput(dataclipId: string) {
  onNode(`
    import Ecto.Query
    Lightning.Repo.update_all(
      Lightning.Invocation.Query.wipe_dataclips(from d in Lightning.Invocation.Dataclip, where: d.id == ^${JSON.stringify(dataclipId)}),
      [])
    :ok`);
}
