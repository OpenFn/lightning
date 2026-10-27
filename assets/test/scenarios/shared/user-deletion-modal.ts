// Scenarios from annotations/shared/shared-user-deletion-modal.md, run on a
// host page. The host seeds the accounts and passes `open`, which opens the
// modal on that host for the account with that id.
import { expect, type Browser, type Page } from '@playwright/test';

import {
  expectAt,
  field,
  modal,
  modalTitle,
  otherSession,
  sql,
  submit,
} from '../steps';

import { toast } from './flash-messages';

type Account = { id: string; email: string };
type Open = (id: string) => Promise<void>;

const TITLE = 'Delete user';

async function dialog(page: Page) {
  await expect(modalTitle(page, TITLE)).toBeVisible();
  return modal(page, TITLE);
}

// Whether the account is disabled and scheduled for deletion, as stored
const stateOf = (id: string) =>
  sql<{ disabled: boolean; scheduled: boolean }>(
    `select coalesce(disabled, false) as disabled,
            scheduled_deletion is not null as scheduled
     from users where id = '${id}'`
  )[0];

const untouched = { disabled: false, scheduled: false };

// @S01 The modal says what is deleted and asks for the email
//   Given the modal is open on "<host>" for user "amara@example.org"
//   Then I see a dialog "Delete user"
//   And I see "<owner> account and credential data will be deleted. Please make sure none of these credentials are used in production workflows."
//   And I see a "User email" field and the buttons "Delete account" and "Cancel"
export async function S01(
  page: Page,
  account: Account,
  open: Open,
  owner: string
) {
  await open(account.id);

  const d = await dialog(page);
  await expect(d).toContainText(
    `${owner} account and credential data will be deleted. Please make sure none of these credentials are used in production workflows.`
  );
  await expect(field(d, 'User email')).toBeVisible();
  for (const name of ['Delete account', 'Cancel'])
    await expect(d.getByRole('button', { name, exact: true })).toBeVisible();
}

// @S02 A mismatched email does not schedule the account
//   Given the modal is open for unscheduled user "amara@example.org"
//   When I set "User email" to "invalid@email.com"
//   Then I see "This email doesn't match your current email"
//   When I click "Delete account"
//   Then I still see the dialog with that error
//   And "amara@example.org" is not disabled or scheduled for deletion
// `send` sends the modal's confirm with an email, past the page's own check,
// so the last Then can fail on a page that turns the button off.
export async function S02(
  page: Page,
  account: Account,
  open: Open,
  send: (email: string) => Promise<void>
) {
  await open(account.id);
  const d = await dialog(page);

  await field(d, 'User email').fill('invalid@email.com');
  await field(d, 'User email').blur();
  // The words differ by host and version ("your current email", "the user's
  // email"); what matters is that the mismatch is named
  const error = d.getByText(/This email doesn't match/);
  await expect(error).toBeVisible();

  await submit(d, 'Delete account');
  await expect(modalTitle(page, TITLE)).toBeVisible();
  await expect(error).toBeVisible();

  await send('invalid@email.com');
  expect(stateOf(account.id)).toEqual(untouched);
}

// @S03 A superuser account can't be scheduled for deletion
//   Given the modal is open for superuser "root@example.org"
//   When I set "User email" to "root@example.org"
//   Then I see "You can't delete a superuser account."
//   When I click "Delete account"
//   Then "root@example.org" is not disabled or scheduled for deletion
// One version says so as the email is typed, another once it is sent; both
// say it before the account could change.
export async function S03(page: Page, superuser: Account, open: Open) {
  await open(superuser.id);
  const d = await dialog(page);

  await field(d, 'User email').fill(superuser.email);
  await field(d, 'User email').blur();
  await submit(d, 'Delete account');

  await expect(
    d.getByText("You can't delete a superuser account.")
  ).toBeVisible();
  expect(stateOf(superuser.id)).toEqual(untouched);
}

// @S04 A matching email schedules the account and hands off
//   Given the modal is open on "<host>" for unscheduled non-superuser "amara@example.org"
//   When I set "User email" to "amara@example.org"
//   And I click "Delete account"
//   Then "amara@example.org" is disabled and scheduled for deletion
//   And I am sent to "<next>"
//   And the flow "flow-account-revocation-teardown" has started for "amara@example.org"
// The flow has started when the account's sessions are gone.
export async function S04(
  page: Page,
  browser: Browser,
  account: Account,
  open: Open,
  next: string
) {
  const elsewhere = await otherSession(browser, account.email);
  const sessions = () =>
    sql<{ n: number }>(
      `select count(*)::int as n from user_tokens
       where context = 'session' and user_id = '${account.id}'`
    )[0].n;
  expect(sessions()).toBeGreaterThan(0);
  await open(account.id);
  const d = await dialog(page);

  await field(d, 'User email').fill(account.email);
  await field(d, 'User email').blur();
  await submit(d, 'Delete account');

  await expectAt(page, next);
  expect(stateOf(account.id)).toEqual({ disabled: true, scheduled: true });
  expect(sessions()).toBe(0);
  await elsewhere.context().close();
}

const ACTIVITY_NOTE =
  'activity related to active projects. We may not be able to delete them entirely from the app until those projects are deleted.';

// @S05 An account that has created runs is warned it may stay
//   Given user "amara@example.org" has started a run
//   And "amara@example.org" is not scheduled for deletion
//   When the modal opens for "amara@example.org"
//   Then I see "activity related to active projects. ..."
//   Given user "bob@example.org" has never started a run
//   When the modal opens for "bob@example.org"
//   Then I do not see that note
export async function S05(
  page: Page,
  withRun: Account,
  withoutRun: Account,
  open: Open
) {
  await open(withRun.id);
  await expect((await dialog(page)).getByText(ACTIVITY_NOTE)).toBeVisible();

  await open(withoutRun.id);
  const d = await dialog(page);
  await expect(field(d, 'User email')).toBeVisible();
  await expect(d.getByText(ACTIVITY_NOTE)).toHaveCount(0);
}

// @S06 A superuser purges an already scheduled account
//   Given I am a superuser on "/settings/users"
//   And non-superuser "amara@example.org" is scheduled for deletion and has no runs, project files or keychain credentials
//   When I click "Delete now" for "amara@example.org"
//   And I click "Delete account"
//   Then I am on "/settings/users"
//   And I see "User deleted"
//   And "amara@example.org", their project memberships and their credentials no longer exist
// `open` is the host's "Delete now". The email is typed too: one version
// asks for it before purging, the other ignores it.
export async function S06(
  page: Page,
  account: Account,
  open: Open,
  returnTo: string
) {
  await open(account.id);
  const d = await dialog(page);

  await field(d, 'User email').fill(account.email);
  await field(d, 'User email').blur();
  await submit(d, 'Delete account');

  await expectAt(page, returnTo);
  await expect(toast(page, 'User deleted')).toBeVisible();
  expect(
    sql(`select 1 from users where id = '${account.id}'
         union all select 1 from project_users where user_id = '${account.id}'
         union all select 1 from credentials where user_id = '${account.id}'`)
  ).toEqual([]);
}

// @S07 An account with runs can't be purged now
//   Given I am a superuser on "/settings/users"
//   And "amara@example.org" is scheduled for deletion and has started a run
//   When I click "Delete now" for "amara@example.org"
//   Then I see "This user cannot be deleted until their auditable activities have also been purged."
//   And I see only a "Cancel" button
export async function S07(page: Page, account: Account, open: Open) {
  await open(account.id);
  const d = await dialog(page);

  await expect(
    d.getByText(
      'This user cannot be deleted until their auditable activities have also been purged.'
    )
  ).toBeVisible();
  await expect(d.getByRole('button', { name: 'Cancel' })).toBeVisible();
  await expect(d.getByRole('button', { name: 'Delete account' })).toHaveCount(
    0
  );
  await expect(field(d, 'User email')).toHaveCount(0);
}

// @S08 A purge blocked by remaining activity changes nothing
//   Given I am a superuser with the delete now modal open for scheduled user "amara@example.org"
//   And "amara@example.org" has a run, a project file or a keychain credential the modal did not count
//   When I click "Delete account"
//   Then I am on "/settings/users"
//   And I see "Cannot delete user with associated activity"
//   And I do not see "User deleted"
//   And "amara@example.org" still exists with their memberships and credentials
// `addActivity` gives the account a run once the modal is open.
export async function S08(
  page: Page,
  account: Account,
  open: Open,
  addActivity: () => void,
  returnTo: string
) {
  await open(account.id);
  const d = await dialog(page);
  addActivity();

  await field(d, 'User email').fill(account.email);
  await field(d, 'User email').blur();
  await submit(d, 'Delete account');

  await expectAt(page, returnTo);
  // The reason's words differ by version; what matters is the refusal
  await expect(toast(page, 'Cannot delete user')).toBeVisible();
  await expect(toast(page, 'User deleted')).toHaveCount(0);
  expect(sql(`select 1 from users where id = '${account.id}'`)).toHaveLength(1);
}

// @S09 Backing out returns to the host and changes nothing
//   Given the modal is open on "<host>" for user "amara@example.org"
//   When I click <control>
//   Then I am on "<return_to>"
//   And "amara@example.org" is not disabled or scheduled for deletion
export async function S09(
  page: Page,
  account: Account,
  open: Open,
  control: string,
  returnTo: string
) {
  await open(account.id);
  const d = await dialog(page);

  // Any case: today's close button is named "close"
  await d
    .getByRole('button', { name: new RegExp(`^${control}$`, 'i') })
    .click();

  await expectAt(page, returnTo);
  await expect(modalTitle(page, TITLE)).toHaveCount(0);
  expect(stateOf(account.id)).toEqual(untouched);
}
