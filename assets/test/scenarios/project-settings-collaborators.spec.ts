// Scenarios from annotations/views/project-settings-collaborators.md. The
// shared session, scope, banner, header, flash and tab chrome scenarios run
// once for every settings tab, in project-settings-setup.spec.ts.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns the projects I don't. Other people are new
// accounts made for the test, seeded before the project so they are removed
// after it.
import { randomUUID } from 'node:crypto';

import { expect, test, type Locator, type Page } from '@playwright/test';

import {
  addAnotherRow,
  addCollaboratorsButton,
  addCollaboratorsDialog,
  collaboratorEmail,
  collaboratorRole,
  collaboratorRow,
  digestOf,
  dropRow,
  expectOpen,
  failureAlertOf,
  fillCollaborator,
  inviteDialog,
  inviteName,
  openSettings,
  panel,
  removeCollaboratorButton,
  removeDialog,
  roleNotice,
  SANDBOX_BANNER,
  sendCollaboratorRequest,
  submitAddWithRole,
  toggleSupportAccess,
} from './pages/project-settings';
import {
  addMember,
  exec,
  expectTooltip,
  mailbox,
  membershipOf,
  projectCredentialId,
  removeAccountByEmail,
  seedUser,
  seedWorkspace,
  signInAs,
  sql,
  storedAccount,
  user,
  watchLiveView,
  withLimiterRefusing,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PROJECT = 'Malawi HIV';

const PASSING_OLD = { tag: '@passing-old' };
const PASSING_BOTH = { tag: ['@passing-old', '@passing-new'] };
const SERIAL_OLD = { tag: ['@passing-old', '@serial'] };
const SERIAL = { tag: ['@passing-old', '@passing-new', '@serial'] };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given I am a <role> on project <name> (owner@openfn.org owns it unless I do)
function givenProject(
  role: Role,
  name = PROJECT,
  extra: Partial<WorkspaceSeed> = {}
) {
  const members: Record<string, Role> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const w = seedWorkspace({ name, members, ...extra }, OTHER);
  cleanups.push(w.remove);
  return w.id(name);
}

// Given "<first> <last>" has an account. Seed people before the project.
function givenPerson(first: string, last: string) {
  const person = seedUser(first.toLowerCase(), {
    firstName: first,
    lastName: last,
  });
  cleanups.push(person.remove);
  return person;
}

// Given <person> is a <role> on project <id>
function givenMember(
  id: string,
  userId: string,
  role: Role,
  opts: { failureAlert?: boolean; digest?: string } = {}
) {
  const m = addMember(id, userId, role, opts);
  cleanups.push(m.remove);
  return m.id;
}

// An email nobody has an account for. Removes the account an invite makes.
function nobodysEmail() {
  const email = `new.person-${randomUUID().slice(0, 8)}@example.org`;
  cleanups.push(() => removeAccountByEmail(email));
  return email;
}

const myEmail = () => user(ME).email;
const otherEmail = () => user(OTHER).email;

// Given I am signed in and on project <id>'s Collaboration tab
async function onCollaboration(page: Page, id: string) {
  await signInAs(page, ME);
  const lv = watchLiveView(page);
  await openSettings(page, id, 'Collaboration');
  return lv;
}

// When I add a row to the add form, making <rows>. Today the row comes from
// the server, and filling before it arrives loses it.
async function addRow(dialog: Locator, rows: number) {
  await addAnotherRow(dialog).click();
  await expect(collaboratorEmail(dialog, rows - 1)).toBeVisible();
}

async function openAddForm(page: Page) {
  await addCollaboratorsButton(page).click();
  const dialog = addCollaboratorsDialog(page);
  await expectOpen(dialog);
  return dialog;
}

const saveButton = (page: Page) =>
  addCollaboratorsDialog(page).getByRole('button', {
    name: /save collaborator/i,
  });

const actorsOf = (id: string, event: string) =>
  sql<{ actor_id: string }>(
    `select actor_id from audit_events where item_id = '${id}' and event = '${event}'`
  ).map(e => e.actor_id);

const supportAccessOf = (id: string) =>
  sql<{ allow_support_access: boolean }>(
    `select allow_support_access from projects where id = '${id}'`
  )[0].allow_support_access;

const mailTo = async (page: Page, email: string) =>
  (await mailbox(page.request)).filter(m => m.to.includes(email));

const NOT_AUTHORIZED = 'You are not authorized to perform this action';
const UPDATED = /Project user updated success/;

// @S01
// Scenario: Everyone on the project sees who else is on it
//   Given I am a viewer on project "Malawi HIV"
//   And "Amara Banda" is an editor on the project
//   When I open the collaboration tab
//   Then I see "Amara Banda" with her email and role "Editor"
//   And I see each collaborator's failure alert and digest setting
test('@S01', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('viewer');
  givenMember(id, amara.id, 'editor', { failureAlert: true, digest: 'daily' });
  await onCollaboration(page, id);

  const row = collaboratorRow(page, amara.email);
  await expect(row).toContainText('Amara Banda');
  await expect(row).toContainText('Editor');
  await expect(failureAlertOf(row)).toHaveText(/Enabled/);
  await expect(digestOf(row)).toHaveText(/Daily/);
  await expect(collaboratorRow(page, otherEmail())).toContainText('Owner');
});

// @S02
// Scenario: Admin adds an existing user
//   Given I am an admin on project "Malawi HIV"
//   And "amara@example.org" is a registered user not on the project
//   When I click "Add collaborator(s)"
//   And I enter "amara@example.org" with role "Editor"
//   And I click "Save collaborator"
//   Then I see "Collaborator added successfully"
//   And "amara@example.org" appears in the list with role "Editor"
//   And an audit event "collaborator_added" is recorded against me
//   And the flow "flow-collaborator-added-email" has started for "amara@example.org"
test('@S02', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('admin');
  await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  await fillCollaborator(dialog, 0, amara.email, 'Editor');
  await saveButton(page).click();

  await expect(page.getByText('Collaborator added successfully')).toBeVisible();
  await expect(collaboratorRow(page, amara.email)).toContainText('Editor');
  expect(membershipOf(id, amara.id)?.role).toBe('editor');
  expect(actorsOf(id, 'collaborator_added')).toContain(user(ME).id);
  await expect
    .poll(async () => (await mailTo(page, amara.email)).length)
    .toBe(1);
});

// @S03
// Scenario: Admin adds several users in one go
//   Given I am an owner on project "Malawi HIV"
//   And three registered users are not on the project
//   When I add rows until there are three
//   And I enter each user's email with roles "Admin", "Editor" and "Viewer"
//   And I click "Save collaborators"
//   Then I see "Collaborators added successfully"
//   And all three appear in the list with those roles
test('@S03', PASSING_BOTH, async ({ page }) => {
  const people = [
    givenPerson('Amara', 'Banda'),
    givenPerson('Tomas', 'Silva'),
    givenPerson('Lindiwe', 'Phiri'),
  ];
  const roles = ['Admin', 'Editor', 'Viewer'] as const;
  const id = givenProject('owner');
  await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  await addRow(dialog, 2);
  await addRow(dialog, 3);
  for (const [i, p] of people.entries())
    await fillCollaborator(dialog, i, p.email, roles[i]);
  await saveButton(page).click();

  await expect(
    page.getByText('Collaborators added successfully')
  ).toBeVisible();
  for (const [i, p] of people.entries()) {
    await expect(collaboratorRow(page, p.email)).toContainText(roles[i]);
    expect(membershipOf(id, p.id)?.role).toBe(roles[i].toLowerCase());
  }
});

// @S04
// Scenario: Viewers and editors cannot add collaborators
//   Given I am an editor on project "Malawi HIV"
//   When I open the collaboration tab
//   Then the "Add collaborator(s)" button is disabled with tooltip "You are not authorized to perform this action"
//   And sending "toggle_collaborators_modal" does not open the add form
test('@S04', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  const lv = await onCollaboration(page, id);

  await expect(addCollaboratorsButton(page)).toBeDisabled();
  await expectTooltip(page, addCollaboratorsButton(page), NOT_AUTHORIZED);
  await sendCollaboratorRequest(page, lv, 'open-add');

  await expect(addCollaboratorsDialog(page)).toHaveCount(0);
  expect(lv.crashes()).toBe(0);
});

// @S05
// Scenario: The owner role cannot be granted when adding
//   Given I am an admin on project "Malawi HIV"
//   When I open the add form
//   Then the role options are "Viewer", "Editor" and "Admin"
//   And submitting role "owner" anyway shows "is invalid"
test('@S05', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('admin');
  const lv = await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  const options = await collaboratorRole(dialog)
    .getByRole('option')
    .allTextContents();
  expect(options.map(o => o.trim()).filter(o => o !== 'Select Role')).toEqual([
    'Viewer',
    'Editor',
    'Admin',
  ]);
  await submitAddWithRole(page, amara.email, 'owner');

  await expect(page.getByText('is invalid')).toBeVisible();
  expect(membershipOf(id, amara.id)).toBeUndefined();
  expect(lv.crashes()).toBe(0);
});

// @S06
// Scenario: Adding someone already on the project is refused
//   Given I am an admin on project "Malawi HIV"
//   And "amara@example.org" is already on the project
//   When I submit the add form with "amara@example.org"
//   Then I see "This account is already part of this project"
//   And nothing is saved
test('@S06', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('admin');
  givenMember(id, amara.id, 'editor');
  await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  await fillCollaborator(dialog, 0, amara.email, 'Viewer');
  // A form that refuses before the click turns Save off; one that checks
  // on save turns it on once the row is valid. Wait for either.
  const refusal = dialog.getByText(
    'This account is already part of this project'
  );
  await expect(
    saveButton(page).and(page.locator(':enabled')).or(refusal).first()
  ).toBeVisible();
  if (await saveButton(page).isEnabled()) await saveButton(page).click();

  await expect(refusal).toBeVisible();
  expect(membershipOf(id, amara.id)?.role).toBe('editor');
});

// @S07
// Scenario: An invalid email is caught before saving
//   Given I am an owner on project "Malawi HIV"
//   When I type "not-an-email" in the add form
//   Then I see "Email address not valid."
//   And the save button is disabled
// Old only: the design-system form says "has invalid format".
test('@S07', PASSING_OLD, async ({ page }) => {
  const id = givenProject('owner');
  await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  await collaboratorEmail(dialog).fill('not-an-email');
  await collaboratorEmail(dialog).blur();

  await expect(dialog).toContainText('Email address not valid.');
  await expect(saveButton(page)).toBeDisabled();
});

// @S08
// Scenario: People without an account move on to the invite form
//   Given I am an owner on project "Malawi HIV"
//   And "new.person@example.org" has no OpenFn account
//   When I submit the add form with "new.person@example.org" as "Editor"
//   Then I see "This collaborator does not have an OpenFn account. Invite them to join OpenFn and grant access to the project."
//   And the "Invite new user(s) to join OpenFn" form opens with that email and role filled in
test('@S08', PASSING_BOTH, async ({ page }) => {
  const email = nobodysEmail();
  const id = givenProject('owner');
  await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  await fillCollaborator(dialog, 0, email, 'Editor');
  await saveButton(page).click();

  await expect(
    page.getByText(
      'This collaborator does not have an OpenFn account. Invite them to join OpenFn and grant access to the project.'
    )
  ).toBeVisible();
  const invite = inviteDialog(page);
  await expect(collaboratorEmail(invite)).toHaveValue(email);
  await expect(collaboratorRole(invite)).toHaveValue(/editor/i);
});

// @S09
// Scenario: Mixed list adds the people with accounts and invites the rest
//   Given I am an owner on project "Malawi HIV"
//   And "amara@example.org" is registered and "new.person@example.org" is not
//   When I submit the add form with both
//   Then "amara@example.org" is added to the project
//   And I see "1 out of 2 collaborators have OpenFn accounts and have been added to your project. You can invite others to join OpenFn and grant them access to this project."
//   And the invite form opens for "new.person@example.org" only
test('@S09', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const email = nobodysEmail();
  const id = givenProject('owner');
  await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  await addRow(dialog, 2);
  await fillCollaborator(dialog, 0, amara.email, 'Editor');
  await fillCollaborator(dialog, 1, email, 'Viewer');
  await saveButton(page).click();

  await expect(
    page.getByText(
      '1 out of 2 collaborators have OpenFn accounts and have been added to your project. You can invite others to join OpenFn and grant them access to this project.'
    )
  ).toBeVisible();
  expect(membershipOf(id, amara.id)?.role).toBe('editor');
  const invite = inviteDialog(page);
  await expect(collaboratorEmail(invite)).toHaveValue(email);
  await expect(collaboratorEmail(invite, 1)).toHaveCount(0);
});

// When I submit the add form with <email> as <role> and reach the invite form
async function reachInviteForm(
  page: Page,
  email: string,
  role: 'Viewer' | 'Editor' | 'Admin'
) {
  const dialog = await openAddForm(page);
  await fillCollaborator(dialog, 0, email, role);
  await saveButton(page).click();
  const invite = inviteDialog(page);
  await expectOpen(invite);
  return invite;
}

// @S10
// Scenario: Admin invites a person without an account
//   Given the invite form is open for "new.person@example.org" as "Editor"
//   When I enter first name "Non" and last name "Exists"
//   And I click "Invite new user"
//   Then I see "Invite sent successfully"
//   And "Non Exists" appears in the list with role "Editor"
//   And no "You now have access to" email is sent to them
//   And the flow "flow-invite-new-collaborator" has started for "new.person@example.org"
test('@S10', PASSING_BOTH, async ({ page }) => {
  const email = nobodysEmail();
  const id = givenProject('admin');
  await onCollaboration(page, id);

  const invite = await reachInviteForm(page, email, 'Editor');
  await inviteName(invite, 'First Name').fill('Non');
  await inviteName(invite, 'Last Name').fill('Exists');
  await invite.getByRole('button', { name: /invite new user/i }).click();

  await expect(page.getByText('Invite sent successfully')).toBeVisible();
  const row = collaboratorRow(page, email);
  await expect(row).toContainText('Non Exists');
  await expect(row).toContainText('Editor');
  await expect.poll(async () => (await mailTo(page, email)).length).toBe(1);
  const mails = await mailTo(page, email);
  expect(mails.map(m => m.subject).join('\n')).not.toMatch(
    /You now have access to/
  );
});

// @S11
// Scenario: An invite to an email that already has an account is refused
//   Given the invite form is open
//   When I change the email to that of a registered user and submit
//   Then I see "This email is already taken"
//   And no email is sent
test('@S11', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const email = nobodysEmail();
  const id = givenProject('owner');
  await onCollaboration(page, id);

  const invite = await reachInviteForm(page, email, 'Editor');
  await collaboratorEmail(invite).fill(amara.email);
  await inviteName(invite, 'First Name').fill('Amara');
  await inviteName(invite, 'Last Name').fill('Banda');
  await invite.getByRole('button', { name: /invite new user/i }).click();

  await expect(invite).toContainText('This email is already taken');
  expect(membershipOf(id, amara.id)).toBeUndefined();
  expect(await mailTo(page, amara.email)).toHaveLength(0);
  expect(await mailTo(page, email)).toHaveLength(0);
});

const CAP = 'You can only have 3 collaborators in this project';

// @S12 @variant:usage-limited
// Scenario: The add button is disabled when the collaborator cap is reached
//   Given project "Malawi HIV" has reached its collaborator limit with message "You can only have 3 collaborators in this project"
//   And I am an admin on the project
//   When I open the collaboration tab
//   Then the "Add collaborator(s)" button is disabled
//   And its tooltip says "You can only have 3 collaborators in this project"
test('@S12', SERIAL, async ({ page }) => {
  cleanups.push(withLimiterRefusing('new_user', CAP));
  const id = givenProject('admin');
  await onCollaboration(page, id);

  await expect(addCollaboratorsButton(page)).toBeDisabled();
  await expectTooltip(page, addCollaboratorsButton(page), CAP);
});

// @S13 @variant:usage-limited
// Scenario: Adding more rows than the plan allows is blocked in the form
//   Given project "Malawi HIV" may add 2 more collaborators
//   And I am an admin with the add form open
//   When I add a third row
//   Then I see the limiter's message in the form
//   And the save button is disabled
//   When I remove a row
//   Then the message goes away
// Old only: the design-system form shows the limit when you save, not as
// rows are added.
test('@S13', SERIAL_OLD, async ({ page }) => {
  cleanups.push(withLimiterRefusing('new_user', CAP, { over: 2 }));
  const id = givenProject('admin');
  await onCollaboration(page, id);

  const dialog = await openAddForm(page);
  await addAnotherRow(dialog).click();
  await expect(dialog).not.toContainText(CAP);
  await addAnotherRow(dialog).click();

  await expect(dialog).toContainText(CAP);
  await expect(saveButton(page)).toBeDisabled();
  await dropRow(page, dialog, 2);
  await expect(dialog).not.toContainText(CAP);
});

// When I remove <who> and confirm
async function removeAndConfirm(page: Page, who: string) {
  await removeCollaboratorButton(collaboratorRow(page, who)).click();
  const confirm = removeDialog(page);
  await confirm.getByRole('button', { name: /confirm|remove/i }).click();
}

// @S14
// Scenario: Admin removes a collaborator
//   Given I am an admin on project "Malawi HIV"
//   And "Amara Banda" is a viewer on the project
//   When I click "Remove collaborator" on her row
//   And I confirm in "Remove Amara Banda"
//   Then I see "Collaborator removed"
//   And she is no longer in the list
//   And her user account still exists
//   And an audit event "collaborator_removed" is recorded against me
//   And her open project pages are handed to shared-project-scope S07
// (The hand-off is shared-project-scope S07, run in the Setup spec.)
test('@S14', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('admin');
  givenMember(id, amara.id, 'viewer');
  await onCollaboration(page, id);

  await removeCollaboratorButton(collaboratorRow(page, amara.email)).click();
  const confirm = page
    .getByRole('dialog')
    .filter({ hasText: 'Remove Amara Banda' });
  await expectOpen(confirm);
  await confirm.getByRole('button', { name: /confirm|remove/i }).click();

  await expect(page.getByText('Collaborator removed')).toBeVisible();
  await expect(collaboratorRow(page, amara.email)).toHaveCount(0);
  expect(membershipOf(id, amara.id)).toBeUndefined();
  expect(storedAccount({ id: amara.id })).toBeTruthy();
  expect(actorsOf(id, 'collaborator_removed')).toContain(user(ME).id);
});

// @S15
// Scenario: Removal warns about and withdraws the person's credentials
//   Given I am an admin on project "Malawi HIV"
//   And "Amy Admin" is a viewer who owns credentials "DHIS2 play" and "PostgreSQL" shared with the project
//   When I open the removal confirmation for "Amy Admin"
//   Then it says "and their owned credentials DHIS2 play, PostgreSQL will be removed from it"
//   When I confirm
//   Then neither credential is available in project "Malawi HIV"
// owner@openfn.org plays "Amy Admin", as the credentials need a seeded owner.
test('@S15', PASSING_BOTH, async ({ page }) => {
  const w = seedWorkspace(
    {
      name: PROJECT,
      members: { [ME]: 'admin', [OTHER]: 'viewer' },
      credentials: ['DHIS2 play', 'PostgreSQL'],
    },
    OTHER
  );
  cleanups.push(w.remove);
  const id = w.id(PROJECT);
  // Every project has exactly one owner
  givenMember(id, user('super@openfn.org').id, 'owner');
  await onCollaboration(page, id);

  await removeCollaboratorButton(collaboratorRow(page, otherEmail())).click();
  const confirm = removeDialog(page);
  await expect(confirm).toContainText(
    /and their owned credentials .* will be removed from it/
  );
  // today in no fixed order
  await expect(confirm).toContainText('DHIS2 play');
  await expect(confirm).toContainText('PostgreSQL');
  await confirm.getByRole('button', { name: /confirm|remove/i }).click();

  await expect(collaboratorRow(page, otherEmail())).toHaveCount(0);
  expect(projectCredentialId(id, 'DHIS2 play')).toBeUndefined();
  expect(projectCredentialId(id, 'PostgreSQL')).toBeUndefined();
});

// @S16
// Scenario: Viewers and editors cannot remove collaborators
//   Given I am an editor on project "Malawi HIV"
//   When I open the collaboration tab
//   Then every "Remove collaborator" button is disabled with tooltip "You do not have permission to remove a user"
//   And sending "remove_project_user" for a member shows "You are not authorized to perform this action."
//   And the member is still on the project
test('@S16', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('editor');
  const member = givenMember(id, amara.id, 'viewer');
  const lv = await onCollaboration(page, id);

  const button = removeCollaboratorButton(collaboratorRow(page, amara.email));
  await expect(button).toBeDisabled();
  await expectTooltip(
    page,
    button,
    'You do not have permission to remove a user'
  );
  for (const b of await panel(page, 'Collaboration')
    .getByRole('button', { name: /remove collaborator/i })
    .all())
    await expect(b).toBeDisabled();
  await sendCollaboratorRequest(page, lv, 'remove', member);

  expect(membershipOf(id, amara.id)?.role).toBe('viewer');
  expect(lv.crashes()).toBe(0);
});

// @S17
// Scenario: The owner cannot be removed
//   Given I am an admin on project "Malawi HIV"
//   When I open the collaboration tab
//   Then the owner's "Remove collaborator" button is disabled with tooltip "You cannot remove an owner"
//   And sending "remove_project_user" for the owner is refused
test('@S17', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const lv = await onCollaboration(page, id);

  const button = removeCollaboratorButton(collaboratorRow(page, otherEmail()));
  await expect(button).toBeDisabled();
  await expectTooltip(page, button, 'You cannot remove an owner');
  const owner = membershipOf(id, user(OTHER).id);
  await sendCollaboratorRequest(page, lv, 'remove', owner.id);

  expect(membershipOf(id, user(OTHER).id)?.role).toBe('owner');
  expect(lv.crashes()).toBe(0);
});

// @S18
// Scenario: Admins cannot remove themselves
//   Given I am an admin on project "Malawi HIV"
//   When I open the collaboration tab
//   Then my own "Remove collaborator" button is disabled with tooltip "You cannot remove yourself"
//   And sending "remove_project_user" for my row is refused
test('@S18', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  const lv = await onCollaboration(page, id);

  const button = removeCollaboratorButton(collaboratorRow(page, myEmail()));
  await expect(button).toBeDisabled();
  await expectTooltip(page, button, 'You cannot remove yourself');
  const mine = membershipOf(id, user(ME).id);
  await sendCollaboratorRequest(page, lv, 'remove', mine.id);

  expect(membershipOf(id, user(ME).id)?.role).toBe('admin');
  expect(lv.crashes()).toBe(0);
});

// @S19
// Scenario: A parent project's admins cannot be removed from a sandbox
//   Given "Parent Admin" is an admin on project "Malawi HIV"
//   And "Parent Admin" is an editor on its sandbox "dev"
//   And I am the owner of "dev"
//   When I open the collaboration tab of "dev"
//   Then "Parent Admin"'s "Remove collaborator" button is disabled with tooltip "Cannot remove a user who is admin or owner on the parent project"
// owner@openfn.org plays "Parent Admin".
test('@S19', PASSING_BOTH, async ({ page }) => {
  const w = seedWorkspace(
    {
      name: PROJECT,
      members: { [ME]: 'owner', [OTHER]: 'admin' },
      sandboxes: [{ name: 'dev', members: { [OTHER]: 'editor' } }],
    },
    ME
  );
  cleanups.push(w.remove);
  await onCollaboration(page, w.id('dev'));

  const button = removeCollaboratorButton(collaboratorRow(page, otherEmail()));
  await expect(button).toBeDisabled();
  await expectTooltip(
    page,
    button,
    'Cannot remove a user who is admin or owner on the parent project'
  );
});

// @S20
// Scenario: An admin demoted after loading the page cannot remove anyone
//   Given I have the collaboration tab open as an admin on project "Malawi HIV"
//   And I am demoted to editor without my page reloading
//   When I confirm removing "Amara Banda"
//   Then I see "You are not authorized to perform this action."
//   And she is still on the project
test('@S20', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('admin');
  givenMember(id, amara.id, 'viewer');
  await onCollaboration(page, id);

  // Only the stored role changes: nothing tells my open page
  exec(
    `update project_users set role = 'editor'
     where project_id = '${id}' and user_id = '${user(ME).id}'`
  );
  await removeAndConfirm(page, amara.email);

  await expect(page.getByText(NOT_AUTHORIZED)).toBeVisible();
  expect(membershipOf(id, amara.id)?.role).toBe('viewer');
});

// @S21
// Scenario: Memberships of another project cannot be touched from this one
//   Given I am an admin on project "Malawi HIV"
//   And "Bob" is an editor on project "Kenya TB" only
//   When I send "remove_project_user", "set_failure_alert" or "set_digest" with Bob's membership id
//   Then I see "You are not authorized to perform this action."
//   And Bob's membership is unchanged
for (const kind of ['remove', 'alert', 'digest'] as const) {
  test(`@S21 ${kind}`, PASSING_BOTH, async ({ page }) => {
    const bob = givenPerson('Bob', 'Mwale');
    const id = givenProject('admin');
    const kenya = seedWorkspace(
      { name: 'Kenya TB', members: { [OTHER]: 'owner' } },
      OTHER
    );
    cleanups.push(kenya.remove);
    const kenyaId = kenya.id('Kenya TB');
    const member = givenMember(kenyaId, bob.id, 'editor', {
      failureAlert: false,
      digest: 'never',
    });
    const lv = await onCollaboration(page, id);

    await sendCollaboratorRequest(page, lv, kind, member);

    expect(membershipOf(kenyaId, bob.id)).toEqual({
      id: member,
      role: 'editor',
      failure_alert: false,
      digest: 'never',
    });
    expect(lv.crashes()).toBe(0);
  });
}

// Given my failure alert and digest on project <id> are these
const setMine = (id: string, failureAlert: boolean, digest: string) =>
  exec(
    `update project_users set failure_alert = ${failureAlert}, digest = '${digest}'
     where project_id = '${id}' and user_id = '${user(ME).id}'`
  );

// @S22
// Scenario: A member turns on their own failure alerts
//   Given I am an editor on project "Malawi HIV" with failure alerts disabled
//   When I set my failure alert to "Enabled"
//   Then I see a success message
//   And my failure alert shows "Enabled"
//   And the flow "flow-failure-alert-email" uses my new setting
// (The flow reads the stored setting, checked here.)
test('@S22', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  setMine(id, false, 'weekly');
  await onCollaboration(page, id);

  const alert = failureAlertOf(collaboratorRow(page, myEmail())).getByRole(
    'combobox'
  );
  await alert.selectOption({ label: 'Enabled' });

  await expect(page.getByText(UPDATED)).toBeVisible();
  await expect(alert).toHaveValue('true');
  expect(membershipOf(id, user(ME).id)?.failure_alert).toBe(true);
});

// @S23
// Scenario: A member chooses how often they get the digest
//   Given I am a viewer on project "Malawi HIV" with digest "Never"
//   When I set my digest to "Weekly"
//   Then my digest shows "Weekly"
test('@S23', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  setMine(id, false, 'never');
  await onCollaboration(page, id);

  const digest = digestOf(collaboratorRow(page, myEmail())).getByRole(
    'combobox'
  );
  await digest.selectOption({ label: 'Weekly' });

  await expect(page.getByText(UPDATED)).toBeVisible();
  await expect(digest).toHaveValue('weekly');
  expect(membershipOf(id, user(ME).id)?.digest).toBe('weekly');
});

// @S24
// Scenario: Members cannot change other members' notifications
//   Given I am an admin on project "Malawi HIV"
//   And "Amara Banda" has failure alerts enabled and digest "Never"
//   When I open the collaboration tab
//   Then Amara's failure alert and digest are shown as text, not selects
//   And sending "set_failure_alert" or "set_digest" for her row shows "You are not authorized to perform this action."
//   And her settings are unchanged
test('@S24', PASSING_BOTH, async ({ page }) => {
  const amara = givenPerson('Amara', 'Banda');
  const id = givenProject('admin');
  const member = givenMember(id, amara.id, 'editor', {
    failureAlert: false,
    digest: 'never',
  });
  const lv = await onCollaboration(page, id);

  const row = collaboratorRow(page, amara.email);
  await expect(failureAlertOf(row)).toHaveText(/Disabled/);
  await expect(digestOf(row)).toHaveText(/Never/);
  await expect(row.getByRole('combobox')).toHaveCount(0);
  await sendCollaboratorRequest(page, lv, 'alert', member);
  await sendCollaboratorRequest(page, lv, 'digest', member);

  expect(membershipOf(id, amara.id)).toMatchObject({
    failure_alert: false,
    digest: 'never',
  });
  expect(lv.crashes()).toBe(0);
});

// @S25 @variant:failure-alerts-limited
// Scenario: Failure alerts show as unavailable when the plan doesn't include them
//   Given failure alerts are not available for project "Malawi HIV"
//   And I have failure alerts enabled
//   When I open the collaboration tab
//   Then my failure alert shows "Unavailable" and cannot be changed
test('@S25', SERIAL, async ({ page }) => {
  cleanups.push(withLimiterRefusing('alert_failure', 'No failure alerts'));
  const id = givenProject('editor');
  setMine(id, true, 'weekly');
  await onCollaboration(page, id);

  const alert = failureAlertOf(collaboratorRow(page, myEmail()));
  await expect(alert).toHaveText(/Unavailable/);
  await expect(alert.getByRole('combobox')).toHaveCount(0);
});

// @S26
// Scenario: Admin grants and revokes support access
//   Given I am an admin on project "Malawi HIV" with support access off
//   When I switch on "Grant support access"
//   Then I see "Granted access to support users successfully"
//   And an audit event "allow_support_access_updated" is recorded
//   When I switch it off
//   Then I see "Revoked access to support users successfully"
//   And open support sessions are handed to shared-project-scope S09
// (The hand-off is shared-project-scope S09, run in the Setup spec.)
test('@S26', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('admin');
  await onCollaboration(page, id);

  await toggleSupportAccess(page);
  await expect(
    page.getByText('Granted access to support users successfully')
  ).toBeVisible();
  expect(supportAccessOf(id)).toBe(true);
  expect(actorsOf(id, 'allow_support_access_updated')).toContain(user(ME).id);

  await toggleSupportAccess(page);
  await expect(
    page.getByText('Revoked access to support users successfully')
  ).toBeVisible();
  expect(supportAccessOf(id)).toBe(false);
});

// @S27
// Scenario: Viewers and editors don't see the support access switch
//   Given I am an editor on project "Malawi HIV"
//   When I open the collaboration tab
//   Then I do not see "Grant support access"
test('@S27', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  await onCollaboration(page, id);

  await expect(collaboratorRow(page, myEmail())).toBeVisible();
  await expect(
    panel(page, 'Collaboration').getByText('Grant support access')
  ).toHaveCount(0);
});

// @S28
// Scenario: Members without admin rights are told what they can change
//   Given I am a viewer on project "Malawi HIV"
//   When I open the collaboration tab
//   Then I see "Role based permissions: You cannot modify this project's collaboration settings, but you can change your notification preferences."
test('@S28', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('viewer');
  await onCollaboration(page, id);

  await expect(roleNotice(panel(page, 'Collaboration'))).toHaveText(
    "Role based permissions: You cannot modify this project's collaboration settings, but you can change your notification preferences."
  );
});

// @S29 @variant:sandbox
// Scenario: A sandbox says its membership changes stay in the sandbox
//   Given I am the owner of sandbox "dev" of project "Malawi HIV"
//   When I open the collaboration tab of "dev"
//   Then I see "Changes you make here only apply to this sandbox and do not sync to the parent project on merge."
test('@S29', PASSING_BOTH, async ({ page }) => {
  const w = seedWorkspace(
    { name: PROJECT, members: { [ME]: 'owner' }, sandboxes: [{ name: 'dev' }] },
    ME
  );
  cleanups.push(w.remove);
  await onCollaboration(page, w.id('dev'));

  await expect(
    panel(page, 'Collaboration').getByText(SANDBOX_BANNER.local)
  ).toBeVisible();
});
