// Scenarios from annotations/views/profile-delete-account.md, and the shared
// ones it inherits.
//
// Who's who: in the page's own scenarios "I" and "amara@example.org" are an
// account of my own (Amara Diallo), seeded for each test and removed after,
// so deleting it touches no one else. The inherited session, header, date and
// flash scenarios need a seeded account the shared steps know, so there "I"
// am editor@openfn.org (Esther Editor); keepAccount puts it back.
import { expect, test, type Page } from '@playwright/test';

import { sendDeletion } from './pages/profile';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import * as userDeletionModal from './shared/user-deletion-modal';
import {
  expectAt,
  keepAccount,
  modal,
  open,
  runStartedBy,
  seedUser,
  setSignUpTime,
  signInAs,
  sql,
  tagFor,
  user,
  watchLiveView,
  type SeededUser,
  type UserSeed,
} from './steps';

const ME = 'editor@openfn.org';
const deletePath = (id: string) => `/profile/${id}/delete`;

const cleanups: (() => void)[] = [];
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
  cleanups.length = 0;
});

// Given I am signed in as "amara@example.org" (an account of my own)
async function signedIn(page: Page, seed: UserSeed = {}) {
  const me = seedUser(seed.role === 'superuser' ? 'root' : 'amara', seed);
  cleanups.push(me.remove);
  await signInAs(page, me.email);
  return me;
}

// When I open "/profile/<my user id>/delete"
const deletionOf = (page: Page) => (id: string) => open(page, deletePath(id));

const stateOf = (me: SeededUser) =>
  sql<{ disabled: boolean; scheduled: boolean }>(
    `select coalesce(disabled, false) as disabled,
            scheduled_deletion is not null as scheduled
     from users where id = '${me.id}'`
  )[0];

// The rows of shared-user-deletion-modal's Examples for
// "/profile/<own id>/delete" are this page's scenarios, so they run here
// once: S01 is shared S01, S02 is S04, S03 is S02, S05 is S03, S06 is S05 and
// S07 is S09. Shared S06 to S08 (delete now) are not reachable here (the
// annotation's not_reachable_here: an account scheduled for deletion has no
// session left to open the page).

// @S01
// Scenario: The delete page asks me to confirm over my profile
//   Given I am signed in as "amara@example.org"
//   When I open "/profile/<my user id>/delete"
//   Then I see my profile page
//   And I see a dialog "Delete user"
//   And I see "Your account and credential data will be deleted. Please make sure none of these credentials are used in production workflows."
//   And I see a "User email" field and the buttons "Delete account" and "Cancel"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);

  await userDeletionModal.S01(page, me, deletionOf(page), 'Your');
  // My profile is behind the dialog
  await expect(page.getByText('Delete my account')).toHaveCount(1);
});

// @S02
// Scenario: A user schedules their own account for deletion
//   Given I am signed in as "amara@example.org", who is not a superuser
//   And I am on "/profile/<my user id>/delete"
//   When I set "User email" to "amara@example.org"
//   And I click "Delete account"
//   Then my account is disabled and scheduled for deletion
//   And this browser is sent to "/users/log_out"
//   And the flow "flow-account-revocation-teardown" has started for my account
// Going through "/users/log_out" ends on the log in page.
// Fails on Lightning: scheduling the deletion closes this browser's socket
// before the redirect arrives, so the page stays on the delete page for about
// ten seconds, then reloads to /users/log_in. The rest holds.
test('@S02', { tag: '@pending' }, async ({ page, browser }) => {
  const me = await signedIn(page);

  await userDeletionModal.S04(
    page,
    browser,
    me,
    deletionOf(page),
    /^\/users\/log_(out|in)$/
  );
  // This browser is signed out too
  await page.goto('/profile');
  await expectAt(page, '/users/log_in');
});

// @S03
// Scenario: The wrong email address does not delete the account
//   Given I am on "/profile/<my user id>/delete"
//   When I set "User email" to "invalid@email.com"
//   Then I see "This email doesn't match your current email"
//   When I click "Delete account"
//   Then I still see the dialog with that error
//   And my account is not disabled
//   And no email is sent
// No email: nothing is scheduled, and the scheduling is what sends it.
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const lv = watchLiveView(page);
  const me = await signedIn(page);

  await userDeletionModal.S02(page, me, deletionOf(page), email =>
    sendDeletion(page, lv, email)
  );
  expect(lv.crashes()).toBe(0);
});

// @S04
// Scenario: I can't open the deletion of someone else's account
//   Given I am signed in
//   And "bob@example.org" is another registered user
//   When I open "/profile/<bob's user id>/delete"
//   Then I am on "/profile"
//   And I see "You can't perform this action"
//   And I do not see the "Delete user" dialog
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await signedIn(page);
  const bob = seedUser('bob', { firstName: 'Bob' });
  cleanups.push(bob.remove);

  await page.goto(deletePath(bob.id));

  await expectAt(page, '/profile');
  await expect(page.getByText("You can't perform this action")).toBeVisible();
  await expect(modal(page, 'Delete user')).toHaveCount(0);
  expect(stateOf(bob)).toEqual({ disabled: false, scheduled: false });
});

// @S05
// Scenario: A superuser can't delete their own account here
//   Given I am signed in as a superuser
//   And I am on "/profile/<my user id>/delete"
//   When I set "User email" to my email address
//   Then I see "You can't delete a superuser account."
//   When I click "Delete account"
//   Then my account is not disabled
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const root = await signedIn(page, { role: 'superuser' });

  await userDeletionModal.S03(page, root, deletionOf(page));
});

// @S06
// Scenario: A user who has created runs is warned the account may stay
//   Given I have started a run in a project
//   When I open "/profile/<my user id>/delete"
//   Then I see "*Note that you still have activity related to active projects. We may not be able to delete them entirely from the app until those projects are deleted."
//   Given I have never started a run
//   When I open "/profile/<my user id>/delete"
//   Then I do not see that note
// Two accounts, each signed in in turn: the page only opens for my own.
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const withRun = seedUser('amara');
  const withoutRun = seedUser('bob', { firstName: 'Bob' });
  cleanups.push(withoutRun.remove, withRun.remove, runStartedBy(withRun.id));
  // Signs in as the account whose page opens: it only opens for my own
  const openAs = async (id: string) => {
    await page.context().clearCookies();
    await signInAs(page, id === withRun.id ? withRun.email : withoutRun.email);
    await open(page, deletePath(id));
  };

  await userDeletionModal.S05(page, withRun, withoutRun, openAs);
});

// @S07
// Scenario: Cancelling leaves the account alone
//   Given I am on "/profile/<my user id>/delete"
//   When I click "Cancel"
//   Then I am on "/profile"
//   And I do not see the "Delete user" dialog
//   And my account is not disabled
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const me = await signedIn(page);

  await userDeletionModal.S09(page, me, deletionOf(page), 'Cancel', '/profile');
});

test.describe('inherited, as editor@openfn.org', () => {
  let restoreAccount = () => {};
  test.beforeEach(() => {
    restoreAccount = keepAccount(ME);
  });
  test.afterEach(() => restoreAccount());

  const PAGE = () => deletePath(user(ME).id);

  // Inherited from shared-authenticated-session, as profile-account.
  test.describe('shared-authenticated-session', () => {
    test(
      'shared-authenticated-session@S01 on profile-delete-account',
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await authenticatedSession.S01(page, PAGE(), ME);
      }
    );

    test(
      'shared-authenticated-session@S02 on profile-delete-account',
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page, browser }) => {
        await authenticatedSession.S02(page, browser, PAGE(), ME);
      }
    );

    test(
      'shared-authenticated-session@S03 on profile-delete-account',
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await authenticatedSession.S03(page, PAGE(), ME);
      }
    );

    // On the port the open dialog is modal: the navigation behind it can't
    // be reached until it closes.
    test(
      'shared-authenticated-session@S07 on profile-delete-account',
      { tag: '@passing-old' },
      async ({ page, browser }) => {
        await authenticatedSession.S07(
          page,
          browser,
          PAGE(),
          '/credentials',
          ME
        );
      }
    );

    for (const [id, variant] of [
      ['S04', 'require-email-verification'],
      ['S05', 'require-email-verification'],
      ['S06', 'require-email-verification'],
      ['S08', 'book-demo-banner'],
      ['S09', 'book-demo-banner'],
      ['S10', 'gdpr-banner'],
    ])
      test(
        `shared-authenticated-session@${id} on profile-delete-account`,
        { tag: tagFor(id, []) },
        () => {
          test.skip(
            true,
            `variant ${variant} is not configured on this instance`
          );
        }
      );
  });

  // Inherited from shared-project-header: the no-project header only.
  // S12 fails on Lightning: the open dialog keeps the keyboard, so the
  // project picker shortcut does nothing here. It passes on profile-account.
  // On the port the open dialog is modal, so only S13 (nothing to click)
  // passes; S11, S17 and S18 pass on profile-account.
  test.describe('shared-project-header', () => {
    for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
      test(
        `shared-project-header@${id} on profile-delete-account`,
        {
          tag:
            id === 'S13'
              ? ['@passing-old', '@passing-new']
              : tagFor(id, ['S11', 'S13', 'S18']),
        },
        async ({ page }) => {
          await projectHeader[id](page, PAGE(), ME);
        }
      );

    test(
      'shared-project-header@S17 on profile-delete-account',
      { tag: '@passing-old' },
      async ({ page }) => {
        await projectHeader.S17(page, PAGE());
      }
    );

    test(
      'shared-project-header@S14 on profile-delete-account',
      { tag: '@pending' },
      () => {
        test.skip(
          true,
          'variant require-email-verification is not configured on this instance'
        );
      }
    );
  });

  // Inherited from shared-local-datetime: "Created:" on the profile behind
  // the dialog shows my sign-up time. S04 and S05 fail on Lightning: the
  // dialog covers the timestamp, so it can't be hovered or clicked. The same
  // on the port.
  test.describe('shared-local-datetime', () => {
    // Given my account was created at <utc>, and today is <today>
    async function created(
      page: Page,
      { utc, today }: { utc: string; today?: string }
    ) {
      await signInAs(page, ME);
      setSignUpTime(ME, utc);
      if (today) await page.clock.setFixedTime(today);
      await open(page, PAGE());
      return page.getByText(/^\s*Created:/);
    }

    test.describe(() => {
      test.use({ timezoneId: localDatetime.given.S01.timezoneId });
      test(
        'shared-local-datetime@S01 on profile-delete-account',
        { tag: ['@passing-old', '@passing-new'] },
        async ({ page }) => {
          await localDatetime.S01(
            page,
            await created(page, localDatetime.given.S01)
          );
        }
      );
    });

    for (const id of ['S04', 'S05'] as const)
      test(
        `shared-local-datetime@${id} on profile-delete-account`,
        { tag: tagFor(id, []) },
        async ({ page }) => {
          await localDatetime[id](
            page,
            await created(page, localDatetime.given[id])
          );
        }
      );
  });

  // Inherited from shared-flash-messages: opening someone else's deletion
  // redirects to "/profile" with an error flash.
  test.describe('shared-flash-messages', () => {
    const someoneElse = (page: Page) => async () => {
      await page.goto(deletePath(user('owner@openfn.org').id));
    };

    test(
      'shared-flash-messages@S02 on profile-delete-account',
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await signInAs(page, ME);
        await flashMessages.S02(
          page,
          "You can't perform this action",
          someoneElse(page)
        );
      }
    );

    // S05 is an info flash carried by a redirect; this page's redirect
    // carries an error, which is S02.
  });
});
