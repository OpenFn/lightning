// Scenarios from annotations/views/run-show.md.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names (a viewer unless it says otherwise). owner@openfn.org owns every
// project and builds its workflows and runs through Lightning.
// super@openfn.org is the third member a test needs. Every project is seeded
// by the test and removed again afterwards, with its runs, dataclips and the
// credentials its steps used.
import { expect, test, type Page } from '@playwright/test';

import {
  cancelButton,
  detail,
  detailLabel,
  expectDisabledTab,
  expectSelectedStep,
  inspectLink,
  lastCrumb,
  panel,
  projectAdmins,
  runStep,
  selectStep,
  stepNamed,
  sendCancelFor,
  stepDuration,
  versionChip,
  workflowLink,
} from './pages/run-show';
import * as authenticatedSession from './shared/authenticated-session';
import * as bodyViewer from './shared/dataclip-body-viewer';
import * as flashMessages from './shared/flash-messages';
import * as hashTabs from './shared/hash-tabs';
import * as localDatetime from './shared/local-datetime';
import * as logViewer from './shared/log-viewer';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as runComponents from './shared/run-components';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  changeRoleOnNode,
  changeWorkflowOnNode,
  claimRun,
  dataclipPath,
  exec,
  expectAt,
  expectHistoryOrder,
  chip,
  keepAccount,
  keepNoData,
  mailedLinkTo,
  makeSupportUser,
  manifest,
  open,
  otherSession,
  PASSWORD,
  preferencesOf,
  redeliverLogLine,
  removeMemberOnNode,
  removeMfaOf,
  removeWorkflowData,
  runPath,
  scheduleDeletionOnNode,
  seedDataclip,
  seedRun,
  seedUser,
  seedWorkspace,
  sendFailureAlertOnNode,
  setPreferences,
  setSupportAccessOnNode,
  shortId,
  signInAs,
  snapshotTakenAt,
  submitLogin,
  user,
  utcStamp,
  workerReports,
  type RunSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING = { tag: ['@passing-old', '@passing-new'] };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests change my preferences, disable or MFA me
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it);
// removed after the test with its runs and dataclips — returns its id
function givenProject(
  members: Record<string, Role> = { [ME]: 'viewer' },
  { name = 'Malawi HIV', ...rest }: Partial<WorkspaceSeed> = {}
) {
  const owned = Object.values(members).includes('owner')
    ? members
    : { ...members, [OWNER]: 'owner' as const };
  const by = Object.entries(owned).find(([, r]) => r === 'owner')![0];
  const w = seedWorkspace({ name, members: owned, ...rest }, by);
  cleanups.push(w.remove);
  const id = w.id(name);
  // Runs before the project is removed: runs and steps hold references
  cleanups.push(() => removeWorkflowData(id));
  return { id, w, by };
}

// Given project <projectId> has a run seeded by its owner — returns its ids.
// Its credentials are removed after the project.
function givenRun(projectId: string, seed: RunSeed) {
  const run = seedRun(projectId, seed, OWNER);
  cleanups.unshift(run.removeCredentials);
  return run;
}

// When I sign in and open run <runId> of project <projectId>, with <rest>
// (a query and fragment) after its path
async function openRun(
  page: Page,
  projectId: string,
  runId: string,
  rest = ''
) {
  await signInAs(page, ME);
  await open(page, `${runPath(projectId, runId)}${rest}`);
}

// When I open the run page's <label> tab
const openTab = (page: Page, label: string) =>
  hashTabs.tab(page, label).click();

// The step data a tab shows: the body viewer's lines
const shownBody = (page: Page) => bodyViewer.viewerText(page);
const formatted = (body: object) => JSON.stringify(body, null, 2);

// Text on screen, wherever the page puts it
const onScreen = (page: Page, text: string | RegExp) =>
  page.getByText(text).filter({ visible: true });

// @S01
// Scenario: The run's summary shows what ran, when and how it ended
//   Given workflow "Intake" in project "Malawi HIV" has a run that a webhook request started
//   When I open the run page
//   Then the breadcrumb reads "Run" followed by the run's short id
//   And I see "Workflow" linking to "Intake"
//   And I see "Work Order" with the work order's short id
//   And I see "Started by" reading "Webhook trigger"
//   And I see "Started", "Finished", "Duration" and "Status"
test('@S01', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenRun(projectId, { steps: [{ name: 'Fetch' }] });
  await openRun(page, projectId, run.runId);

  await expect
    .poll(() => lastCrumb(page))
    .toMatch(new RegExp(`^Run ?${shortId(run.runId)}(\\s|$)`));
  await expect(workflowLink(page)).toHaveText(/^\s*Intake\s*$/);
  await expect(detail(page, 'Work Order')).toHaveText(
    new RegExp(`^\\s*${shortId(run.workOrderId)}\\s*$`)
  );
  await expect(detail(page, 'Started by')).toHaveText(
    /^\s*Webhook trigger\s*$/
  );
  for (const label of ['Started', 'Finished', 'Duration', 'Status'])
    await expect.soft(detailLabel(page, label), label).toBeVisible();
});

// @S02
// Scenario Outline: "Started by" names the person or the trigger
//   Given a run of workflow "Intake" <started>
//   When I open the run page
//   Then "Started by" reads <label>
//   Examples: a webhook request "Webhook trigger"; its cron trigger "Cron
//   trigger"; retried by "amara@example.org" from History, "amara@example.org"
// Amara's address is new each run, as every worker sees every account.
test('@S02', PASSING, async ({ page }) => {
  const amara = seedUser('amara');
  cleanups.push(amara.remove);
  const { id: projectId } = givenProject();
  const examples: [RunSeed, string][] = [
    [{ trigger: 'webhook' }, 'Webhook trigger'],
    [{ trigger: 'cron' }, 'Cron trigger'],
    [{ createdBy: amara.email }, amara.email],
  ];
  await signInAs(page, ME);
  for (const [seed, label] of examples) {
    const run = givenRun(projectId, {
      ...seed,
      workflow: `Intake ${label}`,
      steps: [{ name: 'Fetch' }],
    });
    await open(page, runPath(projectId, run.runId));
    await expect
      .soft(detail(page, 'Started by'), label)
      .toHaveText(new RegExp(`^\\s*${label}\\s*$`));
  }
});

// @S03
// Scenario: The version chip says whether the run used the latest workflow
//   Given a run executed on workflow "Intake" at its current version
//   And another run executed on an older snapshot of "Intake"
//   When I open the first run
//   Then the breadcrumb shows a "latest" chip with tooltip "This run is based on the latest version of this workflow."
//   When I open the second run
//   Then the chip shows the first seven characters of the snapshot id
//   And its tooltip says the run is based on a snapshot taken on that snapshot's date and time
// The current run is of another workflow that has not changed since: each
// seeded run builds its own workflow.
test('@S03', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const older = givenRun(projectId, { steps: [{ name: 'Fetch' }] });
  changeWorkflowOnNode(projectId, 'Intake', OWNER);
  const current = givenRun(projectId, {
    workflow: 'Intake today',
    steps: [{ name: 'Fetch' }],
  });

  await openRun(page, projectId, current.runId);
  await expect(versionChip(page)).toHaveText(/latest/);
  await versionChip(page).hover();
  await expect(page.getByRole('tooltip')).toContainText(
    'This run is based on the latest version of this workflow.'
  );

  await open(page, runPath(projectId, older.runId));
  await expect(versionChip(page)).toHaveText(
    new RegExp(older.snapshotId.slice(0, 7))
  );
  await versionChip(page).hover();
  await expect(page.getByRole('tooltip')).toContainText(
    `This run is based on a snapshot of this workflow that was taken on ${snapshotTakenAt(older.snapshotId)}`
  );
});

// @S04
// Scenario: The final output links to the stored result
//   Given a run of "Intake" finished with a final output
//   When I open the run page
//   Then "Final Output" shows the output's short id linking to "/projects/<project_id>/dataclips/<dataclip_id>/show"
//   And when a run finished without a final output, "Final Output" is empty
test('@S04', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const withOutput = givenRun(projectId, {
    steps: [{ name: 'Fetch' }],
    finalState: { patients: 3 },
  });
  expect(withOutput.finalId, 'the run has a final output').not.toBeNull();
  const without = givenRun(projectId, {
    workflow: 'Intake without output',
    steps: [{ name: 'Fetch' }],
  });

  await openRun(page, projectId, withOutput.runId);
  const link = detail(page, 'Final Output').getByRole('link');
  await expect(link).toHaveText(
    new RegExp(`^\\s*${shortId(withOutput.finalId!)}\\s*$`)
  );
  await expect(link).toHaveAttribute(
    'href',
    dataclipPath(projectId, withOutput.finalId!)
  );

  await open(page, runPath(projectId, without.runId));
  await expect(detailLabel(page, 'Final Output')).toBeVisible();
  await expect(detail(page, 'Final Output')).toHaveText(/^\s*$/);
});

// @S05
// Scenario: The work order link opens that work order in History
//   Given a run of work order "W"
//   When I click the work order's short id
//   Then I am on History with "filters[workorder_id]" set to "W"
//   And history-work-orders S10 holds
// history-work-orders S10: only "W" is listed, under a chip "Work order:
// <short id of W>".
test('@S05', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenRun(projectId, { steps: [{ name: 'Fetch' }] });
  givenRun(projectId, { workflow: 'Another', steps: [{ name: 'Fetch' }] });
  await openRun(page, projectId, run.runId);

  await detail(page, 'Work Order')
    .getByRole('link', { name: shortId(run.workOrderId) })
    .click();

  await expectAt(page, `/projects/${projectId}/history`);
  expect(new URL(page.url()).searchParams.get('filters[workorder_id]')).toBe(
    run.workOrderId
  );
  await expectHistoryOrder(page, [run.workOrderId]);
  await expect(chip(page, /^Work order:/)).toContainText(
    `Work order: ${shortId(run.workOrderId)}`
  );
});

// @S06
// Scenario: A run from another project cannot be opened
//   Given I am an editor on project "Malawi HIV"
//   And run "R" belongs to project "Kenya TB"
//   When I visit "/projects/<Malawi HIV id>/runs/<R id>"
//   Then I am on the "Malawi HIV" history page
//   And I see "Run not found"
//   And the same happens for a run id that does not exist
// I am an editor on "Kenya TB" too, so only the project in the URL refuses.
test('@S06', PASSING, async ({ page }) => {
  const malawi = givenProject({ [ME]: 'editor' });
  const kenya = givenProject({ [ME]: 'editor' }, { name: 'Kenya TB' });
  const r = givenRun(kenya.id, { steps: [{ name: 'Fetch' }] });
  await signInAs(page, ME);

  for (const id of [r.runId, '00000000-0000-4000-8000-000000000000']) {
    await page.goto(runPath(malawi.id, id));
    await expectAt(page, `/projects/${malawi.id}/history`);
    await expect
      .soft(flashMessages.toast(page, 'Run not found'), id)
      .toBeVisible();
  }
});

// Given a finished run whose steps "Fetch" and "Transform" stored their
// input and output: Fetch read the webhook's body, Transform read Fetch's
// output
const TWO_STEPS = {
  input: { patients: 12 },
  Fetch: { fetched: 12 },
  Transform: { transformed: 12 },
};
// What Fetch received: a webhook request's body comes wrapped with its request
const FETCH_INPUT = { data: TWO_STEPS.input, request: null };
function givenTwoStepRun(projectId: string, seed: RunSeed = {}) {
  return givenRun(projectId, {
    input: { type: 'http_request', body: TWO_STEPS.input },
    steps: [
      { name: 'Fetch', output: TWO_STEPS.Fetch },
      { name: 'Transform', output: TWO_STEPS.Transform },
    ],
    ...seed,
  });
}

// @S07
// Scenario: Selecting a step shows its input and output
//   Given a run whose steps "Fetch" and "Transform" have finished with stored input and output
//   When I select "Fetch" in the step list
//   Then the URL carries "step=<Fetch step id>"
//   And "Fetch" is marked as selected
//   And the "Input" tab shows "Fetch"'s input
//   And the "Output" tab shows "Fetch"'s output
//   When I select "Transform" and then "Fetch" again
//   Then the "Output" tab shows "Fetch"'s output again
test('@S07', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenTwoStepRun(projectId);
  await openRun(page, projectId, run.runId);

  await selectStep(page, run.steps.Fetch, 'Fetch');

  await expect
    .poll(() => new URL(page.url()).searchParams.get('step'))
    .toBe(run.steps.Fetch);
  await expectSelectedStep(page, run.steps, 'Fetch');
  await openTab(page, 'Input');
  await expect.poll(() => shownBody(page)).toBe(formatted(FETCH_INPUT));
  await openTab(page, 'Output');
  await expect.poll(() => shownBody(page)).toBe(formatted(TWO_STEPS.Fetch));

  await selectStep(page, run.steps.Transform, 'Transform');
  await expectSelectedStep(page, run.steps, 'Transform');
  await selectStep(page, run.steps.Fetch, 'Fetch');
  await expectSelectedStep(page, run.steps, 'Fetch');
  await openTab(page, 'Output');
  await expect.poll(() => shownBody(page)).toBe(formatted(TWO_STEPS.Fetch));
});

// @S08
// Scenario: A step link opens the run with that step selected
//   Given run "R" has a finished step "Fetch"
//   When I open "/projects/<project_id>/runs/<R id>?step=<Fetch step id>"
//   Then "Fetch" is marked as selected
//   And the "Input" and "Output" tabs are enabled
// Enabled: each opens and shows the step's data.
test('@S08', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenTwoStepRun(projectId);

  await openRun(page, projectId, run.runId, `?step=${run.steps.Fetch}`);

  await expectSelectedStep(page, run.steps, 'Fetch');
  await openTab(page, 'Input');
  await hashTabs.expectSelected(page, 'Input');
  await expect.poll(() => shownBody(page)).toBe(formatted(FETCH_INPUT));
  await openTab(page, 'Output');
  await hashTabs.expectSelected(page, 'Output');
  await expect.poll(() => shownBody(page)).toBe(formatted(TWO_STEPS.Fetch));
});

// @S09
// Scenario: Input and output need a step to be selected
//   Given I open a run without selecting a step
//   Then the "Log" tab is shown
//   And the "Input" tab is disabled with the tooltip "A valid step must be selected to view its input"
//   And the "Output" tab is disabled with the tooltip "A valid step (with a readable output) must be selected to view its output"
// Fails on the port: the tabs show no tab panel.
test('@S09', PASSING_OLD, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenTwoStepRun(projectId);
  await openRun(page, projectId, run.runId);

  await hashTabs.expectSelected(page, 'Log');
  await expect(panel(page, 'Log')).toBeVisible();
  await expectDisabledTab(
    page,
    'Input',
    'A valid step must be selected to view its input'
  );
  await expectDisabledTab(
    page,
    'Output',
    'A valid step (with a readable output) must be selected to view its output'
  );
  await hashTabs.S06(page, 'Input', 'Log');
});

// The S01 lines of shared-log-viewer, as a run's job logged them
const loggedInReverse = () =>
  logViewer.given.S01.lines.map(line => ({
    ...line,
    source: logViewer.given.S01.source,
  }));

// @S10
// Scenario: The log tab shows everything the run logged
//   Given a finished run of "Intake" that logged "Fetched 12 patients" and "Posted batch 1"
//   When I open the run page
//   Then the "Log" tab shows both lines in time order, each prefixed with its source
// "Posted batch 1" is stored first but logged a second later.
test('@S10', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenRun(projectId, {
    steps: [{ name: 'Fetch', seconds: 3 }],
    logs: loggedInReverse(),
  });
  await openRun(page, projectId, run.runId);

  await logViewer.S01(page);
});

// Given a finished run whose steps "Fetch" and "Transform" each logged two
// lines, "Fetch" first
const STEP_LINES = {
  Fetch: ['Fetching patients', 'Fetched 12 patients'],
  Transform: ['Transforming 12 patients', 'Transformed 12 patients'],
};
function givenLoggedSteps(projectId: string) {
  return givenRun(projectId, {
    steps: [
      { name: 'Fetch', seconds: 2 },
      { name: 'Transform', seconds: 2 },
    ],
    logs: [
      { message: STEP_LINES.Fetch[0], step: 'Fetch', at: 0.5 },
      { message: STEP_LINES.Fetch[1], step: 'Fetch', at: 1.5 },
      { message: STEP_LINES.Transform[0], step: 'Transform', at: 2.5 },
      { message: STEP_LINES.Transform[1], step: 'Transform', at: 3.5 },
    ],
  });
}

// @S11
// Scenario: Selecting a step highlights its log lines
//   Given a finished run whose steps "Fetch" and "Transform" both logged
//   When I select "Transform"
//   Then the log scrolls to "Transform"'s first line
//   And "Transform"'s lines are marked in the gutter
//   And "Fetch"'s lines are not marked
// Clearing the selection is going Back to the run without a step.
// Pending on old: the highlight starts one line early (annotation 6.1).
// Passes on the port only: the highlight starts on the step's first line.
test('@S11', { tag: '@passing-new' }, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenLoggedSteps(projectId);
  await openRun(page, projectId, run.runId);

  await logViewer.S05(
    page,
    STEP_LINES.Transform.map(line => `R/T ${line}`),
    () => selectStep(page, run.steps.Transform, 'Transform'),
    () => page.goBack().then(() => undefined)
  );
});

// @S12
// Scenario: The log level filter is remembered
//   Given I have never set a log level
//   And a finished run logged a "debug" line and an "info" line
//   When I open the run page
//   Then the filter reads "info" and the "debug" line is hidden
//   When I choose "debug"
//   Then both lines are shown
//   And when I open another run, the filter reads "debug"
test('@S12', PASSING, async ({ page }) => {
  setPreferences(ME, {});
  const { id: projectId } = givenProject();
  const { debug, info } = logViewer.given.S03;
  const logs = [
    { message: debug, level: 'debug' as const },
    { message: info, level: 'info' as const },
  ];
  const r1 = givenRun(projectId, { steps: [{ name: 'Fetch' }], logs });
  const r2 = givenRun(projectId, {
    workflow: 'Intake again',
    steps: [{ name: 'Fetch' }],
    logs,
  });
  await openRun(page, projectId, r1.runId);

  await logViewer.expectLevel(page, 'info');
  await expect.poll(() => logViewer.logLines(page)).toEqual([`R/T ${info}`]);
  await logViewer.chooseLevel(page, 'debug');
  await expect
    .poll(() => logViewer.logLines(page))
    .toEqual([`R/T ${debug}`, `R/T ${info}`]);
  await logViewer.S04(
    page,
    () => preferencesOf(ME).desired_log_level,
    () => open(page, runPath(projectId, r2.runId))
  );
});

// @S13
// Scenario: A finished run with no logs says so
//   Given a run that was lost before it logged anything
//   When I open the run page
//   Then the "Log" tab says "No logs were received for this run."
test('@S13', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenRun(projectId, { state: 'lost' });
  await openRun(page, projectId, run.runId);

  await logViewer.S06(page);
});

// @S14
// Scenario Outline: An unfinished run's log says what it is waiting for
//   Given a run in state <state> that has not logged anything
//   When I open the run page
//   Then the "Log" tab shows <message>
//   Examples: available "Waiting for worker"; claimed "Creating runtime &
//   installing adaptors"; started "Nothing yet"
test('@S14', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const examples = [
    ['available', 'Waiting for worker'],
    ['claimed', 'Creating runtime & installing adaptors'],
    ['started', 'Nothing yet'],
  ];
  await signInAs(page, ME);
  for (const [state, message] of examples) {
    const run = givenRun(projectId, { workflow: `Intake ${state}`, state });
    await open(page, runPath(projectId, run.runId));
    await expect.soft(onScreen(page, message), state).toBeVisible();
  }
});

// @S15
// Scenario: A running step's output says it is not there yet
//   Given a started run whose step "Fetch" has not finished
//   When I select "Fetch"
//   Then the "Output" tab shows "Nothing yet"
test('@S15', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenRun(projectId, {
    state: 'started',
    steps: [{ name: 'Fetch', exit: null }],
    logs: [{ message: 'Fetching patients', step: 'Fetch' }],
  });
  await openRun(page, projectId, run.runId);

  await selectStep(page, run.steps.Fetch, 'Fetch');
  await openTab(page, 'Output');

  await hashTabs.expectSelected(page, 'Output');
  await expect(onScreen(page, 'Nothing yet')).toBeVisible();
});

// @S16
// Scenario: Editors can cancel a queued run from this page
//   Given I am an editor and run "R" is "available"
//   When I open the run page for "R"
//   Then I see a "Cancel" action
//   And shared-run-components S09, S10, S11 and S12 hold on this page
// S10 to S12 run in the shared block below; S09 is the cancel itself.
test('@S16', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject({ [ME]: 'editor' });
  const run = givenRun(projectId, { state: 'available' });
  await openRun(page, projectId, run.runId);

  await expect(cancelButton(page)).toBeVisible();
  await runComponents.S09(
    page,
    cancelButton(page),
    run.runId,
    detail(page, 'Status')
  );
});

// Given a run of "Intake" on the version before the workflow changed, and a
// run of another workflow on its current version
function givenOlderAndCurrent(projectId: string) {
  const older = givenRun(projectId, { steps: [{ name: 'Fetch' }] });
  changeWorkflowOnNode(projectId, 'Intake', OWNER);
  const current = givenRun(projectId, {
    workflow: 'Intake today',
    steps: [{ name: 'Fetch' }],
  });
  return { older, current };
}

// @S17
// Scenario: The workflow and step inspect links open the version that ran
//   Given a run executed on an older version of "Intake"
//   When I look at the "Workflow" link or a step's inspect link
//   Then shared-run-components S07 holds, and S08 under experimental features
//   And the flow "flow-open-run-in-editor" starts when I follow either
// S08 (and the flow it starts) runs in the shared block below.
// Fails on the port: a step's inspect link has no address.
test('@S17', PASSING_OLD, async ({ page }) => {
  const { id: projectId } = givenProject();
  const { older, current } = givenOlderAndCurrent(projectId);
  await openRun(page, projectId, older.runId);
  const now = await page.context().newPage();
  await open(now, runPath(projectId, current.runId));

  await runComponents.S07(page, {
    older: workflowLink(page),
    olderRun: older.runId,
    version: older.version,
    current: workflowLink(now),
    currentRun: current.runId,
  });
  await runComponents.S07(page, {
    older: inspectLink(page, older.steps.Fetch),
    olderRun: older.runId,
    version: older.version,
    current: inspectLink(now, current.steps.Fetch),
    currentRun: current.runId,
  });
});

// @S18
// Scenario: An open run page follows the run as it executes
//   Given I have run "R" open while it is "available"
//   When the worker claims, starts and completes steps of "R"
//   Then the flow "flow-run-show-live-updates" ends on this page
// The flow's S01 to S06 and S08, in one run: claimed, started, a step that
// starts, logs and completes while selected, and the run's completion.
test('@S18', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject({ [ME]: 'editor' });
  const run = givenRun(projectId, { state: 'available', jobs: ['Fetch'] });
  await openRun(page, projectId, run.runId);
  const status = detail(page, 'Status');
  await expect(status).toHaveText(/Enqueued/);
  await expect(cancelButton(page)).toBeVisible();

  workerReports(run.runId, { claim: true });
  await expect(status).toHaveText(/Starting/);
  await expect(cancelButton(page)).toHaveCount(0);

  workerReports(run.runId, { start: true });
  await expect(status).toHaveText(/Running/);
  await expect(detail(page, 'Started')).toHaveText(/\d/);

  const fetch = workerReports(run.runId, { startStep: 'Fetch' });
  await expect(runStep(page, fetch)).toContainText('Fetch');
  workerReports(run.runId, { log: 'Fetched 12 patients', step: fetch });
  await expect
    .poll(() => logViewer.logLines(page))
    .toContain('R/T Fetched 12 patients');

  await selectStep(page, fetch, 'Fetch');
  await openTab(page, 'Output');
  await expect(onScreen(page, 'Nothing yet')).toBeVisible();
  workerReports(run.runId, {
    completeStep: fetch,
    output: { patients: 12 },
  });
  await expect.poll(() => shownBody(page)).toBe(formatted({ patients: 12 }));

  workerReports(run.runId, { complete: 'success', finalState: { done: 1 } });
  await expect(status).toHaveText(/Success/);
  await expect(detail(page, 'Finished')).toHaveText(/\d/);
  await expect(detail(page, 'Final Output').getByRole('link')).toBeVisible();
});

// @S19
// Scenario: A failure alert's run link lands on this page
//   Given I received a failure alert for run "R" of workflow "Intake"
//   When I follow the link to "inspect the run and its logs"
//   Then I am on "/projects/<project_id>/runs/<R id>"
//   And the flow "flow-failure-alert-email" ends on this page
//   And if I was signed out, the flow "flow-login-return-to" starts for that URL
// Followed signed out: signing in returns me to the run.
test('@S19', PASSING, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenRun(projectId, {
    state: 'failed',
    steps: [{ name: 'Fetch', exit: 'fail' }],
  });
  const path = runPath(projectId, run.runId);
  sendFailureAlertOnNode(
    projectId,
    { id: run.workflowId, name: 'Intake' },
    ME,
    { workOrderId: run.workOrderId, runId: run.runId }
  );

  const link = await mailedLinkTo(page.request, user(ME).email, path);
  expect(link).toBe(path);
  await page.goto(link);
  await expectAt(page, '/users/log_in');
  await submitLogin(page, ME, PASSWORD);

  await expectAt(page, path);
  await expect(detail(page, 'Status')).toHaveText(/Failed/);
});

// @S20
// Scenario: A run on a zero-persistence project shows its data as not retained
//   Given project "Malawi HIV" never retains I/O data and run "R" was created after the switch
//   When I open "R" and select its step
//   Then the flow "flow-zero-persistence-runs" ends on this page (its S01 and S04)
// The flow's S01: the webhook body is wiped once the worker has it and the
// step's output is never stored. Its S04: an admin is pointed to the policy,
// an editor to the admins.
test('@S20', PASSING, async ({ page, browser }) => {
  const { id: projectId } = givenProject({ [ME]: 'admin', [THIRD]: 'editor' });
  keepNoData(projectId);
  const run = givenRun(projectId, {
    input: { type: 'http_request', wipedAt: utcStamp(new Date()) },
    steps: [{ name: 'Fetch' }],
  });
  await openRun(page, projectId, run.runId, `?step=${run.steps.Fetch}#input`);

  await expect(onScreen(page, 'No Input Data here!')).toBeVisible();
  await expect(
    onScreen(
      page,
      "Input data for this step has not been retained in accordance with your project's data storage policy."
    )
  ).toBeVisible();
  await expect(
    onScreen(page, /You can.t rerun this work order, but you can change/)
  ).toBeVisible();
  await expect(page.getByRole('link', { name: 'this policy' })).toHaveAttribute(
    'href',
    `/projects/${projectId}/settings#data-storage`
  );
  await openTab(page, 'Output');
  await expect(onScreen(page, 'No Output Data here!')).toBeVisible();

  const editor = await otherSession(browser, THIRD);
  await open(
    editor,
    `${runPath(projectId, run.runId)}?step=${run.steps.Fetch}#input`
  );
  await expect(
    onScreen(
      editor,
      /Contact one of your\s+project admins\s+for more information\./
    )
  ).toBeVisible();
  await expect(editor.getByRole('link', { name: 'this policy' })).toHaveCount(
    0
  );
  await projectAdmins(editor).hover();
  await expect(editor.getByRole('tooltip')).toContainText(user(OWNER).email);
  await editor.context().close();
});

// ---------------------------------------------------------------------------
// Inherited shared annotations, run on a run page

// Given project "Malawi HIV" (or <name>) with these members and a finished
// run whose step "Fetch" stored an output
function givenRunPage(
  members: Record<string, Role> = { [ME]: 'owner' },
  name = 'Malawi HIV'
) {
  const project = givenProject(members, { name });
  const run = givenRun(project.id, {
    steps: [{ name: 'Fetch', output: { shared: true } }],
  });
  return { ...project, run, path: runPath(project.id, run.runId) };
}

// Shown once the run has loaded
const summary = (page: Page) => detailLabel(page, 'Work Order');

test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on run-show',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S01(page, givenRunPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on run-show',
    PASSING,
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, givenRunPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on run-show',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S03(page, givenRunPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on run-show',
    PASSING,
    async ({ page, browser }) => {
      const h = givenRunPage();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.id}/w`,
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
    test(`shared-authenticated-session@${id} on run-show`, PENDING, () => {
      test.skip(true, `variant ${variant} is not configured on this instance`);
    });
});

test.describe('shared-project-scope', () => {
  test('shared-project-scope@S01 on run-show', PASSING, async ({ page }) => {
    await projectScope.S01(page, givenRunPage().path);
  });

  test('shared-project-scope@S02 on run-show', PASSING, async ({ page }) => {
    await projectScope.S02(page, givenRunPage().path, ME, summary(page));
  });

  test('shared-project-scope@S03 on run-show', PASSING, async ({ page }) => {
    await projectScope.S03(page, givenRunPage({ [OWNER]: 'owner' }).path, ME);
  });

  test('shared-project-scope@S04 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [OWNER]: 'owner' });
    exec(
      `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.id}'`
    );
    await projectScope.S04(page, h.path, OWNER);
  });

  test('shared-project-scope@S05 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage();
    exec(`update projects set requires_mfa = true where id = '${h.id}'`);
    removeMfaOf(ME);
    await projectScope.S05(page, h.path, ME);
  });

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on run-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenRunPage({ [OWNER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, summary(page));
    }
  );

  test('shared-project-scope@S07 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'editor', [OWNER]: 'owner' });
    await projectScope.S07(page, h.path, ME, () =>
      removeMemberOnNode(h.id, ME, OWNER)
    );
  });

  test('shared-project-scope@S08 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'admin', [OWNER]: 'owner' });
    await projectScope.S08(
      page,
      `${h.path}?x=1`,
      ME,
      () => changeRoleOnNode(h.id, ME, 'viewer'),
      summary(page)
    );
  });

  test(
    'shared-project-scope@S09 on run-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenRunPage({ [OWNER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S09(page, h.path, ME, () =>
        setSupportAccessOnNode(h.id, false)
      );
    }
  );

  test('shared-project-scope@S10 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'editor', [OWNER]: 'owner' });
    await projectScope.S10(page, h.path, ME, () =>
      scheduleDeletionOnNode(h.id)
    );
  });

  // shared-project-scope S11 and S12 are not run on this page: they are about
  // an open workflow editor (archived sandbox, deleted workflow), and this
  // page holds no workflow open.
});

test.describe('shared-usage-limits-banner', () => {
  test('shared-usage-limits-banner@S01 on run-show', PENDING, () => {
    test.skip(true, 'variant usage-limited is not configured on this instance');
  });

  test(
    'shared-usage-limits-banner@S02 on run-show',
    PASSING,
    async ({ page }) => {
      await usageLimitsBanner.S02(page, givenRunPage().path, ME, summary(page));
    }
  );
});

// The picker scenarios seed their own "Malawi HIV", so this page's project
// has another name.
test.describe('shared-project-header', () => {
  const HOST = 'Run host';

  // The last crumb holds the run's id and its version chip
  test('shared-project-header@S01 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'editor' }, HOST);
    await projectHeader.S01(page, h.path, ME, HOST, [
      { name: 'History', href: `/projects/${h.id}/history` },
      { name: `Run ${shortId(h.run.runId)} latest` },
    ]);
  });

  test('shared-project-header@S02 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'editor' }, HOST);
    await projectHeader.S02(page, ME, { path: h.path, project: HOST });
  });

  test('shared-project-header@S03 on run-show', PASSING, async ({ page }) => {
    const w = seedWorkspace(
      {
        name: HOST,
        members: { [ME]: 'editor', [OWNER]: 'owner' },
        sandboxes: [
          { name: 'dev', color: '#E33D63', members: { [ME]: 'editor' } },
        ],
      },
      OWNER
    );
    cleanups.push(w.remove);
    const dev = w.id('dev');
    cleanups.push(() => removeWorkflowData(dev));
    const run = givenRun(dev, { steps: [{ name: 'Fetch' }] });
    await projectHeader.S03(page, ME, {
      path: runPath(dev, run.runId),
      label: `${HOST}:dev`,
    });
  });

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on run-show`,
      PASSING,
      async ({ page }) => {
        const h = givenRunPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on run-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenRunPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, whatever page hosts the header
  test('shared-project-header@S09 on run-show', PASSING, async ({ page }) => {
    await projectHeader.S09(page, ME);
  });

  // A run exists only in its own project: the Examples row "a run's page"
  // lands on the history page
  test('shared-project-header@S10 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'editor' }, HOST);
    await projectHeader.S10(page, h.path, ME, '/history');
  });

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on run-show`,
      PASSING,
      async ({ page }) => {
        const h = givenRunPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test('shared-project-header@S14 on run-show', PENDING, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

  // The run page marks History (annotation 6.2)
  test('shared-project-header@S15 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'viewer' }, HOST);
    await projectHeader.S15(page, h.path, ME, h.id, 'History');
  });

  // The preference is data, so the variant is seeded rather than skipped
  test('shared-project-header@S16 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'editor' }, HOST);
    await projectHeader.S16(page, h.path, ME, { channels: true });
  });

  // A superuser needs a role on the project to open this page at all
  test('shared-project-header@S17 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'viewer', [THIRD]: 'viewer' }, HOST);
    await projectHeader.S17(page, h.path);
  });
});

// Inherited from shared-run-components: the state pill, step icons,
// durations, carried-over marker, version links and cancel. S13 and S14 are
// about the step rerun icon, which only History shows (not_reachable_here);
// S15 to S18 are the editor run viewer's.
test.describe('shared-run-components', () => {
  test('shared-run-components@S01 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const labelled = [
      ['available', 'Enqueued'],
      ['claimed', 'Starting'],
      ['started', 'Running'],
      ['failed', 'Failed'],
    ];
    await signInAs(page, ME);
    for (const [state, label] of labelled) {
      const run = givenRun(projectId, { workflow: `Intake ${state}`, state });
      await open(page, runPath(projectId, run.runId));
      await runComponents.S01(page, [[detail(page, 'Status'), label]]);
    }
  });

  test('shared-run-components@S02 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, {
      state: 'started',
      steps: [
        { name: 'Fetch' },
        { name: 'Transform', exit: 'fail' },
        { name: 'Load', exit: null },
      ],
    });
    await openRun(page, projectId, run.runId);

    await runComponents.S02(page, {
      pending: runStep(page, run.steps.Load),
      success: runStep(page, run.steps.Fetch),
      failed: runStep(page, run.steps.Transform),
    });
  });

  test('shared-run-components@S03 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const kill = (name: string, errorType: string) => ({
      name,
      exit: 'kill',
      errorType,
    });
    const run = givenRun(projectId, {
      state: 'killed',
      steps: [
        kill('Timeout', 'TimeoutError'),
        kill('Security', 'SecurityError'),
        kill('Memory', 'OOMError'),
        kill('Size', 'StateTooLargeError'),
      ],
    });
    await openRun(page, projectId, run.runId);

    await runComponents.S03(page, {
      timeout: runStep(page, run.steps.Timeout),
      security: runStep(page, run.steps.Security),
      oom: runStep(page, run.steps.Memory),
      tooLarge: runStep(page, run.steps.Size),
    });
  });

  test('shared-run-components@S04 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, {
      state: 'started',
      steps: [{ name: 'Fetch', exit: null, seconds: 5 }],
    });
    await openRun(page, projectId, run.runId);

    await runComponents.S04(page, stepDuration(page, run.steps.Fetch));
  });

  // The run that has not started is on a second page
  test('shared-run-components@S05 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const ran = givenRun(projectId, {
      steps: [{ name: 'Fetch', seconds: 90 }],
    });
    const waiting = givenRun(projectId, {
      workflow: 'Intake queued',
      state: 'available',
    });
    await openRun(page, projectId, ran.runId);
    const queued = await page.context().newPage();
    await open(queued, runPath(projectId, waiting.runId));

    await runComponents.S05(
      page,
      stepDuration(page, ran.steps.Fetch),
      detail(queued, 'Duration')
    );
  });

  test('shared-run-components@S06 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, {
      state: 'failed',
      steps: [
        { name: 'Fetch', carried: true },
        { name: 'Load', exit: 'fail' },
      ],
    });
    await openRun(page, projectId, run.runId);

    await runComponents.S06(
      page,
      runStep(page, run.steps.Fetch),
      runStep(page, run.steps.Load)
    );
  });

  // The workflow link and the step's inspect link; page S17 runs the same
  test('shared-run-components@S07 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const { older, current } = givenOlderAndCurrent(projectId);
    await openRun(page, projectId, older.runId);
    const now = await page.context().newPage();
    await open(now, runPath(projectId, current.runId));

    await runComponents.S07(page, {
      older: workflowLink(page),
      olderRun: older.runId,
      version: older.version,
      current: workflowLink(now),
      currentRun: current.runId,
    });
  });

  test('shared-run-components@S08 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const { older } = givenOlderAndCurrent(projectId);
    setPreferences(ME, { experimental_features: true });
    await openRun(page, projectId, older.runId);

    await runComponents.S08(
      page,
      workflowLink(page),
      older.runId,
      `/projects/${projectId}/w/${older.workflowId}`
    );
  });

  test('shared-run-components@S09 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject({ [ME]: 'editor' });
    const run = givenRun(projectId, { state: 'available' });
    await openRun(page, projectId, run.runId);

    await runComponents.S09(
      page,
      cancelButton(page),
      run.runId,
      detail(page, 'Status')
    );
  });

  test('shared-run-components@S10 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject({ [ME]: 'editor' });
    const run = givenRun(projectId, { state: 'available' });
    await openRun(page, projectId, run.runId);
    await expect(cancelButton(page)).toBeVisible();

    await runComponents.S10(page, cancelButton(page), run.runId, () =>
      claimRun(run.runId)
    );
  });

  // Sent from my own queued run's page, naming Kenya TB's run
  // Fails on the port: Cancel always cancels the page's own run, so no other run can be named.
  test(
    'shared-run-components@S11 on run-show',
    PASSING_OLD,
    async ({ page }) => {
      const { id: projectId } = givenProject({ [ME]: 'editor' });
      const mine = givenRun(projectId, { state: 'available' });
      const kenya = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
      const theirs = givenRun(kenya.id, { state: 'available' });
      await openRun(page, projectId, mine.runId);

      await runComponents.S11(
        page,
        () => sendCancelFor(page, theirs.runId),
        theirs.runId
      );
    }
  );

  // A viewer sees no cancel button on a queued run; an editor sees none on a
  // claimed, a started or a finished one
  test(
    'shared-run-components@S12 on run-show',
    PASSING,
    async ({ page, browser }) => {
      const { id: projectId } = givenProject({
        [ME]: 'viewer',
        [THIRD]: 'editor',
      });
      const queued = givenRun(projectId, { state: 'available' });
      await openRun(page, projectId, queued.runId);
      await expect(summary(page)).toBeVisible();
      await runComponents.S12(page, cancelButton(page));

      const editor = await otherSession(browser, THIRD);
      for (const state of ['claimed', 'started', 'success']) {
        const run = givenRun(projectId, { workflow: `Intake ${state}`, state });
        await open(editor, runPath(projectId, run.runId));
        await expect(summary(editor)).toBeVisible();
        await runComponents.S12(editor, cancelButton(editor));
      }
      await editor.context().close();
    }
  );

  // shared-run-components S13 to S18 are not run on this page (see above).
});

// Inherited from shared-local-datetime: "Started" in the summary. "Finished"
// uses the same component.
test.describe('shared-local-datetime', () => {
  // Given a run that started at <utc>, and today is <today>
  async function started(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, { at: utc, steps: [{ name: 'Fetch' }] });
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, runPath(projectId, run.runId));
    return detail(page, 'Started');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test('shared-local-datetime@S01 on run-show', PASSING, async ({ page }) => {
      await localDatetime.S01(
        page,
        await started(page, localDatetime.given.S01)
      );
    });
  });

  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on run-show`,
      PASSING,
      async ({ page }) => {
        await localDatetime[id](
          page,
          await started(page, localDatetime.given[id])
        );
      }
    );

  // "Finished" of a run that is still going. Expect it to fail on today's
  // page, which leaves it empty (annotation 6.2).
  // Pending on old: Finished is left empty, not "--" (annotation 6.2).
  test('shared-local-datetime@S07 on run-show', PENDING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, {
      state: 'started',
      steps: [{ name: 'Fetch', exit: null }],
    });
    await openRun(page, projectId, run.runId);
    await localDatetime.S07(page, detail(page, 'Finished'));
  });

  // shared-local-datetime S03 is not run on this page: the summary uses the
  // default format, never relative_detailed.
});

// Inherited from shared-hash-tabs: Log (the default), Input and Output.
// Input and Output are open only with a step selected.
test.describe('shared-hash-tabs', () => {
  const OTHERS = ['Input', 'Output'];
  const panelOf = (page: Page) => (label: string) => panel(page, label);

  // Given a finished run whose step "Fetch" stored its data, and I may see it
  function givenTabs() {
    const { id: projectId } = givenProject();
    const run = givenTwoStepRun(projectId);
    const path = runPath(projectId, run.runId);
    return { run, path, step: `${path}?step=${run.steps.Fetch}` };
  }

  // Fails on the port: the tabs show no tab panel.
  test('shared-hash-tabs@S01 on run-show', PASSING_OLD, async ({ page }) => {
    const t = givenTabs();
    await signInAs(page, ME);
    await hashTabs.S01(
      page,
      () => open(page, t.step),
      panelOf(page),
      'Log',
      OTHERS
    );
  });

  // Fails on the port: the tabs show no tab panel.
  test('shared-hash-tabs@S02 on run-show', PASSING_OLD, async ({ page }) => {
    const t = givenTabs();
    await signInAs(page, ME);
    await hashTabs.S02(
      page,
      () => open(page, `${t.step}#output`),
      panelOf(page),
      'Output',
      'Log'
    );
  });

  // Fails on the port: the tabs show no tab panel.
  test('shared-hash-tabs@S03 on run-show', PASSING_OLD, async ({ page }) => {
    const t = givenTabs();
    await signInAs(page, ME);
    await open(page, t.step);
    await hashTabs.S03(page, panelOf(page), 'Output', 'output', [
      'Log',
      'Input',
    ]);
  });

  test('shared-hash-tabs@S04 on run-show', PASSING, async ({ page }) => {
    const t = givenTabs();
    await signInAs(page, ME);
    await hashTabs.S04(
      page,
      () => open(page, `${t.step}#input`),
      { label: 'Input', hash: 'input' },
      'Output'
    );
  });

  // The server re-renders when another step of the run starts
  test('shared-hash-tabs@S05 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, {
      state: 'started',
      steps: [{ name: 'Fetch', output: { fetched: 12 } }],
      jobs: ['Transform'],
    });
    await openRun(
      page,
      projectId,
      run.runId,
      `?step=${run.steps.Fetch}#output`
    );

    await hashTabs.S05(page, panelOf(page), 'Output', 'Log', async () => {
      workerReports(run.runId, { startStep: 'Transform' });
      await expect(stepNamed(page, 'Transform')).toBeVisible();
    });
  });

  test('shared-hash-tabs@S06 on run-show', PASSING, async ({ page }) => {
    const t = givenTabs();
    await signInAs(page, ME);
    await open(page, t.path);
    await hashTabs.S06(page, 'Input', 'Log');
  });
});

// Inherited from shared-log-viewer: the Log tab
test.describe('shared-log-viewer', () => {
  test('shared-log-viewer@S01 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, {
      steps: [{ name: 'Fetch', seconds: 3 }],
      logs: loggedInReverse(),
    });
    await openRun(page, projectId, run.runId);

    await logViewer.S01(page, () =>
      redeliverLogLine(run.runId, 'Fetched 12 patients')
    );
  });

  test('shared-log-viewer@S02 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const { json, notJson } = logViewer.given.S02;
    const run = givenRun(projectId, {
      steps: [{ name: 'Fetch' }],
      logs: [{ message: json }, { message: notJson }],
    });
    await openRun(page, projectId, run.runId);

    await logViewer.S02(page);
  });

  test('shared-log-viewer@S03 on run-show', PASSING, async ({ page }) => {
    setPreferences(ME, {});
    const { id: projectId } = givenProject();
    const { debug, info } = logViewer.given.S03;
    const run = givenRun(projectId, {
      steps: [{ name: 'Fetch' }],
      logs: [
        { message: debug, level: 'debug' },
        { message: info, level: 'info' },
      ],
    });
    await openRun(page, projectId, run.runId);

    await logViewer.S03(page);
  });

  test('shared-log-viewer@S04 on run-show', PASSING, async ({ page }) => {
    setPreferences(ME, {});
    const { id: projectId } = givenProject();
    const logs = [
      { message: logViewer.given.S03.debug, level: 'debug' as const },
      { message: logViewer.given.S03.info },
    ];
    const r1 = givenRun(projectId, { steps: [{ name: 'Fetch' }], logs });
    const r2 = givenRun(projectId, {
      workflow: 'Intake again',
      steps: [{ name: 'Fetch' }],
      logs,
    });
    await openRun(page, projectId, r1.runId);

    await logViewer.S04(
      page,
      () => preferencesOf(ME).desired_log_level,
      () => open(page, runPath(projectId, r2.runId))
    );
  });

  // Pending on old: the highlight starts one line early (annotation 6.1).
  // Passes on the port only: the highlight starts on the step's first line.
  test(
    'shared-log-viewer@S05 on run-show',
    { tag: '@passing-new' },
    async ({ page }) => {
      const { id: projectId } = givenProject();
      const run = givenLoggedSteps(projectId);
      await openRun(page, projectId, run.runId);

      await logViewer.S05(
        page,
        STEP_LINES.Transform.map(line => `R/T ${line}`),
        () => selectStep(page, run.steps.Transform, 'Transform'),
        () => page.goBack().then(() => undefined)
      );
    }
  );

  test('shared-log-viewer@S06 on run-show', PASSING, async ({ page }) => {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, { state: 'lost' });
    await openRun(page, projectId, run.runId);

    await logViewer.S06(page);
  });
});

// Inherited from shared-dataclip-body-viewer: the Input and Output tabs
test.describe('shared-dataclip-body-viewer', () => {
  // Opening the page I am on again: a URL that differs only after "#" would
  // not load the page again, so leave it first
  async function reopen(page: Page, path: string) {
    await page.goto('about:blank');
    await open(page, path);
  }

  // Given my run's step "Fetch" produced <output>, when I open its Output tab
  async function onOutput(page: Page, output: object) {
    const { id: projectId } = givenProject();
    const run = givenRun(projectId, { steps: [{ name: 'Fetch', output }] });
    const path = `${runPath(projectId, run.runId)}?step=${run.steps.Fetch}#output`;
    await signInAs(page, ME);
    await open(page, path);
    return { projectId, run, path };
  }

  test(
    'shared-dataclip-body-viewer@S01 on run-show',
    PASSING,
    async ({ page }) => {
      const body = { patients: [{ id: 1 }] };
      await onOutput(page, body);
      await bodyViewer.S01(page, body);
    }
  );

  test(
    'shared-dataclip-body-viewer@S02 on run-show',
    PASSING,
    async ({ page }) => {
      const body = { patients: [{ id: 1 }] };
      await onOutput(page, body);
      await bodyViewer.S02(page, body);
    }
  );

  // The webhook request is the first step's input
  test(
    'shared-dataclip-body-viewer@S03 on run-show',
    PASSING,
    async ({ page }) => {
      const { id: projectId } = givenProject();
      const { username, password } = bodyViewer.given.S03;
      const run = givenRun(projectId, {
        basicAuth: [username, password],
        input: bodyViewer.webhookRequest(),
        steps: [{ name: 'Fetch' }],
      });
      await openRun(
        page,
        projectId,
        run.runId,
        `?step=${run.steps.Fetch}#input`
      );
      await bodyViewer.S03(page);
    }
  );

  test(
    'shared-dataclip-body-viewer@S04 on run-show',
    PASSING,
    async ({ page }) => {
      const { id: projectId } = givenProject();
      const { Login, Fetch, Post, output } = bodyViewer.given.S04;
      const run = givenRun(projectId, {
        steps: [
          { name: 'Login', credential: Login },
          { name: 'Fetch', credential: Fetch, output },
          { name: 'Post', credential: Post },
        ],
      });
      await openRun(
        page,
        projectId,
        run.runId,
        `?step=${run.steps.Fetch}#output`
      );
      await bodyViewer.S04(page);
    }
  );

  // Each Examples row is its own "Kenya TB"; my own run is on "Malawi HIV",
  // which I can read. Expect it to fail on the port, as on dataclip-show
  // (the copy button stays when the body failed to load).
  // Fails on the port: the copy button stays when the body failed to load.
  test(
    'shared-dataclip-body-viewer@S05 on run-show',
    PASSING_OLD,
    async ({ page }) => {
      const mine = await onOutput(page, { shared: true });
      const kenya = (members: Record<string, Role>) => {
        const { id } = givenProject(members, { name: 'Kenya TB' });
        return {
          id,
          d: seedDataclip(id, {
            type: 'global',
            body: bodyViewer.given.S05.body,
          }),
        };
      };
      const notMine = kenya({ [OWNER]: 'owner' });
      const scheduled = kenya({ [ME]: 'viewer' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${scheduled.id}'`
      );
      const mfa = kenya({ [ME]: 'viewer' });
      exec(`update projects set requires_mfa = true where id = '${mfa.id}'`);
      removeMfaOf(ME);

      for (const k of [notMine, scheduled, mfa])
        await bodyViewer.S05(page, mine.run.outputs.Fetch, k.d, () =>
          reopen(page, mine.path)
        );
    }
  );

  test(
    'shared-dataclip-body-viewer@S06 on run-show',
    PASSING,
    async ({ page }) => {
      const mine = await onOutput(page, { shared: true });
      await bodyViewer.S06(page, mine.run.outputs.Fetch, () =>
        reopen(page, mine.path)
      );
    }
  );
});

// The page's own flashes: "Run cancelled." (info), and "Run not found"
// (error) carried to History when the run is not in the project (S06).
test.describe('shared-flash-messages', () => {
  // Given I am an editor on a queued run's page — the act cancels it
  async function cancelling(page: Page) {
    const { id: projectId } = givenProject({ [ME]: 'editor' });
    const run = givenRun(projectId, { state: 'available' });
    await openRun(page, projectId, run.runId);
    await expect(cancelButton(page)).toBeVisible();
    return { run, act: () => cancelButton(page).click() };
  }

  test('shared-flash-messages@S01 on run-show', PASSING, async ({ page }) => {
    const { act } = await cancelling(page);
    await flashMessages.S01(page, 'Run cancelled.', act);
  });

  test('shared-flash-messages@S02 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage({ [ME]: 'editor' });
    const other = givenRunPage({ [ME]: 'editor' }, 'Kenya TB');
    await signInAs(page, ME);
    await flashMessages.S02(page, 'Run not found', async () => {
      await page.goto(runPath(h.id, other.run.runId));
    });
  });

  test('shared-flash-messages@S03 on run-show', PASSING, async ({ page }) => {
    const { act } = await cancelling(page);
    await flashMessages.S03(page, 'Run cancelled.', act);
  });

  // The page next updates when the cancelled run logs a line
  test('shared-flash-messages@S04 on run-show', PASSING, async ({ page }) => {
    const { run, act } = await cancelling(page);
    await flashMessages.S04(page, 'Run cancelled.', act, async () => {
      workerReports(run.runId, { log: 'After the cancel' });
      await page.waitForTimeout(1000);
    });
  });

  test('shared-flash-messages@S06 on run-show', PASSING, async ({ page }) => {
    const h = givenRunPage();
    const notMine = givenRunPage({ [OWNER]: 'owner' }, 'Kenya TB');
    await signInAs(page, ME);
    await open(page, h.path);

    await flashMessages.S06(
      page,
      () => open(page, notMine.path),
      '/projects',
      page.getByRole('cell', {
        name: manifest().projects[0].name,
        exact: true,
      })
    );
  });

  // shared-flash-messages S05 is not run on this page: it needs an info flash
  // carried by a redirect, and this page's only redirect carries an error.
  // S07 is on admin pages (settings layout) and S08 on the sign-in and
  // account forms.
});
