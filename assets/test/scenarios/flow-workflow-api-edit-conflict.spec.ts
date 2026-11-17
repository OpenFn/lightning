// Scenarios from annotations/flows/flow-workflow-api-edit-conflict.md: a
// workflow changed through the API while someone has it open in the editor.
//
// Who's who: "I" am the API client, holding owner@openfn.org's seeded API
// token (an owner may :edit_workflow, as the editor the annotation names
// may). super@openfn.org stands in for "amara@example.org", an editor with
// "Intake" open. Every project is seeded by the test and removed again
// afterwards, with its workflows. "Intake" is a webhook trigger leading to
// "Fetch", then "Load".
//
// The flow needs a Lightning API and a database, so the demo skips it.
import { expect, test, type Page } from '@playwright/test';

import {
  editorToasts,
  node,
  openEditor,
  renameStep,
  workflowTitle,
} from './pages/workflow-editor';
import {
  otherSession,
  patchWithBearer,
  putWithBearer,
  removeWorkflowData,
  seedEditorWorkflow,
  seededApiTokenOf,
  seedWorkspace,
  signInAs,
  storedWorkflow,
  type EditorWorkflow,
} from './steps';

const OWNER = 'owner@openfn.org';
const AMARA = 'super@openfn.org';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {
  S03: 'old: the reopened editor shows "Intake v2" but keeps the unsaved job rename "Fetch draft" (as shared-editor-session S04 on the canvas)',
};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old'],
});

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project "Malawi HIV" with Amara as an editor has workflow "Intake"
function givenIntake() {
  const w = seedWorkspace(
    { name: 'Malawi HIV', members: { [OWNER]: 'owner', [AMARA]: 'editor' } },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id('Malawi HIV');
  cleanups.push(() => removeWorkflowData(id));
  return seedEditorWorkflow(id, OWNER);
}

const apiPath = (wf: EditorWorkflow) =>
  `/api/projects/${wf.projectId}/workflows/${wf.id}`;

// Given "amara@example.org" has <wf> open in the editor, in a browser of her
// own
async function amaraOpens(page: Page, wf: EditorWorkflow) {
  await signInAs(page, AMARA);
  await openEditor(page, wf.projectId, wf.id);
}

const conflict = (wf: EditorWorkflow) => ({
  id: wf.id,
  errors: {
    workflow: [
      `Cannot save a workflow (${wf.name}) while it is being edited on the App UI`,
    ],
  },
});

// @S01
// Scenario Outline: An API update is refused while the workflow is open in the editor
//   Given "amara@example.org" has "Intake" open in the editor
//   And I hold an API token for an editor on the project
//   When I send a <method> to "/api/projects/<project_id>/workflows/<Intake id>" renaming it to "Intake v2"
//   Then the response status is 409
//   And the response body is {"id": "<Intake id>", "errors": {"workflow": ["Cannot save a workflow (Intake) while it is being edited on the App UI"]}}
//   And "Intake" is still named "Intake" with its lock version unchanged
//   And the open editor still shows "Intake" with no new message
//   Examples: PATCH, PUT
test('@S01', tags('S01'), async ({ page, request }) => {
  const wf = givenIntake();
  await amaraOpens(page, wf);
  const token = seededApiTokenOf(OWNER).token;
  const version = storedWorkflow(wf.id).lock_version;

  for (const [method, send] of [
    ['PATCH', patchWithBearer],
    ['PUT', putWithBearer],
  ] as const)
    await test.step(method, async () => {
      const res = await send(request, apiPath(wf), token, {
        name: 'Intake v2',
      });

      expect.soft(res.status(), method).toBe(409);
      expect.soft(await res.json(), method).toEqual(conflict(wf));
      expect.soft(storedWorkflow(wf.id), method).toMatchObject({
        name: 'Intake',
        lock_version: version,
      });
      await expect.soft(workflowTitle(page, 'Intake'), method).toBeVisible();
      await expect.soft(editorToasts(page), method).toHaveCount(0);
    });
});

// @S02
// Scenario: The lock lifts when the editor closes
//   Given "amara@example.org" had "Intake" open in the editor
//   And my PATCH renaming it to "Intake v2" was refused with 409
//   When "amara@example.org" closes the tab
//   And I send the same PATCH again
//   Then the response status is 200
//   And the response body's workflow is named "Intake v2"
// Her session ends a moment after the tab closes, so the PATCH is sent until
// it is answered with something other than the refusal.
test('@S02', tags('S02'), async ({ browser, request }) => {
  const wf = givenIntake();
  const amara = await otherSession(browser, AMARA);
  await openEditor(amara, wf.projectId, wf.id);
  const token = seededApiTokenOf(OWNER).token;
  const rename = () =>
    patchWithBearer(request, apiPath(wf), token, { name: 'Intake v2' });
  expect((await rename()).status()).toBe(409);

  await amara.close();

  let last = await rename();
  await expect
    .poll(async () => (last = await rename()).status(), EVENTUALLY)
    .not.toBe(409);
  expect(last.status()).toBe(200);
  expect((await last.json()).workflow.name).toBe('Intake v2');
});

// @S03
// Scenario: The next person to open the editor sees the API's change, not an old draft
//   Given "amara@example.org" renamed a job in "Intake" without saving and closed the tab
//   And I renamed "Intake" to "Intake v2" through the API
//   When "amara@example.org" opens "Intake" in the editor again
//   Then the editor shows "Intake v2"
//   And the unsaved job rename is gone
test('@S03', tags('S03'), async ({ browser, request }) => {
  const wf = givenIntake();
  const amara = await otherSession(browser, AMARA);
  await openEditor(amara, wf.projectId, wf.id);
  await renameStep(amara, 'Fetch', 'Fetch draft');
  // The shared copy is written to the database after a short pause
  await amara.waitForTimeout(3000);
  await amara.close();
  const token = seededApiTokenOf(OWNER).token;
  // Her session ends a moment after the tab closes (S02)
  await expect
    .poll(
      async () =>
        (
          await patchWithBearer(request, apiPath(wf), token, {
            name: 'Intake v2',
          })
        ).status(),
      EVENTUALLY
    )
    .toBe(200);

  const again = await otherSession(browser, AMARA);
  await openEditor(again, wf.projectId, wf.id);

  await expect(workflowTitle(again, 'Intake v2')).toBeVisible();
  await expect(node(again, 'Fetch draft')).toHaveCount(0);
  await expect(node(again, 'Fetch')).toBeVisible();
});
