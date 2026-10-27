// Scenarios from annotations/views/admin-user-edit.md.
//
// Who's who: "I" am owner@openfn.org, made a superuser for each test (the
// role is put back afterwards). editor@openfn.org is the regular user. The
// accounts a scenario names ("amara@example.org", "root@example.org", …) are
// seeded per test, or created by the test, with a fresh email, since every
// worker's test sees every account on the instance, and removed afterwards.
import { randomUUID } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import {
  disabledCheckbox,
  sendSave,
  supportSwitch,
  type UserValues,
} from './pages/admin-user-edit';
import * as adminSpace from './shared/admin-space';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import { toast } from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import {
  auditEventsOf,
  clickable,
  expectAt,
  field,
  keepAccount,
  mailbox,
  mailerFailing,
  makeSuperuser,
  open,
  otherSession,
  PASSWORD,
  passwordWorks,
  removeAccountByEmail,
  seedUser,
  sessionsOf,
  signInAs,
  sql,
  storedAccount,
  submit,
  submitButton,
  tagFor,
  user,
  watchLiveView,
  type UserSeed,
} from './steps';

const ME = 'owner@openfn.org';
const REGULAR = 'editor@openfn.org';
const LIST = '/settings/users';
const NEW = '/settings/users/new';
const editPath = (id: string) => `${LIST}/${id}`;
const GOOD_PASSWORD = 'a long enough password';

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

// A fresh "<prefix>-…@example.org" for an account the test creates or moves
// to; whatever holds it is removed after the test
function freshEmail(prefix: string) {
  const email = `${prefix}-${randomUUID().slice(0, 8)}@example.org`;
  cleanups.push(() => removeAccountByEmail(email));
  return email;
}

// Given I am a superuser, signed in and on <path>
async function signedIn(page: Page, path: string) {
  await signInAs(page, ME);
  await open(page, path);
}

type TextField = 'First Name' | 'Last Name' | 'Email' | 'Password';

// When I fill in <label> with <value>, for each pair. An empty value is typed
// then cleared: a box only filled with "" doesn't count as used, and today's
// form shows errors only on used fields.
async function fillIn(page: Page, values: Partial<Record<TextField, string>>) {
  for (const [label, value] of Object.entries(values)) {
    const box = field(page, label);
    if (value === '') await box.fill('x');
    await box.fill(value);
  }
}

// When I choose role "<label>"
const chooseRole = (page: Page, label: 'User' | 'Superuser') =>
  field(page, 'Role').selectOption({ label });

// When I click "Save" on a form both versions accept. Today's form keeps Save
// off until its check of what was typed comes back, and submit() leaves an off
// button alone, so wait for it first.
async function save(page: Page) {
  await expect(submitButton(page, 'Save')).toBeEnabled();
  await submit(page, 'Save');
}

// When I create an account for <email> with role <role>
async function createAccount(
  page: Page,
  email: string,
  role: 'User' | 'Superuser' = 'User'
) {
  await open(page, NEW);
  await fillIn(page, {
    'First Name': 'Amara',
    'Last Name': 'Okafor',
    Email: email,
    Password: GOOD_PASSWORD,
  });
  await chooseRole(page, role);
  await save(page);
}

// The cell of <email>'s row in the users list, under the column headed <header>
async function listCell(page: Page, email: string, header: string) {
  const headers = (await page.getByRole('columnheader').allInnerTexts()).map(
    h => h.trim()
  );
  const column = headers.indexOf(header);
  expect(column, `a "${header}" column`).toBeGreaterThanOrEqual(0);
  return page
    .getByRole('row')
    .filter({ hasText: email })
    .getByRole('cell')
    .nth(column);
}

// @S01
// Scenario: A superuser creates a user account
//   Given I am a superuser
//   When I visit "/settings/users/new"
//   And I fill in "First Name" with "Amara", "Last Name" with "Okafor", "Email" with "amara@example.org" and "Password" with "a long enough password"
//   And I choose role "User"
//   And I click "Save"
//   Then I am on "/settings/users"
//   And I see "User created successfully"
//   And I see "amara@example.org" in the list with role "user"
//   And an audit event "user" "created" is recorded for "amara@example.org" with me as the actor
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const email = freshEmail('amara');
  await signInAs(page, ME);

  await createAccount(page, email);

  await expectAt(page, LIST);
  await expect(toast(page, 'User created successfully')).toBeVisible();
  await expect(await listCell(page, email, 'Role*')).toHaveText('user');
  const created = storedAccount({ email });
  expect(created).toMatchObject({
    first_name: 'Amara',
    last_name: 'Okafor',
    role: 'user',
  });
  expect(auditEventsOf(created!.id)).toContainEqual({
    event: 'created',
    actor_id: user(ME).id,
  });
});

// @S02
// Scenario: A new account is sent a confirmation email that names its creator
//   Given I am a superuser named "Bob" with email "bob@example.org"
//   When I create an account for "amara@example.org"
//   Then an email "Confirm your OpenFn account" is sent to "amara@example.org"
//   And it says "Bob has just created an OpenFn account for you"
//   And it names "bob@example.org" as the person to contact
//   And the flow "flow-admin-created-account-confirm" has started for "amara@example.org"
// "Bob" is me: my own first name and email. The flow has started when a
// confirmation token waits for the new account.
test(
  '@S02',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, request }) => {
    const email = freshEmail('amara');
    const [me] = sql<{ first_name: string; email: string }>(
      `select first_name, email from users where id = '${user(ME).id}'`
    );
    await signInAs(page, ME);

    await createAccount(page, email);
    await expectAt(page, LIST);

    const sentTo = async () =>
      (await mailbox(request)).filter(m => m.to.includes(email));
    await expect
      .poll(async () => (await sentTo()).map(m => m.subject))
      .toEqual(['Confirm your OpenFn account']);
    const text = ((await sentTo())[0].text ?? '').replace(/\s+/g, ' ');
    expect(text).toContain(
      `${me.first_name} has just created an OpenFn account for you`
    );
    expect(text).toContain(`contact ${me.first_name} (${me.email})`);
    const { id } = storedAccount({ email })!;
    expect(
      sql(
        `select 1 from user_tokens where context = 'confirm' and user_id = '${id}'`
      )
    ).toHaveLength(1);
  }
);

// @S03
// Scenario: The superuser is told when the confirmation email could not be sent
//   Given I am a superuser
//   And the mailer refuses deliveries
//   When I create an account for "amara@example.org"
//   Then I am on "/settings/users"
//   And I see the error "User created, but the confirmation email could not be sent"
//   And "amara@example.org" is in the list
test(
  '@S03',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const email = freshEmail('amara');
    await signInAs(page, ME);
    cleanups.push(mailerFailing());

    await createAccount(page, email);

    await expectAt(page, LIST);
    await expect(
      toast(page, 'User created, but the confirmation email could not be sent')
    ).toBeVisible();
    await expect(
      page.getByRole('row').filter({ hasText: email })
    ).toBeVisible();
  }
);

// @S04
// Scenario: A superuser creates another superuser
//   Given I am a superuser
//   When I create an account for "root@example.org" with role "Superuser"
//   Then I see "User created successfully"
//   And "root@example.org" is stored with role superuser
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const email = freshEmail('root');
  await signInAs(page, ME);

  await createAccount(page, email, 'Superuser');

  await expect(toast(page, 'User created successfully')).toBeVisible();
  expect(storedAccount({ email })?.role).toBe('superuser');
});

// @S05
// Scenario: The form refuses an account that can't be used
//   Given I am a superuser
//   And "taken@example.org" already has an account
//   When I visit "/settings/users/new"
//   Then the "Save" button is disabled
//   When I clear "First Name"
//   Then I see "can't be blank"
//   When I fill in "Email" with "taken@example.org"
//   Then I see "has already been taken"
//   When I fill in "Password" with "short"
//   Then I see that the password should be at least 12 characters
//   And the "Save" button is disabled
// The Value is that nothing is stored. Today's form turns Save off while the
// form is invalid; the port checks on press. So each step presses Save through
// submit() and checks the message and the database, not the button. Each bad
// account is then sent past the form too, and must still not be stored.
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const taken = given('taken');
  const email = freshEmail('amara');
  const lv = watchLiveView(page);
  await signedIn(page, NEW);
  const nothingStored = () => {
    expect(storedAccount({ email })).toBeUndefined();
    expect(
      sql(`select 1 from users where email = '${taken.email}'`)
    ).toHaveLength(1);
  };

  // When I clear "First Name" (the rest is fine)
  await fillIn(page, {
    'First Name': '',
    'Last Name': 'Okafor',
    Email: email,
    Password: GOOD_PASSWORD,
  });
  await submit(page, 'Save');
  await expect(page.getByText("can't be blank")).toBeVisible();
  nothingStored();

  // When I fill in "Email" with "taken@example.org". The changeset's "has
  // already been taken" reaches users as its translation.
  await fillIn(page, { 'First Name': 'Amara', Email: taken.email });
  await submit(page, 'Save');
  await expect(
    page.getByText(/has already been taken|This value should be unique/)
  ).toBeVisible();
  nothingStored();

  // When I fill in "Password" with "short"
  await fillIn(page, { Email: email, Password: 'short' });
  await submit(page, 'Save');
  await expect(
    page.getByText('Password minimum length is 12 characters.')
  ).toBeVisible();
  nothingStored();

  // The same three accounts, sent past the form
  const good: UserValues = {
    firstName: 'Amara',
    lastName: 'Okafor',
    email,
    password: GOOD_PASSWORD,
    role: 'user',
  };
  for (const bad of [
    { ...good, firstName: '' },
    { ...good, email: taken.email },
    { ...good, password: 'short' },
  ]) {
    await sendSave(page, lv, bad);
    expect.soft(storedAccount({ email }), JSON.stringify(bad)).toBeUndefined();
    removeAccountByEmail(email);
  }
  expect(
    sql(`select 1 from users where email = '${taken.email}'`)
  ).toHaveLength(1);
  expect(lv.crashes()).toBe(0);
});

// @S06
// Scenario: A superuser changes an account's details, role and access
//   Given I am a superuser
//   And "amara@example.org" is a user
//   When I visit "/settings/users/<amara id>"
//   And I change "First Name" to "Ama", "Email" to "ama@example.org" and "Password" to "some updated password"
//   And I choose role "Superuser"
//   And I tick the disabled checkbox
//   And I click "Save"
//   Then I am on "/settings/users"
//   And I see "User updated successfully"
//   And the account has email "ama@example.org", role superuser, is disabled, and signs in only with "some updated password"
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara');
  const newEmail = freshEmail('ama');
  await signedIn(page, editPath(amara.id));

  await fillIn(page, {
    'First Name': 'Ama',
    Email: newEmail,
    Password: 'some updated password',
  });
  await chooseRole(page, 'Superuser');
  await disabledCheckbox(page).check();
  await save(page);

  await expectAt(page, LIST);
  await expect(toast(page, 'User updated successfully')).toBeVisible();
  expect(storedAccount({ id: amara.id })).toMatchObject({
    first_name: 'Ama',
    email: newEmail,
    role: 'superuser',
    disabled: true,
  });
  expect(passwordWorks(amara.id, 'some updated password')).toBe(true);
  expect(passwordWorks(amara.id, PASSWORD)).toBe(false);
});

// @S07
// Scenario: Leaving the password blank keeps the current one
//   Given I am a superuser
//   And "amara@example.org" signs in with "her own password"
//   When I visit "/settings/users/<amara id>"
//   And I change "Last Name" to "Okafor-Bello" and leave "Password" empty
//   And I click "Save"
//   Then "amara@example.org" still signs in with "her own password"
//   And the flow "flow-account-revocation-teardown" reports her sessions untouched
// Her password is the seeded one; she is signed in in another browser.
test(
  '@S07',
  { tag: ['@passing-old', '@passing-new'] },
  async ({ page, browser }) => {
    const amara = given('amara');
    const elsewhere = await otherSession(browser, amara.email);
    const sessions = sessionsOf(amara.id);
    expect(sessions).toBeGreaterThan(0);
    await signedIn(page, editPath(amara.id));

    await fillIn(page, { 'Last Name': 'Okafor-Bello' });
    await expect(field(page, 'Password')).toHaveValue('');
    await save(page);

    await expect(toast(page, 'User updated successfully')).toBeVisible();
    expect(storedAccount({ id: amara.id })?.last_name).toBe('Okafor-Bello');
    expect(passwordWorks(amara.id, PASSWORD)).toBe(true);
    expect(sessionsOf(amara.id)).toBe(sessions);
    await elsewhere.context().close();
  }
);

// @S08
// Scenario Outline: Changes that reduce or move access hand off to the revocation flow
//   Given I am a superuser
//   And "amara@example.org" is a superuser with support access, signed in elsewhere
//   When I visit "/settings/users/<amara id>"
//   And I <change>
//   And I click "Save"
//   Then I see "User updated successfully"
//   And the flow "flow-account-revocation-teardown" has started for "amara@example.org"
//
//   Examples:
//     | change                                        |
//     | tick the disabled checkbox                    |
//     | set "Password" to "a brand new password"      |
//     | change "Email" to "amara@new.example.org"     |
//     | choose role "User"                            |
//     | turn off "Support User"                       |
// The flow has started when her sessions are gone. Each example has its own
// account, and is checked softly so one failure doesn't hide the rest.
test(
  '@S08',
  { tag: ['@passing-old', '@passing-new'] },
  async ({ page, browser }) => {
    const changes: [string, () => Promise<unknown>][] = [
      ['tick the disabled checkbox', () => disabledCheckbox(page).check()],
      [
        'set "Password" to "a brand new password"',
        () => fillIn(page, { Password: 'a brand new password' }),
      ],
      [
        'change "Email" to "amara@new.example.org"',
        () => fillIn(page, { Email: freshEmail('amara-new') }),
      ],
      ['choose role "User"', () => chooseRole(page, 'User')],
      ['turn off "Support User"', () => supportSwitch(page).click()],
    ];
    const soft = expect.configure({ soft: true });
    await signInAs(page, ME);

    for (const [change, act] of changes) {
      const amara = given('amara', { role: 'superuser', supportUser: true });
      const elsewhere = await otherSession(browser, amara.email);
      expect(sessionsOf(amara.id), change).toBeGreaterThan(0);
      await open(page, editPath(amara.id));

      await act();
      await save(page);

      await soft(
        toast(page, 'User updated successfully'),
        change
      ).toBeVisible();
      await soft.poll(() => sessionsOf(amara.id), { message: change }).toBe(0);
      await elsewhere.context().close();
    }
  }
);

// @S09
// Scenario: A superuser changes someone's email without their confirmation
//   Given I am a superuser
//   And "amara@example.org" is a confirmed user
//   When I visit "/settings/users/<amara id>"
//   And I change "Email" to "amara@new.example.org" and click "Save"
//   Then the account's email is "amara@new.example.org" at once
//   And no email is sent to either address
//   And an audit event "user" "updated" records the email before and after
//   And the flow "flow-change-email-confirm" has not started
// That flow has started when a pending "change:" token exists for her.
test(
  '@S09',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, request }) => {
    const amara = given('amara');
    const newEmail = freshEmail('amara-new');
    await signedIn(page, editPath(amara.id));

    await fillIn(page, { Email: newEmail });
    await save(page);

    await expect(toast(page, 'User updated successfully')).toBeVisible();
    expect(storedAccount({ id: amara.id })?.email).toBe(newEmail);
    const sent = (await mailbox(request)).filter(
      m => m.to.includes(amara.email) || m.to.includes(newEmail)
    );
    expect(sent).toEqual([]);
    const events = sql<{ before: string; after: string }>(
      `select changes->'before'->>'email' as before,
              changes->'after'->>'email' as after
       from audit_events where item_id = '${amara.id}' and event = 'updated'`
    );
    expect(events).toEqual([{ before: amara.email, after: newEmail }]);
    expect(
      sql(
        `select 1 from user_tokens
         where user_id = '${amara.id}' and context like 'change:%'`
      )
    ).toEqual([]);
  }
);

// @S10
// Scenario: Granting support access warns how far it reaches
//   Given I am a superuser
//   And "amara@example.org" is a user without support access
//   When I visit "/settings/users/<amara id>"
//   Then I do not see "Heads Up!"
//   When I turn on "Support User"
//   Then I see "This user will be able to access ALL projects that have support access enabled"
//   When I click "Save"
//   Then "amara@example.org" has support access
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara');
  await signedIn(page, editPath(amara.id));
  await expect(page.getByText('Heads Up!')).toBeHidden();

  await supportSwitch(page).click();

  await expect(
    page.getByText(
      'This user will be able to access ALL projects that have support access enabled'
    )
  ).toBeVisible();
  await save(page);
  await expect(toast(page, 'User updated successfully')).toBeVisible();
  expect(storedAccount({ id: amara.id })?.support_user).toBe(true);
});

// @S11
// Scenario: Scheduled deletion is only offered for non-superuser accounts
//   Given I am a superuser
//   And "amara@example.org" is a user
//   When I visit "/settings/users/<amara id>"
//   Then I see "Scheduled Deletion"
//   When I choose role "Superuser"
//   Then I do not see "Scheduled Deletion"
//   When I visit "/settings/users/<my id>"
//   Then I do not see "Scheduled Deletion"
//   When I choose role "User"
//   Then I see "Scheduled Deletion"
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara');
  const deletion = field(page, 'Scheduled Deletion');
  await signedIn(page, editPath(amara.id));
  await expect(deletion).toBeVisible();

  await chooseRole(page, 'Superuser');
  await expect(deletion).toBeHidden();

  await open(page, editPath(user(ME).id));
  await expect(deletion).toBeHidden();

  await chooseRole(page, 'User');
  await expect(deletion).toBeVisible();
});

// @S12
// Scenario: Cancel leaves the account unchanged
//   Given I am a superuser
//   And "amara@example.org" is a user
//   When I visit "/settings/users/<amara id>"
//   And I change "First Name" to "Someone else"
//   And I click "Cancel"
//   Then I am on "/settings/users"
//   And the account's first name is unchanged
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const amara = given('amara', { firstName: 'Amara' });
  await signedIn(page, editPath(amara.id));

  await fillIn(page, { 'First Name': 'Someone else' });
  await clickable(page, 'Cancel').click();

  await expectAt(page, LIST);
  expect(storedAccount({ id: amara.id })?.first_name).toBe('Amara');
});

// Inherited from shared-admin-space: the gate, the settings layout and side
// menu with "Users" current, and the demotion handoff.
test.describe('shared-admin-space', () => {
  test(
    'shared-admin-space@S01 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S01(page, NEW, ME, 'Users');
    }
  );

  // Both routes, with the regular user's own id on the edit one
  test(
    'shared-admin-space@S02 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S02(page, NEW, REGULAR);
      await page.context().clearCookies(); // signed out, so S02 can sign in
      await adminSpace.S02(page, editPath(user(REGULAR).id), REGULAR);
    }
  );

  test('shared-admin-space@S03 on admin-user-edit', { tag: '@pending' }, () => {
    test.skip(
      true,
      'needs a socket mount that skips the HTTP check, which no browser action produces; the page cannot be reached with a forged mount'
    );
  });

  for (const id of ['S04', 'S05'])
    test(
      `shared-admin-space@${id} on admin-user-edit`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: it is about "/dashboard"; the inherits line names S01 to S03 and S06'
        );
      }
    );

  test(
    'shared-admin-space@S06 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await adminSpace.S06(page, browser, NEW, ME);
    }
  );

  test('shared-admin-space@S07 on admin-user-edit', { tag: '@pending' }, () => {
    test.skip(
      true,
      'variant settings-menu-extension is not configured on this instance'
    );
  });
});

// Inherited from shared-authenticated-session, on "/settings/users/new".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, NEW, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, NEW, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, NEW, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      // The admin menu has no "Credentials"; "Audit" is a label it does have
      await authenticatedSession.S07(
        page,
        browser,
        NEW,
        '/settings/audit',
        ME,
        'Audit'
      );
    }
  );

  for (const id of ['S04', 'S05', 'S06'])
    test(
      `shared-authenticated-session@${id} on admin-user-edit`,
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
      `shared-authenticated-session@${id} on admin-user-edit`,
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
      `shared-project-header@${id} on admin-user-edit`,
      { tag: ['@passing-old', '@passing-new'] },
      async ({ page }) => {
        await projectHeader[id](page, NEW, ME);
      }
    );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectHeader.S10(page, NEW, ME, '/w');
    }
  );

  test(
    'shared-project-header@S14 on admin-user-edit',
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
      `shared-project-header@${id} on admin-user-edit`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line takes only the no-project parts (S04, S06, S08, S10 to S14, S18)'
        );
      }
    );
});

// Inherited from shared-flash-messages. Save puts its flash and moves to
// "/settings/users" (S05), where the admin toast stays until clicked (S07).
test.describe('shared-flash-messages', () => {
  // When I save a change to an account's last name
  async function saveAChange(page: Page) {
    const amara = given('amara');
    await open(page, editPath(amara.id));
    await fillIn(page, { 'Last Name': 'Okafor-Bello' });
    await save(page);
  }

  test(
    'shared-flash-messages@S05 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await signInAs(page, ME);
      await flashMessages.S05(
        page,
        'User updated successfully',
        () => saveAChange(page),
        LIST
      );
    }
  );

  test(
    'shared-flash-messages@S07 on admin-user-edit',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await signInAs(page, ME);
      await flashMessages.S07(page, 'User updated successfully', () =>
        saveAChange(page)
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
      `shared-flash-messages@${id} on admin-user-edit`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(true, `not reachable here: ${why}`);
      }
    );
});
