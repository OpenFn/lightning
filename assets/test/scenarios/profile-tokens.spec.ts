// Scenarios from annotations/views/profile-tokens.md.
//
// Who's who: "I" and "bob@example.org" are editor@openfn.org, who has no token
// in the seeded scenario. "amara@example.org" is owner@openfn.org, whose
// seeded API token is the one the manifest lists.
import { expect, test, type Page } from '@playwright/test';

import * as localDatetime from './shared/local-datetime';
import {
  apiTokensOf,
  changePassword,
  confirmDeletionNaming,
  expectAt,
  getWithBearer,
  keepPassword,
  open,
  PASSWORD,
  reload,
  removeApiTokensOf,
  seededApiTokenOf,
  setApiTokenTimes,
  signInAs,
  tagFor,
} from './steps';

const ME = 'editor@openfn.org';
const AMARA = 'owner@openfn.org';

const mask = (token: string) => `...${token.slice(-10)}`;
// Rows of the token list, without its header row
const tokenRows = (page: Page) =>
  page.getByRole('row').filter({ has: page.getByRole('cell') });
const tokenRow = (page: Page, token: string) =>
  tokenRows(page).filter({ hasText: mask(token) });
// The field that shows a newly generated token; the page has no other
const tokenField = (page: Page) => page.getByRole('textbox');

// Given I am signed in and on "/profile/tokens"
async function signedIn(page: Page) {
  await signInAs(page, ME);
  await open(page, '/profile/tokens');
}

// Given I am signed in and on "/profile/tokens" with no API tokens
async function signedInWithNoTokens(page: Page) {
  removeApiTokensOf(ME);
  await signedIn(page);
}

// When I click "Generate New Token" — returns the token the field shows
async function generateToken(page: Page) {
  const field = tokenField(page);
  const before = (await field.count()) ? await field.inputValue() : null;
  await page
    .getByRole('button', { name: 'Generate New Token' })
    .first()
    .click();
  await expect(field).toBeVisible();
  if (before) await expect(field).not.toHaveValue(before);
  return field.inputValue();
}

// The row the server stored for a token I was shown
function stored(token: string) {
  const row = apiTokensOf(ME).find(t => t.token === token);
  expect(row, 'the token should be stored').toBeTruthy();
  return row!;
}

// @S01
// Scenario: A user with no tokens is pointed to generate one
//   Given I am signed in and have no API tokens
//   When I open "/profile/tokens"
//   Then I see "Personal Access Tokens" as the page title
//   And I see "No Personal Access Tokens" and "Get started by creating a new access token."
//   And I see a "Generate New Token" button
//   And the side menu marks "API Tokens" as current
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  await signedInWithNoTokens(page);

  await expect(page).toHaveTitle(/Personal Access Tokens/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Personal Access Tokens'
  );
  await expect(page.getByText('No Personal Access Tokens')).toBeVisible();
  await expect(
    page.getByText('Get started by creating a new access token.')
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Generate New Token' }).first()
  ).toBeVisible();
  await expect(page.getByRole('link', { name: 'API Tokens' })).toHaveAttribute(
    'aria-current',
    'page'
  );
});

// @S02
// Scenario: A user generates a token and sees it in full once
//   Given I am signed in and on "/profile/tokens"
//   When I click "Generate New Token"
//   Then I see "Token created successfully"
//   And I see "Make sure to copy your token now as you will not be able to see it again."
//   And the token field shows the full token
//   And the token list has a new row showing "..." followed by the token's last 10 characters
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);
  const rowsBefore = await tokenRows(page).count();

  const token = await generateToken(page);

  await expect(page.getByText('Token created successfully')).toBeVisible();
  await expect(
    page.getByText(
      'Make sure to copy your token now as you will not be able to see it again.'
    )
  ).toBeVisible();
  await expect(tokenRows(page)).toHaveCount(rowsBefore + 1);
  await expect(tokenRow(page, token)).toBeVisible();
  // The field shows the newest stored token, in full
  expect(apiTokensOf(ME)[0].token).toBe(token);
});

// @S03
// Scenario: A token can't be read back after leaving the page
//   Given I have just generated a token on "/profile/tokens"
//   When I reload "/profile/tokens"
//   Then I do not see the token field
//   And the token's row shows only "..." followed by its last 10 characters
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);
  const token = await generateToken(page);

  await reload(page);

  await expect(tokenField(page)).toHaveCount(0);
  const row = tokenRow(page, token);
  await expect(row).toBeVisible();
  await expect(row).not.toContainText(token.slice(0, 20));
  expect(await page.content()).not.toContain(token);
});

// @S04
// Scenario: Copying the new token puts the whole token on the clipboard
//   Given I have just generated a token on "/profile/tokens"
//   When I click "Copy to clipboard"
//   Then my clipboard holds the full token
//   And I briefly see "Copied!"
test('@S04', { tag: '@passing-old' }, async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await signedIn(page);
  const token = await generateToken(page);

  await page.getByRole('button', { name: 'Copy to clipboard' }).click();

  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(token);
  const copied = page.getByText('Copied!', { exact: true });
  await expect(copied).toBeVisible();
  await expect(copied).toBeHidden({ timeout: 3000 });
});

// @S05
// Scenario: Each token shows when it was created and whether it has been used
//   Given I have a token created on 1 March that was last used on 10 March
//   And I have a token that has never been used
//   When I open "/profile/tokens"
//   Then the first token shows its "Created on" and "Last Used at" dates
//   And the second token shows "Never used" under "Last Used at"
test('@S05', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);
  const used = await generateToken(page);
  setApiTokenTimes(used, {
    inserted_at: '2026-03-01 09:00:00',
    last_used_at: '2026-03-10 14:30:00',
  });
  const unused = await generateToken(page);

  await open(page, '/profile/tokens');

  // Columns: Token | Created on | Last Used at. The browser runs in UTC.
  const usedCells = tokenRow(page, used).getByRole('cell');
  await expect(usedCells.nth(1)).toHaveText('March 1st, 9:00 AM');
  await expect(usedCells.nth(2)).toHaveText('March 10th, 2:30 PM');
  await expect(tokenRow(page, unused).getByRole('cell').nth(2)).toHaveText(
    'Never used'
  );
});

// @S06
// Scenario: A user only sees their own tokens
//   Given "amara@example.org" has an API token
//   And I am signed in as "bob@example.org" with one API token
//   When I open "/profile/tokens"
//   Then the list has exactly one row, for my token
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  const amaras = seededApiTokenOf(AMARA);
  await signedInWithNoTokens(page);
  const mine = await generateToken(page);

  await open(page, '/profile/tokens');

  await expect(tokenRows(page)).toHaveCount(1);
  await expect(tokenRow(page, mine)).toBeVisible();
  await expect(page.getByRole('table')).not.toContainText(mask(amaras.token));
});

// @S07
// Scenario: A user deletes a token after confirming
//   Given I have an API token listed on "/profile/tokens"
//   When I click the delete icon on its row
//   Then I am on "/profile/tokens/<token id>/delete"
//   And I see "Delete API Access Token"
//   And I see "Any applications or scripts using this token will no longer be able to access the API."
//   When I click "Yes"
//   Then I am on "/profile/tokens"
//   And I see "Token deleted successfully"
//   And the token's row is gone
//   And the flow "flow-personal-access-token-use" refuses that token from now on
test('@S07', { tag: '@passing-old' }, async ({ page, request }) => {
  await signedIn(page);
  const token = await generateToken(page);
  expect((await getWithBearer(request, '/api/projects', token)).status()).toBe(
    200
  );
  const { id } = stored(token);
  await open(page, '/profile/tokens');

  // The delete icon is the row's only link; it has no accessible name.
  await tokenRow(page, token).getByRole('link').click();

  await expectAt(page, `/profile/tokens/${id}/delete`);
  await expect(page.getByText('Delete API Access Token')).toBeVisible();
  await expect(
    page.getByText(
      'Any applications or scripts using this token will no longer be able to access the API.'
    )
  ).toBeVisible();

  await page.getByRole('button', { name: 'Yes' }).click();

  await expectAt(page, '/profile/tokens');
  await expect(page.getByText('Token deleted successfully')).toBeVisible();
  await expect(tokenRow(page, token)).toHaveCount(0);
  expect(apiTokensOf(ME).map(t => t.id)).not.toContain(id);
  expect((await getWithBearer(request, '/api/projects', token)).status()).toBe(
    401
  );
});

// @S08
// Scenario: Backing out of a deletion keeps the token
//   Given I have opened the delete modal for one of my tokens
//   When I click "Cancel"
//   Then I am on "/profile/tokens"
//   And the token's row is still listed
test('@S08', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);
  const token = await generateToken(page);
  await tokenRow(page, token).getByRole('link').click();
  await expect(page.getByText('Delete API Access Token')).toBeVisible();

  await page.getByRole('button', { name: 'Cancel' }).click();

  await expectAt(page, '/profile/tokens');
  await expect(page.getByText('Delete API Access Token')).toBeHidden();
  await expect(tokenRow(page, token)).toBeVisible();
  expect(apiTokensOf(ME).map(t => t.token)).toContain(token);
});

// @S09
// Scenario: A user can't open the deletion of someone else's token
//   Given "amara@example.org" has an API token
//   And I am signed in as "bob@example.org"
//   When I open "/profile/tokens/<Amara's token id>/delete"
//   Then I am on "/profile/tokens"
//   And I see "You can't perform this action"
//   And I do not see "Delete API Access Token"
test('@S09', { tag: '@passing-old' }, async ({ page }) => {
  const amaras = seededApiTokenOf(AMARA);
  await signInAs(page, ME);

  await open(page, `/profile/tokens/${amaras.id}/delete`);

  await expectAt(page, '/profile/tokens');
  await expect(page.getByText("You can't perform this action")).toBeVisible();
  await expect(page.getByText('Delete API Access Token')).toHaveCount(0);
  expect(apiTokensOf(AMARA).map(t => t.id)).toContain(amaras.id);
});

// @S10
// Scenario: A forged delete request for someone else's token deletes nothing
//   Given I have opened the delete modal for my own token
//   And "amara@example.org" has an API token
//   When a delete is submitted from that modal naming Amara's token id
//   Then I am on "/profile/tokens"
//   And I see "You can't perform this action"
//   And both tokens still exist
test('@S10', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);
  const mine = await generateToken(page);
  await tokenRow(page, mine).getByRole('link').click();
  const amaras = seededApiTokenOf(AMARA);

  await confirmDeletionNaming(page, amaras.id);

  await expectAt(page, '/profile/tokens');
  await expect(page.getByText("You can't perform this action")).toBeVisible();
  expect(apiTokensOf(ME).map(t => t.token)).toContain(mine);
  expect(apiTokensOf(AMARA).map(t => t.id)).toContain(amaras.id);
});

// @S11
// Scenario: Tokens revoked by a password change are gone from the list
//   Given I have an API token listed on "/profile/tokens"
//   When the flow "flow-account-revocation-teardown" has run for my own password change
//   And I open "/profile/tokens" again
//   Then I see "No Personal Access Tokens"
test('@S11', { tag: '@passing-old' }, async ({ page }) => {
  const restorePassword = keepPassword(ME);
  try {
    await signedIn(page);
    const token = await generateToken(page);
    await open(page, '/profile/tokens');
    await expect(tokenRow(page, token)).toBeVisible();

    await changePassword(page, ME, PASSWORD, `${PASSWORD}-new`);
    await expect.poll(() => apiTokensOf(ME)).toEqual([]);
    await open(page, '/profile/tokens');

    await expect(page.getByText('No Personal Access Tokens')).toBeVisible();
    await expect(tokenRow(page, token)).toHaveCount(0);
    expect(apiTokensOf(ME)).toEqual([]);
  } finally {
    restorePassword();
  }
});

// Inherited from shared-local-datetime: "Created on" and "Last Used at" each
// show one timestamp.
const columns = { 'Created on': 'inserted_at', 'Last Used at': 'last_used_at' };

// Given my token's "<column>" is <utc>, and today is <today>
async function tokenTimestamp(
  page: Page,
  column: keyof typeof columns,
  { utc, today }: { utc: string; today?: string }
) {
  await signedIn(page);
  const token = await generateToken(page);
  setApiTokenTimes(token, { [columns[column]]: utc });
  if (today) await page.clock.setFixedTime(today);
  await open(page, '/profile/tokens');
  // Columns: Token | Created on | Last Used at
  const index = Object.keys(columns).indexOf(column) + 1;
  return tokenRow(page, token).getByRole('cell').nth(index);
}

for (const column of Object.keys(columns) as (keyof typeof columns)[]) {
  test.describe(column, () => {
    test.describe(() => {
      test.use({ timezoneId: localDatetime.given.S01.timezoneId });
      test(
        'shared-local-datetime@S01 on profile-tokens',
        { tag: '@passing-old' },
        async ({ page }) => {
          const cell = await tokenTimestamp(
            page,
            column,
            localDatetime.given.S01
          );
          await localDatetime.S01(page, cell);
        }
      );
    });

    for (const id of ['S02', 'S04', 'S05'] as const) {
      test(
        `shared-local-datetime@${id} on profile-tokens`,
        { tag: tagFor(id, ['S01', 'S02', 'S04', 'S05']) },
        async ({ page }) => {
          const cell = await tokenTimestamp(
            page,
            column,
            localDatetime.given[id]
          );
          await localDatetime[id](page, cell);
        }
      );
    }
  });
}
