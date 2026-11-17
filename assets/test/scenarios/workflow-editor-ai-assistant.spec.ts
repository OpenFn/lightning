// Scenarios from annotations/views/workflow-editor-ai-assistant.md, and the
// shared-workflow-yaml-format scenario the assistant's apply hosts (S11).
//
// Who's who: "I" (and "Ben") is editor@openfn.org; each test gives me the
// role its Given names. owner@openfn.org owns every project and saves its
// workflows through Lightning; super@openfn.org stands in for "Amara", the
// collaborator a test needs. Every project ("Malawi HIV", "Malawi TB") is
// seeded by the test and removed again afterwards, with its workflows and its
// conversations. "Intake" is a webhook trigger leading to "Fetch", then
// "Load", unless a test says otherwise.
//
// The editor is not being ported: these record what today's assistant panel
// does, through pages/workflow-editor-ai-assistant.ts, so a rebuild that
// keeps the Value passes.
//
// The assistant needs Lightning started with AI_ASSISTANT_API_KEY=<anything>
// (and APOLLO_ENDPOINT, if not the dev default http://localhost:3000). Without
// it every test but S01 skips. Stand-ins:
// - Apollo: the test starts a stand-in on the endpoint's port and sets each
//   reply (text, a workflow, a failed code edit, a dropped stream, a held
//   one). One process can hold the port, so those tests are @serial.
// - The assistant's channel is joined from a second connection signed in as
//   the same person where the page would not send the frame (a viewer's
//   context update, another project's run) or is torn down by the change
//   under test (S13, S23, S25, S28 to S30).
// - Conversations, including a stuck one (S18) and a quota (S19, S20), are
//   seeded on the node; S11 replaces a failed reply's workflow in the
//   database so its retry can succeed.
//
// shared-authenticated-session, shared-project-scope,
// shared-usage-limits-banner, shared-editor-session and shared-flash-messages
// belong to the route /projects/:id/w/:id and run on it once, in
// workflow-editor-canvas.spec.ts. The assistant's channel authorises its own
// join, so who may join it is here (S23, S28 to S30).
import { expect, test, type Page } from '@playwright/test';

import {
  clickEmptyCanvas,
  confirmDialog,
  editorQuery,
  editorToast,
  headerTooltip,
  node,
  openEditor,
  renameStep,
  saveButton,
  unsavedMarker,
} from './pages/workflow-editor';
import {
  aiButton,
  aiButtonTip,
  aiChannelAs,
  aboutDialog,
  addStep,
  answer,
  ask,
  assistantOnInstance,
  buildWithAi,
  changedStep,
  chatInUrl,
  choosePanelMenu,
  chunk,
  conversationItem,
  conversationsOf,
  credentialOfJob,
  done,
  dropBody,
  edited,
  gate,
  listConversationsOverHttp,
  listedConversations,
  loadMoreButton,
  messageBox,
  messageBoxTip,
  messagesOf,
  NEEDS_KEY,
  newConversationParams,
  newWorkflowFile,
  openPanelMenu,
  openStepButton,
  openWithPanel,
  panel,
  reasonOf,
  removeConversationsOf,
  replaceReplyWorkflow,
  replies,
  repliesSettled,
  requireMfa,
  restoreButton,
  revertButton,
  runStuckMessageSweep,
  searchConversations,
  seedConversations,
  sendButton,
  sentMessages,
  setBody,
  standInApollo,
  switchToVersion,
  thinking,
  withoutAssistant,
  type AiChannel,
  type ConversationSeed,
} from './pages/workflow-editor-ai-assistant';
import {
  closeIdeButton,
  ideReady,
  jobSelector,
  openIde,
} from './pages/workflow-editor-ide';
import { shown } from './pages/workflow-editor-versions-and-promote';
import * as adaptorConfig from './shared/adaptor-credential-config';
import * as yamlFormat from './shared/workflow-yaml-format';
import {
  changeRoleOnNode,
  deleteWorkflowOnNode,
  goLiveOnNode,
  keepAccount,
  makeSupportUser,
  nameOf,
  obanJobsNaming,
  reload,
  removeMemberOnNode,
  removeWorkflowData,
  renameStepOnNode,
  scheduleDeletionOnNode,
  seedCredential,
  seedEditorWorkflow,
  seedRun,
  seedWorkspace,
  setPreferences,
  setSupportAccessOnNode,
  signInAs,
  storedWorkflow,
  withLimiterRefusing,
  workflowsOf,
  type EditorWorkflow,
  type EditorWorkflowSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PENDING_SERIAL = { tag: ['@pending', '@serial'] };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING_OLD_SERIAL = { tag: ['@passing-old', '@serial'] };

// A page that has to react to something done elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

const SEND = 'Send to DHIS2';
const DHIS2 = '@openfn/language-dhis2@latest';
const MESSAGE_PROCESSOR = 'Lightning.AiAssistant.MessageProcessor';

let cleanups: (() => unknown)[] = [];
test.beforeEach(() => {
  // Some tests change my preferences or my support flag
  cleanups = [keepAccount(ME)];
});
test.afterEach(async () => {
  for (const cleanup of cleanups.reverse()) await cleanup();
});

// Given the instance has the assistant configured
function needsAssistant() {
  test.skip(!assistantOnInstance().enabled, NEEDS_KEY);
}

// Given the assistant answers through the stand-in Apollo, until the test ends
async function givenApollo() {
  needsAssistant();
  const apollo = await standInApollo();
  cleanups.push(() => apollo.stop());
  return apollo;
}

// Given project <name> exists with these members (owner@openfn.org owns it)
// — removed after the test with its workflows and conversations
function givenProject(
  members: Record<string, Role> = { [ME]: 'editor' },
  { name = 'Malawi HIV', ...rest }: Partial<WorkspaceSeed> = {}
) {
  const owned = { ...members, [OWNER]: 'owner' as const };
  const w = seedWorkspace({ name, members: owned, ...rest }, OWNER);
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  cleanups.push(() => removeConversationsOf(id));
  return { id, w, by: OWNER };
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
  return { ...p, wf };
}

// When I sign in as <email> and open <wf> with the assistant panel open
async function openAs(
  page: Page,
  wf: EditorWorkflow,
  {
    email = ME,
    query = {},
  }: { email?: string; query?: Record<string, string> } = {}
) {
  await signInAs(page, email);
  await openWithPanel(page, wf.projectId, wf.id, query);
}

// Given conversation <title> on <wf>, started by <by> — resolves to its id
const givenConversation = (
  wf: EditorWorkflow,
  title: string,
  by = OWNER,
  rest: Partial<ConversationSeed> = {}
) =>
  seedConversations(wf.projectId, [
    { title, workflowId: wf.id, by, ...rest },
  ])[0];

// When I join conversation <sessionId> from a second connection — closed
// again after the test
async function channelAs(
  page: Page,
  sessionId: string,
  params: Record<string, unknown> = {}
) {
  const channel = await aiChannelAs(page, sessionId, params);
  cleanups.push(() => channel.close());
  return channel;
}

// Then the server has closed <channel>, and joining again is refused
async function expectShut(page: Page, channel: AiChannel, sessionId: string) {
  await expect.poll(() => channel.closed(), EVENTUALLY).toBe(true);
  const again = await channelAs(page, sessionId);
  expect(again.joined.status).toBe('error');
  expect(reasonOf(again.joined)).toBe('unauthorized');
}

// When I save the workflow
async function saveWorkflow(page: Page) {
  await saveButton(page).click();
  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
}

// ---------------------------------------------------------------------------
// Open the assistant
// ---------------------------------------------------------------------------

// @S01
// Scenario: Without the assistant configured, the AI button says why it is off
//   Given the instance has no Apollo endpoint or key
//   And I have workflow "Intake" open
//   Then the AI button in the header is disabled
//   And hovering it shows "Your instance does not have build-time AI enabled. Contact your administrator or support@openfn.org to configure it."
//   And Cmd/Ctrl+K does nothing
// The key is taken off the running instance for this test, so it runs alone.
test('@S01', PASSING_OLD_SERIAL, async ({ page }) => {
  cleanups.push(withoutAssistant());
  const { wf } = givenIntake();
  await signInAs(page, ME);
  await openEditor(page, wf.projectId, wf.id);

  await expect(aiButton(page)).toBeDisabled();
  expect(await aiButtonTip(page)).toContain(
    'Your instance does not have build-time AI enabled. Contact your administrator or support@openfn.org to configure it.'
  );
  await clickEmptyCanvas(page);
  await page.keyboard.press('ControlOrMeta+k');
  await page.waitForTimeout(500);
  await expect(panel(page)).toHaveCount(0);
  expect(editorQuery(page).chat).toBeUndefined();
});

// @S02
// Scenario: Members open and close the assistant without leaving the workflow
//   Given I have workflow "Intake" open
//   When I click the AI button
//   Then the "Assistant" panel opens and the URL has "chat=true"
//   And hovering the button shows "Close AI Assistant" with the Cmd/Ctrl+K shortcut
//   When I press Cmd/Ctrl+K
//   Then the panel closes and "chat", "w-chat" and "j-chat" leave the URL
//   When I open "/projects/<id>/w/<Intake id>?chat=true"
//   Then the panel is open on load
test('@S02', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { wf } = givenIntake();
  await signInAs(page, ME);
  await openEditor(page, wf.projectId, wf.id);

  await aiButton(page).click();

  await expect(panel(page)).toBeVisible();
  await expect(
    panel(page).getByRole('heading', { name: 'Assistant', exact: true })
  ).toBeVisible();
  await expect.poll(() => editorQuery(page).chat).toBe('true');
  const tip = await aiButtonTip(page);
  expect(tip).toContain('Close AI Assistant');
  expect(tip).toMatch(/K/);

  await clickEmptyCanvas(page);
  await page.keyboard.press('ControlOrMeta+k');

  await expect(panel(page)).toHaveCount(0);
  await expect.poll(() => editorQuery(page).chat).toBeUndefined();
  const query = editorQuery(page);
  for (const param of ['chat', 'w-chat', 'j-chat'])
    expect(query[param]).toBeUndefined();

  await openWithPanel(page, wf.projectId, wf.id);
});

// @S03
// Scenario: The assistant is not available on an older version
//   Given I have workflow "Intake" open with the assistant panel open
//   When I switch to version 3 of "Intake"
//   Then the panel closes and its conversation is cleared from the URL
//   And the AI button is disabled with "Switch to the latest version of this workflow to use the AI Assistant."
// "Version 3" is the version before a later save.
test('@S03', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { wf, by } = givenIntake();
  const pinned = storedWorkflow(wf.id).lock_version;
  renameStepOnNode(wf.id, 'Load', 'Load v2', by);
  const session = givenConversation(wf, 'What does Intake do?');
  await openAs(page, wf, { query: { 'w-chat': session } });

  await switchToVersion(page, pinned);

  await expect(panel(page)).toHaveCount(0, EVENTUALLY);
  await expect.poll(() => editorQuery(page).chat).toBeUndefined();
  expect(chatInUrl(page)).toBeNull();
  await expect(aiButton(page)).toBeDisabled();
  expect(await aiButtonTip(page)).toContain(
    'Switch to the latest version of this workflow to use the AI Assistant.'
  );
});

// @S31
// Scenario: Members can read what the assistant sends and keeps before they use it
//   Given I have the assistant open
//   Then under the message box I see "Please use AI responsibly. Never share PII." with "Learn more."
//   When I choose "About the AI Assistant" from the menu
//   Then I see that messages are saved unencrypted, kept by Anthropic up to 30 days, not used for training, and shared with project collaborators
//   And the menu links to "Responsible AI Policy"
test('@S31', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { wf } = givenIntake();
  await openAs(page, wf);

  await expect(
    panel(page).getByText('Please use AI responsibly. Never share PII.')
  ).toBeVisible();
  await expect(
    panel(page).getByRole('link', { name: 'Learn more.' })
  ).toBeVisible();

  await choosePanelMenu(page, 'About the AI Assistant');

  const about = aboutDialog(page);
  await expect(about).toBeVisible();
  await expect(about).toContainText(/saved unencrypted/);
  await expect(about).toContainText(/Anthropic[^.]*up to 30 days/);
  await expect(about).toContainText(/not used to train/);
  await expect(about).toContainText(/shared with project collaborators/);
  await about.getByRole('button', { name: 'Close' }).click();

  await openPanelMenu(page);
  await expect(
    panel(page).getByRole('link', { name: 'Responsible AI Policy' })
  ).toHaveAttribute('href', /openfn\.org\/ai/);
});

// ---------------------------------------------------------------------------
// Ask and get answers
// ---------------------------------------------------------------------------

// @S04
// Scenario: A first message starts a conversation
//   Given I am an editor with "Intake" open and the panel showing "No conversations yet"
//   When I type "Add a step that posts to DHIS2" and press Enter
//   Then a conversation titled "Add a step that posts to DHIS2" is created
//   And my message shows "Sent by <my name>"
//   And the URL has "w-chat=<conversation id>"
// The reply itself is not looked at: no stand-in answers it here.
test('@S04', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { id, wf } = givenIntake();
  await openAs(page, wf);
  await expect(panel(page).getByText('No conversations yet')).toBeVisible();

  await ask(page, 'Add a step that posts to DHIS2');

  await expect.poll(() => conversationsOf(id).length, EVENTUALLY).toBe(1);
  const [conversation] = conversationsOf(id);
  expect(conversation.title).toBe('Add a step that posts to DHIS2');
  expect(conversation.workflow_id).toBe(wf.id);
  await expect(sentMessages(page)).toHaveCount(1);
  await expect(sentMessages(page)).toContainText(
    'Add a step that posts to DHIS2'
  );
  await expect(sentMessages(page)).toContainText(`Sent by ${nameOf(ME).full}`);
  await expect.poll(() => chatInUrl(page)).toBe(conversation.id);
});

// @S05
// Scenario: Every message carries the workflow as it is now
//   Given I have "Intake" open with an unsaved new step "Clean data"
//   When I ask "What does this workflow do?"
//   Then the request to the assistant includes the workflow with "Clean data"
//   And with the code editor open on "Clean data", the page sent is "workflows/Intake/Clean data"
// The unsaved edit is "Fetch" renamed to "Clean data". The code editor half
// opens the saved step "Load", since a reload starts from what is saved.
test('@S05', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  const { wf } = givenIntake();
  await openAs(page, wf);
  await renameStep(page, 'Fetch', 'Clean data');

  await ask(page, 'What does this workflow do?');

  await expect.poll(() => apollo.asked().length, EVENTUALLY).toBe(1);
  const [first] = apollo.asked();
  expect(first.content).toBe('What does this workflow do?');
  expect(first.workflow_yaml).toContain('Clean data');
  expect(first.page).toBe('workflows/Intake');

  await openIde(page, wf.projectId, wf.id, wf.steps.Load, { chat: 'true' });
  await ask(page, 'What does this step do?');

  await expect.poll(() => apollo.asked().length, EVENTUALLY).toBe(2);
  expect(apollo.asked()[1].page).toBe('workflows/Intake/Load');
});

// @S06
// Scenario: A reply streams in and sending waits until it is done
//   Given I have sent a message in a conversation
//   Then I see a status such as "Thinking..." while the assistant works
//   And the reply text appears as it arrives and stays once complete
//   And the message box is disabled until the reply is in
test('@S06', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  const [first, second] = [gate(), gate()];
  apollo.replyWith([
    thinking,
    first.step,
    chunk('Intake receives patient records'),
    second.step,
    chunk(' and loads them.'),
    done('Intake receives patient records and loads them.'),
  ]);
  const { wf } = givenIntake();
  await openAs(page, wf);

  await ask(page, 'What does this workflow do?');

  await expect(panel(page).getByText('Thinking...')).toBeVisible(EVENTUALLY);
  await expect(messageBox(page)).toBeDisabled();
  first.open();
  await expect(
    panel(page).getByText(/Intake receives patient records/)
  ).toBeVisible(EVENTUALLY);
  await expect(messageBox(page)).toBeDisabled();
  second.open();

  await repliesSettled(page, 1);
  await expect(replies(page)).toContainText(
    'Intake receives patient records and loads them.'
  );
});

// @S15
// Scenario: A failed reply says why and can be tried again
//   Given the assistant fails to answer "What does this do?" with "The connection to the assistant was lost. Please try again."
//   Then the reply area shows "The connection to the assistant was lost." with "Try again"
//   And my question is not marked failed a second time
//   When I click "Try again"
//   Then the question is sent again and the button disappears
// The stand-in drops the connection before any text.
test('@S15', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(['cut'], answer('It loads patient records.'));
  const { wf } = givenIntake();
  await openAs(page, wf);

  await ask(page, 'What does this do?');

  const reason = panel(page).getByText(
    'The connection to the assistant was lost.'
  );
  await expect(reason).toHaveCount(1, EVENTUALLY);
  const tryAgain = panel(page).getByRole('button', { name: 'Try again' });
  await expect(tryAgain).toHaveCount(1);

  await tryAgain.click();

  await expect.poll(() => apollo.asked().length, EVENTUALLY).toBe(2);
  expect(apollo.asked()[1].content).toBe('What does this do?');
  await expect(replies(page).last()).toContainText(
    'It loads patient records.',
    EVENTUALLY
  );
  await expect(tryAgain).toHaveCount(0);
});

// @S16
// Scenario: Text that streamed before a failure is kept
//   Given the assistant's reply stops partway through
//   Then the text that arrived stays on screen with the failure reason below it
//   And it is still there after reload
test('@S16', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith([chunk('Intake receives patient records and'), 'cut']);
  const { wf } = givenIntake();
  await openAs(page, wf);

  await ask(page, 'What does this workflow do?');

  const expectPartial = async () => {
    const reply = replies(page).last();
    await expect(reply).toContainText(
      'Intake receives patient records and',
      EVENTUALLY
    );
    await expect(reply).toContainText(
      'The connection to the assistant was lost.'
    );
  };
  await expectPartial();
  await expect.poll(() => chatInUrl(page)).toMatch(/^[0-9a-f-]{36}$/);

  await reload(page);

  await expect(panel(page)).toBeVisible();
  await expectPartial();
});

// @S17
// Scenario: A reply whose code edit failed says so
//   Given the assistant answers but could not apply its edit to a step's code
//   Then the reply shows "I tried to update the code but couldn't apply the change." with "Try again"
//   And "Try again" re-runs my question, and disappears once a later reply arrives
test('@S17', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(
    answer('I updated Fetch.', { codeEditFailed: true }),
    answer('Fetch now logs each patient.')
  );
  const { wf } = givenIntake();
  await openAs(page, wf);

  await ask(page, 'Make Fetch log each patient');

  const notice = panel(page).getByText(
    "I tried to update the code but couldn't apply the change."
  );
  await expect(notice).toBeVisible(EVENTUALLY);
  await panel(page).getByRole('button', { name: 'Try again' }).click();

  await expect.poll(() => apollo.asked().length, EVENTUALLY).toBe(2);
  expect(apollo.asked()[1].content).toBe('Make Fetch log each patient');
  await expect(replies(page).last()).toContainText(
    'Fetch now logs each patient.',
    EVENTUALLY
  );
  await expect(
    panel(page).getByRole('button', { name: 'Try again' })
  ).toHaveCount(0);
});

// @S18
// Scenario: A message stuck by a crash or deploy is released
//   Given a message has been "processing" longer than the reply time limit plus two minutes and its job is gone
//   When the reaper runs
//   Then the message shows "The assistant was interrupted before it finished." with "Try again"
//   And the message box is enabled again
// The sweep runs over the whole instance.
test('@S18', PASSING_OLD_SERIAL, async ({ page }) => {
  needsAssistant();
  const { wf } = givenIntake();
  const session = givenConversation(wf, 'What does Intake do?', ME, {
    messages: [
      { role: 'user', content: 'What does Intake do?', status: 'processing' },
    ],
  });
  await openAs(page, wf, { query: { 'w-chat': session } });
  await expect(sentMessages(page)).toHaveCount(1, EVENTUALLY);
  await expect(messageBox(page)).toBeDisabled();

  runStuckMessageSweep();

  await expect(
    panel(page).getByText('The assistant was interrupted before it finished.')
  ).toBeVisible(EVENTUALLY);
  await expect(
    panel(page).getByRole('button', { name: 'Try again' })
  ).toBeVisible();
  await expect(messageBox(page)).toBeEnabled();
});

// ---------------------------------------------------------------------------
// Have changes applied
// ---------------------------------------------------------------------------

// @S07
// Scenario: The assistant's workflow changes land on the canvas for the person who asked, unsaved
//   Given I am an editor with "Intake" open
//   When I ask "Add a step that posts to DHIS2" and the reply changes the workflow
//   Then the canvas shows the new step as the reply arrives
//   And "Save" shows unsaved changes (shared-editor-session S19)
//   And the reply lists the changed steps
//   And the YAML is parsed and written as shared-workflow-yaml-format describes
// How the YAML is parsed and written is shared-workflow-yaml-format's; its
// S11 runs below on this apply.
test('@S07', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  const held = gate();
  apollo.replyWith(req => {
    const yaml = edited(req, addStep(SEND, 'Load'));
    return [
      { event: 'changes', data: { yaml } },
      held.step,
      ...answer(`I added "${SEND}" after Load.`, { yaml }),
    ];
  });
  const { wf } = givenIntake();
  await openAs(page, wf);

  await ask(page, 'Add a step that posts to DHIS2');

  await expect(node(page, SEND)).toBeVisible(EVENTUALLY);
  held.open();
  await repliesSettled(page, 1);
  await expect(unsavedMarker(page)).toBeVisible();
  await expect(changedStep(replies(page).last(), SEND)).toBeVisible();
  expect(storedWorkflow(wf.id).steps).not.toContain(SEND);
});

// @S08
// Scenario: Applied changes keep each step's credential
//   Given step "Send to DHIS2" uses credential "DHIS2 prod"
//   When an applied reply rewrites "Send to DHIS2"
//   Then "Send to DHIS2" still uses "DHIS2 prod"
test('@S08', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(req =>
    answer(`I rewrote "${SEND}".`, {
      yaml: edited(req, setBody(SEND, "create('dataValueSets', {});")),
    })
  );
  const { id, wf } = givenIntake(
    { [ME]: 'editor' },
    { steps: ['Fetch', SEND] }
  );
  const credential = seedCredential(OWNER, {
    name: 'DHIS2 prod',
    schema: 'dhis2',
    bodies: {
      main: {
        username: 'admin',
        password: 'district',
        hostUrl: 'https://play.dhis2.example.org',
      },
    },
    projects: [id],
  });
  cleanups.push(credential.remove);
  adaptorConfig.jobUses(wf.steps[SEND], DHIS2, {
    projectId: id,
    credentialId: credential.id,
  });
  const before = credentialOfJob(wf.steps[SEND]);
  await openAs(page, wf);

  await ask(page, `Rewrite "${SEND}" to post data values`);
  await repliesSettled(page, 1);
  await saveWorkflow(page);

  expect(before).not.toBeNull();
  expect(credentialOfJob(wf.steps[SEND])).toBe(before);
});

// @S09
// Scenario: On a new workflow, the assistant's workflow is created for the person who asked
//   Given I started a new workflow with "Build with AI" (workflow-editor-new S20)
//   When the reply carries a workflow
//   Then it is applied and saved with errors only reported
//   And a validation failure appears as an assistant message instead of a toast
test('@S09', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(
    answer('Here is a workflow for patient intake.', {
      yaml: newWorkflowFile('Patient intake'),
    }),
    answer('Here is a workflow for discharges.', {
      yaml: newWorkflowFile('Discharges', 'Fetch discharges', {
        withBody: false,
      }),
    })
  );
  const { id } = givenProject();
  await signInAs(page, ME);

  await buildWithAi(page, id, 'Take in patient records from a webhook');

  await expect
    .poll(() => workflowsOf(id).map(w => w.name), EVENTUALLY)
    .toContain('Patient intake');
  await expect(editorToast(page, 'Workflow saved')).toHaveCount(0);

  await buildWithAi(page, id, 'Fetch discharges every night');

  // The reply, then the validation failure as a message of its own
  await expect
    .poll(() => replies(page).count(), EVENTUALLY)
    .toBeGreaterThanOrEqual(2);
  await expect(editorToast(page, 'Failed to apply workflow')).toHaveCount(0);
  expect(workflowsOf(id).map(w => w.name)).not.toContain('Discharges');
});

// @S10
// Scenario: On a new workflow, changes wait for a connection
//   Given I am creating a new workflow and my editor connection has dropped
//   When the assistant's reply carries a workflow
//   Then I see "Not connected" with "Connect to the server before creating a workflow."
//   And while the editor is still joining I see "Still connecting" instead
//   And once I reconnect the workflow is applied and saved
test('@S10', PENDING, () => {
  test.skip(
    true,
    'the editor and the assistant share one connection, so a reply cannot arrive while the editor is offline'
  );
});

// @S11
// Scenario: A change that did not reach the canvas says so and can be retried
//   Given the assistant replies with a workflow that cannot be applied
//   Then I see "Failed to apply workflow" with the reason
//   And the reply says "These changes were not applied to the canvas." with "Try again"
//   And there is no "Revert changes" on it
//   When I reload the page and reopen the conversation
//   Then the reply still says the changes were not applied
//   When I click "Try again" and the apply succeeds
//   Then the notice is gone and the server forgets the failure
// The workflow cannot be applied because a step has no code. Before the
// reload the stored reply's workflow is fixed, so the retry can succeed.
test('@S11', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  let fixed = '';
  apollo.replyWith(req => {
    fixed = edited(req, addStep(SEND, 'Load'));
    return answer(`I added "${SEND}".`, {
      yaml: edited(req, addStep(SEND, 'Load'), dropBody('Fetch')),
    });
  });
  const { wf } = givenIntake();
  await openAs(page, wf);

  await ask(page, 'Add a step that posts to DHIS2');

  await expect(editorToast(page, 'Failed to apply workflow')).toBeVisible(
    EVENTUALLY
  );
  const notice = panel(page).getByText(
    'These changes were not applied to the canvas.'
  );
  await expect(notice).toBeVisible(EVENTUALLY);
  await expect(revertButton(page)).toHaveCount(0);
  await expect(node(page, SEND)).toHaveCount(0);

  const session = chatInUrl(page)!;
  await expect
    .poll(() => messagesOf(session).some(m => m.apply_failed), EVENTUALLY)
    .toBe(true);
  replaceReplyWorkflow(session, fixed);
  await reload(page);
  await expect(notice).toBeVisible(EVENTUALLY);

  await panel(page).getByRole('button', { name: 'Try again' }).click();

  await expect(node(page, SEND)).toBeVisible(EVENTUALLY);
  await expect(notice).toHaveCount(0);
  await expect
    .poll(() => messagesOf(session).some(m => m.apply_failed), EVENTUALLY)
    .toBe(false);
});

// @S12
// Scenario: The last reply's changes can be reverted and restored
//   Given the assistant's last reply changed "Intake" and I have edited nothing since
//   When I click "Revert changes" on that reply
//   Then the workflow is back as it was before the reply, and the control reads "Restore changes"
//   Given instead I edited the workflow after the reply
//   When I click "Revert changes"
//   Then I see "Reverting replaces the whole workflow" with "Revert anyway"
//   And only the last settled reply offers "Revert changes"
// Two replies, each adding a step; the second is the one reverted.
test('@S12', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(
    req =>
      answer(`I added "${SEND}".`, {
        yaml: edited(req, addStep(SEND, 'Load')),
      }),
    req =>
      answer('I added "Notify".', {
        yaml: edited(req, addStep('Notify', SEND)),
      })
  );
  const { wf } = givenIntake();
  await openAs(page, wf);
  await ask(page, 'Add a step that posts to DHIS2');
  await repliesSettled(page, 1);
  await ask(page, 'Then notify the team');
  await repliesSettled(page, 2);
  await expect(node(page, 'Notify')).toBeVisible();

  await expect(revertButton(page)).toHaveCount(1);
  await expect(
    replies(page).last().getByRole('button', { name: 'Revert changes' })
  ).toBeVisible();
  await revertButton(page).click();

  await expect(node(page, 'Notify')).toHaveCount(0);
  await expect(node(page, SEND)).toBeVisible();
  await expect(restoreButton(page)).toBeVisible();
  await restoreButton(page).click();
  await expect(node(page, 'Notify')).toBeVisible();

  await renameStep(page, 'Fetch', 'Fetch patients');
  await revertButton(page).click();

  const dialog = page.getByRole('dialog', {
    name: 'Reverting replaces the whole workflow',
  });
  await expect(shown(dialog)).toBeVisible();
  await expect(
    dialog.getByRole('button', { name: 'Revert anyway' })
  ).toBeVisible();
});

// @S32
// Scenario: A step the assistant changed opens in the code editor
//   Given a reply lists changes to step "Send to DHIS2"
//   When I click "Send to DHIS2" in the reply
//   Then the code editor opens on "Send to DHIS2" (handoff to workflow-editor-ide)
// Today the reply's step has an "Open" link beside its name.
test('@S32', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(req =>
    answer(`I rewrote "${SEND}".`, {
      yaml: edited(req, setBody(SEND, "create('dataValueSets', {});")),
    })
  );
  const { wf } = givenIntake({ [ME]: 'editor' }, { steps: ['Fetch', SEND] });
  await openAs(page, wf);
  await ask(page, `Rewrite "${SEND}" to post data values`);
  await repliesSettled(page, 1);

  await openStepButton(replies(page).last(), SEND).click();

  await ideReady(page);
  await expect(jobSelector(page)).toHaveText(new RegExp(SEND));
  expect(editorQuery(page)).toMatchObject({
    panel: 'editor',
    job: wf.steps[SEND],
  });
  await expect(closeIdeButton(page)).toBeVisible();
});

// ---------------------------------------------------------------------------
// Limits on what people can do
// ---------------------------------------------------------------------------

// @S13
// Scenario: Viewers can ask but cannot change the workflow through the assistant
//   Given I am a viewer on the project with "Intake" open
//   When I ask the assistant a question
//   Then my message is sent and answered
//   And no reply is applied to the canvas
//   And "Apply" is disabled with "Cannot apply workflow in readonly mode"
//   And a job context update I send is refused with "unauthorized"
// Still pending, old: the reply has no "Apply"; it lists its changes as made though the canvas is unchanged
test('@S13', PENDING_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(req =>
    answer(`I added "${SEND}".`, { yaml: edited(req, addStep(SEND, 'Load')) })
  );
  const { wf } = givenIntake({ [ME]: 'viewer' });
  await openAs(page, wf);

  await ask(page, 'Add a step that posts to DHIS2');

  await repliesSettled(page, 1);
  expect(apollo.asked()).toHaveLength(1);
  await expect(node(page, SEND)).toHaveCount(0);
  const apply = panel(page).getByRole('button', { name: 'Apply', exact: true });
  await expect(apply).toBeDisabled();
  expect(await headerTooltip(page, apply)).toContain(
    'Cannot apply workflow in readonly mode'
  );

  const channel = await channelAs(page, chatInUrl(page)!);
  const update = await channel.push('update_context', {
    job_body: 'fn(s => s);',
  });
  expect(update.status).toBe('error');
  expect(reasonOf(update)).toBe('unauthorized');
});

// @S14 @variant:experimental-features
// Scenario: On a live workflow the assistant offers to switch to draft
//   Given "Intake" is live outside a sandbox and I have experimental features on
//   When I open the assistant
//   Then I see "The Assistant cannot make changes while this workflow is live." with "Switch to draft"
//   And replies are not applied
//   When I click "Switch to draft"
//   Then I see "This takes the workflow out of production. Its triggers will be turned off and it will stop processing data until you go live again."
// Switching to draft itself is workflow-editor-canvas's; it is not confirmed.
test('@S14', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(req =>
    answer(`I added "${SEND}".`, { yaml: edited(req, addStep(SEND, 'Load')) })
  );
  setPreferences(ME, { experimental_features: true });
  const { wf, by } = givenIntake({ [ME]: 'editor' }, { enabled: false });
  goLiveOnNode(wf.id, by);
  await openAs(page, wf);

  await expect(
    panel(page).getByText(
      'The Assistant cannot make changes while this workflow is live.'
    )
  ).toBeVisible();
  await ask(page, 'Add a step that posts to DHIS2');
  await repliesSettled(page, 1);
  await expect(node(page, SEND)).toHaveCount(0);

  await panel(page).getByRole('button', { name: 'Switch to draft' }).click();

  await expect(
    confirmDialog(page, 'Switch to draft').getByText(
      'This takes the workflow out of production. Its triggers will be turned off and it will stop processing data until you go live again.'
    )
  ).toBeVisible();
});

// @S19 @variant:ai-limit-reached
// Scenario: When the AI quota is spent the panel says so
//   Given project "Malawi HIV" has used its AI quota with the message "AI usage limit reached for this month"
//   When I open the assistant on "Intake"
//   Then I see "AI usage limit reached for this month" at the top of the panel
//   And the message box is disabled and hovering it shows the same text
// The usage limiter is instance-wide.
test('@S19', PASSING_OLD_SERIAL, async ({ page }) => {
  needsAssistant();
  const limit = 'AI usage limit reached for this month';
  cleanups.push(withLimiterRefusing('ai_usage', limit));
  const { wf } = givenIntake();

  await openAs(page, wf);

  await expect(
    panel(page).getByRole('alert').filter({ hasText: limit })
  ).toBeVisible();
  await expect(messageBox(page)).toBeDisabled();
  expect(await messageBoxTip(page)).toContain(limit);
});

// @S20 @variant:ai-limit-reached
// Scenario: A message sent after the quota runs out is kept but not answered
//   Given the quota runs out while I have the panel open
//   When I send "Why did step 2 fail?"
//   Then I see "Message limit exceeded" with the limit message
//   And my message is shown as failed and is not sent to the assistant
//   And "Try again" checks the quota again before sending
// In a conversation already open; the quota is still spent at "Try again".
test('@S20', PASSING_OLD_SERIAL, async ({ page }) => {
  needsAssistant();
  const limit = 'AI usage limit reached for this month';
  const { wf } = givenIntake();
  const session = givenConversation(wf, 'What does Intake do?', ME);
  await openAs(page, wf, { query: { 'w-chat': session } });
  await expect(replies(page)).toHaveCount(1, EVENTUALLY);
  cleanups.push(withLimiterRefusing('ai_usage', limit));

  await ask(page, 'Why did step 2 fail?');

  const alert = editorToast(page, 'Message limit exceeded');
  await expect(alert).toBeVisible(EVENTUALLY);
  await expect(alert).toContainText(limit);
  await expect(sentMessages(page).last()).toContainText('Why did step 2 fail?');
  const tryAgain = panel(page).getByRole('button', { name: 'Try again' });
  await expect(tryAgain).toBeVisible();
  const asked = () =>
    messagesOf(session).find(m => m.content === 'Why did step 2 fail?');
  await expect.poll(() => asked()?.status).toBe('error');
  expect(obanJobsNaming(MESSAGE_PROCESSOR, asked()!.id)).toHaveLength(0);

  await tryAgain.click();

  await expect(editorToast(page, 'Message limit exceeded')).toBeVisible();
  await page.waitForTimeout(1000);
  expect(obanJobsNaming(MESSAGE_PROCESSOR, asked()!.id)).toHaveLength(0);
});

// @S26
// Scenario: Messages over 10,000 characters cannot be sent
//   Given I have typed 9,500 characters
//   Then I see "9,500 / 10,000"
//   When I type past 10,000 characters
//   Then the counter says it is too long to send and "Send" is disabled
test('@S26', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { wf } = givenIntake();
  await openAs(page, wf);
  await expect(messageBox(page)).toBeEnabled(EVENTUALLY);

  await messageBox(page).fill('a'.repeat(9500));

  await expect(panel(page).getByText(/9,500\s*\/\s*10,000/)).toBeVisible();
  await expect(sendButton(page)).toBeEnabled();

  await messageBox(page).fill('a'.repeat(10001));

  await expect(panel(page).getByText(/too long to send/)).toBeVisible();
  await expect(sendButton(page)).toBeDisabled();
});

// ---------------------------------------------------------------------------
// Keep conversations with the project
// ---------------------------------------------------------------------------

// @S21
// Scenario: Members browse and reopen this workflow's conversations
//   Given "Intake" has 25 conversations
//   When I open "Conversations" from the panel menu
//   Then I see the 20 most recently updated, each with its title, relative time and message count
//   And "Load 5 more" loads the rest
//   When I search "dhis2"
//   Then only conversations whose title contains "dhis2" are listed
//   When I click one
//   Then its messages load and the URL has its id
//   And conversations from other workflows are not listed
// Three of the 25 mention DHIS2; "Discharge" has one of its own.
test('@S21', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { wf } = givenIntake();
  const discharge = seedEditorWorkflow(wf.projectId, OWNER, {
    name: 'Discharge',
  });
  const titles = Array.from({ length: 25 }, (_, i) =>
    i % 10 === 3 ? `Post to DHIS2 number ${i + 1}` : `Question number ${i + 1}`
  );
  const ids = seedConversations(wf.projectId, [
    ...titles.map((title, i) => ({
      title,
      workflowId: wf.id,
      by: ME,
      minutesAgo: i * 10,
    })),
    { title: 'About Discharge', workflowId: discharge.id, by: ME },
  ]);
  // From inside a conversation: the panel opens on the list without one
  await openAs(page, wf, { query: { 'w-chat': ids[0] } });

  await choosePanelMenu(page, 'Conversations');

  await expect
    .poll(() => listedConversations(page), EVENTUALLY)
    .toEqual(titles.slice(0, 20));
  const newest = conversationItem(page, titles[0]);
  await expect(newest).toContainText(/just now|minute/);
  await expect(newest).toContainText('2');
  await expect(loadMoreButton(page)).toHaveText(/Load 5 more/);
  await loadMoreButton(page).click();
  await expect.poll(() => listedConversations(page)).toEqual(titles);
  expect(await listedConversations(page)).not.toContain('About Discharge');

  await searchConversations(page, 'dhis2');

  const dhis2 = titles.filter(t => /dhis2/i.test(t));
  await expect.poll(() => listedConversations(page)).toEqual(dhis2);
  await conversationItem(page, dhis2[0]).click();

  await expect(sentMessages(page)).toContainText(dhis2[0], EVENTUALLY);
  await expect.poll(() => chatInUrl(page)).toBe(ids[titles.indexOf(dhis2[0])]);
});

// @S22
// Scenario: Conversations are shared with everyone on the project
//   Given editor "Amara" had a conversation on "Intake"
//   When viewer "Ben" opens its link
//   Then "Ben" sees every message, each attributed to who sent it
// The owner joined Amara's conversation, so two people sent messages in it.
test('@S22', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { wf } = givenIntake({ [ME]: 'viewer', [THIRD]: 'editor' });
  const session = givenConversation(wf, 'How do I post to DHIS2?', THIRD, {
    messages: [
      { role: 'user', content: 'How do I post to DHIS2?', by: THIRD },
      { role: 'assistant', content: 'Use the dhis2 adaptor.' },
      { role: 'user', content: 'And from Kobo?', by: OWNER },
      { role: 'assistant', content: 'Use the kobotoolbox adaptor.' },
    ],
  });

  await openAs(page, wf, { query: { 'w-chat': session } });

  await expect(sentMessages(page)).toHaveCount(2, EVENTUALLY);
  await expect(sentMessages(page).nth(0)).toContainText(
    `Sent by ${nameOf(THIRD).full}`
  );
  await expect(sentMessages(page).nth(1)).toContainText(
    `Sent by ${nameOf(OWNER).full}`
  );
  await expect(replies(page)).toHaveCount(2);
  await expect(replies(page).nth(0)).toContainText('Use the dhis2 adaptor.');
  await expect(replies(page).nth(1)).toContainText(
    'Use the kobotoolbox adaptor.'
  );
});

// @S23
// Scenario Outline: People outside the project cannot read or join its conversations
//   Given a conversation on workflow "Intake" in project "Malawi HIV"
//   When <who> joins it or lists the project's conversations
//   Then the join is refused with "unauthorized" and the listing with 403
//   Examples:
//     | who                                                      |
//     | a registered user not on "Malawi HIV"                    |
//     | a support user while support access is off               |
//     | an editor who has not enrolled in MFA, on an MFA project |
// One step per example, each on a project of its own; soft, so every
// example is checked. The support example comes last: I keep the flag.
test('@S23', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  await signInAs(page, ME);

  const expectRefused = async (wf: EditorWorkflow, who: string) => {
    const session = givenConversation(wf, 'What does Intake do?');
    const channel = await channelAs(page, session);
    expect.soft(channel.joined.status, who).toBe('error');
    expect.soft(reasonOf(channel.joined), who).toBe('unauthorized');
    expect
      .soft(await listConversationsOverHttp(page, wf.projectId, wf.id), who)
      .toBe(403);
  };

  await test.step('a registered user not on the project', async () => {
    const { wf } = givenIntake({});
    await expectRefused(wf, 'not a member');
  });

  await test.step('an editor not enrolled in MFA, on an MFA project', async () => {
    const { id, wf } = givenIntake(
      { [ME]: 'editor' },
      {},
      { name: 'Malawi Malaria' }
    );
    requireMfa(id);
    await expectRefused(wf, 'MFA not enrolled');
  });

  await test.step('a support user while support access is off', async () => {
    cleanups.push(makeSupportUser(ME));
    const { wf } = givenIntake({}, {}, { name: 'Malawi TB' });
    await expectRefused(wf, 'support, access off');
  });
});

// @S24
// Scenario: With a run open, members attach its logs and the shape of its data
//   Given I have run "R" of "Intake" open
//   Then above the message box I see "Send run logs" and "Send run data", unticked
//   When I tick "Send run data" and ask "Why did step 2 fail?"
//   Then the assistant receives each step's input and output with values replaced by their types
//   And the next time I open "Intake" "Send run data" is still ticked
//   And with no run open neither box is offered
// "Fetch" output 3 patients; the number must not reach the assistant.
test('@S24', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  const { id } = givenProject();
  const run = seedRun(
    id,
    {
      workflow: 'Intake',
      steps: [
        { name: 'Fetch', output: { patients: 3 } },
        { name: 'Load', exit: 'fail', errorType: 'RuntimeError' },
      ],
      state: 'failed',
    },
    OWNER
  );
  cleanups.unshift(run.removeCredentials);
  await signInAs(page, ME);
  const withRun = { run: run.runId };
  await openWithPanel(page, id, run.workflowId, withRun);
  const box = (name: string) => panel(page).getByRole('checkbox', { name });

  await expect(box('Send run logs')).not.toBeChecked();
  await expect(box('Send run data')).not.toBeChecked();
  await box('Send run data').check();
  await ask(page, 'Why did step 2 fail?');

  await expect.poll(() => apollo.asked().length, EVENTUALLY).toBe(1);
  const attached = apollo.asked()[0].attachments ?? [];
  const types = attached.map(a => a.type);
  expect(types).toContain('output_dataclip');
  expect(types).not.toContain('log');
  const fetchOutput = JSON.stringify(
    attached.find(
      a =>
        a.type === 'output_dataclip' &&
        (a.content as { step?: string }).step === 'Fetch'
    )
  );
  expect(fetchOutput).toContain('patients');
  expect(fetchOutput).not.toMatch(/"patients":\s*3/);

  await openWithPanel(page, id, run.workflowId, withRun);
  await expect(box('Send run data')).toBeChecked();

  await openWithPanel(page, id, run.workflowId);
  await expect(box('Send run logs')).toHaveCount(0);
  await expect(box('Send run data')).toHaveCount(0);
});

// @S25
// Scenario: A run from another project is never attached
//   Given I am on "Malawi HIV" and run "X" belongs to a project I am not on
//   When I send a message, or start a conversation, naming run "X"
//   Then run "X" is dropped and nothing from it is attached
// Sent from a second connection, as the panel would send them, with both
// boxes ticked.
test('@S25', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  const { id, wf } = givenIntake();
  const other = givenProject({}, { name: 'Malawi TB' });
  const x = seedRun(
    other.id,
    { workflow: 'Lab results', steps: [{ name: 'Fetch', output: { hiv: 1 } }] },
    OWNER
  );
  cleanups.unshift(x.removeCredentials);
  const naming = {
    follow_run_id: x.runId,
    attach_logs: true,
    attach_io_data: true,
  };
  await signInAs(page, ME);

  const channel = await channelAs(
    page,
    'new',
    newConversationParams(id, wf.id, 'Why did step 2 fail?', naming)
  );
  expect(channel.joined.status).toBe('ok');
  await expect.poll(() => apollo.asked().length, EVENTUALLY).toBe(1);
  const [conversation] = conversationsOf(id);
  expect(conversation.follow_run_id).not.toBe(x.runId);

  const sent = await channel.push('new_message', {
    content: 'And step 3?',
    use_global_assistant: true,
    ...naming,
  });
  expect(sent.status).toBe('ok');
  await expect.poll(() => apollo.asked().length, EVENTUALLY).toBe(2);

  for (const request of apollo.asked())
    expect(request.attachments ?? []).toEqual([]);
  expect(conversationsOf(id)[0].follow_run_id).not.toBe(x.runId);
});

// @S27
// Scenario: A conversation started on an unsaved workflow stays with it once saved
//   Given I started a conversation while creating a new workflow
//   When the workflow is saved for the first time
//   Then the conversation is listed under the saved workflow
// The first save is the one the assistant's workflow gets (S09).
test('@S27', PASSING_OLD_SERIAL, async ({ page }) => {
  const apollo = await givenApollo();
  apollo.replyWith(
    answer('Here is a workflow for patient intake.', {
      yaml: newWorkflowFile('Patient intake'),
    })
  );
  const { id } = givenProject();
  await signInAs(page, ME);

  await buildWithAi(page, id, 'Take in patient records from a webhook');

  await expect
    .poll(() => workflowsOf(id).map(w => w.name), EVENTUALLY)
    .toContain('Patient intake');
  const saved = workflowsOf(id).find(w => w.name === 'Patient intake')!;
  await expect
    .poll(() => conversationsOf(id)[0]?.workflow_id, EVENTUALLY)
    .toBe(saved.id);

  // The panel opens on the list
  await openWithPanel(page, id, saved.id);
  await expect
    .poll(() => listedConversations(page), EVENTUALLY)
    .toEqual(['Take in patient records from a webhook']);
});

// @S28
// Scenario Outline: Losing access to the project closes the assistant
//   Given <who> has a conversation open on "Intake"
//   When <change>
//   Then their assistant channel closes and further messages they send are refused with "unauthorized"
//   Examples:
//     | who                         | change                                 |
//     | an editor                   | an admin removes them from the project |
//     | a support user with no role | an owner turns support access off      |
// "Further messages" are a new join of the same conversation. The editor
// page itself reacts too (shared-project-scope S07, S09).
test('@S28', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  await signInAs(page, ME);

  await test.step('an admin removes an editor from the project', async () => {
    const { id, wf } = givenIntake();
    const session = givenConversation(wf, 'What does Intake do?');
    const channel = await channelAs(page, session);
    expect(channel.joined.status).toBe('ok');

    removeMemberOnNode(id, ME, OWNER);

    await expectShut(page, channel, session);
  });

  await test.step('an owner turns support access off', async () => {
    cleanups.push(makeSupportUser(ME));
    const { id, wf } = givenIntake(
      {},
      {},
      { name: 'Malawi TB', allowSupportAccess: true }
    );
    const session = givenConversation(wf, 'What does Intake do?');
    const channel = await channelAs(page, session);
    expect(channel.joined.status).toBe('ok');

    setSupportAccessOnNode(id, false);

    await expectShut(page, channel, session);
  });
});

// @S29
// Scenario: Becoming a viewer keeps the conversation open
//   Given I am an editor with a conversation open
//   When my role changes to viewer
//   Then my assistant channel stays open and I can still list conversations and send messages
//   And a job context update I send is refused
test('@S29', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { id, wf } = givenIntake();
  const session = givenConversation(wf, 'What does Intake do?', ME);
  await signInAs(page, ME);
  const channel = await channelAs(page, session);
  expect(channel.joined.status).toBe('ok');

  changeRoleOnNode(id, ME, 'viewer');

  await page.waitForTimeout(2000);
  expect(channel.closed()).toBe(false);
  const listed = await channel.push('list_sessions', { offset: 0, limit: 20 });
  expect(listed.status).toBe('ok');
  const sent = await channel.push('new_message', {
    content: 'And what does Load do?',
    use_global_assistant: true,
  });
  expect(sent.status).toBe('ok');
  const update = await channel.push('update_context', {
    job_body: 'fn(s => s);',
  });
  expect(update.status).toBe('error');
});

// @S30
// Scenario: Deleting the workflow or scheduling the project for deletion closes the assistant
//   Given I have a conversation open on "Intake"
//   When another member deletes "Intake"
//   Then the flow "flow-delete-open-workflow" ends here: my assistant channel closes (its S02)
//   When instead the project is scheduled for deletion
//   Then the flow "flow-schedule-project-deletion" ends here: my assistant channel closes (its S04)
// The second half uses a conversation on "Discharge", since "Intake" is gone.
test('@S30', PASSING_OLD, async ({ page }) => {
  needsAssistant();
  const { id, wf } = givenIntake();
  const discharge = seedEditorWorkflow(id, OWNER, { name: 'Discharge' });
  const [onIntake, onDischarge] = seedConversations(id, [
    { title: 'What does Intake do?', workflowId: wf.id, by: ME },
    { title: 'What does Discharge do?', workflowId: discharge.id, by: ME },
  ]);
  await signInAs(page, ME);
  const intake = await channelAs(page, onIntake);
  expect(intake.joined.status).toBe('ok');

  deleteWorkflowOnNode(wf.id, OWNER);

  await expect.poll(() => intake.closed(), EVENTUALLY).toBe(true);

  const other = await channelAs(page, onDischarge);
  expect(other.joined.status).toBe('ok');

  scheduleDeletionOnNode(id);

  await expect.poll(() => other.closed(), EVENTUALLY).toBe(true);
});

// ---------------------------------------------------------------------------
// shared-workflow-yaml-format: S11 runs here, on the assistant's apply to an
// existing workflow. S01 to S10 run on workflow-editor-new's import dialog.
// ---------------------------------------------------------------------------

test.describe('shared-workflow-yaml-format', () => {
  const name = (id: string) =>
    `shared-workflow-yaml-format@${id} on workflow-editor-ai-assistant`;

  // The assistant answers each question with the file it is given, which the
  // panel applies to the open "Intake"
  test(name('S11'), PASSING_OLD_SERIAL, async ({ page }) => {
    const apollo = await givenApollo();
    const { id } = givenProject();
    const intake = yamlFormat.seedCanonicalWorkflow(id, OWNER, {
      customPath: 'facility-001',
    });
    await signInAs(page, ME);
    await openWithPanel(page, id, intake.id);
    let asked = 0;

    await yamlFormat.S11(
      page,
      intake,
      async yaml => {
        apollo.replyWith(answer('Here is the workflow.', { yaml }));
        await ask(page, `Apply this file (${++asked})`);
        await repliesSettled(page, asked);
        await expect(unsavedMarker(page)).toBeVisible();
      },
      () => saveWorkflow(page)
    );
  });
});
