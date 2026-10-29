// Scenarios from annotations/shared/shared-editor-session.md, run on any
// editor panel. The host owns the Given: it seeds the project, its members
// and the workflow (`given` below says what each needs), and passes the
// workflow as `w`. The functions sign in, open the editor and hold the When
// and Then. Anything that knows how the editor is built lives in
// pages/workflow-editor.ts.
//
// The "can't change" scenarios (S10, S11) send what the page would send past
// its own guard, through watchEditorSocket, and check the server's copy of
// the document and the database. Create the watcher before the page opens.
import { expect, test, type Page } from '@playwright/test';

import {
  canvas,
  collaboratorAvatar,
  editorPath,
  editorReady,
  editorToast,
  headerTooltip,
  loadingWorkflow,
  node,
  openEditor,
  openSettings,
  readOnlyPill,
  remoteCursor,
  renameStep,
  renameWorkflow,
  renameWorkflowIn,
  roomFor,
  saveButton,
  settingsFlagged,
  toastButton,
  unsavedMarker,
  watchEditorSocket,
  workflowTitle,
  headerButton,
  joinRoom,
  type EditorSocket,
} from '../pages/workflow-editor';
import {
  expectAt,
  field,
  open,
  sharedDocOf,
  signInAs,
  storedWorkflow,
} from '../steps';

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

export type EditorTarget = {
  projectId: string;
  id: string;
  name: string;
  /** step name -> job id */
  steps: Record<string, string>;
};

// What each scenario needs the host to seed. "Intake" is seedEditorWorkflow's
// default: a webhook trigger leading to "Fetch", then "Load".
export const given = {
  S01: 'a viewer on the project of workflow "Intake"',
  S02: 'two editors on the project of "Intake"',
  S03: 'an editor on the project of "Intake"',
  S04: 'an editor on the project of "Intake", and a way to save it outside the editor (rename step "Load" to "Load v2")',
  S05: 'two editors on the project of "Intake"',
  S06: 'an editor on the project of "Intake"',
  S07: 'two editors on the project of "Intake"',
  S08: 'two editors on the project of "Intake"',
  S09: 'an editor on the project of "Intake", and a way to make saves fail until put back (the adaptor catalogue unavailable)',
  S10: 'a viewer, or an editor with a version query (?v=<earlier lock version>) of "Intake"',
  S11: 'an editor on the project of "Intake" and an owner who demotes them',
  S12: 'two editors on the project of "Intake" and an admin who removes one',
  S13: 'a support user (no role, support access on) and an editor on the project of "Intake"',
  S14: 'a user not on the project, or an editor without MFA on a project that requires it',
  S15: 'an editor on "Intake" in one project and another member on a workflow in a second project',
  S16: 'an editor on "Intake" and another workflow in the same project open by a second member',
  S17: 'two members of the project of "Intake"',
  S18: 'two members of the project of "Intake"',
  S19: 'an editor on the project of "Intake"',
  S20: 'an editor with experimental features on, and a second editor without them, on live workflow "Intake" in a project with a sandbox',
  S21: 'an editor and a viewer on the project of "Intake"',
  S22: 'an editor on the project of "Intake"',
};

// Signs <email> in on <page> and opens workflow <w>, with <query>
async function openAs(page: Page, email: string, w: EditorTarget, query = '') {
  await signInAs(page, email);
  await openEditor(page, w.projectId, w.id, query);
}

// The workflow's saved version in the database
const savedVersion = (w: EditorTarget) => storedWorkflow(w.id).lock_version;

// The session on <sock> has been closed by the server
const sessionClosed = (sock: EditorSocket) =>
  expect
    .poll(() => sock.pushed('phx_close').length, EVENTUALLY)
    .toBeGreaterThan(0);

// @S01 The editor waits for the shared copy before showing the workflow
//   Given I am a viewer on project "Malawi HIV" with workflow "Intake"
//   When I open "Intake"
//   Then I see "Loading workflow" until the document has synced and the session context has loaded
//   And then I see "Intake"
export async function S01(page: Page, email: string, w: EditorTarget) {
  const sock = await watchEditorSocket(page);
  await signInAs(page, email);
  sock.hold();
  await open(page, editorPath(w.projectId, w.id));

  await expect(loadingWorkflow(page)).toBeVisible();
  await expect(node(page, 'Fetch')).toHaveCount(0);

  sock.release();
  await editorReady(page);
  await expect(node(page, 'Fetch')).toBeVisible();
  await expect(workflowTitle(page, w.name)).toBeVisible();
}

// @S02 Collaborators see each other's edits without saving
//   Given editors "Amara" and "Ben" both have "Intake" open
//   When "Amara" renames step "Fetch" to "Fetch patients"
//   Then "Ben" eventually sees "Fetch patients" without reloading
export async function S02(
  amara: Page,
  ben: Page,
  emails: [string, string],
  w: EditorTarget
) {
  await openAs(amara, emails[0], w);
  await openAs(ben, emails[1], w);

  await renameStep(amara, 'Fetch', 'Fetch patients');

  await expect(node(ben, 'Fetch patients')).toBeVisible(EVENTUALLY);
}

// @S03 Unsaved edits survive a reload
//   Given I am an editor with "Intake" open
//   When I add a step and do not save
//   And I reload the page
//   Then the new step is still there, and Save shows unsaved changes
// Renaming a step stands in for adding one: any unsaved change is kept.
export async function S03(page: Page, email: string, w: EditorTarget) {
  await openAs(page, email, w);
  await renameStep(page, 'Load', 'Load patients');
  // The shared copy is written to the database after a short pause
  await page.waitForTimeout(3000);

  await page.reload();
  await editorReady(page);

  await expect(node(page, 'Load patients')).toBeVisible();
  await expect(unsavedMarker(page)).toBeVisible();
}

// @S04 A shared draft older than the last save is replaced by the saved workflow
//   Given "Intake" has a stored shared draft from lock version 3
//   And "Intake" was since saved to lock version 5
//   When I open "Intake"
//   Then I see the workflow as saved at lock version 5
// `saveElsewhere` renames "Load" to "Load v2" and saves, outside the editor.
export async function S04(
  page: Page,
  email: string,
  w: EditorTarget,
  saveElsewhere: () => void
) {
  await openAs(page, email, w);
  await renameStep(page, 'Fetch', 'Fetch draft');
  await page.waitForTimeout(3000);
  // Leaving writes the draft and closes the shared copy
  await page.goto('about:blank');
  await expect.poll(() => sharedDocOf(w.id), EVENTUALLY).toBeNull();

  saveElsewhere();

  await openEditor(page, w.projectId, w.id);
  await expect(node(page, 'Load v2')).toBeVisible();
  await expect(node(page, 'Fetch')).toBeVisible();
  await expect(node(page, 'Fetch draft')).toHaveCount(0);
}

// @S05 A dropped connection keeps the workflow on screen and blocks saving
//   Given I am an editor with "Intake" open
//   When my connection drops
//   Then I still see "Intake"
//   And "Save" is disabled with "You are disconnected. Reconnecting..."
//   And "Ctrl+S" does nothing
//   When I make an edit and the connection returns
//   Then my edit reaches the other collaborators
export async function S05(
  page: Page,
  other: Page,
  emails: [string, string],
  w: EditorTarget
) {
  const sock = await watchEditorSocket(page);
  await openAs(page, emails[0], w);
  await openAs(other, emails[1], w);
  await renameStep(page, 'Fetch', 'Fetch first');
  const version = savedVersion(w);

  sock.drop();

  await expect(node(page, 'Fetch first')).toBeVisible();
  await expect(saveButton(page)).toBeDisabled();
  expect(await headerTooltip(page, saveButton(page).locator('xpath=..'))).toBe(
    'You are disconnected. Reconnecting...'
  );
  await page.keyboard.press('ControlOrMeta+s');
  await page.waitForTimeout(1000);
  expect(savedVersion(w)).toBe(version);

  await renameStep(page, 'Load', 'Load offline');
  sock.reconnect();

  await expect(node(other, 'Load offline')).toBeVisible(EVENTUALLY);
}

// @S06 Editor saves the workflow
//   Given I am an editor with "Intake" open and unsaved changes
//   When I click "Save"
//   Then I see "Workflow saved" with "Last saved at <time>"
//   And the unsaved changes marker is gone
export async function S06(page: Page, email: string, w: EditorTarget) {
  await openAs(page, email, w);
  await renameStep(page, 'Fetch', 'Fetch patients');
  await expect(unsavedMarker(page)).toBeVisible();

  await saveButton(page).click();

  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
  await expect(editorToast(page, /Last saved at/)).toBeVisible();
  await expect(unsavedMarker(page)).toHaveCount(0);
  expect(storedWorkflow(w.id).steps).toContain('Fetch patients');
}

// @S07 Everyone in the room learns about a save
//   Given editors "Amara" and "Ben" have "Intake" open with the same unsaved change
//   When "Amara" saves
//   Then "Ben" eventually sees no unsaved changes marker
//   And "Ben"'s session knows the new saved version
export async function S07(
  amara: Page,
  ben: Page,
  emails: [string, string],
  w: EditorTarget
) {
  await openAs(amara, emails[0], w);
  await openAs(ben, emails[1], w);
  await renameStep(amara, 'Fetch', 'Fetch patients');
  await expect(unsavedMarker(ben)).toBeVisible(EVENTUALLY);

  await saveButton(amara).click();
  await expect(editorToast(amara, 'Workflow saved')).toBeVisible();

  await expect(unsavedMarker(ben)).toHaveCount(0, EVENTUALLY);
  // Ben's next save builds on Amara's: it is accepted, not refused as stale
  await renameStep(ben, 'Load', 'Load patients');
  await saveButton(ben).click();
  await expect(editorToast(ben, 'Workflow saved')).toBeVisible();
  expect(storedWorkflow(w.id).steps).toEqual([
    'Fetch patients',
    'Load patients',
  ]);
}

// @S08 An invalid workflow is refused and its errors are shown to everyone
//   Given editors "Amara" and "Ben" have "Intake" open
//   And "Amara" has cleared the workflow name
//   When "Amara" saves
//   Then "Amara" sees "Save failed: invalid workflow"
//   And both see the name field flagged as invalid
//   And nothing is broadcast as saved
//   When "Amara" fixes the name and saves
//   Then the error is gone for both
// Saved with Ctrl+S: the Save button may already be off once the settings
// show an error (Header.tsx: canSave && !hasSettingsErrors).
export async function S08(
  amara: Page,
  ben: Page,
  emails: [string, string],
  w: EditorTarget
) {
  const benSock = await watchEditorSocket(ben);
  await openAs(amara, emails[0], w);
  await openAs(ben, emails[1], w);
  const version = savedVersion(w);

  await renameWorkflow(amara, '');
  await amara.keyboard.press('ControlOrMeta+s');

  await expect(
    editorToast(amara, 'Save failed: invalid workflow')
  ).toBeVisible();
  await expect.poll(() => settingsFlagged(amara), EVENTUALLY).toBe(true);
  await expect.poll(() => settingsFlagged(ben), EVENTUALLY).toBe(true);
  expect(savedVersion(w)).toBe(version);
  expect(benSock.pushed('workflow_saved')).toHaveLength(0);

  await renameWorkflow(amara, `${w.name} fixed`);
  await amara.keyboard.press('ControlOrMeta+s');

  await expect(editorToast(amara, 'Workflow saved')).toBeVisible();
  await expect.poll(() => settingsFlagged(amara), EVENTUALLY).toBe(false);
  await expect.poll(() => settingsFlagged(ben), EVENTUALLY).toBe(false);
}

// @S09 A failed save says so and can be retried
//   Given I am an editor with "Intake" open
//   When my save fails for a reason other than validation or permission
//   Then I see "Failed to save workflow" with the reason and a "Retry" button
//   And repeated failures reuse the same message rather than stacking
//   When I click "Retry" and the save succeeds
//   Then the failure message is replaced by "Workflow saved"
// `failSaves` makes saves fail and returns what puts it back.
export async function S09(
  page: Page,
  email: string,
  w: EditorTarget,
  failSaves: () => () => void
) {
  await openAs(page, email, w);
  await renameStep(page, 'Fetch', 'Fetch patients');
  const putBack = failSaves();
  const failed = editorToast(page, 'Failed to save workflow');
  try {
    await saveButton(page).click();
    await expect(failed).toBeVisible({ timeout: 90000 });
    await saveButton(page).click();
    await page.waitForTimeout(2000);
    await expect(
      page.locator('[data-sonner-toast]').filter({
        hasText: 'Failed to save workflow',
      })
    ).toHaveCount(1, { timeout: 90000 });
  } finally {
    putBack();
  }

  await toastButton(page, 'Failed to save workflow', 'Retry').click();

  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
  await expect(failed).toHaveCount(0);
  expect(storedWorkflow(w.id).steps).toContain('Fetch patients');
}

// @S10 The shared copy can't be changed by someone who may only read it
//   Given <who> with "Intake" open
//   Then the editor is read-only with "<tooltip>"
//   And "Save" is disabled
//   And any document change sent from my browser is dropped by the server
//   And a save request is refused
// One Examples row per call: `query` pins a version for the second row;
// `room` names the version room it joins ("v1"), the live one otherwise.
export async function S10(
  page: Page,
  email: string,
  w: EditorTarget,
  tooltip: string,
  { query = '', room = '' } = {}
) {
  const sock = await watchEditorSocket(page);
  await openAs(page, email, w, query);
  const version = savedVersion(w);

  await expect.soft(readOnlyPill(page)).toBeVisible();
  expect.soft(await headerTooltip(page, readOnlyPill(page))).toBe(tooltip);
  await expect.soft(saveButton(page)).toBeDisabled();

  await sock.sendDocChange(renameWorkflowIn('Changed from a read-only page'));
  expect.soft(sharedDocOf(w.id, room)?.name).toBe(w.name);

  const reply = await sock.push('save_workflow');
  expect.soft(reply.status).toBe('error');
  expect.soft(savedVersion(w)).toBe(version);
  expect.soft(storedWorkflow(w.id).name).toBe(w.name);
  // The page is still up
  await expect.soft(node(page, 'Fetch')).toBeVisible();
}

// @S11 Demoting an editor stops their changes straight away
//   Given I am an editor with "Intake" open
//   When an owner changes my role to viewer in another session
//   Then my further document changes are dropped by the server
//   And a save I send is refused with "You don't have permission to edit this workflow"
//   And my page reloads with viewer permissions (shared-project-scope S08)
export async function S11(
  page: Page,
  email: string,
  w: EditorTarget,
  demote: () => void
) {
  const sock = await watchEditorSocket(page);
  await openAs(page, email, w);
  const version = savedVersion(w);

  demote();
  await expect(readOnlyPill(page)).toBeVisible(EVENTUALLY);

  await sock.sendDocChange(renameWorkflowIn('Changed after demotion'));
  expect(sharedDocOf(w.id)?.name).toBe(w.name);

  const reply = await sock.push('save_workflow');
  expect(reply.status).toBe('error');
  expect(JSON.stringify(reply.response)).toMatch(
    /don.t have permission to edit this workflow/
  );
  expect(savedVersion(w)).toBe(version);
}

// @S12 Removing a member closes their session on the workflow
//   Given I am an editor with "Intake" open
//   When an admin removes me from the project
//   Then my editor session closes
//   And my page leaves the project (shared-project-scope S07)
//   And other collaborators' sessions stay open
export async function S12(
  page: Page,
  other: Page,
  emails: [string, string],
  w: EditorTarget,
  remove: () => void
) {
  const mine = await watchEditorSocket(page);
  const theirs = await watchEditorSocket(other);
  await openAs(page, emails[0], w);
  await openAs(other, emails[1], w);

  remove();

  await sessionClosed(mine);
  await expectAt(page, '/projects');
  await other.waitForTimeout(1000);
  expect(theirs.pushed('phx_close')).toHaveLength(0);
  await renameStep(other, 'Fetch', 'Fetch still');
  await expect.poll(() => sharedDocOf(w.id)?.steps).toContain('Fetch still');
}

// @S13 Revoking support access closes a support user's session but not a member's
//   Given a support user with no role and an editor both have "Intake" open
//   When an owner disables support access on the project
//   Then the support user's editor session closes
//   And the editor's session stays open
export async function S13(
  support: Page,
  editor: Page,
  emails: { support: string; editor: string },
  w: EditorTarget,
  revoke: () => void
) {
  const supportSock = await watchEditorSocket(support);
  const editorSock = await watchEditorSocket(editor);
  await openAs(support, emails.support, w);
  await openAs(editor, emails.editor, w);

  revoke();

  await sessionClosed(supportSock);
  await editor.waitForTimeout(1000);
  expect(editorSock.pushed('phx_close')).toHaveLength(0);
  await expect(node(editor, 'Fetch')).toBeVisible();
}

// @S14 Non-members and unenrolled members can't join the room
//   Given workflow "Intake" in project "Malawi HIV"
//   When <who> joins the collaboration room for "Intake"
//   Then the join is refused with "unauthorized"
//   And asking for an existing and a non-existent older version gives the same refusal
// One Examples row per call. <who> is signed in on <page>, on any page.
export async function S14(page: Page, email: string, w: EditorTarget) {
  await signInAs(page, email);
  await open(page, '/projects');
  const params = { project_id: w.projectId, action: 'edit' };
  const version = savedVersion(w);

  for (const topic of [
    roomFor(w.id),
    roomFor(w.id, version),
    roomFor(w.id, version + 100),
  ]) {
    const reply = await joinRoom(page, topic, params);
    expect.soft(reply.status, topic).toBe('error');
    expect.soft(JSON.stringify(reply.response), topic).toMatch(/unauthorized/);
  }
}

// @S15 Scheduling a project for deletion closes its editor sessions only
//   Given I have "Intake" open in "project-1" and another member has a workflow open in "project-2"
//   When "project-1" is scheduled for deletion
//   Then my editor session closes
//   And the session in "project-2" stays open
export async function S15(
  page: Page,
  other: Page,
  emails: [string, string],
  mine: EditorTarget,
  theirs: EditorTarget,
  schedule: () => void
) {
  const mySock = await watchEditorSocket(page);
  const theirSock = await watchEditorSocket(other);
  await openAs(page, emails[0], mine);
  await openAs(other, emails[1], theirs);

  schedule();

  await sessionClosed(mySock);
  await other.waitForTimeout(1000);
  expect(theirSock.pushed('phx_close')).toHaveLength(0);
  await expect(canvas(other)).toBeVisible();
}

// @S16 Deleting the open workflow closes only that workflow's sessions
//   Given I have "Intake" open
//   When another member deletes "Intake"
//   Then the flow "flow-delete-open-workflow" ends here: my editor session for "Intake" closes
//   And sessions on other workflows in the project stay open
export async function S16(
  page: Page,
  other: Page,
  emails: [string, string],
  mine: EditorTarget,
  theirs: EditorTarget,
  remove: () => void
) {
  const mySock = await watchEditorSocket(page);
  const theirSock = await watchEditorSocket(other);
  await openAs(page, emails[0], mine);
  await openAs(other, emails[1], theirs);

  remove();

  await sessionClosed(mySock);
  await other.waitForTimeout(1000);
  expect(theirSock.pushed('phx_close')).toHaveLength(0);
  await expect(canvas(other)).toBeVisible();
}

// @S17 Members see who else has the workflow open
//   Given "Amara Banda" and I both have "Intake" open
//   Then I see an avatar "AB" in the header with tooltip "Amara Banda (amara@example.org)"
//   And it has a green border while she has been active in the last 12 seconds
//   When she opens "Intake" in a second tab
//   Then I still see one avatar, with " - 2 tabs" in the tooltip
//   When she closes every tab
//   Then her avatar stays for up to a minute and then disappears
// `amara` is her name, initials and email; `secondTab` is another page of
// her browser.
export async function S17(
  page: Page,
  her: Page,
  secondTab: Page,
  email: string,
  amara: { email: string; full: string; initials: string },
  w: EditorTarget
) {
  await openAs(page, email, w);
  await openAs(her, amara.email, w);
  const avatar = collaboratorAvatar(page, amara.initials);

  await expect(avatar).toBeVisible(EVENTUALLY);
  expect(await headerTooltip(page, avatar)).toBe(
    `${amara.full} (${amara.email})`
  );
  // Active in the last 12 seconds: a green border
  const border = await avatar.evaluate(el => {
    for (let n: Element | null = el; n; n = n.parentElement) {
      const c = getComputedStyle(n).borderTopColor;
      const [r, g, b] = (c.match(/\d+/g) ?? []).map(Number);
      if (g > r && g > b) return 'green';
    }
    return 'none';
  });
  expect(border).toBe('green');

  await openEditor(secondTab, w.projectId, w.id);
  await expect(avatar).toHaveCount(1);
  await expect
    .poll(() => headerTooltip(page, avatar), EVENTUALLY)
    .toContain(' - 2 tabs');

  await her.close();
  await secondTab.close();
  test.info().setTimeout(test.info().timeout + 90000);
  await expect(avatar).toHaveCount(0, { timeout: 90000 });
}

// @S18 Members see where others are pointing on the canvas
//   Given "Amara Banda" and I both have "Intake" open
//   When she moves her pointer over the canvas
//   Then I see a cursor labelled "Amara Banda" in her colour following it
//   When her pointer leaves the canvas
//   Then her cursor disappears
export async function S18(
  page: Page,
  her: Page,
  email: string,
  amara: { email: string; full: string },
  w: EditorTarget
) {
  await openAs(page, email, w);
  await openAs(her, amara.email, w);
  const box = (await canvas(her).boundingBox())!;

  await her.mouse.move(box.x + 200, box.y + 150, { steps: 5 });
  await her.mouse.move(box.x + 260, box.y + 190, { steps: 5 });

  await expect(remoteCursor(page, amara.full)).toBeVisible(EVENTUALLY);

  await her.mouse.move(box.x + box.width + 200, 5, { steps: 5 });
  await expect(remoteCursor(page, amara.full)).toHaveCount(0, EVENTUALLY);
}

// @S19 Save shows when I have unsaved changes
//   Given I am an editor with "Intake" open and nothing changed
//   Then "Save" shows no unsaved changes marker
//   When I change the workflow's name, a step, a path, a trigger or a step's position
//   Then "Save" shows the unsaved changes marker
// Each kind of change gets its own page load; `changes` are the host's ways
// of making one, by name.
export async function S19(
  page: Page,
  email: string,
  w: EditorTarget,
  changes: Record<string, (page: Page) => Promise<void>>
) {
  await openAs(page, email, w);
  for (const [what, change] of Object.entries(changes)) {
    await openEditor(page, w.projectId, w.id);
    await expect.soft(unsavedMarker(page), what).toHaveCount(0);
    await change(page);
    await expect.soft(unsavedMarker(page), what).toBeVisible();
    // Put the shared copy back for the next change
    await page.keyboard.press('ControlOrMeta+z');
  }
}

// @S20 Leaving with unsaved changes asks for confirmation
//   Given I am an editor with experimental features and unsaved changes in "Intake"
//   When I close the tab
//   Then the browser asks me to confirm leaving
//   When I instead leave by choosing a sandbox from "Edit in sandbox"
//   Then I am not asked
// Experimental features lock a live workflow for me, so the unsaved change
// is made by `colleague` (without them) in the shared copy. `sandbox` is the
// name of a sandbox of the project.
export async function S20(
  page: Page,
  colleague: Page,
  emails: { me: string; colleague: string },
  w: EditorTarget,
  sandbox: string
) {
  await openAs(colleague, emails.colleague, w);
  await renameStep(colleague, 'Fetch', 'Fetch unsaved');
  await openAs(page, emails.me, w);
  await expect(node(page, 'Fetch unsaved')).toBeVisible();

  let asked = 0;
  page.on('dialog', d => {
    if (d.type() === 'beforeunload') asked++;
    void d.dismiss();
  });
  await page.close({ runBeforeUnload: true });
  await expect.poll(() => asked).toBe(1);

  const again = await page.context().newPage();
  let askedAgain = 0;
  again.on('dialog', d => {
    if (d.type() === 'beforeunload') askedAgain++;
    void d.accept();
  });
  await openEditor(again, w.projectId, w.id);
  await headerButton(again, 'Edit in sandbox').click();
  await again.getByRole('button', { name: sandbox }).first().click();
  await expect
    .poll(() => new URL(again.url()).pathname)
    .not.toBe(editorPath(w.projectId, w.id));
  expect(askedAgain).toBe(0);
}

// @S21 Editor saves with the keyboard from anywhere on the page
//   Given I am an editor with "Intake" open and my cursor in a form field
//   When I press Ctrl+S, or Cmd+S on a Mac
//   Then the workflow is saved, and the browser's own save dialog does not open
//   When I am a viewer and press Ctrl+S
//   Then nothing is saved
export async function S21(
  page: Page,
  viewerPage: Page,
  emails: { editor: string; viewer: string },
  w: EditorTarget
) {
  await openAs(page, emails.editor, w);
  await renameWorkflow(page, `${w.name} by keyboard`);
  await expect(field(page, 'Workflow Name')).toBeFocused();
  const downloads: unknown[] = [];
  page.on('download', d => downloads.push(d));

  await page.keyboard.press('ControlOrMeta+s');

  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
  expect(storedWorkflow(w.id).name).toBe(`${w.name} by keyboard`);
  expect(downloads).toHaveLength(0);

  const version = savedVersion(w);
  await openAs(viewerPage, emails.viewer, w);
  // A viewer's fields are disabled, so the keys go to the page
  await openSettings(viewerPage);
  await viewerPage.keyboard.press('ControlOrMeta+s');
  await viewerPage.waitForTimeout(1500);
  expect(savedVersion(w)).toBe(version);
}

// @S22 A tab left open across a deploy keeps its connection
//   Given I have "Intake" open from before a deploy that removed an event my tab still sends
//   When my tab sends that event
//   Then it gets an error reply and my session stays connected
export async function S22(page: Page, email: string, w: EditorTarget) {
  const sock = await watchEditorSocket(page);
  await openAs(page, email, w);
  // Page loads close their own sockets; count only closes after the event
  const closedBefore = sock.closed();

  const reply = await sock.push('an_event_this_server_no_longer_has', {});

  expect(reply.status).toBe('error');
  expect((await sock.push('get_context')).status).toBe('ok');
  expect(sock.pushed('phx_close')).toHaveLength(0);
  expect(sock.closed()).toBe(closedBefore);
  await expect(node(page, 'Fetch')).toBeVisible();
}
