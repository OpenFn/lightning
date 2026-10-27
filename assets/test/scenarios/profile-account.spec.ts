// Scenarios from annotations/views/profile-account.md.
//
// Who's who: "I", "Amara Okafor" and "amara@example.org" are editor@openfn.org
// (Esther Editor), whose password "correct horse battery" is the seeded
// welcome12345. Every test puts editor's name, email, password, sidebar,
// sign-up time, disabled flag and MFA back as it found them.
import { expect, test, type Locator, type Page } from '@playwright/test';

import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import {
  expectAt,
  field,
  fieldBlock,
  keepAccount,
  mailbox,
  mailerFailing,
  open,
  otherSession,
  PASSWORD,
  setSignUpTime,
  signInAs,
  sql,
  user,
  tagFor,
} from './steps';

const ME = 'editor@openfn.org';
const PAGE = '/profile';

let restoreAccount = () => {};
test.beforeEach(() => {
  restoreAccount = keepAccount(ME);
});
test.afterEach(() => restoreAccount());

const me = () =>
  sql<{
    first_name: string;
    last_name: string;
    email: string;
    contact_preference: string;
    hashed_password: string;
  }>(
    `select first_name, last_name, email, contact_preference, hashed_password
     from users where id = '${user(ME).id}'`
  )[0];

const pendingEmailChanges = () =>
  sql<{ sent_to: string }>(
    `select sent_to from user_tokens
     where user_id = '${user(ME).id}' and context like 'change:%'`
  );

// Given I am signed in and on "/profile"
async function signedIn(page: Page) {
  await signInAs(page, ME);
  await open(page, PAGE);
}

// When I request an email change to <email> with <password>
async function requestEmailChange(page: Page, email: string, password: string) {
  await field(page, 'New email address').fill(email);
  await field(page, 'Enter password to confirm').fill(password);
  // Both fields validate on blur
  await field(page, 'Enter password to confirm').blur();
  await clickIfYouCan(page.getByRole('button', { name: 'Update email' }));
}

// When I click <button> — a disabled button fails the scenario but lets the
// remaining steps still report what they see
async function clickIfYouCan(button: Locator) {
  await expect
    .soft(button, 'should be clickable')
    .toBeEnabled({ timeout: 5000 });
  if (await button.isEnabled()) await button.click();
}

// @S01
// Scenario: The profile shows whose account this is
//   Given I am signed in as "Amara Okafor" with email "amara@example.org"
//   When I open "/profile"
//   Then I see the heading "Amara Okafor"
//   And I see "Email: amara@example.org"
//   And I see "Created:" followed by my sign-up date
//   And I see the cards "Change basic information", "Change email", "Change password" and "Delete account"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { first_name, last_name } = me();
  const [{ inserted_at }] = sql<{ inserted_at: string }>(
    `select to_char(inserted_at, 'YYYY-MM-DD HH24:MI:SS') as inserted_at
     from users where id = '${user(ME).id}'`
  );

  await signedIn(page);

  await expect(page.getByRole('heading', { level: 2 })).toHaveText(
    `${first_name} ${last_name}`
  );
  await expect(
    page.getByText(`Email: ${user(ME).email}`, { exact: true })
  ).toBeVisible();
  // "Created:" is followed by a timestamp whose exact value is my sign-up
  const created = page.getByRole('paragraph').filter({ hasText: 'Created:' });
  await expect(created).toBeVisible();
  await created.getByText(/\d/).first().hover();
  await expect(page.getByRole('tooltip')).toContainText(`${inserted_at} UTC`);
  for (const title of [
    'Change basic information',
    'Change email',
    'Change password',
    'Delete account',
  ])
    await expect(page.getByText(title, { exact: true })).toBeVisible();
});

// @S02
// Scenario: A user updates their name and contact preference
//   Given I am signed in as "Amara Okafor"
//   When I set "First name" to "Kylian" and "Last name" to "Mbappe"
//   And I set "Contact preference" to "Anytime"
//   And I click "Save"
//   Then I see "User information updated successfully"
//   And I see the heading "Kylian Mbappe"
//   And "Contact preference" shows "Anytime"
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await signedIn(page);

  await field(page, 'First name').fill('Kylian');
  await field(page, 'Last name').fill('Mbappe');
  await field(page, 'Contact preference').selectOption({ label: 'Anytime' });
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(
    page.getByText('User information updated successfully')
  ).toBeVisible();
  await expect(page.getByRole('heading', { level: 2 })).toHaveText(
    'Kylian Mbappe'
  );
  await expect(
    field(page, 'Contact preference').locator('option:checked')
  ).toHaveText('Anytime');
  expect(me()).toMatchObject({
    first_name: 'Kylian',
    last_name: 'Mbappe',
    contact_preference: 'any',
  });
});

// @S03
// Scenario: A blank or unprintable name is refused
//   Given I am on "/profile"
//   When I clear "First name"
//   Then I see "This field can't be blank." under "First name"
//   When I set "First name" to "Kylian" followed by a bell character and click "Save"
//   Then I see "can't contain control characters"
//   And my name is unchanged
// Fails on Lightning: once the bell is typed the name is invalid and Save is
// disabled, so it can't be clicked. The error shows and the name is unchanged.
// Fails on the port: the design system words the blank name "can't be blank".
test('@S03', { tag: '@pending' }, async ({ page }) => {
  const before = me();
  await signedIn(page);

  await field(page, 'First name').fill('');
  await expect(
    fieldBlock(page, 'First name').getByText("This field can't be blank.")
  ).toBeVisible();

  await field(page, 'First name').fill('Kylian\u0007');
  await clickIfYouCan(page.getByRole('button', { name: 'Save' }));

  await expect(
    page.getByText("can't contain control characters")
  ).toBeVisible();
  expect(me().first_name).toBe(before.first_name);
});

// @S04
// Scenario: A user asks to change their email with their password
//   Given I am signed in as "amara@example.org" with password "correct horse battery"
//   When I set "New email address" to "amara@new.example.org"
//   And I set "Enter password to confirm" to "correct horse battery"
//   And I click "Update email"
//   Then I see "You will receive an email with instructions shortly."
//   And my email is still "amara@example.org"
//   And the flow "flow-change-email-confirm" has started for "amara@new.example.org"
// Fails on Lightning: the form's LiveComponent puts the message without a
// redirect, and LiveView passes no such flash to the page. The flow starts.
// Passes on the port.
test(
  '@S04',
  { tag: ['@passing-new', '@serial'] },
  async ({ page, request }) => {
    const NEW = 'amara@new.example.org';
    const sentBefore = (await mailbox(request)).length;
    await signedIn(page);

    await requestEmailChange(page, NEW, PASSWORD);

    await expect
      .soft(
        page.getByText('You will receive an email with instructions shortly.')
      )
      .toBeVisible();
    expect(me().email).toBe(ME);
    await expect(
      page.getByText(`Email: ${user(ME).email}`, { exact: true })
    ).toBeVisible();
    // flow-change-email-confirm has started: a pending change for the new
    // address, a warning to the old one and instructions to the new one
    expect(pendingEmailChanges()).toEqual([{ sent_to: NEW }]);
    const after = await mailbox(request);
    const sent = after.slice(0, after.length - sentBefore);
    expect(sent).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          to: [ME],
          subject: 'Your OpenFn email was changed',
        }),
        expect.objectContaining({
          to: [NEW],
          subject: 'Please confirm your new email',
        }),
      ])
    );
  }
);

// @S05
// Scenario: An email change with the wrong password is refused
//   Given I am signed in as "amara@example.org"
//   When I set "New email address" to "attacker@example.org"
//   And I set "Enter password to confirm" to a wrong password
//   And I click "Update email"
//   Then "Enter password to confirm" shows an error
//   And no email is sent
// Fails on Lightning: the password is checked when the field loses focus,
// which disables "Update email", so it can't be clicked. The field shows
// "Your passwords do not match." and nothing is sent. Passes on the port.
test(
  '@S05',
  { tag: ['@passing-new', '@serial'] },
  async ({ page, request }) => {
    const sentBefore = (await mailbox(request)).length;
    await signedIn(page);

    await requestEmailChange(page, 'attacker@example.org', 'not-my-password');

    await expect(
      fieldBlock(page, 'Enter password to confirm').getByRole('paragraph')
    ).not.toHaveCount(0);
    await expect(
      page.getByText('You will receive an email with instructions shortly.')
    ).toHaveCount(0);
    expect(pendingEmailChanges()).toEqual([]);
    expect((await mailbox(request)).length).toBe(sentBefore);
  }
);

// @S06
// Scenario: An address that can't receive mail is refused before anything is sent
//   Given I am on "/profile"
//   When I set "New email address" to "oops email" and leave the field
//   Then I see "Email address not valid."
//   And "Update email" is disabled
// Differs on the port: the design system words it "must be a valid email
// address" and leaves "Update email" on. Nothing is sent.
test(
  '@S06',
  { tag: ['@passing-old', '@serial'] },
  async ({ page, request }) => {
    const sentBefore = (await mailbox(request)).length;
    await signedIn(page);

    await field(page, 'New email address').fill('oops email');
    await field(page, 'New email address').blur();

    await expect(
      fieldBlock(page, 'New email address').getByText(
        'Email address not valid.'
      )
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Update email' })
    ).toBeDisabled();
    expect(pendingEmailChanges()).toEqual([]);
    expect((await mailbox(request)).length).toBe(sentBefore);
  }
);

// @S07
// Scenario: A failed email delivery is reported
//   Given the mailer is failing
//   When I request an email change with my correct password
//   Then I see "Failed to request email update"
// Fails on Lightning: same as @S04, the error flash never reaches the page.
// Passes on the port.
test('@S07', { tag: ['@passing-new', '@serial'] }, async ({ page }) => {
  await signedIn(page);
  const restoreMailer = mailerFailing();
  try {
    await requestEmailChange(page, 'amara@new.example.org', PASSWORD);

    await expect(
      page.getByText('Failed to request email update')
    ).toBeVisible();
  } finally {
    restoreMailer();
  }
});

// @S08
// Scenario: A user changes their password
//   Given I am signed in with password "correct horse battery"
//   When I set "New password" and "Confirm new password" to "a much longer phrase"
//   And I set "Current password" to "correct horse battery"
//   And I click "Update password"
//   Then I am on "/projects"
//   And I see "Password changed successfully."
//   And I can sign in with "a much longer phrase"
//   And the flow "flow-account-revocation-teardown" has started for my account
// Fails on Lightning: the change closes this browser's socket before the
// redirect arrives, so the page stays on /profile for about ten seconds, then
// reloads to /users/log_in with no message. The rest holds. The same on the
// port.
test('@S08', { tag: '@pending' }, async ({ page, browser }) => {
  const NEW = 'a much longer phrase';
  const elsewhere = await otherSession(browser, ME);
  await signedIn(page);

  await field(page, 'New password').fill(NEW);
  await field(page, 'Confirm new password').fill(NEW);
  await field(page, 'Current password').fill(PASSWORD);
  await page.getByRole('button', { name: 'Update password' }).click();

  await expect
    .soft(page, 'should land on /projects')
    .toHaveURL(/^[^/]+\/\/[^/]+\/projects$/, { timeout: 15000 });
  await expect
    .soft(page.getByText('Password changed successfully.'))
    .toBeVisible();
  // flow-account-revocation-teardown has started: my other session is out
  await elsewhere.goto(PAGE);
  await expectAt(elsewhere, '/users/log_in');
  await elsewhere.context().close();
  // I can sign in with the new password
  const again = await otherSession(browser, ME, NEW);
  await again.context().close();
});

// @S09
// Scenario: A password change with the wrong current password is refused
//   Given I am on "/profile"
//   When I enter a valid new password twice
//   And I set "Current password" to a wrong password
//   And I click "Update password"
//   Then I see "is not valid" under "Current password"
//   And my password is unchanged
//   And my other sessions are still signed in
test(
  '@S09',
  { tag: ['@passing-old', '@passing-new'] },
  async ({ page, browser }) => {
    const before = me().hashed_password;
    const elsewhere = await otherSession(browser, ME);
    await signedIn(page);

    await field(page, 'New password').fill('a much longer phrase');
    await field(page, 'Confirm new password').fill('a much longer phrase');
    await field(page, 'Current password').fill('not-my-password');
    await page.getByRole('button', { name: 'Update password' }).click();

    await expect(
      fieldBlock(page, 'Current password').getByText('is not valid')
    ).toBeVisible();
    expect(me().hashed_password).toBe(before);
    await open(elsewhere, PAGE);
    await expectAt(elsewhere, PAGE);
    await elsewhere.context().close();
  }
);

// @S10
// Scenario: A new password must be long enough and typed the same twice
//   Given I am on "/profile"
//   When I set "New password" to "abc"
//   Then I see "Password minimum length is 12 characters."
//   When I set "New password" to "password1234" and "Confirm new password" to "password4567"
//   Then I see "Your passwords do not match."
//   And "Update password" is disabled
// Differs on the port: the design system words them "should be at least 12
// character(s)" and "does not match password", and leaves "Update password" on.
test('@S10', { tag: '@passing-old' }, async ({ page }) => {
  await signedIn(page);

  await field(page, 'New password').fill('abc');
  await expect(
    fieldBlock(page, 'New password').getByText(
      'Password minimum length is 12 characters.'
    )
  ).toBeVisible();

  await field(page, 'New password').fill('password1234');
  await field(page, 'Confirm new password').fill('password4567');
  await expect(page.getByText('Your passwords do not match.')).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Update password' })
  ).toBeDisabled();
});

// @S11
// Scenario: The profile leads to account deletion
//   Given I am signed in
//   When I click "Delete my account"
//   Then I am on "/profile/<my user id>/delete"
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await signedIn(page);

  await page.getByRole('link', { name: 'Delete my account' }).click();

  await expectAt(page, `/profile/${user(ME).id}/delete`);
});

// @S12 @variant:gdpr-preferences
// Scenario: The configured GDPR preferences card is shown
//   Given the instance configures a GDPR preferences component
//   When I open "/profile"
//   Then I see the configured preferences component
//   Given the instance does not configure one
//   When I open "/profile"
//   Then I do not see it
test('@S12', { tag: '@pending' }, () => {
  test.skip(
    true,
    'variant gdpr-preferences: this instance sets :gdpr_preferences to false and ships no component'
  );
});

// Inherited from shared-authenticated-session, on "/profile".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
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
  ])
    test(
      `shared-authenticated-session@${id} on profile-account`,
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
test.describe('shared-project-header', () => {
  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on profile-account`,
      { tag: tagFor(id, ['S11', 'S12', 'S13', 'S18', 'S17'], true) },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  test(
    'shared-project-header@S17 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await projectHeader.S17(page, PAGE);
    }
  );

  test(
    'shared-project-header@S14 on profile-account',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );
});

// Inherited from shared-local-datetime: "Created:" shows my sign-up time.
test.describe('shared-local-datetime', () => {
  // Given my account was created at <utc>, and today is <today>
  async function created(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    await signInAs(page, ME);
    setSignUpTime(ME, utc);
    if (today) await page.clock.setFixedTime(today);
    await open(page, PAGE);
    return page.getByRole('paragraph').filter({ hasText: 'Created:' });
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on profile-account',
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
      `shared-local-datetime@${id} on profile-account`,
      { tag: tagFor(id, ['S01', 'S04', 'S05'], true) },
      async ({ page }) => {
        await localDatetime[id](
          page,
          await created(page, localDatetime.given[id])
        );
      }
    );
});

// Inherited from shared-flash-messages: the profile's own messages.
test.describe('shared-flash-messages', () => {
  // When I save a new first name
  const saveName = (page: Page) => async () => {
    await field(page, 'First name').fill('Kylian');
    await page.getByRole('button', { name: 'Save' }).click();
  };
  const SAVED = 'User information updated successfully';

  test(
    'shared-flash-messages@S01 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S01(page, SAVED, saveName(page));
    }
  );

  // Fails on this page: its only error flash never renders (see @S07). On
  // the port the message is a red alert in the email form, not a toast.
  test(
    'shared-flash-messages@S02 on profile-account',
    { tag: ['@pending', '@serial'] },
    async ({ page }) => {
      await signedIn(page);
      const restoreMailer = mailerFailing();
      try {
        await flashMessages.S02(page, 'Failed to request email update', () =>
          requestEmailChange(page, 'amara@new.example.org', PASSWORD)
        );
      } finally {
        restoreMailer();
      }
    }
  );

  test(
    'shared-flash-messages@S03 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S03(page, SAVED, saveName(page));
    }
  );

  test(
    'shared-flash-messages@S04 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S04(page, SAVED, saveName(page), async () => {
        // Typing in a form makes the page render again
        await field(page, 'Last name').fill('Mbappe');
        await expect(page.getByRole('button', { name: 'Save' })).toBeEnabled();
      });
    }
  );

  test(
    'shared-flash-messages@S05 on profile-account',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await signedIn(page);
      await flashMessages.S05(page, SAVED, saveName(page), PAGE);
    }
  );
});
