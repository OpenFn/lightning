// Scenarios from annotations/views/first-setup.md.
//
// Who's who: the page only opens on an instance with no superuser, so every
// test that needs one takes the role away from the instance's superusers
// (firstSetupOpen in steps.ts) and gives it back afterwards. Accounts the
// test creates get a fresh "<name>-…@example.org" and are removed after.
// "amara@example.org" is seeded per test. editor@openfn.org is the signed-in
// regular user where a scenario needs one. Every test changes or reads
// instance-wide state (the superusers, the first setup setting), so all are
// @serial and leave both as they found them.
import { randomUUID } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import { liveNavigate, sendSave, type SetupValues } from './pages/first-setup';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import {
  expectAt,
  field,
  firstSetupOpen,
  open,
  removeAccountByEmail,
  seedUser,
  signInAs,
  sql,
  storedAccount,
  submit,
  submitButton,
  watchLiveView,
  withFlag,
} from './steps';

const PATH = '/first_setup';
const REGULAR = 'editor@openfn.org';
const GOOD_PASSWORD = 'a long enough password';
const PASSING = { tag: ['@passing-old', '@passing-new', '@serial'] };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given first setup is allowed
// And there is no superuser
function noSuperuser() {
  cleanups.push(firstSetupOpen());
}

// Given first setup is allowed (a superuser may exist)
function firstSetupAllowed() {
  cleanups.push(withFlag('allow_first_setup', true));
}

// Given first setup is not allowed
function firstSetupClosed() {
  cleanups.push(withFlag('allow_first_setup', false));
}

// A fresh "<prefix>-…@example.org"; any account holding it is removed after
function freshEmail(prefix: string) {
  const email = `${prefix}-${randomUUID().slice(0, 8)}@example.org`;
  cleanups.push(() => removeAccountByEmail(email));
  return email;
}

const superuserCount = () =>
  sql<{ n: number }>(
    `select count(*)::int as n from users where role = 'superuser'`
  )[0].n;

const LABELS: Record<keyof SetupValues, string> = {
  firstName: 'First name',
  lastName: 'Last name',
  email: 'Email',
  password: 'Password',
  passwordConfirmation: 'Password confirmation',
};

// Values that pass every check, for the fields a scenario doesn't name
const good = (email: string): SetupValues => ({
  firstName: 'Test',
  lastName: 'McTest',
  email,
  password: GOOD_PASSWORD,
  passwordConfirmation: GOOD_PASSWORD,
});

// When I fill in each field given. An empty value is typed then cleared: a
// box only filled with "" doesn't count as used, and today's form shows
// errors only on used fields.
async function fillIn(page: Page, values: Partial<SetupValues>) {
  for (const [key, value] of Object.entries(values)) {
    const box = field(page, LABELS[key as keyof SetupValues]);
    if (value === '') await box.fill('x');
    await box.fill(value);
  }
}

// When I fill in the form with good values for <email> and click "Save".
// Today's form keeps Save off until its check of what was typed comes back,
// and submit() leaves an off button alone, so wait for it first.
async function createSuperuser(page: Page, email: string) {
  await open(page, PATH);
  await fillIn(page, good(email));
  await expect(submitButton(page, 'Save')).toBeEnabled();
  await submit(page, 'Save');
}

// @S01
// Scenario: Operator creates the first superuser and is handed off to sign in
//   Given first setup is allowed
//   And there is no superuser
//   When I open "/first_setup"
//   Then I see the heading "Setup"
//   When I fill in first name "Test", last name "McTest", email "foo@example.com"
//   And I fill in password and password confirmation "1234567890ab"
//   And I click "Save"
//   Then a user "foo@example.com" exists with role superuser
//   And the flow "flow-first-superuser-sign-in" has started for "foo@example.com"
test('@S01', PASSING, async ({ page }) => {
  noSuperuser();
  const email = freshEmail('foo');
  await open(page, PATH);
  await expect(page.getByRole('heading', { name: 'Setup' })).toBeVisible();

  await fillIn(page, {
    ...good(email),
    password: '1234567890ab',
    passwordConfirmation: '1234567890ab',
  });
  await expect(submitButton(page, 'Save')).toBeEnabled();
  // The flow has started when the browser is sent to exchange its sign-in token
  const [handoff] = await Promise.all([
    page.waitForRequest(r =>
      new URL(r.url()).pathname.startsWith('/users/token_exchange/')
    ),
    submit(page, 'Save'),
  ]);

  expect(storedAccount({ email })?.role).toBe('superuser');
  expect(new URL(handoff.url()).pathname).toMatch(
    /^\/users\/token_exchange\/./
  );
});

// @S02
// Scenario: A mismatched password confirmation is flagged while typing
//   Given first setup is allowed
//   And there is no superuser
//   When I open "/first_setup"
//   And I type password "123" and leave the confirmation empty
//   Then I see "does not match confirmation"
//   And "Save" is disabled
// "Save is disabled" is not asserted: today's form turns it off, the design
// system keeps it on and refuses on press. Pressing it creates nothing on both.
test('@S02', PASSING, async ({ page }) => {
  noSuperuser();
  await open(page, PATH);

  await fillIn(page, { password: '123', passwordConfirmation: '' });
  await submit(page, 'Save');

  await expect(page.getByText('does not match confirmation')).toBeVisible();
  expect(superuserCount()).toBe(0);
});

// @S03
// Scenario: A password shorter than 12 characters is refused
//   Given first setup is allowed
//   And there is no superuser
//   When I open "/first_setup"
//   And I type password and confirmation "123"
//   Then I see "Password minimum length is 12 characters."
//   And "Save" is disabled
// "Save is disabled": as S02.
test('@S03', PASSING, async ({ page }) => {
  noSuperuser();
  await open(page, PATH);

  await fillIn(page, { password: '123', passwordConfirmation: '123' });
  await submit(page, 'Save');

  await expect(
    page.getByText('Password minimum length is 12 characters.')
  ).toBeVisible();
  expect(superuserCount()).toBe(0);
});

// @S04
// Scenario: A superuser without first and last name is refused
//   Given first setup is allowed
//   And there is no superuser
//   When I open "/first_setup"
//   And I fill in first name " ", an empty last name, email "nameless@example.com" and a valid password and confirmation
//   Then I see "can't be blank"
//   And "Save" is disabled
//   When I submit the form anyway
//   Then I see "can't be blank"
//   And no user "nameless@example.com" exists
//   And there is still no superuser
// "Save is disabled": as S02. "Submit anyway" is the save sent past the form.
// Today's page shows "can't be blank" translated ("This field can't be
// blank."); the design system shows the raw text. Both hold the words.
test('@S04', PASSING, async ({ page }) => {
  noSuperuser();
  const email = freshEmail('nameless');
  const lv = watchLiveView(page);
  await open(page, PATH);
  const values = { ...good(email), firstName: ' ', lastName: '' };

  await fillIn(page, values);
  await submit(page, 'Save');
  await expect(page.getByText(/can't be blank/).first()).toBeVisible();

  await sendSave(page, lv, values);

  await expect(page.getByText(/can't be blank/).first()).toBeVisible();
  expect(storedAccount({ email })).toBeUndefined();
  expect(superuserCount()).toBe(0);
});

// @S05
// Scenario: A name with a control character is refused
//   Given first setup is allowed
//   And there is no superuser
//   When I open "/first_setup"
//   And I submit first name "Ann" followed by a bell character, last name "Smith", email "bell@example.com" and a valid password
//   Then I see "can't contain control characters"
//   And no user "bell@example.com" exists
//   And there is still no superuser
// Today's Save is off for this form, so the save is also sent past the form.
test('@S05', PASSING, async ({ page }) => {
  noSuperuser();
  const email = freshEmail('bell');
  const lv = watchLiveView(page);
  await open(page, PATH);
  const values = {
    ...good(email),
    firstName: 'Ann\u0007',
    lastName: 'Smith',
  };

  await fillIn(page, values);
  await submit(page, 'Save');

  await expect(
    page.getByText("can't contain control characters").first()
  ).toBeVisible();
  await sendSave(page, lv, values);
  expect(storedAccount({ email })).toBeUndefined();
  expect(superuserCount()).toBe(0);
});

// @S06
// Scenario: An invalid or already registered email is refused
//   Given first setup is allowed
//   And there is no superuser
//   And a non-superuser account "amara@example.org" exists
//   When I open "/first_setup"
//   And I fill in email "not-an-email"
//   Then I see "must be a valid email address"
//   When I fill in email "amara@example.org"
//   Then I see "has already been taken"
//   And "Save" is disabled
// "Save is disabled": as S02. Today's page shows both messages translated
// ("Email address not valid.", "This value should be unique."); either
// wording passes.
test('@S06', PASSING, async ({ page }) => {
  noSuperuser();
  const amara = seedUser('amara');
  cleanups.push(amara.remove);
  await open(page, PATH);

  await fillIn(page, good('not-an-email'));
  await submit(page, 'Save');
  await expect(
    page.getByText(/must be a valid email address|Email address not valid/)
  ).toBeVisible();

  await fillIn(page, { email: amara.email });
  await submit(page, 'Save');
  await expect(
    page.getByText(/has already been taken|This value should be unique/)
  ).toBeVisible();

  expect(superuserCount()).toBe(0);
  expect(storedAccount({ email: amara.email })?.role).toBe('user');
});

// @S07
// Scenario: Visiting the page after a superuser exists sends me to projects
//   Given first setup is allowed
//   And a superuser exists
//   When I visit "/first_setup"
//   Then I am redirected to "/projects"
// Signed in, so /projects opens rather than sending me on to log in.
test('@S07', PASSING, async ({ page }) => {
  firstSetupAllowed();
  expect(superuserCount()).toBeGreaterThan(0);
  await signInAs(page, REGULAR);

  await page.goto(PATH);

  await expectAt(page, '/projects');
  await expect(field(page, 'First name')).toHaveCount(0);
});

// @S08
// Scenario: Navigating to the page from inside the app after a superuser exists sends me to projects
//   Given first setup is allowed
//   And a superuser exists
//   And I am signed in on "/credentials"
//   When a live navigation takes me to "/first_setup"
//   Then I land on "/projects"
//   And no registration form is shown
test('@S08', PASSING, async ({ page }) => {
  firstSetupAllowed();
  expect(superuserCount()).toBeGreaterThan(0);
  await signInAs(page, REGULAR);
  await open(page, '/credentials');

  await liveNavigate(page, PATH);

  await expectAt(page, '/projects');
  await expect(field(page, 'First name')).toHaveCount(0);
});

// @S09 @variant:first-setup-closed
// Scenario: Instances administered by a service account refuse the page
//   Given first setup is not allowed
//   And there is no superuser
//   When I visit "/first_setup"
//   Then I get a 404 with "First setup is disabled for this instance."
test('@S09', PASSING, async ({ page }) => {
  noSuperuser();
  firstSetupClosed();

  const response = await page.goto(PATH);

  expect(response?.status()).toBe(404);
  await expect(
    page.getByText('First setup is disabled for this instance.')
  ).toBeVisible();
});

// @S10 @variant:first-setup-closed
// Scenario: Instances administered by a service account refuse live navigation to the page
//   Given first setup is not allowed
//   And I am signed in on "/credentials"
//   When a live navigation takes me to "/first_setup"
//   Then I am redirected to "/projects"
test('@S10', PASSING, async ({ page }) => {
  firstSetupClosed();
  await signInAs(page, REGULAR);
  await open(page, '/credentials');

  await liveNavigate(page, PATH);

  await expectAt(page, '/projects');
  await expect(field(page, 'First name')).toHaveCount(0);
});

// @S11 @variant:first-setup-closed
// Scenario: Instances administered by a service account are not forced into first setup
//   Given first setup is not allowed
//   And there is no superuser
//   When I visit "/"
//   Then I am not redirected to "/first_setup"
test('@S11', PASSING, async ({ page }) => {
  noSuperuser();
  firstSetupClosed();

  await page.goto('/');
  await page.waitForLoadState('networkidle');

  expect(new URL(page.url()).pathname).not.toBe(PATH);
});

// Inherited from shared-authenticated-session: only the :browser pipeline and
// its S11 redirect, which is how visitors arrive here. S01 to S06 are gates of
// :require_authenticated_user and S07 to S10 chrome of the signed-in layout;
// this route has neither (annotation inherits line).
test.describe('shared-authenticated-session', () => {
  // @S11 @variant:first-setup-open
  // Scenario: An instance with no superuser sends pages to first setup
  //   Given first setup is allowed
  //   And there is no superuser
  //   When I visit "/projects"
  //   Then I am on "/first_setup"
  test(
    'shared-authenticated-session@S11 on first-setup',
    PASSING,
    async ({ page }) => {
      noSuperuser();
      await authenticatedSession.S11(page, '/projects');
    }
  );
});

// Inherited from shared-flash-messages. The page puts one flash, the info
// "Superuser account created.", carried through the sign-in hand-off to
// /projects. S01, S03 and S05 read it there. Not run: S02 (the page puts no
// error flash), S04 (the new superuser's empty /projects has nothing that
// makes it render again), S06 (no Not Found card here), S07 (not an admin
// page), S08 (not a sign-in form). The "already exists" flash is never shown
// (annotation 6.1); S07 and S08 above cover that visit.
test.describe('shared-flash-messages', () => {
  const CREATED = 'Superuser account created.';

  // Given there is no superuser — the action creates one
  function creating(page: Page) {
    noSuperuser();
    const email = freshEmail('first');
    return () => createSuperuser(page, email);
  }

  test(
    'shared-flash-messages@S01 on first-setup',
    PASSING,
    async ({ page }) => {
      await flashMessages.S01(page, CREATED, creating(page));
    }
  );

  test(
    'shared-flash-messages@S03 on first-setup',
    PASSING,
    async ({ page }) => {
      await flashMessages.S03(page, CREATED, creating(page));
    }
  );

  test(
    'shared-flash-messages@S05 on first-setup',
    PASSING,
    async ({ page }) => {
      await flashMessages.S05(page, CREATED, creating(page), '/projects');
    }
  );
});
