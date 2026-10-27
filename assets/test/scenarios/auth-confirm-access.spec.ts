// Scenarios from annotations/views/auth-confirm-access.md.
//
// Who's who: "I" is a fresh "amara-…@example.org" account (Amara Diallo, the
// seeded password), made per test and removed after with its MFA. The page
// opens only for someone sent here, so each test is sent from the backup
// codes page, the one page that asks for it. Shared S02 disables an
// administrator-managed account, so it uses editor@openfn.org and puts it
// back.
import { expect, test, type Page } from '@playwright/test';

import { codeBox, passwordBox } from './pages/auth-confirm-access';
import * as authenticatedSession from './shared/authenticated-session';
import {
  clickable,
  exec,
  expectAt,
  firstSetupOpen,
  keepAccount,
  open,
  PASSWORD,
  seedUser,
  signInAs,
  sql,
  submitButton,
  totpCode,
  watchLiveView,
} from './steps';

const PATH = '/auth/confirm_access';
const SENSITIVE = '/profile/auth/backup_codes';
const EDITOR = 'editor@openfn.org';
// The authenticator secret seeded below, as an app would hold it
const SECRET = 'VOV2XK5LVOV2XK5LVOV2XK5LVOV2XK5L';
const PASSING = { tag: ['@passing-old', '@passing-new'] };
const PENDING = { tag: '@pending' };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given I am an account of my own (Amara Diallo), removed after
function me() {
  const account = seedUser('amara');
  cleanups.push(() => {
    exec(`delete from user_totps where user_id = '${account.id}';
          delete from user_backup_codes where user_id = '${account.id}'`);
    account.remove();
  });
  return account;
}

// And I have MFA enabled, with SECRET in my authenticator app
function withMfa(id: string) {
  exec(`insert into user_totps (id, user_id, secret, inserted_at, updated_at)
        values (gen_random_uuid(), '${id}', decode(repeat('ab', 20), 'hex'), now(), now());
        update users set mfa_enabled = true where id = '${id}'`);
}

// And I was sent to "Confirm access" from "/profile/auth/backup_codes"
async function sentHere(page: Page) {
  await open(page, SENSITIVE);
  await expectAt(page, PATH);
}

const sudoSessions = (id: string) =>
  sql<{ n: number }>(
    `select count(*)::int as n from user_tokens
     where context = 'sudo_session' and user_id = '${id}'`
  )[0].n;

// Then I am taken to "/profile/auth/backup_codes" with a "sudo_token"
async function expectSentBack(page: Page) {
  await expect
    .poll(() => {
      const url = new URL(page.url());
      return url.pathname === SENSITIVE && !!url.searchParams.get('sudo_token');
    })
    .toBe(true);
}

const timeStep = (at = Date.now()) => Math.floor(at / 30000);

// Waits until at least `seconds` are left in the authenticator's 30s step, so
// a code typed now is still the current one when the server checks it
async function roomInTimeStep(page: Page, seconds: number) {
  const left = 30000 - (Date.now() % 30000);
  if (left < seconds * 1000) await page.waitForTimeout(left + 500);
}

// When I click "Use your authenticator app instead" (or the way back)
const switchTo = (page: Page, name: string) => clickable(page, name).click();

// @S01
// Scenario: The page shows who is signed in and asks for the password by default
//   Given I am signed in as "Amara Diallo"
//   And I was sent to "Confirm access" from "/profile/auth/backup_codes"
//   Then I see "Confirm access"
//   And I see "Signed in as:" followed by "Amara Diallo" and the avatar "AD"
//   And I see "Password" and a password field
//   And I see "Enter your password to confirm access"
//   And I see a "Confirm" button
//   And I do not see "Authentication Code"
test('@S01', PASSING, async ({ page }) => {
  const amara = me();
  await signInAs(page, amara.email);
  await sentHere(page);

  await expect(
    page.getByRole('heading', { name: 'Confirm access' })
  ).toBeVisible();
  await expect(page.getByText(/Signed in as:\s*Amara Diallo/)).toBeVisible();
  await expect(page.getByText('AD', { exact: true })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Password' })).toBeVisible();
  await expect(passwordBox(page)).toBeVisible();
  await expect(
    page.getByText('Enter your password to confirm access')
  ).toBeVisible();
  await expect(submitButton(page, 'Confirm')).toBeVisible();
  await expect(page.getByText('Authentication Code')).toHaveCount(0);
});

// @S02
// Scenario: Correct password sends me back to the page I asked for
//   Given I am signed in
//   And I was sent to "Confirm access" from "/profile/auth/backup_codes"
//   When I enter my password and click "Confirm"
//   Then a sudo session is recorded for me
//   And I am taken to "/profile/auth/backup_codes" with a "sudo_token" query parameter, replacing "Confirm access" in history
//   And the flow "flow-reauth-backup-codes" continues on that page
// The flow continuing is the backup codes page opening with the token
// (profile-backup-codes). "Replacing in history": going back from there
// skips "Confirm access" and lands on the page I was on before.
// @pending on both apps: the return is a full page load that adds a history entry, so back lands on Confirm access.
test('@S02', PENDING, async ({ page }) => {
  const amara = me();
  await signInAs(page, amara.email);
  await open(page, '/profile');
  await sentHere(page);

  await passwordBox(page).fill(PASSWORD);
  await submitButton(page, 'Confirm').click();

  await expectSentBack(page);
  expect(sudoSessions(amara.id)).toBe(1);
  await page.goBack();
  await expectAt(page, '/profile');
});

// @S03
// Scenario: Wrong password is refused and unlocks nothing
//   Given I am signed in
//   And I was sent to "Confirm access" from "/profile/auth/backup_codes"
//   When I enter a wrong password and click "Confirm"
//   Then I see "Invalid password! Try again."
//   And I am still on "Confirm access"
//   And no sudo session is recorded for me
test('@S03', PASSING, async ({ page }) => {
  const amara = me();
  await signInAs(page, amara.email);
  await sentHere(page);

  await passwordBox(page).fill('not my password');
  await submitButton(page, 'Confirm').click();

  await expect(page.getByText('Invalid password! Try again.')).toBeVisible();
  await expectAt(page, PATH);
  expect(sudoSessions(amara.id)).toBe(0);
});

// @S04
// Scenario: Users with MFA can switch to their authenticator code and back
//   Given I am signed in with MFA enabled
//   And I was sent to "Confirm access" from "/profile/auth/backup_codes"
//   When I click "Use your authenticator app instead"
//   Then I see "Authentication Code" and a code field
//   And I see "Open your two-factor authenticator (TOTP) app or browser extension to view your authentication code."
//   And I see a "Verify" button
//   And I see "Use your password instead"
//   When I click "Use your password instead"
//   Then I see "Password" and "Enter your password to confirm access"
//   And I see "Use your authenticator app instead"
// MFA is turned on after signing in, so the sign-in needs no code.
test('@S04', PASSING, async ({ page }) => {
  const amara = me();
  await signInAs(page, amara.email);
  withMfa(amara.id);
  await sentHere(page);

  await switchTo(page, 'Use your authenticator app instead');

  await expect(
    page.getByRole('heading', { name: 'Authentication Code' })
  ).toBeVisible();
  await expect(codeBox(page)).toBeVisible();
  await expect(
    page.getByText(
      'Open your two-factor authenticator (TOTP) app or browser extension to view your authentication code.'
    )
  ).toBeVisible();
  await expect(submitButton(page, 'Verify')).toBeVisible();
  await expect(clickable(page, 'Use your password instead')).toBeVisible();

  await switchTo(page, 'Use your password instead');

  await expect(page.getByRole('heading', { name: 'Password' })).toBeVisible();
  await expect(
    page.getByText('Enter your password to confirm access')
  ).toBeVisible();
  await expect(
    clickable(page, 'Use your authenticator app instead')
  ).toBeVisible();
});

// @S05
// Scenario: Users without MFA are not offered the authenticator option
//   Given I am signed in without MFA
//   And I was sent to "Confirm access" from "/profile/auth/backup_codes"
//   Then I do not see "Use your authenticator app instead"
test('@S05', PASSING, async ({ page }) => {
  const amara = me();
  await signInAs(page, amara.email);
  await sentHere(page);

  await expect(submitButton(page, 'Confirm')).toBeVisible();
  await expect(
    clickable(page, 'Use your authenticator app instead')
  ).toHaveCount(0);
});

// @S06
// Scenario: Correct authenticator code sends me back to the page I asked for
//   Given I am signed in with MFA enabled
//   And I was sent to "Confirm access" from "/profile/auth/backup_codes"
//   And I have switched to "Authentication Code"
//   When I enter the current code from my authenticator app and click "Verify"
//   Then a sudo session is recorded for me
//   And I am taken to "/profile/auth/backup_codes" with a "sudo_token" query parameter
//   And the flow "flow-reauth-backup-codes" continues on that page
// MFA is turned on after signing in, so no code has been used yet.
test('@S06', PASSING, async ({ page }) => {
  const amara = me();
  await signInAs(page, amara.email);
  withMfa(amara.id);
  await sentHere(page);
  await switchTo(page, 'Use your authenticator app instead');

  await roomInTimeStep(page, 5);
  await codeBox(page).fill(totpCode(SECRET));
  await submitButton(page, 'Verify').click();

  await expectSentBack(page);
  expect(sudoSessions(amara.id)).toBe(1);
});

// @S07
// Scenario: Wrong or reused authenticator code is refused and unlocks nothing
//   Given I am signed in with MFA enabled
//   And I was sent to "Confirm access" from "/profile/auth/backup_codes"
//   And I have switched to "Authentication Code"
//   When I enter "000000", which is not a valid code, and click "Verify"
//   Then I see "Invalid OTP code! Try again."
//   And no sudo session is recorded for me
//   When I enter a code I already used to sign in during the current time step and click "Verify"
//   Then I see "Invalid OTP code! Try again."
// The message is already showing from the first try, so the second refusal
// is read as: the server answered, I am still here and nothing is unlocked,
// all inside the time step the code was used in.
test('@S07', PASSING, async ({ page }) => {
  const amara = me();
  withMfa(amara.id);
  const lv = watchLiveView(page);
  await signInAs(page, amara.email);
  await expectAt(page, '/users/two-factor');
  await roomInTimeStep(page, 20);
  const step = timeStep();
  const used = totpCode(SECRET);
  await page.getByPlaceholder('XXXXXX').fill(used);
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page).not.toHaveURL(/\/users\/two-factor/);
  await sentHere(page);
  await switchTo(page, 'Use your authenticator app instead');

  await codeBox(page).fill('000000');
  await submitButton(page, 'Verify').click();

  await expect(page.getByText('Invalid OTP code! Try again.')).toBeVisible();
  expect(sudoSessions(amara.id)).toBe(0);

  const before = lv.events();
  await codeBox(page).fill(used);
  await submitButton(page, 'Verify').click();
  await lv.answered(before + 1);

  await expect(page.getByText('Invalid OTP code! Try again.')).toBeVisible();
  await expectAt(page, PATH);
  expect(sudoSessions(amara.id)).toBe(0);
  expect(timeStep(), 'still the time step the code was used in').toBe(step);
});

// Inherited from shared-authenticated-session. S01 to S03 and S11 run; S04
// and S05 are lockout checks for a variant this instance doesn't configure;
// S06 to S10 are chrome of the signed-in layout, which this page doesn't use
// (annotation inherits line).
test.describe('shared-authenticated-session', () => {
  // Signed out, the visit itself is what sends me here after logging in
  test(
    'shared-authenticated-session@S01 on auth-confirm-access',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S01(page, PATH, me().email);
    }
  );

  // Opened the way users reach it, from the backup codes page; the reload is
  // of "Confirm access"
  test(
    'shared-authenticated-session@S02 on auth-confirm-access',
    PASSING,
    async ({ page, browser }) => {
      cleanups.push(keepAccount(EDITOR));
      await authenticatedSession.S02(page, browser, SENSITIVE, EDITOR);
    }
  );

  test(
    'shared-authenticated-session@S03 on auth-confirm-access',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S03(page, PATH, me().email);
    }
  );

  for (const id of ['S04', 'S05'])
    test(
      `shared-authenticated-session@${id} on auth-confirm-access`,
      PENDING,
      () => {
        test.skip(
          true,
          'variant require-email-verification is not configured on this instance'
        );
      }
    );

  for (const id of ['S06', 'S07', 'S08', 'S09', 'S10'])
    test(
      `shared-authenticated-session@${id} on auth-confirm-access`,
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
  //   When I visit "/auth/confirm_access"
  //   Then I am on "/first_setup"
  test(
    'shared-authenticated-session@S11 on auth-confirm-access',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      cleanups.push(firstSetupOpen());
      await authenticatedSession.S11(page, PATH);
    }
  );
});
