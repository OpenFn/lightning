// Scenarios from annotations/flows/flow-ai-session-collaborators.md: an AI
// assistant conversation that two people on one workflow both have open.
//
// Who's who: "I" am editor@openfn.org; super@openfn.org is "Amara", the
// colleague who asks. Both are editors on "Malawi HIV" and have "Intake"
// open in browsers of their own. owner@openfn.org owns the project and saves
// its workflow through Lightning. Every project is seeded by the test and
// removed again afterwards, with its conversations. "Intake" is a webhook
// trigger leading to "Fetch", then "Load".
//
// The assistant needs Lightning started with AI_ASSISTANT_API_KEY set (see
// workflow-editor-ai-assistant.spec.ts); without it these skip. Apollo is
// the stand-in from pages/workflow-editor-ai-assistant.ts, on one port, so
// every test is @serial. S05's lock is the two events Amara's browser sends
// around an apply, sent from her page's own socket; that half needs no key.
import { expect, test, type Browser, type Page } from '@playwright/test';

import {
  headerTooltip,
  node,
  openEditor,
  renameStep,
  saveButton,
  unsavedMarker,
  watchEditorSocket,
} from './pages/workflow-editor';
import {
  addStep,
  answer,
  ask,
  assistantOnInstance,
  choosePanelMenu,
  chunk,
  done,
  edited,
  gate,
  listedConversations,
  messageBox,
  NEEDS_KEY,
  openWithPanel,
  panel,
  removeConversationsOf,
  replies,
  repliesSettled,
  revertButton,
  seedConversations,
  sentBy,
  standInApollo,
  thinking,
  tryAgainButton,
} from './pages/workflow-editor-ai-assistant';
import {
  nameOf,
  otherSession,
  removeWorkflowData,
  seedEditorWorkflow,
  seedWorkspace,
  sharedDocOf,
  signInAs,
  storedWorkflow,
  type EditorWorkflow,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const AMARA = 'super@openfn.org';

// Scenarios that don't pass on the old app, and why; the rest pass there
const UNRUN =
  'not run yet: the e2e instance was started without AI_ASSISTANT_API_KEY';
const STILL_PENDING: Record<string, string> = {
  S01: UNRUN,
  S02: UNRUN,
  S03: UNRUN,
  S04: UNRUN,
  S06: UNRUN,
};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old', '@serial'],
});

// A reply goes through a background job and a stream, so it gets this long
const EVENTUALLY = { timeout: 20000 };

const QUESTION = 'Add a step that posts to DHIS2';
const SEND = 'Post to DHIS2';

const needsAssistant = () =>
  test.skip(!assistantOnInstance().enabled, NEEDS_KEY);

let cleanups: (() => unknown)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(async () => {
  for (const cleanup of cleanups.reverse()) await cleanup();
});

// Given the assistant answers through the stand-in Apollo, until the test ends
async function givenApollo() {
  needsAssistant();
  const apollo = await standInApollo();
  cleanups.push(() => apollo.stop());
  return apollo;
}

// Given project "Malawi HIV", where Amara and I are editors, has "Intake"
function givenIntake() {
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
  cleanups.push(() => removeConversationsOf(id));
  return seedEditorWorkflow(id, OWNER);
}

// Given a conversation on <wf> that Amara started — returns its id
const givenConversation = (wf: EditorWorkflow) =>
  seedConversations(wf.projectId, [
    { title: 'What does Intake do?', workflowId: wf.id, by: AMARA },
  ])[0];

// Given <page> (mine) and Amara's own browser have <wf> open with the
// assistant panel, on conversation <chat> if given
async function bothOpen(
  page: Page,
  browser: Browser,
  wf: EditorWorkflow,
  chat?: string
) {
  const query: Record<string, string> = chat ? { 'w-chat': chat } : {};
  await signInAs(page, ME);
  await openWithPanel(page, wf.projectId, wf.id, query);
  const amara = await otherSession(browser, AMARA);
  await openWithPanel(amara, wf.projectId, wf.id, query);
  return amara;
}

// @S01
// Scenario: A colleague's new conversation appears in my list
//   Given "Amara" and I both have workflow "Intake" open
//   And I have the assistant's conversation list open on "Intake"
//   When "Amara" starts a conversation with "Add a step that posts to DHIS2"
//   Then "Add a step that posts to DHIS2" appears at the top of my list without a reload
//   And the conversation count goes up by one
test('@S01', tags('S01'), async ({ page, browser }) => {
  const apollo = await givenApollo();
  apollo.always(answer('Here is how.'));
  const wf = givenIntake();
  givenConversation(wf);
  const amara = await bothOpen(page, browser, wf);
  await choosePanelMenu(page, 'Conversations');
  const before = (await listedConversations(page)).length;

  await ask(amara, QUESTION);

  await expect
    .poll(async () => (await listedConversations(page))[0], EVENTUALLY)
    .toBe(QUESTION);
  expect(await listedConversations(page)).toHaveLength(before + 1);
});

// @S02
// Scenario: Everyone in the conversation sees the question, who asked it, and the reply as it streams
//   Given "Amara" and I are both in the same conversation on "Intake"
//   When "Amara" asks "Add a step that posts to DHIS2"
//   Then I see her message with "Sent by Amara"
//   And I see the assistant's status and reply text appear as they arrive
//   And once complete the reply is the same one "Amara" sees
// The reply is held after its first words, so they are seen before the end.
test('@S02', tags('S02'), async ({ page, browser }) => {
  const apollo = await givenApollo();
  const held = gate();
  const text = 'Add a step after Load that posts to DHIS2.';
  apollo.replyWith([
    thinking,
    chunk('Add a step after Load'),
    held.step,
    chunk(' that posts to DHIS2.'),
    done(text),
  ]);
  const wf = givenIntake();
  const chat = givenConversation(wf);
  const amara = await bothOpen(page, browser, wf, chat);

  await ask(amara, QUESTION);

  await expect(sentBy(page, nameOf(AMARA).full)).toBeVisible(EVENTUALLY);
  await expect(panel(page)).toContainText('Add a step after Load', EVENTUALLY);
  await expect(replies(page).filter({ hasText: text })).toHaveCount(0);
  held.open();
  await repliesSettled(page, 2);
  await repliesSettled(amara, 2);
  expect(await replies(page).last().innerText()).toBe(
    await replies(amara).last().innerText()
  );
  await expect(replies(page).last()).toContainText(text);
});

// @S03
// Scenario: Nobody can send while a colleague's question is being answered
//   Given "Amara" and I are in the same conversation on "Intake"
//   When "Amara"'s question starts being answered
//   Then my message box is disabled until the reply is in or fails
//   And if I open the conversation while it is still being answered, my message box is disabled too
test('@S03', tags('S03'), async ({ page, browser }) => {
  const apollo = await givenApollo();
  const held = gate();
  apollo.replyWith([thinking, held.step, ...answer('Done.')]);
  const wf = givenIntake();
  const chat = givenConversation(wf);
  const amara = await bothOpen(page, browser, wf, chat);

  await ask(amara, QUESTION);

  await expect(messageBox(page)).toBeDisabled(EVENTUALLY);
  const later = await page.context().newPage();
  await openWithPanel(later, wf.projectId, wf.id, { 'w-chat': chat });
  await expect(messageBox(later)).toBeDisabled(EVENTUALLY);
  held.open();
  await expect(messageBox(page)).toBeEnabled(EVENTUALLY);
  await expect(messageBox(later)).toBeEnabled(EVENTUALLY);
});

// @S04
// Scenario: Only the asker's browser applies the reply, and colleagues see it on their canvas
//   Given "Amara", an editor, and I, an editor, are in the same conversation on "Intake"
//   When "Amara" asks for a new step "Post to DHIS2" and the reply changes the workflow
//   Then my browser does not import the reply
//   And "Post to DHIS2" appears on my canvas through the shared workflow
//   And my "Save" shows unsaved changes (shared-editor-session)
// Had my browser imported the reply too, the shared workflow would hold the
// step twice.
test('@S04', tags('S04'), async ({ page, browser }) => {
  const apollo = await givenApollo();
  apollo.replyWith(req =>
    answer(`I added "${SEND}" after Load.`, {
      yaml: edited(req, addStep(SEND, 'Load')),
    })
  );
  const wf = givenIntake();
  const chat = givenConversation(wf);
  const amara = await bothOpen(page, browser, wf, chat);

  await ask(amara, QUESTION);

  await expect(node(page, SEND)).toBeVisible(EVENTUALLY);
  await expect(unsavedMarker(page)).toBeVisible();
  await repliesSettled(page, 2);
  await page.waitForTimeout(2000);
  expect(sharedDocOf(wf.id)?.steps.filter(s => s === SEND)).toHaveLength(1);
  expect(storedWorkflow(wf.id).steps).not.toContain(SEND);
});

// @S05
// Scenario: While anyone applies AI changes, collaborators cannot save or revert
//   Given "Amara" and I have "Intake" open, and I am an editor
//   When "Amara"'s browser starts applying the assistant's changes
//   Then my "Save" is disabled and hovering it shows "Applying AI-generated workflow..."
//   And "Revert changes" and the "Try again" on a failed apply are unavailable in my panel
//   When her apply finishes
//   Then my "Save" is enabled again
// The apply is the two events her browser sends around it. My panel is
// checked only where the instance has the assistant: there her earlier reply
// changed the workflow, so it offers "Revert changes".
test('@S05', tags('S05'), async ({ page, browser }) => {
  const withPanel = assistantOnInstance().enabled;
  const wf = givenIntake();
  const chat = givenConversation(wf);
  if (withPanel) {
    const apollo = await givenApollo();
    apollo.replyWith(req =>
      answer(`I added "${SEND}".`, { yaml: edited(req, addStep(SEND, 'Load')) })
    );
  }
  const open = (p: Page) =>
    withPanel
      ? openWithPanel(p, wf.projectId, wf.id, { 'w-chat': chat })
      : openEditor(p, wf.projectId, wf.id);
  const amara = await otherSession(browser, AMARA);
  const sock = await watchEditorSocket(amara);
  await open(amara);
  await signInAs(page, ME);
  await open(page);
  if (withPanel) {
    await ask(amara, QUESTION);
    await repliesSettled(page, 2);
  }
  // A change of my own, so Save is otherwise on
  await renameStep(page, 'Fetch', 'Fetch patients');
  await expect(saveButton(page)).toBeEnabled();

  await sock.push('start_applying_workflow', { message_id: 'scenario-apply' });

  await expect(saveButton(page)).toBeDisabled(EVENTUALLY);
  expect(await headerTooltip(page, saveButton(page).locator('xpath=..'))).toBe(
    'Applying AI-generated workflow...'
  );
  if (withPanel) {
    await expect(revertButton(page)).toBeDisabled();
    if (await tryAgainButton(page).count())
      await expect(tryAgainButton(page)).toBeDisabled();
  } else {
    test.info().annotations.push({
      type: 'skipped half',
      description: `my panel's Revert and Try again: ${NEEDS_KEY}`,
    });
  }

  await sock.push('done_applying_workflow', { message_id: 'scenario-apply' });

  await expect(saveButton(page)).toBeEnabled(EVENTUALLY);
});

// @S06
// Scenario: A failed reply, and its retry, are seen by everyone in the conversation
//   Given "Amara" and I are in the same conversation and her question fails
//   Then I see the failure and "Try again" on her question
//   When "Amara" clicks "Try again"
//   Then "Try again" disappears for me as well
// The first reply's stream is cut; the retry is answered.
test('@S06', tags('S06'), async ({ page, browser }) => {
  const apollo = await givenApollo();
  apollo.replyWith(['cut'], answer('Here is how.'));
  const wf = givenIntake();
  const chat = givenConversation(wf);
  const amara = await bothOpen(page, browser, wf, chat);

  await ask(amara, QUESTION);

  await expect(tryAgainButton(page)).toBeVisible(EVENTUALLY);
  await expect(panel(page)).toContainText(
    'The connection to the assistant was lost.'
  );
  await tryAgainButton(amara).click();

  await expect(tryAgainButton(page)).toHaveCount(0, EVENTUALLY);
});
