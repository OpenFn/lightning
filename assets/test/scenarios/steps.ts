// Steps shared by annotation scenarios. They drive the real pages and read and
// seed the e2e database that the verify-lightning instance runs on.
//
// TARGET=demo runs the same specs against the openfn-ia-demo replica instead:
// hash routes, one fixed signed-in user, static fixtures and no server. A
// step it can't honour skips the test and says why.
import { execFileSync, spawn } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import {
  expect,
  test,
  type APIRequestContext,
  type Browser,
  type Dialog,
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
  await field(page, 'Email').fill(forWorker(email));
  await field(page, 'Password').fill(password);
  await page.getByRole('button', { name: 'Log in' }).click();
  await expect(page).not.toHaveURL(/\/users\/log_in/);
}

type LiveView = { isConnected(): boolean; isJoinPending(): boolean };
type LiveSocket = {
  main?: LiveView;
  execJS: (el: Element, js: string) => void;
};

// Waits for the page's LiveView to join, asking LiveView's own client
export async function liveViewJoined(page: Page) {
  await page.waitForFunction(() => {
    const { liveSocket } = window as unknown as { liveSocket?: LiveSocket };
    const main = liveSocket?.main;
    return !!main && main.isConnected() && !main.isJoinPending();
  });
}

// When I open "<path>" — waits for the LiveView socket to join
export async function open(page: Page, path: string) {
  if (onDemo) return void (await page.goto(`#${path}`));
  await page.goto(path);
  await liveViewJoined(page);
}

// When I reload the page
export async function reload(page: Page) {
  lightningOnly('needs a reload that keeps state: demo tokens live in memory');
  await page.reload();
  await liveViewJoined(page);
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
// A HEEx modal names the token on its button, so the forgery rewrites that and
// clicks. A modal without one gets the page's delete event sent straight down
// the LiveView socket, as a tampered client would.
export async function confirmDeletionNaming(page: Page, id: string) {
  lightningOnly('needs a server: a forged delete has nothing to reach');
  const yes = page.getByRole('button', { name: 'Yes' });
  await expect(yes).toBeVisible();
  if (await yes.getAttribute('phx-value-id')) {
    await yes.evaluate((el, id) => el.setAttribute('phx-value-id', id), id);
    await yes.click();
    return;
  }
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
  await page
    .getByRole('switch', { name: 'Enable multi-factor authentication' })
    .click();
  await clickable(page, 'this secret key').click();
  const secretModal = modal(page, 'Your two-factor secret');
  const secret = (await secretModal.getByRole('code').innerText()).trim();
  // Escape is unreliable here: pressed during the open transition, the dialog
  // stays up and blocks the form.
  await secretModal.getByRole('button', { name: 'Close' }).click();
  await expect(modalTitle(page, 'Your two-factor secret')).toBeHidden();
  // The page has several "Save" buttons; Enter submits the code's own form.
  const code = page.getByPlaceholder('XXXXXX');
  await code.fill(totpCode(secret));
  await code.press('Enter');
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
    .locator('#reauthentication-form input[type="password"]')
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

// The form control a visible label names, found by its label. Today's
// Lightning labels carry `for` but most inputs have no id, so the label isn't
// linked and getByLabel finds nothing there; for those the control is the next
// one after its label. Drop that fallback once the labels are linked.
// `within` narrows the search to a dialog or form when a label repeats.
export function field(within: Page | Locator, label: string) {
  return within
    .getByLabel(labelText(label))
    .or(
      labelled(within, label).locator(
        'xpath=following::*[self::select or self::textarea or self::input[not(@type="hidden")]][1]'
      )
    );
}

// The eye at the end of a password field, which shows or hides what was typed
export const passwordEye = (within: Page | Locator, label: string) =>
  field(within, label).locator('xpath=following-sibling::div[1]/*[1]');

// A label as shown, with or without the required-field asterisk
const labelText = (label: string) => new RegExp(`^\\s*${label}\\s*\\*?\\s*$`);

// Something the user clicks by its name, whether it's drawn as a button or a
// link: designs swap one for the other.
export function clickable(
  within: Page | Locator,
  name: string | RegExp,
  { exact }: { exact?: boolean } = {}
) {
  return within
    .getByRole('button', { name, exact })
    .or(within.getByRole('link', { name, exact }));
}

// A modal, found by its title. Ask its title whether it is open, not the
// dialog: the design system's dialog wrapper is 0x0, so Playwright calls the
// dialog itself hidden while its content shows.
export const modal = (page: Page, title: string) =>
  page.getByRole('dialog', { name: title });

// The open modal's title; hidden once the modal has closed
export const modalTitle = (page: Page, title: string) =>
  modal(page, title).getByRole('heading', { name: title });

export const submitButton = (within: Page | Locator, name: string) =>
  within.getByRole('button', { name, exact: true });

// When I submit the form with <name>. A page may refuse a bad form before
// the click (the button is off) or after it (the error comes back), so a
// disabled button is left alone and the Then says what the user sees.
export async function submit(within: Page | Locator, name: string) {
  const button = submitButton(within, name);
  await expect(button).toBeVisible();
  if (await button.isEnabled()) await button.click();
}

// The block holding a field's label, control and any error under it
export function fieldBlock(within: Page | Locator, label: string) {
  return labelled(within, label).locator('xpath=..');
}

const labelled = (within: Page | Locator, label: string) =>
  within.locator('label').filter({ hasText: labelText(label) });

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
  // Labelled by its hint. Today's "Disabled?" checkbox renders no label text
  // and sits before that hint, unlinked; drop the fallback once it's linked.
  const hint = 'A disabled user will not be allowed to login.';
  await admin
    .getByRole('checkbox', { name: hint })
    .or(
      admin
        .getByText(hint)
        .locator('xpath=preceding::input[@type="checkbox"][1]')
    )
    .check();
  await admin.getByRole('button', { name: 'Save' }).click();
  await expect
    .poll(() =>
      sql(`select disabled from users where id = '${user(email).id}'`)
    )
    .toEqual([{ disabled: true }]);
  await admin.context().close();
}

export type Mail = { to: string[]; subject: string; text: string | null };

// The mail the instance has sent, newest first, from Swoosh's dev mailbox
export async function mailbox(request: APIRequestContext): Promise<Mail[]> {
  lightningOnly('needs a server: the dev mailbox');
  const res = await request.get('/dev/mailbox/json');
  expect(res.ok(), '/dev/mailbox/json should answer').toBe(true);
  const { data } = (await res.json()) as {
    data: { to: string[]; subject: string; text_body: string | null }[];
  };
  // Recipients read '"Name" <address>' or a bare address
  return data.map(m => ({
    subject: m.subject,
    text: m.text_body,
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

// Removes project <id> with its members and credential shares, if it is still there
export const removeProject = (id: string) =>
  exec(`delete from project_users where project_id = '${id}';
        delete from project_credentials where project_id = '${id}';
        delete from projects where id = '${id}'`);

// Given project "<name>" exists with these members, by user id (seedUser's
// accounts), and this description, creation time and scheduled deletion
// (UTC, "YYYY-MM-DD HH:MM:SS") — returns its id and a function that removes it
export function seedProjectWith(
  name: string,
  members: Record<string, Role>,
  {
    description = null,
    insertedAt = null,
    scheduledDeletion = null,
  }: {
    description?: string | null;
    insertedAt?: string | null;
    scheduledDeletion?: string | null;
  } = {}
) {
  const id = randomUUID();
  const users = Object.entries(members).map(
    ([userId, role]) =>
      `insert into project_users (id, project_id, user_id, role, inserted_at, updated_at)
         values (gen_random_uuid(), '${id}', '${userId}', '${role}', now(), now());`
  );
  const at = insertedAt ? `'${insertedAt}'` : 'now()';
  exec(`insert into projects (id, name, description, scheduled_deletion, inserted_at, updated_at)
          values ('${id}', ${literal(name)}, ${literal(description)},
                  ${scheduledDeletion ? `'${scheduledDeletion}'` : 'null'}, ${at}, ${at});
        ${users.join('\n')}`);
  return { id, name, remove: () => removeProject(id) };
}

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
  await liveViewJoined(page);
}

// When a "sort" event arrives with column "<column>": a crafted LiveView push
// sent from the <header> column's sort control. Where the table sorts in the
// browser the server has no sort event, so this checks that an unknown event
// leaves the page working.
export async function sortByColumnNamed(
  page: Page,
  header: string,
  column: string
) {
  lightningOnly('needs a server: a crafted event has nothing to reach');
  await clickable(page.getByRole('columnheader'), header).evaluate(
    (el, by) =>
      (window as unknown as { liveSocket: LiveSocket }).liveSocket.execJS(
        el,
        JSON.stringify([['push', { event: 'sort', value: { by } }]])
      ),
    column
  );
}

// Watches what the page's LiveView sends and what the server answers. Call it
// before the page opens. `crashes()` counts the times the server reported the
// LiveView crashed; `answered(n)` waits until at least n events have been sent
// and the server has answered each one, with a reply or a crash.
export function watchLiveView(page: Page) {
  const pending = new Set<string>();
  let sent = 0;
  let crashes = 0;
  const frame = (payload: string | Buffer) =>
    typeof payload === 'string' ? (JSON.parse(payload) as unknown[]) : [];
  page.on('websocket', ws => {
    if (!ws.url().includes('/live/websocket')) return;
    ws.on('framesent', ({ payload }) => {
      const [, ref, , event] = frame(payload);
      if (event !== 'event') return;
      sent++;
      pending.add(ref as string);
    });
    ws.on('framereceived', ({ payload }) => {
      const [, ref, , event] = frame(payload);
      if (event === 'phx_reply') pending.delete(ref as string);
      if (event === 'phx_error') {
        crashes++;
        pending.clear();
      }
    });
  });
  return {
    events: () => sent,
    crashes: () => crashes,
    answered: (n: number) =>
      expect
        .poll(() => sent >= n && pending.size === 0, 'server answered')
        .toBe(true),
  };
}

// When I submit a form by clicking <submit>, with an extra field "<name>" set
// to "<value>" in the request: a crafted request, made by rewriting the
// LiveView event the click sends, whatever shape the page gives it (form
// fields, or a value pushed from a component). Call it before the page opens;
// it returns the submit step.
export async function submittingExtraField(
  page: Page,
  name: string,
  value: string
) {
  lightningOnly('needs a server: a crafted request has nothing to reach');
  let armed = false;
  let added = 0;
  // [join_ref, ref, topic, "event", { type, event, value }]
  const withField = (message: string) => {
    const frame = JSON.parse(message);
    const payload = frame[3] === 'event' ? frame[4] : undefined;
    if (payload?.type === 'form' && typeof payload.value === 'string') {
      // Nest it like the form's own fields: "project[raw_name]" gives
      // "project[parent_id]"
      const params = new URLSearchParams(payload.value);
      const scope = [...params.keys()]
        .filter(key => !key.startsWith('_'))
        .map(key => key.match(/^(\w+)\[/)?.[1])
        .find(Boolean);
      params.append(scope ? `${scope}[${name}]` : name, value);
      payload.value = params.toString();
    } else if (payload?.value && typeof payload.value === 'object') {
      payload.value[name] = value;
    } else return message;
    added++;
    return JSON.stringify(frame);
  };
  await page.routeWebSocket(/\/live\/websocket/, ws => {
    const server = ws.connectToServer();
    ws.onMessage(message =>
      server.send(
        armed && typeof message === 'string' ? withField(message) : message
      )
    );
  });
  return async (submit: Locator) => {
    armed = true;
    await submit.click();
    await expect
      .poll(() => added, `"${name}" was added to the request`)
      .toBeGreaterThan(0);
  };
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
// ids that passed on this page (and @passing-new when they pass on the port
// too), @pending for the rest.
export function tagFor(id: string, passing: readonly string[]): string;
export function tagFor(
  id: string,
  passing: readonly string[],
  onPort: true
): string | string[];
export function tagFor(
  id: string,
  passing: readonly string[],
  onPort = false
): string | string[] {
  if (!passing.includes(id)) return '@pending';
  return onPort ? ['@passing-old', '@passing-new'] : '@passing-old';
}

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

// Given a failure alert for the workflow was emailed to "<email>", about this
// work order and run (made-up ones if not given)
export function sendFailureAlertOnNode(
  projectId: string,
  wf: Pick<SeededWorkflow, 'id' | 'name'>,
  email: string,
  about?: { workOrderId: string; runId: string }
) {
  const id = (v?: string) => (v ? `"${v}"` : 'Ecto.UUID.generate()');
  onNodeOk([
    `recipient = Lightning.Repo.get!(Lightning.Accounts.User, "${user(email).id}")`,
    `project = Lightning.Projects.get_project!("${projectId}")`,
    `Lightning.FailureAlerter.alert(%{"workflow_id" => "${wf.id}", "workflow_name" => "${wf.name}", "project" => project, "work_order_id" => ${id(about?.workOrderId)}, "run_id" => ${id(about?.runId)}, "recipient" => recipient})`,
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

// When I click a work order's row, which opens its runs (both versions put
// them in the table row after it)
export async function expandWorkOrder(page: Page, id: string) {
  await historyCell(historyRow(page, id), 'Status').click();
  await expect(
    page.locator(`#toggle_details_for_${id} + tr [id^="run_"]`).first()
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

/** The stand-in for a retry button that is not available, named by why. */
export const disabledRetry = (page: Page, workOrderId: string) =>
  historyCell(historyRow(page, workOrderId), 'Runs').getByLabel(
    /not authorized to start runs|cannot be rerun/
  );

// When I point at a control that is off: the pointer goes where it is, even
// though the control itself ignores it (the tooltip sits on what is under it)
export const pointAt = (control: Locator) => control.hover({ force: true });

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

/** What carries the tooltip of a disabled bulk action: today a wrapper named
 * by it, in the design system the button, which it describes. */
export const tipOf = (page: Page, text: string) =>
  page.locator(`[aria-label="${text}"], [aria-description="${text}"]`);

/** The filter chip whose button reads <name>. */
export const chip = (page: Page, name: string | RegExp) =>
  page
    .getByRole('button', { name })
    .locator('xpath=ancestor::*[contains(@id, "-filter-chip")][1]');

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
  // Ticked once the server has applied it (the design system's box shows the
  // filter it is sent back), so click and wait rather than check()
  for (const label of labels) {
    const box = page.getByRole('checkbox', { name: label, exact: true });
    await box.click();
    await expect(box).toBeChecked();
  }
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
// nothing on it offers that action. The sortable column header <header> sends
// an event named by its phx-click; repoint it and click.
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

// When I click <control> as a tampered client would: the event it sends
// carries <values> in place of the page's own. Call it before the page opens;
// it returns the click step. Only the first event after the click is changed.
export async function sendingValues(
  page: Page,
  values: Record<string, string>
) {
  lightningOnly('needs a server: a forged event has nothing to reach');
  let armed = false;
  let changed = 0;
  // [join_ref, ref, topic, "event", { type, event, value }]
  const withValues = (message: string) => {
    const frame = JSON.parse(message);
    const value = frame[3] === 'event' ? frame[4]?.value : undefined;
    if (!value || typeof value !== 'object') return message;
    Object.assign(value, values);
    armed = false;
    changed++;
    return JSON.stringify(frame);
  };
  await page.routeWebSocket(/\/live\/websocket/, ws => {
    const server = ws.connectToServer();
    ws.onMessage(message =>
      server.send(
        armed && typeof message === 'string' ? withValues(message) : message
      )
    );
  });
  return async (control: Locator) => {
    const before = changed;
    armed = true;
    await control.click();
    await expect.poll(() => changed, 'the event was changed').toBe(before + 1);
  };
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

/** The duration shown for a step, run or work order inside <within>:
 * "212 ms", "4 s", "2 m", "1 h" or "Not started". */
export const elapsedOf = (within: Locator) =>
  within.getByText(/^\s*(\d+ (ms|s|m|h)|Not started)\s*$/);

/** The time a run's header shows, in its relative detailed form. Today's is
 * marked by its format; the design system's is the first timestamp in the
 * run (each one is a button that copies it), held by the header's text. */
export const runTimestamp = (page: Page, runId: string) =>
  historyRun(page, runId)
    .locator('[data-format="relative_detailed"]')
    .or(
      historyRun(page, runId)
        .getByRole('button', { name: /\d:\d\d/ })
        .first()
        .locator('xpath=..')
    );

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

export type UserSeed = {
  firstName?: string;
  lastName?: string;
  role?: 'user' | 'superuser';
  disabled?: boolean;
  supportUser?: boolean;
  /** UTC, "YYYY-MM-DD HH:MM:SS" */
  scheduledDeletion?: string;
};
export type SeededUser = { id: string; email: string; remove: () => void };

// Given "<prefix>-…@example.org" is an account like this, with the seeded
// password. The email is new each time, as every worker sees every account.
// remove() deletes it again, if it is still there.
export function seedUser(prefix: string, seed: UserSeed = {}): SeededUser {
  const id = randomUUID();
  const email = `${prefix}-${id.slice(0, 8)}@example.org`;
  exec(`insert into users (id, email, first_name, last_name, hashed_password, role,
          disabled, support_user, scheduled_deletion, confirmed_at, inserted_at, updated_at)
        select '${id}', '${email}', ${literal(seed.firstName ?? 'Amara')},
          ${literal(seed.lastName ?? 'Diallo')}, hashed_password, '${seed.role ?? 'user'}',
          ${seed.disabled ?? false}, ${seed.supportUser ?? false},
          ${seed.scheduledDeletion ? `'${seed.scheduledDeletion}'` : 'null'}, now(), now(), now()
        from users where id = '${user('super@openfn.org').id}'`);
  return {
    id,
    email,
    remove: () =>
      exec(`delete from user_tokens where user_id = '${id}';
            delete from users where id = '${id}'`),
  };
}

// Given <userId> has started a run (in a project of its own) — returns a
// function that removes it again. Remove it before the account.
export function runStartedBy(userId: string) {
  const project = seedProject('Activity', {});
  const wf = seedWorkflow(project.id);
  const workOrderId = seedWorkOrder(wf, {
    state: 'success',
    runs: [{ state: 'success' }],
  });
  exec(
    `update runs set created_by_id = '${userId}' where work_order_id = '${workOrderId}'`
  );
  return () => {
    removeWorkflowData(project.id);
    project.remove();
  };
}

// When the page receives <event> with <value>, as a tampered client would send
// it: pushed from the LiveView root (an open modal hides the rest of the page
// from the accessibility tree), or to the component that holds `target` (a
// selector). Waits for the server to answer. `lv` is watchLiveView(page), set
// up before the page opened.
export async function pushEvent(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  event: string,
  value: Record<string, unknown>,
  target?: string
) {
  lightningOnly('needs a server: a crafted request has nothing to reach');
  const before = lv.events();
  await page
    .locator('[data-phx-main]')
    .evaluate(
      (el, js) =>
        (window as unknown as { liveSocket: LiveSocket }).liveSocket.execJS(
          el,
          js
        ),
      JSON.stringify([['push', { event, value, ...(target && { target }) }]])
    );
  await lv.answered(before + 1);
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

// When I click <control> and confirm "Are you sure" — resolves to what I was
// asked. Today the browser asks; the design system asks in a dialog titled
// <title> and confirmed with a button of the same name.
export async function clickAndConfirm(
  page: Page,
  control: Locator,
  title: string
) {
  let asked: string | undefined;
  const accept = (d: Dialog) => {
    asked = d.message();
    void d.accept();
  };
  page.once('dialog', accept);
  await control.click();
  const heading = modalTitle(page, title);
  await expect
    .poll(async () => asked !== undefined || (await heading.isVisible()))
    .toBe(true);
  if (asked !== undefined) return asked;
  page.off('dialog', accept);
  const dialog = modal(page, title);
  const question = await dialog.innerText();
  const confirm = title.split(' ')[0];
  await dialog.getByRole('button', { name: confirm, exact: true }).click();
  return question;
}

// ---------------------------------------------------------------------------
// Sandboxes page (annotations/views/sandboxes-index.md)
// ---------------------------------------------------------------------------

export const sandboxesPath = (projectId: string) =>
  `/projects/${projectId}/sandboxes`;

// A project in a seeded workspace. The root gets `members`; each sandbox is
// provisioned through Lightning by the workspace's `by` user, so it starts
// with the parent's members and copies of its workflows, credentials and
// collections, and its `members` then change roles on top (null removes).
// `workflows`, `credentials` and `collections` are added to this project
// after it exists and before its own sandboxes, so those copy them.
export type WorkspaceSeed = {
  name: string;
  members?: Record<string, Role | null>;
  env?: string | null;
  color?: string;
  allowSupportAccess?: boolean;
  workflows?: string[];
  credentials?: string[];
  collections?: string[];
  scheduledInDays?: number;
  sandboxes?: WorkspaceSeed[];
};

const ex = (v: unknown) => JSON.stringify(v);
const exUser = (email: string) =>
  `Lightning.Repo.get!(Lightning.Accounts.User, ${ex(user(email).id)})`;

// A workflow with one job and an enabled cron trigger, saved through
// Lightning so it has a version
const exWorkflow = (project: string, name: string, by: string) =>
  `{:ok, _} = Lightning.Workflows.save_workflow(%{name: ${ex(name)}, project_id: ${project}.id,
     jobs: [%{id: Ecto.UUID.generate(), name: "Step", body: "fn(s => s)", adaptor: "@openfn/language-common@latest"}],
     triggers: [%{type: :cron, cron_expression: "0 * * * *", enabled: true}]}, ${by})`;

// Given this workspace exists, built by "<by>" — returns each project's id by
// name, and a function that removes the whole workspace again
export function seedWorkspace(seed: WorkspaceSeed, by: string) {
  const lines = [`import Ecto.Query`, `by = ${exUser(by)}`, `ids = %{}`];
  const credentials: string[] = [];
  let n = 0;
  const build = (s: WorkspaceSeed, parent: string | null) => {
    const v = `p${n++}`;
    if (parent === null) {
      const members = Object.entries(s.members || {}).filter(([, r]) => r);
      lines.push(
        `${v} = Lightning.Repo.insert!(%Lightning.Projects.Project{name: ${ex(s.name)},
           allow_support_access: ${!!s.allowSupportAccess},
           project_users: [${members
             .map(
               ([e, r]) =>
                 `%Lightning.Projects.ProjectUser{user_id: ${ex(user(e).id)}, role: :${r}}`
             )
             .join(', ')}]})`
      );
    } else {
      lines.push(
        `{:ok, ${v}} = Lightning.Projects.Sandboxes.provision(${parent}, by, %{name: ${ex(s.name)}, color: ${ex(s.color || '#5AA1F0')}, env: "dev"})`
      );
      for (const [e, r] of Object.entries(s.members || {})) {
        const uid = ex(user(e).id);
        lines.push(
          `Lightning.Repo.delete_all(from pu in Lightning.Projects.ProjectUser, where: pu.project_id == ^${v}.id and pu.user_id == ^${uid})`
        );
        if (r)
          lines.push(
            `Lightning.Repo.insert!(%Lightning.Projects.ProjectUser{project_id: ${v}.id, user_id: ${uid}, role: :${r}})`
          );
      }
    }
    lines.push(
      `${v} |> Ecto.Changeset.change(%{env: ${s.env === undefined ? (parent ? '"dev"' : 'nil') : s.env === null ? 'nil' : ex(s.env)}, color: ${parent || s.color ? ex(s.color || '#5AA1F0') : 'nil'}, allow_support_access: ${!!s.allowSupportAccess}}) |> Lightning.Repo.update!()`
    );
    for (const w of s.workflows || []) lines.push(exWorkflow(v, w, 'by'));
    for (const c of s.credentials || []) {
      credentials.push(c);
      lines.push(
        `{:ok, _} = Lightning.Credentials.create_credential(%{name: ${ex(c)}, schema: "raw", body: %{}, user_id: by.id, project_credentials: [%{project_id: ${v}.id}]}, by)`
      );
    }
    for (const c of s.collections || [])
      lines.push(
        `Lightning.Repo.insert!(%Lightning.Collections.Collection{name: ${ex(c)}, project_id: ${v}.id})`
      );
    lines.push(`ids = Map.put(ids, ${ex(s.name)}, ${v}.id)`);
    for (const child of s.sandboxes || []) build(child, v);
    // Scheduled last, so its own sandboxes could still be provisioned
    if (s.scheduledInDays !== undefined)
      lines.push(
        `Lightning.Repo.query!("update projects set scheduled_deletion = now() + ($2::int * interval '1 second') where id = $1", [Ecto.UUID.dump!(${v}.id), ${s.scheduledInDays * 86400 + 3600}])`
      );
  };
  build(seed, null);
  lines.push(`Jason.encode!(ids)`);
  // The node's log lines come back too; the result is the last line
  const out = onNode(lines.join('\n')).trim().split('\n').pop()!;
  const ids = JSON.parse(JSON.parse(out)) as Record<string, string>;
  const rootId = ids[seed.name];
  return {
    ids,
    id: (name: string) => {
      const id = ids[name] ?? projectIdIn(rootId, name);
      if (!id) throw new Error(`no project "${name}" in the workspace`);
      return id;
    },
    remove: () => removeWorkspace(rootId, by, credentials),
  };
}

// The id of the project called <name> in the workspace under <rootId>, such
// as one a test created through the page
export function projectIdIn(rootId: string, name: string) {
  return sql<{ id: string }>(
    `with recursive tree as (select id from projects where id = '${rootId}'
       union all select p.id from projects p join tree on p.parent_id = tree.id)
     select p.id from projects p join tree using (id) where p.name = ${literal(name)}`
  )[0]?.id as string | undefined;
}

// Removes a seeded workspace, deepest sandboxes first, and the credentials
// its builder made for it
function removeWorkspace(rootId: string, by: string, credentials: string[]) {
  onNodeOk([
    `import Ecto.Query`,
    `ids = ["${rootId}" | Lightning.Projects.descendant_ids(["${rootId}"])]`,
    `for id <- Enum.sort_by(ids, &Lightning.Projects.depth_of/1, :desc), p = Lightning.Repo.get(Lightning.Projects.Project, id), do: {:ok, _} = Lightning.Projects.delete_project(p)`,
    `Lightning.Repo.delete_all(from c in Lightning.Credentials.Credential, where: c.user_id == ^${ex(user(by).id)} and c.name in ^${ex(credentials)})`,
  ]);
}

// Given workflow <name> is added to project <projectId>, created <daysAgo>
// days ago (backdated after the save)
export function addWorkflowOnNode(
  projectId: string,
  name: string,
  by: string,
  { daysAgo }: { daysAgo?: number } = {}
) {
  onNodeOk([
    `p = Lightning.Repo.get!(Lightning.Projects.Project, "${projectId}")`,
    exWorkflow('p', name, exUser(by)),
  ]);
  if (daysAgo)
    exec(`update workflows set inserted_at = now() - interval '${daysAgo} days'
          where project_id = '${projectId}' and name = ${literal(name)}`);
}

// When "<by>" changes workflow <name> in project <projectId> and saves it, so
// it gets a new version
export function changeWorkflowOnNode(
  projectId: string,
  name: string,
  by: string
) {
  onNodeOk([
    `import Ecto.Query`,
    `wf = Lightning.Repo.one!(from w in Lightning.Workflows.Workflow, where: w.project_id == ^"${projectId}" and w.name == ^${ex(name)} and is_nil(w.deleted_at), preload: [:jobs, :triggers, :edges])`,
    `[job | _] = wf.jobs`,
    `{:ok, _} = wf |> Lightning.Workflows.Workflow.changeset(%{jobs: [%{id: job.id, body: "fn(s => ({ ...s, at: ${Date.now()} }))"}]}) |> Lightning.Workflows.save_workflow(${exUser(by)})`,
  ]);
}

// Given a collection <name> in project <projectId>
export function addCollectionOnNode(projectId: string, name: string) {
  onNodeOk([
    `Lightning.Repo.insert!(%Lightning.Collections.Collection{name: ${ex(name)}, project_id: "${projectId}"})`,
  ]);
}

// Given the sandboxes of project <projectId> can be nested at most <depth>
// levels deep — returns a function that puts the setting back
export function withSandboxNestingDepth(depth: number) {
  const was = onNode(
    `Application.get_env(:lightning, :max_sandbox_nesting_depth)`
  ).trim();
  onNode(
    `Application.put_env(:lightning, :max_sandbox_nesting_depth, ${depth})`
  );
  return () =>
    onNode(
      was === 'nil'
        ? `Application.delete_env(:lightning, :max_sandbox_nesting_depth)`
        : `Application.put_env(:lightning, :max_sandbox_nesting_depth, ${was})`
    );
}

// Given the usage limiter refuses <action> (:new_sandbox, :new_collection)
// with <text> — returns a function that puts the previous limiter back
export function withLimiterRefusing(action: string, text: string) {
  const key = '{Lightning.Services.AdapterHelper, :usage_limiter}';
  const was = onNode(`:persistent_term.get(${key}, nil)`).trim();
  onNode(`
    defmodule Lightning.Extensions.ScenarioActionLimiter do
      @behaviour Lightning.Extensions.UsageLimiting
      alias Lightning.Extensions.UsageLimiter

      def limit_action(%{type: type}, _context) when type == :${action},
        do: {:error, :too_many, %Lightning.Extensions.Message{text: ${ex(text)}}}

      def limit_action(action, context), do: UsageLimiter.limit_action(action, context)
      defdelegate check_limits(context), to: UsageLimiter
      defdelegate increment_ai_usage(session, usage), to: UsageLimiter
      defdelegate get_run_options(context), to: UsageLimiter
      defdelegate get_data_retention_periods(context), to: UsageLimiter
      defdelegate get_data_retention_message(context), to: UsageLimiter
    end
    :persistent_term.put(${key}, Lightning.Extensions.ScenarioActionLimiter)
  `);
  return () =>
    onNode(
      was === 'nil'
        ? `:persistent_term.erase(${key})`
        : `:persistent_term.put(${key}, ${was})`
    );
}

// Where the old and new sandboxes pages differ. Everything below that knows
// how either page is built lives here, so a redesign only changes this block.
// The two pages share these ids, which name a sandbox's controls where
// nothing else can tell one card's "Edit" from the next card's:
// branch-rewire-sandbox-<id>, edit-sandbox-<id>, delete-sandbox-<id> and
// cancel-deletion-sandbox-<id>.

// A sandbox's name on its card
export const sandboxName = (page: Page, name: string) =>
  page.getByRole('heading', { name, exact: true });

// A live card, which opens the project when clicked: its name and badges
export const sandboxCard = (page: Page, name: string) =>
  page.getByRole('button').filter({ has: sandboxName(page, name) });

const actionIds = {
  merge: 'branch-rewire-sandbox',
  edit: 'edit-sandbox',
  delete: 'delete-sandbox',
} as const;

// The hover target of a sandbox's merge, edit or delete action: where its
// tooltip opens, enabled or not
export const sandboxActionTarget = (
  page: Page,
  id: string,
  action: keyof typeof actionIds
) => page.locator(`#${actionIds[action]}-${id}`);

// A sandbox's merge, edit or delete action. Today's Lightning gives the
// button no name; its label sits on the wrapper.
export const sandboxAction = (
  page: Page,
  id: string,
  action: keyof typeof actionIds
) => sandboxActionTarget(page, id, action).getByRole('button');

// A scheduled sandbox's Restore button
export const restoreButton = (page: Page, id: string) =>
  page
    .locator(`#cancel-deletion-sandbox-${id}`)
    .getByRole('button', { name: 'Restore' });

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystemSandboxes = async (page: Page) =>
  (await page.locator('#sandboxes-index-page').count()) > 0;

// A row of the merge modal's workflow, credential or collection lists
export const mergeRow = (dialog: Locator, name: string) =>
  dialog
    .getByRole('listitem')
    .filter({ has: dialog.page().getByText(name, { exact: true }) });

// When I tick or untick a row of the merge modal (by its text, the way a
// user does: today's rows take the click on the row, not the box)
export const toggleMergeRow = (dialog: Locator, name: string) =>
  mergeRow(dialog, name).getByText(name, { exact: true }).click();

// The merge target picker: today a listbox behind a button, on the design
// system a native select
export async function mergeTargets(dialog: Locator) {
  const select = dialog.getByRole('combobox');
  const options = (await select.count())
    ? select.getByRole('option')
    : dialog.getByRole('option', { includeHidden: true });
  return (await options.allTextContents())
    .map(t => t.trim())
    .filter(t => t && t !== 'Select a project');
}

// The target the merge picker shows as chosen ("" when none)
export async function chosenMergeTarget(dialog: Locator) {
  const select = dialog.getByRole('combobox');
  if (await select.count())
    return (
      await select.evaluate(
        el => (el as HTMLSelectElement).selectedOptions[0]?.text ?? ''
      )
    ).trim();
  return (await dialog.locator('[aria-haspopup="listbox"]').innerText()).trim();
}

// When I choose <name> as the merge target
export async function chooseMergeTarget(dialog: Locator, name: string) {
  const select = dialog.getByRole('combobox');
  if (await select.count())
    return void (await select.selectOption({ label: name }));
  await dialog.locator('[aria-haspopup="listbox"]').click();
  await dialog.getByRole('option', { name, exact: true }).click();
}

type SandboxRequest =
  | { kind: 'delete'; id: string; name: string }
  | { kind: 'restore'; id: string }
  | {
      kind: 'merge';
      id: string;
      targetId: string;
      workflowIds?: string[];
      deletedWorkflowIds?: string[];
    };

// When the page receives a delete, restore or merge request for a sandbox,
// as a tampered client would send it, whatever the page offers. Waits for the
// server to answer every event. `lv` is watchLiveView(page), set up before
// the page opened.
export async function sendSandboxRequest(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  request: SandboxRequest
) {
  lightningOnly('needs a server: a crafted request has nothing to reach');
  // The page's LiveView root: a modal hides the rest of the page from the
  // accessibility tree
  const from = page.locator('[data-phx-main]');
  const designSystem = await isDesignSystemSandboxes(page);
  const events: [string, Record<string, unknown>][] =
    request.kind === 'restore'
      ? [['cancel-sandbox-deletion', { id: request.id }]]
      : request.kind === 'delete'
        ? designSystem
          ? [
              [
                'delete-sandbox',
                { id: request.id, nameConfirmation: request.name },
              ],
            ]
          : [
              ['open-delete-modal', { id: request.id }],
              ['confirm-delete', { confirm: { name: request.name } }],
            ]
        : designSystem
          ? [
              [
                'merge-sandbox',
                {
                  id: request.id,
                  targetId: request.targetId,
                  workflowIds: request.workflowIds ?? [],
                  deletedWorkflowIds: request.deletedWorkflowIds ?? [],
                  credentialIds: [],
                  skippedCollectionNames: [],
                },
              ],
            ]
          : [
              ['open-merge-modal', { id: request.id }],
              ...(request.deletedWorkflowIds ?? []).map(
                id =>
                  ['toggle-workflow', { id }] as [
                    string,
                    Record<string, unknown>,
                  ]
              ),
              ['confirm-merge', { merge: { target_id: request.targetId } }],
            ];
  for (const [event, value] of events) {
    const before = lv.events();
    await from.evaluate(
      (el, js) =>
        (window as unknown as { liveSocket: LiveSocket }).liveSocket.execJS(
          el,
          js
        ),
      JSON.stringify([['push', { event, value }]])
    );
    await lv.answered(before + 1);
  }
}

// The workflows of project <projectId> by name, live ones only
export const workflowsOf = (projectId: string) =>
  sql<{ id: string; name: string }>(
    `select id, name from workflows where project_id = '${projectId}'
     and deleted_at is null order by name`
  );

// Whether project <projectId> is scheduled for deletion, and when
export const scheduledDeletionOf = (projectId: string) =>
  sql<{ at: string | null }>(
    `select scheduled_deletion as at from projects where id = '${projectId}'`
  )[0]?.at ?? null;

// ---------------------------------------------------------------------------
// Channels (channels-index; the channel logs and request pages can reuse it)
// ---------------------------------------------------------------------------

export const channelsPath = (projectId: string) =>
  `/projects/${projectId}/channels`;

// Given project <projectId> has webhook auth method <name> (an API key),
// made by "<by>" — returns its id
export function addWebhookAuthMethodOnNode(
  projectId: string,
  name: string,
  by: string
) {
  const out = onNode(
    `{:ok, w} = Lightning.WebhookAuthMethods.create_auth_method(%{name: ${ex(name)}, auth_type: :api, project_id: ${ex(projectId)}}, actor: ${exUser(by)})
     w.id`
  );
  return JSON.parse(out.trim().split('\n').pop()!) as string;
}

// A channel in a project. `clients` are webhook auth method names and
// `credential` a credential name, both already in the project. `requests`
// are logged requests by start time (UTC, "YYYY-MM-DD HH:MM:SS"); `wiped`
// ones were stored without their payloads.
export type ChannelSeed = {
  name: string;
  destination?: string;
  enabled?: boolean;
  clients?: string[];
  credential?: string;
  requests?: { at: string; wiped?: boolean }[];
};

// Given project <projectId> has this channel, made by "<by>" through
// Lightning (so it is audited) — returns its id
export function seedChannel(projectId: string, seed: ChannelSeed, by: string) {
  const pid = ex(projectId);
  const attrs = [
    `name: ${ex(seed.name)}`,
    `destination_url: ${ex(seed.destination ?? 'https://destination.example.com/data')}`,
    `project_id: ${pid}`,
    `enabled: ${seed.enabled ?? true}`,
    `client_auth_methods: Enum.map(${ex(seed.clients ?? [])}, &%{webhook_auth_method_id: Lightning.Repo.one!(from w in Lightning.Workflows.WebhookAuthMethod, where: w.project_id == ^${pid} and w.name == ^&1, select: w.id)})`,
    ...(seed.credential
      ? [
          `destination_auth_method: %{project_credential_id: Lightning.Repo.one!(from pc in Lightning.Projects.ProjectCredential, join: c in assoc(pc, :credential), where: pc.project_id == ^${pid} and c.name == ^${ex(seed.credential)}, select: pc.id)}`,
        ]
      : []),
  ];
  const requests = (seed.requests ?? []).map(
    r =>
      `Lightning.Repo.insert!(%Lightning.Channels.ChannelRequest{channel_id: c.id, channel_snapshot_id: s.id, request_id: Ecto.UUID.generate(), state: :success, started_at: DateTime.from_naive!(~N[${r.at.includes('.') ? r.at : `${r.at}.000000`}], "Etc/UTC"), is_wiped: ${!!r.wiped}})`
  );
  const out = onNode(
    [
      `import Ecto.Query`,
      `{:ok, c} = Lightning.Channels.create_channel(%{${attrs.join(', ')}}, actor: ${exUser(by)})`,
      `{:ok, s} = Lightning.Channels.get_or_create_current_snapshot(c)`,
      ...requests,
      `c.id`,
    ].join('\n')
  );
  return JSON.parse(out.trim().split('\n').pop()!) as string;
}

// Removes the channels of project <projectId> and their logged requests,
// which would otherwise stop the project being deleted
export const removeChannelsOf = (projectId: string) =>
  exec(`delete from channel_requests where channel_id in
          (select id from channels where project_id = '${projectId}');
        delete from channels where project_id = '${projectId}'`);

// The channels of project <projectId> by name
export const channelsOf = (projectId: string) =>
  sql<{ id: string; name: string; destination_url: string; enabled: boolean }>(
    `select id, name, destination_url, enabled from channels
     where project_id = '${projectId}' order by name`
  );

// What a channel is attached to: its client methods and destination
// credential, by name
export const channelAuthOf = (channelId: string) => {
  const rows = sql<{ role: string; name: string }>(
    `select cam.role, coalesce(w.name, c.name) as name
     from channel_auth_methods cam
     left join webhook_auth_methods w on w.id = cam.webhook_auth_method_id
     left join project_credentials pc on pc.id = cam.project_credential_id
     left join credentials c on c.id = pc.credential_id
     where cam.channel_id = '${channelId}' order by name`
  );
  return {
    clients: rows.filter(r => r.role === 'client').map(r => r.name),
    destination: rows.filter(r => r.role === 'destination').map(r => r.name),
  };
};

// The id of the project credential that shares credential <name> with
// project <projectId>
export const projectCredentialId = (projectId: string, name: string) =>
  sql<{ id: string }>(
    `select pc.id from project_credentials pc join credentials c on c.id = pc.credential_id
     where pc.project_id = '${projectId}' and c.name = ${literal(name)}`
  )[0]?.id;

// ---------------------------------------------------------------------------
// Collections (annotations/views/admin-collections.md)
// ---------------------------------------------------------------------------

export type CollectionSeed = { records?: number; bytes?: number };

// Given project <projectId> has a collection <name> with <records> records,
// using <bytes> bytes of storage — returns its id. Removing the project
// removes the collection and its records.
export function seedCollection(
  projectId: string,
  name: string,
  { records = 0, bytes }: CollectionSeed = {}
) {
  const id = randomUUID();
  const items = Array.from(
    { length: records },
    (_, i) => `%{"key" => "key-${i + 1}", "value" => "value-${i + 1}"}`
  );
  onNodeOk([
    `c = Lightning.Repo.insert!(%Lightning.Collections.Collection{id: "${id}", name: ${ex(name)}, project_id: "${projectId}"})`,
    ...(records
      ? [`{:ok, _} = Lightning.Collections.put_all(c, [${items.join(', ')}])`]
      : []),
  ]);
  if (bytes !== undefined)
    exec(`update collections set byte_size_sum = ${bytes} where id = '${id}'`);
  return id;
}

// Every collection called <name>: its id, project and number of records
export const collectionsCalled = (name: string) =>
  sql<{ id: string; project_id: string; records: number }>(
    `select c.id, c.project_id,
       (select count(*)::int from collection_items i where i.collection_id = c.id) as records
     from collections c where c.name = ${literal(name)} order by c.project_id`
  );

// The collection with id <id>, if it is still there
export const collectionById = (id: string) =>
  sql<{ name: string; project_id: string; records: number }>(
    `select c.name, c.project_id,
       (select count(*)::int from collection_items i where i.collection_id = c.id) as records
     from collections c where c.id = '${id}'`
  )[0];

// The records left behind by collection <id>
export const recordsOfCollection = (id: string) =>
  sql<{ n: number }>(
    `select count(*)::int as n from collection_items where collection_id = '${id}'`
  )[0].n;

// Given project <projectId> is at its plan's collection limit: creating a
// collection there is refused with <text>; other projects are unaffected.
// Returns a function that puts the previous collection hook back.
export function withCollectionLimit(projectId: string, text: string) {
  const key = '{Lightning.Services.AdapterHelper, :collection_hook}';
  const was = onNode(`:persistent_term.get(${key}, nil)`).split('\n').pop();
  onNode(`
    defmodule Lightning.Extensions.ScenarioCollectionLimit do
      @behaviour Lightning.Extensions.CollectionHooking
      alias Lightning.Extensions.CollectionHook

      def handle_create(attrs) do
        if (attrs[:project_id] || attrs["project_id"]) == ${ex(projectId)},
          do: {:error, :exceeds_limit, %Lightning.Extensions.Message{text: ${ex(text)}}},
          else: CollectionHook.handle_create(attrs)
      end

      defdelegate handle_delete(project_id, size), to: CollectionHook
      defdelegate handle_put_items(collection, size), to: CollectionHook
      defdelegate handle_delete_items(collection, size), to: CollectionHook
    end
    :persistent_term.put(${key}, Lightning.Extensions.ScenarioCollectionLimit)
  `);
  return () =>
    onNode(
      was === 'nil'
        ? `:persistent_term.erase(${key})`
        : `:persistent_term.put(${key}, ${was})`
    );
}

// ---------------------------------------------------------------------------
// SSO providers (annotations/views/admin-auth-providers.md)
// ---------------------------------------------------------------------------

export type StoredAuthProvider = {
  name: string;
  discovery_url: string;
  client_id: string;
  redirect_uri: string;
  allow_unverified_email: boolean;
};

// The SSO providers stored on the instance
export const authProviders = () =>
  sql<StoredAuthProvider>(
    `select name, discovery_url, client_id, redirect_uri, allow_unverified_email
     from auth_providers order by inserted_at`
  );

// Given SSO provider <attrs> is configured, through Lightning's own create
export function seedAuthProvider(attrs: {
  name: string;
  discoveryUrl: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
}) {
  onNodeOk([
    `{:ok, _} = Lightning.AuthProviders.create(%{name: ${ex(attrs.name)}, discovery_url: ${ex(attrs.discoveryUrl)}, client_id: ${ex(attrs.clientId)}, client_secret: ${ex(attrs.clientSecret)}, redirect_uri: ${ex(attrs.redirectUri)}})`,
  ]);
}

// Removes every stored SSO provider, and the node's cached sign-in handler
// for each of them and for <names>
export function removeAuthProviders(names: string[] = []) {
  onNodeOk([
    `stored = Lightning.Repo.all(Lightning.AuthProviders.AuthConfig) |> Enum.map(& &1.name)`,
    `Enum.each(stored ++ ${ex(names)}, &Lightning.AuthProviders.remove_handler/1)`,
    `Lightning.Repo.delete_all(Lightning.AuthProviders.AuthConfig)`,
  ]);
}

export type StandInProvider = {
  /** The discovery URL of document <kind> */
  discovery: (kind: 'good' | 'not-json' | 'no-authorization') => string;
  /** Where the provider's sign-in page is */
  authorizeUrl: string;
  /** A discovery URL on a port nobody listens on */
  refused: string;
  /** Every request the provider got */
  requests: URL[];
  close: () => Promise<void>;
};

// Given a stand-in OpenID Connect provider on this machine. Its "good"
// discovery document names authorization and token endpoints, "not-json" is
// plain text and "no-authorization" lacks the authorization endpoint.
export async function standInProvider(): Promise<StandInProvider> {
  const requests: URL[] = [];
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', base);
    requests.push(url);
    const kind = url.pathname.split('/')[1];
    const json = (body: object) => {
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify(body));
    };
    if (!url.pathname.endsWith('/.well-known/openid-configuration'))
      return res.end('signed in');
    if (kind === 'not-json') return res.end('not json');
    const endpoints = {
      issuer: base,
      token_endpoint: `${base}/token`,
      userinfo_endpoint: `${base}/userinfo`,
      jwks_uri: `${base}/jwks`,
    };
    json(
      kind === 'good'
        ? { ...endpoints, authorization_endpoint: `${base}/authorize` }
        : endpoints
    );
  });
  const listen = (s: Server) =>
    new Promise<number>(resolve =>
      s.listen(0, '127.0.0.1', () => resolve((s.address() as AddressInfo).port))
    );
  const base = `http://127.0.0.1:${await listen(server)}`;
  const spare = createServer();
  const refusedPort = await listen(spare);
  await new Promise(resolve => spare.close(resolve));
  const path = '/.well-known/openid-configuration';
  return {
    discovery: kind => `${base}/${kind}${path}`,
    authorizeUrl: `${base}/authorize`,
    refused: `http://127.0.0.1:${refusedPort}/good${path}`,
    requests,
    close: () => new Promise(resolve => server.close(() => resolve())),
  };
}

// Where a signed-out visit to "/authenticate/<name>" sends the browser, or
// null when it isn't sent on
export async function ssoStart(request: APIRequestContext, name: string) {
  const res = await request.get(`/authenticate/${name}`, { maxRedirects: 0 });
  const to = res.headers()['location'];
  return res.status() >= 300 && res.status() < 400 && to ? to : null;
}

// ---------------------------------------------------------------------------
// Adaptor catalogue (annotations/views/admin-maintenance.md)
// ---------------------------------------------------------------------------

// What the stand-in registry publishes: adaptor name => its latest version, a
// configuration schema (JSON) and the bytes of its square icon
export type Upstream = Record<
  string,
  { version: string; schema: string; icon: string }
>;

const STAND_IN = 'Lightning.Adaptors.ScenarioStrategy';
const ADAPTORS_META = '{Lightning.Adaptors.Supervisor, Lightning.Adaptors}';
const lastLine = (out: string) => out.trim().split('\n').pop()!;

// Given the adaptor registry is a stand-in on the node that publishes only
// <upstream>, so no refresh reaches npm or touches the instance's real
// adaptors. Returns a function that puts the configured strategy back.
// Instance-wide: a test that uses it is @serial.
export function standInRegistry(upstream: Upstream = {}) {
  onNode(`
    defmodule ${STAND_IN} do
      @behaviour Lightning.Adaptors.Strategy

      defp get(key, default), do: :persistent_term.get({__MODULE__, key}, default)
      defp upstream, do: get(:upstream, %{})

      def list_adaptors do
        :counters.add(get(:listings, nil), 1, 1)
        wait_while_held(600)
        {:ok, Enum.map(upstream(), fn {name, a} -> %{name: name, latest_version: a["version"]} end)}
      end

      defp wait_while_held(0), do: :ok
      defp wait_while_held(n) do
        if get(:held, false), do: (Process.sleep(50); wait_while_held(n - 1)), else: :ok
      end

      def fetch_adaptor(name) do
        case upstream()[name] do
          nil -> {:error, :not_found}
          a ->
            {:ok, {schema, sha}} = Lightning.Adaptors.Strategy.digest_schema(a["schema"])
            {:ok, %{name: name, description: nil, homepage: nil, repository: nil, license: nil,
                    latest_version: a["version"], deprecated: false,
                    schema_data: schema, schema_sha256: sha,
                    versions: [%{version: a["version"], integrity: nil, tarball_url: nil,
                                 size_bytes: nil, dependencies: %{}, peer_dependencies: %{},
                                 published_at: nil, deprecated: false}]}}
        end
      end

      def fetch_icon(name, :square) do
        case upstream()[name] do
          nil -> {:error, :not_found}
          a -> {:ok, %{data: a["icon"], ext: "png"}}
        end
      end
      def fetch_icon(_name, _shape), do: {:error, :not_found}

      def fetch_icons(_opts) do
        wait_while_held(600)
        if get(:icons_failing, false) do
          {:error, :scenario_outage}
        else
          {:ok, Map.new(upstream(), fn {name, a} ->
            {name, %{square: %{data: a["icon"], ext: "png", sha256: :crypto.hash(:sha256, a["icon"])}}}
          end)}
        end
      end
    end
    :persistent_term.put({${STAND_IN}, :listings}, :counters.new(1, []))
    :persistent_term.put({${STAND_IN}, :held}, false)
    :persistent_term.put({${STAND_IN}, :icons_failing}, false)
    Application.put_env(:lightning, ${STAND_IN}, source: :npm)
    :ok
  `);
  publishUpstream(upstream);
  const was = lastLine(
    onNode(`:persistent_term.get(${ADAPTORS_META}).strategy`)
  );
  onNode(
    `:persistent_term.put(${ADAPTORS_META}, %{:persistent_term.get(${ADAPTORS_META}) | strategy: ${STAND_IN}})`
  );
  return () =>
    onNode(
      `:persistent_term.put(${ADAPTORS_META}, %{:persistent_term.get(${ADAPTORS_META}) | strategy: ${was}})`
    );
}

// Given upstream now publishes <upstream>. Keep "#{" out of the values: they
// travel as an Elixir string.
export function publishUpstream(upstream: Upstream) {
  onNode(
    `:persistent_term.put({${STAND_IN}, :upstream}, Jason.decode!(${ex(JSON.stringify(upstream))}))`
  );
}

// Given the stand-in registry answers listings and icon fetches only once
// released (each waits at most 30 s)
export const holdRegistry = (held: boolean) =>
  onNode(`:persistent_term.put({${STAND_IN}, :held}, ${held})`);

// Given fetching icons from the stand-in registry fails
export const failIconFetches = () =>
  onNode(`:persistent_term.put({${STAND_IN}, :icons_failing}, true)`);

// How many registry listings the stand-in has answered (or is holding)
export const listingsSoFar = () =>
  Number(
    lastLine(
      onNode(`:counters.get(:persistent_term.get({${STAND_IN}, :listings}), 1)`)
    )
  );

// Given <name> is stored as upstream publishes it now, through Lightning's
// own single-package refresh
export function seedAdaptor(name: string) {
  expect(
    lastLine(onNode(`Lightning.Adaptors.refresh_package(${ex(name)})`))
  ).toBe(':ok');
}

// When a registry refresh starts on the instance (as the periodic poll does)
export const startRegistryRefresh = () =>
  expect(lastLine(onNode('Lightning.Adaptors.refresh()'))).toBe(':ok');

export type StoredAdaptor = {
  latest_version: string;
  schema_sha256: string | null;
  icon_sha256: string | null;
  versions: string[];
};

// The stored catalogue row for <name>, or undefined
export const storedAdaptor = (name: string): StoredAdaptor | undefined =>
  sql<StoredAdaptor>(
    `select a.latest_version, a.schema_sha256,
            encode(a.icon_square_sha256, 'hex') as icon_sha256,
            coalesce((select array_agg(v.version order by v.version)
                      from adaptor_versions v where v.adaptor_id = a.id), '{}') as versions
     from adaptors a where a.name = ${literal(name)}`
  )[0];

// How many adaptors the refreshes look at (the active source's rows)
export const adaptorsOnInstance = () =>
  Number(
    lastLine(
      onNode(
        'length(Lightning.Adaptors.Catalogue.list_adaptors(Lightning.Adaptors.Supervisor.source(Lightning.Adaptors)))'
      )
    )
  );

export const removeAdaptors = (names: string[]) =>
  exec(`delete from adaptors where name in (${names.map(literal).join(', ')})`);

// Given the adaptors scheduler can't be reached. Returns a function that
// makes it reachable again.
export function schedulerUnreachable() {
  const name =
    '{:global, Lightning.Adaptors.Supervisor.scheduler_name(Lightning.Adaptors)}';
  onNode(`
    {:global, n} = ${name}
    pid = :global.whereis_name(n)
    :persistent_term.put({${STAND_IN}, :scheduler}, pid)
    :global.unregister_name(n)
  `);
  return () =>
    onNode(`
      {:global, n} = ${name}
      :yes = :global.register_name(n, :persistent_term.get({${STAND_IN}, :scheduler}))
    `);
}

// ---------------------------------------------------------------------------
// Admin user form (annotations/views/admin-user-edit.md)
// ---------------------------------------------------------------------------

export type StoredAccount = {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
  disabled: boolean;
  support_user: boolean;
};

/** The stored account with this id or email, or undefined. */
export const storedAccount = (by: { id: string } | { email: string }) =>
  sql<StoredAccount>(
    `select id, email, first_name, last_name, role, disabled, support_user
     from users
     where ${'id' in by ? `id = '${by.id}'` : `email = ${literal(by.email)}`}`
  )[0] as StoredAccount | undefined;

// Removes the account with this email, if a test created one
export const removeAccountByEmail = (email: string) =>
  exec(`delete from user_tokens
          where user_id in (select id from users where email = ${literal(email)});
        delete from users where email = ${literal(email)}`);

// Whether <password> is account <id>'s password. Asked on the node, so a
// disabled account can be asked too. onNode output ends with the result.
export const passwordWorks = (id: string, password: string) =>
  onNode(
    `Lightning.Accounts.User.valid_password?(Lightning.Repo.get!(Lightning.Accounts.User, "${id}"), ${JSON.stringify(password)})`
  )
    .trim()
    .split('\n')
    .pop() === 'true';

/** How many signed-in sessions account <id> has. */
export const sessionsOf = (id: string) =>
  sql<{ n: number }>(
    `select count(*)::int as n from user_tokens
     where context = 'session' and user_id = '${id}'`
  )[0].n;

// ---------------------------------------------------------------------------
// Channel requests (history-channel-logs; channel-request-show can reuse it)
// ---------------------------------------------------------------------------

// The channel logs tab of a project, filtered to <channelId> if given
export const channelLogsPath = (projectId: string, channelId?: string) =>
  `/projects/${projectId}/history/channels${channelId ? `?filters[channel_id]=${channelId}` : ''}`;

// A request a channel logged: its state, when it started (UTC, "YYYY-MM-DD
// HH:MM:SS"), the path the destination answered on and the proxy's error
export type ChannelRequestSeed = {
  at: string;
  state?: 'pending' | 'success' | 'failed' | 'timeout' | 'error';
  path?: string;
  error?: string;
  completedAt?: string;
  // More request columns, as stored (client_identity, client_auth_type,
  // client_webhook_auth_method_id, destination_credential_id)
  request?: Record<string, string | null>;
  // The one event the proxy recorded, columns as stored (request_headers,
  // response_body_preview, latency_us, ...); a destination response unless
  // `type` says otherwise
  event?: { type?: 'destination_response' | 'error' } & Record<string, unknown>;
};

// Column values as the body of an Elixir map: JSON strings, numbers,
// booleans and lists read the same in Elixir; null is nil
const exAttrs = (attrs: Record<string, unknown>) =>
  Object.entries(attrs)
    .map(([k, v]) => `${k}: ${v === null ? 'nil' : ex(v)}`)
    .join(', ');

// A UTC time; the columns keep microseconds, so the fraction is spelled out to
// six digits
const exUtc = (at: string) => {
  const [seconds, fraction = ''] = at.split('.');
  return `DateTime.from_naive!(~N[${seconds}.${fraction.padEnd(6, '0')}], "Etc/UTC")`;
};

export type SeededChannelRequest = { id: string; requestId: string };

// Given channel <channelId> logged these requests — returns each one's id and
// request id, in order. Stored as the proxy stores them, through Lightning's
// own rule for what the project keeps: one that keeps no data loses the path.
export function seedChannelRequests(
  channelId: string,
  seeds: ChannelRequestSeed[]
): SeededChannelRequest[] {
  const policy = 'Lightning.Channels.PersistencePolicy';
  const kept = (kind: string, attrs: string) =>
    `Lightning.Repo.insert!(struct(Lightning.Channels.${kind}, ${policy}.wipe_${kind === 'ChannelRequest' ? 'request' : 'event'}_attrs(%{${attrs}}, persist_observations: keep)))`;
  const lines = [
    `c = Lightning.Repo.get!(Lightning.Channels.Channel, ${ex(channelId)})`,
    `{:ok, s} = Lightning.Channels.get_or_create_current_snapshot(c)`,
    `keep = ${policy}.persist_observations?(c.project_id)`,
  ];
  seeds.forEach((r, i) => {
    const state = r.state ?? 'success';
    const times = `started_at: ${exUtc(r.at)}${r.completedAt ? `, completed_at: ${exUtc(r.completedAt)}` : ''}`;
    const columns = exAttrs({ client_identity: 'scenario', ...r.request });
    lines.push(
      `r${i} = ${kept('ChannelRequest', `channel_id: c.id, channel_snapshot_id: s.id, request_id: Ecto.UUID.generate(), state: :${state}, ${times}, ${columns}`)}`
    );
    if (r.event) {
      const { type = 'destination_response', ...event } = r.event;
      lines.push(
        kept(
          'ChannelEvent',
          `channel_request_id: r${i}.id, type: :${type}, ${exAttrs(event)}`
        )
      );
    }
    if (r.path !== undefined)
      lines.push(
        kept(
          'ChannelEvent',
          `channel_request_id: r${i}.id, type: :destination_response, request_method: "GET", request_path: ${ex(r.path)}, response_status: ${state === 'failed' ? 502 : 200}`
        )
      );
    if (r.error !== undefined)
      lines.push(
        kept(
          'ChannelEvent',
          `channel_request_id: r${i}.id, type: :error, request_method: "GET", error_message: ${ex(r.error)}`
        )
      );
  });
  lines.push(
    `Jason.encode!(Enum.map([${seeds.map((_, i) => `r${i}`).join(', ')}], &%{id: &1.id, requestId: &1.request_id}))`
  );
  const out = onNode(lines.join('\n')).trim().split('\n').pop()!;
  return JSON.parse(JSON.parse(out)) as SeededChannelRequest[];
}

// When "<by>" renames channel <channelId> to <name> through Lightning, which
// makes a new config version
export const renameChannelOnNode = (
  channelId: string,
  name: string,
  by: string
) =>
  onNode(
    `c = Lightning.Repo.get!(Lightning.Channels.Channel, ${ex(channelId)})
     {:ok, _} = Lightning.Channels.update_channel(c, %{name: ${ex(name)}}, actor: ${exUser(by)})
     :ok`
  );

// Given project <projectId> keeps no input or output data
export const keepNoData = (projectId: string) =>
  exec(
    `update projects set retention_policy = 'erase_all' where id = '${projectId}'`
  );

// ---------------------------------------------------------------------------
// Dataclips and runs (annotations/views/dataclip-show.md)
// ---------------------------------------------------------------------------

export const dataclipPath = (projectId: string, id: string) =>
  `/projects/${projectId}/dataclips/${id}/show`;

export const runPath = (projectId: string, id: string) =>
  `/projects/${projectId}/runs/${id}`;

export type DataclipType =
  | 'http_request'
  | 'step_result'
  | 'saved_input'
  | 'global'
  | 'kafka';

export type DataclipSeed = {
  type: DataclipType;
  body?: object;
  /** the request details a webhook or kafka dataclip keeps */
  request?: object;
  /** stored at (UTC, "YYYY-MM-DD HH:MM:SS[.ffffff]"); now if not given */
  at?: string;
  /** wiped by the retention policy at (UTC, "YYYY-MM-DD HH:MM:SS") */
  wipedAt?: string;
};

const exJson = (v: unknown) => `Jason.decode!(${ex(JSON.stringify(v))})`;

// Elixir that stores a dataclip in project <project> (an Elixir expression)
// as Lightning does, binding it to <v>. A wiped one goes through the
// retention policy's own wipe, then takes the given wipe time.
const exDataclip = (v: string, project: string, seed: DataclipSeed) => [
  `${v} = Lightning.Repo.insert!(Lightning.Invocation.Dataclip.new(%{project_id: ${project}, type: :${seed.type},
     body: ${exJson(seed.body ?? {})}, request: ${seed.request ? exJson(seed.request) : 'nil'}${
       seed.at
         ? `, inserted_at: ${exUtc(seed.at)}, updated_at: ${exUtc(seed.at)}`
         : ''
     }}))`,
  ...(seed.wipedAt
    ? [
        `{1, _} = Lightning.Repo.update_all(Lightning.Invocation.Query.wipe_dataclips(from d in Lightning.Invocation.Dataclip, where: d.id == ^${v}.id), [])`,
        `Lightning.Repo.update_all(from(d in Lightning.Invocation.Dataclip, where: d.id == ^${v}.id), set: [wiped_at: DateTime.truncate(${exUtc(seed.wipedAt)}, :second)])`,
      ]
    : []),
];

// Given project <projectId> has this dataclip — returns its id. Removing the
// project's workflow data (removeWorkflowData) removes it.
export function seedDataclip(projectId: string, seed: DataclipSeed) {
  const out = onNode(
    [`import Ecto.Query`, ...exDataclip('d', ex(projectId), seed), `d.id`].join(
      '\n'
    )
  );
  return JSON.parse(out.trim().split('\n').pop()!) as string;
}

export type RunStepSeed = {
  /** the step's job */
  name: string;
  /** the values of the credential the job uses, if it uses one */
  credential?: Record<string, unknown>;
  /** the step's output */
  output?: object;
  /** how the step ended, "success" unless said; null while it still runs */
  exit?: string | null;
  errorType?: string;
  /** how long it ran, or has been running, in seconds; 1 unless said */
  seconds?: number;
  /** the step is one an earlier run of the work order ran, carried over */
  carried?: boolean;
};

export type RunLogSeed = {
  message: string;
  /** "info" unless said */
  level?: 'debug' | 'info' | 'warn' | 'error' | 'success' | 'always';
  /** "R/T" unless said */
  source?: string;
  /** the step that logged it, by name; the run itself if not given */
  step?: string;
  /** seconds after the run started; otherwise a millisecond apart, in order */
  at?: number;
};

export type RunSeed = {
  /** the workflow's name */
  workflow?: string;
  /** what starts the workflow; a webhook unless said */
  trigger?: 'webhook' | 'cron';
  /** the webhook trigger takes basic auth with this user and password */
  basicAuth?: [string, string];
  /** the work order's input; an empty webhook request if not given */
  input?: DataclipSeed;
  /** in the order they ran, one after the other */
  steps?: RunStepSeed[];
  /** more jobs the workflow has, that no step of this run has run (yet) */
  jobs?: string[];
  /** the run's state, "success" unless said; available, claimed and started
   * runs are unfinished, and an available one is never offered to a worker */
  state?: string;
  /** the run was started by this person (a retry from History), not by the
   * trigger */
  createdBy?: string;
  /** what the run logged */
  logs?: RunLogSeed[];
  /** the run started at (UTC, "YYYY-MM-DD HH:MM:SS"); otherwise so that its
   * steps end now */
  at?: string;
  /** the run then finishes, as a worker would finish it, with this state */
  finalState?: object;
};

export type SeededRunIds = {
  workflowId: string;
  workOrderId: string;
  runId: string;
  inputId: string;
  /** step name -> the id of its output */
  outputs: Record<string, string>;
  /** step name -> the step's id */
  steps: Record<string, string>;
  /** the run's final output, once it has finished */
  finalId: string | null;
  /** the snapshot the run executed, and its version */
  snapshotId: string;
  version: number;
  /** removes the credentials the steps used; after the project has gone */
  removeCredentials: () => void;
};

const UNFINISHED_RUN = ['available', 'claimed', 'started'];

// Given a run of a workflow in project <projectId>, built by "<by>" through
// Lightning: the workflow (a trigger and a job per step), its credentials, a
// work order and its run, with the run options Lightning gives the project,
// its steps and what it logged. A `finalState` completes the run through
// Lightning, so the final output is kept or wiped by the project's retention
// policy; otherwise the run is seeded in its `state`. Each step's input is
// the output of the step before it, or the work order's input. Remove with
// removeWorkflowData(projectId) before the project, then removeCredentials.
export function seedRun(
  projectId: string,
  seed: RunSeed,
  by: string
): SeededRunIds {
  const steps = seed.steps ?? [];
  const prefix = `scenario-${randomUUID().slice(0, 8)}`;
  const finishing = seed.finalState !== undefined;
  const state = finishing ? 'started' : (seed.state ?? 'success');
  const unfinished = UNFINISHED_RUN.includes(state);
  // Each step starts when the one before it ends
  const durations = steps.map(s => s.seconds ?? 1);
  const starts = durations.map((_, i) =>
    durations.slice(0, i).reduce((a, b) => a + b, 0)
  );
  const span = durations.reduce((a, b) => a + b, 0) + 1;
  const at = (seconds: number) =>
    `DateTime.add(t0, ${Math.round(seconds * 1000)}, :millisecond)`;
  const workOrderState =
    state === 'available' ? 'pending' : unfinished ? 'running' : state;
  const lines = [
    `import Ecto.Query`,
    `by = ${exUser(by)}`,
    `pid = ${ex(projectId)}`,
    `t0 = ${seed.at ? exUtc(seed.at) : `DateTime.add(DateTime.utc_now(), -${span}, :second)`}`,
  ];
  steps.forEach((s, i) => {
    if (!s.credential) return;
    lines.push(
      `{:ok, c${i}} = Lightning.Credentials.create_credential(%{name: ${ex(`${prefix}-${s.name}`)}, schema: "raw", credential_bodies: [%{name: "main", body: ${exJson(s.credential)}}], user_id: by.id, project_credentials: [%{project_id: pid}]}, by)`,
      `pc${i} = Lightning.Repo.one!(from pc in Lightning.Projects.ProjectCredential, where: pc.credential_id == ^c${i}.id and pc.project_id == ^pid)`
    );
  });
  const jobs = steps.map(
    (s, i) =>
      `%{id: Ecto.UUID.generate(), name: ${ex(s.name)}, body: "fn(s => s)", adaptor: "@openfn/language-common@latest"${s.credential ? `, project_credential_id: pc${i}.id` : ''}}`
  );
  for (const name of seed.jobs ?? [])
    jobs.push(
      `%{id: Ecto.UUID.generate(), name: ${ex(name)}, body: "fn(s => s)", adaptor: "@openfn/language-common@latest"}`
    );
  const trigger =
    seed.trigger === 'cron'
      ? `%{id: Ecto.UUID.generate(), type: :cron, cron_expression: "0 0 * * *", enabled: true}`
      : `%{id: Ecto.UUID.generate(), type: :webhook, enabled: true}`;
  lines.push(
    `{:ok, wf} = Lightning.Workflows.save_workflow(%{name: ${ex(seed.workflow ?? 'Intake')}, project_id: pid,
       jobs: [${jobs.join(', ')}], triggers: [${trigger}]}, by)`,
    `wf = Lightning.Repo.preload(wf, [:jobs, :triggers], force: true)`,
    `t = hd(wf.triggers)`,
    `snap = Lightning.Workflows.Snapshot.get_current_for(wf)`
  );
  // A worker would take a queued run at once; Lightning offers none of a
  // workflow whose concurrency is 0 (the form refuses 0, so it is set here)
  if (state === 'available')
    lines.push(
      `Lightning.Repo.update_all(from(w in Lightning.Workflows.Workflow, where: w.id == ^wf.id), set: [concurrency: 0])`
    );
  if (seed.basicAuth)
    lines.push(
      `{:ok, _} = Lightning.WebhookAuthMethods.create_auth_method(t, %{name: ${ex(`${prefix}-basic`)}, auth_type: :basic, username: ${ex(seed.basicAuth[0])}, password: ${ex(seed.basicAuth[1])}, project_id: pid}, actor: by)`
    );
  const startedBy = seed.createdBy
    ? `created_by_id: Lightning.Repo.get_by!(Lightning.Accounts.User, email: ${ex(forWorker(seed.createdBy))}).id, starting_job_id: ${steps.length ? `Enum.find(wf.jobs, &(&1.name == ${ex(steps[0].name)})).id` : 'nil'}`
    : `starting_trigger_id: t.id`;
  lines.push(
    ...exDataclip('input', 'pid', seed.input ?? { type: 'http_request' }),
    `wo = Lightning.Repo.insert!(%Lightning.WorkOrder{workflow_id: wf.id, trigger_id: t.id, dataclip_id: input.id, snapshot_id: snap.id, state: :${workOrderState}, last_activity: DateTime.utc_now()})`,
    `run = Lightning.Repo.insert!(%Lightning.Run{work_order_id: wo.id, ${startedBy}, dataclip_id: input.id, snapshot_id: snap.id,
       state: :${state}, claimed_at: ${state === 'available' ? 'nil' : 't0'}, started_at: ${['available', 'claimed'].includes(state) ? 'nil' : 't0'},
       finished_at: ${unfinished ? 'nil' : at(span)}, options: Lightning.Runs.get_run_options(wf.id, pid)})`,
    `outputs = %{}`,
    `step_ids = %{}`,
    `last_output = input`
  );
  steps.forEach((s, i) => {
    const running = s.exit === null;
    const output =
      s.output && !running
        ? exDataclip(`o${i}`, 'pid', { type: 'step_result', body: s.output })
        : [];
    lines.push(
      ...output,
      `job = Enum.find(wf.jobs, &(&1.name == ${ex(s.name)}))`,
      `s${i} = Lightning.Repo.insert!(%Lightning.Invocation.Step{job_id: job.id, snapshot_id: snap.id, input_dataclip_id: last_output.id,
         output_dataclip_id: ${output.length ? `o${i}.id` : 'nil'}, credential_id: ${s.credential ? `c${i}.id` : 'nil'},
         exit_reason: ${running ? 'nil' : ex(s.exit ?? 'success')}, error_type: ${s.errorType ? ex(s.errorType) : 'nil'},
         started_at: ${at(starts[i])}, finished_at: ${running ? 'nil' : at(starts[i] + durations[i])}${s.carried ? `, inserted_at: DateTime.add(t0, -3600, :second)` : ''}})`,
      `Lightning.Repo.insert!(%Lightning.RunStep{run_id: run.id, step_id: s${i}.id})`,
      `step_ids = Map.put(step_ids, ${ex(s.name)}, s${i}.id)`,
      ...(output.length
        ? [
            `outputs = Map.put(outputs, ${ex(s.name)}, o${i}.id)`,
            `last_output = o${i}`,
          ]
        : [])
    );
  });
  (seed.logs ?? []).forEach((log, i) => {
    lines.push(
      `{:ok, _} = Lightning.Runs.append_run_log(run, %{message: ${ex(log.message)}, level: ${ex(log.level ?? 'info')}, source: ${ex(log.source ?? 'R/T')},
         step_id: ${log.step ? `Map.fetch!(step_ids, ${ex(log.step)})` : 'nil'}, timestamp: ${at(log.at ?? i / 1000)}})`
    );
  });
  if (finishing)
    lines.push(
      `{:ok, run} = Lightning.Runs.complete_run(run, %{"state" => "success", "final_state" => ${exJson(seed.finalState)}})`
    );
  lines.push(
    `Jason.encode!(%{workflowId: wf.id, workOrderId: wo.id, runId: run.id, inputId: input.id, outputs: outputs, steps: step_ids, finalId: run.final_dataclip_id, snapshotId: snap.id, version: snap.lock_version})`
  );
  const out = onNode(lines.join('\n')).trim().split('\n').pop()!;
  const ids = JSON.parse(JSON.parse(out)) as Omit<
    SeededRunIds,
    'removeCredentials'
  >;
  return {
    ...ids,
    removeCredentials: () =>
      onNodeOk([
        `import Ecto.Query`,
        `Lightning.Repo.delete_all(from c in Lightning.Credentials.Credential, where: like(c.name, ^${ex(`${prefix}-%`)}))`,
      ]),
  };
}

export type WorkerReport =
  | { claim: true }
  | { start: true }
  /** a step of this job starts; returns its id */
  | { startStep: string }
  | { log: string; step?: string }
  | { completeStep: string; reason?: string; output?: object }
  | { complete: string; finalState?: object };

// When the worker reports <report> for run <runId>. Sent through the
// functions the worker's run channel calls, so an open run page hears of it
// as it would from a worker. A claim has no such function for one run (a
// worker claims whatever is queued), so it is the update a claim makes.
// Returns the id of a started step, and "" otherwise.
export function workerReports(runId: string, report: WorkerReport): string {
  const head = [
    `run = Lightning.Repo.get!(Lightning.Run, ${ex(runId)}) |> Lightning.Repo.preload(work_order: [workflow: :jobs])`,
  ];
  let act: string[];
  if ('claim' in report)
    act = [
      `{:ok, _} = Lightning.Runs.update_run(Ecto.Changeset.change(run, %{state: :claimed, claimed_at: DateTime.utc_now()}))`,
    ];
  else if ('start' in report)
    act = [`{:ok, _} = Lightning.Runs.start_run(run)`];
  else if ('startStep' in report)
    act = [
      `job = Enum.find(run.work_order.workflow.jobs, &(&1.name == ${ex(report.startStep)}))`,
      `id = Ecto.UUID.generate()`,
      `{:ok, _} = Lightning.Runs.start_step(run, %{"job_id" => job.id, "step_id" => id, "input_dataclip_id" => run.dataclip_id})`,
    ];
  else if ('log' in report)
    act = [
      `{:ok, _} = Lightning.Runs.append_run_log(run, %{"message" => ${ex(report.log)}, "source" => "R/T", "level" => "info", "step_id" => ${report.step ? ex(report.step) : 'nil'}, "timestamp" => DateTime.utc_now()})`,
    ];
  else if ('completeStep' in report)
    act = [
      `{:ok, _} = Lightning.Runs.complete_step(%{"run_id" => run.id, "step_id" => ${ex(report.completeStep)}, "project_id" => run.work_order.workflow.project_id, "reason" => ${ex(report.reason ?? 'success')}${
        report.output
          ? `, "output_dataclip" => ${ex(JSON.stringify(report.output))}, "output_dataclip_id" => Ecto.UUID.generate()`
          : ''
      }}, run.options)`,
    ];
  else
    act = [
      `{:ok, _} = Lightning.Runs.complete_run(run, %{"state" => ${ex(report.complete)}${report.finalState ? `, "final_state" => ${exJson(report.finalState)}` : ''}})`,
    ];
  const last = 'startStep' in report ? `id` : `""`;
  const out = onNode([...head, ...act, last].join('\n'))
    .trim()
    .split('\n')
    .pop()!;
  return JSON.parse(out) as string;
}

// When the line <message> that run <runId> logged reaches an open run page a
// second time, as a worker's retried send would
export function redeliverLogLine(runId: string, message: string) {
  onNodeOk([
    `import Ecto.Query`,
    `line = Lightning.Repo.one!(from l in Lightning.Invocation.LogLine, where: l.run_id == ^${ex(runId)} and l.message == ^${ex(message)})`,
    `Lightning.Runs.Events.log_appended(line)`,
  ]);
}

/** When a snapshot was taken, as "YYYY-MM-DD at HH:MM:SS" (UTC). */
export const snapshotTakenAt = (snapshotId: string) =>
  sql<{ at: string }>(
    `select to_char(inserted_at, 'YYYY-MM-DD "at" HH24:MI:SS') as at
     from workflow_snapshots where id = '${snapshotId}'`
  )[0].at;
