// Scenarios from annotations/views/workflow-editor-canvas.md, and the shared
// scenarios the editor inherits.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns every project and saves its workflows through
// Lightning; super@openfn.org is the other collaborator a test needs. Every
// project ("Malawi HIV" and its sandboxes) is seeded by the test and removed
// again afterwards, with its workflows. "Intake" is a webhook trigger leading
// to "Fetch", then "Load" on success, unless a test says otherwise.
//
// The editor is not being ported: these record what today's editor does,
// through pages/workflow-editor.ts, so a rebuild that keeps the Value passes.
import { expect, test, type Page } from '@playwright/test';

import {
  adaptorPicker,
  autoLayoutButton,
  canvas,
  chooseAdaptor,
  clickEmptyCanvas,
  clickPlus,
  confirm,
  confirmDialog,
  controlTooltip,
  dragOver,
  dragPath,
  dragPathToEmpty,
  dragStep,
  editorPath,
  editorQuery,
  editorReady,
  editorToast,
  environmentBadge,
  expectInvalidTarget,
  fitViewButton,
  header,
  headerButton,
  headerTooltip,
  inView,
  layoutModeSwitch,
  lifecycleBadge,
  loadingWorkflow,
  minimap,
  node,
  nodes,
  openEditor,
  panCanvas,
  panelHeading,
  pathBetween,
  pathCondition,
  paths,
  plusButton,
  readOnlyPill,
  redoButton,
  releasePath,
  renameStep,
  renameWorkflow,
  saveButton,
  settingsButton,
  settingsFlagged,
  startPath,
  undoButton,
  unsavedMarker,
  watchEditorSocket,
  whereIs,
  workflowSwitch,
  workflowTitle,
  workflowsListPath,
} from './pages/workflow-editor';
import { connectRunWorkflow } from './pages/workflow-editor-manual-run';
import { openNew, startCard } from './pages/workflow-editor-new';
import * as adaptorConfig from './shared/adaptor-credential-config';
import * as authenticatedSession from './shared/authenticated-session';
import * as editorSession from './shared/editor-session';
import * as flashMessages from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as runRetry from './shared/run-retry-controls';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  catalogueUnavailable,
  changeRoleOnNode,
  deleteWorkflowOnNode,
  exec,
  expectAt,
  goLiveOnNode,
  keepAccount,
  makeSupportUser,
  manifest,
  nameOf,
  open,
  otherSession,
  patchWithBearer,
  releasesOf,
  removeMemberOnNode,
  removeMfaOf,
  removeWorkflowData,
  renameStepOnNode,
  scheduleDeletionOnNode,
  scheduledDeletionOf,
  seedEditorWorkflow,
  seededApiTokenOf,
  seedRun,
  seedWorkspace,
  setPreferences,
  setSupportAccessOnNode,
  sharedDocOf,
  signInAs,
  sql,
  storedWorkflow,
  submit,
  switchWorkflowOnNode,
  tagFor,
  unconfirmedSince,
  withFlag,
  withLimiterRefusing,
  withRefusingLimiter,
  workflowsOf,
  type EditorWorkflow,
  type EditorWorkflowSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {
  S07: 'old: disabled Undo and Redo show no tooltip',
  S09: 'old: saving after "Run auto layout" keeps the earlier manual positions',
  S10: 'old: the diagram does not refit when the canvas is resized',
  S16: 'old: the disabled Undo shows no tooltip on a live workflow',
  S23: 'variant not configured on this instance',
  S27: 'old: Save keeps the unsaved changes marker after a switch made elsewhere',
  'shared-editor-session@S04':
    'old: the shared copy stayed open after the page left, so the stored draft is never reloaded',
  'shared-editor-session@S18':
    "old: no cursor labelled with the other member's name was found (unconfirmed)",
  'shared-editor-session@S20':
    'old: no sandbox button found after "Edit in sandbox" (unconfirmed)',
  'shared-usage-limits-banner@S01': 'variant not configured on this instance',
  'shared-run-retry-controls@S03':
    'old: "Retry" on a pinned version starts no run',
  'shared-run-retry-controls@S07': 'old: Ctrl+Enter in the IDE starts no run',
  'shared-run-retry-controls@S10':
    'old: the run button is enabled on a workflow not yet created',
  'shared-run-retry-controls@S13':
    'old: the run button reads "Retry" while the run is going (unconfirmed)',
};
const tags = (key: string, serial = false) => ({
  tag: [
    key in STILL_PENDING ? '@pending' : '@passing-old',
    ...(serial ? ['@serial'] : []),
  ],
});

const LIMIT = 'Your plan is at its limit.';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests change my preferences, confirmation or MFA
  cleanups = [keepAccount(ME)];
});
// Every cleanup runs even when one fails, so a project is never left behind
test.afterEach(() => {
  const errors: unknown[] = [];
  for (const cleanup of cleanups.reverse())
    try {
      cleanup();
    } catch (e) {
      errors.push(e);
    }
  if (errors.length) throw errors[0];
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
  seed: EditorWorkflowSeed = {},
  project: Partial<WorkspaceSeed> = {}
) {
  const p = givenProject(members, project);
  const wf = seedEditorWorkflow(p.id, p.by, seed);
  return { ...p, wf, path: editorPath(p.id, wf.id) };
}

// When I sign in as <email> and open <wf> in the editor, with <query>
async function openAs(page: Page, wf: EditorWorkflow, email = ME, query = '') {
  await signInAs(page, email);
  await openEditor(page, wf.projectId, wf.id, query);
}

// Given I have experimental features on
function experimental() {
  setPreferences(ME, { experimental_features: true });
}

// Given a Lightning setting for this test (put back after it)
function withSetting(putBack: () => unknown) {
  cleanups.push(() => void putBack());
}

// When I add a step after <from> from its plus button, choosing the HTTP
// adaptor
async function addHttpStep(page: Page, from: string) {
  await clickPlus(page, from);
  await chooseAdaptor(page, 'http');
}

// @S01
// Scenario: A member opens a workflow and sees its diagram
//   Given project "Malawi HIV" has workflow "Intake" with a webhook trigger and steps "Fetch" and "Load"
//   And I am a viewer on "Malawi HIV"
//   When I open "/projects/<project id>/w/<workflow id>"
//   Then I see "Loading workflow" until the document has synced
//   And I see the trigger, "Fetch" and "Load" connected by their paths
//   And I see the fit view, layout, undo and redo controls and a minimap
test('@S01', tags('S01'), async ({ page }) => {
  const { path } = givenIntake({ [ME]: 'viewer' });
  const sock = await watchEditorSocket(page);
  await signInAs(page, ME);
  sock.hold();

  await open(page, path);
  await expect(loadingWorkflow(page)).toBeVisible();
  sock.release();
  await editorReady(page);

  for (const name of ['Webhook trigger', 'Fetch', 'Load'])
    await expect(node(page, name)).toBeVisible();
  await expect(await pathBetween(page, 'Webhook trigger', 'Fetch')).toHaveCount(
    1
  );
  await expect(await pathBetween(page, 'Fetch', 'Load')).toHaveCount(1);
  for (const control of [
    fitViewButton(page),
    layoutModeSwitch(page),
    undoButton(page),
    redoButton(page),
  ])
    await expect(control).toBeVisible();
  await expect(minimap(page)).toBeVisible();
});

// @S02
// Scenario: Editor adds a step from a step's plus button
//   Given I am an editor with "Intake" open
//   When I click the plus button on "Fetch"
//   Then the adaptor picker opens
//   When I choose the HTTP adaptor
//   Then a step "Http" appears below "Fetch", connected by an "on success" path
//   And "Http" is selected and its inspector is open
//   When I add another HTTP step the same way
//   Then it is named "Http 1"
test('@S02', tags('S02'), async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);

  await clickPlus(page, 'Fetch');
  await expect(adaptorPicker(page)).toBeVisible();
  await chooseAdaptor(page, 'http');

  await expect(node(page, 'Http')).toBeVisible();
  const path = await pathBetween(page, 'Fetch', 'Http');
  await expect(path).toHaveCount(1);
  expect(await pathCondition(path)).toBe('on success');
  expect((await whereIs(page, 'Http')).y).toBeGreaterThan(
    (await whereIs(page, 'Fetch')).y
  );
  await expect(panelHeading(page, 'Http')).toBeVisible();

  await addHttpStep(page, 'Fetch');
  await expect(node(page, 'Http 1')).toBeVisible();
});

// @S03
// Scenario: Editor adds a step by dragging a path onto empty canvas
//   Given I am an editor with "Intake" open
//   When I drag from the plus button on "Load" and release over empty canvas
//   Then the adaptor picker opens
//   When I choose an adaptor
//   Then a new step appears connected from "Load"
//   When I instead release over an existing step that is not a valid target
//   Then nothing is added
test('@S03', tags('S03'), async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);

  await dragPathToEmpty(page, 'Load');
  await expect(adaptorPicker(page)).toBeVisible();
  await chooseAdaptor(page, 'http');

  await expect(node(page, 'Http')).toBeVisible();
  await expect(await pathBetween(page, 'Load', 'Http')).toHaveCount(1);

  const [stepCount, pathCount] = [
    await nodes(page).count(),
    await paths(page).count(),
  ];
  await startPath(page, 'Load');
  await dragOver(page, 'Fetch');
  await releasePath(page);

  await expect(adaptorPicker(page)).toHaveCount(0);
  await expect(nodes(page)).toHaveCount(stepCount);
  await expect(paths(page)).toHaveCount(pathCount);
});

// @S04
// Scenario: Editor connects two steps
//   Given I am an editor with "Intake" open, where "Fetch" and "Load" are not connected
//   When I drag a path from "Fetch" and drop it on "Load"
//   Then an "on success" path from "Fetch" to "Load" appears
test('@S04', tags('S04'), async ({ page }) => {
  const { wf } = givenIntake(
    { [ME]: 'editor' },
    { paths: [['trigger', 'Fetch']] }
  );
  await openAs(page, wf);
  await expect(await pathBetween(page, 'Fetch', 'Load')).toHaveCount(0);

  await dragPath(page, 'Fetch', 'Load');

  const path = await pathBetween(page, 'Fetch', 'Load');
  await expect(path).toHaveCount(1);
  expect(await pathCondition(path)).toBe('on success');
  await expect.poll(() => sharedDocOf(wf.id)?.paths).toBe(2);
});

// @S05
// Scenario Outline: The canvas refuses paths that would break the workflow
//   Given I am an editor with a workflow open
//   When I drag a path from <source> and drop it on <target>
//   Then while dragging, <target> is marked as an invalid target with "<reason>"
//   And no path is added
//   Examples:
//     | source                    | target                     | reason                          |
//     | a step                    | the same step              |                                 |
//     | a step                    | the trigger                | Cannot connect to a trigger     |
//     | a step                    | one of its ancestors       | Cannot create circular workflow |
//     | a step                    | a step it already leads to | Already connected to this step  |
test('@S05', tags('S05'), async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);
  const before = await paths(page).count();

  for (const [source, target, reason] of [
    ['Load', 'Load', ''],
    ['Load', 'Webhook trigger', 'Cannot connect to a trigger'],
    ['Load', 'Fetch', 'Cannot create circular workflow'],
    ['Fetch', 'Load', 'Already connected to this step'],
  ]) {
    await startPath(page, source);
    await dragOver(page, target);
    await expectInvalidTarget(page, target, reason);
    await releasePath(page);
    // Cleanup per example: close a picker a refused drop might have opened
    await page.keyboard.press('Escape');
    await expect
      .soft(paths(page), `${source} -> ${target}`)
      .toHaveCount(before);
  }
  expect(sharedDocOf(wf.id)?.paths).toBe(before);
});

// @S06
// Scenario: Selecting a step opens its inspector and empty canvas closes it
//   Given I have "Intake" open
//   When I click "Fetch"
//   Then the URL has "job=<Fetch id>" and the flow hands off to workflow-editor-inspectors
//   When I click an empty part of the canvas
//   Then the inspector closes
test('@S06', tags('S06'), async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'viewer' });
  await openAs(page, wf);

  await node(page, 'Fetch').click();
  await expect.poll(() => editorQuery(page).job).toBe(wf.steps.Fetch);
  await expect(panelHeading(page, 'Fetch')).toBeVisible();

  await clickEmptyCanvas(page);
  await expect(panelHeading(page, 'Fetch')).toHaveCount(0);
  await expect.poll(() => editorQuery(page).job).toBeUndefined();
});

// @S07
// Scenario: Editor undoes and redoes canvas edits
//   Given I am an editor with "Intake" open
//   When I add a step
//   And I click "Undo"
//   Then the step is gone
//   When I press Ctrl+Y, or Cmd+Shift+Z on a Mac
//   Then the step is back
//   And "Undo" and "Redo" say "Nothing to undo" and "Nothing to redo" when there is nothing to take back
test('@S07', tags('S07'), async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);
  // Soft, so undo and redo are still checked
  expect
    .soft(await controlTooltip(page, undoButton(page)))
    .toBe('Nothing to undo');
  expect
    .soft(await controlTooltip(page, redoButton(page)))
    .toBe('Nothing to redo');

  await addHttpStep(page, 'Fetch');
  await expect(node(page, 'Http')).toBeVisible();
  // The new step's inspector takes the canvas's place in the URL; go back
  await clickEmptyCanvas(page);
  while (await undoButton(page).isEnabled()) {
    await undoButton(page).click();
    if ((await node(page, 'Http').count()) === 0) break;
  }
  await expect(node(page, 'Http')).toHaveCount(0);

  await page.keyboard.press(
    process.platform === 'darwin' ? 'Meta+Shift+z' : 'Control+y'
  );
  await expect(node(page, 'Http')).toBeVisible();
});

// @S08
// Scenario: Editor arranges steps by hand in manual layout
//   Given I am an editor with "Intake" open in automatic layout
//   When I click "Switch to manual layout mode"
//   And I drag "Load" to a new spot
//   And I save
//   Then "Load" is in the new spot after a reload, for me and for other members
//   When I click "Switch to auto layout mode"
//   Then the steps are laid out automatically again
test('@S08', tags('S08'), async ({ page, browser }) => {
  const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'viewer' });
  await openAs(page, wf);
  const auto = await whereIs(page, 'Load');
  expect(await controlTooltip(page, layoutModeSwitch(page))).toBe(
    'Switch to manual layout mode'
  );

  await layoutModeSwitch(page).click();
  await dragStep(page, 'Load', 220, 80);
  const placed = await whereIs(page, 'Load');
  expect(Math.abs(placed.x - auto.x)).toBeGreaterThan(100);
  await saveButton(page).click();
  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
  expect(storedWorkflow(wf.id).positions?.[wf.steps.Load]).toBeTruthy();

  // Same zoom and pan for both: fit the view after loading
  // In step widths, so the zoom the fit lands on doesn't matter
  const relative = async (p: Page) => {
    await fitViewButton(p).click();
    await p.waitForTimeout(500); // the fit animates
    const [f, l] = [await whereIs(p, 'Fetch'), await whereIs(p, 'Load')];
    const width = (await node(p, 'Fetch').boundingBox())!.width;
    const steps = (d: number) => Math.round((d / width) * 10) / 10;
    return { dx: steps(l.x - f.x), dy: steps(l.y - f.y) };
  };
  const mine = await relative(page);
  await page.reload();
  await editorReady(page);
  expect(await relative(page)).toEqual(mine);
  const other = await otherSession(browser, THIRD);
  await openEditor(other, wf.projectId, wf.id);
  expect(await relative(other)).toEqual(mine);

  expect(await controlTooltip(page, layoutModeSwitch(page))).toBe(
    'Switch to auto layout mode'
  );
  await layoutModeSwitch(page).click();
  await expect.poll(async () => (await relative(page)).dx).not.toBe(mine.dx);
});

// @S09
// Scenario: Editor re-runs automatic layout over manual positions
//   Given I am an editor with "Intake" open in manual layout
//   When I click "Run auto layout (override manual positions)"
//   Then the steps move to the automatic layout and those positions become the manual ones
test('@S09', tags('S09'), async ({ page }) => {
  const { wf } = givenIntake(
    { [ME]: 'editor' },
    { positions: { Fetch: { x: 600, y: 0 }, Load: { x: 0, y: 600 } } }
  );
  await openAs(page, wf);
  const before = await whereIs(page, 'Load');

  await autoLayoutButton(page).click();

  await expect
    .poll(async () => (await whereIs(page, 'Load')).x)
    .not.toBe(before.x);
  expect(await controlTooltip(page, layoutModeSwitch(page))).toBe(
    'Switch to auto layout mode'
  );
  await saveButton(page).click();
  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
  expect(storedWorkflow(wf.id).positions?.[wf.steps.Load]).not.toEqual({
    x: 0,
    y: 600,
  });
});

// @S10
// Scenario: Member fits the diagram to the screen
//   Given I have "Intake" open and have panned away from it
//   When I click "Fit view"
//   Then every step is in view
//   And the diagram refits when the canvas is resized, for example when a side panel opens
test('@S10', tags('S10'), async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'viewer' });
  await openAs(page, wf);
  const all = ['Webhook trigger', 'Fetch', 'Load'];

  await panCanvas(page, -900, -700);
  await expect.poll(() => inView(page, 'Load')).toBe(false);

  await fitViewButton(page).click();
  for (const name of all)
    await expect.poll(() => inView(page, name)).toBe(true);

  await panCanvas(page, -900, -700);
  await expect.poll(() => inView(page, 'Load')).toBe(false);
  const size = page.viewportSize()!;
  await page.setViewportSize({ width: size.width - 200, height: size.height });
  for (const name of all)
    await expect.poll(() => inView(page, name)).toBe(true);
});

// @S11
// Scenario Outline: The canvas is read-only when I can't change what is on screen
//   Given <who> with "Intake" open
//   Then I see "Read-only" in the header, with "<tooltip>" on hover
//   And steps show no plus button and cannot be dragged
//   And "Undo", "Redo" and the layout mode switch are disabled
//   And the workflow switch, if shown, is disabled
//   Examples:
//     | who                                                         | tooltip                                                                       |
//     | I am a viewer                                               | You do not have permission to edit this workflow                              |
//     | I am an editor reading an older version                     | You are viewing a pinned version of this workflow                             |
//     | I am an editor viewing the workflow as a past run executed it | You are viewing this workflow as a past run executed it                     |
test('@S11', tags('S11'), async ({ page }) => {
  // Each row opens its own workflow; the expectations are soft so every row
  // is checked
  const viewer = givenIntake({ [ME]: 'viewer' }, { name: 'Intake viewer' });
  const pinned = seedEditorWorkflow(viewer.id, viewer.by, {
    name: 'Intake pinned',
  });
  const oldVersion = storedWorkflow(pinned.id).lock_version;
  renameStepOnNode(pinned.id, 'Load', 'Load v2', viewer.by);
  const run = seedRun(
    viewer.id,
    { workflow: 'Intake run', steps: [{ name: 'Fetch' }, { name: 'Load' }] },
    viewer.by
  );
  cleanups.unshift(run.removeCredentials);

  const rows: [string, Role, string, string, string][] = [
    [
      'viewer',
      'viewer',
      viewer.wf.id,
      '',
      'You do not have permission to edit this workflow',
    ],
    [
      'older version',
      'editor',
      pinned.id,
      `?v=${oldVersion}`,
      'You are viewing a pinned version of this workflow',
    ],
    [
      'as a past run',
      'editor',
      run.workflowId,
      `?as_run=${run.runId}`,
      'You are viewing this workflow as a past run executed it',
    ],
  ];
  await signInAs(page, ME);
  for (const [who, role, id, query, tooltip] of rows) {
    changeRoleOnNode(viewer.id, ME, role, { quietly: true });
    await page.goto('about:blank');
    await openEditor(page, viewer.id, id, query);

    await expect.soft(readOnlyPill(page), who).toBeVisible();
    expect
      .soft(await headerTooltip(page, readOnlyPill(page)), who)
      .toBe(tooltip);
    await node(page, 'Fetch').hover();
    await expect.soft(plusButton(page, 'Fetch'), who).toHaveCount(0);
    // Dragging a step that can't move pans the canvas, so compare it with
    // its neighbour
    const gap = async () => {
      const [f, l] = [
        await whereIs(page, 'Fetch'),
        await whereIs(page, 'Load'),
      ];
      return { dx: Math.round(f.x - l.x), dy: Math.round(f.y - l.y) };
    };
    const at = await gap();
    await dragStep(page, 'Fetch', 150, 100);
    expect.soft(await gap(), who).toEqual(at);
    for (const control of [
      undoButton(page),
      redoButton(page),
      layoutModeSwitch(page),
    ])
      await expect.soft(control, who).toBeDisabled();
    if ((await workflowSwitch(page).count()) > 0)
      await expect.soft(workflowSwitch(page), who).toBeDisabled();
  }
});

// @S12
// Scenario: Editor switches the workflow off from the header and saves
//   Given experimental features are off for me
//   And I am an editor with "Intake" open, whose triggers are enabled
//   When I turn the workflow switch off
//   Then every trigger in the workflow is disabled in the draft and the save button shows unsaved changes
//   When I save
//   Then I see "Workflow saved"
//   And "Intake" no longer starts work orders from its triggers
test('@S12', tags('S12'), async ({ page }) => {
  setPreferences(ME, { experimental_features: false });
  const { wf } = givenIntake({ [ME]: 'editor' }, { enabled: true });
  await openAs(page, wf);
  await expect(workflowSwitch(page)).toBeChecked();

  await workflowSwitch(page).click();

  await expect(workflowSwitch(page)).not.toBeChecked();
  await expect
    .poll(() => sharedDocOf(wf.id)?.triggers_enabled)
    .toEqual([false]);
  await expect(unsavedMarker(page)).toBeVisible();

  await saveButton(page).click();
  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
  expect(storedWorkflow(wf.id).triggers_enabled).toEqual([false]);
});

// @S13 @variant:activation-limited
// Scenario: Switching a workflow on beyond the plan's limit is refused on save
//   Given the usage limiter refuses workflow activation with "Your plan is at its limit."
//   And "Intake" is saved with its triggers disabled
//   When I turn the workflow switch on and save
//   Then I see "Failed to save workflow" with "Your plan is at its limit."
//   And "Intake" still has its triggers disabled
test('@S13', tags('S13', true), async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'editor' }, { enabled: false });
  withSetting(withRefusingLimiter(LIMIT));
  await openAs(page, wf);

  await workflowSwitch(page).click();
  await expect(workflowSwitch(page)).toBeChecked();
  await saveButton(page).click();

  await expect(editorToast(page, 'Failed to save workflow')).toBeVisible();
  await expect(editorToast(page, LIMIT)).toBeVisible();
  expect(storedWorkflow(wf.id).triggers_enabled).toEqual([false]);
});

// @S14 @variant:experimental-features
// Scenario: Editor takes a draft workflow live after confirming
//   Given I am an editor with draft workflow "Intake" open
//   Then I see a "Draft" badge and a "Go live" button, and no workflow switch
//   When I click "Go live"
//   Then I see "This puts the workflow into production. Its triggers will be turned on and it will start processing real data."
//   When I confirm "Go live"
//   Then the badge says "Live", the triggers are enabled, and a release is recorded
test('@S14', tags('S14'), async ({ page }) => {
  experimental();
  const { wf } = givenIntake({ [ME]: 'editor' }, { enabled: false });
  await openAs(page, wf);
  await expect(lifecycleBadge(page)).toHaveText('Draft');
  await expect(workflowSwitch(page)).toHaveCount(0);
  const releases = releasesOf(wf.id);

  await headerButton(page, 'Go live').click();
  await expect(confirmDialog(page, 'Go live')).toContainText(
    'This puts the workflow into production. Its triggers will be turned on and it will start processing real data.'
  );
  await confirm(page, 'Go live');

  await expect(lifecycleBadge(page)).toHaveText('Live');
  await expect.poll(() => storedWorkflow(wf.id).state).toBe('live');
  expect(storedWorkflow(wf.id).triggers_enabled).toEqual([true]);
  expect(releasesOf(wf.id)).toBe(releases + 1);
});

// @S15 @variant:experimental-features
// Scenario: Going live saves what is on screen
//   Given I am an editor with draft workflow "Intake" open
//   And I have renamed "Fetch" to "Fetch patients" without saving
//   When I go live
//   Then the live workflow has a step named "Fetch patients"
test('@S15', tags('S15'), async ({ page }) => {
  experimental();
  const { wf } = givenIntake({ [ME]: 'editor' }, { enabled: false });
  await openAs(page, wf);
  await renameStep(page, 'Fetch', 'Fetch patients');

  await headerButton(page, 'Go live').click();
  await confirm(page, 'Go live');

  await expect.poll(() => storedWorkflow(wf.id).state).toBe('live');
  expect(storedWorkflow(wf.id).steps).toContain('Fetch patients');
});

// @S16 @variant:experimental-features
// Scenario: A live workflow is locked until it is switched to draft
//   Given I am an editor with live workflow "Intake" open
//   Then I see a "Live" badge and no "Read-only" pill, no "Save" button, and "Switch to draft" and "Edit in sandbox" buttons
//   And the canvas is read-only with "This workflow is live. Switch to draft or edit in a sandbox to make changes."
//   When I click "Switch to draft" and confirm
//   Then the badge says "Draft", the triggers are disabled and I can edit again
test('@S16', tags('S16'), async ({ page }) => {
  experimental();
  const { wf, by } = givenIntake({ [ME]: 'editor' }, { enabled: false });
  goLiveOnNode(wf.id, by);
  await openAs(page, wf);

  await expect(lifecycleBadge(page)).toHaveText('Live');
  await expect(readOnlyPill(page)).toHaveCount(0);
  await expect(saveButton(page)).toHaveCount(0);
  await expect(headerButton(page, 'Switch to draft')).toBeVisible();
  await expect(headerButton(page, 'Edit in sandbox')).toBeVisible();
  // Soft, so switching to draft is still checked
  expect
    .soft(await controlTooltip(page, undoButton(page)))
    .toBe(
      'This workflow is live. Switch to draft or edit in a sandbox to make changes.'
    );
  await node(page, 'Fetch').hover();
  await expect(plusButton(page, 'Fetch')).toHaveCount(0);

  await headerButton(page, 'Switch to draft').click();
  await confirm(page, 'Switch to draft');

  await expect(lifecycleBadge(page)).toHaveText('Draft');
  await expect.poll(() => storedWorkflow(wf.id).state).toBe('draft');
  expect(storedWorkflow(wf.id).triggers_enabled).toEqual([false]);
  await node(page, 'Fetch').hover();
  await expect(plusButton(page, 'Fetch')).toBeVisible();
});

// @S17 @variant:experimental-features @variant:activation-limited
// Scenario: Going live beyond the plan's limit says so and leaves the workflow in draft
//   Given the usage limiter refuses workflow activation with "Your plan is at its limit."
//   And I am an editor with draft workflow "Intake" open, whose triggers are disabled
//   When I go live
//   Then I see "Could not go live" with "Your plan is at its limit."
//   And "Intake" is still a draft
test('@S17', tags('S17', true), async ({ page }) => {
  experimental();
  const { wf } = givenIntake({ [ME]: 'editor' }, { enabled: false });
  withSetting(withRefusingLimiter(LIMIT));
  await openAs(page, wf);

  await headerButton(page, 'Go live').click();
  await confirm(page, 'Go live');

  await expect(editorToast(page, 'Could not go live')).toBeVisible();
  await expect(editorToast(page, LIMIT)).toBeVisible();
  expect(storedWorkflow(wf.id).state).toBe('draft');
  expect(storedWorkflow(wf.id).triggers_enabled).toEqual([false]);
});

// The workflow called <name> in project <projectId>, as the editor opens it
function workflowIn(projectId: string, name: string): EditorWorkflow {
  const found = workflowsOf(projectId).find(w => w.name === name);
  if (!found) throw new Error(`no workflow ${name} in ${projectId}`);
  return { id: found.id, projectId, name, steps: {}, triggerId: null };
}

// @S18 @variant:experimental-features @variant:sandbox
// Scenario: Editor turns a sandbox's copy of a workflow on and off
//   Given I am an editor with "Intake" open in sandbox "dev"
//   Then I see "Turn on" and "Promote", and no "Go live" or lifecycle badge
//   When I click "Turn on"
//   Then the sandbox's "Intake" triggers are enabled and the button says "Turn off"
test('@S18', tags('S18'), async ({ page }) => {
  experimental();
  const { w } = givenProject(
    { [ME]: 'editor' },
    { workflows: ['Intake'], sandboxes: [{ name: 'dev' }] }
  );
  const wf = workflowIn(w.id('dev'), 'Intake');
  exec(`update triggers set enabled = false where workflow_id = '${wf.id}'`);
  await openAs(page, wf);

  await expect(headerButton(page, 'Turn on')).toBeVisible();
  await expect(headerButton(page, 'Promote')).toBeVisible();
  await expect(headerButton(page, 'Go live')).toHaveCount(0);
  await expect(lifecycleBadge(page)).toHaveCount(0);

  await headerButton(page, 'Turn on').click();

  await expect(headerButton(page, 'Turn off')).toBeVisible();
  await expect
    .poll(() => storedWorkflow(wf.id).triggers_enabled)
    .toEqual([true]);
});

// @S19 @variant:sandbox
// Scenario: The header shows the sandbox path from the highest project I can reach
//   Given "Root" has sandbox "a", which has sandbox "b"
//   And I am an owner on "a" and "b" but not on "Root"
//   When I open a workflow in "b"
//   Then the project picker button says "a/b" and is marked as a sandbox
// A project has one owner (owner@openfn.org built them), so I am an admin.
test('@S19', tags('S19'), async ({ page }) => {
  const { w } = givenProject(
    { [OWNER]: 'owner' },
    {
      name: 'Root',
      sandboxes: [
        {
          name: 'a',
          members: { [ME]: 'admin' },
          sandboxes: [
            { name: 'b', members: { [ME]: 'admin' }, workflows: ['Intake'] },
          ],
        },
      ],
    }
  );
  const wf = workflowIn(w.id('b'), 'Intake');
  await openAs(page, wf);

  const picker = page.getByRole('button', { name: /^a\s*[/:]\s*b$/ });
  await expect(picker).toBeVisible();
  await expect(page.getByRole('button', { name: /Root/ })).toHaveCount(0);
  // Marked as a sandbox: drawn in the sandbox's colour, not the plain button's
  await expect(picker).not.toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
});

// @S20
// Scenario: The header shows the project's environment
//   Given project "Malawi HIV" has environment "production"
//   When I open one of its workflows
//   Then I see a "production" badge after the workflow name, titled "Project environment is production"
test('@S20', tags('S20'), async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'viewer' }, {}, { env: 'production' });
  await openAs(page, wf);

  const badge = environmentBadge(page, 'production');
  await expect(badge).toHaveText('production');
  expect((await badge.boundingBox())!.x).toBeGreaterThan(
    (await workflowTitle(page, 'Intake').boundingBox())!.x
  );
});

// @S21
// Scenario: Clicking the workflow name returns to the bare canvas
//   Given I have "Intake" open with a step selected, the run panel open and a run loaded
//   When I click "Intake" in the header
//   Then no panel is open, nothing is selected and no run is loaded
//   And the back button returns me to where I was
test('@S21', tags('S21'), async ({ page }) => {
  const p = givenProject({ [ME]: 'editor' });
  const run = seedRun(
    p.id,
    { workflow: 'Intake', steps: [{ name: 'Fetch' }, { name: 'Load' }] },
    p.by
  );
  cleanups.unshift(run.removeCredentials);
  await signInAs(page, ME);
  await openEditor(page, p.id, run.workflowId, `?panel=run&run=${run.runId}`);
  await node(page, 'Fetch').click();
  await expect.poll(() => editorQuery(page).run).toBe(run.runId);
  await expect.poll(() => Object.keys(editorQuery(page))).toContain('job');
  const before = new URL(page.url()).search;

  await workflowTitle(page, 'Intake').click();

  await expect.poll(() => editorQuery(page)).toEqual({});
  await expect(panelHeading(page, 'Fetch')).toHaveCount(0);

  await page.goBack();
  await expect.poll(() => new URL(page.url()).search).toBe(before);
});

// @S22
// Scenario: Workflow settings open from the header and flag errors
//   Given I have "Intake" open and its name is blank in the draft
//   Then the settings button in the header is red
//   When I click it
//   Then the workflow settings panel opens and the flow hands off to workflow-editor-inspectors
//   When I click it again
//   Then the panel closes
test('@S22', tags('S22'), async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf);
  expect(await settingsFlagged(page)).toBe(false);
  await renameWorkflow(page, '');
  await settingsButton(page).click();
  await expect(panelHeading(page, 'Workflow settings')).toHaveCount(0);

  await expect.poll(() => settingsFlagged(page)).toBe(true);

  await settingsButton(page).click();
  await expect(panelHeading(page, 'Workflow settings')).toBeVisible();
  await settingsButton(page).click();
  await expect(panelHeading(page, 'Workflow settings')).toHaveCount(0);
});

// @S23 @variant:stale-build
// Scenario: People are told when a newer build has been deployed
//   Given I opened "Intake" before a deploy changed the editor's assets
//   When my page reconnects
//   Then I see "A new version of Lightning is available" with "Save any changes, then reload to update." and a "Reload" button
//   And the message stays until I reload
test('@S23', tags('S23'), () => {
  test.skip(true, 'variant stale-build is not configured on this instance');
});

// @S24 @variant:require-email-verification
// Scenario: An unconfirmed user is warned in the editor and can ask for a new link
//   Given my account was created 2 hours ago and my email is unconfirmed
//   When I open "Intake"
//   Then I see "Please confirm your account before" followed by the deadline 48 hours after sign-up, above the header
//   When I click "Resend confirmation email"
//   Then the flow "flow-resend-account-confirmation" has started
test('@S24', tags('S24', true), async ({ page }) => {
  const { wf } = givenIntake();
  withSetting(withFlag('require_email_verification', true));
  withSetting(unconfirmedSince(ME, 2));
  await openAs(page, wf);

  const banner = page
    .getByRole('alert')
    .filter({ hasText: 'Please confirm your account before' });
  await expect(banner).toBeVisible();
  expect((await banner.boundingBox())!.y).toBeLessThan(
    (await saveButton(page).boundingBox())!.y
  );

  // The handoff: the resend request is made and answered
  await banner.getByRole('link', { name: /Resend confirmation email/ }).click();
  await expect(
    page.getByText(/confirmation (email|link)|check your email/i).first()
  ).toBeVisible();
});

// @S25 @variant:experimental-features @variant:sandbox
// Scenario: Archiving a sandbox from the editor hands off to the sandbox flows
//   Given I am an owner on sandbox "sb" and promoted "alpha" from it
//   When I click "Archive sandbox"
//   Then the flow "flow-sandbox-merge" continues at its S10
//   And the flow "flow-sandbox-scheduled-deletion" has started for "sb"
test('@S25', tags('S25'), async ({ page }) => {
  experimental();
  const { w } = givenProject(
    { [ME]: 'editor' },
    // A project has one owner (owner@openfn.org built it); an admin may
    // archive the sandbox too
    {
      workflows: ['alpha'],
      sandboxes: [{ name: 'sb', members: { [ME]: 'admin' } }],
    }
  );
  const sb = w.id('sb');
  const wf = workflowIn(sb, 'alpha');
  await openAs(page, wf);

  // Given I promoted "alpha": the promote dialog then offers the archive
  await headerButton(page, 'Promote').click();
  await submit(page.getByRole('dialog'), 'Save and promote');

  await headerButton(page, 'Archive sandbox').click();

  // flow-sandbox-scheduled-deletion has started for "sb"
  await expect.poll(() => scheduledDeletionOf(sb)).not.toBeNull();
  // flow-sandbox-merge continues: the editor leaves the sandbox
  await expect
    .poll(() => new URL(page.url()).pathname)
    .not.toContain(`/projects/${sb}/`);
});

// @S26
// Scenario: The editor follows a workflow deleted elsewhere
//   Given I have "Intake" open
//   When another member deletes "Intake" from the workflows list
//   Then the flow "flow-delete-open-workflow" ends here at its S01 and S02
test('@S26', tags('S26'), async ({ page }) => {
  const { id, wf } = givenIntake({ [ME]: 'editor' });
  await openAs(page, wf);

  deleteWorkflowOnNode(wf.id, OWNER);

  await expectAt(page, workflowsListPath(id));
  await expect(page.getByText('Workflow deleted.')).toBeVisible();
});

// @S27
// Scenario: The editor follows a switch made on the workflows list
//   Given I have "Intake" open
//   When another member switches "Intake" off on the workflows list
//   Then the flow "flow-toggle-workflow-open-editor" ends here at its S01
test('@S27', tags('S27'), async ({ page }) => {
  setPreferences(ME, { experimental_features: false });
  const { wf } = givenIntake({ [ME]: 'editor' }, { enabled: true });
  await openAs(page, wf);
  await expect(workflowSwitch(page)).toBeChecked();

  switchWorkflowOnNode(wf.id, false, OWNER);

  await expect(workflowSwitch(page)).not.toBeChecked({ timeout: 15000 });
  await expect(unsavedMarker(page)).toHaveCount(0);
});

// @S28
// Scenario: A workflow from another project is not opened
//   Given I am an owner on "Malawi HIV" and not on "Kenya TB"
//   When I open "/projects/<Malawi HIV id>/w/<a Kenya TB workflow id>"
//   Then I am on "/projects/<Malawi HIV id>/w"
//   And I see "Workflow not found"
test('@S28', tags('S28'), async ({ page }) => {
  const malawi = givenProject({ [ME]: 'owner' });
  const kenya = givenIntake({ [OWNER]: 'owner' }, {}, { name: 'Kenya TB' });
  await signInAs(page, ME);

  await page.goto(editorPath(malawi.id, kenya.wf.id));

  await expectAt(page, workflowsListPath(malawi.id));
  await expect(page.getByText('Workflow not found')).toBeVisible();
  await expect(node(page, 'Fetch')).toHaveCount(0);
});

// @S29
// Scenario: Having a workflow open blocks API writes to it
//   Given I have "Intake" open
//   When a client updates "Intake" through the workflows API
//   Then the flow "flow-workflow-api-edit-conflict" applies
test('@S29', tags('S29'), async ({ page, request }) => {
  const { id, wf } = givenIntake({ [ME]: 'viewer' });
  await openAs(page, wf);
  const token = seededApiTokenOf(OWNER).token;

  const res = await patchWithBearer(
    request,
    `/api/projects/${id}/workflows/${wf.id}`,
    token,
    { name: 'Renamed by a script' }
  );

  expect(res.status()).toBe(409);
  expect(storedWorkflow(wf.id).name).toBe('Intake');
});

// ---------------------------------------------------------------------------
// shared-editor-session
// ---------------------------------------------------------------------------

test.describe('shared-editor-session', () => {
  const ON = 'on workflow-editor-canvas';
  const name = (id: string) => `shared-editor-session@${id} ${ON}`;

  test(name('S01'), tags('shared-editor-session@S01'), async ({ page }) => {
    const { wf } = givenIntake({ [ME]: 'viewer' });
    await editorSession.S01(page, ME, wf);
  });

  for (const id of ['S02', 'S05', 'S07', 'S08'] as const)
    test(
      name(id),
      tags(`shared-editor-session@${id}`),
      async ({ page, browser }) => {
        const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
        const other = await otherSession(browser, THIRD);
        await editorSession[id](page, other, [ME, THIRD], wf);
      }
    );

  for (const id of ['S03', 'S06', 'S22'] as const)
    test(name(id), tags(`shared-editor-session@${id}`), async ({ page }) => {
      const { wf } = givenIntake();
      await editorSession[id](page, ME, wf);
    });

  test(name('S04'), tags('shared-editor-session@S04'), async ({ page }) => {
    const { wf, by } = givenIntake();
    await editorSession.S04(page, ME, wf, () =>
      renameStepOnNode(wf.id, 'Load', 'Load v2', by)
    );
  });

  // Saves wait on the adaptor catalogue, which is instance-wide
  test(
    name('S09'),
    tags('shared-editor-session@S09', true),
    async ({ page }) => {
      const { wf } = givenIntake();
      await editorSession.S09(page, ME, wf, catalogueUnavailable);
    }
  );

  test(name('S10'), tags('shared-editor-session@S10'), async ({ page }) => {
    // Examples, one workflow each; soft expectations in the step
    const viewer = givenIntake({ [ME]: 'viewer' });
    await editorSession.S10(
      page,
      ME,
      viewer.wf,
      'You do not have permission to edit this workflow'
    );

    const pinned = seedEditorWorkflow(viewer.id, viewer.by, {
      name: 'Intake pinned',
    });
    const v = storedWorkflow(pinned.id).lock_version;
    renameStepOnNode(pinned.id, 'Load', 'Load v2', viewer.by);
    changeRoleOnNode(viewer.id, ME, 'editor', { quietly: true });
    await page.goto('about:blank');
    await editorSession.S10(
      page,
      ME,
      pinned,
      'You are viewing a pinned version of this workflow',
      { query: `?v=${v}`, room: `v${v}` }
    );
  });

  test(name('S11'), tags('shared-editor-session@S11'), async ({ page }) => {
    const { id, wf } = givenIntake();
    await editorSession.S11(page, ME, wf, () =>
      changeRoleOnNode(id, ME, 'viewer')
    );
  });

  test(
    name('S12'),
    tags('shared-editor-session@S12'),
    async ({ page, browser }) => {
      const { id, wf } = givenIntake({
        [ME]: 'editor',
        [THIRD]: 'editor',
      });
      const other = await otherSession(browser, THIRD);
      await editorSession.S12(page, other, [ME, THIRD], wf, () =>
        removeMemberOnNode(id, ME, OWNER)
      );
    }
  );

  // A support user sees every project that allows support access
  test(
    name('S13'),
    tags('shared-editor-session@S13', true),
    async ({ page, browser }) => {
      const { id, wf } = givenIntake(
        { [THIRD]: 'editor' },
        {},
        { allowSupportAccess: true }
      );
      cleanups.push(makeSupportUser(ME));
      const editor = await otherSession(browser, THIRD);
      await editorSession.S13(
        page,
        editor,
        { support: ME, editor: THIRD },
        wf,
        () => setSupportAccessOnNode(id, false)
      );
    }
  );

  test(name('S14'), tags('shared-editor-session@S14'), async ({ page }) => {
    // Example 1: a registered user not on the project
    const { wf } = givenIntake({ [OWNER]: 'owner' });
    await editorSession.S14(page, ME, wf);

    // Example 2: an editor who has not enrolled in MFA, on an MFA project
    const mfa = givenIntake({ [ME]: 'editor' }, {}, { name: 'MFA project' });
    exec(`update projects set requires_mfa = true where id = '${mfa.id}'`);
    removeMfaOf(ME);
    await editorSession.S14(page, ME, mfa.wf);
  });

  test(
    name('S15'),
    tags('shared-editor-session@S15'),
    async ({ page, browser }) => {
      const one = givenIntake(
        { [ME]: 'editor', [THIRD]: 'editor' },
        {},
        { name: 'project-1' }
      );
      const two = givenIntake(
        { [ME]: 'editor', [THIRD]: 'editor' },
        {},
        { name: 'project-2' }
      );
      const other = await otherSession(browser, THIRD);
      await editorSession.S15(page, other, [ME, THIRD], one.wf, two.wf, () =>
        scheduleDeletionOnNode(one.id)
      );
    }
  );

  test(
    name('S16'),
    tags('shared-editor-session@S16'),
    async ({ page, browser }) => {
      const { id, by, wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
      const second = seedEditorWorkflow(id, by, { name: 'Other' });
      const other = await otherSession(browser, THIRD);
      await editorSession.S16(page, other, [ME, THIRD], wf, second, () =>
        deleteWorkflowOnNode(wf.id, OWNER)
      );
    }
  );

  test(
    name('S17'),
    tags('shared-editor-session@S17'),
    async ({ page, browser }) => {
      const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
      const her = await otherSession(browser, THIRD);
      const secondTab = await her.context().newPage();
      await editorSession.S17(page, her, secondTab, ME, nameOf(THIRD), wf);
    }
  );

  test(
    name('S18'),
    tags('shared-editor-session@S18'),
    async ({ page, browser }) => {
      const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
      const her = await otherSession(browser, THIRD);
      await editorSession.S18(page, her, ME, nameOf(THIRD), wf);
    }
  );

  test(name('S19'), tags('shared-editor-session@S19'), async ({ page }) => {
    // "Load" starts unconnected, so the path change can add one: a trigger
    // has no handle to drag a path from
    const { wf } = givenIntake(
      { [ME]: 'editor' },
      { paths: [['trigger', 'Fetch']] }
    );
    await editorSession.S19(page, ME, wf, {
      name: p => renameWorkflow(p, 'Intake renamed'),
      step: p => renameStep(p, 'Fetch', 'Fetch renamed'),
      path: p => dragPath(p, 'Fetch', 'Load').then(() => undefined),
      trigger: p => workflowSwitch(p).click(),
      position: async p => {
        await layoutModeSwitch(p).click();
        await dragStep(p, 'Load', 150, 60);
      },
    });
  });

  test(
    name('S20'),
    tags('shared-editor-session@S20'),
    async ({ page, browser }) => {
      experimental();
      const { w, by, wf } = givenIntake(
        { [ME]: 'editor', [THIRD]: 'editor' },
        {},
        { sandboxes: [{ name: 'dev' }] }
      );
      goLiveOnNode(wf.id, by);
      setPreferences(THIRD, { experimental_features: false });
      cleanups.push(keepAccount(THIRD));
      const colleague = await otherSession(browser, THIRD);
      await signInAs(page, ME);
      expect(w.id('dev')).toBeTruthy();
      await editorSession.S20(
        page,
        colleague,
        { me: ME, colleague: THIRD },
        wf,
        'dev'
      );
    }
  );

  test(
    name('S21'),
    tags('shared-editor-session@S21'),
    async ({ page, browser }) => {
      const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'viewer' });
      const viewer = await otherSession(browser, THIRD);
      await editorSession.S21(page, viewer, { editor: ME, viewer: THIRD }, wf);
    }
  );
});

// ---------------------------------------------------------------------------
// shared-authenticated-session
// ---------------------------------------------------------------------------

test.describe('shared-authenticated-session', () => {
  const name = (id: string) =>
    `shared-authenticated-session@${id} on workflow-editor-canvas`;
  const PASSED = ['S01', 'S02', 'S03', 'S07'];

  for (const id of ['S01', 'S03'] as const)
    test(name(id), { tag: tagFor(id, PASSED) }, async ({ page }) => {
      await authenticatedSession[id](page, givenIntake().path, ME);
    });

  test(
    name('S02'),
    { tag: tagFor('S02', PASSED) },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, givenIntake().path, ME);
    }
  );

  // The variant is an instance flag read at request time
  test(
    name('S04'),
    tags('shared-authenticated-session@S04', true),
    async ({ page }) => {
      const h = givenIntake();
      withSetting(withFlag('require_email_verification', true));
      withSetting(unconfirmedSince(ME, 50));
      await authenticatedSession.S04(page, h.path, ME);
    }
  );

  test(
    name('S05'),
    tags('shared-authenticated-session@S05', true),
    async ({ page }) => {
      withSetting(withFlag('require_email_verification', true));
      withSetting(unconfirmedSince(ME, 50));
      await authenticatedSession.S05(page, ME);
    }
  );

  test(
    name('S07'),
    { tag: tagFor('S07', PASSED) },
    async ({ page, browser }) => {
      const h = givenIntake();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        workflowsListPath(h.id),
        ME,
        'History'
      );
    }
  );

  for (const [id, variant] of [
    ['S06', 'require-email-verification'],
    ['S08', 'book-demo-banner'],
    ['S09', 'book-demo-banner'],
    ['S10', 'gdpr-banner'],
    ['S11', 'first-setup-open'],
  ])
    test(name(id), { tag: tagFor(id, PASSED) }, () => {
      test.skip(true, `variant ${variant} is not configured on this instance`);
    });
});

// ---------------------------------------------------------------------------
// shared-project-scope (S10, S11 and S12 are the receiving ends of project
// deletion, sandbox archive and workflow deletion on this page)
// ---------------------------------------------------------------------------

test.describe('shared-project-scope', () => {
  const name = (id: string) =>
    `shared-project-scope@${id} on workflow-editor-canvas`;

  test(name('S01'), tags('shared-project-scope@S01'), async ({ page }) => {
    await projectScope.S01(page, givenIntake().path);
  });

  test(name('S02'), tags('shared-project-scope@S02'), async ({ page }) => {
    await projectScope.S02(page, givenIntake().path, ME, node(page, 'Fetch'));
  });

  test(name('S03'), tags('shared-project-scope@S03'), async ({ page }) => {
    const h = givenIntake({ [OWNER]: 'owner' });
    await projectScope.S03(page, h.path, ME);
  });

  test(name('S04'), tags('shared-project-scope@S04'), async ({ page }) => {
    const h = givenIntake({ [ME]: 'owner' }, {}, { scheduledInDays: 7 });
    await projectScope.S04(page, h.path, ME);
  });

  test(name('S05'), tags('shared-project-scope@S05'), async ({ page }) => {
    const h = givenIntake();
    exec(`update projects set requires_mfa = true where id = '${h.id}'`);
    removeMfaOf(ME);
    await projectScope.S05(page, h.path, ME);
  });

  test(
    name('S06'),
    tags('shared-project-scope@S06', true),
    async ({ page }) => {
      const h = givenIntake(
        { [OWNER]: 'owner' },
        {},
        { allowSupportAccess: true }
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, node(page, 'Fetch'));
    }
  );

  test(name('S07'), tags('shared-project-scope@S07'), async ({ page }) => {
    const h = givenIntake();
    await projectScope.S07(page, h.path, ME, () =>
      removeMemberOnNode(h.id, ME, OWNER)
    );
  });

  test(name('S08'), tags('shared-project-scope@S08'), async ({ page }) => {
    const h = givenIntake({ [ME]: 'admin' });
    await projectScope.S08(
      page,
      `${h.path}?panel=settings`,
      ME,
      () => changeRoleOnNode(h.id, ME, 'viewer'),
      canvas(page)
    );
  });

  test(
    name('S09'),
    tags('shared-project-scope@S09', true),
    async ({ page }) => {
      const h = givenIntake(
        { [OWNER]: 'owner' },
        {},
        { allowSupportAccess: true }
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S09(page, h.path, ME, () =>
        setSupportAccessOnNode(h.id, false)
      );
    }
  );

  test(name('S10'), tags('shared-project-scope@S10'), async ({ page }) => {
    const h = givenIntake();
    await projectScope.S10(page, h.path, ME, () =>
      scheduleDeletionOnNode(h.id)
    );
  });

  // The preference is data, so the variant is seeded rather than skipped
  test(name('S11'), tags('shared-project-scope@S11'), async ({ page }) => {
    experimental();
    const { w, id, by } = givenProject(
      { [ME]: 'editor' },
      { workflows: ['Intake'], sandboxes: [{ name: 'dev' }] }
    );
    const sandbox = workflowIn(w.id('dev'), 'Intake');
    const parent = workflowIn(id, 'Intake');
    expect(by).toBe(OWNER);
    await projectScope.S11(
      page,
      editorPath(sandbox.projectId, sandbox.id),
      ME,
      () => scheduleDeletionOnNode(sandbox.projectId),
      editorPath(id, parent.id)
    );
  });

  test(name('S12'), tags('shared-project-scope@S12'), async ({ page }) => {
    const h = givenIntake();
    await projectScope.S12(
      page,
      h.path,
      ME,
      () => deleteWorkflowOnNode(h.wf.id, OWNER),
      workflowsListPath(h.id)
    );
  });
});

// ---------------------------------------------------------------------------
// shared-usage-limits-banner
// ---------------------------------------------------------------------------

test.describe('shared-usage-limits-banner', () => {
  test(
    'shared-usage-limits-banner@S01 on workflow-editor-canvas',
    tags('shared-usage-limits-banner@S01'),
    () => {
      test.skip(
        true,
        'variant usage-limited is not configured on this instance'
      );
    }
  );

  test(
    'shared-usage-limits-banner@S02 on workflow-editor-canvas',
    tags('shared-usage-limits-banner@S02'),
    async ({ page }) => {
      await usageLimitsBanner.S02(
        page,
        givenIntake().path,
        ME,
        node(page, 'Fetch')
      );
    }
  );
});

// ---------------------------------------------------------------------------
// shared-project-header: the picker modal only (S04 to S12). The editor draws
// its own React header; its picker button opens the layout's global picker.
// The picker scenarios seed their own "Malawi HIV", so this page's project
// has another name.
// ---------------------------------------------------------------------------

test.describe('shared-project-header', () => {
  const HOST = 'Editor host';
  const PASSED = ['S04', 'S05', 'S06', 'S08', 'S11', 'S12'];
  const name = (id: string) =>
    `shared-project-header@${id} on workflow-editor-canvas`;

  for (const id of ['S04', 'S05', 'S06', 'S08', 'S11', 'S12'] as const)
    test(name(id), { tag: tagFor(id, PASSED) }, async ({ page }) => {
      const h = givenIntake({ [ME]: 'editor' }, {}, { name: HOST });
      await projectHeader[id](page, h.path, ME);
    });

  // A support user sees every project that allows support access
  test(
    name('S07'),
    tags('shared-project-header@S07', true),
    async ({ page }) => {
      const h = givenIntake({ [ME]: 'editor' }, {}, { name: HOST });
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, whatever page hosts the header
  test(name('S09'), tags('shared-project-header@S09'), async ({ page }) => {
    await projectHeader.S09(page, ME);
  });

  // The Examples row "a workflow's editor | the workflows page"
  test(name('S10'), tags('shared-project-header@S10'), async ({ page }) => {
    const h = givenIntake({ [ME]: 'editor' }, {}, { name: HOST });
    await projectHeader.S10(page, h.path, ME, '/w');
  });

  // shared-project-header S01 to S03 and S13 to S18 are not run here: the
  // inherits comment narrows this page to the picker modal (S04 to S12),
  // because the editor draws its own header.
});

// ---------------------------------------------------------------------------
// shared-flash-messages. The editor's own messages are toasts of its own
// (shared-editor-session); the flashes it ends up showing arrive on the page
// it sends people to.
// ---------------------------------------------------------------------------

test.describe('shared-flash-messages', () => {
  const FLASH = 'Workflow deleted.';
  const name = (id: string) =>
    `shared-flash-messages@${id} on workflow-editor-canvas`;

  // Given I have the editor open and another user deletes the workflow: the
  // workflow list I land on shows the info flash "Workflow deleted."
  async function withDeletion(page: Page) {
    const h = givenIntake();
    // A second workflow keeps the list's table (and its Name header) on screen
    seedEditorWorkflow(h.id, h.by, { name: 'Other' });
    await openAs(page, h.wf);
    const deleteIt = () =>
      Promise.resolve(deleteWorkflowOnNode(h.wf.id, OWNER));
    return { h, deleteIt };
  }

  test(name('S01'), tags('shared-flash-messages@S01'), async ({ page }) => {
    const { deleteIt } = await withDeletion(page);
    await flashMessages.S01(page, FLASH, deleteIt);
  });

  // The error flash this page can end up showing: "Workflow not found"
  test(name('S02'), tags('shared-flash-messages@S02'), async ({ page }) => {
    const h = givenIntake();
    const other = givenIntake({ [ME]: 'viewer' }, {}, { name: 'Kenya TB' });
    await signInAs(page, ME);
    await flashMessages.S02(page, 'Workflow not found', async () => {
      await page.goto(editorPath(h.id, other.wf.id));
    });
  });

  test(name('S03'), tags('shared-flash-messages@S03'), async ({ page }) => {
    const { deleteIt } = await withDeletion(page);
    await flashMessages.S03(page, FLASH, deleteIt);
  });

  test(name('S04'), tags('shared-flash-messages@S04'), async ({ page }) => {
    const { deleteIt } = await withDeletion(page);
    await flashMessages.S04(page, FLASH, deleteIt, async () => {
      // Sorting makes the workflow list render again
      await page.getByRole('columnheader', { name: 'Name' }).click();
      await expect(
        page.getByRole('columnheader', { name: 'Name' })
      ).toBeVisible();
    });
  });

  test(name('S05'), tags('shared-flash-messages@S05'), async ({ page }) => {
    const { h, deleteIt } = await withDeletion(page);
    await flashMessages.S05(page, FLASH, deleteIt, workflowsListPath(h.id));
  });

  test(name('S06'), tags('shared-flash-messages@S06'), async ({ page }) => {
    const h = givenIntake();
    const notMine = givenIntake({ [OWNER]: 'owner' }, {}, { name: 'Kenya TB' });
    await openAs(page, h.wf);

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
  });

  // shared-flash-messages S07 (admin pages only) and S08 (sign-in and account
  // forms only) are not run on this page: it shows neither.
});

// ---------------------------------------------------------------------------
// shared-run-retry-controls: the header's run control (S01 to S03, S07, S10,
// S11, S13) and the retry endpoint (S12), which needs no surface. S04 to S06,
// S08 and S09 run where the run panel and the IDE are
// (workflow-editor-manual-run, workflow-editor-ide).
// ---------------------------------------------------------------------------

test.describe('shared-run-retry-controls', () => {
  const name = (id: string) =>
    `shared-run-retry-controls@${id} on workflow-editor-canvas`;

  // Given project "Malawi HIV" with these members has a finished run of
  // "Intake" (steps "Fetch" and "Load"), seeded through Lightning
  function givenFinishedRun(
    members: Record<string, Role> = { [ME]: 'editor' }
  ) {
    const p = givenProject(members);
    const run = seedRun(
      p.id,
      { workflow: 'Intake', steps: [{ name: 'Fetch' }, { name: 'Load' }] },
      p.by
    );
    cleanups.unshift(run.removeCredentials);
    // A run is started from the trigger's path, so the trigger needs one
    connectRunWorkflow(run.workflowId, p.id, ['Fetch', 'Load']);
    return { ...p, run };
  }

  const triggerOf = (workflowId: string) =>
    sql<{ id: string }>(
      `select id from triggers where workflow_id = '${workflowId}'`
    )[0].id;

  test(name('S01'), tags('shared-run-retry-controls@S01'), async ({ page }) => {
    const { wf } = givenIntake();
    await openAs(page, wf);
    await runRetry.S01(page, header(page), {
      ...wf,
      triggerId: wf.triggerId!,
    });
  });

  test(name('S02'), tags('shared-run-retry-controls@S02'), async ({ page }) => {
    const { id, run } = givenFinishedRun();
    await signInAs(page, ME);
    await openEditor(page, id, run.workflowId, `?run=${run.runId}`);
    await runRetry.S02(page, header(page), run);
  });

  test(name('S03'), tags('shared-run-retry-controls@S03'), async ({ page }) => {
    experimental();
    const { id, by, run } = givenFinishedRun();
    renameStepOnNode(run.workflowId, 'Load', 'Load v2', by);
    const latest = storedWorkflow(run.workflowId).lock_version;
    await signInAs(page, ME);
    await openEditor(
      page,
      id,
      run.workflowId,
      `?v=${run.version}&run=${run.runId}`
    );
    await runRetry.S03(page, header(page), run, {
      pinned: run.version,
      latest,
    });
  });

  test(name('S07'), tags('shared-run-retry-controls@S07'), async ({ page }) => {
    const { wf } = givenIntake();
    const fetch = wf.steps.Fetch;
    await openAs(page, wf, ME, `?panel=run&job=${fetch}`);
    await runRetry.S07(page, header(page), wf.id, fetch, () =>
      openEditor(page, wf.projectId, wf.id, `?panel=editor&job=${fetch}`)
    );
  });

  // Examples, one step each. The rows that make me an editor share one
  // workflow; the deleted row comes last.
  test(name('S10'), tags('shared-run-retry-controls@S10'), async ({ page }) => {
    const why = runRetry.given.S10;
    const h = givenIntake({ [ME]: 'viewer' });
    const sock = await watchEditorSocket(page);
    await openAs(page, h.wf);

    await test.step('I am a viewer', () =>
      runRetry.S10(page, header(page), why.viewer));

    changeRoleOnNode(h.id, ME, 'editor', { quietly: true });
    const pinned = storedWorkflow(h.wf.id).lock_version;
    renameStepOnNode(h.wf.id, 'Load', 'Load v2', h.by);
    await test.step('I am viewing a pinned version', async () => {
      await openEditor(page, h.id, h.wf.id, `?v=${pinned}`);
      await runRetry.S10(page, header(page), why.pinned);
    });

    await test.step('"Intake" is new and not yet created', async () => {
      // The editor's header shows once a starting point is chosen
      await openNew(page, h.id);
      await startCard(page, 'Build from scratch').click();
      await runRetry.S10(page, header(page), why.unsaved);
    });

    await test.step('the editor is disconnected', async () => {
      await openEditor(page, h.id, h.wf.id);
      sock.drop();
      await runRetry.S10(page, header(page), why.disconnected);
      sock.reconnect();
    });

    await test.step('"Intake" has been deleted', async () => {
      await openEditor(page, h.id, h.wf.id);
      deleteWorkflowOnNode(h.wf.id, OWNER);
      await runRetry.S10(page, header(page), why.deleted);
    });
  });

  // The usage limiter is instance-wide
  test(
    name('S11'),
    tags('shared-run-retry-controls@S11', true),
    async ({ page }) => {
      const { id, run } = givenFinishedRun();
      cleanups.push(withLimiterRefusing('new_run', runRetry.given.S11.limit));
      await signInAs(page, ME);
      await openEditor(page, id, run.workflowId, `?run=${run.runId}`);
      await runRetry.S11(
        page,
        header(page),
        {
          id: run.workflowId,
          projectId: id,
          triggerId: triggerOf(run.workflowId),
        },
        { runId: run.runId, stepId: run.steps.Fetch }
      );
    }
  );

  // Examples in turn: a viewer on "Malawi HIV", an editor on "Kenya TB" only,
  // signed out
  test(name('S12'), tags('shared-run-retry-controls@S12'), async ({ page }) => {
    const status = runRetry.given.S12;
    const malawi = givenFinishedRun({ [ME]: 'viewer' });
    const kenya = givenProject({ [ME]: 'editor' }, { name: 'Kenya TB' });
    const retry = { ...malawi.run, stepId: malawi.run.steps.Fetch };
    await signInAs(page, ME);
    await open(page, workflowsListPath(malawi.id));

    await test.step('I am a viewer on "Malawi HIV"', () =>
      runRetry.S12(page, retry, malawi.id, status.viewer));

    removeMemberOnNode(malawi.id, ME, OWNER);
    await open(page, workflowsListPath(kenya.id));
    await test.step('I am an editor on "Kenya TB" only', () =>
      runRetry.S12(page, retry, kenya.id, status.otherProject));

    await page.context().clearCookies();
    await page.goto('/users/log_in');
    await test.step('I am signed out', () =>
      runRetry.S12(page, retry, malawi.id, status.signedOut));
  });

  test(name('S13'), tags('shared-run-retry-controls@S13'), async ({ page }) => {
    const { wf } = givenIntake();
    // The e2e worker finishes a run at once; a slow first step keeps it
    // processing long enough to see
    exec(`update jobs set body = $b$fn(state => new Promise(r =>
      setTimeout(() => r(state), 10000)));$b$
      where id = '${wf.steps.Fetch}'`);
    await openAs(page, wf);
    await runRetry.S13(page, header(page), wf.id);
  });
});

// ---------------------------------------------------------------------------
// shared-adaptor-credential-config: the canvas reaches the adaptor picker
// only, through a step's plus button (S08 to S10). The rest runs where the
// adaptor box is (workflow-editor-inspectors, workflow-editor-ide).
// ---------------------------------------------------------------------------

test.describe('shared-adaptor-credential-config', () => {
  const name = (id: string) =>
    `shared-adaptor-credential-config@${id} on workflow-editor-canvas`;

  test(
    name('S08'),
    tags('shared-adaptor-credential-config@S08'),
    async ({ page }) => {
      const { wf } = givenIntake();
      await openAs(page, wf);
      await adaptorConfig.S08(
        page,
        () => clickPlus(page, 'Fetch'),
        node(page, 'Http')
      );
    }
  );

  // The adaptor catalogue is instance-wide
  test(
    name('S09'),
    tags('shared-adaptor-credential-config@S09', true),
    async ({ page }) => {
      let putBack: (() => void) | null = catalogueUnavailable();
      const makeAvailable = () => {
        putBack?.();
        putBack = null;
      };
      cleanups.push(makeAvailable);
      const { wf } = givenIntake();
      await openAs(page, wf);
      await adaptorConfig.S09(
        page,
        () => clickPlus(page, 'Fetch'),
        makeAvailable
      );
    }
  );

  test(
    name('S10'),
    tags('shared-adaptor-credential-config@S10', true),
    async ({ page }) => {
      cleanups.push(adaptorConfig.withRetiredAdaptors());
      const { wf } = givenIntake();
      await openAs(page, wf);
      await adaptorConfig.S10(page, () => clickPlus(page, 'Fetch'));
    }
  );
});
