// Scenarios from annotations/views/admin-audit.md.
//
// Who's who: "I" and "Amara Diallo" are owner@openfn.org, made a superuser for
// each test (the role is put back afterwards). super@openfn.org is "another
// superuser" where one is needed. editor@openfn.org is the regular user. Every
// test starts with an empty audit trail and gets the instance's own events
// back afterwards.
import { expect, test, type Locator, type Page } from '@playwright/test';

import * as adminSpace from './shared/admin-space';
import * as authenticatedSession from './shared/authenticated-session';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import {
  exec,
  isolateAuditEvents,
  keepAccount,
  makeSuperuser,
  onNode,
  open,
  seedAuditEvent,
  seedProject,
  shortId,
  signInAs,
  sql,
  user,
  tagFor,
} from './steps';

const ME = 'owner@openfn.org';
const REGULAR = 'editor@openfn.org';
const PAGE = '/settings/audit';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME), makeSuperuser(ME), isolateAuditEvents()];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given I am a superuser, signed in and on "/settings/audit"
async function signedIn(page: Page, path = PAGE) {
  await signInAs(page, ME);
  await open(page, path);
}

// The UTC time `ago` milliseconds back, as "YYYY-MM-DD HH:MM:SS"
const utcAgo = (ago: number) =>
  new Date(Date.now() - ago).toISOString().slice(0, 19).replace('T', ' ');
const DAY = 24 * 3600 * 1000;

const nameOf = (email: string) =>
  sql<{ name: string }>(
    `select first_name || ' ' || last_name as name from users where id = '${user(email).id}'`
  )[0].name;

// The row of an event: the one with a cell reading exactly the event name
const eventRow = (page: Page, event: string) =>
  page
    .getByRole('row')
    .filter({ has: page.getByRole('cell', { name: event, exact: true }) });

// The row of whatever the audit event on subject `itemId` shows
const subjectRow = (page: Page, itemId: string) =>
  page.getByRole('row').filter({ hasText: shortId(itemId) });

// The recorded changes of one field: "<field> <old> -> <new>"
const changes = (page: Page) => page.getByRole('row').getByRole('listitem');
const change = (page: Page, field: string) =>
  changes(page).filter({ hasText: new RegExp(`^\\s*${field}(\\s|$)`) });

// Any icon or arrow glyph in the change: not tied to one icon class
const arrow = (item: Locator) =>
  item.locator('svg, [class*="arrow"], :text("→")');

// The change reads as just the field name and its value(s)
const reads = async (item: Locator, field: string, ...values: string[]) =>
  expect((await item.innerText()).trim().split(/\s+/)).toEqual([
    field,
    ...values,
  ]);

// Whether the text is painted with a line through it
const struck = (text: Locator) =>
  text.evaluate(el =>
    getComputedStyle(el).textDecorationLine.includes('line-through')
  );

// @S01
// Scenario: Audit events are listed newest first with actor and subject
//   Given I am a superuser
//   And "Amara Diallo" (amara@example.org) created credential "DHIS2 prod" yesterday
//   And "Amara Diallo" deleted that credential today
//   When I open "/settings/audit"
//   Then the table has columns "Occurred", "Event", "Actor" and "Subject"
//   And the first row has event "deleted" and the second has event "created"
//   And both rows show actor "Amara Diallo" with "amara@example.org" beneath
//   And both rows show subject "credential" with the first 8 characters of the credential id
test('@S01', { tag: '@passing-old' }, async ({ page }) => {
  const { itemId } = seedAuditEvent({
    event: 'created',
    actorId: user(ME).id,
    insertedAt: utcAgo(DAY),
  });
  seedAuditEvent({ event: 'deleted', itemId, actorId: user(ME).id });

  await signedIn(page);

  for (const name of ['Occurred', 'Event', 'Actor', 'Subject'])
    await expect(page.getByRole('columnheader', { name })).toBeVisible();
  await expect(
    page.getByRole('cell', { name: /^(created|deleted)$/ })
  ).toHaveText(['deleted', 'created']);
  for (const event of ['deleted', 'created']) {
    const row = eventRow(page, event);
    await expect(row).toContainText(nameOf(ME));
    await expect(row).toContainText(user(ME).email);
    await expect(row).toContainText('credential');
    await expect(row).toContainText(shortId(itemId));
  }
});

// @S02
// Scenario: An event by a deleted user still identifies the actor
//   Given "temp@example.org" deleted a credential
//   And the account "temp@example.org" has since been deleted
//   When I open "/settings/audit" as a superuser
//   Then that row shows actor "(User deleted)"
//   And beneath it the first 8 characters of the deleted user's id
test('@S02', { tag: '@passing-old' }, async ({ page }) => {
  // No user has this id: the account is gone
  const { itemId, actorId } = seedAuditEvent({ event: 'deleted' });

  await signedIn(page);

  const row = subjectRow(page, itemId);
  await expect(row).toContainText('(User deleted)');
  await expect(row).toContainText(shortId(actorId));
});

// @S03
// Scenario: Changes are shown field by field with old and new values
//   Given a project's "history_retention_period" was changed from 30 to 7 days
//   When I open "/settings/audit" as a superuser
//   Then under the "history_retention_period_updated" row I see "history_retention_period" with "30" struck through, an arrow, and "7"
test('@S03', { tag: '@passing-old' }, async ({ page }) => {
  seedAuditEvent({
    event: 'history_retention_period_updated',
    itemType: 'project',
    changes: {
      before: { history_retention_period: 30 },
      after: { history_retention_period: 7 },
    },
  });

  await signedIn(page);

  const item = change(page, 'history_retention_period');
  await expect(item).toHaveCount(1);
  const old = item.getByText('30', { exact: true });
  await expect(old).toBeVisible();
  expect(await struck(old)).toBe(true);
  await expect(arrow(item).first()).toBeVisible();
  const now = item.getByText('7', { exact: true });
  await expect(now).toBeVisible();
  expect(await struck(now)).toBe(false);
});

// @S04
// Scenario: Fields only on one side of a change are still listed, in name order
//   Given an event whose changes have before "bar" and "foo", and after "bar", "baz" and "foo"
//   When the event's changes are shown
//   Then fields appear in the order "bar", "baz", "foo"
//   And "baz" shows only its new value with no arrow
//   And a field present only before shows its old value struck through with an arrow to an empty value
test('@S04', { tag: '@passing-old' }, async ({ page }) => {
  seedAuditEvent({
    event: 'updated',
    changes: {
      before: { bar: 'b1', foo: 'f1' },
      after: { bar: 'b1', baz: 'z2', foo: 'f2' },
    },
  });
  // The older event: a field that was cleared
  seedAuditEvent({
    event: 'updated',
    changes: { before: { gone: 'g1' }, after: { other: 'o2' } },
    insertedAt: utcAgo(DAY),
  });

  await signedIn(page);

  const fields = (await changes(page).allInnerTexts()).map(
    text => text.trim().split(/\s/)[0]
  );
  expect(fields).toEqual(['bar', 'baz', 'foo', 'gone', 'other']);
  const baz = change(page, 'baz');
  await expect(baz).toContainText('z2');
  await reads(baz, 'baz', 'z2');
  await expect(arrow(baz)).toHaveCount(0);
  expect(await struck(baz.getByText('z2', { exact: true }))).toBe(false);
  const gone = change(page, 'gone');
  const goneOld = gone.getByText('g1', { exact: true });
  expect(await struck(goneOld)).toBe(true);
  await expect(arrow(gone).first()).toBeVisible();
});

// @S05
// Scenario: A created event shows only the new values
//   Given user "amara@example.org" was created by a superuser
//   When I open "/settings/audit" as a superuser
//   Then under the user "created" row each recorded field shows its value with no arrow and nothing struck through
test('@S05', { tag: '@passing-old' }, async ({ page }) => {
  const recorded = {
    email: 'amara@example.org',
    first_name: 'Amara',
    last_name: 'Diallo',
    role: 'user',
  };
  seedAuditEvent({
    event: 'created',
    itemType: 'user',
    changes: { before: null, after: recorded },
  });

  await signedIn(page);

  for (const [field, value] of Object.entries(recorded)) {
    const item = change(page, field);
    await expect(item).toHaveCount(1);
    const shown = item.getByText(value, { exact: true });
    await expect(shown).toBeVisible();
    expect(await struck(shown)).toBe(false);
    await reads(item, field, value);
    await expect(arrow(item)).toHaveCount(0);
  }
});

// @S06
// Scenario: Credential environment bodies are shown as encrypted values only
//   Given credential "DHIS2" was updated with environments "production" and "staging" and a body containing "s3cret-token"
//   When I open "/settings/audit" as a superuser
//   Then under that credential's "updated" row I see "body:production" and "body:staging", in that order, each followed by an encoded value
//   And I do not see "s3cret-token"
test('@S06', { tag: '@passing-old' }, async ({ page }) => {
  // Recorded by the credential audit writer itself, staging first
  onNode(`
    credential = Lightning.Repo.all(Lightning.Credentials.Credential) |> hd()
    bodies = [{"staging", %{"token" => "s3cret-token"}}, {"production", %{"token" => "s3cret-token"}}]
    {:ok, _} =
      Lightning.Credentials.Audit.user_initiated_event("updated", credential, %{}, bodies)
      |> Lightning.Credentials.Audit.save()
  `);

  await signedIn(page);

  const bodies = changes(page).filter({ hasText: /^\s*body:/ });
  await expect(bodies).toHaveCount(2);
  const [production, staging] = await bodies.allInnerTexts();
  expect(production).toMatch(/^body:production\s+[A-Za-z0-9+/=]{20,}$/);
  expect(staging).toMatch(/^body:staging\s+[A-Za-z0-9+/=]{20,}$/);
  await expect(page.getByText('s3cret-token')).toHaveCount(0);
  expect(await page.content()).not.toContain('s3cret-token');
});

// @S07
// Scenario: Webhook auth method secrets are shown encrypted
//   Given a webhook auth method with password "hunter22" and API key "k-123" was created
//   When I open "/settings/audit" as a superuser
//   Then the "webhook_auth_method" "created" row lists "password" and "api_key"
//   And I do not see "hunter22" or "k-123"
test('@S07', { tag: '@passing-old' }, async ({ page }) => {
  // Recorded by the webhook auth method audit writer itself
  onNode(`
    actor = Lightning.Repo.get_by!(Lightning.Accounts.User, email: "${ME}")
    {:ok, _} =
      Lightning.Workflows.WebhookAuthMethodAudit.event(
        "created",
        Ecto.UUID.generate(),
        actor,
        %{before: nil, after: %{password: "hunter22", api_key: "k-123"}}
      )
      |> Lightning.Workflows.WebhookAuthMethodAudit.save()
  `);

  await signedIn(page);

  await expect(eventRow(page, 'created')).toContainText('webhook_auth_method');
  for (const field of ['password', 'api_key']) {
    const item = change(page, field);
    await expect(item).toHaveCount(1);
  }
  for (const secret of ['hunter22', 'k-123']) {
    await expect(page.getByText(secret)).toHaveCount(0);
    expect(await page.content()).not.toContain(secret);
  }
});

// @S08
// Scenario Outline: Automated actors are labelled as the system that acted
//   Given an audit event whose actor is <actor>
//   When I open "/settings/audit" as a superuser
//   Then the actor column shows "<label>"
//   Examples:
//     | an existing GitHub repo connection | GitHub                            |
//     | a deleted GitHub repo connection   | (Project Repo Connection Deleted) |
//     | an existing cron trigger           | Cron                              |
//     | an existing webhook trigger        | Webhook                           |
//     | a deleted trigger                  | (Trigger Deleted)                 |
//     | a service account                  | Service account                   |
test('@S08', { tag: '@passing-old' }, async ({ page }) => {
  const project = seedProject(
    'audit-actors-project',
    {},
    {
      workflows: [{ updated_at: '2026-01-01 00:00:00' }],
    }
  );
  cleanups.push(project.remove);
  const [{ workflow }] = sql<{ workflow: string }>(
    `select id as workflow from workflows where project_id = '${project.id}'`
  );
  const [{ connection, cron, hook }] = sql<Record<string, string>>(
    `select gen_random_uuid() as connection, gen_random_uuid() as cron,
            gen_random_uuid() as hook`
  );
  exec(`insert into project_repo_connections
          (id, project_id, root_project_id, repo, branch, inserted_at, updated_at)
        values ('${connection}', '${project.id}', '${project.id}', 'repo', 'main', now(), now());
        insert into triggers (id, type, workflow_id, project_id, cron_expression, enabled, inserted_at, updated_at)
        values ('${cron}', 'cron', '${workflow}', '${project.id}', '0 * * * *', true, now(), now());
        insert into triggers (id, type, workflow_id, project_id, enabled, inserted_at, updated_at)
        values ('${hook}', 'webhook', '${workflow}', '${project.id}', true, now(), now())`);
  const [{ gone }] = sql<{ gone: string }>(`select gen_random_uuid() as gone`);

  const cases = [
    ['project_repo_connection', connection, 'GitHub'],
    ['project_repo_connection', gone, '(Project Repo Connection Deleted)'],
    ['trigger', cron, 'Cron'],
    ['trigger', hook, 'Webhook'],
    ['trigger', gone, '(Trigger Deleted)'],
    ['service_account', gone, 'Service account'],
  ] as const;
  const subjects = cases.map(([actorType, actorId]) =>
    seedAuditEvent({
      event: 'updated',
      actorType,
      actorId,
      metadata: { service_account_id: 'key-1234' },
    })
  );

  await signedIn(page);

  const headers = await page.getByRole('columnheader').allInnerTexts();
  const actorCol = headers.findIndex(h => h.includes('Actor'));
  expect(actorCol).toBeGreaterThanOrEqual(0);
  // What keeps the actor attributable under the label, where it is gone
  const ident: Record<number, string> = {
    1: shortId(gone),
    4: shortId(gone),
    5: 'key-1234',
  };
  for (const [i, [, , label]] of cases.entries()) {
    const row = subjectRow(page, subjects[i].itemId);
    const cell = row.getByRole('cell').nth(actorCol);
    await expect(cell).toContainText(label);
    if (ident[i]) await expect(cell).toContainText(ident[i]);
  }
});

// @S09
// Scenario: The history is paged ten events at a time
//   Given there are 25 audit events
//   When I open "/settings/audit" as a superuser
//   Then I see 10 events and "Showing 1 to 10 of 25 total results"
//   When I click page "3"
//   Then the URL has "page=3"
//   And I see 5 events and "Showing 21 to 25 of 25 total results"
test('@S09', { tag: '@passing-old' }, async ({ page }) => {
  for (let i = 0; i < 25; i++)
    seedAuditEvent({ event: 'snapshot_created', insertedAt: utcAgo(i * 1000) });
  const events = page.getByRole('cell', {
    name: 'snapshot_created',
    exact: true,
  });

  await signedIn(page);

  await expect(events).toHaveCount(10);
  await expect(page.getByText(/\b1\D+10\D+25\b/)).toBeVisible();

  await page.getByRole('link', { name: '3', exact: true }).click();

  await expect(page).toHaveURL(/[?&]page=3(&|$)/);
  await expect(events).toHaveCount(5);
  await expect(page.getByText(/\b21\D+25\D+25\b/)).toBeVisible();
});

// Inherited from shared-admin-space: the gate, and the settings layout and
// side menu with "Audit" current.
test.describe('shared-admin-space', () => {
  test(
    'shared-admin-space@S01 on admin-audit',
    { tag: '@passing-old' },
    async ({ page }) => {
      await adminSpace.S01(page, PAGE, ME, 'Audit');
    }
  );

  test(
    'shared-admin-space@S02 on admin-audit',
    { tag: '@passing-old' },
    async ({ page }) => {
      await adminSpace.S02(page, PAGE, REGULAR);
    }
  );

  test('shared-admin-space@S03 on admin-audit', { tag: '@pending' }, () => {
    test.skip(
      true,
      'needs a socket mount that skips the HTTP check, which no browser action produces; the page cannot be reached with a forged mount'
    );
  });

  for (const id of ['S04', 'S05'])
    test(
      `shared-admin-space@${id} on admin-audit`,
      { tag: tagFor(id, ['S01', 'S02', 'S06']) },
      () => {
        test.skip(
          true,
          'not reachable here: it is about "/dashboard"; the inherits line names only S01, S02, S03 and S06'
        );
      }
    );

  test(
    'shared-admin-space@S06 on admin-audit',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await adminSpace.S06(page, browser, PAGE, ME);
    }
  );

  test('shared-admin-space@S07 on admin-audit', { tag: '@pending' }, () => {
    test.skip(
      true,
      'variant settings-menu-extension is not configured on this instance'
    );
  });
});

// Inherited from shared-authenticated-session, on "/settings/audit".
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on admin-audit',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S01(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on admin-audit',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on admin-audit',
    { tag: '@passing-old' },
    async ({ page }) => {
      await authenticatedSession.S03(page, PAGE, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on admin-audit',
    { tag: '@passing-old' },
    async ({ page, browser }) => {
      // The admin menu has no "Credentials"; "Users" is a label it does have
      await authenticatedSession.S07(
        page,
        browser,
        PAGE,
        '/settings/users',
        ME,
        'Users'
      );
    }
  );

  for (const [id, variant] of [
    ['S04', 'require-email-verification'],
    ['S05', 'require-email-verification'],
    ['S06', 'require-email-verification'],
  ])
    test(
      `shared-authenticated-session@${id} on admin-audit`,
      { tag: tagFor(id, ['S01', 'S02', 'S03', 'S07']) },
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );

  for (const id of ['S08', 'S09', 'S10', 'S11'])
    test(
      `shared-authenticated-session@${id} on admin-audit`,
      { tag: tagFor(id, ['S01', 'S02', 'S03', 'S07']) },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line says S08 to S10 are not on the settings layout, and S11 is a first-setup redirect before any page'
        );
      }
    );
});

// Inherited from shared-flash-messages.
test.describe('shared-flash-messages', () => {
  test('shared-flash-messages@S07 on admin-audit', { tag: '@pending' }, () => {
    test.skip(
      true,
      'no action on this page or on a page that lands on it puts a flash ("this view sets no flash of its own"), so there is no toast to click'
    );
  });

  for (const id of ['S01', 'S02', 'S03', 'S04', 'S05', 'S06', 'S08'])
    test(
      `shared-flash-messages@${id} on admin-audit`,
      { tag: '@pending' },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line names only S07 for the settings layout'
        );
      }
    );
});

// Inherited from shared-project-header: the global picker, the confirmation
// banner and the account menu (no-project parts).
test.describe('shared-project-header', () => {
  for (const id of ['S04', 'S06', 'S08', 'S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on admin-audit`,
      {
        tag: tagFor(id, [
          'S04',
          'S06',
          'S08',
          'S11',
          'S12',
          'S13',
          'S18',
          'S10',
        ]),
      },
      async ({ page }) => {
        await projectHeader[id](page, PAGE, ME);
      }
    );

  // The Examples row "the projects list or my profile | the workflows page"
  test(
    'shared-project-header@S10 on admin-audit',
    { tag: '@passing-old' },
    async ({ page }) => {
      await projectHeader.S10(page, PAGE, ME, '/w');
    }
  );

  test('shared-project-header@S14 on admin-audit', { tag: '@pending' }, () => {
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
      `shared-project-header@${id} on admin-audit`,
      {
        tag: tagFor(id, [
          'S04',
          'S06',
          'S08',
          'S11',
          'S12',
          'S13',
          'S18',
          'S10',
        ]),
      },
      () => {
        test.skip(
          true,
          'not reachable here: the inherits line takes only the no-project parts (S04, S06, S08, S10 to S14, S18)'
        );
      }
    );
});

// Inherited from shared-local-datetime: the "Occurred" column.
test.describe('shared-local-datetime', () => {
  // Given an audit event was recorded at <utc>, and today is <today>
  async function occurred(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    seedAuditEvent({ event: 'updated', insertedAt: utc });
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, PAGE);
    return page.getByRole('row').getByRole('cell').first();
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on admin-audit',
      { tag: '@passing-old' },
      async ({ page }) => {
        await localDatetime.S01(
          page,
          await occurred(page, localDatetime.given.S01)
        );
      }
    );
  });

  for (const id of ['S02', 'S04', 'S05'] as const)
    test(
      `shared-local-datetime@${id} on admin-audit`,
      { tag: tagFor(id, ['S01', 'S02', 'S04', 'S05']) },
      async ({ page }) => {
        await localDatetime[id](
          page,
          await occurred(page, localDatetime.given[id])
        );
      }
    );

  for (const [id, why] of [
    [
      'S03',
      '"Occurred" always uses the default format, never relative_detailed',
    ],
    ['S06', 'audit_events.inserted_at is stored to the whole second'],
    ['S07', 'every audit event has an inserted_at'],
  ])
    test(
      `shared-local-datetime@${id} on admin-audit`,
      { tag: tagFor(id, ['S01', 'S02', 'S04', 'S05']) },
      () => {
        test.skip(
          true,
          `not reachable here: ${why}; the inherits line takes S01 to S05`
        );
      }
    );
});
