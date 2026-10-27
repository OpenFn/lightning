// Scenarios from annotations/views/admin-maintenance.md.
//
// Who's who: "I" am owner@openfn.org, made a superuser for each test (the
// role is put back afterwards). editor@openfn.org is the regular user.
//
// The adaptor registry is a stand-in on the node (standInRegistry in
// steps.ts), so no refresh reaches npm or changes the instance's real
// adaptors. It publishes only adaptors with a fresh name
// ("@openfn/language-scenario-<hex>") that the test removes afterwards; the
// scenarios' "@openfn/language-http" stands for any adaptor. Swapping the
// registry, or making the scheduler unreachable, is instance-wide, so every
// test that runs a refresh is @serial.
import { createHash, randomUUID } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import { runButton, type MaintenanceCard } from './pages/admin-maintenance';
import * as adminSpace from './shared/admin-space';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import { toast } from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import {
  adaptorsOnInstance,
  failIconFetches,
  holdRegistry,
  keepAccount,
  listingsSoFar,
  makeSuperuser,
  open,
  publishUpstream,
  removeAdaptors,
  schedulerUnreachable,
  seedAdaptor,
  signInAs,
  standInRegistry,
  startRegistryRefresh,
  storedAdaptor,
  tagFor,
  type Upstream,
} from './steps';

const ME = 'owner@openfn.org';
const REGULAR = 'editor@openfn.org';
const PAGE = '/settings/maintenance';
const REGISTRY: MaintenanceCard = 'Refresh Adaptor Registry';
const ICONS: MaintenanceCard = 'Refresh Adaptor Icons';
const EVENTUALLY = { timeout: 30_000 };

let cleanups: (() => unknown)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), makeSuperuser(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

const SCHEMA = '{"type":"object","properties":{"baseUrl":{"type":"string"}}}';
const NEW_SCHEMA =
  '{"type":"object","properties":{"baseUrl":{"type":"string"},"apiKey":{"type":"string"}}}';
const sha256 = (text: string) =>
  createHash('sha256').update(text).digest('hex');

// An adaptor no other test or real catalogue has, removed after the test
function freshAdaptor() {
  const name = `@openfn/language-scenario-${randomUUID().slice(0, 8)}`;
  cleanups.push(() => removeAdaptors([name]));
  return name;
}

// Given the registry is the stand-in, publishing <upstream> (put back after)
function registry(upstream: Upstream = {}) {
  cleanups.push(standInRegistry(upstream));
}

// Given the stand-in holds its answers until the test releases them
function held() {
  holdRegistry(true);
  cleanups.push(() => holdRegistry(false));
}

// Given I am a superuser on the maintenance page
async function signedIn(page: Page) {
  await signInAs(page, ME);
  await open(page, PAGE);
}

// When I click "Run" on the <card> card
const run = (page: Page, card: MaintenanceCard) =>
  runButton(page, card).click();

// @S01
// Scenario: A superuser sees both maintenance actions
//   Given I am a superuser
//   When I open "/settings/maintenance"
//   Then I see the title "Maintenance"
//   And I see a "Refresh Adaptor Registry" card reading "Re-fetch the list of available adaptors and their versions." with a "Run" button
//   And I see a "Refresh Adaptor Icons" card reading "Does not touch adaptor metadata or version history." with a "Run" button
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await signedIn(page);

  await expect(
    page.getByRole('heading', { name: 'Maintenance', exact: true })
  ).toBeVisible();
  for (const [card, reading] of [
    [REGISTRY, 'Re-fetch the list of available adaptors and their versions.'],
    [ICONS, 'Does not touch adaptor metadata or version history.'],
  ] as const) {
    await expect(page.getByRole('heading', { name: card })).toBeVisible();
    await expect(page.getByText(reading)).toBeVisible();
    await expect(runButton(page, card)).toHaveText(/^\s*Run\s*$/);
    await expect(runButton(page, card)).toBeEnabled();
  }
});

// @S02
// Scenario: Refreshing the adaptor registry is queued and confirmed at once
//   Given I am a superuser on "/settings/maintenance"
//   And a new version of "@openfn/language-http" has been published upstream
//   When I click "Run" on the "Refresh Adaptor Registry" card
//   Then I see "Adaptor refresh queued."
//   And the flow "flow-adaptor-catalogue-update" has started
test(
  '@S02',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const http = freshAdaptor();
    registry({ [http]: { version: '7.0.0', schema: SCHEMA, icon: 'icon-a' } });
    seedAdaptor(http);
    await signedIn(page);
    publishUpstream({
      [http]: { version: '7.1.0', schema: SCHEMA, icon: 'icon-a' },
    });

    await run(page, REGISTRY);

    await expect(toast(page, 'Adaptor refresh queued.')).toBeVisible();
    // The handoff: the new version is in the catalogue
    await expect
      .poll(() => storedAdaptor(http)?.latest_version, EVENTUALLY)
      .toBe('7.1.0');
  }
);

// @S03
// Scenario: A registry refresh that can't be started is reported as a failure
//   Given I am a superuser on "/settings/maintenance"
//   And the adaptors scheduler is not reachable
//   When I click "Run" on the "Refresh Adaptor Registry" card
//   Then I see an error beginning "Refresh failed:"
//   And I do not see "Adaptor refresh queued."
test(
  '@S03',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await signedIn(page);
    cleanups.push(schedulerUnreachable());

    await run(page, REGISTRY);

    await expect(toast(page, 'Refresh failed:')).toBeVisible(EVENTUALLY);
    await expect(toast(page, 'Adaptor refresh queued.')).toHaveCount(0);
  }
);

// @S04
// Scenario: A registry refresh during one already running joins it
//   Given I am a superuser on "/settings/maintenance"
//   And an adaptor registry refresh is already running
//   When I click "Run" on the "Refresh Adaptor Registry" card
//   Then I see "Adaptor refresh queued."
//   And only one registry refresh runs
test(
  '@S04',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const http = freshAdaptor();
    registry({ [http]: { version: '7.1.0', schema: SCHEMA, icon: 'icon-a' } });
    await signedIn(page);
    held();
    startRegistryRefresh();
    await expect.poll(listingsSoFar).toBe(1);

    await run(page, REGISTRY);
    await expect(toast(page, 'Adaptor refresh queued.')).toBeVisible();

    holdRegistry(false);
    await expect
      .poll(() => storedAdaptor(http)?.latest_version, EVENTUALLY)
      .toBe('7.1.0');
    // A second refresh would have asked for its own listing by now
    expect(listingsSoFar(), 'registry listings').toBe(1);
  }
);

// @S05
// Scenario: Refreshing icons reports its start and then its result
//   Given I am a superuser on "/settings/maintenance"
//   And the upstream icon for "@openfn/language-dhis2" has changed
//   When I click "Run" on the "Refresh Adaptor Icons" card
//   Then I see "Icon refresh started."
//   And eventually I see "Icon refresh complete" with 1 updated and the rest unchanged
//   And the flow "flow-adaptor-catalogue-update" has started for "@openfn/language-dhis2"
test(
  '@S05',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const dhis2 = freshAdaptor();
    registry({ [dhis2]: { version: '2.0.0', schema: SCHEMA, icon: 'icon-a' } });
    seedAdaptor(dhis2);
    const rest = adaptorsOnInstance() - 1;
    await signedIn(page);
    held();

    await run(page, ICONS);

    await expect(toast(page, 'Icon refresh started.')).toBeVisible();
    holdRegistry(false);
    const done = toast(page, 'Icon refresh complete');
    await expect(done).toBeVisible(EVENTUALLY);
    await expect(done).toContainText(/(?<!\d)1 updated/);
    await expect(done).toContainText(new RegExp(`(?<!\\d)${rest} unchanged`));
    // The handoff: the new icon is in the catalogue
    expect(storedAdaptor(dhis2)?.icon_sha256).toBe(sha256('icon-a'));
  }
);

// @S06
// Scenario: A failed icon refresh is reported as an error
//   Given I am a superuser on "/settings/maintenance"
//   And fetching icons upstream fails
//   When I click "Run" on the "Refresh Adaptor Icons" card
//   Then eventually I see an error beginning "Icon refresh failed"
test(
  '@S06',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    registry();
    failIconFetches();
    await signedIn(page);

    await run(page, ICONS);

    await expect(toast(page, 'Icon refresh failed')).toBeVisible(EVENTUALLY);
  }
);

// @S07
// Scenario: An icon refresh never changes adaptor versions or metadata
//   Given "@openfn/language-http" is stored at version "7.0.0" with a configuration schema
//   And upstream now lists "@openfn/language-http" at "7.1.0" with a new icon
//   When I run the icon refresh as a superuser
//   Then "@openfn/language-http" is still stored at "7.0.0" with the same schema and version history
//   And its icon is updated
test(
  '@S07',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const http = freshAdaptor();
    registry({ [http]: { version: '7.0.0', schema: SCHEMA, icon: 'icon-a' } });
    seedAdaptor(http);
    const before = storedAdaptor(http)!;
    expect(before.latest_version).toBe('7.0.0');
    expect(before.schema_sha256).toBe(sha256(SCHEMA));
    publishUpstream({
      [http]: { version: '7.1.0', schema: NEW_SCHEMA, icon: 'icon-b' },
    });

    await signedIn(page);
    await run(page, ICONS);
    await expect(toast(page, 'Icon refresh complete')).toBeVisible(EVENTUALLY);

    const after = storedAdaptor(http)!;
    expect(after.latest_version).toBe('7.0.0');
    expect(after.schema_sha256).toBe(before.schema_sha256);
    expect(after.versions).toEqual(before.versions);
    expect(after.icon_sha256).toBe(sha256('icon-b'));
  }
);

// @S08 @variant:local-adaptors
// Scenario: Under the local adaptors strategy, icons come from the local repo
//   Given the instance uses the local adaptors strategy
//   And I have replaced the square icon of "@openfn/language-http" in the local adaptors repo
//   When I run the icon refresh as a superuser
//   Then eventually I see "Icon refresh complete" with 1 updated
test('@S08', { tag: '@pending' }, () => {
  test.skip(
    true,
    'variant local-adaptors is not configured on this instance: the strategy and its catalogue source are chosen at boot'
  );
});

// Inherited from shared-admin-space: the gate (this page checks the policy
// itself), and the settings layout and side menu with "Maintenance" current.
test.describe('shared-admin-space', () => {
  test(
    'shared-admin-space@S01 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S01(page, PAGE, ME, 'Maintenance');
    }
  );

  test(
    'shared-admin-space@S02 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S02(page, PAGE, REGULAR);
    }
  );

  test(
    'shared-admin-space@S03 on admin-maintenance',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'needs a socket mount that skips the HTTP check, which no browser action produces; the page cannot be reached with a forged mount'
      );
    }
  );

  for (const id of ['S04', 'S05'])
    test(
      `shared-admin-space@${id} on admin-maintenance`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: it is about "/dashboard"; the inherits line names only S01, S02 and the gate'
        );
      }
    );

  test(
    'shared-admin-space@S06 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await adminSpace.S06(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-admin-space@S07 on admin-maintenance',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant settings-menu-extension is not configured on this instance'
      );
    }
  );
});

// Inherited from shared-authenticated-session, on "/settings/maintenance".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      // The admin menu has no "Credentials"; "Audit" is a label it does have
      await authenticatedSession.S07(
        page,
        browser,
        PAGE,
        '/settings/audit',
        ME,
        'Audit'
      );
    }
  );

  for (const id of ['S04', 'S05', 'S06'])
    test(
      `shared-authenticated-session@${id} on admin-maintenance`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'variant require-email-verification is not configured on this instance'
        );
      }
    );

  for (const id of ['S08', 'S09', 'S10', 'S11'])
    test(
      `shared-authenticated-session@${id} on admin-maintenance`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line says banners are not on the settings layout (S08 to S10), and S11 is a first-setup redirect before any page'
        );
      }
    );
});

// Inherited from shared-project-header: the global picker, the confirmation
// banner and the account menu (no-project parts).
test.describe('shared-project-header', () => {
  for (const id of ['S04', 'S06', 'S08', 'S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on admin-maintenance`,
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test(
    'shared-project-header@S14 on admin-maintenance',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );

  for (const id of [
    'S01',
    'S02',
    'S03',
    'S05',
    'S07',
    'S09',
    'S15',
    'S16',
    'S17',
  ])
    test(
      `shared-project-header@${id} on admin-maintenance`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line takes only the no-project parts (S04, S06, S08, S10 to S14, S18)'
        );
      }
    );
});

// Inherited from shared-flash-messages. Every result on this page is a flash
// on the settings layout, whose toast is S07. It runs a registry refresh, so
// it is @serial with the stand-in registry.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S07 on admin-maintenance',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      registry();
      await flashMessages.S07(page, 'Adaptor refresh queued.', async () => {
        await signedIn(page);
        await run(page, REGISTRY);
      });
    }
  );

  for (const [id, why] of [
    ['S01', 'it is about the live layout; the settings layout toast is S07'],
    ['S02', 'it is about the live layout; the settings layout toast is S07'],
    ['S03', 'it is about the live layout; the settings layout toast is S07'],
    ['S04', 'it is about the live layout; the settings layout toast is S07'],
    ['S05', 'no action on this page redirects; each flash shows in place'],
    [
      'S06',
      'nothing on this page sends a "not found" or "no access" nav flash',
    ],
    ['S08', 'it is about the sign-in and account forms'],
  ])
    test(
      `shared-flash-messages@${id} on admin-maintenance`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(true, `not reachable here: ${why}`);
      }
    );
});
