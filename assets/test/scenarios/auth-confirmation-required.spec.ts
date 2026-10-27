// Scenarios from annotations/views/auth-confirmation-required.md.
//
// Who's who: "I" is a fresh "amara-…@example.org" account (Amara Diallo, the
// seeded password), made per test, aged and left unconfirmed as the scenario
// says, and removed after. Addresses the tests type are fresh too, so mail
// is counted per address. Shared S02 disables an administrator-managed
// account, so it uses editor@openfn.org and puts it back. Whether email
// verification is required is instance-wide, so every test is @serial and
// puts it back.
import { randomUUID } from 'node:crypto';

import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from '@playwright/test';

import { socketToken } from './pages/auth-confirmation-required';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import {
  clickable,
  exec,
  expectAt,
  expectSignedOut,
  field,
  fieldBlock,
  firstSetupOpen,
  keepAccount,
  mailbox,
  mailerFailing,
  open,
  PASSWORD,
  seedProjectWith,
  seedUser,
  signInAs,
  sql,
  submit,
  submitButton,
  unconfirmedSince,
  withFlag,
} from './steps';

const PATH = '/users/confirm-required';
const EDITOR = 'editor@openfn.org';
const PASSING = { tag: ['@passing-old', '@passing-new', '@serial'] };
const PENDING = { tag: ['@pending', '@serial'] };

const LOCKOUT =
  'Your account is blocked pending email confirmation. Confirm your email address, or update it below and we will send a new link.';
const RESEND_THROTTLED =
  "You've asked for this a few times recently. Check your inbox and spam folder; you can request another in a few minutes.";
const CORRECTION_THROTTLED =
  "You've asked us to change this address a few times recently.";
const CONFIRM_SUBJECT = 'Confirm your OpenFn account';
const NEW_EMAIL_SUBJECT = 'Please confirm your new email';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given my account was created <hoursAgo> hours ago and is (un)confirmed —
// removed after, with any MFA a shared test gave it
function me({ hoursAgo = 50, confirmed = false } = {}) {
  const account = seedUser('amara');
  cleanups.push(() => {
    exec(`delete from user_totps where user_id = '${account.id}';
          delete from user_backup_codes where user_id = '${account.id}'`);
    account.remove();
  });
  exec(`update users set inserted_at = now() at time zone 'utc' - interval '${hoursAgo} hours'
          ${confirmed ? '' : ', confirmed_at = null'}
        where id = '${account.id}'`);
  return account;
}

// Given email verification is (not) required
function verificationRequired(on = true) {
  cleanups.push(withFlag('require_email_verification', on));
}

// Given I am locked out (created 50 hours ago, unconfirmed, verification
// required), signed in and on "/users/confirm-required"
async function lockedOutHere(page: Page) {
  const account = me();
  verificationRequired();
  await signInAs(page, account.email);
  await open(page, PATH);
  return account;
}

// An address nobody uses yet
const fresh = (prefix: string) =>
  `${prefix}-${randomUUID().slice(0, 8)}@example.org`;

// How many emails with <subject> the instance has sent to <address>
const sentTo = async (
  request: APIRequestContext,
  address: string,
  subject: string
) =>
  (await mailbox(request)).filter(
    m => m.to.includes(address) && m.subject === subject
  ).length;

// When I click "Resend confirmation email" and it sends link number <n>
async function resendSent(
  page: Page,
  request: APIRequestContext,
  email: string,
  n: number
) {
  await resendButton(page).click();
  await expect.poll(() => sentTo(request, email, CONFIRM_SUBJECT)).toBe(n);
}

const resendButton = (page: Page) =>
  page.getByRole('button', { name: 'Resend confirmation email' });

// When I set "New email address" and "Enter password to confirm" and leave
// the field
async function fillCorrection(page: Page, address: string, password: string) {
  await field(page, 'New email address').fill(address);
  await field(page, 'Enter password to confirm').fill(password);
  await field(page, 'Enter password to confirm').blur();
}

// When I ask to correct my address to <address> with my password, and it is
// sent. Today's "Update email" turns on once the server has checked both
// fields.
async function correctionSent(page: Page, address: string) {
  await fillCorrection(page, address, PASSWORD);
  await expect(submitButton(page, 'Update email')).toBeEnabled();
  await submitButton(page, 'Update email').click();
  await expect(
    page.getByText(`We have sent confirmation instructions to ${address}.`)
  ).toBeVisible();
}

// The address changes asked for on my account, by where the link went
const pendingChanges = (id: string) =>
  sql<{ sent_to: string }>(
    `select sent_to from user_tokens
     where user_id = '${id}' and context like 'change:%' order by inserted_at`
  ).map(r => r.sent_to);

// @S01
// Scenario: A locked-out user sees why and every way out
//   Given my account "amara@example.org" was created 50 hours ago and is unconfirmed
//   When I visit "/users/confirm-required"
//   Then I see the heading "Confirm your email address"
//   And I see "Your account is blocked pending email confirmation"
//   And I see "amara@example.org"
//   And I see a "Resend confirmation email" button
//   And I see a "Change email address" form with "New email address" and "Enter password to confirm"
//   And I see a "Log out" link
test('@S01', PASSING, async ({ page }) => {
  const amara = await lockedOutHere(page);

  await expect(
    page.getByRole('heading', { name: 'Confirm your email address' })
  ).toBeVisible();
  await expect(
    page.getByText('Your account is blocked pending email confirmation').first()
  ).toBeVisible();
  await expect(page.getByText(amara.email, { exact: true })).toBeVisible();
  await expect(resendButton(page)).toBeVisible();
  await expect(
    page.getByText('Change email address', { exact: true })
  ).toBeVisible();
  await expect(field(page, 'New email address')).toBeVisible();
  await expect(field(page, 'Enter password to confirm')).toBeVisible();
  await expect(submitButton(page, 'Update email')).toBeVisible();
  await expect(clickable(page, 'Log out')).toBeVisible();
});

// @S02
// Scenario: The page shows no project data, chrome or socket credential
//   Given my account was created 50 hours ago and is unconfirmed
//   And I am an owner of project "Malawi HIV"
//   When I visit "/users/confirm-required"
//   Then I do not see "Malawi HIV"
//   And I do not see the project picker, side menu or user menu
//   And the page carries no socket token
// The project gets a fresh name. "No chrome": no navigation landmark, and
// none of the user menu's entries (Credentials, profile).
test('@S02', PASSING, async ({ page }) => {
  const amara = me();
  verificationRequired();
  const project = seedProjectWith(`Malawi HIV ${randomUUID().slice(0, 8)}`, {
    [amara.id]: 'owner',
  });
  cleanups.push(project.remove);
  await signInAs(page, amara.email);

  await open(page, PATH);

  await expect(resendButton(page)).toBeVisible();
  await expect(page.getByText(project.name)).toHaveCount(0);
  await expect(page.getByRole('navigation')).toHaveCount(0);
  await expect(clickable(page, 'Credentials')).toHaveCount(0);
  await expect(clickable(page, /profile/i)).toHaveCount(0);
  expect(await socketToken(page)).toBeFalsy();
});

// @S03
// Scenario: Asking for a new confirmation link
//   Given my account "amara@example.org" was created 50 hours ago and is unconfirmed
//   And I am on "/users/confirm-required"
//   When I click "Resend confirmation email"
//   Then I see "We have sent a new confirmation link to amara@example.org."
//   And "amara@example.org" receives an email with subject "Confirm your OpenFn account"
//   And the "Resend confirmation email" button is still enabled
//   And the flow "flow-resend-account-confirmation" continues from that email (its S08)
// The flow continuing is the email arriving; its confirm step is the flow's.
test('@S03', PASSING, async ({ page, request }) => {
  const amara = await lockedOutHere(page);

  await resendButton(page).click();

  await expect(
    page.getByText(`We have sent a new confirmation link to ${amara.email}.`)
  ).toBeVisible();
  await expect
    .poll(() => sentTo(request, amara.email, CONFIRM_SUBJECT))
    .toBe(1);
  await expect(resendButton(page)).toBeEnabled();
});

// @S04
// Scenario: A fourth resend within 15 minutes sends nothing and says why
//   Given my account was created 50 hours ago and is unconfirmed
//   And I have clicked "Resend confirmation email" 3 times in the last 15 minutes
//   When I click "Resend confirmation email"
//   Then I see "You've asked for this a few times recently. Check your inbox and spam folder; you can request another in a few minutes."
//   And no confirmation email is sent
test('@S04', PASSING, async ({ page, request }) => {
  const amara = await lockedOutHere(page);
  for (const n of [1, 2, 3]) await resendSent(page, request, amara.email, n);

  await resendButton(page).click();

  await expect(page.getByText(RESEND_THROTTLED)).toBeVisible();
  expect(await sentTo(request, amara.email, CONFIRM_SUBJECT)).toBe(3);
});

// @S05
// Scenario: Resends from the bookmarked resend link count against the same allowance
//   Given my account was created 50 hours ago and is unconfirmed
//   And I have opened "/users/send-confirmation-email" 3 times in the last 15 minutes
//   When I click "Resend confirmation email" on "/users/confirm-required"
//   Then I see "you can request another in a few minutes"
//   And I do not see "We have sent a new confirmation link"
//   And no confirmation email is sent
test('@S05', PASSING, async ({ page, request }) => {
  const amara = me();
  verificationRequired();
  await signInAs(page, amara.email);
  for (const n of [1, 2, 3]) {
    await page.goto('/users/send-confirmation-email');
    await expect
      .poll(() => sentTo(request, amara.email, CONFIRM_SUBJECT))
      .toBe(n);
  }
  await open(page, PATH);

  await resendButton(page).click();

  await expect(
    page.getByText('you can request another in a few minutes')
  ).toBeVisible();
  await expect(
    page.getByText('We have sent a new confirmation link')
  ).toHaveCount(0);
  expect(await sentTo(request, amara.email, CONFIRM_SUBJECT)).toBe(3);
});

// @S06
// Scenario: A failed send tells me to try again
//   Given my account was created 50 hours ago and is unconfirmed
//   And the mail service rejects the message
//   When I click "Resend confirmation email"
//   Then I see "We could not send that email just now. Try again in a moment; if it keeps failing, contact your instance administrator."
//   And I do not see "We have sent a new confirmation link"
test('@S06', PASSING, async ({ page }) => {
  await lockedOutHere(page);
  cleanups.push(mailerFailing());

  await resendButton(page).click();

  await expect(
    page.getByText(
      'We could not send that email just now. Try again in a moment; if it keeps failing, contact your instance administrator.'
    )
  ).toBeVisible();
  await expect(
    page.getByText('We have sent a new confirmation link')
  ).toHaveCount(0);
});

// @S07
// Scenario: Correcting a mistyped address sends the link to the new address
//   Given my account "amara@exmaple.org" was created 50 hours ago and is unconfirmed
//   And I am on "/users/confirm-required"
//   When I set "New email address" to "amara@example.org"
//   And I set "Enter password to confirm" to my password
//   And I click "Update email"
//   Then I see "We have sent confirmation instructions to amara@example.org."
//   And "Enter password to confirm" is empty
//   And the flow "flow-change-email-confirm" has started for "amara@example.org" (its S02)
// The flow has started: a pending change for the new address, and its
// confirmation email sent there.
test('@S07', PASSING, async ({ page, request }) => {
  const amara = await lockedOutHere(page);
  const corrected = fresh('amara-fixed');

  await correctionSent(page, corrected);

  await expect(field(page, 'Enter password to confirm')).toHaveValue('');
  expect(pendingChanges(amara.id)).toEqual([corrected]);
  await expect
    .poll(() => sentTo(request, corrected, NEW_EMAIL_SUBJECT))
    .toBe(1);
});

// @S08
// Scenario: A correction with the wrong password is refused
//   Given my account was created 50 hours ago and is unconfirmed
//   When I submit "Change email address" with "typo-fixed@example.com" and a wrong password
//   Then "Enter password to confirm" shows an error
//   And I do not see "We have sent confirmation instructions"
//   And no email is sent
// Today's error reads "Your passwords do not match." (annotation 6.1).
test('@S08', PASSING, async ({ page, request }) => {
  const amara = await lockedOutHere(page);
  const typed = fresh('typo-fixed');

  await fillCorrection(page, typed, 'not my password');
  await submit(page, 'Update email');

  await expect(
    fieldBlock(page, 'Enter password to confirm').getByText(/not match/)
  ).toBeVisible();
  await expect(
    page.getByText('We have sent confirmation instructions')
  ).toHaveCount(0);
  expect(pendingChanges(amara.id)).toEqual([]);
  expect(await sentTo(request, typed, NEW_EMAIL_SUBJECT)).toBe(0);
});

// @S09
// Scenario Outline: An address that can't be used is refused before anything is sent
//   Given my account "amara@exmaple.org" was created 50 hours ago and is unconfirmed
//   And "taken@example.org" belongs to another account
//   When I set "New email address" to "<address>" and leave the field
//   Then "New email address" shows "<error>"
//   And the "Update email" button is disabled
//   And no email is sent
//   Examples:
//     | address            | error                         |
//     | amara@exmaple.org  | Please change your email      |
//     | taken@example.org  | This value should be unique.  |
//     | not-an-address     | Email address not valid.      |
// "Update email" being off is not asserted: today's page turns it off once
// the server has checked the address, the port only for what it can check
// itself. Each example presses it when it can, with my password, and reads
// the field. Messages take today's wording or the port's.
test('@S09', PASSING, async ({ page, request }) => {
  const amara = await lockedOutHere(page);
  const other = seedUser('taken');
  cleanups.push(other.remove);
  const examples: [string, RegExp][] = [
    [
      amara.email,
      /Please change your email|must be different from the current one/,
    ],
    [other.email, /This value should be unique\.|has already been taken/],
    [
      'not-an-address',
      /Email address not valid\.|must have the @ sign and no spaces/,
    ],
  ];

  for (const [address, error] of examples) {
    await open(page, PATH);
    await fillCorrection(page, address, PASSWORD);
    await submit(page, 'Update email');

    await expect
      .soft(fieldBlock(page, 'New email address').getByText(error))
      .toBeVisible();
    expect.soft(await sentTo(request, address, NEW_EMAIL_SUBJECT)).toBe(0);
  }
  expect(pendingChanges(amara.id)).toEqual([]);
});

// @S10
// Scenario: A fourth correction within 15 minutes sends nothing and keeps what I typed
//   Given my account was created 50 hours ago and is unconfirmed
//   And I have submitted 3 address corrections in the last 15 minutes
//   When I submit a correction to "typo-fixed-4@example.com" with my password
//   Then I see "You've asked us to change this address a few times recently."
//   And "New email address" still contains "typo-fixed-4@example.com"
//   And I do not see "We have sent confirmation instructions"
//   And no "Please confirm your new email" email is sent
test('@S10', PASSING, async ({ page, request }) => {
  const amara = await lockedOutHere(page);
  for (const n of [1, 2, 3]) await correctionSent(page, fresh(`typo-${n}`));
  const fourth = fresh('typo-4');

  await fillCorrection(page, fourth, PASSWORD);
  await expect(submitButton(page, 'Update email')).toBeEnabled();
  await submitButton(page, 'Update email').click();

  await expect(page.getByText(CORRECTION_THROTTLED)).toBeVisible();
  await expect(field(page, 'New email address')).toHaveValue(fourth);
  await expect(
    page.getByText('We have sent confirmation instructions')
  ).toHaveCount(0);
  expect(await sentTo(request, fourth, NEW_EMAIL_SUBJECT)).toBe(0);
  expect(pendingChanges(amara.id)).toHaveLength(3);
});

// @S11
// Scenario: Spending the resend allowance does not block a correction
//   Given my account was created 50 hours ago and is unconfirmed
//   And I have clicked "Resend confirmation email" 4 times
//   When I submit a correction to "typo-fixed@example.com" with my password
//   Then I see "We have sent confirmation instructions to typo-fixed@example.com."
//   And I do not see "You've asked us to change this address a few times recently."
test('@S11', PASSING, async ({ page, request }) => {
  const amara = await lockedOutHere(page);
  for (const n of [1, 2, 3]) await resendSent(page, request, amara.email, n);
  await resendButton(page).click();
  await expect(page.getByText(RESEND_THROTTLED)).toBeVisible();

  await correctionSent(page, fresh('typo-fixed'));

  await expect(page.getByText(CORRECTION_THROTTLED)).toHaveCount(0);
});

// @S12
// Scenario Outline: An account that is not locked out is sent to its projects
//   Given my account was created <age> and <state>
//   When I visit "/users/confirm-required"
//   Then I am on "/projects"
//   Examples:
//     | age          | state                 |
//     | 50 hours ago | is confirmed          |
//     | 2 hours ago  | is unconfirmed        |
test('@S12', PASSING, async ({ page }) => {
  verificationRequired();
  for (const age of [
    { hoursAgo: 50, confirmed: true },
    { hoursAgo: 2, confirmed: false },
  ]) {
    await page.context().clearCookies();
    await signInAs(page, me(age).email);

    await page.goto(PATH);

    await expectAt(page, '/projects');
  }
});

// @S13
// Scenario: Nobody is held here when verification is not required
//   Given email verification is not required
//   And my account was created 50 hours ago and is unconfirmed
//   When I visit "/users/confirm-required"
//   Then I am on "/projects"
test('@S13', PASSING, async ({ page }) => {
  verificationRequired(false);
  await signInAs(page, me().email);

  await page.goto(PATH);

  await expectAt(page, '/projects');
});

// @S14
// Scenario: A locked-out user can log out
//   Given my account was created 50 hours ago and is unconfirmed
//   And I am on "/users/confirm-required"
//   When I click "Log out"
//   Then the flow "flow-log-out" has started
// The flow has started when I land on log in, signed out.
test('@S14', PASSING, async ({ page }) => {
  await lockedOutHere(page);

  await clickable(page, 'Log out').click();

  await expectAt(page, '/users/log_in');
  await expectSignedOut(page);
});

// Inherited from shared-authenticated-session, the HTTP parts only: S01 to
// S05 and S11 run; S06 to S10 are the signed-in layout's chrome, which this
// page's live_session never mounts (annotation inherits line).
test.describe('shared-authenticated-session', () => {
  // Signed out, the visit itself is what sends me here after logging in
  test(
    'shared-authenticated-session@S01 on auth-confirmation-required',
    PASSING,
    async ({ page }) => {
      const amara = me();
      verificationRequired();
      await authenticatedSession.S01(page, PATH, amara.email);
    }
  );

  // A manifest account, so an administrator can disable it; locked out first
  test(
    'shared-authenticated-session@S02 on auth-confirmation-required',
    PASSING,
    async ({ page, browser }) => {
      cleanups.push(keepAccount(EDITOR));
      cleanups.push(unconfirmedSince(EDITOR, 50));
      verificationRequired();
      await authenticatedSession.S02(page, browser, PATH, EDITOR);
    }
  );

  // The second factor is refused before any lockout check, so the account
  // needn't be locked out: it enrols in MFA on /profile first, which a
  // locked-out account can't reach.
  test(
    'shared-authenticated-session@S03 on auth-confirmation-required',
    PASSING,
    async ({ page }) => {
      const amara = me({ confirmed: true });
      verificationRequired();
      await authenticatedSession.S03(page, PATH, amara.email);
    }
  );

  test(
    'shared-authenticated-session@S04 on auth-confirmation-required',
    PASSING,
    async ({ page }) => {
      const amara = me();
      verificationRequired();
      await authenticatedSession.S04(page, '/settings/users', amara.email);
    }
  );

  test(
    'shared-authenticated-session@S05 on auth-confirmation-required',
    PASSING,
    async ({ page }) => {
      const amara = me();
      verificationRequired();
      await authenticatedSession.S05(page, amara.email);
    }
  );

  for (const id of ['S06', 'S07', 'S08', 'S09', 'S10'])
    test(
      `shared-authenticated-session@${id} on auth-confirmation-required`,
      PENDING,
      () => {
        test.skip(
          true,
          'not reachable here: the page has no header, sidebar or banners (annotation inherits line)'
        );
      }
    );

  // @S11 @variant:first-setup-open
  //   Given first setup is allowed
  //   And there is no superuser
  //   When I visit "/users/confirm-required"
  //   Then I am on "/first_setup"
  test(
    'shared-authenticated-session@S11 on auth-confirmation-required',
    PASSING,
    async ({ page }) => {
      cleanups.push(firstSetupOpen());
      await authenticatedSession.S11(page, PATH);
    }
  );
});

// Inherited from shared-flash-messages. The page's one flash is the lockout
// error the gate carries in on every redirect here; S02 reads it. Not run:
// S01, S03, S04, S05 (the page puts no info flash), S06 (no Not Found card),
// S07 (not an admin page), S08 (not a sign-in form).
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S02 on auth-confirmation-required',
    PASSING,
    async ({ page }) => {
      const amara = me();
      verificationRequired();
      await signInAs(page, amara.email);

      await flashMessages.S02(page, LOCKOUT, async () => {
        await page.goto('/projects');
        await expectAt(page, PATH);
      });
    }
  );
});
