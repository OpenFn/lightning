// Scenarios from annotations/views/profile-github.md, and the shared ones it
// inherits.
//
// Who's who: "I" am an account of my own (Amara Diallo), seeded for each test
// and removed after. GitHub is a stand-in on the Lightning node, and the
// instance's GitHub app is set up for the test, so every test here is
// @serial.
import { expect, test, type Page } from '@playwright/test';

import {
  dialog,
  expectHint,
  followToGithub,
  githubLink,
} from './pages/profile';
import * as flashMessages from './shared/flash-messages';
import {
  expectAt,
  githubTokenFor,
  githubTokenOf,
  open,
  seedUser,
  signInAs,
  standInGithub,
  type GithubToken,
  type SeededUser,
  type StandInGithub,
} from './steps';

const PAGE = '/profile';
const DISCONNECT = 'Disconnect from GitHub';
const REMOVED = 'GitHub connection removed successfully';

let github: StandInGithub;
let me: SeededUser;
test.beforeEach(() => {
  github = standInGithub();
  me = seedUser('amara');
});
test.afterEach(() => {
  me.remove();
  github.restore();
});

// Given I am signed in with <token> (or none), on "/profile"
async function signedIn(page: Page, token?: GithubToken) {
  if (token) githubTokenFor(me.id, token);
  await signInAs(page, me.email);
  await open(page, PAGE);
}

// When I click "Disconnect from GitHub" — returns the open dialog
async function openDisconnect(page: Page) {
  await page.getByRole('button', { name: DISCONNECT }).click();
  return dialog(page, 'Disconnect from GitHub?');
}

// When I disconnect GitHub and confirm
async function disconnect(page: Page) {
  const confirm = await openDisconnect(page);
  await confirm
    .getByRole('button', { name: 'Disconnect', exact: true })
    .click();
}

// The requests GitHub got to revoke the app's grant
const revocations = () =>
  github
    .requests()
    .filter(r => r.url.endsWith(`/applications/${github.clientId}/grant`));

// Then the flow "flow-github-connect" has started for my account: GitHub is
// asked to authorise this instance's app and send me back here
async function expectConnectStarted(page: Page, verb: 'Connect' | 'Reconnect') {
  const asked = await followToGithub(page, githubLink(page, verb));
  expect(asked.pathname).toBe('/login/oauth/authorize');
  expect(asked.searchParams.get('client_id')).toBe(github.clientId);
  expect(asked.searchParams.get('redirect_uri')).toMatch(
    /\/oauth\/github\/callback$/
  );
}

// @S01
// Scenario: A user with no GitHub link is offered the connection
//   Given I am signed in with no GitHub account connected
//   When I open "/profile"
//   Then I see the card "GitHub Access"
//   And I see "Connect your GitHub Account"
//   And I do not see "Disconnect from GitHub"
//   When I click "Connect your GitHub Account"
//   Then the flow "flow-github-connect" has started for my account
test(
  '@S01',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await signedIn(page);

    await expect(
      page.getByText('GitHub Access', { exact: true })
    ).toBeVisible();
    await expect(githubLink(page, 'Connect')).toBeVisible();
    await expect(page.getByRole('button', { name: DISCONNECT })).toHaveCount(0);

    await expectConnectStarted(page, 'Connect');
  }
);

// @S02
// Scenario: A linked user sees they are connected
//   Given I am signed in with a valid GitHub token
//   When I open "/profile"
//   Then I see "Disconnect from GitHub"
//   And I do not see "Connect your GitHub Account"
test(
  '@S02',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await signedIn(page, 'fresh');

    await expect(page.getByRole('button', { name: DISCONNECT })).toBeVisible();
    await expect(githubLink(page, 'Connect')).toHaveCount(0);
    await expect(githubLink(page, 'Reconnect')).toHaveCount(0);
  }
);

// @S03
// Scenario: A user whose GitHub link lapsed is told and can reconnect
//   Given I am signed in with a GitHub token whose refresh token has expired
//   When I open "/profile"
//   Then I see "Reconnect your GitHub Account" with the tooltip "Your token has expired"
//   And I do not see "Disconnect from GitHub"
//   When I click "Reconnect your GitHub Account"
//   Then the flow "flow-github-connect" has started for my account
test(
  '@S03',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await signedIn(page, 'lapsed');

    const link = githubLink(page, 'Reconnect');
    await expect(link).toBeVisible();
    await expectHint(page, link, 'Your token has expired');
    await expect(page.getByRole('button', { name: DISCONNECT })).toHaveCount(0);

    await expectConnectStarted(page, 'Reconnect');
  }
);

// @S04
// Scenario: A user disconnects GitHub after confirming
//   Given I am signed in with a valid, non-expiring GitHub token
//   When I click "Disconnect from GitHub"
//   Then I see the dialog "Disconnect from GitHub?"
//   And I see "Until you reconnect, you will not be able to set up or modify version control for your projects."
//   When I click "Disconnect"
//   Then OpenFn's grant is revoked on GitHub
//   And I am on "/profile" with "GitHub connection removed successfully"
//   And I see "Connect your GitHub Account"
//   And no GitHub token is stored on my account
test(
  '@S04',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await signedIn(page, 'lasting');

    const confirm = await openDisconnect(page);
    await expect(confirm).toContainText(
      'Until you reconnect, you will not be able to set up or modify version control for your projects.'
    );
    // Nothing happens until I confirm
    expect(revocations()).toHaveLength(0);

    await confirm
      .getByRole('button', { name: 'Disconnect', exact: true })
      .click();

    await expect(page.getByText(REMOVED)).toBeVisible();
    await expectAt(page, PAGE);
    await expect(githubLink(page, 'Connect')).toBeVisible();
    expect(revocations()).toEqual([
      expect.objectContaining({
        method: 'delete',
        body: expect.stringContaining('access-seeded'),
      }),
    ]);
    expect(githubTokenOf(me.id)).toBeNull();
  }
);

// @S05
// Scenario: Disconnecting with an expired access token still revokes the grant on GitHub
//   Given I am signed in with a GitHub token whose access token has expired but whose refresh token has not
//   When I disconnect GitHub and confirm
//   Then OpenFn refreshes the access token with GitHub
//   And OpenFn's grant is revoked on GitHub with the refreshed access token
//   And I see "GitHub connection removed successfully"
//   And no GitHub token is stored on my account
test(
  '@S05',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await signedIn(page, 'access-expired');

    await disconnect(page);

    await expect(page.getByText(REMOVED)).toBeVisible();
    const asked = github.requests().map(r => r.url);
    const refreshed = asked.findIndex(url =>
      url.endsWith('/login/oauth/access_token')
    );
    expect(refreshed, 'the access token was refreshed').toBeGreaterThan(-1);
    expect(revocations()).toEqual([
      expect.objectContaining({
        body: expect.stringContaining('access-refreshed'),
      }),
    ]);
    expect(
      asked.findIndex(url => url.endsWith('/grant')),
      'revoked after the refresh'
    ).toBeGreaterThan(refreshed);
    expect(githubTokenOf(me.id)).toBeNull();
  }
);

// @S06
// Scenario: Disconnecting succeeds locally even when GitHub refuses
//   Given I am signed in with a valid GitHub token
//   And GitHub answers the revocation request with an error
//   When I disconnect GitHub and confirm
//   Then I see "GitHub connection removed successfully"
//   And I see "Connect your GitHub Account"
//   And no GitHub token is stored on my account
test(
  '@S06',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    github.revokeAnswers(422);
    await signedIn(page, 'fresh');

    await disconnect(page);

    await expect(page.getByText(REMOVED)).toBeVisible();
    await expect(githubLink(page, 'Connect')).toBeVisible();
    expect(revocations()).toHaveLength(1);
    expect(githubTokenOf(me.id)).toBeNull();
  }
);

// @S07
// Scenario: Backing out of the disconnect dialog keeps the link
//   Given I am signed in with a valid GitHub token
//   When I click "Disconnect from GitHub"
//   And I click "Cancel"
//   Then the dialog closes
//   And I still see "Disconnect from GitHub"
//   And my GitHub token is unchanged
test(
  '@S07',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await signedIn(page, 'fresh');
    const before = githubTokenOf(me.id);

    const confirm = await openDisconnect(page);
    await confirm.getByRole('button', { name: 'Cancel', exact: true }).click();

    await expect(confirm).toHaveCount(0);
    await expect(page.getByRole('button', { name: DISCONNECT })).toBeVisible();
    expect(revocations()).toHaveLength(0);
    expect(githubTokenOf(me.id)).toEqual(before);
  }
);

// Inherited from shared-authenticated-session and shared-project-header:
// this card is part of "/profile", whose session and header scenarios run in
// profile-account.spec.ts. The card adds none of its own.

// Inherited from shared-flash-messages: disconnecting redirects to "/profile"
// with its message.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S05 on profile-github',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      await signedIn(page, 'fresh');
      await flashMessages.S05(page, REMOVED, () => disconnect(page), PAGE);
    }
  );
});
