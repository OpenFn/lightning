// Scenarios from annotations/flows/flow-delete-open-workflow.md: deleting a
// workflow from the workflows list while someone else has it open.
//
// Who's who: "I" am editor@openfn.org, deleting from the workflows list.
// super@openfn.org is the other member with the workflow open, in a browser
// of their own; owner@openfn.org owns the project, saves its workflows
// through Lightning and is the third member S03 needs. Every project is
// seeded by the test and removed again afterwards. "Intake" (and "Sync
// DHIS2") is a webhook trigger leading to "Fetch", then "Load".
//
// The AI assistant's channel is joined from a second connection of the other
// member, on a conversation seeded on the workflow: the channel's join needs
// no AI key, the panel does.
import { expect, test, type Page } from '@playwright/test';

import { settingsPath } from './pages/project-settings';
import {
  canvas,
  editorPath,
  node,
  openEditor,
  watchEditorSocket,
  workflowsListPath,
} from './pages/workflow-editor';
import {
  aiChannelAs,
  removeConversationsOf,
  seedConversations,
} from './pages/workflow-editor-ai-assistant';
import { deleteOnList, openWorkflowsList } from './pages/workflows-index';
import * as flashMessages from './shared/flash-messages';
import {
  healthPath,
  historyPath,
  open,
  otherSession,
  refuseDeletionOf,
  removeWorkflowData,
  seedEditorWorkflow,
  seedWorkspace,
  signInAs,
  storedWorkflow,
  type EditorWorkflow,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const OTHER = 'super@openfn.org';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old'],
});

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };
// How long an unaffected page is watched for a change that should not come
const QUIET = 3000;

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project "Malawi HIV", where the other member and I are editors, has
// workflow "Intake" (and <more>)
function givenProject(more: string[] = []) {
  const w = seedWorkspace(
    {
      name: 'Malawi HIV',
      members: { [OWNER]: 'owner', [ME]: 'editor', [OTHER]: 'editor' },
    },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id('Malawi HIV');
  cleanups.push(() => removeWorkflowData(id));
  cleanups.push(() => removeConversationsOf(id));
  const intake = seedEditorWorkflow(id, OWNER);
  const others = more.map(name => seedEditorWorkflow(id, OWNER, { name }));
  return { id, intake, others };
}

// When I delete "Intake" from the workflows list and confirm
async function deleteIntake(page: Page, projectId: string) {
  await signInAs(page, ME);
  await openWorkflowsList(page, projectId);
  await deleteOnList(page, 'Intake');
}

// Given the other member has the AI assistant open on <wf>: its channel,
// joined on a conversation about it
async function assistantOn(page: Page, wf: EditorWorkflow) {
  const [session] = seedConversations(wf.projectId, [
    { title: `What does ${wf.name} do?`, workflowId: wf.id, by: OTHER },
  ]);
  const channel = await aiChannelAs(page, session);
  cleanups.push(() => channel.close());
  expect(channel.joined.status).toBe('ok');
  return channel;
}

const pathOf = (page: Page) => new URL(page.url()).pathname;

// @S01
// Scenario Outline: A colleague with the workflow open is sent back to the list
//   Given project "Malawi HIV" has workflow "Intake"
//   And another member has "<page>" of "Intake" open
//   When I delete "Intake" from the workflows page and confirm
//   Then I see "Workflow successfully deleted."
//   And the other member's page follows shared-project-scope S12
//   Examples: the editor; the health page
// shared-project-scope S12: they are eventually on the project's workflows
// page and see "Workflow deleted."
test('@S01', tags('S01'), async ({ page, browser }) => {
  const examples = [
    ['the editor', editorPath],
    ['the health page', healthPath],
  ] as const;
  for (const [where, pathTo] of examples)
    await test.step(where, async () => {
      const { id, intake } = givenProject();
      const other = await otherSession(browser, OTHER);
      await open(other, pathTo(id, intake.id));

      await deleteIntake(page, id);

      await expect
        .soft(flashMessages.toast(page, 'Workflow successfully deleted.'))
        .toBeVisible();
      await expect
        .soft(() => expect(pathOf(other)).toBe(workflowsListPath(id)))
        .toPass(EVENTUALLY);
      await expect
        .soft(flashMessages.toast(other, 'Workflow deleted.'))
        .toBeVisible();
      await other.context().close();
    });
});

// @S02
// Scenario: The open editor's collaboration and AI assistant sessions end
//   Given another member has the collaborative editor and the AI assistant open on "Intake"
//   When I delete "Intake"
//   Then their editor channel for "Intake" closes
//   And their AI assistant channel for "Intake" closes
test('@S02', tags('S02'), async ({ page, browser }) => {
  const { id, intake } = givenProject();
  const other = await otherSession(browser, OTHER);
  const sock = await watchEditorSocket(other);
  await openEditor(other, id, intake.id);
  const assistant = await assistantOn(other, intake);

  await deleteIntake(page, id);

  await expect
    .poll(() => sock.pushed('phx_close').length, EVENTUALLY)
    .toBeGreaterThan(0);
  await expect.poll(() => assistant.closed(), EVENTUALLY).toBe(true);
});

// @S03
// Scenario: People on other workflows and other project pages are not interrupted
//   Given another member has workflow "Sync DHIS2" open in the editor, with its editor and AI assistant channels joined
//   And a third member has the project's workflows, settings and history pages open
//   When I delete "Intake"
//   Then all of those pages stay where they are
//   And those channels stay joined
test('@S03', tags('S03'), async ({ page, browser }) => {
  const {
    id,
    others: [sync],
  } = givenProject(['Sync DHIS2']);
  const other = await otherSession(browser, OTHER);
  const sock = await watchEditorSocket(other);
  await openEditor(other, id, sync.id);
  const assistant = await assistantOn(other, sync);
  const third = await otherSession(browser, OWNER);
  const pages: [Page, string][] = [
    [third, workflowsListPath(id)],
    [await third.context().newPage(), settingsPath(id)],
    [await third.context().newPage(), historyPath(id)],
  ];
  for (const [p, path] of pages) await open(p, path);

  await deleteIntake(page, id);
  await expect(
    flashMessages.toast(page, 'Workflow successfully deleted.')
  ).toBeVisible();
  await page.waitForTimeout(QUIET);

  for (const [p, path] of pages) expect.soft(pathOf(p), path).toBe(path);
  expect.soft(pathOf(other)).toBe(editorPath(id, sync.id));
  await expect.soft(canvas(other)).toBeVisible();
  expect.soft(sock.pushed('phx_close')).toHaveLength(0);
  expect.soft(assistant.closed()).toBe(false);
});

// @S04
// Scenario: Nobody is sent away when the delete fails
//   Given another member has "Intake" open in the editor
//   When deleting "Intake" fails in the database
//   Then no WorkflowDeleted is broadcast
//   And their editor stays open
// The database refuses the update that marks "Intake" deleted. No broadcast
// is read off their editor channel: it is not closed.
test('@S04', tags('S04'), async ({ page, browser }) => {
  const { id, intake } = givenProject();
  cleanups.push(refuseDeletionOf(intake.id));
  const other = await otherSession(browser, OTHER);
  const sock = await watchEditorSocket(other);
  await openEditor(other, id, intake.id);

  await deleteIntake(page, id);
  await page.waitForTimeout(QUIET);

  expect(storedWorkflow(intake.id).deleted).toBe(false);
  await expect(
    flashMessages.toast(page, 'Workflow successfully deleted.')
  ).toHaveCount(0);
  expect(sock.pushed('phx_close')).toHaveLength(0);
  expect(pathOf(other)).toBe(editorPath(id, intake.id));
  await expect(node(other, 'Fetch')).toBeVisible();
});
