// Scenarios from annotations/views/profile-mfa.md, and the shared ones it
// inherits.
//
// Who's who: "I" am an account of my own (Amara Diallo), seeded for each test
// and removed after, so turning MFA on or off touches no one else.
import { expect, test, type Page } from '@playwright/test';

import {
  dialog,
  mfaSwitch,
  qrCode,
  saveCode,
  secretKey,
  setupAnotherDevice,
} from './pages/profile';
import * as flashMessages from './shared/flash-messages';
import {
  attemptLogin,
  exec,
  expectAt,
  fieldBlock,
  lastLine,
  onNode,
  open,
  seedUser,
  signInAs,
  sql,
  totpCode,
  type SeededUser,
} from './steps';

const PAGE = '/profile';

// The secret seedMfa stores (20 bytes of 0xab), as an authenticator app
// shows it in base32
const OLD_PHONE = 'VOV2XK5L'.repeat(4);

const cleanups: (() => void)[] = [];
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
  cleanups.length = 0;
});

// Given I am signed in and have not enrolled in MFA, on "/profile"
async function signedIn(page: Page) {
  const me = seedUser('amara');
  cleanups.push(() => {
    exec(`delete from user_totps where user_id = '${me.id}';
          delete from user_backup_codes where user_id = '${me.id}'`);
    me.remove();
  });
  await signInAs(page, me.email);
  return me;
}

// And I have enrolled in MFA with my old phone — seeded after sign-in, so
// signing in doesn't ask for a code. Recovery codes are stored encrypted, so
// Lightning makes them.
function seedMfa(me: SeededUser) {
  exec(`insert into user_totps (id, user_id, secret, inserted_at, updated_at)
        values (gen_random_uuid(), '${me.id}', decode(repeat('ab', 20), 'hex'), now(), now());
        update users set mfa_enabled = true where id = '${me.id}'`);
  onNode(
    `Lightning.Accounts.get_user!(${JSON.stringify(me.id)}) |> Lightning.Accounts.regenerate_user_backup_codes()`
  );
}

const mfaOf = (me: SeededUser) =>
  sql<{ enabled: boolean; totps: number; codes: string }>(
    `select u.mfa_enabled as enabled,
            (select count(*)::int from user_totps where user_id = u.id) as totps,
            (select string_agg(encode(code, 'hex'), ',' order by code) from user_backup_codes where user_id = u.id) as codes
     from users u where u.id = '${me.id}'`
  )[0];

// Whether Lightning accepts <code> as my second factor now, as sign-in does
const codeWorks = (me: SeededUser, code: string) =>
  lastLine(
    onNode(
      `Lightning.Accounts.get_user!(${JSON.stringify(me.id)}) |> Lightning.Accounts.valid_user_totp?(${JSON.stringify(code)})`
    )
  ) === 'true';

// When I start setup on "/profile"
async function startSetup(page: Page) {
  await open(page, PAGE);
  await mfaSwitch(page).click();
  await expect(page.getByText('Scan the QR code')).toBeVisible();
}

// Then my next sign-in asks for a two-factor code (or doesn't)
async function nextSignInAsksForCode(page: Page, me: SeededUser) {
  const fresh = await page.context().browser()!.newPage();
  await attemptLogin(fresh, me.email);
  const asked = new URL(fresh.url()).pathname === '/users/two-factor';
  await fresh.close();
  return asked;
}

// @S01
// Scenario: A user without MFA sees that it is off
//   Given I am signed in and have not enrolled in MFA
//   When I open "/profile"
//   Then I see "Enable multi-factor authentication"
//   And the "Enable multi-factor authentication" switch is off
//   And I do not see "You have configured an authentication app to get two-factor authentication codes"
//   And I do not see "Scan the QR code"
//   And I do not see "Recovery codes"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await signedIn(page);
  await open(page, PAGE);

  await expect(mfaSwitch(page)).toBeVisible();
  await expect(mfaSwitch(page)).not.toBeChecked();
  await expect(
    page.getByText(
      'You have configured an authentication app to get two-factor authentication codes'
    )
  ).toHaveCount(0);
  await expect(page.getByText('Scan the QR code')).toHaveCount(0);
  await expect(page.getByText('Recovery codes')).toHaveCount(0);
});

// @S02
// Scenario: Starting setup shows a QR code and a key to type in by hand
//   Given I am signed in and have not enrolled in MFA
//   And I am on "/profile"
//   When I click the "Enable multi-factor authentication" switch
//   Then the switch is on
//   And I see "Scan the QR code" and a QR code
//   When I click "this secret key"
//   Then I see "Your two-factor secret" and a secret in base32
// Fails on Lightning: the switch is drawn on but tells assistive technology
// nothing (a bare aria-checked), so it reads as off.
test('@S02', { tag: '@passing-new' }, async ({ page }) => {
  await signedIn(page);
  await startSetup(page);

  await expect(mfaSwitch(page)).toBeChecked();
  await expect(qrCode(page)).toBeVisible();
  expect(await secretKey(page)).toMatch(/^[A-Z2-7]{16,}=*$/);
});

// @S03
// Scenario: Confirming setup with a code from the app turns MFA on
//   Given I am signed in and have not enrolled in MFA
//   And I have started setup on "/profile"
//   When I enter a valid code from my authenticator app in "Verify the code from the app"
//   And I click "Save"
//   Then I see "MFA Setup"
//   And my account has MFA enabled
//   And I am on the two-factor backup codes page with a sudo token
//   And my next sign-in asks for a two-factor code, as in flow "flow-login-return-to" S02
//   And the flow "flow-require-project-mfa" continues to its exit if a project had stopped me
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);
  await startSetup(page);

  await saveCode(page, totpCode(await secretKey(page)));

  await expectAt(page, '/profile/auth/backup_codes');
  await expect(page.getByText('MFA Setup')).toBeVisible();
  expect(mfaOf(me)).toMatchObject({ enabled: true, totps: 1 });
  expect(mfaOf(me).codes?.split(',')).toHaveLength(10);
  // The backup codes page opens without asking for my password again
  await expect(page).not.toHaveURL(/confirm_access/);
  expect(await nextSignInAsksForCode(page, me)).toBe(true);
});

// @S04
// Scenario: A code that doesn't match the app is refused
//   Given I have started setup on "/profile"
//   When I enter "123456", which is not a valid code, and click "Save"
//   Then I see "invalid code" under "Verify the code from the app"
//   And I still see "Scan the QR code"
//   And my account does not have MFA enabled
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);
  await startSetup(page);
  const secret = await secretKey(page);
  // Make sure "123456" isn't, by chance, the code the app shows now
  const wrong = totpCode(secret) === '123456' ? '654321' : '123456';

  await saveCode(page, wrong);

  await expect(
    fieldBlock(page, 'Verify the code from the app').getByText('invalid code')
  ).toBeVisible();
  await expect(page.getByText('Scan the QR code')).toBeVisible();
  await expectAt(page, PAGE);
  expect(mfaOf(me)).toMatchObject({ enabled: false, totps: 0 });
});

// @S05
// Scenario: Abandoning setup changes nothing
//   Given I am signed in and have not enrolled in MFA
//   And I have started setup on "/profile"
//   When I click "Cancel"
//   Then I do not see "Scan the QR code"
//   And the "Enable multi-factor authentication" switch is off
//   And my account does not have MFA enabled
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);
  await startSetup(page);

  await page.getByRole('button', { name: 'Cancel', exact: true }).click();

  await expect(page.getByText('Scan the QR code')).toHaveCount(0);
  await expect(mfaSwitch(page)).not.toBeChecked();
  expect(mfaOf(me)).toMatchObject({ enabled: false, totps: 0 });
});

// @S06
// Scenario: A user with MFA sees it is on and where their recovery codes are
//   Given I am signed in and have enrolled in MFA
//   When I open "/profile"
//   Then the "Enable multi-factor authentication" switch is on
//   And I see "You have configured an authentication app to get two-factor authentication codes."
//   And I see "Setup another device instead"
//   And I see "Recovery codes" with a "View" button
//   And I do not see "Scan the QR code"
// Fails on Lightning: the switch is drawn on but tells assistive technology
// nothing (a bare aria-checked), so it reads as off.
test('@S06', { tag: '@passing-new' }, async ({ page }) => {
  const me = await signedIn(page);
  seedMfa(me);
  await open(page, PAGE);

  await expect(mfaSwitch(page)).toBeChecked();
  await expect(
    page.getByText(
      'You have configured an authentication app to get two-factor authentication codes.'
    )
  ).toBeVisible();
  await expect(setupAnotherDevice(page)).toBeVisible();
  await expect(page.getByText('Recovery codes', { exact: true })).toBeVisible();
  await expect(
    page
      .getByRole('button', { name: 'View', exact: true })
      .or(page.getByRole('link', { name: 'View', exact: true }))
      .first()
  ).toBeVisible();
  await expect(page.getByText('Scan the QR code')).toHaveCount(0);
});

// @S07
// Scenario: Moving MFA to another device replaces the old one
//   Given I am signed in and have enrolled in MFA with my old phone
//   And I am on "/profile"
//   When I click "Setup another device instead"
//   Then I see "Scan the QR code"
//   And I do not see "Setup another device instead"
//   When I enter a valid code from the new device and click "Save"
//   Then I am on "/profile"
//   And I see "MFA Setup"
//   And codes from my old phone are no longer accepted
//   And my recovery codes are unchanged
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);
  seedMfa(me);
  const codes = mfaOf(me).codes;
  await open(page, PAGE);

  await setupAnotherDevice(page).click();
  await expect(page.getByText('Scan the QR code')).toBeVisible();
  await expect(setupAnotherDevice(page)).toHaveCount(0);

  const newPhone = await secretKey(page);
  expect(newPhone).not.toBe(OLD_PHONE);
  await saveCode(page, totpCode(newPhone));

  await expect(page.getByText('MFA Setup')).toBeVisible();
  await expectAt(page, PAGE);
  expect(codeWorks(me, totpCode(OLD_PHONE))).toBe(false);
  expect(mfaOf(me)).toMatchObject({ enabled: true, totps: 1, codes });
});

// @S08
// Scenario: Turning MFA off asks first, then removes it
//   Given I am signed in and have enrolled in MFA
//   And I am on "/profile"
//   When I click the "Enable multi-factor authentication" switch
//   Then I see "Disable MFA"
//   And I see "Are you sure you want to disable MFA from your account? This will make your account less secure."
//   When I click "Disable"
//   Then I am on "/profile"
//   And I see "MFA Disabled"
//   And the switch is off
//   And I do not see "You have configured an authentication app to get two-factor authentication codes"
//   And my next sign-in no longer asks for a two-factor code
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);
  seedMfa(me);
  await open(page, PAGE);

  await mfaSwitch(page).click();
  const confirm = await dialog(page, 'Disable MFA');
  await expect(confirm).toContainText(
    'Are you sure you want to disable MFA from your account? This will make your account less secure.'
  );
  // Nothing changes until I confirm
  expect(mfaOf(me).enabled).toBe(true);

  await confirm.getByRole('button', { name: 'Disable', exact: true }).click();

  await expect(page.getByText('MFA Disabled')).toBeVisible();
  await expectAt(page, PAGE);
  await expect(mfaSwitch(page)).not.toBeChecked();
  await expect(
    page.getByText(
      'You have configured an authentication app to get two-factor authentication codes'
    )
  ).toHaveCount(0);
  expect(mfaOf(me)).toMatchObject({ enabled: false, totps: 0 });
  expect(await nextSignInAsksForCode(page, me)).toBe(false);
});

// @S09
// Scenario: Backing out of turning MFA off keeps it on
//   Given I am signed in and have enrolled in MFA
//   And I have opened the "Disable MFA" confirmation
//   When I click "Cancel"
//   Then I no longer see "Disable MFA"
//   And my account still has MFA enabled
// Fails on Lightning: the switch is drawn on but tells assistive technology
// nothing (a bare aria-checked), so it reads as off.
test('@S09', { tag: '@passing-new' }, async ({ page }) => {
  const me = await signedIn(page);
  seedMfa(me);
  await open(page, PAGE);
  await mfaSwitch(page).click();
  const confirm = await dialog(page, 'Disable MFA');

  await confirm.getByRole('button', { name: 'Cancel', exact: true }).click();

  await expect(confirm).toHaveCount(0);
  await expect(mfaSwitch(page)).toBeChecked();
  expect(mfaOf(me)).toMatchObject({ enabled: true, totps: 1 });
});

// @S10
// Scenario: Viewing recovery codes hands off to re-authentication
//   Given I am signed in and have enrolled in MFA
//   And I am on "/profile"
//   When I click "View" under "Recovery codes"
//   Then the flow "flow-reauth-backup-codes" has started
// The flow starts by asking who I am, when no recent confirmation is held.
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);
  seedMfa(me);
  // Given no recent confirmation of who I am
  exec(
    `delete from user_tokens where context = 'sudo_session' and user_id = '${me.id}'`
  );
  await open(page, PAGE);

  await page
    .getByRole('button', { name: 'View', exact: true })
    .or(page.getByRole('link', { name: 'View', exact: true }))
    .first()
    .click();

  await expectAt(page, '/auth/confirm_access');
});

// Inherited from shared-authenticated-session and shared-project-header:
// this card is part of "/profile", whose session and header scenarios run in
// profile-account.spec.ts. The card adds none of its own.

// Inherited from shared-flash-messages: the card's own messages.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S05 on profile-mfa',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const me = await signedIn(page);
      seedMfa(me);
      await open(page, PAGE);
      await flashMessages.S05(
        page,
        'MFA Disabled',
        async () => {
          await mfaSwitch(page).click();
          await (await dialog(page, 'Disable MFA'))
            .getByRole('button', { name: 'Disable', exact: true })
            .click();
        },
        PAGE
      );
    }
  );
});
