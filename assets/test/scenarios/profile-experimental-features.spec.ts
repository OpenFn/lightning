// Scenarios from annotations/views/profile-experimental-features.md.
//
// "I" is editor@openfn.org. Every test seeds the saved preferences it needs
// and puts editor's account back as it found it (keepAccount in steps.ts).
import { expect, test, type Page } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as projectHeader from './shared/project-header';
import {
  experimentalSwitch,
  keepAccount,
  manifest,
  open,
  preferencesOf,
  setPreferences,
  signInAs,
  tagFor,
} from './steps';

const ME = 'editor@openfn.org';
const PAGE = '/profile';

let restoreAccount = () => {};
test.beforeEach(() => {
  restoreAccount = keepAccount(ME);
});
test.afterEach(() => restoreAccount());

// Given I am signed in, with these saved preferences, and on "/profile"
async function signedIn(page: Page, prefs: Record<string, unknown> = {}) {
  await signInAs(page, ME);
  setPreferences(ME, prefs);
  await open(page, PAGE);
}

const enabled = () => preferencesOf(ME).experimental_features;

// @S01
// Scenario: The card shows experimental features off by default
//   Given I am signed in and have never changed the setting
//   When I open "/profile"
//   Then I see the card "Experimental features"
//   And I see "Enable access to new features and improvements before they're generally available"
//   And the switch is off
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);

  await expect(page.getByText(/experimental features/i).first()).toBeVisible();
  await expect(
    page.getByText(
      "Enable access to new features and improvements before they're generally available"
    )
  ).toBeVisible();
  await expect(experimentalSwitch(page)).not.toBeChecked();
});

// @S02 @variant:experimental-features
// Scenario: The card shows the setting is on when it is on
//   Given I have experimental features turned on
//   When I open "/profile"
//   Then the switch in "Experimental features" is on
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page, { experimental_features: true });

  await expect(experimentalSwitch(page)).toBeChecked();
});

// @S03
// Scenario: A user turns experimental features on
//   Given I am on "/profile" with experimental features off
//   When I switch on "Experimental features"
//   Then experimental features are on for my account
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page, { experimental_features: false });

  await experimentalSwitch(page).click();

  await expect.poll(enabled).toBe(true);
});

// @S04 @variant:experimental-features
// Scenario: A user turns experimental features off
//   Given I am on "/profile" with experimental features on
//   When I switch off "Experimental features"
//   Then experimental features are off for my account
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page, { experimental_features: true });

  await experimentalSwitch(page).click();

  // A missing key counts as off too, so only "not on" is required
  await expect.poll(enabled).not.toBe(true);
});

// @S05
// Scenario: Changing the setting keeps my other preferences
//   Given I have other saved preferences
//   When I switch on "Experimental features"
//   Then my other saved preferences are unchanged
//   And experimental features are on for my account
test('@S05', { tag: '@passing-old' }, async ({ page }) => {
  const others = { sidebar_collapsed: true, run_log_level: 'debug' };
  await signedIn(page, others);

  await experimentalSwitch(page).click();

  await expect.poll(enabled).toBe(true);
  expect(preferencesOf(ME)).toMatchObject(others);
});

// @S06
// Scenario: The setting reaches the rest of the app
//   Given I switched on "Experimental features" on "/profile"
//   When I next open a page in a project I belong to
//   Then shared-project-header S16 applies to my account
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);
  await experimentalSwitch(page).click();
  await expect.poll(enabled).toBe(true);

  await open(page, `/projects/${manifest().projects[0].id}/w`);

  await projectHeader.experimentalIndicators(page, ME, true, true);
});

// Inherited from shared-authenticated-session, on "/profile".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S07(page, browser, PAGE, '/credentials', ME);
    }
  );

  for (const [id, variant] of [
    ['S04', 'require-email-verification'],
    ['S05', 'require-email-verification'],
    ['S06', 'require-email-verification'],
    ['S08', 'book-demo-banner'],
    ['S09', 'book-demo-banner'],
    ['S10', 'gdpr-banner'],
    ['S11', 'first-setup-open'],
  ])
    test(
      `shared-authenticated-session@${id} on profile-experimental-features`,
      { tag: tagFor(id, ['S01', 'S02', 'S03', 'S07']) },
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

// Inherited from shared-project-header: the no-project parts only. S01-S03
// and S15 need a project page, which this page doesn't show.
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
      `shared-project-header@${id} on profile-experimental-features`,
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
          'S16',
        ]),
      },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  test(
    'shared-project-header@S09 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test(
    'shared-project-header@S17 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S17(page, PAGE);
    }
  );

  test(
    'shared-project-header@S16 on profile-experimental-features',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S16(page, PAGE, ME);
    }
  );

  test(
    'shared-project-header@S14 on profile-experimental-features',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );
});
