// Steps shared by annotation scenarios. They drive the real pages and read and
// seed the e2e database that the verify-lightning instance runs on.
//
// TARGET=demo runs the same specs against the openfn-ia-demo replica instead:
// hash routes, one fixed signed-in user, static fixtures and no server. A
// step it can't honour skips the test and says why.
import { execFileSync } from 'node:child_process';
import { createHmac } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';

import {
  expect,
  test,
  type APIRequestContext,
  type Browser,
  type Locator,
  type Page,
} from '@playwright/test';

import { forWorker, WORKER, workerManifest } from './workers';

const onDemo = process.env.TARGET === 'demo';

/** Skips the running test on the demo, which has no database or server. */
function lightningOnly(reason: string) {
  if (!onDemo) return;
  console.log(`skipped on demo: ${reason}`);
  test.skip(true, reason);
}

const MANIFEST = process.env.LIGHTNING_MANIFEST || workerManifest(WORKER);
const DB =
  process.env.LIGHTNING_DB ||
  'postgres://postgres:postgres@localhost/lightning_test_e2e';
const PSQL =
  ['/opt/homebrew/opt/libpq/bin/psql', '/usr/local/opt/libpq/bin/psql'].find(
    existsSync
  ) || 'psql';

export const PASSWORD = 'welcome12345';

type ManifestUser = {
  id: string;
  email: string;
  superuser: boolean;
  api_token: string | null;
};

export function manifest() {
  return JSON.parse(readFileSync(MANIFEST, 'utf8')) as {
    users: ManifestUser[];
    projects: { id: string; name: string }[];
  };
}

export function user(email: string): ManifestUser {
  const found = manifest().users.find(u => u.email === forWorker(email));
  if (!found) throw new Error(`${forWorker(email)} is not in the manifest`);
  return found;
}

/** Runs a query and returns its rows. Values must not come from user input. */
export function sql<T = Record<string, unknown>>(query: string): T[] {
  lightningOnly('needs the database');
  const out = execFileSync(
    PSQL,
    [
      DB,
      '-AtX',
      '-v',
      'ON_ERROR_STOP=1',
      '-c',
      `select coalesce(json_agg(t), '[]') from (${query}) t`,
    ],
    { encoding: 'utf8' }
  );
  return JSON.parse(out) as T[];
}

/** Runs a statement that changes the database (Given steps only). */
export function exec(statement: string) {
  lightningOnly('needs the database');
  execFileSync(PSQL, [DB, '-AtX', '-v', 'ON_ERROR_STOP=1', '-c', statement], {
    encoding: 'utf8',
  });
}

// Given I am signed in as "<email>"
export async function signInAs(page: Page, email: string, password = PASSWORD) {
  if (onDemo) return; // the demo is always signed in as its one user
  await page.goto('/users/log_in');
  // The login inputs have no accessible name (their labels aren't linked), so
  // they can only be found by field name.
  await page.locator('input[name="user[email]"]').fill(forWorker(email));
  await page.locator('input[name="user[password]"]').fill(password);
  await page.getByRole('button', { name: 'Log in' }).click();
  await expect(page).not.toHaveURL(/\/users\/log_in/);
}

// When I open "<path>" — waits for the LiveView socket to join
export async function open(page: Page, path: string) {
  if (onDemo) return void (await page.goto(`#${path}`));
  await page.goto(path);
  await page.locator('.phx-connected').first().waitFor();
}

// When I reload the page
export async function reload(page: Page) {
  lightningOnly('needs a reload that keeps state: demo tokens live in memory');
  await page.reload();
  await page.locator('.phx-connected').first().waitFor();
}

// Then I am on "<path>"
export async function expectAt(page: Page, path: string | RegExp) {
  const at = () => {
    const url = new URL(page.url());
    return onDemo ? url.hash.slice(1) : url.pathname;
  };
  if (typeof path === 'string') await expect.poll(at).toBe(path);
  else await expect.poll(at).toMatch(path);
}

export type ApiToken = {
  id: string;
  token: string;
  inserted_at: string;
  last_used_at: string | null;
};

export function apiTokensOf(email: string): ApiToken[] {
  lightningOnly('needs the database: user_tokens');
  return sql<ApiToken>(
    `select id, convert_from(token, 'UTF8') as token, inserted_at, last_used_at
     from user_tokens where context = 'api' and user_id = '${user(email).id}'
     order by inserted_at desc`
  );
}

// Given "<email>" has no API tokens
export function removeApiTokensOf(email: string) {
  lightningOnly('needs seeded state: no API tokens');
  exec(
    `delete from user_tokens where context = 'api' and user_id = '${user(email).id}'`
  );
}

// Given "<email>" has an API token
export function seededApiTokenOf(email: string) {
  lightningOnly("needs seeded state: another user's API token");
  const [token] = apiTokensOf(email);
  expect(token, `${email} should have the seeded API token`).toBeTruthy();
  return token;
}

// Given my token was created at <inserted_at> and last used at <last_used_at>
// (UTC, "YYYY-MM-DD HH:MM:SS")
export function setApiTokenTimes(
  token: string,
  times: { inserted_at?: string; last_used_at?: string }
) {
  lightningOnly('needs seeded state: token created and last-used times');
  const set = Object.entries(times).map(
    ([column, at]) => `${column} = '${at}'`
  );
  exec(
    `update user_tokens set ${set.join(', ')}
     where context = 'api' and convert_from(token, 'UTF8') = '${token}'`
  );
}

// When a delete is submitted from the open deletion modal naming token <id>.
// The modal's "Yes" sends whatever phx-value-id it carries; repoint it.
export async function confirmDeletionNaming(page: Page, id: string) {
  lightningOnly('needs a server: a forged delete has nothing to reach');
  const yes = page.getByRole('button', { name: 'Yes' });
  await yes.evaluate((el, id) => el.setAttribute('phx-value-id', id), id);
  await yes.click();
}

const passwordHashOf = (email: string) =>
  sql<{ hashed_password: string }>(
    `select hashed_password from users where id = '${user(email).id}'`
  )[0].hashed_password;

// Captures "<email>"'s password now; the returned function puts it back.
export function keepPassword(email: string) {
  lightningOnly('needs the database: a password change');
  const hash = passwordHashOf(email);
  return () =>
    exec(
      `update users set hashed_password = '${hash}' where id = '${user(email).id}'`
    );
}

// When I change my password on "/profile" — ends signed in with the new one
export async function changePassword(
  page: Page,
  email: string,
  current: string,
  next: string
) {
  const before = passwordHashOf(email);
  await open(page, '/profile');
  const form = page.locator('#password-form');
  // Same unlinked labels as the login form.
  await form.locator('input[name="user[password]"]').fill(next);
  await form.locator('input[name="user[password_confirmation]"]').fill(next);
  await form.locator('input[name="user[current_password]"]').fill(current);
  await form.getByRole('button', { name: 'Update password' }).click();
  await expect.poll(() => passwordHashOf(email)).not.toBe(before);
  // The change disconnects the user's sockets before the page's redirect
  // arrives, so the browser is signed out. Sign back in with the new password.
  await page.context().clearCookies();
  await signInAs(page, email, next);
}

/** The 6-digit TOTP code an authenticator app would show (RFC 6238, SHA-1, 30s). */
export function totpCode(base32Secret: string, at = Date.now()) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bits = [...base32Secret.replace(/=+$/, '')]
    .map(c => alphabet.indexOf(c).toString(2).padStart(5, '0'))
    .join('');
  const key = Buffer.from(bits.match(/.{8}/g)!.map(byte => parseInt(byte, 2)));
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(at / 30000)));
  const hmac = createHmac('sha1', key).update(counter).digest();
  const offset = hmac[19] & 0xf;
  return ((hmac.readUInt32BE(offset) & 0x7fffffff) % 1_000_000)
    .toString()
    .padStart(6, '0');
}

// Given "<email>" has not enrolled in MFA
export function removeMfaOf(email: string) {
  const { id } = user(email);
  exec(`delete from user_totps where user_id = '${id}';
        delete from user_backup_codes where user_id = '${id}';
        update users set mfa_enabled = false where id = '${id}'`);
}

// Given "<email>" has enrolled in MFA — seeded straight into the database, so
// the profile enrolment UI is not part of the test. Undone by removeMfaOf.
export function seedMfaFor(email: string) {
  const { id } = user(email);
  exec(`insert into user_totps (id, user_id, secret, inserted_at, updated_at)
        values (gen_random_uuid(), '${id}', decode(repeat('ab', 20), 'hex'), now(), now());
        update users set mfa_enabled = true where id = '${id}'`);
}

// When I confirm MFA setup on "/profile" — the signed-in user must not have
// MFA yet. Reads the secret from the "this secret key" dialog, as a user
// typing it into an authenticator app would.
export async function enrolInMfa(page: Page) {
  await open(page, '/profile');
  await page.locator('#toggle-mfa-switch').click();
  await page.getByText('this secret key').click();
  const secret = (
    await page.locator('#mfa-secret-modal-content code').innerText()
  ).trim();
  // Escape is unreliable here: pressed during the open transition, the dialog
  // stays up and blocks the form.
  await page
    .locator('#mfa-secret-modal')
    .getByRole('button', { name: 'Close' })
    .click();
  await expect(page.locator('#mfa-secret-modal-container')).toBeHidden();
  await page
    .locator('#set_totp_form input[name="user_totp[code]"]')
    .fill(totpCode(secret));
  await page
    .locator('#set_totp_form')
    .getByRole('button', { name: 'Save' })
    .click();
  return secret;
}

// Given the session holds no sudo token that is mine and under five minutes old
export function expireSudoOf(email: string) {
  exec(
    `update user_tokens set inserted_at = now() at time zone 'utc' - interval '6 minutes'
     where context = 'sudo_session' and user_id = '${user(email).id}'`
  );
}

// When I re-authenticate with my password on "/auth/confirm_access"
export async function reauthenticateWithPassword(
  page: Page,
  password = PASSWORD
) {
  await expect(page).toHaveURL(/\/auth\/confirm_access/);
  await page
    .locator('#reauthentication-form input[name="user[password]"]')
    .fill(password);
  await page.getByRole('button', { name: 'Confirm' }).click();
  await expect(page).not.toHaveURL(/\/auth\/confirm_access/);
}

// When a request to "<path>" is sent with "Authorization: Bearer <token>"
export function getWithBearer(
  request: APIRequestContext,
  path: string,
  token: string
) {
  lightningOnly('needs a server: the API');
  return request.get(path, {
    headers: { Authorization: `Bearer ${token}` },
  });
}

// The form control a visible label names. Lightning's form labels carry
// `for` but the inputs have no id, so the label isn't linked and getByLabel
// finds nothing; the control is the next one after its label.
// `within` narrows the search to a dialog or form when a label repeats.
export function field(within: Page | Locator, label: string) {
  return labelled(within, label).locator(
    'xpath=following::*[self::select or self::textarea or self::input[not(@type="hidden")]][1]'
  );
}

// The block holding a field's label, control and any error under it
export function fieldBlock(within: Page | Locator, label: string) {
  return labelled(within, label).locator('xpath=..');
}

const labelled = (within: Page | Locator, label: string) =>
  within
    .locator('label')
    .filter({ hasText: new RegExp(`^\\s*${label}\\s*\\*?\\s*$`) });

const literal = (v: string | boolean | null) =>
  v === null ? 'null' : `$v$${String(v)}$v$`;

// Captures "<email>"'s name, email, contact preference, password, sidebar
// preference, sign-up time, disabled flag and MFA state; the returned
// function puts them back and drops any pending email change.
export function keepAccount(email: string) {
  if (onDemo) return () => {};
  const { id } = user(email);
  const columns = [
    'first_name',
    'last_name',
    'email',
    'contact_preference',
    'hashed_password',
    'preferences::text',
    'inserted_at',
    'disabled',
  ];
  const [row] = sql<Record<string, string | boolean | null>>(
    `select ${columns.join(', ')} from users where id = '${id}'`
  );
  return () => {
    const set = columns.map(c => {
      const name = c.replace('::text', '');
      return `${name} = ${literal(row[name])}`;
    });
    exec(`update users set ${set.join(', ')} where id = '${id}';
          delete from user_tokens where user_id = '${id}' and context like 'change:%'`);
    removeMfaOf(email);
  };
}

// Another browser, signed in as "<email>", sharing nothing with the test's
export async function otherSession(
  browser: Browser,
  email: string,
  password = PASSWORD
) {
  const { baseURL, timezoneId, locale } = test.info().project.use;
  const context = await browser.newContext({ baseURL, timezoneId, locale });
  const page = await context.newPage();
  await signInAs(page, email, password);
  return page;
}

// Given an administrator disables "<email>"'s account
export async function disableAccountAsAdmin(browser: Browser, email: string) {
  const admin = await otherSession(browser, 'super@openfn.org');
  await open(admin, `/settings/users/${user(email).id}`);
  // The "Disabled?" checkbox renders no label text; it sits before its hint.
  await admin
    .getByText('A disabled user will not be allowed to login.')
    .locator('xpath=preceding::input[@type="checkbox"][1]')
    .check();
  await admin.getByRole('button', { name: 'Save' }).click();
  await expect
    .poll(() =>
      sql(`select disabled from users where id = '${user(email).id}'`)
    )
    .toEqual([{ disabled: true }]);
  await admin.context().close();
}

export type Mail = { to: string[]; subject: string };

// The mail the instance has sent, newest first, from Swoosh's dev mailbox
export async function mailbox(request: APIRequestContext): Promise<Mail[]> {
  lightningOnly('needs a server: the dev mailbox');
  const res = await request.get('/dev/mailbox/json');
  expect(res.ok(), '/dev/mailbox/json should answer').toBe(true);
  const { data } = (await res.json()) as {
    data: { to: string[]; subject: string }[];
  };
  // Recipients read '"Name" <address>' or a bare address
  return data.map(m => ({
    subject: m.subject,
    to: m.to.map(t => t.match(/<([^>]+)>$/)?.[1] ?? t),
  }));
}

// Evaluates Elixir on the running Lightning node and returns the inspected
// result. The node shares ~/.erlang.cookie with this machine.
export function onNode(expr: string) {
  lightningOnly('needs a server: the Lightning node');
  const node = process.env.LIGHTNING_NODE || 'lightning_e2e@127.0.0.1';
  return execFileSync(
    'elixir',
    [
      '--name',
      `scenario-${process.pid}@127.0.0.1`,
      '-e',
      `true = Node.connect(:"${node}")
       IO.write(inspect(:erpc.call(:"${node}", Code, :eval_string, [${JSON.stringify(expr)}]) |> elem(0)))`,
    ],
    { encoding: 'utf8' }
  );
}

// Given the mailer is failing — every send is refused until the returned
// function puts the configured adapter back.
export function mailerFailing() {
  const configured = onNode(
    'Application.get_env(:lightning, Lightning.Mailer)'
  );
  onNode(`Application.put_env(:lightning, Lightning.Mailer,
            adapter: Swoosh.Adapters.SMTP, relay: "127.0.0.1", port: 1, retries: 0)`);
  return () =>
    onNode(`Application.put_env(:lightning, Lightning.Mailer, ${configured})`);
}

// Given "<email>"'s account was created at <utc> ("YYYY-MM-DD HH:MM:SS")
export function setSignUpTime(email: string, utc: string) {
  exec(
    `update users set inserted_at = '${utc}' where id = '${user(email).id}'`
  );
}

// Given "<email>" is also a member of project "<name>" — returns its id and
// a function that removes it again
export function extraProjectFor(email: string, name: string) {
  return seedProject(name, { [email]: 'editor' });
}

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given project "<name>" exists with these members, workflows last changed at
// these times (UTC, "YYYY-MM-DD HH:MM:SS[.ffffff]"; `deleted` ones are soft
// deleted) and support access on or off — returns its id and a function that
// removes it again
export function seedProject(
  name: string,
  members: Record<string, Role>,
  {
    workflows = [],
    allowSupportAccess = false,
  }: {
    workflows?: { updated_at: string; deleted?: boolean }[];
    allowSupportAccess?: boolean;
  } = {}
) {
  const [{ id }] = sql<{ id: string }>(`select gen_random_uuid() as id`);
  const users = Object.entries(members).map(
    ([email, role]) =>
      `insert into project_users (id, project_id, user_id, role, inserted_at, updated_at)
         values (gen_random_uuid(), '${id}', '${user(email).id}', '${role}', now(), now());`
  );
  const flows = workflows.map(
    (w, i) =>
      `insert into workflows (id, name, project_id, inserted_at, updated_at, deleted_at)
         values (gen_random_uuid(), 'workflow-${i + 1}', '${id}', '${w.updated_at}',
                 '${w.updated_at}', ${w.deleted ? 'now()' : 'null'});`
  );
  exec(`insert into projects (id, name, allow_support_access, inserted_at, updated_at)
          values ('${id}', ${literal(name)}, ${allowSupportAccess}, now(), now());
        ${users.join('\n')}
        ${flows.join('\n')}`);
  return { id, remove: () => removeProject(id) };
}

const removeProject = (id: string) =>
  exec(`delete from project_users where project_id = '${id}';
        delete from projects where id = '${id}'`);

// Only projects one of this worker's users belongs to, so parallel workers
// creating the same name never see or remove each other's
const ownedByThisWorker = (alias: string) =>
  `exists (select 1 from project_users mine where mine.project_id = ${alias}.id
     and mine.user_id in (${manifest()
       .users.map(u => `'${u.id}'`)
       .join(', ')}))`;

// Removes every project called "<name>" that a scenario created through the
// UI, leaving the seeded ones alone
export function removeProjectsNamed(name: string) {
  const seeded = manifest().projects.map(p => `'${p.id}'`);
  for (const { id } of sql<{ id: string }>(
    `select p.id from projects p where p.name = ${literal(name)}
     and p.id not in (${seeded.join(', ')}) and ${ownedByThisWorker('p')}`
  ))
    removeProject(id);
}

// The projects called "<name>", with their parent and members ("email:role")
export function projectsNamed(name: string) {
  return sql<{ id: string; parent_id: string | null; members: string[] }>(
    `select p.id, p.parent_id,
            coalesce(array_agg(u.email || ':' || pu.role)
              filter (where u.id is not null), '{}') as members
     from projects p
     left join project_users pu on pu.project_id = p.id
     left join users u on u.id = pu.user_id
     where p.name = ${literal(name)} and ${ownedByThisWorker('p')} group by p.id`
  );
}

// Given "<email>" is a support user — returns a function that puts the flag back
export function makeSupportUser(email: string) {
  const { id } = user(email);
  const [{ support_user }] = sql<{ support_user: boolean }>(
    `select support_user from users where id = '${id}'`
  );
  exec(`update users set support_user = true where id = '${id}'`);
  return () =>
    exec(`update users set support_user = ${support_user} where id = '${id}'`);
}

// When I go back — waits for the LiveView socket to join the page I land on
export async function goBack(page: Page) {
  await page.goBack();
  await page.locator('.phx-connected').first().waitFor();
}

// When a "sort" event arrives with column "<column>". A sortable header sends
// the column it sorts by from its phx-value-by; repoint it and click.
export async function sortByColumnNamed(
  page: Page,
  header: string,
  column: string
) {
  const link = page
    .getByRole('columnheader')
    .getByRole('link', { name: header });
  await link.evaluate(
    (el, column) => el.setAttribute('phx-value-by', column),
    column
  );
  await link.click();
}

// When I submit <form> with an extra field "<name>" set to "<value>", by
// clicking its <submit> button. LiveView sends every named input in a form.
export async function submitWithExtraField(
  form: Locator,
  submit: string,
  name: string,
  value: string
) {
  await form.evaluate(
    (el, [name, value]) => {
      const input = document.createElement('input');
      Object.assign(input, { type: 'hidden', name, value });
      el.appendChild(input);
    },
    [name, value]
  );
  await form.getByRole('button', { name: submit }).click();
}

// Given "<email>"'s saved preferences are <prefs>
export function setPreferences(email: string, prefs: Record<string, unknown>) {
  exec(
    `update users set preferences = ${literal(JSON.stringify(prefs))}::jsonb
     where id = '${user(email).id}'`
  );
}

// "<email>"'s saved preferences, as stored
export function preferencesOf(email: string) {
  return sql<{ preferences: Record<string, unknown> }>(
    `select preferences from users where id = '${user(email).id}'`
  )[0].preferences;
}

// The "Experimental features" switch on "/profile". Found by role and name;
// today's switch has no accessible name (the card passes an empty label), so
// the fallback finds it inside the card's form, the only one that saves a
// preference on change.
export function experimentalSwitch(page: Page) {
  return page
    .getByRole('switch', { name: /experimental features/i })
    .or(
      page.locator('form[phx-change="update_preferences"]').getByRole('switch')
    );
}

// When the "Experimental features" switch sends <value> instead of "true" or
// "false", which the rendered form never does: the checkbox under the switch
// is repointed, then the switch is clicked.
export async function switchSendingValue(page: Page, value: string) {
  lightningOnly('needs a server: a forged change event has nothing to reach');
  await page
    .locator('form[phx-change="update_preferences"] input[type="checkbox"]')
    .evaluate((el, value) => ((el as HTMLInputElement).value = value), value);
  await experimentalSwitch(page).click();
}

// Given "<email>" is a superuser — returns a function that puts the role back
export function makeSuperuser(email: string) {
  const { id } = user(email);
  const [{ role }] = sql<{ role: string }>(
    `select role from users where id = '${id}'`
  );
  exec(`update users set role = 'superuser' where id = '${id}'`);
  return () => exec(`update users set role = '${role}' where id = '${id}'`);
}

// When another superuser changes "<email>"'s role to user and saves
export async function demoteAsAdmin(browser: Browser, email: string) {
  const admin = await otherSession(browser, 'super@openfn.org');
  await open(admin, `/settings/users/${user(email).id}`);
  await field(admin, 'Role').selectOption('user');
  await admin.getByRole('button', { name: 'Save' }).click();
  await expect
    .poll(() => sql(`select role from users where id = '${user(email).id}'`))
    .toEqual([{ role: 'user' }]);
  await admin.context().close();
}

/** The first 8 characters of an id, as the audit page shows them. */
export const shortId = (id: string) => id.slice(0, 8);

// Given the instance has no audit events yet — returns a function that puts
// the ones it had back. A crashed run leaves `audit_events_keep` behind; the
// next run keeps that copy rather than overwriting it.
export function isolateAuditEvents() {
  exec(`create table if not exists audit_events_keep as select * from audit_events;
        delete from audit_events`);
  return () =>
    exec(`delete from audit_events;
          insert into audit_events select * from audit_events_keep;
          drop table audit_events_keep`);
}

export type AuditEventSeed = {
  event: string;
  itemType?: string;
  itemId?: string;
  actorId?: string;
  actorType?:
    | 'user'
    | 'trigger'
    | 'project_repo_connection'
    | 'service_account';
  changes?: { before: object | null; after: object | null };
  metadata?: object;
  /** UTC, "YYYY-MM-DD HH:MM:SS"; defaults to now */
  insertedAt?: string;
};

// Given an audit event <seed> was recorded — returns the ids it used
export function seedAuditEvent(seed: AuditEventSeed) {
  const [ids] = sql<{ item: string; actor: string }>(
    `select gen_random_uuid() as item, gen_random_uuid() as actor`
  );
  const itemId = seed.itemId ?? ids.item;
  const actorId = seed.actorId ?? ids.actor;
  const json = (v: object) => `${literal(JSON.stringify(v))}::jsonb`;
  exec(`insert into audit_events
          (id, event, item_id, item_type, actor_id, actor_type, changes, metadata, inserted_at)
        values (gen_random_uuid(), ${literal(seed.event)}, '${itemId}',
          ${literal(seed.itemType ?? 'credential')}, '${actorId}',
          '${seed.actorType ?? 'user'}',
          ${json(seed.changes ?? { before: null, after: null })},
          ${json(seed.metadata ?? {})},
          ${seed.insertedAt ? `'${seed.insertedAt}'` : "now() at time zone 'utc'"})`);
  return { itemId, actorId };
}

// The status tag of a shared test generated in a loop: @passing-old for the
// ids that passed on this page, @pending for the rest.
export const tagFor = (id: string, passing: readonly string[]) =>
  passing.includes(id) ? '@passing-old' : '@pending';
