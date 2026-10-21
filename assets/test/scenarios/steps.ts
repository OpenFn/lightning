// Steps shared by annotation scenarios. They drive the real pages and read and
// seed the e2e database that the verify-lightning instance runs on.
//
// TARGET=demo runs the same specs against the openfn-ia-demo replica instead:
// hash routes, one fixed signed-in user, static fixtures and no server. A
// step it can't honour skips the test and says why.
import { execFileSync, spawn } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
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
// Sends the page's delete event straight down the LiveView socket, as a
// tampered client would, so it doesn't depend on how the modal is built.
export async function confirmDeletionNaming(page: Page, id: string) {
  lightningOnly('needs a server: a forged delete has nothing to reach');
  await expect(page.getByRole('button', { name: 'Yes' })).toBeVisible();
  await page.evaluate(id => {
    const { liveSocket } = window as unknown as {
      liveSocket: { execJS(el: Element, encodedJS: string): void };
    };
    const main = document.querySelector('[data-phx-main]');
    if (!main) throw new Error('No LiveView on the page');
    liveSocket.execJS(
      main,
      JSON.stringify([['push', { event: 'delete_token', value: { id } }]])
    );
  }, id);
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

// The eye at the end of a password field, which shows or hides what was typed
export const passwordEye = (within: Page | Locator, label: string) =>
  field(within, label).locator('xpath=following-sibling::div[1]/*[1]');

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

// ---------------------------------------------------------------------------
// Workflow health page (annotations/views/workflow-health.md)
// ---------------------------------------------------------------------------

const NOW = `(now() at time zone 'utc')`;

/** Where the health page of a workflow lives. */
export const healthPath = (projectId: string, workflowId: string) =>
  `/projects/${projectId}/w/${workflowId}/health`;

/** The element the page mounts its React charts into. */
export const healthRoot = (page: Page) => page.locator('#workflow-health');

export type HealthJob = { name: string; adaptor: string };

const DAILY_SYNC_JOBS: HealthJob[] = [
  { name: 'Fetch', adaptor: '@openfn/language-http@latest' },
  { name: 'Load', adaptor: '@openfn/language-dhis2@latest' },
];

export type SeededWorkflow = {
  id: string;
  projectId: string;
  name: string;
  /** job name (as it reads now) -> job id */
  jobs: Record<string, string>;
  snapshotId: string;
  dataclipId: string;
  /** Renames a job, which publishes a new snapshot of the workflow. */
  rename: (job: string, to: string) => void;
};

// Given workflow "<name>" with these jobs exists in project <projectId>. Remove
// it with removeWorkflowData(projectId) before the project goes.
export function seedWorkflow(
  projectId: string,
  name = 'Daily sync',
  jobs: HealthJob[] = DAILY_SYNC_JOBS
): SeededWorkflow {
  const workflowId = randomUUID();
  const dataclipId = randomUUID();
  const current = jobs.map(j => ({ ...j, id: randomUUID() }));
  let lockVersion = 0;
  let snapshotId = randomUUID();
  const snapshot = (id: string) =>
    `insert into workflow_snapshots (id, workflow_id, name, jobs, triggers, edges, inserted_at, lock_version)
     values ('${id}', '${workflowId}', ${literal(name)},
             ${literal(JSON.stringify(current.map(j => ({ ...j, body: 'fn(state => state)' }))))}::jsonb,
             '[]'::jsonb, '[]'::jsonb, ${NOW}, ${lockVersion})`;

  exec(`insert into workflows (id, name, project_id, inserted_at, updated_at, lock_version)
          values ('${workflowId}', ${literal(name)}, '${projectId}', ${NOW}, ${NOW}, 0);
        ${current
          .map(
            j => `insert into jobs (id, name, body, adaptor, workflow_id, inserted_at, updated_at)
                  values ('${j.id}', ${literal(j.name)}, 'fn(state => state)', '${j.adaptor}',
                          '${workflowId}', ${NOW}, ${NOW});`
          )
          .join('\n')}
        ${snapshot(snapshotId)};
        insert into dataclips (id, body, type, project_id, inserted_at, updated_at)
          values ('${dataclipId}', '{}'::jsonb, 'http_request', '${projectId}', ${NOW}, ${NOW})`);

  const workflow: SeededWorkflow = {
    id: workflowId,
    projectId,
    name,
    jobs: Object.fromEntries(current.map(j => [j.name, j.id])),
    get snapshotId() {
      return snapshotId;
    },
    dataclipId,
    rename(job, to) {
      const found = current.find(j => j.name === job);
      if (!found) throw new Error(`no job called ${job}`);
      found.name = to;
      lockVersion += 1;
      snapshotId = randomUUID();
      exec(`update jobs set name = ${literal(to)} where id = '${found.id}';
            update workflows set lock_version = ${lockVersion} where id = '${workflowId}';
            ${snapshot(snapshotId)}`);
      this.jobs = Object.fromEntries(current.map(j => [j.name, j.id]));
    },
  };
  return workflow;
}

export type SeededStep = {
  job: string;
  /** the step's exit reason; "fail" unless said otherwise */
  exit?: string;
  error?: string | null;
};
export type SeededRun = { state: string; error?: string; steps?: SeededStep[] };

// Given a "<wf>" work order in <state> whose runs were <runs> (oldest first),
// last active <minutesAgo> minutes ago, or at <at> (UTC, "YYYY-MM-DD HH:MM:SS")
export function seedWorkOrder(
  wf: SeededWorkflow,
  {
    state,
    runs = [],
    minutesAgo = 60,
    at,
  }: { state: string; runs?: SeededRun[]; minutesAgo?: number; at?: string }
) {
  const base = at
    ? `('${at}'::timestamp)`
    : `(${NOW} - interval '${minutesAgo} minutes')`;
  const later = (minutes: number) =>
    `(${base} + interval '${minutes} minutes')`;
  const workOrderId = randomUUID();
  const statements = [
    `insert into work_orders (id, workflow_id, inserted_at, updated_at, state, last_activity, snapshot_id, dataclip_id)
     values ('${workOrderId}', '${wf.id}', ${base}, ${base}, '${state}', ${later(runs.length)}, '${wf.snapshotId}', '${wf.dataclipId}')`,
  ];
  runs.forEach((run, i) => {
    const runId = randomUUID();
    statements.push(
      `insert into runs (id, work_order_id, inserted_at, updated_at, state, started_at, finished_at, dataclip_id, error_type, snapshot_id, starting_job_id)
       values ('${runId}', '${workOrderId}', ${later(i)}, ${later(i + 1)}, '${run.state}', ${later(i)}, ${later(i + 1)},
               '${wf.dataclipId}', ${run.error ? literal(run.error) : 'null'}, '${wf.snapshotId}',
               '${wf.jobs[run.steps?.[0]?.job ?? ''] ?? Object.values(wf.jobs)[0]}')`
    );
    for (const step of run.steps ?? []) {
      const jobId = wf.jobs[step.job];
      if (!jobId) throw new Error(`no job called ${step.job}`);
      const stepId = randomUUID();
      statements.push(
        `insert into steps (id, started_at, finished_at, inserted_at, updated_at, job_id, exit_reason, error_type, snapshot_id)
         values ('${stepId}', ${later(i)}, ${later(i + 1)}, ${later(i)}, ${later(i + 1)}, '${jobId}',
                 '${step.exit ?? 'fail'}', ${step.error == null ? 'null' : literal(step.error)}, '${wf.snapshotId}')`,
        `insert into run_steps (id, run_id, step_id, inserted_at)
         values (gen_random_uuid(), '${runId}', '${stepId}', ${later(i)})`
      );
    }
  });
  exec(statements.join(';\n'));
  return workOrderId;
}

// Given <count> "<wf>" work orders in <state>, with no runs, last active
// <minutesAgo> minutes ago
export function seedWorkOrders(
  wf: SeededWorkflow,
  state: string,
  count: number,
  minutesAgo = 60
) {
  exec(`insert into work_orders (id, workflow_id, inserted_at, updated_at, state, last_activity, snapshot_id, dataclip_id)
        select gen_random_uuid(), '${wf.id}', t, t, '${state}', t, '${wf.snapshotId}', '${wf.dataclipId}'
        from (select ${NOW} - interval '${minutesAgo} minutes' as t
              from generate_series(1, ${count})) s`);
}

// Removes the work orders, runs, steps and dataclips seeded for a project's
// workflows. Do this before removing the project: steps and runs hold
// restricting references.
export function removeWorkflowData(projectId: string) {
  exec(`delete from workflow_releases where workflow_id in
          (select id from workflows where project_id = '${projectId}');
        delete from steps where job_id in
          (select j.id from jobs j join workflows w on w.id = j.workflow_id
           where w.project_id = '${projectId}');
        delete from work_orders where workflow_id in
          (select id from workflows where project_id = '${projectId}');
        delete from dataclips where project_id = '${projectId}'`);
}

// Given the browser reports its timezone as <zone>, even one the browser
// itself would not accept. Call before the first page load.
export async function browserReportsTimezone(page: Page, zone: string) {
  await page.addInitScript(zone => {
    // eslint-disable-next-line @typescript-eslint/unbound-method -- called back with its own `this`
    const resolved = Intl.DateTimeFormat.prototype.resolvedOptions;
    Intl.DateTimeFormat.prototype.resolvedOptions = function (
      this: Intl.DateTimeFormat
    ) {
      return { ...resolved.call(this), timeZone: zone };
    };
  }, zone);
}

// Then the History page open in `tab` lists these work orders and not those.
// Each work order of History is a row with a details toggle named by its id.
export async function expectHistoryLists(
  tab: Page,
  listed: string[],
  notListed: string[]
) {
  const row = (id: string) => tab.locator(`#toggle_details_for_${id}`);
  for (const id of listed) await expect(row(id)).toBeAttached();
  for (const id of notListed) await expect(row(id)).toHaveCount(0);
}

// When the tab becomes visible again: the page reads fresh numbers at once
export async function returnToTab(page: Page) {
  await page.evaluate(() =>
    document.dispatchEvent(new Event('visibilitychange'))
  );
}

// Evaluates Elixir that must succeed on the Lightning node
const onNodeOk = (lines: string[]) => onNode(`${lines.join('\n')}\n:ok`);

// When an admin removes "<email>" from project <projectId> in another session
export function removeMemberOnNode(
  projectId: string,
  memberEmail: string,
  actorEmail: string
) {
  onNodeOk([
    `pu = Lightning.Repo.get_by!(Lightning.Projects.ProjectUser, project_id: "${projectId}", user_id: "${user(memberEmail).id}")`,
    `actor = Lightning.Repo.get!(Lightning.Accounts.User, "${user(actorEmail).id}")`,
    `Lightning.Projects.delete_project_user!(pu, actor)`,
  ]);
}

// When an owner changes "<email>"'s role on project <projectId> to <role>
export function changeRoleOnNode(
  projectId: string,
  memberEmail: string,
  role: string
) {
  const { id } = user(memberEmail);
  exec(
    `update project_users set role = '${role}' where project_id = '${projectId}' and user_id = '${id}'`
  );
  onNodeOk([
    `Lightning.Projects.Events.project_user_role_changed("${projectId}", "${id}")`,
  ]);
}

// When an owner turns support access on project <projectId> on or off
export function setSupportAccessOnNode(projectId: string, allowed: boolean) {
  onNodeOk([
    `project = Lightning.Projects.get_project!("${projectId}")`,
    `{:ok, _} = Lightning.Projects.update_project(project, %{allow_support_access: ${allowed}})`,
  ]);
}

// When an owner schedules project <projectId> for deletion
export function scheduleDeletionOnNode(projectId: string) {
  onNodeOk([
    `project = Lightning.Projects.get_project!("${projectId}")`,
    `{:ok, _} = Lightning.Projects.schedule_project_deletion(project)`,
  ]);
}

// When "<email>" deletes workflow <workflowId> in another session
export function deleteWorkflowOnNode(workflowId: string, actorEmail: string) {
  onNodeOk([
    `wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, "${workflowId}")`,
    `actor = Lightning.Repo.get!(Lightning.Accounts.User, "${user(actorEmail).id}")`,
    `{:ok, _} = Lightning.Workflows.mark_for_deletion(wf, actor)`,
  ]);
}

// Given a failure alert for the workflow was emailed to "<email>"
export function sendFailureAlertOnNode(
  projectId: string,
  wf: SeededWorkflow,
  email: string
) {
  onNodeOk([
    `recipient = Lightning.Repo.get!(Lightning.Accounts.User, "${user(email).id}")`,
    `project = Lightning.Projects.get_project!("${projectId}")`,
    `Lightning.FailureAlerter.alert(%{"workflow_id" => "${wf.id}", "workflow_name" => "${wf.name}", "project" => project, "work_order_id" => Ecto.UUID.generate(), "run_id" => Ecto.UUID.generate(), "recipient" => recipient})`,
  ]);
}

// Given a digest listing failures for the workflow was emailed to "<email>"
export function sendDigestOnNode(
  projectId: string,
  wf: SeededWorkflow,
  email: string
) {
  onNodeOk([
    `recipient = Lightning.Repo.get!(Lightning.Accounts.User, "${user(email).id}")`,
    `project = Lightning.Projects.get_project!("${projectId}")`,
    `workflow = Lightning.Repo.get!(Lightning.Workflows.Workflow, "${wf.id}")`,
    `finish = DateTime.utc_now()`,
    `start = DateTime.add(finish, -7, :day)`,
    `Lightning.Accounts.UserNotifier.deliver_project_digest([%{workflow: workflow, successful_workorders: 1, failed_workorders: 2}], %{user: recipient, project: project, digest: :weekly, start_date: start, end_date: finish})`,
  ]);
}

// The path of the link to <path> in the mail the dev mailbox holds for
// "<email>". The mail's fields are searched whole, so it does not matter
// whether the link is in the html or the text body.
export async function mailedLinkTo(
  request: APIRequestContext,
  email: string,
  path: string
) {
  const escaped = path.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
  const link = new RegExp(`https?://[^"\\\\\\s<>]*${escaped}`);
  let found: string | undefined;
  await expect
    .poll(
      async () => {
        const res = await request.get('/dev/mailbox/json');
        const { data } = (await res.json()) as { data: unknown[] };
        for (const mail of data) {
          const text = JSON.stringify(mail);
          if (!text.includes(email)) continue;
          found = text.match(link)?.[0];
          if (found) return true;
        }
        return false;
      },
      { message: `a mail to ${email} linking to ${path}` }
    )
    .toBe(true);
  return new URL(found!).pathname;
}

// ---------------------------------------------------------------------------
// History page (annotations/views/history-work-orders.md)
// ---------------------------------------------------------------------------

/** "YYYY-MM-DD HH:MM:SS" in UTC, as the seeding steps take it. */
export const utcStamp = (date: Date) =>
  date.toISOString().slice(0, 19).replace('T', ' ');

/** The moment <days> days ago. */
export const daysAgo = (days: number) =>
  new Date(Date.now() - days * 24 * 60 * 60 * 1000);

/** A date the way History's filter chips write it: "5-Mar", or "5-Mar-2024". */
export function historyDate(date: Date) {
  const month = date.toLocaleString('en-US', {
    month: 'short',
    timeZone: 'UTC',
  });
  const year = date.getUTCFullYear();
  return `${date.getUTCDate()}-${month}${
    year === new Date().getUTCFullYear() ? '' : `-${year}`
  }`;
}

/**
 * Text that names <date> to within a day, in whatever format a chip writes it:
 * it has the day of the month of the day before, the day itself or the day
 * after. Loose on purpose; the format and the time zone are not the point.
 */
export const nearDate = (date: Date) => {
  const days = [-1, 0, 1].map(offset =>
    new Date(date.getTime() + offset * 86_400_000).getUTCDate()
  );
  return new RegExp(`\\b(${days.join('|')})\\b`);
};

/** Where History lives. `filters` become `filters[...]` params. */
export function historyPath(
  projectId: string,
  filters: Record<string, string | string[]> = {},
  params: Record<string, string> = {}
) {
  const parts = Object.entries(filters).flatMap(([key, value]) =>
    Array.isArray(value)
      ? value.map(v => `filters[${key}][]=${encodeURIComponent(v)}`)
      : [`filters[${key}]=${encodeURIComponent(value)}`]
  );
  for (const [key, value] of Object.entries(params))
    parts.push(`${key}=${encodeURIComponent(value)}`);
  return `/projects/${projectId}/history${parts.length ? `?${parts.join('&')}` : ''}`;
}

// Then the work orders have loaded (or the load has failed)
export const historyLoaded = (page: Page) =>
  expect(page.getByText('Loading work orders ...')).toBeHidden();

// When I open the history page of project <projectId>
export async function openHistory(
  page: Page,
  projectId: string,
  filters?: Record<string, string | string[]>,
  params?: Record<string, string>
) {
  await open(page, historyPath(projectId, filters, params));
  await historyLoaded(page);
}

/** The table of work orders, which only the mounted page has. */
export const historyRoot = (page: Page) => page.locator('#work-orders-table');

export const historySearchBox = (page: Page) =>
  page.getByPlaceholder('Search work orders...');

/** The row of work order <id>. */
export const historyRow = (page: Page, id: string) =>
  page.locator(`#toggle_details_for_${id}`);

const HISTORY_COLUMNS = [
  'select',
  'ID',
  'Workflow',
  'Input',
  'Created',
  'Last Activity',
  'Duration',
  'Status',
  'Runs',
] as const;

/** One cell of a work order's row. */
export const historyCell = (
  row: Locator,
  column: (typeof HISTORY_COLUMNS)[number]
) => row.getByRole('cell').nth(HISTORY_COLUMNS.indexOf(column));

/** The ids of the listed work orders, top to bottom. */
export const listedWorkOrders = (page: Page) =>
  page
    .locator('[id^="toggle_details_for_"]')
    .evaluateAll(rows =>
      rows.map(row => row.id.replace('toggle_details_for_', ''))
    );

// Then the work orders are listed in this order
export const expectHistoryOrder = (page: Page, ids: string[]) =>
  expect.poll(() => listedWorkOrders(page)).toEqual(ids);

// When I click a work order's row, which opens its runs
export async function expandWorkOrder(page: Page, id: string) {
  await historyCell(historyRow(page, id), 'Status').click();
  await expect(
    page.locator(`#workorder-${id} [id^="run_"]`).first()
  ).toBeVisible();
}

/** The block of one run in an opened work order. */
export const historyRun = (page: Page, runId: string) =>
  page.locator(`#run_${runId}`);

/** The link that opens a run, named by the run's short id. */
export const runLink = (page: Page, runId: string) =>
  page.getByRole('link', { name: shortId(runId), exact: true });

/** The row of one step inside an opened run. */
export const stepRow = (page: Page, stepId: string) =>
  page.locator(`#step-${stepId}`);

/** The "run this step again" icon of a step. */
export const rerunStepIcon = (page: Page, stepId: string) =>
  stepRow(page, stepId).getByLabel(
    /run this step|cannot be rerun|cannot be retried/i
  );

/** The icon that opens a step in the editor. */
export const inspectStepLink = (page: Page, stepId: string) =>
  page.locator(`#inspect-step-${stepId}`);

/** The marker of a step carried over from an earlier run. */
export const carriedMarker = (within: Locator) =>
  within.locator('[aria-label^="This step was originally executed"]');

/** The button that cancels one run of an opened work order. */
export const cancelRunButton = (page: Page, runId: string) =>
  historyRun(page, runId).getByRole('button', { name: 'Cancel this run' });

/** The retry button of a work order's row. */
export const retryButton = (row: Locator) =>
  row.getByRole('button', { name: 'Retry (run from the start)' });

/** The stand-in for a retry button that is not available. */
export const disabledRetry = (page: Page, workOrderId: string) =>
  page.locator(`#retry-disabled-${workOrderId}`);

/** The cancel button of a pending work order's row. */
export const cancelWorkOrderButton = (row: Locator) =>
  row.getByRole('button', { name: 'Cancel pending run' });

/** The export button under the table. */
export const exportButton = (page: Page) =>
  page.getByRole('button', { name: /^Export all \d+ results/ });

/** The tick-all box in the table header. */
export const selectAll = (page: Page) =>
  page.getByRole('columnheader').first().getByRole('checkbox');

/** The tick box of one work order. */
export const selectBox = (page: Page, id: string) =>
  historyCell(historyRow(page, id), 'select').getByRole('checkbox');

/** A bulk action above the table ("Cancel", "Retry", "Retry from"). */
export const bulkAction = (page: Page, name: string) =>
  page.getByRole('button', { name, exact: true });

/** The wrapper that carries the tooltip of a disabled bulk action. */
export const tipOf = (page: Page, text: string) =>
  page.locator(`span[aria-label="${text}"]`);

/** The filter chip whose button reads <name>. */
export const chip = (page: Page, name: string | RegExp) =>
  page.getByRole('button', { name }).locator('xpath=..');

/** The button that drops a chip's filter. */
export const clearChipButton = (chipBox: Locator) =>
  chipBox.getByRole('button', { name: 'Clear filter' });

// When I choose <name> from the workflow chip
export async function chooseWorkflow(page: Page, name: string) {
  await page.getByRole('button', { name: /^Workflow is/ }).click();
  await page.getByRole('menuitem', { name, exact: true }).click();
}

// When I tick these statuses in the status chip
export async function chooseStatuses(page: Page, ...labels: string[]) {
  await page.getByRole('button', { name: /^Status (is|in)/ }).click();
  for (const label of labels)
    await page.getByRole('checkbox', { name: label, exact: true }).check();
}

// When I set "Received after" to <value> ("YYYY-MM-DDTHH:MM", UTC)
export async function setReceivedAfter(page: Page, value: string) {
  await page.getByRole('button', { name: /^Received/ }).click();
  await field(page, 'Received After').fill(value);
}

// When I set "Activity After" to <value> ("YYYY-MM-DDTHH:MM", UTC)
export async function setLastActivityAfter(page: Page, value: string) {
  await page.getByRole('button', { name: /^Last activity/ }).click();
  await field(page, 'Activity After').fill(value);
}

// When I include <what> in the search
export async function includeInSearch(
  page: Page,
  what: 'IDs' | 'dataclip names' | 'inputs' | 'run logs'
) {
  await page
    .getByRole('button', { name: new RegExp(`^Include ${what}`) })
    .click();
}

// When I search for <term>
export async function searchHistory(page: Page, term: string) {
  await historySearchBox(page).fill(term);
  await page.getByRole('button', { name: 'Search', exact: true }).click();
}

// When I click the <column> column header
export const sortHistoryBy = (page: Page, column: string) =>
  page.getByRole('columnheader').getByRole('link', { name: column }).click();

// When the page is sent the LiveView event <event> with <values>, even though
// nothing on it offers that action. The sortable column header sends an event
// named by its phx-click; repoint it and click.
export const sendEvent = (
  page: Page,
  event: string,
  values: Record<string, string> = {}
) => sendEventFrom(page, 'Created', event, values);

// The same, from the sortable column header named <header>
export async function sendEventFrom(
  page: Page,
  header: string,
  event: string,
  values: Record<string, string> = {}
) {
  lightningOnly('needs a server: a forged event has nothing to reach');
  const link = page
    .getByRole('columnheader')
    .getByRole('link', { name: header });
  await link.evaluate(
    (el, { event, values }) => {
      el.removeAttribute('phx-value-by');
      el.setAttribute('phx-click', event);
      for (const [name, value] of Object.entries(values))
        el.setAttribute(`phx-value-${name}`, value);
    },
    { event, values }
  );
  await link.click();
}

// When I click a step's "run again" icon after pointing it at <run> and <step>
export async function rerunStepNaming(
  icon: Locator,
  runId: string,
  stepId: string
) {
  lightningOnly('needs a server: a forged rerun has nothing to reach');
  await icon.evaluate(
    (el, ids) => {
      el.setAttribute('phx-value-run_id', ids.runId);
      el.setAttribute('phx-value-step_id', ids.stepId);
    },
    { runId, stepId }
  );
  await icon.click();
}

export type HistoryStepSeed = {
  job: string;
  /** the exit reason ("fail" unless said); null while the step is unfinished */
  exit?: string | null;
  error?: string | null;
  /** this step is the one the previous run ran for the same job, carried over */
  carried?: boolean;
  /** the step's input was wiped by the retention policy */
  inputWiped?: boolean;
  /** the body of the step's input dataclip, which search reads */
  input?: object;
  /** how long the step has run for (unfinished) or ran for (finished) */
  seconds?: number;
  /** a line in the step's log */
  log?: string;
};

export type HistoryRunSeed = {
  /** available, claimed, started, or a final state */
  state: string;
  steps?: HistoryStepSeed[];
  error?: string;
  /** a line in the run's log */
  log?: string;
};

const dataclipSql = (
  id: string,
  projectId: string,
  { body, wiped, name }: { body?: object; wiped?: boolean; name?: string }
) => {
  const json = literal(JSON.stringify(body ?? {}));
  return `insert into dataclips (id, body, type, project_id, inserted_at, updated_at, wiped_at, name, search_vector)
          values ('${id}', ${wiped ? 'null' : `${json}::jsonb`}, 'http_request', '${projectId}', ${NOW}, ${NOW},
                  ${wiped ? NOW : 'null'}, ${name ? literal(name) : 'null'},
                  ${wiped || !body ? 'null' : `jsonb_to_tsvector('english_nostop', ${json}::jsonb, '"all"')`})`;
};

// Given a "<wf>" work order in <state> with these runs (oldest first), last
// active <minutesAgo> minutes ago, or at <at> (UTC, "YYYY-MM-DD HH:MM:SS").
// Run i is created i minutes after the work order and, once it has started,
// finishes a minute later. The workflow's concurrency is set to 0, so Lightning
// never offers its runs to a worker (a worker with no queue list reads every
// queue, "*") and none is claimed while a test looks at it. Returns the ids.
export function seedHistoryOrder(
  wf: SeededWorkflow,
  {
    state,
    runs = [],
    minutesAgo = 60,
    at,
    input,
  }: {
    state: string;
    runs?: HistoryRunSeed[];
    minutesAgo?: number;
    at?: string;
    /** the work order's input dataclip */
    input?: { body?: object; wiped?: boolean; name?: string };
  }
) {
  const base = at
    ? `('${at}'::timestamp)`
    : `(${NOW} - interval '${minutesAgo} minutes')`;
  const later = (minutes: number) =>
    `(${base} + interval '${minutes} minutes')`;
  const workOrderId = randomUUID();
  const statements: string[] = [];
  let clip = wf.dataclipId;
  statements.push(`update workflows set concurrency = 0 where id = '${wf.id}'`);
  if (input) {
    clip = randomUUID();
    statements.push(dataclipSql(clip, wf.projectId, input));
  }
  statements.push(
    `insert into work_orders (id, workflow_id, inserted_at, updated_at, state, last_activity, snapshot_id, dataclip_id)
     values ('${workOrderId}', '${wf.id}', ${base}, ${base}, '${state}', ${later(runs.length)}, '${wf.snapshotId}', '${clip}')`
  );
  const log = (
    message: string,
    runId: string,
    stepId: string | null,
    i: number
  ) =>
    `insert into log_lines (id, message, step_id, run_id, timestamp, level, source, search_vector)
     values (gen_random_uuid(), ${literal(message)}, ${stepId ? `'${stepId}'` : 'null'}, '${runId}', ${later(i)}, 'info', 'R',
             to_tsvector('english_nostop', ${literal(message)}))`;

  const stepIds: Record<string, string>[] = [];
  const runIds: string[] = [];
  runs.forEach((run, i) => {
    const runId = randomUUID();
    runIds.push(runId);
    const waiting = run.state === 'available';
    const claimed = run.state === 'claimed';
    const finished = !waiting && !claimed && run.state !== 'started';
    statements.push(
      `insert into runs (id, work_order_id, inserted_at, updated_at, state, claimed_at, started_at, finished_at, dataclip_id, error_type, snapshot_id, starting_job_id, queue)
       values ('${runId}', '${workOrderId}', ${later(i)}, ${later(i + 1)}, '${run.state}',
               ${claimed ? later(i) : 'null'}, ${waiting || claimed ? 'null' : later(i)}, ${finished ? later(i + 1) : 'null'},
               '${clip}', ${run.error ? literal(run.error) : 'null'}, '${wf.snapshotId}',
               '${wf.jobs[run.steps?.[0]?.job ?? ''] ?? Object.values(wf.jobs)[0]}', 'scenario-history')`
    );
    const ids: Record<string, string> = {};
    for (const step of run.steps ?? []) {
      const jobId = wf.jobs[step.job];
      if (!jobId) throw new Error(`no job called ${step.job}`);
      if (step.carried) {
        const earlier = stepIds[i - 1]?.[step.job];
        if (!earlier) throw new Error(`no earlier step for ${step.job}`);
        ids[step.job] = earlier;
        statements.push(
          `insert into run_steps (id, run_id, step_id, inserted_at)
           values (gen_random_uuid(), '${runId}', '${earlier}', ${later(i)})`
        );
        continue;
      }
      const stepId = randomUUID();
      ids[step.job] = stepId;
      let inputClip = wf.dataclipId;
      if (step.input || step.inputWiped) {
        inputClip = randomUUID();
        statements.push(
          dataclipSql(inputClip, wf.projectId, {
            body: step.input,
            wiped: step.inputWiped,
          })
        );
      }
      const exit = step.exit === undefined ? 'fail' : step.exit;
      const unfinished = exit === null;
      const startedAt =
        unfinished && step.seconds !== undefined
          ? `(${NOW} - interval '${step.seconds} seconds')`
          : later(i);
      const finishedAt = unfinished
        ? 'null'
        : step.seconds !== undefined
          ? `(${later(i)} + interval '${step.seconds} seconds')`
          : later(i + 1);
      statements.push(
        `insert into steps (id, started_at, finished_at, inserted_at, updated_at, job_id, input_dataclip_id, exit_reason, error_type, snapshot_id)
         values ('${stepId}', ${startedAt}, ${finishedAt}, ${later(i)}, ${later(i + 1)}, '${jobId}', '${inputClip}',
                 ${exit === null ? 'null' : literal(exit)}, ${step.error == null ? 'null' : literal(step.error)}, '${wf.snapshotId}')`,
        `insert into run_steps (id, run_id, step_id, inserted_at)
         values (gen_random_uuid(), '${runId}', '${stepId}', ${later(i)})`
      );
      if (step.log) statements.push(log(step.log, runId, stepId, i));
    }
    if (run.log) statements.push(log(run.log, runId, null, i));
    stepIds.push(ids);
  });
  exec(statements.join(';\n'));
  return {
    id: workOrderId,
    dataclipId: clip,
    runs: runIds.map((id, i) => ({ id, steps: stepIds[i] })),
  };
}

// Given <count> "<wf>" work orders, each with a failed run whose log holds
// <message>, last active an hour ago
export function seedLoggedWorkOrders(
  wf: SeededWorkflow,
  count: number,
  message: string
) {
  exec(`with wo as (
          insert into work_orders (id, workflow_id, inserted_at, updated_at, state, last_activity, snapshot_id, dataclip_id)
          select gen_random_uuid(), '${wf.id}', t, t, 'failed', t, '${wf.snapshotId}', '${wf.dataclipId}'
          from (select ${NOW} - interval '60 minutes' as t from generate_series(1, ${count})) s
          returning id, inserted_at
        ), r as (
          insert into runs (id, work_order_id, inserted_at, updated_at, state, started_at, finished_at, dataclip_id, snapshot_id, starting_job_id, queue)
          select gen_random_uuid(), wo.id, wo.inserted_at, wo.inserted_at, 'failed', wo.inserted_at, wo.inserted_at,
                 '${wf.dataclipId}', '${wf.snapshotId}', '${Object.values(wf.jobs)[0]}', 'scenario-history'
          from wo
          returning id, inserted_at
        )
        insert into log_lines (id, message, run_id, timestamp, level, source, search_vector)
        select gen_random_uuid(), ${literal(message)}, r.id, r.inserted_at, 'info', 'R',
               to_tsvector('english_nostop', ${literal(message)})
        from r`);
}

// Given the workflow's jobs run in this order after a webhook trigger. A
// rerun from a step carries over the steps that come before it by walking
// these edges.
export function connectJobs(wf: SeededWorkflow, order: string[]) {
  const triggerId = randomUUID();
  const edge = (source: string, target: string) =>
    `insert into workflow_edges (id, workflow_id, source_job_id, target_job_id, condition_type, enabled, inserted_at, updated_at)
     values (gen_random_uuid(), '${wf.id}', '${wf.jobs[source]}', '${wf.jobs[target]}', 'always', true, ${NOW}, ${NOW})`;
  exec(`insert into triggers (id, workflow_id, project_id, type, enabled, inserted_at, updated_at)
          values ('${triggerId}', '${wf.id}', '${wf.projectId}', 'webhook', true, ${NOW}, ${NOW});
        insert into workflow_edges (id, workflow_id, source_trigger_id, target_job_id, condition_type, enabled, inserted_at, updated_at)
          values (gen_random_uuid(), '${wf.id}', '${triggerId}', '${wf.jobs[order[0]]}', 'always', true, ${NOW}, ${NOW});
        ${order
          .slice(1)
          .map((job, i) => `${edge(order[i], job)};`)
          .join('\n')}`);
}

// When a webhook request reaches the workflow's trigger (connectJobs made it),
// which makes a new work order. Returns once Lightning has accepted it.
export async function postWebhook(page: Page, wf: SeededWorkflow) {
  lightningOnly('needs a server: a webhook has nothing to reach');
  const [trigger] = sql<{ id: string }>(
    `select id from triggers where workflow_id = '${wf.id}' and type = 'webhook'`
  );
  const response = await page.request.post(`/i/${trigger.id}`, {
    data: { patient: { name: 'new arrival' } },
  });
  expect(response.ok(), `webhook answered ${response.status()}`).toBe(true);
}

// Given another session holds the log lines table locked, so that a search of
// run logs waits for it. Returns the function that lets go. Nothing else may
// read log lines meanwhile: the test using this is @serial.
export async function lockLogLines(): Promise<() => void> {
  lightningOnly('needs the database');
  const holder = spawn(PSQL, [DB, '-AtX', '-v', 'ON_ERROR_STOP=1'], {
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  // The session sits idle in its transaction rather than in pg_sleep, so
  // Postgres sees the client go at once, and lets go after 90s if nobody calls
  // the release (a crashed run must not block the next one).
  holder.stdin.write(
    "set idle_in_transaction_session_timeout = '90s';\nbegin;\nlock table log_lines in access exclusive mode;\n\\echo locked\n"
  );
  await new Promise<void>((resolve, reject) => {
    holder.stdout.on('data', chunk => {
      if (String(chunk).includes('locked')) resolve();
    });
    holder.on('exit', () => reject(new Error('the lock was not taken')));
  });
  return () => void holder.stdin.end('rollback;\n');
}

// Given the workflow was deleted
export function markWorkflowDeleted(wf: SeededWorkflow) {
  exec(`update workflows set deleted_at = ${NOW} where id = '${wf.id}'`);
}

// Given the job <name> of the workflow was deleted since its steps ran.
// Steps keep their job id, so remove them with removeStepsOf(wf, name) before
// the project goes.
export function deleteJobOf(wf: SeededWorkflow, name: string) {
  exec(`delete from jobs where id = '${wf.jobs[name]}'`);
}

export function removeStepsOfJob(jobId: string) {
  exec(`delete from steps where job_id = '${jobId}'`);
}

// Given a worker claimed the run after the page loaded
export function claimRun(runId: string) {
  exec(
    `update runs set state = 'claimed', claimed_at = ${NOW} where id = '${runId}'`
  );
}

/** The state a run is in now. */
export const runStateOf = (runId: string) =>
  sql<{ state: string }>(`select state from runs where id = '${runId}'`)[0]
    ?.state;

/** The ids of a work order's runs, oldest first. */
export const runsOfWorkOrder = (workOrderId: string) =>
  sql<{ id: string; starting_job_id: string }>(
    `select id, starting_job_id from runs where work_order_id = '${workOrderId}'
     order by inserted_at`
  );

/** The ids of the steps a run holds, carried over or its own. */
export const stepsOfRun = (runId: string) =>
  sql<{ step_id: string }>(
    `select step_id from run_steps where run_id = '${runId}'`
  ).map(row => row.step_id);

/** The background jobs of <worker> that name <id> in their arguments. */
export const obanJobsNaming = (worker: string, id: string) =>
  sql<{ state: string }>(
    `select state from oban_jobs where worker = '${worker}' and args::text like '%${id}%'`
  );

/** The duration shown for a step, run or work order inside <within>. */
export const elapsedOf = (within: Locator) =>
  within.locator('[phx-hook="ElapsedIndicator"]');

/** The time a run's header shows, in its relative detailed form. */
export const runTimestamp = (page: Page, runId: string) =>
  historyRun(page, runId).locator('[data-format="relative_detailed"]');

// ---------------------------------------------------------------------------
// Log in page (annotations/views/auth-login.md)
// ---------------------------------------------------------------------------

export const REMEMBER_COOKIE = '_lightning_web_user_remember_me';

/** Fills in and submits the log in form on the page already open. Resolves when the server has answered the POST. */
export async function submitLogin(
  page: Page,
  email: string,
  password: string,
  { remember = false } = {}
) {
  await field(page, 'Email').fill(forWorker(email));
  await field(page, 'Password').fill(password);
  if (remember)
    await page
      .locator('input[type="checkbox"][name="user[remember_me]"]')
      .check();
  await Promise.all([
    page.waitForResponse(
      r => r.request().method() === 'POST' && r.url().includes('/users/log_in')
    ),
    page.getByRole('button', { name: 'Log in' }).click(),
  ]);
}

// When I log in with "<email>" and "<password>" — from a fresh visit to the page
export async function attemptLogin(
  page: Page,
  email: string,
  password = PASSWORD,
  options: { remember?: boolean } = {}
) {
  await page.goto('/users/log_in');
  await submitLogin(page, email, password, options);
}

// Then I am logged in as "<email>" — the account menu on /projects names them
export async function expectSignedInAs(page: Page, email: string) {
  await expectAt(page, '/projects');
  await open(page, '/projects');
  const [{ name }] = sql<{ name: string }>(
    `select first_name || ' ' || last_name as name from users where id = '${user(email).id}'`
  );
  await page.getByRole('button', { name: new RegExp(`${name}$`) }).click();
  await expect(
    page.getByRole('menu').getByText(user(email).email, { exact: true })
  ).toBeVisible();
}

// Then I am not logged in — a protected page sends the browser to log in
export async function expectSignedOut(page: Page) {
  await page.goto('/projects');
  await expectAt(page, '/users/log_in');
}

// When the browser is closed and opened again — only cookies that outlive the session remain
export async function reopenBrowser(page: Page) {
  const context = page.context();
  const kept = (await context.cookies()).filter(c => c.expires !== -1);
  await context.clearCookies();
  await context.addCookies(kept);
}

// Given the instance setting :lightning, :<flag> is <value> — returns a function that puts it back
export function withFlag(flag: string, value: boolean) {
  const was = onNode(`Application.get_env(:lightning, :${flag})`).trim();
  onNode(`Application.put_env(:lightning, :${flag}, ${value})`);
  return () => onNode(`Application.put_env(:lightning, :${flag}, ${was})`);
}

// Given the usage limiter refuses workflow activation with <text> — returns a
// function that puts the previous limiter back
export function withRefusingLimiter(text = 'No more workflows') {
  const key = '{Lightning.Services.AdapterHelper, :usage_limiter}';
  const was = onNode(`:persistent_term.get(${key}, nil)`).trim();
  onNode(`
    defmodule Lightning.Extensions.ScenarioRefusingLimiter do
      @behaviour Lightning.Extensions.UsageLimiting
      alias Lightning.Extensions.UsageLimiter

      def limit_action(%{type: :activate_workflow}, _context),
        do: {:error, :too_many_workflows, %Lightning.Extensions.Message{text: ${JSON.stringify(text)}}}

      def limit_action(action, context), do: UsageLimiter.limit_action(action, context)
      defdelegate check_limits(context), to: UsageLimiter
      defdelegate increment_ai_usage(session, usage), to: UsageLimiter
      defdelegate get_run_options(context), to: UsageLimiter
      defdelegate get_data_retention_periods(context), to: UsageLimiter
      defdelegate get_data_retention_message(context), to: UsageLimiter
    end
    :persistent_term.put(${key}, Lightning.Extensions.ScenarioRefusingLimiter)
  `);
  return () =>
    onNode(
      was === 'nil'
        ? `:persistent_term.erase(${key})`
        : `:persistent_term.put(${key}, ${was})`
    );
}

// When "<email>" creates a workflow named <name> in project <projectId>
// through Lightning (it must succeed)
export function createWorkflowOnNode(
  projectId: string,
  name: string,
  actorEmail: string
) {
  onNodeOk([
    `actor = Lightning.Repo.get!(Lightning.Accounts.User, "${user(actorEmail).id}")`,
    `{:ok, _} = Lightning.Workflows.save_workflow(%{name: ${JSON.stringify(name)}, project_id: "${projectId}"}, actor)`,
  ]);
}

// Given an external authentication provider "<name>" is configured — returns a function that removes it
export function withAuthProvider(name: string) {
  onNode(
    `Lightning.AuthProviders.Store.put_handler("${name}", %Lightning.AuthProviders.Handler{name: "${name}"})`
  );
  return () =>
    onNode(`Lightning.AuthProviders.Store.remove_handler("${name}")`);
}

// Given a password reset was asked for "<email>" — the path of the link its mail would carry
export function resetPasswordLinkFor(email: string) {
  const token = onNode(`
    user = Lightning.Accounts.get_user_by_email("${user(email).email}")
    {encoded, row} = Lightning.Accounts.UserToken.build_email_token(user, "reset_password", user.email)
    Lightning.Repo.insert!(row)
    encoded
  `).replace(/"/g, '');
  return `/users/reset_password/${token}`;
}

// Given "<email>" signed up <hours> hours ago and has not confirmed their email — returns a function that restores both
export function unconfirmedSince(email: string, hours: number) {
  const { id } = user(email);
  const [row] = sql<{ confirmed_at: string | null; inserted_at: string }>(
    `select confirmed_at, inserted_at from users where id = '${id}'`
  );
  exec(
    `update users set confirmed_at = null, inserted_at = now() at time zone 'utc' - interval '${hours} hours' where id = '${id}'`
  );
  return () =>
    exec(
      `update users set confirmed_at = ${literal(row.confirmed_at)}, inserted_at = ${literal(row.inserted_at)} where id = '${id}'`
    );
}

// Given "<email>"'s account is scheduled for deletion — returns a function that undoes it
export function scheduledForDeletion(email: string) {
  const { id } = user(email);
  exec(
    `update users set scheduled_deletion = now() at time zone 'utc' + interval '1 day' where id = '${id}'`
  );
  return () =>
    exec(`update users set scheduled_deletion = null where id = '${id}'`);
}

// Given "<email>"'s account is disabled — keepAccount puts it back
export function disableAccount(email: string) {
  exec(`update users set disabled = true where id = '${user(email).id}'`);
}

// When I log out from the account menu
export async function logOut(page: Page, email: string) {
  await open(page, '/projects');
  const [{ name }] = sql<{ name: string }>(
    `select first_name || ' ' || last_name as name from users where id = '${user(email).id}'`
  );
  await page.getByRole('button', { name: new RegExp(`${name}$`) }).click();
  await page.getByRole('menuitem', { name: 'Log out' }).click();
}

// The red or blue message inside the log in form
export const loginAlert = (page: Page) =>
  page
    .getByRole('button', { name: 'Log in' })
    .locator('xpath=ancestor::form')
    .getByRole('alert');

// The values in a Lightning session cookie. It is signed, not encrypted, so
// the middle segment decodes on the node.
export function sessionOf(cookieValue: string): Record<string, unknown> {
  const payload = decodeURIComponent(cookieValue).split('.')[1];
  const out = onNode(
    `"${payload}" |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term() |> Map.new(fn {k, v} -> {k, if(is_binary(v) and not String.valid?(v), do: Base.encode64(v), else: v)} end) |> Jason.encode!()`
  );
  return JSON.parse(JSON.parse(out)) as Record<string, unknown>;
}

// Given first setup is allowed and the instance has no superuser — returns a
// function that puts both back. The test using this is @serial.
export function firstSetupOpen() {
  const restoreFlag = withFlag('allow_first_setup', true);
  const ids = sql<{ id: string }>(
    `select id from users where role = 'superuser'`
  ).map(r => `'${r.id}'`);
  const set = (role: string) =>
    ids.length &&
    exec(`update users set role = '${role}' where id in (${ids.join(', ')})`);
  set('user');
  return () => {
    set('superuser');
    restoreFlag();
  };
}

// ---------------------------------------------------------------------------
// Workflows page (annotations/views/workflows-index.md)
// ---------------------------------------------------------------------------

/** Where the workflows page of a project lives, with an optional query. */
export const workflowsPath = (projectId: string, query = '') =>
  `/projects/${projectId}/w${query ? `?${query}` : ''}`;

// Given workflow "<name>" has one webhook trigger that is on or off (or no
// trigger at all), and is live or a draft (live when its trigger is on, unless
// said). Its trigger leads to the workflow's first job, so Lightning can save
// the workflow when a scenario switches it. Remove it with
// removeWorkflowData(projectId) before the project goes.
export function seedDashboardWorkflow(
  projectId: string,
  name: string,
  {
    triggers = 'on',
    state,
  }: { triggers?: 'on' | 'off' | 'none'; state?: 'live' | 'draft' } = {}
) {
  const wf = seedWorkflow(projectId, name);
  const triggerId = randomUUID();
  exec(`update workflows set state = '${state ?? (triggers === 'on' ? 'live' : 'draft')}'
          where id = '${wf.id}';
        ${
          triggers === 'none'
            ? ''
            : `insert into triggers (id, workflow_id, project_id, type, enabled, inserted_at, updated_at)
                 values ('${triggerId}', '${wf.id}', '${projectId}', 'webhook', ${triggers === 'on'}, ${NOW}, ${NOW});
               insert into workflow_edges (id, workflow_id, source_trigger_id, target_job_id, condition_type, enabled, inserted_at, updated_at)
                 values (gen_random_uuid(), '${wf.id}', '${triggerId}', '${Object.values(wf.jobs)[0]}', 'always', true, ${NOW}, ${NOW});`
        }`);
  return wf;
}

/** What is stored of a workflow: its state, name, when it was deleted and each trigger's on flag. */
export function workflowStored(id: string) {
  const [workflow] = sql<{
    state: string;
    name: string;
    deleted_at: string | null;
  }>(`select state, name, deleted_at from workflows where id = '${id}'`);
  const triggers = sql<{ enabled: boolean }>(
    `select enabled from triggers where workflow_id = '${id}'`
  ).map(t => t.enabled);
  return { ...workflow, triggers };
}

/** The audit events recorded for one item, newest first. */
export const auditEventsOf = (itemId: string) =>
  sql<{ event: string; actor_id: string | null }>(
    `select event, actor_id from audit_events where item_id = '${itemId}'
     order by inserted_at desc`
  );

/** The names of the workflows the list shows, top to bottom. */
export const listedWorkflows = (page: Page) =>
  page
    .getByRole('row')
    .filter({ has: page.getByRole('cell') })
    .evaluateAll(rows =>
      rows.map(row =>
        (row.querySelector('td') as HTMLElement).innerText.split('\n')[0].trim()
      )
    );

/** The heading above the list: "Workflows (<count>)". */
export const workflowsHeading = (page: Page, count?: number) =>
  page.getByRole('heading', {
    name: count === undefined ? /^Workflows \(\d+\)$/ : `Workflows (${count})`,
  });

/** The row of the workflow whose name reads <name>. */
export const workflowRow = (page: Page, name: string) =>
  page.getByRole('row').filter({ has: page.getByText(name, { exact: true }) });

const WORKFLOW_COLUMNS = [
  'name',
  'latest',
  'count',
  'failed',
  'state',
  'actions',
] as const;

/** One cell of a workflow's row. */
export const workflowCell = (
  row: Locator,
  column: (typeof WORKFLOW_COLUMNS)[number]
) => row.getByRole('cell').nth(WORKFLOW_COLUMNS.indexOf(column));

/** The on/off switch of a workflow's row. */
export const workflowSwitch = (row: Locator) => row.getByRole('switch');
// aria-checked is absent when the switch is off, so read the hidden checkbox.
export const workflowSwitchInput = (row: Locator) =>
  row.locator('input[type=checkbox]');

/** The card of a project total, found by its title. */
export const metricCard = (page: Page, title: string) =>
  page.getByRole('heading', { name: title, exact: true }).locator('xpath=..');

/** The query string of the page now, as name to value. */
export const queryOf = (page: Page) =>
  Object.fromEntries(new URL(page.url()).searchParams);

// Then <target> shows the tooltip <text> when pointed at
export async function expectTooltip(page: Page, target: Locator, text: string) {
  // A click hides the tooltip, and hovering where the pointer already is fires
  // no new mouseenter, so move away first.
  await page.mouse.move(0, 0);
  await target.hover();
  await expect(
    page.getByRole('tooltip').filter({ hasText: text })
  ).toBeVisible();
}

// When I type <term> in the workflows search box, key by key (it searches on
// key up, which filling the box does not send)
export async function typeInWorkflowSearch(page: Page, term: string) {
  const box = page.getByPlaceholder('Search', { exact: true });
  await box.click();
  await box.pressSequentially(term);
}

// When I click the clear search button, which is an icon with no name
export const clearWorkflowSearch = (page: Page) =>
  page.locator('#clear_search_button').click();

export const createWorkflowButton = (page: Page) =>
  page.getByRole('button', { name: 'Create new workflow' });

// When I point at a disabled button: it ignores the pointer, the wrapper
// around it carries the tooltip
export const hoverDisabled = (button: Locator) =>
  button.locator('xpath=..').hover();

// How a piece of text looks: its colour and the opacity it is drawn at,
// counting every ancestor's. Two names look different when this differs.
export async function lookOf(text: Locator) {
  return text.evaluate(el => {
    let opacity = 1;
    for (let n: Element | null = el; n; n = n.parentElement)
      opacity *= Number(getComputedStyle(n).opacity);
    return `${getComputedStyle(el).color} @ ${opacity}`;
  });
}

// When I confirm the next "Are you sure" prompt — resolves to what it asked
export function confirmNextPrompt(page: Page) {
  return new Promise<string>(resolve =>
    page.once('dialog', dialog => {
      resolve(dialog.message());
      void dialog.accept();
    })
  );
}
