// Scenarios from annotations/flows/flow-toggle-workflow-open-editor.md: a
// workflow switched on or off from the workflows list while someone has it
// open in the editor.
//
// Who's who: "I" am editor@openfn.org, on the workflows list.
// super@openfn.org stands in for "amara@example.org", an editor with the
// workflow open in a browser of her own, without experimental features (with
// them the editor shows a lifecycle badge instead of the switch).
// owner@openfn.org owns the project and saves its workflows through
// Lightning. Every project is seeded by the test and removed again
// afterwards. "Intake" is a webhook trigger leading to "Fetch", then "Load".
import { expect, test, type Browser } from '@playwright/test';

import {
  editorToast,
  node,
  openEditor,
  readOnlyPill,
  renameStep,
  saveButton,
  triggersEnabledIn,
  versionQuery,
  watchEditorSocket,
  workflowSwitch,
} from './pages/workflow-editor';
import { openWorkflowsList, switchOnList } from './pages/workflows-index';
import * as flashMessages from './shared/flash-messages';
import {
  goLiveOnNode,
  keepAccount,
  otherSession,
  removeWorkflowData,
  renameStepOnNode,
  seedEditorWorkflow,
  seedWorkspace,
  setPreferences,
  signInAs,
  storedWorkflow,
  withRefusingLimiter,
  type EditorWorkflowSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const AMARA = 'super@openfn.org';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {};
const tags = (key: string, serial = false) => ({
  tag: [
    key in STILL_PENDING ? '@pending' : '@passing-old',
    ...(serial ? ['@serial'] : []),
  ],
});

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(AMARA)];
  setPreferences(AMARA, { experimental_features: false });
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project "Malawi HIV", where Amara and I are editors, has workflow
// "Intake" (or <seed>'s)
function givenIntake(seed: EditorWorkflowSeed = {}) {
  const w = seedWorkspace(
    {
      name: 'Malawi HIV',
      members: { [OWNER]: 'owner', [ME]: 'editor', [AMARA]: 'editor' },
    },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id('Malawi HIV');
  cleanups.push(() => removeWorkflowData(id));
  return seedEditorWorkflow(id, OWNER, seed);
}

// Given Amara has <wf> open in the editor (with <query>), in a second browser
async function amaraOpens(
  browser: Browser,
  wf: { projectId: string; id: string },
  query = ''
) {
  const amara = await otherSession(browser, AMARA);
  await openEditor(amara, wf.projectId, wf.id, query);
  return amara;
}

// @S01
// Scenario Outline: A switch on the list shows in an open editor
//   Given "Intake" has its webhook trigger <before>
//   And "amara@example.org" has "Intake" open in the editor in a second tab
//   When I click the "Intake" switch on the workflows list
//   Then I see "Workflow updated"
//   And eventually the second tab's workflow switch is <after>
//   Examples: enabled -> off; disabled -> on
test('@S01', tags('S01'), async ({ page, browser }) => {
  await signInAs(page, ME);
  for (const enabled of [true, false])
    await test.step(`trigger ${enabled ? 'enabled' : 'disabled'}`, async () => {
      const wf = givenIntake({ enabled });
      const amara = await amaraOpens(browser, wf);
      const before = expect.soft(workflowSwitch(amara));
      await (enabled ? before.toBeChecked() : before.not.toBeChecked());
      await openWorkflowsList(page, wf.projectId);

      await switchOnList(page, 'Intake');

      await expect
        .soft(flashMessages.toast(page, 'Workflow updated'))
        .toBeVisible();
      const after = expect.soft(workflowSwitch(amara));
      await (enabled
        ? after.not.toBeChecked(EVENTUALLY)
        : after.toBeChecked(EVENTUALLY));
      await amara.context().close();
    });
});

// @S02
// Scenario: Saving from the open editor does not undo a switch made on the list
//   Given "Intake" is live with its webhook trigger enabled
//   And "amara@example.org" has "Intake" open in the editor
//   When I switch "Intake" off on the workflows list
//   And "amara@example.org" renames a job and saves
//   Then "Intake" still has its trigger disabled
test('@S02', tags('S02'), async ({ page, browser }) => {
  const wf = givenIntake({ enabled: true });
  goLiveOnNode(wf.id, OWNER);
  const amara = await amaraOpens(browser, wf);
  await signInAs(page, ME);
  await openWorkflowsList(page, wf.projectId);

  await switchOnList(page, 'Intake');
  await expect(flashMessages.toast(page, 'Workflow updated')).toBeVisible();
  await expect(workflowSwitch(amara)).not.toBeChecked(EVENTUALLY);
  await renameStep(amara, 'Fetch', 'Fetch patients');
  await saveButton(amara).click();
  await expect(editorToast(amara, 'Workflow saved')).toBeVisible();

  const stored = storedWorkflow(wf.id);
  expect(stored.steps).toContain('Fetch patients');
  expect(stored.triggers_enabled).toEqual([false]);
});

// @S03
// Scenario: A version view is not changed by a switch on the list
//   Given "amara@example.org" is viewing version 3 of "Intake" in the editor
//   When I switch "Intake" off on the workflows list
//   Then the version 3 view still shows its trigger as it was in version 3
// The version she reads is the one saved before a later rename, trigger on.
// A version view draws no switch, so the trigger is read from the copy of the
// workflow the server sent her page.
test('@S03', tags('S03'), async ({ page, browser }) => {
  const wf = givenIntake({ enabled: true });
  const older = storedWorkflow(wf.id).lock_version;
  renameStepOnNode(wf.id, 'Load', 'Load v2', OWNER);
  const amara = await otherSession(browser, AMARA);
  const sock = await watchEditorSocket(amara);
  await openEditor(amara, wf.projectId, wf.id, versionQuery(older));
  await expect(readOnlyPill(amara)).toBeVisible();
  await expect.poll(() => triggersEnabledIn(sock.doc)).toEqual([true]);
  await signInAs(page, ME);
  await openWorkflowsList(page, wf.projectId);

  await switchOnList(page, 'Intake');
  await expect(flashMessages.toast(page, 'Workflow updated')).toBeVisible();
  expect(storedWorkflow(wf.id).triggers_enabled).toEqual([false]);

  // Give the switch time to reach the open editor, as it does on Latest (S01)
  await amara.waitForTimeout(3000);
  expect(triggersEnabledIn(sock.doc)).toEqual([true]);
  await expect(node(amara, 'Load')).toBeVisible();
});

// @S04 @variant:activation-limited
// Scenario: A switch refused by the plan limit does not reach the open editor
//   Given the usage limiter refuses workflow activation with "No more workflows"
//   And "Intake" has its trigger disabled
//   And "amara@example.org" has "Intake" open in the editor
//   When I click the "Intake" switch on the workflows list
//   Then I see "No more workflows"
//   And the editor's workflow switch stays off
// The limiter is instance-wide, so this runs alone.
test('@S04', tags('S04', true), async ({ page, browser }) => {
  cleanups.push(withRefusingLimiter('No more workflows'));
  const wf = givenIntake({ enabled: false });
  const amara = await amaraOpens(browser, wf);
  await expect(workflowSwitch(amara)).not.toBeChecked();
  await signInAs(page, ME);
  await openWorkflowsList(page, wf.projectId);

  await switchOnList(page, 'Intake');

  await expect(flashMessages.toast(page, 'No more workflows')).toBeVisible();
  expect(storedWorkflow(wf.id).triggers_enabled).toEqual([false]);
  await amara.waitForTimeout(3000);
  await expect(workflowSwitch(amara)).not.toBeChecked();
});
