// Scenarios from annotations/flows/flow-open-run-in-editor.md: following a
// run's links from the run page or History into the workflow editor.
//
// Who's who: "I" am editor@openfn.org, an editor on "Malawi HIV" unless a
// test says otherwise. owner@openfn.org owns every project and builds its
// workflows and runs through Lightning. Every project is seeded by the test
// and removed again afterwards, with its runs. A run's workflow "Intake" is
// built with it: a webhook trigger leading to "Fetch", then "Send to DHIS2";
// "Send to DHIS2" failed. A later version renames "Fetch" to "Fetch v2"
// (saved through Lightning).
//
// The run viewer's steps and data show in the IDE only; on the canvas a
// loaded run is its chip under the history panel and its outcomes drawn on
// the steps.
import { expect, test, type Page } from '@playwright/test';

import { inspectLink, workflowLink } from './pages/run-show';
import {
  editorPath,
  editorQuery,
  editorReady,
  headerTooltip,
  legacyEditorPath,
  node,
  openEditor,
  readOnlyPill,
  renameStep,
  unsavedMarker,
  watchEditorSocket,
} from './pages/workflow-editor';
import { ideReady, jobSelector, runChip } from './pages/workflow-editor-ide';
import { connectRunWorkflow } from './pages/workflow-editor-manual-run';
import {
  canvasRunChip,
  jobsOf,
  nodeTips,
  preloadedRun,
  selectedStep,
} from './pages/workflow-editor-run-viewer';
import {
  mismatchBanner,
  versionChip,
} from './pages/workflow-editor-versions-and-promote';
import {
  expandWorkOrder,
  expectAt,
  historyCell,
  historyRow,
  inspectStepLink,
  keepAccount,
  open,
  openHistory,
  removeWorkflowData,
  renameStepOnNode,
  runPath,
  seedRun,
  seedWorkspace,
  setPreferences,
  signInAs,
  type RunSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old'],
});

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

const SEND = 'Send to DHIS2';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests turn my experimental features on
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> with these members (owner@openfn.org owns it unless
// another owner is named) — returns its id
function givenProject(
  name = 'Malawi HIV',
  members: Record<string, Role> = { [ME]: 'editor' }
) {
  const owned = Object.values(members).includes('owner')
    ? members
    : { ...members, [OWNER]: 'owner' as const };
  const by = Object.entries(owned).find(([, r]) => r === 'owner')![0];
  const w = seedWorkspace({ name, members: owned }, by);
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  return id;
}

// Given run "R" of "Intake" (or <seed>'s) in project <projectId>, its
// workflow drawn connected
function givenRun(projectId: string, seed: RunSeed = {}) {
  const run = seedRun(
    projectId,
    {
      workflow: 'Intake',
      state: 'failed',
      steps: [{ name: 'Fetch' }, { name: SEND, exit: 'fail' }],
      ...seed,
    },
    OWNER
  );
  cleanups.unshift(run.removeCredentials);
  connectRunWorkflow(run.workflowId, projectId, ['Fetch', SEND]);
  return run;
}

// Given "Intake" has moved on since run <run>: a new version renames "Fetch"
const movedOn = (run: { workflowId: string }) =>
  renameStepOnNode(run.workflowId, 'Fetch', 'Fetch v2', OWNER);

// Given I have experimental features on
const experimental = () => setPreferences(ME, { experimental_features: true });

// Then the canvas paints run <runId>: its chip, and an outcome on "Fetch"
async function expectRunOnCanvas(page: Page, runId: string) {
  await expect(canvasRunChip(page, runId)).toBeVisible(EVENTUALLY);
  await expect.poll(() => nodeTips(page, SEND), EVENTUALLY).not.toEqual([]);
}

// Then the canvas is read-only, saying <why> when pointed at
async function expectReadOnly(page: Page, why: string) {
  await expect(readOnlyPill(page)).toBeVisible();
  expect(await headerTooltip(page, readOnlyPill(page))).toBe(why);
}

// @S01
// Scenario: The run page's workflow link opens the version that ran, with the run loaded
//   Given run "R" executed on version 1 of "Intake" and "Intake" is now on version 2
//   And I am on the run page for "R"
//   When I follow the "Workflow" link
//   Then I am in the workflow editor for "Intake" at version 1
//   And the run viewer shows "R" with its steps
//   And the canvas cannot be edited, saying "You are viewing a pinned version of this workflow"
test('@S01', tags('S01'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id);
  movedOn(run);
  await signInAs(page, ME);
  await open(page, runPath(id, run.runId));

  await workflowLink(page).click();

  await expectAt(page, editorPath(id, run.workflowId));
  await editorReady(page);
  expect(editorQuery(page).v).toBe(String(run.version));
  await expect(versionChip(page)).toHaveText(`v${run.version}`);
  await expect(node(page, 'Fetch')).toBeVisible();
  await expect(node(page, 'Fetch v2')).toHaveCount(0);
  await expectRunOnCanvas(page, run.runId);
  await expectReadOnly(
    page,
    'You are viewing a pinned version of this workflow'
  );
});

// @S02
// Scenario: A step's inspect link opens that step's job in the IDE with the run loaded
//   Given run "R" has a failed step for job "Send to DHIS2"
//   When I follow that step's inspect link from the run page or from History
//   Then the workflow editor opens with the IDE showing "Send to DHIS2"
//   And the run viewer has "R"'s step for "Send to DHIS2" selected
test('@S02', tags('S02'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id);
  await signInAs(page, ME);

  const from = {
    'the run page': async () => {
      await open(page, runPath(id, run.runId));
      return inspectLink(page, run.steps[SEND]);
    },
    History: async () => {
      await openHistory(page, id);
      await expandWorkOrder(page, run.workOrderId);
      return inspectStepLink(page, run.steps[SEND]);
    },
  };
  for (const [where, link] of Object.entries(from))
    await test.step(where, async () => {
      await (await link()).click();

      await expectAt(page, editorPath(id, run.workflowId));
      await ideReady(page);
      await expect.soft(jobSelector(page), where).toHaveText(/Send to DHIS2/);
      await expect
        .soft(runChip(page, run.runId), where)
        .toBeVisible(EVENTUALLY);
      await expect
        .soft(async () => expect(await selectedStep(page), where).toBe(SEND))
        .toPass(EVENTUALLY);
    });
});

// @S03
// Scenario: A run on the current version opens the editable workflow
//   Given run "R" executed on the current version of "Intake"
//   And I am an editor
//   When I follow the work order's workflow name on History
//   Then the workflow editor opens on the latest "Intake" with "R" in the run viewer
//   And I can edit the workflow
test('@S03', tags('S03'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id);
  await signInAs(page, ME);
  await openHistory(page, id);

  await historyCell(historyRow(page, run.workOrderId), 'Workflow')
    .getByRole('link')
    .click();

  await expectAt(page, editorPath(id, run.workflowId));
  await editorReady(page);
  expect(editorQuery(page).run).toBe(run.runId);
  expect(editorQuery(page).v).toBeUndefined();
  await expectRunOnCanvas(page, run.runId);
  await expect(readOnlyPill(page)).toHaveCount(0);
  await renameStep(page, 'Fetch', 'Fetch patients');
  await expect(unsavedMarker(page)).toBeVisible();
});

// @S04 @variant:experimental-features
// Scenario: With experimental features the link opens the run as it executed
//   Given I have experimental features enabled
//   And run "R" executed on an unreleased draft of "Intake" that has since changed
//   When I follow the "Workflow" link on the run page for "R"
//   Then the workflow editor shows "Intake" as "R" executed it
//   And the run viewer shows "R" with no version mismatch warning
//   And the canvas cannot be edited, saying "You are viewing this workflow as a past run executed it"
// "Intake" was never taken live, so the run's version is a draft save.
test('@S04', tags('S04'), async ({ page }) => {
  experimental();
  const id = givenProject();
  const run = givenRun(id);
  movedOn(run);
  await signInAs(page, ME);
  await open(page, runPath(id, run.runId));

  await workflowLink(page).click();

  await expectAt(page, editorPath(id, run.workflowId));
  await editorReady(page);
  expect(editorQuery(page).as_run).toBe(run.runId);
  await expect(node(page, 'Fetch')).toBeVisible();
  await expect(node(page, 'Fetch v2')).toHaveCount(0);
  await expectRunOnCanvas(page, run.runId);
  await expect(mismatchBanner(page)).toHaveCount(0);
  await expectReadOnly(
    page,
    'You are viewing this workflow as a past run executed it'
  );
});

// @S05
// Scenario: A run from another project is not loaded into the editor
//   Given I am an owner on project "Malawi HIV" and not a member of "Kenya TB"
//   And run "R" belongs to "Kenya TB"
//   When I open "Intake" in "Malawi HIV" with "run=<R id>"
//   Then the editor opens with no run data for "R"
// Malawi HIV's "Intake" is a copy of the run's workflow, with the same step
// names, so painting "R" would show on it.
test('@S05', tags('S05'), async ({ page }) => {
  const malawi = givenProject('Malawi HIV', { [ME]: 'owner' });
  const mine = givenRun(malawi, {
    state: 'success',
    steps: [],
    jobs: ['Fetch', SEND],
  });
  const kenya = givenProject('Kenya TB', {});
  const theirs = givenRun(kenya);
  await signInAs(page, ME);

  await openEditor(page, malawi, mine.workflowId, `?run=${theirs.runId}`);

  expect(await preloadedRun(page)).toBeNull();
  await page.waitForTimeout(3000);
  await expect(canvasRunChip(page, theirs.runId)).toHaveCount(0);
  for (const step of ['Fetch', SEND])
    expect(await nodeTips(page, step)).toEqual([]);
});

// @S06 @variant:experimental-features
// Scenario: An as-executed view only accepts a run of the same workflow
//   Given run "R" executed workflow "Referrals" in the same project
//   When I open "Intake" with "as_run=<R id>"
//   Then the editor reports "run not found" and shows no content as executed
// The report is the editor's refused join of the run's room.
test('@S06', tags('S06'), async ({ page }) => {
  experimental();
  const id = givenProject();
  const intake = givenRun(id, {
    state: 'success',
    steps: [],
    jobs: ['Fetch', SEND],
  });
  const referrals = givenRun(id, { workflow: 'Referrals' });
  await signInAs(page, ME);
  const sock = await watchEditorSocket(page);

  await open(
    page,
    editorPath(id, intake.workflowId, `?as_run=${referrals.runId}`)
  );

  await expect.poll(() => sock.joinReply()?.status, EVENTUALLY).toBe('error');
  expect(JSON.stringify(sock.joinReply()?.response)).toContain('run not found');
  await page.waitForTimeout(2000);
  await expect(node(page, 'Fetch')).toHaveCount(0);
});

// @S07
// Scenario: An old editor bookmark still follows its run
//   Given a bookmark "/projects/<project_id>/w/<Intake id>/legacy?a=<R id>&s=<job id>"
//   When I open it
//   Then I am redirected to "/projects/<project_id>/w/<Intake id>" with "run=<R id>" and "s=<job id>"
//   And the run viewer shows "R"
test('@S07', tags('S07'), async ({ page }) => {
  const id = givenProject();
  const run = givenRun(id);
  const jobId = jobsOf(run.workflowId)[SEND];
  await signInAs(page, ME);

  await page.goto(legacyEditorPath(id, run.workflowId, run.runId, jobId));

  await expectAt(page, editorPath(id, run.workflowId));
  await editorReady(page);
  expect(editorQuery(page)).toMatchObject({ run: run.runId, s: jobId });
  await expectRunOnCanvas(page, run.runId);
});
