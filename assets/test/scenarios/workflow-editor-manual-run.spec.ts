// Scenarios from annotations/views/workflow-editor-manual-run.md, and the
// shared scenarios the run panel hosts.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns every project and saves its workflows through
// Lightning. Every project ("Malawi HIV" and any other) is seeded by the test
// and removed again afterwards, with its workflows, runs and dataclips.
// "Intake" is a webhook trigger leading to "Fetch", then "Load" on success,
// unless a test says otherwise. A test that follows a run "R" seeds it
// through Lightning on an "Intake" of trigger, "Receive", then "Fetch":
// "Receive"'s output is "Fetch"'s input "D".
//
// The editor is not being ported: these record what today's run panel does,
// through pages/workflow-editor-manual-run.ts, so a rebuild that keeps the
// Value passes.
//
// shared-authenticated-session, shared-project-scope,
// shared-usage-limits-banner (the page banner), shared-editor-session and
// shared-flash-messages belong to the route /projects/:id/w/:id, and run on it
// in workflow-editor-canvas.spec.ts. The run limit inside this panel is S19
// and S22 here.
import { expect, test, type Page } from '@playwright/test';

import {
  editorQuery,
  editorReady,
  editorToast,
  header,
  node,
  openEditor,
  renameStep,
  renameWorkflow,
  watchEditorSocket,
} from './pages/workflow-editor';
import { panel } from './pages/workflow-editor-inspectors';
import {
  breakInputPreview,
  chooseNewWorkOrder,
  connectRunWorkflow,
  currentTab,
  customInputText,
  dataclipOf,
  dataclipsIn,
  deleteQuietly,
  dropInputFile,
  filterByDates,
  filterByType,
  filterNamedOnly,
  filterPill,
  focusCustomInput,
  inputRow,
  inputRows,
  inputTab,
  inputTabs,
  listInputsAsPage,
  listedInputNames,
  markOn,
  nameInput,
  panelError,
  postRunAsPage,
  renameButton,
  renameInput,
  requireMfa,
  runPanel,
  runPanelQuery,
  runPanelTitle,
  runWithCustomInput,
  searchInputs,
  seedEarlierInputs,
  seedFollowedRun,
  selectPath,
  selectedInputHeader,
  selectedInputName,
  setCustomInput,
  unselectButton,
  uploadInputFile,
  type RunPanelParams,
} from './pages/workflow-editor-manual-run';
import * as bodyViewer from './shared/dataclip-body-viewer';
import * as runRetry from './shared/run-retry-controls';
import {
  auditEventsOf,
  changeRoleOnNode,
  daysAgo,
  deleteWorkflowOnNode,
  goLiveOnNode,
  keepAccount,
  makeSupportUser,
  open,
  removeMfaOf,
  removeWorkflowData,
  renameStepOnNode,
  scheduleDeletionOnNode,
  seedEditorWorkflow,
  seedRun,
  seedWorkspace,
  setPreferences,
  setSupportAccessOnNode,
  shortId,
  signInAs,
  stepsOfRun,
  storedWorkflow,
  utcStamp,
  withLimiterRefusing,
  type EditorWorkflow,
  type EditorWorkflowSeed,
  type RunSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING_OLD_SERIAL = { tag: ['@passing-old', '@serial'] };

const EMPTY_TEXT = 'Use an empty JSON object as the input for this run.';
const LIMIT_COPY =
  'Search results are limited to the 10 most recent matches for this step.';
const CURRENT = 'Current dataclip for this step';
const NEXT_CRON = 'Next state that will be used for cron execution';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests change my preferences, support flag or MFA
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it
// unless another owner is named) — removed after the test with its workflows
function givenProject(
  members: Record<string, Role> = { [ME]: 'editor' },
  { name = 'Malawi HIV', ...rest }: Partial<WorkspaceSeed> = {}
) {
  const owned = Object.values(members).includes('owner')
    ? members
    : { ...members, [OWNER]: 'owner' as const };
  const by = Object.entries(owned).find(([, r]) => r === 'owner')![0];
  const w = seedWorkspace({ name, members: owned, ...rest }, by);
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  return { id, w, by };
}

// Given project "Malawi HIV" with these members has workflow "Intake" (or
// <seed>'s), saved by its owner
function givenIntake(
  members: Record<string, Role> = { [ME]: 'editor' },
  seed: EditorWorkflowSeed = {}
) {
  const p = givenProject(members);
  const wf = seedEditorWorkflow(p.id, p.by, seed);
  return { ...p, wf };
}

// Given run "R" of "Intake" in project <projectId> (see the header), seeded
// by "<by>"
function givenFollowedRun(projectId: string, by: string, seed: RunSeed = {}) {
  const followed = seedFollowedRun(projectId, by, seed);
  cleanups.unshift(followed.run.removeCredentials);
  return followed;
}

// The query that opens the run panel on step <step> of <wf>
const runQuery = (
  wf: EditorWorkflow,
  step: string,
  extra: Omit<RunPanelParams, 'job'> = {}
) => runPanelQuery({ job: wf.steps[step], ...extra });

// When I sign in as <email> and open <wf> in the editor, with <query>
async function openAs(page: Page, wf: EditorWorkflow, email = ME, query = '') {
  await signInAs(page, email);
  await openEditor(page, wf.projectId, wf.id, query);
}

// When I open <wf> again with <query>, already signed in
const reopen = (page: Page, wf: EditorWorkflow, query = '') =>
  openEditor(page, wf.projectId, wf.id, query);

// When I open the run panel for <step> of <wf>
async function openPanel(
  page: Page,
  wf: EditorWorkflow,
  step = 'Fetch',
  extra: Omit<RunPanelParams, 'job'> = {},
  email = ME
) {
  await openAs(page, wf, email, runQuery(wf, step, extra));
  await expect(runPanelTitle(page)).toBeVisible();
}

// Given I have experimental features on
function experimental() {
  setPreferences(ME, { experimental_features: true });
}

// The panel's run button: "Run From Here", "Retry" or "Processing"
const panelRun = (page: Page) => runRetry.runButton(runPanel(page));

// Waits for exactly one run of <workflowId> more than <before>, and returns it
async function newRun(workflowId: string, before: number) {
  await expect
    .poll(() => runRetry.runsOfWorkflow(workflowId).length, 'a run is created')
    .toBe(before + 1);
  const runs = runRetry.runsOfWorkflow(workflowId);
  return runs[runs.length - 1];
}

// Then no run of <workflowId> is created, once a request has had time to land
async function expectNoNewRun(workflowId: string, before: number) {
  await new Promise(resolve => setTimeout(resolve, 2000));
  expect(runRetry.runsOfWorkflow(workflowId)).toHaveLength(before);
}

const runsOf = (workflowId: string) =>
  runRetry.runsOfWorkflow(workflowId).length;

// When I try to run from the panel: the button may already be off
async function tryToRun(page: Page) {
  if (await panelRun(page).isEnabled()) await panelRun(page).click();
}

// "YYYY-MM-DDTHH:MM" for a datetime field. The browser runs in UTC.
const localDatetime = (date: Date) => date.toISOString().slice(0, 16);

// ---------------------------------------------------------------------------
// Choosing the input
// ---------------------------------------------------------------------------

// @S01
// Scenario: Run a step with an empty input
//   Given I am an editor on project "Malawi HIV" with workflow "Intake" open
//   And step "Fetch" is selected
//   When I click "Run From Here" in the step inspector
//   Then the run panel opens titled "Run from Fetch" on the "Empty" tab
//   And it says "Use an empty JSON object as the input for this run."
//   When I click "Run From Here" in the panel
//   Then the workflow is saved first
//   And a work order is created that starts at "Fetch" with input {}
//   And I see "Run started" with "Saved latest changes and created new work order"
//   And the panel closes and the URL has "run=<new run id>" and no "panel"
//   And workflow-editor-run-viewer takes over
// The run viewer taking over is that view's to prove.
test('@S01', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);
  // An unsaved change, so the save is seen
  await renameStep(page, 'Load', 'Load v2');
  await node(page, 'Fetch').click();
  await runRetry.runButton(panel(page, 'Fetch')).click();

  await expect(runPanelTitle(page)).toHaveText('Run from Fetch');
  expect(await currentTab(page)).toBe('Empty');
  await expect(runPanel(page).getByText(EMPTY_TEXT)).toBeVisible();

  const before = runsOf(wf.id);
  await panelRun(page).click();

  const run = await newRun(wf.id, before);
  expect(run.starting_job_id).toBe(wf.steps.Fetch);
  expect(run.input).toEqual({});
  expect(storedWorkflow(wf.id).steps).toContain('Load v2');
  await expect(runRetry.toast(page, 'Run started')).toContainText(
    'Saved latest changes and created new work order'
  );
  await expect(runPanelTitle(page)).toHaveCount(0);
  await expect.poll(() => editorQuery(page).run).toBe(run.id);
  expect(editorQuery(page).panel).toBeUndefined();
});

// @S02
// Scenario: Run with a custom JSON input
//   Given the run panel is open for "Fetch"
//   When I open the "New" tab and type {"patient": "123"}
//   And I click "Run From Here"
//   Then a saved input dataclip with body {"patient": "123"} is created in "Malawi HIV"
//   And the new work order starts at "Fetch" with that dataclip
test('@S02', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  await openPanel(page, wf);

  await inputTab(page, 'New').click();
  await setCustomInput(page, '{"patient": "123"}');
  const before = runsOf(wf.id);
  await panelRun(page).click();

  const run = await newRun(wf.id, before);
  expect(run.starting_job_id).toBe(wf.steps.Fetch);
  expect(run.input).toEqual({ patient: '123' });
  const dataclip = dataclipOf(run.dataclip_id);
  expect(dataclip.type).toBe('saved_input');
  expect(dataclip.project_id).toBe(id);
});

// @S03
// Scenario Outline: A custom input must be a JSON object within the size limit
//   Given the run panel is open for "Fetch" on the "New" tab
//   When the editor holds <input>
//   Then I see <message>
//   And "Run From Here" is disabled
//   Examples:
//     | input                         | message                                 |
//     | {"a": 1                       | "Invalid JSON format"                   |
//     | [1, 2]                        | "Must be an object"                     |
//     | an object larger than 10 MB   | "Dataclip exceeds the 10 MB size limit" |
//     | nothing                       | no message                              |
// One step per example, the large one last. The Value is that no run starts,
// so each tries to run and checks nothing was created.
test('@S03', PASSING_OLD, async ({ page }) => {
  test.slow();
  const { wf } = givenIntake();
  await openPanel(page, wf);
  await inputTab(page, 'New').click();
  const messages = [
    'Invalid JSON format',
    'Must be an object',
    'Dataclip exceeds the 10 MB size limit',
  ];
  // About 11 MB over 100,000 lines, which Monaco draws comfortably
  const large = JSON.stringify(
    Object.fromEntries(
      Array.from({ length: 100_000 }, (_, i) => [`k${i}`, 'x'.repeat(100)])
    ),
    null,
    2
  );
  const examples: [string, string, string | null][] = [
    ['{"a": 1', '{"a": 1', messages[0]],
    ['[1, 2]', '[1, 2]', messages[1]],
    ['nothing', '', null],
    // Last: clearing 11 MB from Monaco is slow and unreliable
    ['an object larger than 10 MB', large, messages[2]],
  ];

  for (const [name, input, message] of examples)
    await test.step(name, async () => {
      await setCustomInput(page, input);
      if (message)
        await expect(runPanel(page).getByText(message)).toBeVisible();
      else
        for (const m of messages)
          await expect(runPanel(page).getByText(m)).toHaveCount(0);

      const before = runsOf(wf.id);
      await tryToRun(page);
      await expectNoNewRun(wf.id, before);
    });
});

// @S04
// Scenario: Upload a JSON file as the custom input
//   Given the run panel is open for "Fetch" on the "New" tab
//   When I upload "sample.json" containing {"a":1}
//   Then the editor shows it indented by two spaces
//   When I drop "notes.txt" onto the upload area
//   Then I see "Invalid file format. Please only upload: JSON" for a few seconds
test('@S04', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openPanel(page, wf);
  await inputTab(page, 'New').click();

  await uploadInputFile(page, {
    name: 'sample.json',
    content: '{"a":1}',
    mimeType: 'application/json',
  });
  await expect.poll(() => customInputText(page)).toBe('{\n  "a": 1\n}');

  await dropInputFile(page, {
    name: 'notes.txt',
    content: 'just notes',
    mimeType: 'text/plain',
  });
  const refusal = runPanel(page).getByText(
    'Invalid file format. Please only upload: JSON'
  );
  await expect(refusal).toBeVisible();
  await expect(refusal).toBeHidden({ timeout: 8000 });
});

// @S05
// Scenario: Run with an input the step received before
//   Given step "Fetch" has received inputs in earlier runs
//   And the run panel is open for "Fetch"
//   When I open the "Existing" tab
//   Then I see up to 10 of those inputs, newest first, each with its name or short id, type and created date
//   And I see "Search results are limited to the 10 most recent matches for this step."
//   When I click one
//   Then I see its name or "Unnamed", its type and date
//   And the flow hands off to shared-dataclip-body-viewer for its body
//   When I click "Run From Here"
//   Then the new work order uses that dataclip and no new dataclip is created
// The body viewer's own scenarios run on this preview below.
test('@S05', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  const twoDaysAgo = daysAgo(2);
  const [edge, newest] = seedEarlierInputs(wf, 'Fetch', [
    {
      type: 'http_request',
      name: 'Malawi edge case',
      body: { patient: 'edge' },
      at: utcStamp(twoDaysAgo),
    },
    { type: 'saved_input', body: { patient: 'newest' } },
  ]);
  await openPanel(page, wf);

  await inputTab(page, 'Existing').click();

  await expect
    .poll(() => listedInputNames(page))
    .toEqual([shortId(newest), 'Malawi edge case']);
  const year = String(twoDaysAgo.getUTCFullYear());
  await expect(inputRow(page, 'Malawi edge case')).toContainText(
    /http.request/i
  );
  await expect(inputRow(page, 'Malawi edge case')).toContainText(year);
  await expect(inputRow(page, shortId(newest))).toContainText(/saved.input/i);
  await expect(runPanel(page).getByText(LIMIT_COPY)).toBeVisible();

  await inputRow(page, 'Malawi edge case').click();

  await expect(selectedInputName(page)).toHaveText('Malawi edge case');
  await expect(selectedInputHeader(page)).toContainText(/http.request/i);
  await expect(selectedInputHeader(page)).toContainText(year);
  await expect.poll(() => bodyViewer.viewerText(page)).toContain('edge');

  const before = runsOf(wf.id);
  const dataclips = dataclipsIn(id);
  await panelRun(page).click();

  const run = await newRun(wf.id, before);
  expect(run.dataclip_id).toBe(edge);
  expect(dataclipsIn(id)).toBe(dataclips);
});

// @S06
// Scenario Outline: Find an earlier input by search and filters
//   Given the run panel is open for "Fetch" on the "Existing" tab
//   When I <action>
//   Then only matching inputs are listed, refreshed shortly after I stop changing filters
//   And active filters show as removable pills
//   And when none match I see "No dataclips match the filter."
//   Examples:
//     | action                                                    |
//     | type part of an input's name and press Enter              |
//     | type a full input id                                      |
//     | choose type "http request" in the type filter             |
//     | set "Created After" and "Created Before"                  |
//     | turn on the named only filter                             |
// One step per example, each on a freshly opened panel. The inputs are days
// apart, so the date filter does not depend on the time zone.
test('@S06', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const [, unnamed] = seedEarlierInputs(wf, 'Fetch', [
    {
      type: 'http_request',
      name: 'Malawi edge case',
      at: utcStamp(daysAgo(5)),
    },
    { type: 'saved_input', at: utcStamp(daysAgo(3)) },
    { type: 'global', name: 'Kenya sample', at: utcStamp(daysAgo(1 / 24)) },
  ]);
  const all = ['Kenya sample', shortId(unnamed), 'Malawi edge case'];
  await signInAs(page, ME);

  const onExisting = async () => {
    await reopen(page, wf, runQuery(wf, 'Fetch'));
    await inputTab(page, 'Existing').click();
    await expect.poll(() => listedInputNames(page)).toEqual(all);
  };
  const listed = (names: string[]) =>
    expect.poll(() => listedInputNames(page)).toEqual(names);

  await test.step("type part of an input's name and press Enter", async () => {
    await onExisting();
    await searchInputs(page, 'edge');
    await listed(['Malawi edge case']);
  });

  await test.step('type a full input id', async () => {
    await onExisting();
    await searchInputs(page, unnamed);
    await listed([shortId(unnamed)]);
  });

  await test.step('choose type "http request" in the type filter', async () => {
    await onExisting();
    await filterByType(page, 'http request');
    await listed(['Malawi edge case']);
    await expect(filterPill(page, 'http request')).toBeVisible();
  });

  await test.step('set "Created After" and "Created Before"', async () => {
    await onExisting();
    await filterByDates(page, {
      after: localDatetime(daysAgo(4)),
      before: localDatetime(daysAgo(2)),
    });
    await listed([shortId(unnamed)]);
    await expect(filterPill(page, 'after')).toBeVisible();
    await expect(filterPill(page, 'before')).toBeVisible();
  });

  await test.step('turn on the named only filter', async () => {
    await onExisting();
    await filterNamedOnly(page);
    await listed(['Kenya sample', 'Malawi edge case']);
    // The pill takes the filter away again
    await filterPill(page, 'named')
      .getByRole('button', { name: 'Remove' })
      .click();
    await listed(all);
  });

  await test.step('none match', async () => {
    await searchInputs(page, 'no such input');
    await expect(
      runPanel(page).getByText('No dataclips match the filter.')
    ).toBeVisible();
    await expect(inputRows(page)).toHaveCount(0);
  });
});

// @S07
// Scenario: Inputs never cross projects
//   Given step "Other" belongs to project "Kenya TB" where I am not a member
//   When the panel asks for earlier inputs of "Other" through project "Malawi HIV"
//   Then the list is empty
//   When a run is submitted in "Malawi HIV" with a dataclip from "Kenya TB"
//   Then no work order is created
test('@S07', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  const kenya = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const other = seedEditorWorkflow(kenya.id, kenya.by, {
    name: 'Other',
    steps: ['Other'],
  });
  const [theirs] = seedEarlierInputs(other, 'Other', [
    { type: 'global', body: { kenya: 'record' } },
  ]);
  await openAs(page, wf);

  const list = await listInputsAsPage(page, id, other.steps.Other);
  const text = await list.text();
  expect(text).not.toContain(theirs);
  expect(text).not.toContain('record');
  if (list.ok())
    expect((JSON.parse(text) as { data: unknown[] }).data).toHaveLength(0);

  const before = runsOf(wf.id);
  await postRunAsPage(page, id, wf.id, {
    job_id: wf.steps.Fetch,
    dataclip_id: theirs,
  });
  await expectNoNewRun(wf.id, before);
  expect(runsOf(other.id)).toBe(0);
});

// @S08
// Scenario: A cron step defaults to the input its next scheduled run will use
//   Given step "Fetch" is reached from a cron trigger
//   And the last successful run of "Intake" ended with dataclip "D"
//   When I open the run panel for "Fetch" or for that trigger
//   Then "D" is selected
//   And I see "Default Next Input for Cron" and "This workflow has a "cron" trigger, and by default it will use the input below for its next run. You can override that by starting a manual run with an empty input or a custom input at any time."
//   And in the "Existing" list "D" is first, marked with a clock titled "Next state that will be used for cron execution"
// "D" is named so it can be told from the step's other inputs.
test('@S08', PASSING_OLD, async ({ page }) => {
  const { id, by } = givenProject();
  const run = seedRun(
    id,
    {
      workflow: 'Intake',
      trigger: 'cron',
      steps: [
        { name: 'Fetch', output: { fetched: true } },
        { name: 'Load', output: { loaded: true } },
      ],
      finalState: { patients: 3 },
    },
    by
  );
  cleanups.unshift(run.removeCredentials);
  const wf = connectRunWorkflow(run.workflowId, id, ['Fetch', 'Load']);
  nameInput(run.finalId!, 'Next cron state');

  await openPanel(page, wf);

  await expect(selectedInputName(page)).toHaveText('Next cron state');
  await expect(
    runPanel(page).getByText('Default Next Input for Cron')
  ).toBeVisible();
  await expect(
    runPanel(page).getByText(
      /This workflow has a "cron" trigger, and by default it will use the input below for its next run\. You can override that by starting a manual run with an empty input or a custom input at any time\./
    )
  ).toBeVisible();

  await unselectButton(page).click();
  await inputTab(page, 'Existing').click();
  await expect
    .poll(async () => (await listedInputNames(page))[0])
    .toBe('Next cron state');
  await expect(
    markOn(inputRow(page, 'Next cron state'), NEXT_CRON)
  ).toBeVisible();

  await test.step('or for that trigger', async () => {
    await reopen(page, wf, runPanelQuery({ trigger: wf.triggerId! }));
    await expect(selectedInputName(page)).toHaveText('Next cron state');
  });
});

// @S09
// Scenario: An input I unselect stays unselected
//   Given the run panel is open for "Fetch" with an existing input selected
//   When I click the close button beside the input's name
//   Then the tabs return and "Run From Here" is disabled on the "Existing" tab
//   When I switch to "New" and back to "Existing"
//   Then no input is selected
//   When I switch to "Empty"
//   Then "Run From Here" is enabled
// The input is selected for me by following run "R", which would select it
// again if anything did.
test('@S09', PASSING_OLD, async ({ page }) => {
  const { id, by } = givenProject();
  const { run, wf } = givenFollowedRun(id, by);
  await openPanel(page, wf, 'Fetch', { run: run.runId });
  await expect(selectedInputName(page)).toBeVisible();

  await unselectButton(page).click();

  await expect(inputTabs(page)).toBeVisible();
  expect(await currentTab(page)).toBe('Existing');
  await expect(panelRun(page)).toBeDisabled();

  await inputTab(page, 'New').click();
  await inputTab(page, 'Existing').click();
  await expect(inputRows(page).first()).toBeVisible();
  await expect(selectedInputName(page)).toHaveCount(0);

  await inputTab(page, 'Empty').click();
  await expect(panelRun(page)).toBeEnabled();
});

// @S10
// Scenario: Name an earlier input
//   Given I am an editor and an existing input "Unnamed" is selected
//   When I click the pencil, type "Malawi edge case" and press Enter
//   Then the input is shown as "Malawi edge case" here and in the list
//   And an audit event "label_created" is recorded for the dataclip
//   When I clear the name and save
//   Then it shows "Unnamed" and an audit event "label_deleted" is recorded
//   And when I am a viewer I see no pencil
test('@S10', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  const [d] = seedEarlierInputs(wf, 'Fetch', [{ type: 'http_request' }]);
  await openPanel(page, wf, 'Fetch', { dataclip: d });
  await expect(selectedInputName(page)).toHaveText('Unnamed');

  await renameInput(page, 'Malawi edge case');

  await expect(selectedInputName(page)).toHaveText('Malawi edge case');
  expect(dataclipOf(d).name).toBe('Malawi edge case');
  await expect
    .poll(() => auditEventsOf(d).map(e => e.event))
    .toContain('label_created');
  await unselectButton(page).click();
  await expect(inputRow(page, 'Malawi edge case')).toBeVisible();

  await inputRow(page, 'Malawi edge case').click();
  await renameInput(page, '');

  await expect(selectedInputName(page)).toHaveText('Unnamed');
  expect(dataclipOf(d).name).toBeNull();
  await expect
    .poll(() => auditEventsOf(d).map(e => e.event))
    .toContain('label_deleted');

  await test.step('when I am a viewer', async () => {
    changeRoleOnNode(id, ME, 'viewer');
    await reopen(page, wf, runQuery(wf, 'Fetch', { dataclip: d }));
    await expect(selectedInputName(page)).toHaveText('Unnamed');
    await expect(renameButton(page)).toHaveCount(0);
  });
});

// ---------------------------------------------------------------------------
// Running from the header, and what a run starts from
// ---------------------------------------------------------------------------

// @S11
// Scenario: Run the whole workflow with a custom input from the header
//   Given "Intake" has trigger "Webhook" connected to step "Fetch"
//   When I choose "Run with custom input" from the header Run menu
//   Then the trigger is selected and the run panel opens titled "Pick a custom input"
//   And the URL has "panel=run", "trigger=<Webhook id>" and "runMode=custom-input"
//   And the "Existing" list shows inputs received by "Fetch"
//   When I reload the page
//   Then the panel is still titled "Pick a custom input"
//   When I run with the "Empty" tab
//   Then the work order starts at "Fetch"
// Still pending, old: the header's "Run with custom input" leaves runMode out of the URL, so the title does not survive a reload
test('@S11', PENDING, async ({ page }) => {
  const { wf } = givenIntake();
  seedEarlierInputs(wf, 'Fetch', [
    { type: 'http_request', name: 'Kobo sample' },
  ]);
  await openAs(page, wf);

  await runWithCustomInput(page, header(page));

  await expect(runPanelTitle(page)).toHaveText('Pick a custom input');
  await expect
    .poll(() => editorQuery(page))
    .toMatchObject({
      panel: 'run',
      trigger: wf.triggerId!,
      runMode: 'custom-input',
    });
  await inputTab(page, 'Existing').click();
  await expect(inputRow(page, 'Kobo sample')).toBeVisible();

  await page.reload();
  await editorReady(page);
  await expect(runPanelTitle(page)).toHaveText('Pick a custom input');

  await inputTab(page, 'Empty').click();
  const before = runsOf(wf.id);
  await panelRun(page).click();
  const run = await newRun(wf.id, before);
  expect(run.starting_job_id).toBe(wf.steps.Fetch);
});

// @S12
// Scenario: Quick run from the header
//   Given "Intake" has a trigger and no run is loaded
//   When I click "Run" in the header, or press Ctrl+Enter with no panel open
//   Then the workflow is saved and a run starts from the first trigger with an empty input
//   And the panel does not open and the URL has "run=<new run id>"
// Same as shared-run-retry-controls S01, which workflow-editor-canvas runs
// with a click; this runs it with Ctrl+Enter.
test('@S12', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);
  await runRetry.S01(
    page,
    header(page),
    { ...wf, triggerId: wf.triggerId! },
    'keys'
  );
  await expect(runPanelTitle(page)).toHaveCount(0);
});

// @S13
// Scenario: A path cannot be a starting point
//   Given the run panel is open for "Fetch"
//   When I select the path from "Fetch" to "Post"
//   Then the panel says "Select a Step or Trigger to start a Run from"
//   And "Run From Here" is disabled
//   When I select step "Post"
//   Then the panel is titled "Run from Post"
// "Post" is "Intake"'s "Load".
test('@S13', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openPanel(page, wf);

  await selectPath(page, 'Fetch', 'Load');

  await expect(
    runPanel(page).getByText('Select a Step or Trigger to start a Run from')
  ).toBeVisible();
  await expect(panelRun(page)).toBeDisabled();
  const before = runsOf(wf.id);
  await tryToRun(page);
  await expectNoNewRun(wf.id, before);

  await node(page, 'Load').click();
  await expect(runPanelTitle(page)).toHaveText('Run from Load');
});

// ---------------------------------------------------------------------------
// Retrying a followed run
// ---------------------------------------------------------------------------

// @S14
// Scenario: Retry a followed run from a step with the same input
//   Given run "R" of "Intake" is loaded and its "Fetch" step took input "D", not wiped
//   When I open the run panel for "Fetch"
//   Then "D" is selected and marked "Current dataclip for this step" in the list
//   And the button reads "Retry" with a chevron
//   When I click "Retry"
//   Then the workflow is saved and a new run is created on R's work order starting at "Fetch" with input "D"
//   And steps upstream of "Fetch" are attached to the new run, not executed again
//   And I see "Retry started" with "Saved latest changes and re-running with previous input"
//   And the URL has "run=<new run id>"
// "D" is named so the panel can be seen to have chosen it. The list shows
// only once "D" is unselected, so it is chosen again from there.
test('@S14', PASSING_OLD, async ({ page }) => {
  const { id, by } = givenProject();
  const { run, wf, fetchInput } = givenFollowedRun(id, by);
  nameInput(fetchInput, 'Patient 123');
  await openPanel(page, wf, 'Fetch', { run: run.runId });

  await expect(selectedInputName(page)).toHaveText('Patient 123');
  await expect(panelRun(page)).toHaveText(/Retry/);
  await expect(runRetry.runOptions(runPanel(page))).toBeVisible();
  await unselectButton(page).click();
  await expect(markOn(inputRow(page, 'Patient 123'), CURRENT)).toBeVisible();
  await inputRow(page, 'Patient 123').click();
  await expect(panelRun(page)).toHaveText(/Retry/);

  const before = runsOf(wf.id);
  await panelRun(page).click();

  const retry = await newRun(wf.id, before);
  expect(retry.work_order_id).toBe(run.workOrderId);
  expect(retry.starting_job_id).toBe(wf.steps.Fetch);
  expect(retry.dataclip_id).toBe(fetchInput);
  expect(stepsOfRun(retry.id)).toContain(run.steps.Receive);
  await expect(runRetry.toast(page, 'Retry started')).toContainText(
    'Saved latest changes and re-running with previous input'
  );
  await expect.poll(() => editorQuery(page).run).toBe(retry.id);
});

// @S15
// Scenario: Force a new work order while retry is available
//   Given the panel offers "Retry" for run "R"
//   When I open the chevron and choose "Run (New Work Order)", or press Ctrl+Shift+Enter
//   Then a new work order is created with input "D"
//   And R's work order gets no new run
// Same as shared-run-retry-controls S05 (which retries first), once from the
// chevron and once with the keys.
test('@S15', PASSING_OLD, async ({ page }) => {
  const { id, by } = givenProject();
  const { run, wf } = givenFollowedRun(id, by);
  const onR = runQuery(wf, 'Fetch', { run: run.runId });
  const backToR = () => reopen(page, wf, onR);
  const followed = { ...run, upstream: [run.steps.Receive] };
  await openPanel(page, wf, 'Fetch', { run: run.runId });

  await test.step('from the chevron', () =>
    runRetry.S05(page, runPanel(page), followed, backToR, 'menu'));
  await backToR();
  await test.step('with Ctrl+Shift+Enter', () =>
    runRetry.S05(page, runPanel(page), followed, backToR, 'keys'));
});

// @S16
// Scenario: Run, retry and close from the keyboard
//   Given the run panel is open for "Fetch" with a valid input
//   When I press Ctrl+Enter, even while typing in the input editor or the search box
//   Then a run starts, or a retry when one is offered
//   When I press Escape
//   Then the panel closes
// Close to shared-run-retry-controls S06, which this panel can't host: the
// panel closes once a run starts, so S06's editor is gone when it looks
// again. The search box is left out: it shows only while no input is
// selected, and then there is nothing to run.
test('@S16', PASSING_OLD, async ({ page }) => {
  const { id, by, wf } = givenIntake();
  const followed = givenFollowedRun(id, by, { workflow: 'Intake followed' });

  await test.step('a run, typing in the input editor', async () => {
    await openPanel(page, wf);
    await inputTab(page, 'New').click();
    await setCustomInput(page, '{"a": 1}');
    await focusCustomInput(page);
    const before = runsOf(wf.id);
    await page.keyboard.press('ControlOrMeta+Enter');
    const run = await newRun(wf.id, before);
    expect(run.input).toEqual({ a: 1 });
  });

  await test.step('a retry when one is offered', async () => {
    const { run, wf: other } = followed;
    await reopen(page, other, runQuery(other, 'Fetch', { run: run.runId }));
    await expect(panelRun(page)).toHaveText(/Retry/);
    const before = runsOf(other.id);
    await page.keyboard.press('ControlOrMeta+Enter');
    const retry = await newRun(other.id, before);
    expect(retry.work_order_id).toBe(run.workOrderId);
  });

  await test.step('Escape closes the panel', async () => {
    await reopen(page, wf, runQuery(wf, 'Fetch'));
    await expect(runPanelTitle(page)).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(runPanelTitle(page)).toHaveCount(0);
    await expect.poll(() => editorQuery(page).panel).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Saving first, and refusing
// ---------------------------------------------------------------------------

// @S17
// Scenario: A run never starts if the workflow can't be saved first
//   Given "Intake" has a change the server will not save
//   When I click "Run From Here"
//   Then no work order is created
//   And I see "Failed to submit run" with the save error
// Same as shared-run-retry-controls S08. The change is a blank workflow name,
// which stays in the shared draft when the panel is opened.
test('@S17', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);
  await renameWorkflow(page, '');
  await reopen(page, wf, runQuery(wf, 'Fetch'));
  await expect(runPanelTitle(page)).toBeVisible();

  await runRetry.S08(page, runPanel(page), wf.id);
});

// @S18 @variant:experimental-features
// Scenario: A live workflow runs without saving
//   Given "Intake" is live and content-locked
//   When I start a run from "Fetch"
//   Then the workflow is not saved
//   And I see "Run started" with "Created new work order"
// Same as shared-run-retry-controls S09.
test('@S18', PASSING_OLD, async ({ page }) => {
  experimental();
  const { by, wf } = givenIntake();
  goLiveOnNode(wf.id, by);
  await openPanel(page, wf);

  await runRetry.S09(page, runPanel(page), wf.id);
  await expect(runRetry.toast(page, 'Run started')).toContainText(
    'Created new work order'
  );
});

// @S19
// Scenario Outline: Run is refused with a reason
//   Given <state>
//   When I look at "Run From Here" in the panel and the header Run button
//   Then they are disabled with the tooltip <tooltip>
//   Examples:
//     | state                                              | tooltip                                                 |
//     | the editor is disconnected                         | "You are disconnected. Reconnecting..."                 |
//     | I am a viewer                                      | "You do not have permission to run workflows"           |
//     | "Intake" has been deleted                          | "Workflow has been deleted"                             |
//     | I am viewing a pinned version                      | "You are viewing a pinned version of this workflow"     |
//     | "Intake" is new and not yet created                | "Create this workflow before running it"                |
//     | the project's run limit says "Run limit reached"   | "Run limit reached"                                     |
// Same as shared-run-retry-controls S10, here on the panel; the header's
// button runs on workflow-editor-canvas. One step per example; the deleted
// one is its own test. '"Intake" is new' is left out: on /w/new the panel can't be
// opened. The usage limiter is instance-wide, so this runs alone.
test('@S19', PASSING_OLD_SERIAL, async ({ page }) => {
  const why = runRetry.given.S10;
  const { id, by, wf } = givenIntake({ [ME]: 'viewer' });
  const sock = await watchEditorSocket(page);
  await openPanel(page, wf);

  await test.step('I am a viewer', () =>
    runRetry.S10(page, runPanel(page), why.viewer));

  changeRoleOnNode(id, ME, 'editor', { quietly: true });
  const pinned = storedWorkflow(wf.id).lock_version;
  renameStepOnNode(wf.id, 'Load', 'Load v2', by);
  await test.step('I am viewing a pinned version', async () => {
    await reopen(page, wf, runQuery(wf, 'Fetch', { v: pinned }));
    await runRetry.S10(page, runPanel(page), why.pinned);
  });

  await test.step('the editor is disconnected', async () => {
    await reopen(page, wf, runQuery(wf, 'Fetch'));
    sock.drop();
    await runRetry.S10(page, runPanel(page), why.disconnected);
    sock.reconnect();
  });

  await test.step('the run limit says "Run limit reached"', async () => {
    const putBack = withLimiterRefusing('new_run', runRetry.given.S11.limit);
    cleanups.push(putBack);
    await reopen(page, wf, runQuery(wf, 'Fetch'));
    await runRetry.S10(page, runPanel(page), runRetry.given.S11.limit);
    putBack();
  });
});

// Still pending, old: an open editor leaves for the workflow list when its workflow is deleted, so no reason is shown
test('@S19, "Intake" has been deleted', PENDING, async ({ page }) => {
  const { wf } = givenIntake();
  await openPanel(page, wf);
  deleteWorkflowOnNode(wf.id, OWNER);
  await runRetry.S10(page, runPanel(page), runRetry.given.S10.deleted);
});

// @S20
// Scenario Outline: The server only starts runs for people who may run them
//   Given workflow "Intake" in project "Malawi HIV"
//   And <who>
//   When a manual run is posted for "Intake" through "Malawi HIV"
//   Then the response is <status> and <outcome>
//   Examples:
//     | who                                                                  | status | outcome                  |
//     | I am signed out                                                      | 302    | I am sent to log in      |
//     | I am not a member                                                    | 403    | no work order is created |
//     | I am a support user and the project has not allowed support access   | 403    | no work order is created |
//     | I am a support user and the project allows support access            | 201    | a work order is created  |
//     | I am an editor but "Intake" belongs to another project               | 403    | no work order is created |
// One step per example, posted through my own session; signed out comes
// last. The last row posts through "Kenya TB", where I am an editor. A
// support user can reach every project that allows support, so this runs
// alone.
test('@S20', PASSING_OLD_SERIAL, async ({ page }) => {
  const { id, wf } = givenIntake({ [OWNER]: 'owner' });
  const kenya = givenProject({ [ME]: 'editor' }, { name: 'Kenya TB' });
  const body = { job_id: wf.steps.Fetch };
  const expectPost = async (through: string, status: number) => {
    const before = runsOf(wf.id);
    const response = await postRunAsPage(page, through, wf.id, body);
    expect(response.status()).toBe(status);
    if (status === 201) await newRun(wf.id, before);
    else await expectNoNewRun(wf.id, before);
    return response;
  };
  await signInAs(page, ME);
  await open(page, '/projects');

  await test.step('I am not a member', () => expectPost(id, 403));

  cleanups.push(makeSupportUser(ME));
  await test.step('a support user, support access not allowed', () =>
    expectPost(id, 403));

  setSupportAccessOnNode(id, true);
  await test.step('a support user, support access allowed', () =>
    expectPost(id, 201));

  await test.step('"Intake" belongs to another project', () =>
    expectPost(kenya.id, 403));

  await test.step('I am signed out', async () => {
    await page.context().clearCookies();
    await page.goto('/users/log_in');
    const response = await expectPost(id, 302);
    expect(response.headers()['location']).toContain('/users/log_in');
  });
});

// @S21
// Scenario Outline: A retry that can't run says why
//   Given the panel offers "Retry" for run "R"
//   And <state>
//   When I click "Retry"
//   Then no new run is created
//   And I see "Retry failed" with <message>
//   Examples:
//     | state                                    | message                                   |
//     | R's input to "Fetch" has been wiped      | "Failed to retry run"                     |
//     | "Intake" has been deleted                | "Cannot retry run for deleted workflow"   |
// One step per example, each on its own run, with the change made after the
// panel offered "Retry". The deletion is written where the open editor does
// not hear of it; otherwise the editor turns "Retry" off first (S19).
test('@S21', PASSING_OLD, async ({ page }) => {
  const { id, by } = givenProject();
  const wiped = givenFollowedRun(id, by);
  const deleted = givenFollowedRun(id, by, { workflow: 'Intake deleted' });
  await signInAs(page, ME);

  const examples: [string, typeof wiped, () => void, string | RegExp][] = [
    [
      'the input has been wiped',
      wiped,
      () => runRetry.wipeInput(wiped.fetchInput),
      'Failed to retry run',
    ],
    [
      'the workflow has been deleted',
      deleted,
      () => deleteQuietly(deleted.wf.id),
      /workflow has been deleted|deleted workflow/i,
    ],
  ];

  for (const [name, { run, wf }, change, message] of examples)
    await test.step(name, async () => {
      await reopen(page, wf, runQuery(wf, 'Fetch', { run: run.runId }));
      await expect(panelRun(page)).toHaveText(/Retry/);
      change();
      const before = runsOf(wf.id);

      await panelRun(page).click();

      await expect(runRetry.toast(page, 'Retry failed')).toContainText(message);
      await expectNoNewRun(wf.id, before);
    });
});

// @S22 @variant:run-limit-reached
// Scenario: The server enforces the run limit even when the page allowed the click
//   Given the usage limiter refuses new runs with "Run limit exceeded for this project"
//   When I start a run or a retry from the panel
//   Then no run is created
//   And I see the toast with "Run limit exceeded for this project"
// The limiter starts refusing after the panel has loaded, so the page still
// allows the click. A retry first, then a new work order from the chevron.
// The usage limiter is instance-wide, so this runs alone.
test('@S22', PASSING_OLD_SERIAL, async ({ page }) => {
  const text = 'Run limit exceeded for this project';
  const { id, by } = givenProject();
  const { run, wf } = givenFollowedRun(id, by);
  await openPanel(page, wf, 'Fetch', { run: run.runId });
  await expect(panelRun(page)).toHaveText(/Retry/);
  cleanups.push(withLimiterRefusing('new_run', text));
  const before = runsOf(wf.id);

  await test.step('a retry', async () => {
    await panelRun(page).click();
    await expect(runRetry.toast(page, 'Retry failed')).toContainText(text);
    await expectNoNewRun(wf.id, before);
  });

  await test.step('a run', async () => {
    await chooseNewWorkOrder(page, runPanel(page));
    await expect(runRetry.toast(page, 'Failed to submit run')).toContainText(
      text
    );
    await expectNoNewRun(wf.id, before);
  });
});

// @S23
// Scenario: One click starts one run
//   Given the run panel is open for "Fetch"
//   When I click "Run From Here" and the save is still in progress
//   Then the button reads "Processing" and is disabled
//   And clicking it again does not submit a second run
//   And while a followed run is still running the button stays "Processing"
// Close to shared-run-retry-controls S13, which this panel can't host: the
// panel closes once the run is accepted. The save is held by holding back
// what the server sends; the still-running run is seeded started, with no
// worker to finish it until finishRun does.
test('@S23', PASSING_OLD, async ({ page }) => {
  const { id, by, wf } = givenIntake();
  const running = givenFollowedRun(id, by, {
    workflow: 'Intake running',
    state: 'started',
    steps: [
      { name: 'Receive', output: { patient: '123' } },
      { name: 'Fetch', exit: null },
    ],
  });
  const sock = await watchEditorSocket(page);
  await openPanel(page, wf);
  const before = runsOf(wf.id);

  sock.hold();
  await panelRun(page).click();

  await expect(panelRun(page)).toHaveAccessibleName(/Processing/);
  await expect(panelRun(page)).toBeDisabled();
  await panelRun(page).click({ force: true });
  await page.keyboard.press('ControlOrMeta+Enter');
  sock.release();
  await newRun(wf.id, before);
  await expectNoNewRun(wf.id, before + 1);

  await test.step('while a followed run is still running', async () => {
    const { run, wf: other } = running;
    await reopen(page, other, runQuery(other, 'Fetch', { run: run.runId }));
    await expect(panelRun(page)).toHaveAccessibleName(/Processing/);
    await expect(panelRun(page)).toBeDisabled();
    runRetry.finishRun(run.runId);
    await expect(panelRun(page)).not.toHaveAccessibleName(/Processing/);
  });
});

// ---------------------------------------------------------------------------
// Opening from a link
// ---------------------------------------------------------------------------

// @S24
// Scenario: A link can open the panel with an input chosen
//   Given step "Fetch" has received input "D" recently
//   When I open "/projects/<id>/w/<Intake id>?panel=run&job=<Fetch id>&dataclip=<D id>"
//   Then the run panel opens for "Fetch" with "D" selected on the "Existing" tab
//   And "dataclip" is removed from the URL
// "D" is named, and is not the newest input, so the panel can't have chosen
// it by itself.
test('@S24', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const [d] = seedEarlierInputs(wf, 'Fetch', [
    { type: 'http_request', name: 'Patient 123', at: utcStamp(daysAgo(1)) },
    { type: 'saved_input', name: 'Newest' },
  ]);

  await openPanel(page, wf, 'Fetch', { dataclip: d });

  await expect(runPanelTitle(page)).toHaveText('Run from Fetch');
  await expect(selectedInputName(page)).toHaveText('Patient 123');
  await expect.poll(() => editorQuery(page).dataclip).toBeUndefined();
  await unselectButton(page).click();
  expect(await currentTab(page)).toBe('Existing');
});

// @S25
// Scenario: Errors inside the panel don't take down the editor
//   Given something in the run panel throws while rendering
//   Then I see "Error loading run panel" with the error
//   And the rest of the editor keeps working
// Stand-in for "something throws": the earlier inputs come back without a
// type, which the selected input's header can't draw.
test('@S25', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const [d] = seedEarlierInputs(wf, 'Fetch', [{ type: 'http_request' }]);
  await breakInputPreview(page);
  await signInAs(page, ME);

  await openEditor(
    page,
    wf.projectId,
    wf.id,
    runQuery(wf, 'Fetch', { dataclip: d })
  );

  await expect(editorToast(page, 'Error loading run panel')).toBeVisible();
  await expect(panelError(page)).toBeVisible();
  await node(page, 'Load').click();
  await expect.poll(() => editorQuery(page).job).toBe(wf.steps.Load);
});

// ---------------------------------------------------------------------------
// shared-run-retry-controls: the panel's run control. The page's own
// scenarios run most of what the panel hosts: S05=S15, S08=S17, S09=S18,
// S10=S19. S06 and S13 can't run on this panel as written (it closes once a
// run is accepted); S16 and S23 check the same Values in the panel's terms,
// and the IDE hosts them as written. S01 to S03, S07, S11 and S12 run on
// workflow-editor-canvas. This is the rest.
// ---------------------------------------------------------------------------

test.describe('shared-run-retry-controls', () => {
  // A different input selected, then "D" wiped
  test(
    'shared-run-retry-controls@S04 on workflow-editor-manual-run',
    PASSING_OLD,
    async ({ page }) => {
      const { id, by } = givenProject();
      const { run, wf, fetchInput } = givenFollowedRun(id, by);
      seedEarlierInputs(wf, 'Fetch', [
        { type: 'saved_input', name: 'Other input' },
      ]);
      const onR = runQuery(wf, 'Fetch', { run: run.runId });
      await openPanel(page, wf, 'Fetch', { run: run.runId });

      await test.step('I select a different input', () =>
        runRetry.S04(page, runPanel(page), async () => {
          await unselectButton(page).click();
          await inputRow(page, 'Other input').click();
        }));

      await test.step('"D" has been wiped', async () => {
        await reopen(page, wf, onR);
        await runRetry.S04(page, runPanel(page), async () => {
          runRetry.wipeInput(fetchInput);
          await reopen(page, wf, onR);
        });
      });
    }
  );
});

// ---------------------------------------------------------------------------
// shared-dataclip-body-viewer: the preview of a selected earlier input. Each
// input is opened through the panel's dataclip link.
// ---------------------------------------------------------------------------

test.describe('shared-dataclip-body-viewer', () => {
  const name = (id: string) =>
    `shared-dataclip-body-viewer@${id} on workflow-editor-manual-run`;

  // Given step "Fetch" of "Intake" received an input with <body>, when I
  // open the run panel with it selected
  async function onPreview(page: Page, body: object) {
    const { wf } = givenIntake();
    const [d] = seedEarlierInputs(wf, 'Fetch', [{ type: 'global', body }]);
    const show = () => reopen(page, wf, runQuery(wf, 'Fetch', { dataclip: d }));
    await signInAs(page, ME);
    await show();
    return { d, show };
  }

  // Given run <seed> of an "Intake" whose steps ran in <order>, when I open
  // the run panel on <step> with <dataclip> selected
  async function onRunInput(
    page: Page,
    seed: RunSeed,
    order: string[],
    step: string,
    dataclip: (run: ReturnType<typeof seedRun>) => string
  ) {
    const { id, by } = givenProject();
    const run = seedRun(id, { workflow: 'Intake', ...seed }, by);
    cleanups.unshift(run.removeCredentials);
    const wf = connectRunWorkflow(run.workflowId, id, order);
    await openPanel(page, wf, step, { dataclip: dataclip(run) });
  }

  test(name('S01'), PASSING_OLD, async ({ page }) => {
    const body = { patients: [{ id: 1 }] };
    await onPreview(page, body);
    await bodyViewer.S01(page, body);
  });

  test(name('S02'), PASSING_OLD, async ({ page }) => {
    const body = { patients: [{ id: 1 }] };
    await onPreview(page, body);
    await bodyViewer.S02(page, body);
  });

  // The webhook request is "Fetch"'s input
  test(name('S03'), PASSING_OLD, async ({ page }) => {
    const { username, password } = bodyViewer.given.S03;
    await onRunInput(
      page,
      {
        basicAuth: [username, password],
        input: bodyViewer.webhookRequest(),
        steps: [{ name: 'Fetch' }],
      },
      ['Fetch'],
      'Fetch',
      run => run.inputId
    );
    await bodyViewer.S03(page);
  });

  // "Fetch"'s output is "Post"'s input
  test(name('S04'), PASSING_OLD, async ({ page }) => {
    const { Login, Fetch, Post, output } = bodyViewer.given.S04;
    await onRunInput(
      page,
      {
        steps: [
          { name: 'Login', credential: Login },
          { name: 'Fetch', credential: Fetch, output },
          { name: 'Post', credential: Post },
        ],
      },
      ['Login', 'Fetch', 'Post'],
      'Post',
      run => run.outputs.Fetch
    );
    await bodyViewer.S04(page);
  });

  // Each Examples row is its own "Kenya TB": not a member, scheduled for
  // deletion, requires MFA I have not set up
  test(name('S05'), PASSING_OLD, async ({ page }) => {
    const mine = await onPreview(page, { shared: true });
    const kenya = (members: Record<string, Role>) => {
      const { id, by } = givenProject(members, { name: 'Kenya TB' });
      const other = seedEditorWorkflow(id, by, {
        name: 'Other',
        steps: ['Other'],
      });
      const [d] = seedEarlierInputs(other, 'Other', [
        { type: 'global', body: bodyViewer.given.S05.body },
      ]);
      return { id, d };
    };
    const notMine = kenya({ [OWNER]: 'owner' });
    const scheduled = kenya({ [ME]: 'viewer' });
    scheduleDeletionOnNode(scheduled.id);
    const mfa = kenya({ [ME]: 'viewer' });
    requireMfa(mfa.id);
    removeMfaOf(ME);

    for (const k of [notMine, scheduled, mfa])
      await bodyViewer.S05(page, mine.d, k.d, mine.show);
  });

  test(name('S06'), PASSING_OLD, async ({ page }) => {
    const mine = await onPreview(page, { shared: true });
    await bodyViewer.S06(page, mine.d, mine.show);
  });
});
