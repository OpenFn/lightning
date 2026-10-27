// Scenarios from annotations/views/admin-users.md.
//
// Who's who: "I" am owner@openfn.org, made a superuser for each test (the
// role is put back afterwards). editor@openfn.org is the regular user. The
// accounts a scenario names ("amara@example.org", "root@example.org", …) are
// seeded per test with a fresh email, since every worker's test sees every
// account on the instance, and removed again afterwards.
import { expect, test, type Page } from '@playwright/test';

import {
  clearFilterButton,
  expectInert,
  menuAction,
  openActions,
  sendDeletion,
  tick,
} from './pages/admin-users';
import * as adminSpace from './shared/admin-space';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import * as userDeletionModal from './shared/user-deletion-modal';
import {
  clickable,
  expectAt,
  field,
  keepAccount,
  makeSuperuser,
  modal,
  modalTitle,
  open,
  otherSession,
  runStartedBy,
  seedUser,
  signInAs,
  sql,
  submit,
  tagFor,
  user,
  watchLiveView,
  type UserSeed,
} from './steps';

const ME = 'owner@openfn.org';
const REGULAR = 'editor@openfn.org';
const PAGE = '/settings/users';
const deletePath = (id: string) => `${PAGE}/${id}/delete`;

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), makeSuperuser(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given "<prefix>@example.org" is an account like this (removed after the test)
function given(prefix: string, seed: UserSeed = {}) {
  const account = seedUser(prefix, seed);
  cleanups.push(account.remove);
  return account;
}

// Given <id> has started a run (removed after the test, before the account)
function withRun(id: string) {
  cleanups.push(runStartedBy(id));
}

// Given I am a superuser, signed in and on "/settings/users"
async function signedIn(page: Page, path = PAGE) {
  await signInAs(page, ME);
  await open(page, path);
}

const row = (page: Page, email: string) =>
  page.getByRole('row').filter({ hasText: email });

// The cell of <email>'s row under the column headed <header>
async function cell(page: Page, email: string, header: string) {
  const headers = (await page.getByRole('columnheader').allInnerTexts()).map(
    h => h.trim()
  );
  const column = headers.indexOf(header);
  expect(column, `a "${header}" column`).toBeGreaterThanOrEqual(0);
  return row(page, email).getByRole('cell').nth(column);
}

// Where each of <emails> is listed, top to bottom (-1 when it isn't)
async function positions(page: Page, emails: string[]) {
  const rows = await page.getByRole('row').allInnerTexts();
  return emails.map(e => rows.findIndex(r => r.includes(e)));
}

const ascending = (xs: number[]) =>
  xs.every((x, i) => i === 0 || x > xs[i - 1]);

// When I click the "<header>" header
const sortBy = (page: Page, header: string) =>
  clickable(page.getByRole('columnheader'), header, { exact: true }).click();

const filterBox = (page: Page) => page.getByPlaceholder('Filter users...');

// When I type "<text>" in "Filter users..."
async function typeFilter(page: Page, text: string) {
  await filterBox(page).fill('');
  await filterBox(page).pressSequentially(text);
}

// @S01
// Scenario: A superuser sees every account on the instance
//   Given I am a superuser
//   And "amara@example.org" is a user with first name "Amara", support access and a disabled account
//   And "bob@example.org" is a superuser
//   When I visit "/settings/users"
//   Then I see the heading "Users"
//   And I see the columns "First name", "Last name", "Email", "Role*", "Enabled?", "Support?", "Scheduled Deletion" and "Actions"
//   And the row for "amara@example.org" shows role "user", a support tick and no enabled tick
//   And the row for "bob@example.org" shows role "superuser" and an enabled tick
//   And I see the note that a superuser can access everything in a Lightning installation
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara', {
    firstName: 'Amara',
    supportUser: true,
    disabled: true,
  });
  const bob = given('bob', { firstName: 'Bob', role: 'superuser' });

  await signedIn(page);

  await expect(
    page.getByRole('heading', { name: 'Users', exact: true })
  ).toBeVisible();
  for (const name of [
    'First name',
    'Last name',
    'Email',
    'Role*',
    'Enabled?',
    'Support?',
    'Scheduled Deletion',
    'Actions',
  ])
    await expect(
      page.getByRole('columnheader', { name, exact: true })
    ).toBeVisible();

  await expect(await cell(page, amara.email, 'First name')).toHaveText('Amara');
  await expect(await cell(page, amara.email, 'Role*')).toHaveText('user');
  await expect(tick(await cell(page, amara.email, 'Support?'))).toBeVisible();
  await expect(tick(await cell(page, amara.email, 'Enabled?'))).toHaveCount(0);
  await expect(await cell(page, bob.email, 'Role*')).toHaveText('superuser');
  await expect(tick(await cell(page, bob.email, 'Enabled?'))).toBeVisible();

  await expect(
    page.getByText(
      /superuser\s+can access\s+everything\s+in a\s+Lightning installation/
    )
  ).toBeVisible();
});

// @S02
// Scenario: Filtering narrows the list by name, email or role
//   Given I am a superuser
//   And "alice@example.org" is a user named "Alice Smith"
//   And "bob@example.org" is a superuser named "Bob Johnson"
//   When I visit "/settings/users"
//   Then the clear filter button is hidden
//   When I type "alice" in "Filter users..."
//   Then I see "alice@example.org"
//   And I do not see "bob@example.org"
//   And I see the clear filter button
//   When I type "superuser" in "Filter users..."
//   Then I see "bob@example.org"
//   And I do not see "alice@example.org"
//   When I click the clear filter button
//   Then I see "alice@example.org" and "bob@example.org"
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const alice = given('alice', { firstName: 'Alice', lastName: 'Smith' });
  const bob = given('bob', {
    firstName: 'Bob',
    lastName: 'Johnson',
    role: 'superuser',
  });

  await signedIn(page);
  await expect(row(page, alice.email)).toBeVisible();
  await expect(clearFilterButton(page)).toBeHidden();

  await typeFilter(page, 'alice');
  await expect(row(page, alice.email)).toBeVisible();
  await expect(row(page, bob.email)).toHaveCount(0);
  await expect(clearFilterButton(page)).toBeVisible();

  await typeFilter(page, 'superuser');
  await expect(row(page, bob.email)).toBeVisible();
  await expect(row(page, alice.email)).toHaveCount(0);

  await clearFilterButton(page).click();
  await expect(row(page, alice.email)).toBeVisible();
  await expect(row(page, bob.email)).toBeVisible();
});

// @S03
// Scenario: The list is sorted by email and any column can be sorted
//   Given I am a superuser
//   And users "alpha@example.org", "beta@example.org" and "charlie@example.org" exist
//   And "disabled@example.org" is disabled
//   When I visit "/settings/users"
//   Then the rows are in ascending email order
//   When I click the "Email" header
//   Then the rows are in descending email order
//   When I click the "Enabled?" header
//   Then "disabled@example.org" is listed before the enabled accounts
//   When I click the "Role*" header
//   Then superusers are listed before users
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const emails = ['alpha', 'beta', 'charlie'].map(p => given(p).email);
  const disabled = given('disabled', { disabled: true }).email;
  given('root', { role: 'superuser' });

  await signedIn(page);

  await expect
    .poll(async () => ascending(await positions(page, [...emails, disabled])))
    .toBe(true);

  await sortBy(page, 'Email');
  await expect
    .poll(async () =>
      ascending(await positions(page, [disabled, ...[...emails].reverse()]))
    )
    .toBe(true);

  await sortBy(page, 'Enabled?');
  await expect
    .poll(async () => {
      const [first, ...rest] = await positions(page, [disabled, ...emails]);
      return rest.every(p => p > first);
    })
    .toBe(true);

  await sortBy(page, 'Role*');
  const role = (await page.getByRole('columnheader').allInnerTexts())
    .map(h => h.trim())
    .indexOf('Role*');
  await expect
    .poll(async () => {
      const roles: string[] = [];
      for (const r of await page
        .getByRole('row')
        .filter({ has: page.getByRole('cell') })
        .all())
        roles.push((await r.getByRole('cell').nth(role).innerText()).trim());
      return roles.lastIndexOf('superuser') < roles.indexOf('user');
    })
    .toBe(true);
});

// @S04
// Scenario Outline: Superuser accounts are never offered an active delete action
//   Given I am a superuser
//   And "root@example.org" is a superuser <state>
//   When I open the "Actions" menu for "root@example.org"
//   Then I see <label> as plain text, not a link
//   And I see "Cancel deletion" only when "root@example.org" is scheduled for deletion
//   Examples:
//     | state                         | label        |
//     | not scheduled for deletion    | "Delete"     |
//     | scheduled for deletion        | "Delete now" |
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const examples = [
    { root: given('root', { role: 'superuser' }), label: 'Delete' },
    {
      root: given('root', {
        role: 'superuser',
        scheduledDeletion: '2027-10-21 09:30:00',
      }),
      label: 'Delete now',
    },
  ];

  await signInAs(page, ME);
  for (const { root, label } of examples) {
    await open(page, PAGE);
    const menu = await openActions(page, root.email);

    await expectInert(menu, label);
    await expect(menuAction(menu, 'Cancel deletion')).toHaveCount(
      label === 'Delete now' ? 1 : 0
    );
  }
});

// @S05
// Scenario: Delete on a user account opens the deletion dialog over the list
//   Given I am a superuser
//   And "amara@example.org" is a user not scheduled for deletion
//   When I open the "Actions" menu for "amara@example.org"
//   And I click "Delete"
//   Then I am on "/settings/users/<amara id>/delete"
//   And the users list is still shown behind the dialog
//   And shared-user-deletion-modal is open for "amara@example.org" with return to "/settings/users"
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara');

  await signedIn(page);
  const menu = await openActions(page, amara.email);
  await menuAction(menu, 'Delete').click();

  await expectAt(page, deletePath(amara.id));
  await expect(modalTitle(page, 'Delete user')).toBeVisible();
  // The dialog hides the list from the accessibility tree, so look for text:
  // my own row, which the dialog doesn't mention
  await expect(
    page
      .getByText(user(ME).email, { exact: true })
      .filter({ visible: true })
      .first()
  ).toBeVisible();
  // Its return to "/settings/users" is shared-user-deletion-modal S09
});

// @S06
// Scenario: A scheduled account shows when it will go and offers to cancel or delete now
//   Given I am a superuser
//   And "amara@example.org" is a user scheduled for deletion on 21 Oct at 09:30 UTC
//   When I visit "/settings/users"
//   Then the row for "amara@example.org" shows "21 Oct  09:30" under "Scheduled Deletion"
//   And its "Actions" menu offers "Cancel deletion" and "Delete now" links
//   When I click "Delete now"
//   Then I am on "/settings/users/<amara id>/delete"
//   And shared-user-deletion-modal shows its delete-now branch
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara', { scheduledDeletion: '2027-10-21 09:30:00' });

  await signedIn(page);
  await expect(await cell(page, amara.email, 'Scheduled Deletion')).toHaveText(
    /^\s*21 Oct\s+09:30\s*$/
  );
  const menu = await openActions(page, amara.email);
  await expect(menuAction(menu, 'Cancel deletion')).toBeVisible();
  await menuAction(menu, 'Delete now').click();

  await expectAt(page, deletePath(amara.id));
  // What the delete-now branch does is shared-user-deletion-modal S06 to S08
  await expect(modalTitle(page, 'Delete user')).toBeVisible();
});

// @S07
// Scenario: Cancelling a scheduled deletion restores the account
//   Given I am a superuser
//   And "amara@example.org" is a user scheduled for deletion and disabled
//   When I open the "Actions" menu for "amara@example.org"
//   And I click "Cancel deletion"
//   Then I am on "/settings/users"
//   And I see "User deletion canceled"
//   And the row for "amara@example.org" shows no scheduled deletion date and an enabled tick
//   And "amara@example.org" can sign in again with her password
test(
  '@S07',
  { tag: ['@passing-old', '@passing-new'] },
  async ({ page, browser }) => {
    const amara = given('amara', {
      scheduledDeletion: '2027-10-21 09:30:00',
      disabled: true,
    });

    await signedIn(page);
    const menu = await openActions(page, amara.email);
    await menuAction(menu, 'Cancel deletion').click();

    await expectAt(page, PAGE);
    await expect(
      flashMessages.toast(page, 'User deletion canceled')
    ).toBeVisible();
    await expect(
      await cell(page, amara.email, 'Scheduled Deletion')
    ).toHaveText(/^\s*$/);
    await expect(tick(await cell(page, amara.email, 'Enabled?'))).toBeVisible();
    expect(
      sql(
        `select disabled, scheduled_deletion from users where id = '${amara.id}'`
      )
    ).toEqual([{ disabled: false, scheduled_deletion: null }]);

    const later = await otherSession(browser, amara.email);
    await later.context().close();
  }
);

// @S08
// Scenario Outline: The list leads to the user form
//   Given I am a superuser
//   And "amara@example.org" is a user
//   When I visit "/settings/users"
//   And I <action>
//   Then I am on "<path>"
//   Examples:
//     | action                                                  | path                              |
//     | click "New User"                                        | /settings/users/new               |
//     | open the "Actions" menu for "amara@example.org" and click "Edit" | /settings/users/<amara id> |
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara');

  await signedIn(page);
  await clickable(page, 'New User').click();
  await expectAt(page, `${PAGE}/new`);

  await open(page, PAGE);
  const menu = await openActions(page, amara.email);
  await menuAction(menu, 'Edit').click();
  await expectAt(page, `${PAGE}/${amara.id}`);
});

// Inherited from shared-admin-space: the gate, and the settings layout and
// side menu with "Users" current.
test.describe('shared-admin-space', () => {
  test(
    'shared-admin-space@S01 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S01(page, PAGE, ME, 'Users');
    }
  );

  test(
    'shared-admin-space@S02 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S02(page, PAGE, REGULAR);
    }
  );

  test('shared-admin-space@S03 on admin-users', { tag: '@pending' }, () => {
    test.skip(
      true,
      'needs a socket mount that skips the HTTP check, which no browser action produces; the page cannot be reached with a forged mount'
    );
  });

  for (const id of ['S04', 'S05'])
    test(
      `shared-admin-space@${id} on admin-users`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: it is about "/dashboard"; the inherits line names only S01, S02, S03 and S06'
        );
      }
    );

  test(
    'shared-admin-space@S06 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await adminSpace.S06(page, browser, PAGE, ME);
    }
  );

  test('shared-admin-space@S07 on admin-users', { tag: '@pending' }, () => {
    test.skip(
      true,
      'variant settings-menu-extension is not configured on this instance'
    );
  });
});

// Inherited from shared-authenticated-session, on "/settings/users".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on admin-users',
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
      `shared-authenticated-session@${id} on admin-users`,
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
      `shared-authenticated-session@${id} on admin-users`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line says S08 to S10 are not on the settings layout, and S11 is a first-setup redirect before any page'
        );
      }
    );
});

// Inherited from shared-project-header: the global picker, the confirmation
// banner and the account menu (no-project parts).
test.describe('shared-project-header', () => {
  for (const id of ['S04', 'S06', 'S08', 'S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on admin-users`,
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test('shared-project-header@S14 on admin-users', { tag: '@pending' }, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

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
      `shared-project-header@${id} on admin-users`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line takes only the no-project parts (S04, S06, S08, S10 to S14, S18)'
        );
      }
    );
});

// Inherited from shared-user-deletion-modal, on the admin host:
// "/settings/users/<id>/delete", returning to "/settings/users". The rows of
// its Examples for "/profile/<own id>/delete" belong to profile-delete-account.
test.describe('shared-user-deletion-modal', () => {
  // Given the modal is open on "/settings/users/<id>/delete"
  const deletionOf = (page: Page) => async (id: string) => {
    await open(page, deletePath(id));
  };

  test(
    'shared-user-deletion-modal@S01 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara');
      await signInAs(page, ME);
      await userDeletionModal.S01(page, amara, deletionOf(page), "This user's");
    }
  );

  test(
    'shared-user-deletion-modal@S02 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara');
      const lv = watchLiveView(page);
      await signInAs(page, ME);
      await userDeletionModal.S02(page, amara, deletionOf(page), email =>
        sendDeletion(page, lv, email)
      );
    }
  );

  test(
    'shared-user-deletion-modal@S03 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const root = given('root', { role: 'superuser' });
      await signInAs(page, ME);
      await userDeletionModal.S03(page, root, deletionOf(page));
    }
  );

  test(
    'shared-user-deletion-modal@S04 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      const amara = given('amara');
      await signInAs(page, ME);
      await userDeletionModal.S04(page, browser, amara, deletionOf(page), PAGE);
    }
  );

  test(
    'shared-user-deletion-modal@S05 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara');
      withRun(amara.id);
      const bob = given('bob', { firstName: 'Bob' });
      await signInAs(page, ME);
      await userDeletionModal.S05(page, amara, bob, deletionOf(page));
    }
  );

  test(
    'shared-user-deletion-modal@S06 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara', {
        scheduledDeletion: '2027-10-21 09:30:00',
      });
      await signInAs(page, ME);
      await userDeletionModal.S06(page, amara, deletionOf(page), PAGE);
    }
  );

  test(
    'shared-user-deletion-modal@S07 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara', {
        scheduledDeletion: '2027-10-21 09:30:00',
      });
      withRun(amara.id);
      await signInAs(page, ME);
      await userDeletionModal.S07(page, amara, deletionOf(page));
    }
  );

  test(
    'shared-user-deletion-modal@S08 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara', {
        scheduledDeletion: '2027-10-21 09:30:00',
      });
      await signInAs(page, ME);
      await userDeletionModal.S08(
        page,
        amara,
        deletionOf(page),
        () => withRun(amara.id),
        PAGE
      );
    }
  );

  test(
    'shared-user-deletion-modal@S09 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara');
      await signInAs(page, ME);
      await userDeletionModal.S09(page, amara, deletionOf(page), 'Close', PAGE);
    }
  );
});

// Inherited from shared-flash-messages. This page is on the settings layout,
// whose toast is S07; its redirects after a deletion carry a flash (S05).
test.describe('shared-flash-messages', () => {
  // When I cancel a scheduled deletion from the list
  async function cancelDeletion(page: Page) {
    const amara = given('amara', { scheduledDeletion: '2027-10-21 09:30:00' });
    await signedIn(page);
    const menu = await openActions(page, amara.email);
    await menuAction(menu, 'Cancel deletion').click();
  }

  test(
    'shared-flash-messages@S05 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      const amara = given('amara', {
        scheduledDeletion: '2027-10-21 09:30:00',
      });
      await signInAs(page, ME);
      await flashMessages.S05(
        page,
        'User deleted',
        async () => {
          // "Delete now", confirmed: the page redirects to the list
          await open(page, deletePath(amara.id));
          const d = modal(page, 'Delete user');
          await expect(modalTitle(page, 'Delete user')).toBeVisible();
          await field(d, 'User email').fill(amara.email);
          await field(d, 'User email').blur();
          await submit(d, 'Delete account');
        },
        PAGE
      );
    }
  );

  test(
    'shared-flash-messages@S07 on admin-users',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await flashMessages.S07(page, 'User deletion canceled', () =>
        cancelDeletion(page)
      );
    }
  );

  for (const [id, why] of [
    ['S01', 'it is about the live layout; the settings layout toast is S07'],
    ['S02', 'it is about the live layout; the settings layout toast is S07'],
    ['S03', 'it is about the live layout; the settings layout toast is S07'],
    ['S04', 'it is about the live layout; the settings layout toast is S07'],
    [
      'S06',
      'nothing on this page sends a "not found" or "no access" nav flash',
    ],
    ['S08', 'it is about the sign-in and account forms'],
  ])
    test(
      `shared-flash-messages@${id} on admin-users`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(true, `not reachable here: ${why}`);
      }
    );
});
