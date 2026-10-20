// Scenarios from annotations/views/profile-backup-codes.md.
//
// "I" is owner@openfn.org. profile-tokens never signs in as owner, so turning
// on MFA here can't break its sign-in step. Each test starts owner without MFA
// and leaves it that way.
import { expect, test, type Page } from '@playwright/test';

import {
  enrolInMfa,
  exec,
  expireSudoOf,
  open,
  reauthenticateWithPassword,
  removeMfaOf,
  signInAs,
  sql,
  user,
} from './steps';

const ME = 'owner@openfn.org';
const PAGE = '/profile/auth/backup_codes';

const shownCodes = (page: Page) =>
  page
    .locator('div.grid > div.tracking-widest')
    .allInnerTexts()
    .then(codes => codes.map(c => c.trim()));

const codeRowIds = () =>
  sql<{ id: string }>(
    `select id from user_backup_codes where user_id = '${user(ME).id}'`
  ).map(r => r.id);

test.beforeEach(() => removeMfaOf(ME));
test.afterAll(() => removeMfaOf(ME));

// Given I am signed in and have enrolled in MFA — returns the ten codes shown
async function signedInWithMfa(page: Page) {
  await signInAs(page, ME);
  await enrolInMfa(page);
  await expect(page).toHaveURL(/\/profile\/auth\/backup_codes\?sudo_token=/);
  // Codes are in the first render; hooks such as Copy attach only on connect.
  await page.locator('.phx-connected').first().waitFor();
  await expect.poll(() => shownCodes(page).then(c => c.length)).toBe(10);
  return shownCodes(page);
}

// And I have five recovery codes
function keepFiveCodes() {
  exec(
    `delete from user_backup_codes where id in (
       select id from user_backup_codes where user_id = '${user(ME).id}' limit 5)`
  );
  expect(codeRowIds()).toHaveLength(5);
}

// And I re-authenticated less than five minutes ago; When I open the page
async function openAfterReauth(page: Page) {
  expireSudoOf(ME);
  await page.goto(PAGE);
  await reauthenticateWithPassword(page);
  await expect(page).toHaveURL(/\/profile\/auth\/backup_codes\?sudo_token=/);
  await page.locator('.phx-connected').first().waitFor();
}

// @S01
// Scenario: A user who has just re-authenticated sees their recovery codes
//   Given I am signed in and have enrolled in MFA
//   And I have five recovery codes
//   And I re-authenticated less than five minutes ago
//   When I open "/profile/auth/backup_codes"
//   Then I see "Two-factor backup codes"
//   And I see "Recovery codes can be used to access your account in the event you lose access to your device"
//   And I see "Keep your backup codes as safe as your password."
//   And I see each of my five recovery codes
//   And I do not see "MFA Disabled"
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  const enrolled = await signedInWithMfa(page);
  keepFiveCodes();

  await openAfterReauth(page);

  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Two-factor backup codes'
  );
  await expect(
    page.getByText(
      'Recovery codes can be used to access your account in the event you lose access to your device'
    )
  ).toBeVisible();
  await expect(
    page.getByText('Keep your backup codes as safe as your password.')
  ).toBeVisible();
  const shown = await shownCodes(page);
  expect(shown).toHaveLength(5);
  expect(new Set(shown).size).toBe(5);
  for (const code of shown) expect(enrolled).toContain(code);
  await expect(page.getByText('MFA Disabled')).toHaveCount(0);
});

// @S02
// Scenario: Opening the page without a valid sudo window hands off to re-authentication
//   Given I am signed in and have enrolled in MFA
//   And the session holds no sudo token that is mine and under five minutes old
//   When I open "/profile/auth/backup_codes"
//   Then the flow "flow-reauth-backup-codes" has started
//   And I do not see any of my recovery codes
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  const codes = await signedInWithMfa(page);
  expireSudoOf(ME);

  await open(page, PAGE);

  await expect(page).toHaveURL(/\/auth\/confirm_access/);
  const body = await page.locator('body').innerText();
  for (const code of codes) expect(body).not.toContain(code);
});

// @S03
// Scenario: First enrolment lands here with the new codes
//   Given I have just confirmed MFA setup on "/profile" for the first time
//   Then I am on "/profile/auth/backup_codes" with a sudo token in the address
//   And I see ten recovery codes
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  await signInAs(page, ME);

  await enrolInMfa(page);

  await expect(page).toHaveURL(/\/profile\/auth\/backup_codes\?sudo_token=.+/);
  const shown = await shownCodes(page);
  expect(shown).toHaveLength(10);
  expect(new Set(shown).size).toBe(10);
  expect(codeRowIds()).toHaveLength(10);
});

// @S04
// Scenario: Generating new codes replaces every old one
//   Given I am signed in and have enrolled in MFA
//   And I have five recovery codes
//   And I am on "/profile/auth/backup_codes" inside my sudo window
//   Then I see "When you generate new backup codes, you must copy or print the new codes. Your old codes won't work anymore."
//   When I click "Generate new backup codes"
//   Then I see "New Backup Codes Generated!"
//   And I see ten recovery codes
//   And I do not see any of my five old codes
//   And none of my five old codes remain on my account
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  await signedInWithMfa(page);
  keepFiveCodes();
  const oldIds = codeRowIds();
  await openAfterReauth(page);
  const oldCodes = await shownCodes(page);
  expect(oldCodes).toHaveLength(5);
  await expect(
    page.getByText(
      "When you generate new backup codes, you must copy or print the new codes. Your old codes won't work anymore."
    )
  ).toBeVisible();

  await page.getByRole('button', { name: 'Generate new backup codes' }).click();

  await expect(page.getByText('New Backup Codes Generated!')).toBeVisible();
  await expect.poll(() => shownCodes(page).then(c => c.length)).toBe(10);
  const newCodes = await shownCodes(page);
  for (const code of oldCodes) expect(newCodes).not.toContain(code);
  const newIds = codeRowIds();
  expect(newIds).toHaveLength(10);
  for (const id of oldIds) expect(newIds).not.toContain(id);
});

// @S05
// Scenario: Copying puts every code on the clipboard
//   Given I am on "/profile/auth/backup_codes" inside my sudo window
//   And I have ten recovery codes
//   When I click "Copy Codes"
//   Then my clipboard holds each of my ten codes, separated by blank lines
//   And I see "Copied!"
test('@S05', { tag: '@passing-old' }, async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const codes = await signedInWithMfa(page);

  await page.getByRole('button', { name: 'Copy Codes' }).click();

  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
    codes.join('\n\n')
  );
  await expect(page.getByText('Copied!')).toBeVisible();
});

// @S06
// Scenario: Printing hands off to a printable copy in a new tab
//   Given I am on "/profile/auth/backup_codes" inside my sudo window
//   When I click "Print Codes"
//   Then a new tab opens on "/profile/auth/backup_codes/print"
//   And the flow "flow-reauth-backup-codes" S07 owns what that tab shows
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  await signedInWithMfa(page);

  const [tab] = await Promise.all([
    page.waitForEvent('popup'),
    page.getByRole('button', { name: 'Print Codes' }).click(),
  ]);

  await tab.waitForLoadState();
  expect(new URL(tab.url()).pathname).toBe(`${PAGE}/print`);
});

// @S07
// Scenario: A user without MFA is told the codes need it and where to turn it on
//   Given I am signed in and have not enrolled in MFA
//   And I re-authenticated less than five minutes ago
//   When I open "/profile/auth/backup_codes"
//   Then I see "MFA Disabled"
//   And I see "In order to use backup codes, you need to have MFA enabled in your account."
//   When I click "Back to profile"
//   Then I am on "/profile"
test('@S07', { tag: '@passing-old' }, async ({ page }) => {
  await signInAs(page, ME);

  await openAfterReauth(page);

  await expect(page.getByText('MFA Disabled')).toBeVisible();
  await expect(
    page.getByText(
      'In order to use backup codes, you need to have MFA enabled in your account.'
    )
  ).toBeVisible();

  await page.getByRole('link', { name: 'Back to profile' }).click();

  await expect(page).toHaveURL('/profile');
});
