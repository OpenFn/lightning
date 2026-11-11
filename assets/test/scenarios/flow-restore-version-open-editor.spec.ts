// Scenarios from annotations/flows/flow-restore-version-open-editor.md:
// restoring an earlier publish while a colleague has the workflow open.
//
// Who's who: "I" am editor@openfn.org, with experimental features on (they
// are what offer "Restore"), in tab A. super@openfn.org is "Ben", a second
// editor in a browser of his own (tab B): without experimental features
// unless a test says otherwise, so his editor is not locked on a live
// workflow. owner@openfn.org owns the project and saves and publishes its
// workflow through Lightning. Every project is seeded by the test and
// removed again afterwards.
//
// "Intake" is a webhook trigger leading to "Fetch cases", then "Load". It
// went live as v1; then a save added step "Notify" and changed the code of
// "Fetch cases", and that was published as v2.
import { expect, test, type Page } from '@playwright/test';

import {
  editorToast,
  node,
  openEditor,
  renameStep,
  saveButton,
  unsavedMarker,
} from './pages/workflow-editor';
import { addStepOnNode, codeText, openIde } from './pages/workflow-editor-ide';
import {
  chooseRestore,
  closeVersions,
  listedNumbers,
  openVersions,
  publishOnNode,
  restoreConfirm,
  saveBodyOnNode,
  versionRowText,
} from './pages/workflow-editor-versions-and-promote';
import {
  goLiveOnNode,
  keepAccount,
  nameOf,
  otherSession,
  removeWorkflowData,
  seedEditorWorkflow,
  seedWorkspace,
  setPreferences,
  signInAs,
  storedWorkflow,
  workflowMovesOnUnderSaves,
  type EditorWorkflow,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const BEN = 'super@openfn.org';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old'],
});

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };
// How long a page is watched for a change that should not come
const QUIET = 3000;

const V1_BODY = 'fn(s => s)';
const V2_BODY = "fn(s => ({ ...s, cases: 'all' }))";

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), keepAccount(BEN)];
  setPreferences(ME, { experimental_features: true });
  setPreferences(BEN, { experimental_features: false });
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given "Intake" is live with publishes v1 and v2 (see the header)
function givenTwoPublishes() {
  const w = seedWorkspace(
    {
      name: 'Malawi HIV',
      members: { [OWNER]: 'owner', [ME]: 'editor', [BEN]: 'editor' },
    },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id('Malawi HIV');
  cleanups.push(() => removeWorkflowData(id));
  const wf = seedEditorWorkflow(id, OWNER, { steps: ['Fetch cases', 'Load'] });
  goLiveOnNode(wf.id, OWNER);
  addStepOnNode(wf.id, 'Notify', OWNER);
  saveBodyOnNode(wf.id, 'Fetch cases', V2_BODY, OWNER);
  publishOnNode(wf.id, OWNER);
  return wf;
}

// Given Ben has <wf> open in tab B, with <query>
async function benOpens(
  browser: Parameters<typeof otherSession>[0],
  wf: EditorWorkflow,
  query = ''
) {
  const ben = await otherSession(browser, BEN);
  await openEditor(ben, wf.projectId, wf.id, query);
  return ben;
}

// When I restore v1 in tab A — waits for what I am told
async function restoreV1(page: Page, wf: EditorWorkflow, told: string) {
  await signInAs(page, ME);
  await openEditor(page, wf.projectId, wf.id);
  await chooseRestore(page, 'v1');
  await restoreConfirm(page, 1).click();
  await expect(editorToast(page, told)).toBeVisible();
}

// @S01 @variant:experimental-features
// Scenario: A colleague on Latest sees the restored workflow
//   Given "Intake" is live with publishes v1 and v2, and v2 added the step "Notify"
//   And "Ben" has "Intake" open on Latest in tab B
//   When I restore v1 in tab A
//   Then I see "Restored v1"
//   And eventually tab B's canvas no longer shows "Notify"
//   And tab B shows no unsaved changes marker
test('@S01', tags('S01'), async ({ page, browser }) => {
  const wf = givenTwoPublishes();
  const ben = await benOpens(browser, wf);
  await expect(node(ben, 'Notify')).toBeVisible();

  await restoreV1(page, wf, 'Restored v1');

  await expect(node(ben, 'Notify')).toHaveCount(0, EVENTUALLY);
  await expect(unsavedMarker(ben)).toHaveCount(0);
});

// @S02 @variant:experimental-features
// Scenario: A colleague's code editor shows the restored step body
//   Given v2 of "Intake" changed the body of "Fetch cases"
//   And "Ben" has "Fetch cases" open in the code editor in tab B
//   When I restore v1 in tab A
//   Then eventually tab B's code editor shows v1's body of "Fetch cases"
test('@S02', tags('S02'), async ({ page, browser }) => {
  const wf = givenTwoPublishes();
  const ben = await otherSession(browser, BEN);
  await openIde(ben, wf.projectId, wf.id, wf.steps['Fetch cases']);
  await expect.poll(() => codeText(ben)).toBe(V2_BODY);

  await restoreV1(page, wf, 'Restored v1');

  await expect.poll(() => codeText(ben), EVENTUALLY).toBe(V1_BODY);
});

// @S03 @variant:experimental-features @variant:colleague-can-edit
// Scenario: A colleague's next save keeps the rollback
//   Given "Ben" has "Intake" open on Latest without experimental features
//   When I restore v1 in tab A
//   And "Ben" renames step "Fetch cases" to "Fetch all cases" in tab B and saves
//   Then "Intake" has v1's steps with "Fetch all cases" renamed
//   And "Intake" does not have the step "Notify"
test('@S03', tags('S03'), async ({ page, browser }) => {
  const wf = givenTwoPublishes();
  const ben = await benOpens(browser, wf);

  await restoreV1(page, wf, 'Restored v1');
  await expect(node(ben, 'Notify')).toHaveCount(0, EVENTUALLY);
  await renameStep(ben, 'Fetch cases', 'Fetch all cases');
  await saveButton(ben).click();
  await expect(editorToast(ben, 'Workflow saved')).toBeVisible();

  expect(storedWorkflow(wf.id).steps).toEqual(['Fetch all cases', 'Load']);
});

// @S04 @variant:experimental-features
// Scenario: A colleague's version list shows the restore
//   Given "Ben" has "Intake" open on Latest in tab B and has opened its version list
//   When I restore v1 in tab A
//   And "Ben" opens the version list again
//   Then the list is fetched again and shows v3 "Restored v1" with my name
// Ben has experimental features here: the publishes list is theirs.
test('@S04', tags('S04'), async ({ page, browser }) => {
  setPreferences(BEN, { experimental_features: true });
  const wf = givenTwoPublishes();
  const ben = await benOpens(browser, wf);
  await openVersions(ben);
  expect(await listedNumbers(ben)).toEqual([2, 1]);
  await closeVersions(ben);

  await restoreV1(page, wf, 'Restored v1');

  await expect(async () => {
    await openVersions(ben);
    expect(await versionRowText(ben, 'v3')).toContain('Restored v1');
  }).toPass(EVENTUALLY);
  expect(await versionRowText(ben, 'v3')).toContain(nameOf(ME).full);
});

// @S05 @variant:experimental-features
// Scenario: A colleague reading an older version keeps seeing it
//   Given "Ben" is reading v2 of "Intake" in tab B
//   When I restore v1 in tab A
//   Then tab B still shows v2, including the step "Notify"
//   And "Ben"'s version list includes v3 when he opens it again
test('@S05', tags('S05'), async ({ page, browser }) => {
  setPreferences(BEN, { experimental_features: true });
  const wf = givenTwoPublishes();
  const ben = await benOpens(browser, wf, '?release=2');
  await expect(node(ben, 'Notify')).toBeVisible();

  await restoreV1(page, wf, 'Restored v1');
  await ben.waitForTimeout(QUIET);

  await expect(node(ben, 'Notify')).toBeVisible();
  expect(new URL(ben.url()).searchParams.get('release')).toBe('2');
  await expect(async () => {
    await openVersions(ben);
    expect(await listedNumbers(ben)).toContain(3);
  }).toPass(EVENTUALLY);
});

// @S06 @variant:experimental-features
// Scenario: A refused restore leaves colleagues' editors alone
//   Given "Ben" has "Intake" open on Latest in tab B
//   And someone else saves "Intake" while I restore v1
//   When I see "Could not restore v1"
//   Then tab B still shows the workflow as it was
// The save in between is the database skipping the restore's update of the
// workflow, which the restore reads as the workflow having moved on.
test('@S06', tags('S06'), async ({ page, browser }) => {
  const wf = givenTwoPublishes();
  const ben = await benOpens(browser, wf);
  await expect(node(ben, 'Notify')).toBeVisible();
  cleanups.push(workflowMovesOnUnderSaves(wf.id));

  await restoreV1(page, wf, 'Could not restore v1');
  await ben.waitForTimeout(QUIET);

  await expect(node(ben, 'Notify')).toBeVisible();
  await expect(unsavedMarker(ben)).toHaveCount(0);
});
