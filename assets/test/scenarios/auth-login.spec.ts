// Scenarios from annotations/views/auth-login.md.
//
// Who's who: "amara@example.org" is editor@openfn.org (Esther Editor) and
// "kofi@example.org" is owner@openfn.org (Olivia Owner), both seeded with the
// shared password. Every test puts the account(s) it touches back as found.
import { expect, test } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import {
  attemptLogin,
  changePassword,
  disableAccount,
  expectAt,
  expectSignedInAs,
  expectSignedOut,
  field,
  firstSetupOpen,
  keepAccount,
  loginAlert,
  logOut,
  otherSession,
  PASSWORD,
  passwordEye,
  REMEMBER_COOKIE,
  reopenBrowser,
  resetPasswordLinkFor,
  scheduledForDeletion,
  seedMfaFor,
  sessionOf,
  signInAs,
  submitLogin,
  unconfirmedSince,
  withAuthProvider,
  withFlag,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const LOGIN = '/users/log_in';
const INVALID = 'Invalid email or password';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), keepAccount(OTHER)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// @S01
// Scenario: Log in with email and password
//   Given "amara@example.org" is a registered user with password "a long password"
//   And I am not logged in
//   When I open "/users/log_in"
//   And I fill in "Email" with "amara@example.org"
//   And I fill in "Password" with "a long password"
//   And I click "Log in"
//   Then I am logged in as "amara@example.org"
//   And the flow "flow-login-return-to" continues from here
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  await attemptLogin(page, ME);

  await expectSignedInAs(page, ME);
});

// @S02
// Scenario Outline: Wrong credentials are refused with one message
//   Given "amara@example.org" is a registered user with password "a long password"
//   When I log in with "<email>" and "<password>"
//   Then I am on the log in page
//   And I see "Invalid email or password"
//   And I am not logged in
//   Examples: wrong password; unknown email; empty password
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  const rows = [
    [ME, 'wrong password'],
    ['nobody@example.org', PASSWORD],
    [ME, ''],
  ];
  const messages: string[] = [];
  for (const [email, password] of rows) {
    await attemptLogin(page, email, password);

    await expectAt(page, LOGIN);
    await expect(loginAlert(page)).toContainText(INVALID);
    messages.push(await loginAlert(page).innerText());
    await expectSignedOut(page);
  }
  // Nothing in the response tells the three cases apart
  expect(new Set(messages).size).toBe(1);
});

// @S03
// Scenario: Email capitalisation does not matter
//   Given "amara@example.org" is a registered user with password "a long password"
//   When I log in with "Amara@Example.org" and "a long password"
//   Then I am logged in as "amara@example.org"
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  await attemptLogin(
    page,
    ME.replace(/^./, c => c.toUpperCase())
  );

  await expectSignedInAs(page, ME);
});

// @S04
// Scenario Outline: Blocked accounts can't log in even with the right password
//   Given "<email>" is a registered user whose account is <state>
//   When I log in with "<email>" and the right password
//   Then I am on the log in page
//   And I see "<message>"
//   And I am not logged in
//   Examples: disabled; scheduled for deletion
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  disableAccount(ME);
  cleanups.push(scheduledForDeletion(OTHER));
  // The wording is undecided (open question 1), so only that a message shows
  for (const email of [ME, OTHER]) {
    await attemptLogin(page, email);

    await expectAt(page, LOGIN);
    await expect(loginAlert(page)).toBeVisible();
    await expectSignedOut(page);
  }
});

// @S05
// Scenario: An account with MFA is sent to its second factor
//   Given "amara@example.org" has MFA enabled
//   When I log in with "amara@example.org" and the right password
//   Then I am on "/users/two-factor"
//   And when I visit "/projects" I am sent back to "/users/two-factor"
test('@S05', { tag: '@passing-old' }, async ({ page }) => {
  seedMfaFor(ME);

  await attemptLogin(page, ME);

  await expectAt(page, '/users/two-factor');
  await page.goto('/projects');
  await expectAt(page, '/users/two-factor');
});

// @S06
// Scenario: Keep me logged in for 60 days
//   Given "amara@example.org" is a registered user without MFA
//   When I log in with "amara@example.org" and the right password
//   And I had ticked "Keep me logged in for 60 days"
//   Then a signed remember-me cookie valid for 60 days is set
//   And after the browser session ends I am still logged in
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  await attemptLogin(page, ME, PASSWORD, { remember: true });
  await expectAt(page, '/projects');

  // Whatever it is called, a cookie that outlives the session lasts 60 days
  const days = (await page.context().cookies())
    .filter(c => c.expires !== -1)
    .map(c => (c.expires - Date.now() / 1000) / 86400);
  expect(
    days.some(d => d > 59 && d < 61),
    'a cookie that lasts 60 days'
  ).toBe(true);

  await reopenBrowser(page);
  await page.goto('/projects');
  await expectAt(page, '/projects');
});

// @S07
// Scenario: Without "Keep me logged in", closing the browser ends the session
//   Given "amara@example.org" is a registered user without MFA
//   When I log in without ticking "Keep me logged in for 60 days"
//   Then no remember-me cookie is set
test('@S07', { tag: '@passing-old' }, async ({ page }) => {
  await attemptLogin(page, ME);
  await expectAt(page, '/projects');

  const names = (await page.context().cookies()).map(c => c.name);
  expect(names).not.toContain(REMEMBER_COOKIE);
  // Closing the browser takes the session cookie with it
  await reopenBrowser(page);
  await expectSignedOut(page);
});

// @S08
// Scenario: "Keep me logged in" waits for the second factor
//   Given "amara@example.org" has MFA enabled
//   When I log in with the right password and "Keep me logged in for 60 days" ticked
//   Then no remember-me cookie is set yet
//   And I am on "/users/two-factor" with my choice carried along
test('@S08', { tag: '@passing-old' }, async ({ page }) => {
  seedMfaFor(ME);

  await attemptLogin(page, ME, PASSWORD, { remember: true });

  await expectAt(page, '/users/two-factor');
  // No cookie that outlives the session, whatever its name, gets past the
  // second factor. Carrying the choice to the second factor is proven where
  // the second factor is completed (auth-two-factor).
  await reopenBrowser(page);
  await expectSignedOut(page);
});

// @S09
// Scenario: Logging in starts a fresh session
//   Given my browser holds a session with other values in it
//   When I log in successfully
//   Then the session id is renewed
//   And nothing from the old session remains except the page I was going to
test('@S09', { tag: '@passing-old' }, async ({ page, browser }) => {
  // Asking for a protected page puts the return path in the session
  await page.goto('/profile');
  await expectAt(page, LOGIN);
  const session = async () =>
    (await page.context().cookies()).find(c => c.name === '_lightning_key')!;
  const old = await session();
  const before = sessionOf(old.value);
  expect(before, 'the old session holds values').toHaveProperty('_csrf_token');

  await submitLogin(page, ME, PASSWORD);

  // The page I was going to survives
  await expectAt(page, '/profile');
  expect((await session()).value).not.toBe(old.value);
  // Nothing from the old session remains except the page I was going to
  const after = sessionOf((await session()).value);
  for (const [key, value] of Object.entries(before)) {
    if (key === 'user_return_to') continue;
    expect(after[key], `old session value ${key}`).not.toEqual(value);
  }
  // The old session can't be used to reach the account
  const planted = await browser.newContext({
    baseURL: test.info().project.use.baseURL,
  });
  await planted.addCookies([old]);
  const other = await planted.newPage();
  await other.goto('/projects');
  await expectAt(other, LOGIN);
  await planted.close();
});

// @S10
// Scenario: A signed-in visitor is sent to their projects
//   Given I am logged in
//   When I open "/users/log_in"
//   Then I am on "/projects"
test('@S10', { tag: '@passing-old' }, async ({ page }) => {
  await signInAs(page, ME);

  await page.goto(LOGIN);

  await expectAt(page, '/projects');
});

// @S11
// Scenario: Forgot your password?
//   Given I am not logged in
//   When I open "/users/log_in"
//   Then I see a "Forgot your password?" link to "/users/reset_password"
test('@S11', { tag: '@passing-old' }, async ({ page }) => {
  await page.goto(LOGIN);

  const link = page.getByRole('link', { name: 'Forgot your password?' });
  await expect(link).toHaveAttribute('href', '/users/reset_password');
  await link.click();
  await expectAt(page, '/users/reset_password');
});

// @S12
// Scenario: A deep link opened while signed out continues after login
//   Given the flow "flow-login-return-to" brought me here from a page that needs login
//   When I log in successfully
//   Then the flow "flow-login-return-to" continues to the page I asked for
test('@S12', { tag: '@passing-old' }, async ({ page }) => {
  await page.goto('/profile/tokens');
  await expectAt(page, LOGIN);

  await submitLogin(page, ME, PASSWORD);

  await expectAt(page, '/profile/tokens');
});

// @S13 @variant:signup-allowed
// Scenario Outline: Register link only where self-signup is allowed
//   Given self-signup is <setting>
//   When I open "/users/log_in"
//   Then I <see> a "Register" link to "/users/register"
//   Examples: allowed; disabled
test('@S13', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const register = page.getByRole('link', { name: 'Register', exact: true });

  const restore = withFlag('allow_signup', true);
  try {
    await page.goto(LOGIN);
    await expect(register).toHaveAttribute('href', '/users/register');

    withFlag('allow_signup', false);
    await page.goto(LOGIN);
    await expect(
      page.getByRole('link', { name: 'Forgot your password?' })
    ).toBeVisible();
    await expect(register).toHaveCount(0);
  } finally {
    restore();
  }
});

// @S14
// Scenario: An invited collaborator who has set a password logs in here
//   Given the flow "flow-invite-new-collaborator" has reset my password
//   When I arrive on "/users/log_in"
//   Then I see "Password reset successfully."
//   And I can log in as in S01
test('@S14', { tag: '@passing-old' }, async ({ page }) => {
  const next = 'a brand new password 42';
  await page.goto(resetPasswordLinkFor(ME));
  await field(page, 'New password').fill(next);
  await field(page, 'Confirm new password').fill(next);
  await page.getByRole('button', { name: 'Reset password' }).click();

  await expectAt(page, LOGIN);
  await expect(page.getByText('Password reset successfully.')).toBeVisible();
  await submitLogin(page, ME, next);
  await expectSignedInAs(page, ME);
});

// @S15
// Scenario: A revoked browser lands here and can sign in again
//   Given the flow "flow-account-revocation-teardown" has revoked my sessions on this browser
//   Then this browser is on "/users/log_in"
//   When I log in with my old password
//   Then I see "Invalid email or password"
test('@S15', { tag: '@passing-old' }, async ({ page, browser }) => {
  await signInAs(page, ME);
  const elsewhere = await otherSession(browser, ME);
  await changePassword(elsewhere, ME, PASSWORD, 'a changed password 42');
  await elsewhere.context().close();

  await page.goto('/projects');
  await expectAt(page, LOGIN);

  await submitLogin(page, ME, PASSWORD);

  await expect(page.getByText(INVALID)).toBeVisible();
  await expectSignedOut(page);

  // Only the current credentials work
  await submitLogin(page, ME, 'a changed password 42');
  await expectSignedInAs(page, ME);
});

// @S16
// Scenario: Logging out lands here with a confirmation
//   Given I am logged in
//   When I log out
//   Then I am on "/users/log_in"
//   And I see "Logged out successfully."
test('@S16', { tag: '@passing-old' }, async ({ page }) => {
  await signInAs(page, ME);

  await logOut(page, ME);

  await expectAt(page, LOGIN);
  await expect(page.getByText('Logged out successfully.')).toBeVisible();
});

// @S17 @variant:sso-provider
// Scenario Outline: External provider button only when one is configured
//   Given an external authentication provider is <configured>
//   When I open "/users/log_in"
//   Then I <see> "via external provider"
//   Examples: configured; not configured
test('@S17', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const button = page.getByRole('link', { name: 'via external provider' });

  const remove = withAuthProvider('acme');
  try {
    await page.goto(LOGIN);
    await expect(button).toBeVisible();
  } finally {
    remove();
  }

  await page.goto(LOGIN);
  await expect(page.getByRole('button', { name: 'Log in' })).toBeVisible();
  await expect(button).toHaveCount(0);
});

// @S18 @variant:sso-provider
// Scenario: The external provider button starts single sign-on
//   Given an external authentication provider "acme" is configured
//   When I click "via external provider"
//   Then I am sent to "/authenticate/acme"
//   And the flow "flow-sso-login" has started
test('@S18', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const remove = withAuthProvider('acme');
  try {
    await page.goto(LOGIN);

    // The stand-in provider has no real endpoints, so only the hop is asserted
    const [request] = await Promise.all([
      page.waitForRequest(
        r => new URL(r.url()).pathname === '/authenticate/acme'
      ),
      page.getByRole('link', { name: 'via external provider' }).click(),
    ]);
    expect(new URL(request.url()).pathname).toBe('/authenticate/acme');
  } finally {
    remove();
  }
});

// @S19 @variant:first-setup-open
// Scenario: A fresh install sends visitors to first setup
//   Given first setup is allowed
//   And there is no superuser
//   When I open "/users/log_in"
//   Then I am on "/first_setup"
test('@S19', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  const restore = firstSetupOpen();
  try {
    await authenticatedSession.S11(page, LOGIN);
  } finally {
    restore();
  }
});

// @S20 @variant:require-email-verification
// Scenario: An account past its confirmation deadline logs in and is sent to confirm
//   Given my account was created 50 hours ago and my email is unconfirmed
//   When I log in with the right password
//   Then I am logged in
//   And the gate in shared-authenticated-session S04 sends me to "/users/confirm-required"
test('@S20', { tag: ['@passing-old', '@serial'] }, async ({ page }) => {
  cleanups.push(unconfirmedSince(ME, 50));
  cleanups.push(withFlag('require_email_verification', true));

  await attemptLogin(page, ME);

  await expectAt(page, '/users/confirm-required');
  // I am logged in: the log in page now sends me on instead of showing the form
  await page.goto(LOGIN);
  await expect(page).not.toHaveURL(/\/users\/log_in/);
});

// @S21
// Scenario: Reveal the password I typed
//   Given I am not logged in
//   When I open "/users/log_in"
//   And I type "a long password" into "Password"
//   And I click the eye icon in the password field
//   Then the password field shows "a long password" as plain text
//   And clicking the eye again hides it
test('@S21', { tag: '@passing-old' }, async ({ page }) => {
  await page.goto(LOGIN);
  const password = field(page, 'Password');
  await password.fill('a long password');

  await passwordEye(page, 'Password').click();

  await expect(password).toHaveAttribute('type', 'text');
  await expect(password).toHaveValue('a long password');

  await passwordEye(page, 'Password').click();

  await expect(password).toHaveAttribute('type', 'password');
});

// Inherited from shared-authenticated-session. Only S11 is reachable here.
// S01 to S06 are gates of the :require_authenticated_user scope; the inherits
// comment says "Its S01 to S06 gates do not run here: this scope has no
// :require_authenticated_user". S04 is exercised through this page's own S20.
// S07 to S10 (sidebar, book-a-demo and GDPR banners) are chrome of the signed-in
// app layout, which this controller page does not render; they need another page.
test.describe('shared-authenticated-session', () => {
  // @S11 @variant:first-setup-open
  // Scenario: An instance with no superuser sends pages to first setup
  //   Given first setup is allowed
  //   And there is no superuser
  //   When I visit "/users/log_in"
  //   Then I am on "/first_setup"
  test(
    'shared-authenticated-session@S11 on auth-login',
    { tag: ['@passing-old', '@serial'] },
    async ({ page }) => {
      const restore = firstSetupOpen();
      try {
        await authenticatedSession.S11(page, LOGIN);
      } finally {
        restore();
      }
    }
  );
});

// Inherited from shared-flash-messages. Only S08 (the inline form flash) is
// reachable. S01 to S07 are toasts of the LiveView layout; this page is a
// controller template that shows its info and error flashes inside the form
// (new.html.heex), including the ones carried in by a redirect (S14, S16), so
// there is no toast to test. They need a LiveView page.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S08 on auth-login',
    { tag: '@passing-old' },
    async ({ page }) => {
      await page.goto(LOGIN);
      await flashMessages.S08(
        page,
        INVALID,
        () => submitLogin(page, ME, 'wrong password'),
        field(page, 'Email')
      );
    }
  );
});
