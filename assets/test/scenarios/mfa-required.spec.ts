// Scenarios from annotations/views/mfa-required.md.
//
// Who's who: "I" is editor@openfn.org (Esther Editor), who has not enrolled in
// MFA unless a test says otherwise. "Malawi HIV" is a project each test seeds
// and removes again. Every test puts editor's account (MFA included) back as
// it found it.
import { expect, test, type Page } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import {
  exec,
  expectAt,
  keepAccount,
  manifest,
  open,
  removeMfaOf,
  seedMfaFor,
  seedProject,
  signInAs,
  tagFor,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PAGE = '/mfa_required';
const MESSAGE =
  'This project requires all members to use multi-factor authentication.';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME)];
  removeMfaOf(ME);
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given I am an editor on project "Malawi HIV", which requires MFA
function memberOfMfaProject() {
  const project = seedProject('Malawi HIV', { [ME]: 'editor' });
  exec(`update projects set requires_mfa = true where id = '${project.id}'`);
  cleanups.push(project.remove);
}

// Given I am signed in and on "/mfa_required"
async function signedIn(page: Page) {
  await signInAs(page, ME);
  await open(page, PAGE);
}

// @S01
// Scenario: An unenrolled member is told why and where to enrol
//   Given I am an editor on project "Malawi HIV", which requires MFA
//   And I have not enrolled in MFA
//   When I visit "/mfa_required"
//   Then I see "MFA Required for Project"
//   And I see "This project requires all members to use multi-factor authentication."
//   And I see a "your account" link to "/profile"
//   And I see a "Visit your account" link to "/profile"
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  memberOfMfaProject();

  await signedIn(page);

  await expect(
    page.getByText('MFA Required for Project').first()
  ).toBeVisible();
  await expect(page.getByText(MESSAGE)).toBeVisible();
  for (const name of ['your account', 'Visit your account'])
    await expect(
      page.getByRole('main').getByRole('link', { name, exact: true })
    ).toHaveAttribute('href', '/profile');
});

// @S02
// Scenario: Visiting the account hands off to enrolment
//   Given I am an unenrolled member on "/mfa_required"
//   When I click "Visit your account"
//   Then I am on "/profile"
//   And the flow "flow-require-project-mfa" continues at enrolment (its S03)
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  memberOfMfaProject();
  await signedIn(page);

  await page.getByRole('link', { name: 'Visit your account' }).click();

  // Enrolment itself is flow-require-project-mfa S03
  await expectAt(page, '/profile');
});

// @S03
// Scenario: An enrolled user is not kept on this page
//   Given I have enrolled in MFA
//   When I visit "/mfa_required"
//   Then I am on "/projects"
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  // Sign in first: with MFA already on, login would stop at the second-factor
  // prompt. Enrolling afterwards leaves a normal session for an enrolled user.
  await signInAs(page, ME);
  seedMfaFor(ME);

  await open(page, PAGE);

  await expectAt(page, '/projects');
  await expect(page.getByText(MESSAGE)).toHaveCount(0);
});

// @S04
// Scenario: A blocked member can still reach their other work
//   Given I am an unenrolled member on "/mfa_required"
//   Then the side menu shows "Projects", "User Profile", "Credentials" and "API Tokens"
//   When I click "Projects" in the side menu
//   Then I am on "/projects"
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  memberOfMfaProject();
  await signedIn(page);

  const menu = page.getByRole('navigation');
  for (const name of ['Projects', 'User Profile', 'Credentials', 'API Tokens'])
    await expect(menu.getByRole('link', { name, exact: true })).toBeVisible();

  await menu.getByRole('link', { name: 'Projects', exact: true }).click();

  await expectAt(page, '/projects');
});

// Inherited from shared-authenticated-session, on "/mfa_required".
// S08, S09 are left out: "shared-authenticated-session S08, S09 (book-a-demo
// banner)" is in not_reachable_here.
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on mfa-required',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on mfa-required',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  // The account has MFA by the time the second factor is pending, so the
  // page's own redirect for enrolled users never gets a say
  test(
    'shared-authenticated-session@S03 on mfa-required',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on mfa-required',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S07(page, browser, PAGE, '/credentials', ME);
    }
  );

  for (const [id, variant] of [
    ['S04', 'require-email-verification'],
    ['S05', 'require-email-verification'],
    ['S06', 'require-email-verification'],
    ['S10', 'gdpr-banner'],
    ['S11', 'first-setup-open'],
  ])
    test(
      `shared-authenticated-session@${id} on mfa-required`,
      { tag: tagFor(id, ['S01', 'S02', 'S03', 'S07']) },
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

// Inherited from shared-project-header: the no-project header only.
// S01-S03 and S15, S16 are left out: "shared-project-header S01-S03
// (breadcrumbs and picker button)" and "shared-project-header S15, S16
// (project side menu items)" are in not_reachable_here.
test.describe('shared-project-header', () => {
  for (const id of [
    'S04',
    'S05',
    'S06',
    'S07',
    'S08',
    'S11',
    'S12',
    'S13',
    'S18',
  ] as const)
    test(
      `shared-project-header@${id} on mfa-required`,
      {
        tag: tagFor(id, [
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S11',
          'S12',
          'S13',
          'S18',
          'S09',
          'S10',
          'S17',
        ]),
      },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  test(
    'shared-project-header@S09 on mfa-required',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on mfa-required',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test(
    'shared-project-header@S17 on mfa-required',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S17(page, PAGE);
    }
  );

  test('shared-project-header@S14 on mfa-required', { tag: '@pending' }, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });
});

// Inherited from shared-flash-messages. This page puts no flash of its own, so
// only the Not Found card is reached, by following a link to a project I am
// not in.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S06 on mfa-required',
    { tag: '@passing-old' },
    async ({ page }) => {
      const stranger = seedProject('zz-not-mine', { [OTHER]: 'owner' });
      cleanups.push(stranger.remove);
      await signedIn(page);

      await flashMessages.S06(
        page,
        async () => {
          await page.goto(`/projects/${stranger.id}/w`);
        },
        '/projects',
        page
          .getByRole('main')
          .getByText(manifest().projects[0].name, { exact: true })
      );
    }
  );

  for (const id of ['S01', 'S02', 'S03', 'S04', 'S05', 'S07', 'S08'])
    test(
      `shared-flash-messages@${id} on mfa-required`,
      { tag: tagFor(id, ['S06']) },
      () => {
        test.skip(
          true,
          'this page has no action that puts a flash message, so there is nothing to host the scenario'
        );
      }
    );
});
