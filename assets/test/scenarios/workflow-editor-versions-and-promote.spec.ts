// Scenarios from annotations/views/workflow-editor-versions-and-promote.md,
// and the shared scenarios this view reaches in its own terms.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns every project and saves, publishes and
// provisions through Lightning; super@openfn.org is the colleague ("Ben") a
// test needs. Every project ("Malawi HIV", its sandboxes, "Kenya TB") is
// seeded by the test and removed again afterwards, with its workflows, runs
// and dataclips. "Intake" is a webhook trigger leading to "Fetch", then
// "Load", unless a test says otherwise. Saves and publishes are told apart by
// renaming a step, so the canvas shows which one is open.
//
// The editor is not being ported: these record what today's editor does,
// through pages/workflow-editor-versions-and-promote.ts, so a rebuild that
// keeps the Value passes.
//
// Shared scenarios. shared-authenticated-session, shared-project-scope,
// shared-editor-session and shared-flash-messages belong to the route
// /projects/:id/w/:id and run whole in workflow-editor-canvas.spec.ts. Here:
// - shared-editor-session S10 (pinned views are read-only) is checked as page
//   tests S01, S03 and S16; S07 (everyone learns about a save) as S07; S20
//   (no unload warning when leaving for a sandbox) as S30; S14 (refused
//   pinned joins) as its own test below, for the publish and run rooms.
// - shared-project-scope S03 is its own test below, reached by joining a
//   sandbox from the picker; S11 (archive landing) belongs to the promote
//   flow and runs on the canvas spec.
// - shared-dataclip-body-viewer: only the access rule for the run input that
//   "Edit in sandbox" loads (S05), as its own test below.
// - shared-run-components: none. The history panel draws its own state pills
//   (not the shared ones), and the run viewer owns the React ports (S15 to
//   S18).
//
// Stand-ins: S08, S10, S12 (first example) and S14 answer, or hold back, a
// request on the workflow's room in the server's place (standInRoom); S11,
// S28 and S29 send the requests the page won't send (watchEditorSocket);
// publishes, restores, runs and sandboxes are seeded through Lightning.
import { expect, test, type Page } from '@playwright/test';

import {
  editorPath,
  editorQuery,
  editorReady,
  editorToast,
  headerTooltip,
  joinRoom,
  node,
  openEditor,
  readOnlyPill,
  renameStep,
  saveButton,
  watchEditorSocket,
  type EditorSocket,
} from './pages/workflow-editor';
import {
  dataclipOf,
  nameInput,
  seedEarlierInputs,
} from './pages/workflow-editor-manual-run';
import {
  bodyAsPage,
  chooseRestore,
  chooseSaveAndSync,
  closeVersions,
  continueSection,
  createButton,
  deletePublish,
  discardChoice,
  discardDialog,
  editInSandboxButton,
  expandHistory,
  expandWorkOrder,
  fullHistoryButton,
  historyExpanded,
  historyLength,
  historyPanel,
  historyRetry,
  joinSandbox,
  listedNumbers,
  listedSandboxes,
  listedVersions,
  listedWorkOrders,
  mismatchBanner,
  namedDataclipsOf,
  openSandboxPicker,
  openVersions,
  pickVersion,
  pinOf,
  pressHistoryShortcut,
  promoteButton,
  promoteDialog,
  provisionSandboxOnNode,
  publishOnNode,
  publishesOf,
  releaseRoom,
  restoreConfirm,
  restoreDialog,
  restoreLinks,
  restoreOnNode,
  reviewCreate,
  reviewDialog,
  reviewText,
  runInputAsPage,
  runLink,
  runRoom,
  sandboxNameBox,
  sandboxPicker,
  shown,
  sandboxesOf,
  saveRenameOnNode,
  savedInputChoice,
  savedInputNames,
  savesOf,
  seedRunOn,
  sendCreateSandbox,
  sendListSandboxes,
  sendRestore,
  serverRefusal,
  setReviewText,
  standInRoom,
  startWith,
  swapToWebhookOnNode,
  syncDialog,
  versionChip,
  versionItem,
  versionMenu,
  versionRowText,
  versionTagOf,
  viewAsExecutedButton,
  workOrderLink,
  workOrderRow,
  workflowNamed,
} from './pages/workflow-editor-versions-and-promote';
import {
  catalogueUnavailable,
  changeRoleOnNode,
  connectRepoOnNode,
  expectAt,
  goLiveOnNode,
  keepAccount,
  nameOf,
  open,
  otherSession,
  patchWithBearer,
  removeMemberOnNode,
  removeWorkflowData,
  scheduleDeletionOnNode,
  seedDataclip,
  seedEditorWorkflow,
  seededApiTokenOf,
  setPreferences,
  signInAs,
  storedWorkflow,
  submit,
  utcStamp,
  withLimiterRefusing,
  exec,
  type EditorWorkflow,
  type EditorWorkflowSeed,
  type WorkspaceSeed,
  seedWorkspace,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const BEN = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING_OLD_SERIAL = { tag: ['@passing-old', '@serial'] };

const LIMIT = 'Your plan allows no more sandboxes.';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests turn my experimental features on
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it
// unless another owner is named) — removed after the test with its workflows
// and any sandboxes made under it
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

// Given "Intake" is live with publishes v1 ("Fetch") and v2 ("Fetch v2")
function givenTwoPublishes(wf: EditorWorkflow, by: string) {
  goLiveOnNode(wf.id, by);
  saveRenameOnNode(wf.id, 'Fetch', 'Fetch v2', by);
  publishOnNode(wf.id, by);
}

// Given a webhook request kept as an input in project <projectId>
const anInput = (projectId: string, body: object = {}) =>
  seedDataclip(projectId, { type: 'http_request', body });

// When I sign in as <email> and open <wf> in the editor, with <query>
async function openAs(page: Page, wf: EditorWorkflow, email = ME, query = '') {
  await signInAs(page, email);
  await openEditor(page, wf.projectId, wf.id, query);
}

// Given <email> has experimental features on (or off)
function experimental(email = ME, on = true) {
  if (email !== ME) cleanups.push(keepAccount(email));
  setPreferences(email, { experimental_features: on });
}

// The editor path of the copy of <name> in project <projectId>
const copyPath = (projectId: string, name = 'Intake') =>
  editorPath(projectId, workflowNamed(projectId, name).id);

// ---------------------------------------------------------------------------
// Browsing versions
// ---------------------------------------------------------------------------

// @S01
// Scenario: Member opens an earlier save read-only
//   Given workflow "Intake" has saves 3, 4 and 5, and 5 is current
//   When I open the version chip, which reads "latest"
//   Then I see "latest" and each save as "v5", "v4", "v3" with its time
//   When I pick "v3"
//   Then the URL carries "v=3" and the chip reads "v3" in yellow
//   And the canvas shows save 3 and is read-only
//   When I pick "latest"
//   Then the pin is removed and I am back on the editable workflow
// The chip's colour is not checked: it says the same as its label.
test('@S01', PASSING_OLD, async ({ page }) => {
  const { wf, by } = givenIntake();
  saveRenameOnNode(wf.id, 'Load', 'Load b', by);
  saveRenameOnNode(wf.id, 'Load b', 'Load c', by);
  const saves = savesOf(wf.id);
  const oldest = saves[saves.length - 1];
  await openAs(page, wf);

  await expect(versionChip(page)).toHaveText(/^latest$/i);
  await openVersions(page);
  expect((await listedVersions(page)).map(l => l.toLowerCase())).toEqual([
    'latest',
    ...saves.map(n => `v${n}`),
  ]);

  await pickVersion(page, `v${oldest}`);
  await expect.poll(() => pinOf(page).v).toBe(String(oldest));
  await expect(versionChip(page)).toHaveText(`v${oldest}`);
  await expect(node(page, 'Load')).toBeVisible();
  await expect(node(page, 'Load c')).toHaveCount(0);
  await expect(readOnlyPill(page)).toBeVisible();

  await pickVersion(page, 'latest');
  await expect.poll(() => pinOf(page).v).toBeUndefined();
  await expect(node(page, 'Load c')).toBeVisible();
  await expect(readOnlyPill(page)).toHaveCount(0);
});

// @S02 @variant:experimental-features
// Scenario: A live workflow lists its publishes and where each came from
//   Given "Intake" is live outside a sandbox with publishes v1 (first go-live), v2 (promoted from sandbox "fix-dates"), v3 (published from draft) and v4 (restored v2)
//   When I open the version chip
//   Then "Latest" comes first, then a "Version history" list newest first
//   And each row shows its v-number, "Initial go-live", "Promoted sandbox fix-dates", "Published from draft" or "Restored v2", the publisher's name and the date
//   And only v4 has a green pill
//   And ordinary saves are not listed
// The green pill (which publish is live) is not checked by colour; v4 being
// first under "Latest" says the same.
test('@S02', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  const fixDates = provisionSandboxOnNode(id, 'fix-dates', by);
  goLiveOnNode(wf.id, by);
  saveRenameOnNode(wf.id, 'Load', 'Load v2', by);
  publishOnNode(wf.id, by, { kind: 'promote', source: fixDates });
  saveRenameOnNode(wf.id, 'Load v2', 'Load v3', by);
  publishOnNode(wf.id, by);
  restoreOnNode(wf.id, 2, by);
  // An ordinary save after the last publish
  saveRenameOnNode(wf.id, 'Load v2', 'Load saved', by);
  await openAs(page, wf);

  await openVersions(page);
  expect((await listedVersions(page)).map(l => l.toLowerCase())).toEqual([
    'latest',
    'v4',
    'v3',
    'v2',
    'v1',
  ]);
  const publisher = nameOf(OWNER).full;
  for (const [label, how] of [
    ['v4', 'Restored v2'],
    ['v3', 'Published from draft'],
    ['v2', 'Promoted sandbox fix-dates'],
    ['v1', 'Initial go-live'],
  ]) {
    const text = await versionRowText(page, label);
    expect.soft(text, label).toContain(how);
    expect.soft(text, label).toContain(publisher);
    expect.soft(text, label).toContain(String(new Date().getUTCFullYear()));
  }
});

// @S03 @variant:experimental-features
// Scenario: Member opens a publish read-only and comes back to Latest
//   Given "Intake" is live with publishes v1 and v2
//   When I pick "v1" from the version chip
//   Then the URL carries "release=1" and no "run", "step", "v" or "as_run"
//   And the chip reads "v1" and the v1 row is marked
//   And the canvas shows v1 and is read-only
//   When I pick "Latest"
//   Then the pin is removed
// The row's mark is a check icon; the chip reading "v1" says the same.
test('@S03', PASSING_OLD, async ({ page }) => {
  experimental();
  const { wf, by } = givenIntake();
  givenTwoPublishes(wf, by);
  await openAs(page, wf);

  await pickVersion(page, 'v1');
  await expect.poll(() => pinOf(page).release).toBe('1');
  const { run, v, as_run } = pinOf(page);
  expect([run, v, as_run, editorQuery(page).step]).toEqual([
    undefined,
    undefined,
    undefined,
    undefined,
  ]);
  await expect(versionChip(page)).toHaveText('v1');
  await expect(node(page, 'Fetch')).toBeVisible();
  await expect(node(page, 'Fetch v2')).toHaveCount(0);
  await expect(readOnlyPill(page)).toBeVisible();

  await pickVersion(page, 'latest');
  await expect.poll(() => pinOf(page).release).toBeUndefined();
  await expect(node(page, 'Fetch v2')).toBeVisible();
});

// @S04 @variant:experimental-features
// Scenario Outline: The list matches what the workflow's versions mean
//   Given "Intake" is <state> <where>
//   When I open the version chip
//   Then I see the <list> list
//   Examples:
//     | state | where                  | list      |
//     | live  | in an ordinary project | publishes |
//     | draft | in an ordinary project | saves     |
//     | live  | in a sandbox           | saves     |
// Each list is told apart by its numbers: publish numbers or save numbers.
test('@S04', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  const sandbox = provisionSandboxOnNode(id, 'dev', by);
  const copy = workflowNamed(sandbox, 'Intake').id;
  goLiveOnNode(wf.id, by);
  goLiveOnNode(copy, by);
  const draft = seedEditorWorkflow(id, by, { name: 'Billing' });
  saveRenameOnNode(draft.id, 'Load', 'Load b', by);
  await signInAs(page, ME);

  for (const [example, projectId, workflowId, numbers] of [
    ['live', id, wf.id, publishesOf(wf.id).map(r => r.n)],
    ['draft', id, draft.id, savesOf(draft.id)],
    ['live in a sandbox', sandbox, copy, savesOf(copy)],
  ] as const) {
    await openEditor(page, projectId, workflowId);
    await openVersions(page);
    expect.soft(await listedNumbers(page), example).toEqual(numbers);
  }
});

// @S05 @variant:experimental-features
// Scenario: A saved-version link on a live workflow falls back to the live copy
//   Given "Intake" is live outside a sandbox
//   When I open "Intake" with "v=5" in the URL
//   Then "v=5" is removed from the URL without adding a history entry
// The link names save 1, which exists: a save that doesn't exist leaves the
// editor with no workflow to read the state from.
test('@S05', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  await signInAs(page, ME);
  const before = await historyLength(page);

  await open(page, editorPath(id, wf.id, '?v=1'));

  await expect.poll(() => pinOf(page).v).toBeUndefined();
  expect(await historyLength(page)).toBe(before + 1);
});

// @S06 @variant:experimental-features
// Scenario: Switching version with unsaved edits asks first
//   Given I am an editor with unsaved changes in "Intake"
//   When I pick another version
//   Then I see "You have unsaved changes" and nothing has switched yet
//   When I choose "Cancel"
//   Then I stay where I was
//   When I pick it again and choose "Save and switch"
//   Then the workflow is saved and then the version switches
//   When the save fails instead
//   Then I stay on my copy with the dialog usable
// "Intake" is a draft (a live one can't be edited with experimental
// features). The failing save is tried first, so the same edit is then saved;
// saves fail while the adaptor catalogue is unavailable, which is
// instance-wide.
test('@S06', PASSING_OLD_SERIAL, async ({ page }) => {
  experimental();
  const { wf, by } = givenIntake();
  saveRenameOnNode(wf.id, 'Load', 'Load b', by);
  const older = savesOf(wf.id)[1];
  await openAs(page, wf);
  await renameStep(page, 'Fetch', 'Fetch mine');

  await pickVersion(page, `v${older}`);
  await expect(shown(discardDialog(page))).toBeVisible();
  expect(pinOf(page).v).toBeUndefined();
  await discardChoice(page, 'Cancel').click();
  await expect(discardDialog(page)).toHaveCount(0);
  expect(pinOf(page).v).toBeUndefined();
  await expect(node(page, 'Fetch mine')).toBeVisible();

  const putBack = catalogueUnavailable();
  try {
    await pickVersion(page, `v${older}`);
    await discardChoice(page, 'Save and switch').click();
    await expect(discardChoice(page, 'Save and switch')).toBeEnabled({
      timeout: 15000,
    });
    expect(pinOf(page).v).toBeUndefined();
    expect(storedWorkflow(wf.id).steps).not.toContain('Fetch mine');
  } finally {
    putBack();
  }

  await discardChoice(page, 'Save and switch').click();
  await expect.poll(() => pinOf(page).v).toBe(String(older));
  expect(storedWorkflow(wf.id).steps).toContain('Fetch mine');
});

// @S07
// Scenario: The version list catches up with saves
//   Given I opened the version chip on "Intake" once
//   When anyone in the room saves "Intake"
//   And I open the version chip again
//   Then the list is fetched again and includes the new save
// Also shared-editor-session S07 in this view's terms.
test('@S07', PASSING_OLD, async ({ page, browser }) => {
  const { wf } = givenIntake({ [ME]: 'editor', [BEN]: 'editor' });
  await openAs(page, wf);
  await openVersions(page);
  const before = await listedNumbers(page);
  await closeVersions(page);

  const ben = await otherSession(browser, BEN);
  await openEditor(ben, wf.projectId, wf.id);
  await renameStep(ben, 'Fetch', 'Fetch patients');
  await saveButton(ben).click();
  await expect(editorToast(ben, 'Workflow saved')).toBeVisible();
  const saved = storedWorkflow(wf.id).lock_version;
  expect(before).not.toContain(saved);

  await expect
    .poll(async () => {
      await openVersions(page);
      const listed = await listedNumbers(page);
      await closeVersions(page);
      return listed;
    })
    .toContain(saved);
});

// @S08
// Scenario: A version list that fails to load says so and tries again
//   Given loading the versions of "Intake" fails
//   When I open the version chip
//   Then I see "Failed to load versions" in the menu and as an alert
//   When I close and reopen the chip
//   Then the versions are requested again
// Stand-in: the server's refusal of the version list is given in its place.
test('@S08', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const room = await standInRoom(page);
  room.refuse('versions');
  await openAs(page, wf);

  await openVersions(page);
  await expect(versionMenu(page)).toContainText('Failed to load versions');
  await expect(editorToast(page, 'Failed to load versions')).toBeVisible();

  const asked = room.asked('versions');
  room.allow('versions');
  await closeVersions(page);
  await openVersions(page);
  await expect.poll(() => room.asked('versions')).toBeGreaterThan(asked);
  expect(await listedNumbers(page)).toEqual(savesOf(wf.id));
});

// ---------------------------------------------------------------------------
// Rolling back a live workflow
// ---------------------------------------------------------------------------

// @S09 @variant:experimental-features
// Scenario: Editor restores an earlier publish without taking the workflow offline
//   Given "Intake" is live with publishes v1 and v2, and v2 broke a job
//   And I am an editor
//   When I choose "Restore" on the v1 row
//   Then I see "Restore v1?" explaining that v1's content is put back and published, and later work is lost
//   When I choose "Restore v1"
//   Then I see "Restored v1"
//   And "Intake" is still live with v1's job bodies
//   And the version list shows a new v3 "Restored v1"
//   And choosing "Restore" did not also pin v1
// Still pending, old: the version list doesn't show the restore's new publish v3, even reopened (unconfirmed)
test('@S09', PENDING, async ({ page }) => {
  experimental();
  const { wf, by } = givenIntake();
  givenTwoPublishes(wf, by);
  await openAs(page, wf);

  await chooseRestore(page, 'v1');
  await expect(shown(restoreDialog(page, 1))).toBeVisible();
  await expect(restoreDialog(page, 1)).toContainText(/lost/);
  expect(pinOf(page).release).toBeUndefined();

  await restoreConfirm(page, 1).click();
  await expect(editorToast(page, 'Restored v1')).toBeVisible();
  const stored = storedWorkflow(wf.id);
  expect(stored.state).toBe('live');
  expect(stored.steps).toEqual(['Fetch', 'Load']);
  expect(publishesOf(wf.id)[0]).toMatchObject({
    n: 3,
    kind: 'restore',
    restored_from: 1,
  });
  if (await versionMenu(page).isVisible()) await closeVersions(page);
  await openVersions(page);
  expect(await versionRowText(page, 'v3')).toContain('Restored v1');
  expect(pinOf(page).release).toBeUndefined();
});

// @S10 @variant:experimental-features
// Scenario: The restore dialog says which triggers it will delete or bring back off
//   Given "Intake" gained a webhook at "/payments" and lost its cron trigger since v1
//   When I choose "Restore" on the v1 row
//   Then "Restore v1" stays disabled with "Checking what this will change..." until the check answers
//   And I see "One trigger will be deleted" naming "the webhook at /payments, which is on now" and "Anything calling those URLs stops working."
//   And I see "One trigger comes back switched off" naming "a scheduled trigger", explaining that a version does not record its authentication
// Stand-in: the check's answer is held back until the first Then is read.
// Webhook paths are unique on the instance, so "payments" carries a suffix.
test('@S10', PASSING_OLD, async ({ page }) => {
  experimental();
  const { wf, by } = givenIntake({ [ME]: 'editor' }, { trigger: 'cron' });
  goLiveOnNode(wf.id, by);
  const path = `payments-${wf.id.slice(0, 8)}`;
  swapToWebhookOnNode(wf.id, path, by);
  publishOnNode(wf.id, by);
  const room = await standInRoom(page);
  room.hold('restore check');
  await openAs(page, wf);

  await chooseRestore(page, 'v1');
  const dialog = restoreDialog(page, 1);
  await expect(dialog).toContainText('Checking what this will change...');
  await expect(restoreConfirm(page, 1)).toBeDisabled();

  room.release();
  await expect(dialog).toContainText('One trigger will be deleted');
  await expect(dialog).toContainText(
    `the webhook at /${path}, which is on now`
  );
  await expect(dialog).toContainText(
    'Anything calling those URLs stops working.'
  );
  await expect(dialog).toContainText('One trigger comes back switched off');
  await expect(dialog).toContainText('a scheduled trigger');
  await expect(dialog).toContainText(/authentication/);
  await expect(restoreConfirm(page, 1)).toBeEnabled();
});

// @S11 @variant:experimental-features
// Scenario: Viewers can't restore
//   Given I am a viewer on "Intake"
//   When I open the version chip
//   Then no row offers "Restore"
//   And a restore request sent anyway is refused with a permission message
// The request sent anyway is checked by its effect: nothing restored.
test('@S11', PASSING_OLD, async ({ page }) => {
  experimental();
  const { wf, by } = givenIntake({ [ME]: 'viewer' });
  givenTwoPublishes(wf, by);
  const sock = await watchEditorSocket(page);
  await openAs(page, wf);

  await openVersions(page);
  await versionItem(page, 'v1').hover();
  await expect(restoreLinks(page)).toHaveCount(0);
  await closeVersions(page);

  const reply = await sendRestore(sock, 1);
  expect(reply.status).toBe('error');
  expect(publishesOf(wf.id)).toHaveLength(2);
  expect(storedWorkflow(wf.id).steps).toContain('Fetch v2');
});

// @S12 @variant:experimental-features
// Scenario Outline: A refused restore says why and leaves the workflow as it was
//   Given I am an editor restoring v1 of "Intake"
//   When <cause>
//   Then I see "Could not restore v1" with "<message>"
//   And the restore dialog stays open and usable
//   Examples:
//     | cause                                        | message                                                  |
//     | someone else saves "Intake" at the same time | Someone else saved this workflow. Try the restore again. |
//     | v1 no longer exists                          | That version no longer exists                            |
// Stand-in for the first row: a save landing in the middle of the restore is
// a race no browser can time, so the server's refusal for it is given in its
// place. The second row is real: v1's publish is removed before I confirm.
test('@S12', PASSING_OLD, async ({ page }) => {
  experimental();
  const { wf, by } = givenIntake();
  givenTwoPublishes(wf, by);
  const room = await standInRoom(page);
  await openAs(page, wf);
  await chooseRestore(page, 'v1');
  await expect(restoreConfirm(page, 1)).toBeEnabled();

  const raced = 'Someone else saved this workflow. Try the restore again.';
  room.refuse('restore', serverRefusal(raced, 'workflow_moved_on'));
  await restoreConfirm(page, 1).click();
  await expect(editorToast(page, raced)).toContainText('Could not restore v1');
  await expect(shown(restoreDialog(page, 1))).toBeVisible();
  await expect(restoreConfirm(page, 1)).toBeEnabled();
  room.allow('restore');

  deletePublish(wf.id, 1);
  await restoreConfirm(page, 1).click();
  await expect(
    editorToast(page, 'That version no longer exists')
  ).toContainText('Could not restore v1');
  await expect(restoreConfirm(page, 1)).toBeEnabled();
  expect(publishesOf(wf.id).map(r => r.n)).toEqual([2]);
  expect(storedWorkflow(wf.id).steps).toContain('Fetch v2');
});

// ---------------------------------------------------------------------------
// Seeing what ran
// ---------------------------------------------------------------------------

// @S13
// Scenario: Member sees recent activity without leaving the editor
//   Given "Intake" has work orders with runs
//   When I expand the history panel on the canvas, or press Ctrl+H (Cmd+H on a Mac)
//   Then "Recent History" lists the most recent work orders newest first, each with its state and when it last ran
//   And expanding a work order lists its runs with state, when and how long
//   And the panel stays expanded or collapsed the next time I open the editor
// "When" and "how long" are relative texts that change by the minute; the
// order says when.
test('@S13', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake({ [ME]: 'viewer' });
  const older = seedRunOn(wf, {
    inputId: anInput(id),
    state: 'failed',
    minutesAgo: 30,
  });
  const newer = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 5 });
  await openAs(page, wf);
  await expect(historyExpanded(page)).toHaveCount(0);

  await pressHistoryShortcut(page);
  await expect(historyExpanded(page)).toBeVisible();
  await expect
    .poll(() => listedWorkOrders(page))
    .toEqual([newer.workOrderId, older.workOrderId]);
  await expect(workOrderRow(page, newer.workOrderId)).toContainText(/success/i);
  await expect(workOrderRow(page, older.workOrderId)).toContainText(/failed/i);

  await expandWorkOrder(page, older.workOrderId);
  await expect(runLink(page, older.runId)).toBeVisible();

  await openEditor(page, id, wf.id);
  await expect(historyExpanded(page)).toBeVisible();
  await pressHistoryShortcut(page);
  await expect(historyExpanded(page)).toHaveCount(0);
  await openEditor(page, id, wf.id);
  await expect(historyExpanded(page)).toHaveCount(0);
});

// @S14
// Scenario Outline: The history panel says when there is nothing to show or it could not load
//   Given <condition>
//   When I expand the history panel
//   Then I see "<message>"
//   Examples:
//     | condition                | message                                                       |
//     | "Intake" has never run   | No related history                                            |
//     | history is still loading | Loading history...                                            |
//     | loading history failed   | Failed to load history, with a "Retry" button that asks again |
// Stand-in: the history request's answer is held back, then refused, in the
// server's place. The panel stays expanded across reloads.
test('@S14', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const room = await standInRoom(page);
  await openAs(page, wf);
  await expandHistory(page);
  await expect(historyPanel(page)).toContainText('No related history');

  room.hold('history');
  await page.reload();
  await editorReady(page);
  await expect(historyPanel(page)).toContainText('Loading history...');
  room.release();
  await expect(historyPanel(page)).toContainText('No related history');

  room.refuse('history');
  await page.reload();
  await editorReady(page);
  await expect(historyPanel(page)).toContainText('Failed to load history');
  const asked = room.asked('history');
  room.allow('history');
  await historyRetry(page).click();
  await expect.poll(() => room.asked('history')).toBeGreaterThan(asked);
  await expect(historyPanel(page)).toContainText('No related history');
});

// @S15
// Scenario: Picking a run shows it on the version it ran on
//   Given run "a1b2c3" of "Intake" ran on save 3, and save 5 is current
//   When I pick that run in the history panel
//   Then the URL carries "v=3" and "run=a1b2c3"
//   When I pick a run that ran on save 5 instead
//   Then the pin is removed and "run" names that run
//   And picking a work order with a single run picks that run
// Each work order here has a single run, so expanding it picks it.
test('@S15', PASSING_OLD, async ({ page }) => {
  const { id, wf, by } = givenIntake();
  const ran = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 10 });
  saveRenameOnNode(wf.id, 'Load', 'Load b', by);
  saveRenameOnNode(wf.id, 'Load b', 'Load c', by);
  const current = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 1 });
  await openAs(page, wf);
  await expandHistory(page);

  await expandWorkOrder(page, ran.workOrderId);
  await expect
    .poll(() => pinOf(page))
    .toMatchObject({ v: String(ran.version), run: ran.runId });
  await expect(node(page, 'Load')).toBeVisible();

  await expandWorkOrder(page, current.workOrderId);
  await expect.poll(() => pinOf(page).run).toBe(current.runId);
  expect(pinOf(page).v).toBeUndefined();
  await expect(node(page, 'Load c')).toBeVisible();
});

// @S16 @variant:experimental-features
// Scenario: On a live workflow, a run of older content opens as it executed
//   Given "Intake" is live and run "a1b2c3" ran on content that is no longer live
//   When I pick that run in the history panel
//   Then the URL carries "as_run=a1b2c3" and "run=a1b2c3"
//   And the chip reads that run's version, or "unpublished"
//   When I have unsaved changes in a sandbox or draft and pick a run of older content there
//   Then I am asked before my edits are thrown away
// The last two lines are tried on a draft, "Billing".
// Still pending, old: on a draft, picking a run of older content only selects the run, so nothing is asked
test('@S16', PENDING, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  const onV1 = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 20 });
  saveRenameOnNode(wf.id, 'Load', 'Load draft', by);
  const unpublished = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 10 });
  saveRenameOnNode(wf.id, 'Load draft', 'Load v2', by);
  publishOnNode(wf.id, by);
  const draft = seedEditorWorkflow(id, by, { name: 'Billing' });
  const old = seedRunOn(draft, { inputId: anInput(id) });
  saveRenameOnNode(draft.id, 'Load', 'Load b', by);
  await openAs(page, wf);
  await expandHistory(page);

  await expandWorkOrder(page, onV1.workOrderId);
  await expect
    .poll(() => pinOf(page))
    .toMatchObject({ as_run: onV1.runId, run: onV1.runId });
  await expect(versionChip(page)).toHaveText('v1');
  await expect(readOnlyPill(page)).toBeVisible();

  await expandWorkOrder(page, unpublished.workOrderId);
  await expect.poll(() => pinOf(page).as_run).toBe(unpublished.runId);
  await expect(versionChip(page)).toHaveText('unpublished');

  await openEditor(page, id, draft.id);
  await renameStep(page, 'Fetch', 'Fetch mine');
  await expandHistory(page);
  await expandWorkOrder(page, old.workOrderId);
  await expect(shown(discardDialog(page))).toBeVisible();
});

// @S17
// Scenario: A run read on another version says so and offers to switch
//   Given run "a1b2c3" ran on save 3 and the canvas shows save 5 with that run selected
//   When I look at the history panel
//   Then I see "This run took place on version 3." and "View as executed"
//   When I choose "View as executed"
//   Then the canvas switches to save 3, asking first if I have unsaved changes
// Without experimental features the switch never asks (6.2), so only the
// switch is checked.
test('@S17', PASSING_OLD, async ({ page }) => {
  const { id, wf, by } = givenIntake();
  const ran = seedRunOn(wf, { inputId: anInput(id) });
  saveRenameOnNode(wf.id, 'Load', 'Load b', by);
  saveRenameOnNode(wf.id, 'Load b', 'Load c', by);
  await openAs(page, wf, ME, `?run=${ran.runId}`);
  await expandHistory(page);

  await expect(mismatchBanner(page)).toContainText(
    `This run took place on version ${ran.version}.`
  );
  await viewAsExecutedButton(page).click();
  await expect.poll(() => pinOf(page).v).toBe(String(ran.version));
  await expect(node(page, 'Load')).toBeVisible();
});

// @S18 @variant:experimental-features
// Scenario: Reading a publish shows only the runs of that publish
//   Given "Intake" has runs on v1 and on v2
//   When I open v1 from the version chip
//   Then the history panel lists only the work orders with runs on v1
test('@S18', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  const onV1 = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 10 });
  saveRenameOnNode(wf.id, 'Fetch', 'Fetch v2', by);
  publishOnNode(wf.id, by);
  const onV2 = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 1 });
  await openAs(page, wf);
  await expandHistory(page);
  await expect(workOrderRow(page, onV2.workOrderId)).toBeVisible();

  await pickVersion(page, 'v1');

  await expect(workOrderRow(page, onV1.workOrderId)).toBeVisible();
  await expect(workOrderRow(page, onV2.workOrderId)).toHaveCount(0);
  expect(await listedWorkOrders(page)).toEqual([onV1.workOrderId]);
});

// @S19 @variant:experimental-features
// Scenario: Each run is tagged with the version it ran on
//   Given "Intake" is live and its runs ran on v2 and on content never published
//   When I expand a work order in the history panel
//   Then runs read "v2" or "unpublished" before the run id
//   And on a draft they read the save number instead
//   And without experimental features no tag is shown
test('@S19', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  givenTwoPublishes(wf, by);
  const onV2 = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 10 });
  saveRenameOnNode(wf.id, 'Load', 'Load draft', by);
  const unpublished = seedRunOn(wf, { inputId: anInput(id), minutesAgo: 5 });
  const draft = seedEditorWorkflow(id, by, { name: 'Billing' });
  const onDraft = seedRunOn(draft, { inputId: anInput(id) });
  await openAs(page, wf);
  await expandHistory(page);

  await expandWorkOrder(page, onV2.workOrderId);
  await expect.poll(() => versionTagOf(page, onV2.runId)).toBe('v2');
  await expandWorkOrder(page, unpublished.workOrderId);
  await expect
    .poll(() => versionTagOf(page, unpublished.runId))
    .toBe('unpublished');

  await openEditor(page, id, draft.id);
  await expandHistory(page);
  await expandWorkOrder(page, onDraft.workOrderId);
  await expect
    .poll(() => versionTagOf(page, onDraft.runId))
    .toBe(`v${onDraft.version}`);

  experimental(ME, false);
  await openEditor(page, id, wf.id);
  await expandHistory(page);
  await expandWorkOrder(page, onV2.workOrderId);
  await expect(runLink(page, onV2.runId)).toBeVisible();
  expect(await versionTagOf(page, onV2.runId)).toBeNull();
});

// @S20
// Scenario: History links lead to the full history, a work order or a run
//   Given the history panel lists work order "wo1" with run "r1"
//   When I choose the stack icon "View full history for this workflow"
//   Then I am taken to the history page filtered to "Intake"
//   When I choose the work order id
//   Then I am taken to the history page filtered to that work order
//   When I choose the run id
//   Then I am taken to that run's page
// Each link leaves the editor, which is opened again for the next one.
test('@S20', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake({ [ME]: 'viewer' });
  const r1 = seedRunOn(wf, { inputId: anInput(id) });
  const at = () => new URL(page.url());
  await openAs(page, wf);
  await expandHistory(page);

  await fullHistoryButton(page).click();
  await expectAt(page, `/projects/${id}/history`);
  expect(at().searchParams.get('filters[workflow_id]')).toBe(wf.id);

  await openEditor(page, id, wf.id);
  await expandHistory(page);
  await workOrderLink(page, r1.workOrderId).click();
  await expectAt(page, `/projects/${id}/history`);
  expect(at().searchParams.get('filters[workorder_id]')).toBe(r1.workOrderId);

  await openEditor(page, id, wf.id);
  await expandHistory(page);
  await expandWorkOrder(page, r1.workOrderId);
  await runLink(page, r1.runId).click();
  await expectAt(page, `/projects/${id}/runs/${r1.runId}`);
});

// ---------------------------------------------------------------------------
// Editing in a sandbox
// ---------------------------------------------------------------------------

// @S21 @variant:experimental-features
// Scenario: Editor copies a live workflow into a new sandbox and lands in it
//   Given "Intake" is live in an ordinary project and I am an editor
//   When I choose "Edit in sandbox"
//   Then I see "Edit in sandbox" with "Create a new sandbox" and "Starts from the version live now."
//   And "Create sandbox" is disabled until I type a name
//   When I type "Trying dates" and choose "Create sandbox"
//   Then a sandbox is created from the parent with this workflow's copy as a disabled draft
//   And the flow "flow-edit-in-sandbox" has started for that sandbox's copy of "Intake"
// A name is needed: checked by trying without one and seeing nothing made.
test('@S21', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  await openAs(page, wf);

  await openSandboxPicker(page);
  await expect(sandboxPicker(page)).toContainText('Create a new sandbox');
  await expect(sandboxPicker(page)).toContainText(
    'Starts from the version live now.'
  );
  await submit(sandboxPicker(page), 'Create sandbox');
  expect(sandboxesOf(id)).toHaveLength(0);

  await sandboxNameBox(page).fill('Trying dates');
  await submit(sandboxPicker(page), 'Create sandbox');

  await expect.poll(() => sandboxesOf(id)).toHaveLength(1);
  const [sandbox] = sandboxesOf(id);
  expect(sandbox.name).toMatch(/trying.dates/i);
  const copy = workflowNamed(sandbox.id, 'Intake');
  expect(copy.state).toBe('draft');
  expect(copy.triggers_enabled).toEqual([false]);
  await expectAt(page, editorPath(sandbox.id, copy.id));
});

// @S22 @variant:experimental-features
// Scenario: Starting a sandbox from the open run's input, checked first
//   Given run "a1b2c3" is open in "Intake" and its input was kept
//   When I choose "Edit in sandbox"
//   Then "This run's input" is selected and the button reads "Continue"
//   When I choose "Continue"
//   Then I see "Check the data before it leaves production" with the input in an editable JSON editor
//   When I remove a field and choose "Create sandbox"
//   Then the sandbox starts with my edited copy named "Input from run a1b2c3" and the original is untouched
//   When I instead edit it into something that is not a JSON object
//   Then I see "This needs to be a JSON object." or "This isn't valid JSON." and nothing is created
// The refused edits are tried first: the good one leaves the page.
test('@S22', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  const original = { patient: '123', nhs: '9990001111' };
  const inputId = anInput(id, original);
  const run = seedRunOn(wf, { inputId });
  await openAs(page, wf, ME, `?run=${run.runId}`);

  await openSandboxPicker(page);
  await expect(startWith(page, "This run's input")).toBeChecked();
  await expect(createButton(page)).toHaveText('Continue');
  await sandboxNameBox(page).fill('Trying dates');
  await createButton(page).click();
  await expect(shown(reviewDialog(page))).toBeVisible();
  await expect.poll(() => reviewText(page)).toContain('"nhs"');

  for (const [text, message] of [
    ['[1, 2]', 'This needs to be a JSON object.'],
    ['{"patient": ', "This isn't valid JSON."],
  ]) {
    await setReviewText(page, text);
    await reviewCreate(page).click();
    await expect.soft(reviewDialog(page).getByText(message)).toBeVisible();
  }
  expect(sandboxesOf(id)).toHaveLength(0);

  await setReviewText(page, '{"patient": "123"}');
  await reviewCreate(page).click();

  await expect.poll(() => sandboxesOf(id)).toHaveLength(1);
  const [sandbox] = sandboxesOf(id);
  await expect
    .poll(() => namedDataclipsOf(sandbox.id))
    .toEqual([
      expect.objectContaining({
        name: `Input from run ${run.runId.slice(0, 6)}`,
        body: { patient: '123' },
      }),
    ]);
  expect(dataclipOf(inputId).body).toEqual(original);
  await expectAt(page, copyPath(sandbox.id));
});

// @S23 @variant:experimental-features
// Scenario: A run whose input was not kept can't seed a sandbox
//   Given the open run's input was not kept
//   When I choose "This run's input" and "Continue"
//   Then I see "This run's input was not kept, so there is nothing to copy." and "Continue" is disabled
// That nothing can start from it is checked by trying again.
test('@S23', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  const inputId = seedDataclip(id, {
    type: 'http_request',
    body: { patient: '123' },
    wipedAt: utcStamp(new Date()),
  });
  const run = seedRunOn(wf, { inputId });
  await openAs(page, wf, ME, `?run=${run.runId}`);

  await openSandboxPicker(page);
  await startWith(page, "This run's input").check();
  await sandboxNameBox(page).fill('Trying dates');
  await submit(sandboxPicker(page), 'Continue');

  await expect(sandboxPicker(page)).toContainText(
    "This run's input was not kept, so there is nothing to copy."
  );
  await submit(sandboxPicker(page), 'Continue');
  await expect(reviewDialog(page)).toHaveCount(0);
  expect(sandboxesOf(id)).toHaveLength(0);
});

// @S24 @variant:experimental-features
// Scenario: The picker says when the sandbox forks a newer version than the run used
//   Given the open run ran on v2 and v3 is live
//   When I choose "This run's input"
//   Then I see "This run used v2. The sandbox starts from v3, the version live now"
test('@S24', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  givenTwoPublishes(wf, by);
  const run = seedRunOn(wf, { inputId: anInput(id, { patient: '123' }) });
  saveRenameOnNode(wf.id, 'Fetch v2', 'Fetch v3', by);
  publishOnNode(wf.id, by);
  await openAs(page, wf, ME, `?run=${run.runId}`);

  await openSandboxPicker(page);
  await startWith(page, "This run's input").check();

  await expect(sandboxPicker(page)).toContainText(
    'This run used v2. The sandbox starts from v3, the version live now'
  );
});

// @S25 @variant:experimental-features
// Scenario: Starting a sandbox from a saved input
//   Given the project has named inputs "Sample patient" (saved input) and "Step result" (step result)
//   When I choose "A saved input"
//   Then only "Sample patient" is listed, and "Create sandbox" waits until I pick it
//   When I pick it and create the sandbox
//   Then it is sent by id and the sandbox starts with a copy of it
//   When it was removed from the project in the meantime
//   Then I see "That saved input is no longer available in this project."
// Stand-in for "removed": the input loses its name, which takes it out of
// the project's named inputs. Tried before the create that leaves the page.
test('@S25', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  const [sample] = seedEarlierInputs(wf, 'Fetch', [
    {
      type: 'saved_input',
      body: { patient: 'sample' },
      name: 'Sample patient',
    },
    { type: 'step_result', body: { step: 'out' }, name: 'Step result' },
  ]);
  await openAs(page, wf);

  await openSandboxPicker(page);
  await sandboxNameBox(page).fill('Trying dates');
  await startWith(page, 'A saved input').check();
  await expect.poll(() => savedInputNames(page)).toEqual(['Sample patient']);
  await submit(sandboxPicker(page), 'Create sandbox');
  expect(sandboxesOf(id)).toHaveLength(0);

  await savedInputChoice(page, 'Sample patient').check();
  nameInput(sample, '');
  await submit(sandboxPicker(page), 'Create sandbox');
  await expect(
    editorToast(
      page,
      'That saved input is no longer available in this project.'
    )
  ).toBeVisible();
  expect(sandboxesOf(id)).toHaveLength(0);

  nameInput(sample, 'Sample patient');
  await submit(sandboxPicker(page), 'Create sandbox');
  await expect.poll(() => sandboxesOf(id)).toHaveLength(1);
  const [sandbox] = sandboxesOf(id);
  expect(namedDataclipsOf(sandbox.id)).toEqual([
    expect.objectContaining({
      name: 'Sample patient',
      body: { patient: 'sample' },
    }),
  ]);
});

// @S26 @variant:experimental-features
// Scenario: Editor continues in a sandbox that already holds the workflow
//   Given sandboxes "fix-dates" and "old-try" of the project hold a workflow named "Intake", and "gone" is scheduled for deletion
//   When I open "Edit in sandbox"
//   Then "Continue in a sandbox" lists "fix-dates" and "old-try", newest first, each with its owner and when it was created
//   And sandboxes without "Intake" and "gone" are not listed
//   When I choose "fix-dates"
//   Then the flow "flow-edit-in-sandbox" has started for the "Intake" copy in "fix-dates"
//   And the section is hidden when no sandbox qualifies
// The last line is checked first, on live workflow "Billing", which no
// sandbox holds.
test('@S26', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  provisionSandboxOnNode(id, 'old-try', by, { hoursAgo: 48 });
  const other = provisionSandboxOnNode(id, 'other', by, { hoursAgo: 3 });
  exec(
    `update workflows set name = 'Not Intake' where project_id = '${other}'`
  );
  const fixDates = provisionSandboxOnNode(id, 'fix-dates', by, {
    hoursAgo: 2,
  });
  scheduleDeletionOnNode(provisionSandboxOnNode(id, 'gone', by));
  const billing = seedEditorWorkflow(id, by, { name: 'Billing' });
  goLiveOnNode(billing.id, by);

  await openAs(page, billing);
  await openSandboxPicker(page);
  await expect(sandboxPicker(page)).toContainText('Create a new sandbox');
  await expect(continueSection(page)).toHaveCount(0);

  await openEditor(page, id, wf.id);
  await openSandboxPicker(page);
  await expect
    .poll(() => listedSandboxes(page))
    .toEqual(['fix-dates', 'old-try']);
  for (const name of ['fix-dates', 'old-try']) {
    await expect
      .soft(joinSandbox(page, name))
      .toContainText(nameOf(OWNER).full);
    await expect.soft(joinSandbox(page, name)).toContainText(/Created .+ago/);
  }

  await joinSandbox(page, 'fix-dates').click();
  await expectAt(page, copyPath(fixDates));
});

// @S27 @variant:experimental-features
// Scenario: A sandbox name already used under the project is refused in place
//   Given the project already has a sandbox "trying-dates"
//   When I create a sandbox named "Trying dates"
//   Then I see "A sandbox with this name exists already." under the name field
test('@S27', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  provisionSandboxOnNode(id, 'trying-dates', by);
  await openAs(page, wf);

  await openSandboxPicker(page);
  await sandboxNameBox(page).fill('Trying dates');
  await submit(sandboxPicker(page), 'Create sandbox');

  await expect(
    sandboxPicker(page).getByText('A sandbox with this name exists already.')
  ).toBeVisible();
  expect(sandboxesOf(id)).toHaveLength(1);
});

// @S28 @variant:experimental-features @variant:sandbox-limited
// Scenario: The plan's sandbox limit stops a new sandbox but not joining one
//   Given the plan allows no more sandboxes
//   When I open "Edit in sandbox"
//   Then "Create sandbox" is disabled with a lock and the limiter's message as its tooltip
//   And typing a name or pressing Enter does not get past it
//   And a create request sent anyway is refused with the limiter's message
//   And I can still join a listed sandbox
// The limiter is instance-wide. The lock is an icon; the tooltip says why.
// The request sent anyway is checked by its effect: nothing made.
test('@S28', PASSING_OLD_SERIAL, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  const fixDates = provisionSandboxOnNode(id, 'fix-dates', by);
  const putBack = withLimiterRefusing('new_sandbox', LIMIT);
  cleanups.push(() => void putBack());
  const sock = await watchEditorSocket(page);
  await openAs(page, wf);

  await openSandboxPicker(page);
  await sandboxNameBox(page).fill('Trying dates');
  await expect(createButton(page)).toBeDisabled();
  expect(await headerTooltip(page, createButton(page))).toBe(LIMIT);
  await sandboxNameBox(page).press('Enter');
  expect(sandboxesOf(id).map(s => s.name)).toEqual(['fix-dates']);

  const reply = await sendCreateSandbox(sock, 'forced');
  expect(reply.status).toBe('error');
  expect(sandboxesOf(id).map(s => s.name)).toEqual(['fix-dates']);

  await joinSandbox(page, 'fix-dates').click();
  await expectAt(page, copyPath(fixDates));
});

// @S29 @variant:experimental-features
// Scenario: People who can't create sandboxes can't start one from the editor
//   Given I am a viewer on "Intake", which is live
//   Then "Edit in sandbox" is disabled with "You do not have permission to create a sandbox in this project."
//   And listing or creating sandboxes is refused by the server
//   And while I read an older publish as an editor, "Edit in sandbox" is disabled too
test('@S29', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake({ [ME]: 'viewer' });
  givenTwoPublishes(wf, by);
  provisionSandboxOnNode(id, 'fix-dates', by);
  const sock: EditorSocket = await watchEditorSocket(page);
  await openAs(page, wf);

  await expect(editInSandboxButton(page)).toBeDisabled();
  expect(await headerTooltip(page, editInSandboxButton(page))).toBe(
    'You do not have permission to create a sandbox in this project.'
  );
  expect((await sendListSandboxes(sock)).status).toBe('error');
  expect((await sendCreateSandbox(sock, 'forced')).status).toBe('error');
  expect(sandboxesOf(id).map(s => s.name)).toEqual(['fix-dates']);

  changeRoleOnNode(id, ME, 'editor', { quietly: true });
  await page.goto('about:blank');
  await openEditor(page, id, wf.id, '?release=1');
  await expect(editInSandboxButton(page)).toBeDisabled();
});

// @S30 @variant:experimental-features
// Scenario: Leaving for a sandbox with unsaved changes asks first
//   Given I have unsaved changes in "Intake"
//   When I choose a sandbox to continue in
//   Then I see "You have unsaved changes" and nothing navigates yet
//   When I choose "Save and switch"
//   Then the workflow is saved and then I am taken to the sandbox, without the browser's own leave warning
// Experimental features lock a live workflow for me, so the unsaved change
// is made by Ben (without them) in the shared copy, as shared-editor-session
// S20 does. Also S20 in this view's terms.
// Still pending, old: "Save and switch" on a live workflow with experimental features didn't save the colleague's edits, so the page stayed (unconfirmed)
test('@S30', PENDING, async ({ page, browser }) => {
  experimental();
  experimental(BEN, false);
  const { id, wf, by } = givenIntake({ [ME]: 'editor', [BEN]: 'editor' });
  goLiveOnNode(wf.id, by);
  const fixDates = provisionSandboxOnNode(id, 'fix-dates', by);
  const ben = await otherSession(browser, BEN);
  await openEditor(ben, id, wf.id);
  await renameStep(ben, 'Fetch', 'Fetch unsaved');
  await openAs(page, wf);
  await expect(node(page, 'Fetch unsaved')).toBeVisible();
  let warned = 0;
  page.on('dialog', d => {
    if (d.type() === 'beforeunload') warned++;
    void d.accept();
  });

  await openSandboxPicker(page);
  await joinSandbox(page, 'fix-dates').click();
  await expect(shown(discardDialog(page))).toBeVisible();
  expect(new URL(page.url()).pathname).toBe(editorPath(id, wf.id));

  await discardChoice(page, 'Save and switch').click();
  await expect
    .poll(() => storedWorkflow(wf.id).steps)
    .toContain('Fetch unsaved');
  await expectAt(page, copyPath(fixDates));
  expect(warned).toBe(0);
});

// ---------------------------------------------------------------------------
// Hand-offs
// ---------------------------------------------------------------------------

// @S31
// Scenario: Save & Sync hands off to the GitHub sync flow
//   Given "Intake" is in a project connected to GitHub and I am an editor
//   When I choose "Save & Sync"
//   Then the dialog "Save and sync changes to GitHub" names the repository and branch
//   And the flow "flow-github-sync-actions" has started when I confirm
// Confirming reaches GitHub, which the flow's own checks cover; this stops at
// the dialog.
test('@S31', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  connectRepoOnNode(id, {
    repo: 'openfn/malawi-hiv',
    branch: 'sync-main',
    installation: '4242',
  });
  await openAs(page, wf);

  await chooseSaveAndSync(page);

  await expect(syncDialog(page)).toContainText('openfn/malawi-hiv');
  await expect(syncDialog(page)).toContainText('sync-main');
});

// @S32 @variant:experimental-features
// Scenario: Promote hands off to the sandbox merge flow, and only acts on the current workflow
//   Given "Intake" is open in a sandbox
//   When I choose "Promote"
//   Then the flow "flow-sandbox-merge" has started
//   When I am reading an older save of it instead
//   Then "Promote" is disabled with "You are reading the past. Promote acts on the current workflow."
test('@S32', PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, by } = givenIntake();
  const sandbox = provisionSandboxOnNode(id, 'dev', by);
  const copy = workflowNamed(sandbox, 'Intake').id;
  saveRenameOnNode(copy, 'Load', 'Load b', by);
  saveRenameOnNode(copy, 'Load b', 'Load c', by);
  const older = savesOf(copy)[1];
  await signInAs(page, ME);
  await openEditor(page, sandbox, copy);

  await promoteButton(page).click();
  await expect(shown(promoteDialog(page))).toBeVisible();

  await page.goto('about:blank');
  await openEditor(page, sandbox, copy, `?v=${older}`);
  await expect(promoteButton(page)).toBeDisabled();
  expect(await headerTooltip(page, promoteButton(page))).toBe(
    'You are reading the past. Promote acts on the current workflow.'
  );
});

// @S33
// Scenario: Any open view of the workflow counts as open for API writes
//   Given I have "Intake" open on an older save
//   Then the flow "flow-workflow-api-edit-conflict" treats "Intake" as open in the editor
test('@S33', PASSING_OLD, async ({ page, request }) => {
  const { id, wf, by } = givenIntake({ [ME]: 'viewer' });
  const older = storedWorkflow(wf.id).lock_version;
  saveRenameOnNode(wf.id, 'Load', 'Load b', by);
  await openAs(page, wf, ME, `?v=${older}`);
  await expect(versionChip(page)).toHaveText(`v${older}`);

  const res = await patchWithBearer(
    request,
    `/api/projects/${id}/workflows/${wf.id}`,
    seededApiTokenOf(OWNER).token,
    { name: 'Renamed by a script' }
  );

  expect(res.status()).toBe(409);
  expect(storedWorkflow(wf.id).name).toBe('Intake');
});

// @S34 @variant:experimental-features
// Scenario: A restore reaches colleagues who have the workflow open
//   Given "Ben" has "Intake" open on Latest
//   When I restore v1
//   Then the flow "flow-restore-version-open-editor" has started for "Ben"
// Ben, without experimental features, sees v1's content on his canvas.
// Still pending, old: a colleague's canvas showed the restored content in one of three runs (unconfirmed)
test('@S34', PENDING, async ({ page, browser }) => {
  experimental();
  experimental(BEN, false);
  const { wf, by } = givenIntake({ [ME]: 'editor', [BEN]: 'editor' });
  givenTwoPublishes(wf, by);
  const ben = await otherSession(browser, BEN);
  await openEditor(ben, wf.projectId, wf.id);
  await expect(node(ben, 'Fetch v2')).toBeVisible();
  await openAs(page, wf);

  await chooseRestore(page, 'v1');
  await restoreConfirm(page, 1).click();
  await expect(editorToast(page, 'Restored v1')).toBeVisible();
  await expect(node(page, 'Fetch')).toBeVisible();

  await expect(node(ben, 'Fetch')).toBeVisible({ timeout: 15000 });
  await expect(node(ben, 'Fetch v2')).toHaveCount(0);
});

// ---------------------------------------------------------------------------
// Shared scenarios in this view's terms (see the header)
// ---------------------------------------------------------------------------

const ON = 'on workflow-editor-versions-and-promote';

// @S14 Non-members can't join the room, here the rooms of a publish and of a
// run shown as it executed
test(`shared-editor-session@S14 ${ON}`, PASSING_OLD, async ({ page }) => {
  const { id, wf, by } = givenIntake({ [OWNER]: 'owner' });
  goLiveOnNode(wf.id, by);
  const run = seedRunOn(wf, { inputId: anInput(id) });
  await signInAs(page, ME);
  await open(page, '/projects');
  const params = { project_id: id, action: 'edit' };

  for (const topic of [
    releaseRoom(wf.id, 1),
    releaseRoom(wf.id, 99),
    runRoom(wf.id, run.runId),
  ]) {
    const reply = await joinRoom(page, topic, params);
    expect.soft(reply.status, topic).toBe('error');
    expect.soft(JSON.stringify(reply.response), topic).toMatch(/unauthorized/);
  }
});

// @S03 Joining a sandbox I'm not a member of says the project was not found
test(`shared-project-scope@S03 ${ON}`, PASSING_OLD, async ({ page }) => {
  experimental();
  const { id, wf, by } = givenIntake();
  goLiveOnNode(wf.id, by);
  const sandbox = provisionSandboxOnNode(id, 'fix-dates', by);
  removeMemberOnNode(sandbox, ME, OWNER);
  await openAs(page, wf);

  await openSandboxPicker(page);
  await joinSandbox(page, 'fix-dates').click();

  await expectAt(page, '/projects');
  await expect(page.getByText('Not Found', { exact: true })).toBeVisible();
});

// @S05 The run input "Edit in sandbox" loads is refused for a run and a
// dataclip of a project I'm not on
test(`shared-dataclip-body-viewer@S05 ${ON}`, PASSING_OLD, async ({ page }) => {
  const { id } = givenIntake();
  const kenya = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const theirs = seedEditorWorkflow(kenya.id, kenya.by);
  const d = anInput(kenya.id, { patient: 'record' });
  const run = seedRunOn(theirs, { inputId: d });
  await signInAs(page, ME);

  const viaRun = await runInputAsPage(page, id, run.runId, theirs.steps.Fetch);
  expect.soft(await viaRun.text()).not.toContain('record');
  const body = await bodyAsPage(page, d);
  expect.soft(body.status()).toBe(403);
  expect.soft(await body.text()).not.toContain('record');
});
