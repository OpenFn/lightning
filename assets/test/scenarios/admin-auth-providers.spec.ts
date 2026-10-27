// Scenarios from annotations/views/admin-auth-providers.md.
//
// Who's who: "I" am owner@openfn.org, made a superuser for each test (the
// role is put back afterwards). editor@openfn.org is the regular user.
//
// The instance has one SSO provider at most, so every page scenario is
// @serial: it checks that no provider is stored, and removes what it stored
// afterwards. A stand-in provider on this machine (standInProvider in
// steps.ts) serves the discovery documents and the sign-in page. The e2e
// instance runs the insecure-loopback variant, so http to 127.0.0.1 is
// accepted; S07 switches that off to read the default.
import { expect, test, type Page } from '@playwright/test';

import { sendSave, type ProviderValues } from './pages/admin-auth-providers';
import * as adminSpace from './shared/admin-space';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import {
  authProviders,
  expectAt,
  field,
  fieldBlock,
  keepAccount,
  makeSuperuser,
  open,
  removeAuthProviders,
  seedAuthProvider,
  signInAs,
  ssoStart,
  standInProvider,
  submit,
  submitButton,
  tagFor,
  watchLiveView,
  withFlag,
  type StandInProvider,
} from './steps';

const ME = 'owner@openfn.org';
const REGULAR = 'editor@openfn.org';
const PAGE = '/settings/authentication';
const NEW = '/settings/authentication/new';
const NAME = 'acme-idp';

let cleanups: (() => unknown)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), makeSuperuser(ME)];
});
test.afterEach(async () => {
  for (const cleanup of cleanups.reverse()) await cleanup();
});

// Given no SSO provider is configured, and the stand-in provider is up.
// An instance that already has a provider fails here rather than lose it.
async function noProviderYet() {
  expect(authProviders(), 'no SSO provider on the instance').toEqual([]);
  cleanups.push(() => removeAuthProviders([NAME]));
  const idp = await standInProvider();
  cleanups.push(idp.close);
  return idp;
}

// Given provider "acme-idp" is configured with client ID <clientId>, and its
// discovery document works
function providerConfigured(idp: StandInProvider, clientId = 'id') {
  seedAuthProvider({
    name: NAME,
    discoveryUrl: idp.discovery('good'),
    clientId,
    clientSecret: 'client-secret',
    redirectUri: `https://old.example.org/authenticate/${NAME}/callback`,
  });
}

// Given I am a superuser on <path>
async function signedIn(page: Page, path = NEW) {
  await signInAs(page, ME);
  await open(page, path);
}

const LABELS: [string, keyof ProviderValues][] = [
  ['Name', 'name'],
  ['Discovery URL', 'discoveryUrl'],
  ['Client ID', 'clientId'],
  ['Client Secret', 'clientSecret'],
  ['Redirect Host', 'redirectHost'],
];

// A form that could be saved: discovery from the stand-in provider
const validValues = (idp: StandInProvider): ProviderValues => ({
  name: NAME,
  discoveryUrl: idp.discovery('good'),
  clientId: 'client-id',
  clientSecret: 'client-secret',
  redirectHost: 'https://lightning.example.org',
});

// When I fill in <values>, field by field. An empty value is typed and then
// cleared, as a user leaves a field blank; filling an empty box with nothing
// doesn't count as touching it, so today's form shows no message for it.
async function fillIn(page: Page, values: Partial<ProviderValues>) {
  for (const [label, key] of LABELS) {
    const value = values[key];
    if (value === undefined) continue;
    if (value === '') await field(page, label).fill('x');
    await field(page, label).fill(value);
  }
}

// When I fill in a valid provider and the form has checked it
async function fillValid(page: Page, values: ProviderValues) {
  await fillIn(page, values);
  await expect(submitButton(page, 'Save')).toBeEnabled();
}

const testButton = (page: Page, state: 'Test' | 'Success' | 'Failed') =>
  page.getByRole('button', { name: state, exact: true });

const trustSwitch = (page: Page) =>
  page.getByRole('checkbox', {
    name: 'Trust unverified emails from this provider',
  });

// @S01
// Scenario: With no provider, the page opens an empty provider form
//   Given I am a superuser
//   And no authentication provider is configured
//   When I visit "/settings/authentication"
//   Then I am on "/settings/authentication/new"
//   And I see empty "Name", "Discovery URL", "Client ID" and "Client Secret" fields
//   And I do not see a "Remove" button
test(
  '@S01',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    await noProviderYet();

    await signedIn(page, PAGE);

    await expectAt(page, NEW);
    for (const label of ['Name', 'Discovery URL', 'Client ID', 'Client Secret'])
      await expect(field(page, label)).toHaveValue('');
    await expect(page.getByRole('button', { name: 'Remove' })).toHaveCount(0);
  }
);

// @S02
// Scenario: A superuser creates a provider
//   Given I am a superuser on "/settings/authentication/new"
//   When I fill in name "acme-idp", a discovery URL, client ID "client-id" and client secret "client-secret"
//   And I click "Save"
//   Then I see "Authentication Provider created."
//   And I am on "/settings/authentication"
//   And the form shows provider "acme-idp"
//   And a "Remove" button is shown
test(
  '@S02',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const idp = await noProviderYet();
    await signedIn(page);

    const values = validValues(idp);
    await fillValid(page, values);
    await submit(page, 'Save');

    await expect(
      page.getByText('Authentication Provider created.')
    ).toBeVisible();
    await expectAt(page, PAGE);
    await expect(field(page, 'Name')).toHaveValue(NAME);
    await expect(page.getByRole('button', { name: 'Remove' })).toBeVisible();
    expect(authProviders()).toMatchObject([
      {
        name: NAME,
        discovery_url: values.discoveryUrl,
        client_id: 'client-id',
      },
    ]);
  }
);

// @S03
// Scenario: The redirect URI to register is shown as the form is filled
//   Given I am a superuser on "/settings/authentication/new"
//   While the form is incomplete
//   Then the "Redirect URI" box shows the redirect host followed by "…" and is greyed out
//   When I fill in every required field with name "acme-idp" and redirect host "https://lightning.example.org"
//   Then the "Redirect URI" box shows "https://lightning.example.org/authenticate/acme-idp/callback"
// "Greyed out" is how the box says it isn't final; the "…" says the same.
test(
  '@S03',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const idp = await noProviderYet();
    await signedIn(page);

    const host = await field(page, 'Redirect Host').inputValue();
    await expect(page.getByText(`${host}…`, { exact: true })).toBeVisible();

    await fillValid(page, validValues(idp));

    await expect(
      page.getByText(
        'https://lightning.example.org/authenticate/acme-idp/callback',
        { exact: true }
      )
    ).toBeVisible();
  }
);

// @S04
// Scenario Outline: An incomplete or malformed provider can't be saved
//   Given I am a superuser on "/settings/authentication/new"
//   When I enter <input>
//   Then I see "<error>" under the <field> field
//   And the "Save" button is disabled
//   Examples:
//     | input                  | field         | error                                                                            |
//     | an empty name          | Name          | can't be blank                                                                   |
//     | name "Acme IdP"        | Name          | must be lower-case and only contain alphanumeric, dash and underscore characters |
//     | discovery URL "acme"   | Discovery URL | must be a valid HTTP/s URL                                                       |
//     | an empty client secret | Client Secret | can't be blank                                                                   |
// The Value is that nothing is stored, so the test presses Save (today's page
// turns it off, the port checks on press) and then sends each save past the
// form, and checks the database. The URL message may be either wording:
// today's page shows the translation of "must be a valid HTTP/s URL", the
// port shows it untranslated.
test('@S04', { tag: ['@passing-new', '@serial'] }, async ({ page }) => {
  const idp = await noProviderYet();
  const examples: [Partial<ProviderValues>, string, string | RegExp][] = [
    [{ name: '' }, 'Name', "can't be blank"],
    [
      { name: 'Acme IdP' },
      'Name',
      'must be lower-case and only contain alphanumeric, dash and underscore characters',
    ],
    [
      { discoveryUrl: 'acme' },
      'Discovery URL',
      /The HTTP\/s URL provided is not valid\.|must be a valid HTTP\/s URL/,
    ],
    [{ clientSecret: '' }, 'Client Secret', "can't be blank"],
  ];
  await signInAs(page, ME);

  for (const [input, label, error] of examples) {
    const lv = watchLiveView(page);
    await open(page, NEW);
    const values = { ...validValues(idp), ...input };

    await fillIn(page, values);
    await submit(page, 'Save');

    await expect(fieldBlock(page, label)).toContainText(error);
    expect(authProviders(), `${label}: ${error}`).toEqual([]);

    await sendSave(page, lv, values);
    // Soft, and anything stored is removed, so every example is read
    expect
      .soft(authProviders(), `sent past the form: ${label}: ${error}`)
      .toEqual([]);
    removeAuthProviders();
    expect(lv.crashes()).toBe(0);
  }
});

// @S05
// Scenario: Testing a working discovery URL passes
//   Given I am a superuser with a valid provider form
//   And the discovery URL serves a document with authorization and token endpoints
//   When I click "Test"
//   Then the button shows "Success"
//   When I change any field
//   Then the button shows "Test" again
test(
  '@S05',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const idp = await noProviderYet();
    await signedIn(page);
    await fillValid(page, validValues(idp));

    await testButton(page, 'Test').click();

    await expect(testButton(page, 'Success')).toBeVisible();

    await field(page, 'Client ID').fill('another-client-id');

    await expect(testButton(page, 'Test')).toBeVisible();
    await expect(testButton(page, 'Success')).toHaveCount(0);
  }
);

// @S06
// Scenario Outline: Testing a broken discovery URL says why it failed
//   Given I am a superuser with a valid provider form
//   And the discovery URL <problem>
//   When I click "Test"
//   Then I see the error "<message>"
//   And the button shows "Failed"
//   And I see "<message>" under the Discovery URL field
//   Examples:
//     | problem                                     | message                                                                  |
//     | returns a body that is not JSON             | error parsing .well-known                                                |
//     | refuses the connection                      | could not connect to discovery endpoint                                  |
//     | returns JSON with no authorization endpoint | Provider expects a WellKnown struct with a 'authorization_endpoint' key. |
// Today the message also comes as a toast; under the field is where both
// versions say it.
test(
  '@S06',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const idp = await noProviderYet();
    const examples: [string, string][] = [
      [idp.discovery('not-json'), 'error parsing .well-known'],
      [idp.refused, 'could not connect to discovery endpoint'],
      [
        idp.discovery('no-authorization'),
        "Provider expects a WellKnown struct with a 'authorization_endpoint' key.",
      ],
    ];
    await signInAs(page, ME);

    for (const [discoveryUrl, message] of examples) {
      await open(page, NEW);
      await fillValid(page, { ...validValues(idp), discoveryUrl });

      await testButton(page, 'Test').click();

      await expect(testButton(page, 'Failed')).toBeVisible();
      await expect(fieldBlock(page, 'Discovery URL')).toContainText(message);
    }
  }
);

// @S07
// Scenario: A plaintext discovery URL never passes the test
//   Given I am a superuser with a valid provider form
//   And the discovery URL is "http://idp.example.org/.well-known/openid-configuration"
//   When I click "Test"
//   Then I see the error "discovery endpoint must use https"
//   And no request is made to that URL
// Read under the default variant: http to this machine is refused too, so the
// stand-in provider can tell whether it was asked.
test(
  '@S07',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const idp = await noProviderYet();
    cleanups.push(withFlag('auth_providers_allow_insecure_loopback', false));
    await signedIn(page);
    await fillValid(page, validValues(idp));

    await testButton(page, 'Test').click();

    await expect(fieldBlock(page, 'Discovery URL')).toContainText(
      'discovery endpoint must use https'
    );
    await expect(testButton(page, 'Failed')).toBeVisible();
    expect(idp.requests).toEqual([]);
  }
);

// @S08
// Scenario: Editing the provider takes effect for sign-ins
//   Given provider "acme-idp" is configured with client ID "id"
//   And I am a superuser on "/settings/authentication"
//   Then the form shows the stored values and a redirect host taken from the stored redirect URI
//   When I change the client ID to "new-client-id" and the redirect host to "http://localhost:3030"
//   And I click "Save"
//   Then I see "Authentication Provider updated."
//   And the "Redirect URI" box shows "http://localhost:3030/authenticate/acme-idp/callback"
//   And sign-ins handled by this node in flow "flow-sso-login" use client ID "new-client-id" and that redirect URI
// The secret is left alone: the port no longer shows it, and keeps it when
// the field is blank.
test(
  '@S08',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, request }) => {
    const idp = await noProviderYet();
    providerConfigured(idp, 'id');
    await signedIn(page, PAGE);

    await expect(field(page, 'Name')).toHaveValue(NAME);
    await expect(field(page, 'Discovery URL')).toHaveValue(
      idp.discovery('good')
    );
    await expect(field(page, 'Client ID')).toHaveValue('id');
    await expect(field(page, 'Redirect Host')).toHaveValue(
      /^https:\/\/old\.example\.org\/?$/
    );

    await fillIn(page, {
      clientId: 'new-client-id',
      redirectHost: 'http://localhost:3030',
    });
    await submit(page, 'Save');

    await expect(
      page.getByText('Authentication Provider updated.')
    ).toBeVisible();
    const callback = `http://localhost:3030/authenticate/${NAME}/callback`;
    await expect(page.getByText(callback, { exact: true })).toBeVisible();

    const start = (await ssoStart(request, NAME)) ?? '';
    expect(start, 'sign-in starts at the provider').toContain(
      `${idp.authorizeUrl}?`
    );
    const params = new URL(start).searchParams;
    expect(params.get('client_id')).toBe('new-client-id');
    expect(params.get('redirect_uri')).toBe(callback);
  }
);

// @S09
// Scenario: Unverified provider emails are not trusted unless an admin turns it on
//   Given I am a superuser on "/settings/authentication/new"
//   Then "Trust unverified emails from this provider" is unchecked
//   And I see "Only enable for a provider you trust that doesn't assert email_verified. Off by default."
//   When I check it and save the provider
//   Then the stored provider trusts unverified emails
//   And flow "flow-sso-login" applies its trusted-provider rule (its S11) to sign-ins through it
// The flow's rule is flow-sso-login's S11; here, the stored setting.
test(
  '@S09',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page }) => {
    const idp = await noProviderYet();
    await signedIn(page);

    await expect(trustSwitch(page)).not.toBeChecked();
    await expect(
      page.getByText(
        /Only enable for a provider you trust that doesn't assert\s*email_verified\s*\.\s*Off by default\./
      )
    ).toBeVisible();

    await fillValid(page, validValues(idp));
    await trustSwitch(page).check();
    await submit(page, 'Save');

    await expect(
      page.getByText('Authentication Provider created.')
    ).toBeVisible();
    expect(authProviders()).toMatchObject([
      { name: NAME, allow_unverified_email: true },
    ]);
  }
);

// @S10
// Scenario: Removing the provider turns off SSO
//   Given provider "acme-idp" is configured
//   And I am a superuser on "/settings/authentication"
//   When I click "Remove"
//   Then I see "Authentication Provider removed"
//   And I am on "/settings/authentication/new"
//   And no provider is stored
//   And flow "flow-sso-login" can no longer start through "acme-idp" on this node
test(
  '@S10',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, request }) => {
    const idp = await noProviderYet();
    providerConfigured(idp);
    // Sign-in starts through it now, so the node has it cached
    expect(await ssoStart(request, NAME)).toContain(`${idp.authorizeUrl}?`);
    await signedIn(page, PAGE);

    await page.getByRole('button', { name: 'Remove' }).click();

    await expect(
      page.getByText('Authentication Provider removed')
    ).toBeVisible();
    await expectAt(page, NEW);
    expect(authProviders()).toEqual([]);
    expect((await ssoStart(request, NAME)) ?? '').not.toContain(
      idp.authorizeUrl
    );
  }
);

// Inherited from shared-admin-space: the gate, and the settings layout and
// side menu with "Authentication" current. The menu links to the blank form,
// which is where the page is with no provider.
test.describe('shared-admin-space', () => {
  test(
    'shared-admin-space@S01 on admin-auth-providers',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S01(page, NEW, ME, 'Authentication');
    }
  );

  test(
    'shared-admin-space@S02 on admin-auth-providers',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await adminSpace.S02(page, PAGE, REGULAR);
    }
  );

  test(
    'shared-admin-space@S03 on admin-auth-providers',
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
      `shared-admin-space@${id} on admin-auth-providers`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: it is about "/dashboard"; the inherits line names only S01, S02, S03 and S06'
        );
      }
    );

  test(
    'shared-admin-space@S06 on admin-auth-providers',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await adminSpace.S06(page, browser, NEW, ME);
    }
  );

  test(
    'shared-admin-space@S07 on admin-auth-providers',
    { tag: '@pending' },
    () => {
      test.skip(
        true,
        'variant settings-menu-extension is not configured on this instance'
      );
    }
  );
});

// Inherited from shared-authenticated-session, on the blank form: with no
// provider, "/settings/authentication" moves itself there.
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on admin-auth-providers',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S01(page, NEW, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on admin-auth-providers',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, NEW, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on admin-auth-providers',
    { tag: ['@passing-old', '@passing-new'] },
    async ({ page }) => {
      await authenticatedSession.S03(page, NEW, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on admin-auth-providers',
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
      `shared-authenticated-session@${id} on admin-auth-providers`,
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
      `shared-authenticated-session@${id} on admin-auth-providers`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(
          true,
          'not reachable here: S08 to S10 are not on the settings layout, and S11 is a first-setup redirect before any page'
        );
      }
    );
});

// Inherited from shared-flash-messages: the inherits line takes S07, the
// settings layout's toast that stays until clicked. Saving an edit puts it.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S07 on admin-auth-providers',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const idp = await noProviderYet();
      providerConfigured(idp);
      await flashMessages.S07(
        page,
        'Authentication Provider updated.',
        async () => {
          await signedIn(page, PAGE);
          await fillIn(page, { clientId: 'new-client-id' });
          await submit(page, 'Save');
        }
      );
    }
  );

  for (const [id, why] of [
    ['S01', 'it is about the live layout; the settings layout toast is S07'],
    ['S02', 'it is about the live layout; the settings layout toast is S07'],
    ['S03', 'it is about the live layout; the settings layout toast is S07'],
    ['S04', 'it is about the live layout; the settings layout toast is S07'],
    ['S05', 'the inherits line takes only S07'],
    ['S06', 'the inherits line takes only S07'],
    ['S08', 'it is about the sign-in and account forms'],
  ])
    test(
      `shared-flash-messages@${id} on admin-auth-providers`,
      { tag: tagFor(id, []) },
      () => {
        test.skip(true, `not reachable here: ${why}`);
      }
    );
});
