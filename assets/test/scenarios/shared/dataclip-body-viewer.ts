// Scenarios from annotations/shared/shared-dataclip-body-viewer.md.
//
// The host page owns the Given: it seeds the dataclip (the `given` values
// below) and opens the page that shows it. The functions hold the When and
// Then. The viewer is one component on every host page, in both versions, so
// what knows how it is built (Monaco's drawn lines, the copy button's
// "copied" signal) lives at the top of this file rather than in each host's
// page helper.
import { expect, type Page } from '@playwright/test';

// The viewer's editor. Both versions draw the body in a read-only Monaco.
// A host can hold other editors out of sight (the run page's log, behind
// its tab), so only the one on screen counts.
export const viewer = (page: Page) =>
  page.locator('.monaco-editor').filter({ visible: true });

// The text the viewer shows, one line per drawn line. Monaco draws only the
// lines in view, and spaces as no-break spaces, so keep bodies short.
export async function viewerText(page: Page) {
  const lines = viewer(page).locator('.view-line');
  return (await lines.allInnerTexts()).join('\n').replace(/\u00a0/g, ' ');
}

// The same text with drawn lines joined up: a long line that wraps is drawn
// as several, so substring checks read this one.
const flatText = async (page: Page) =>
  (await viewerText(page)).replace(/\n/g, '');

export const copyButton = (page: Page) =>
  page.getByRole('button', { name: 'Copy to clipboard' });

// What says the copy worked: today the button is renamed "Copied to
// clipboard" (its title "Copied!"); the design system's tooltip reads
// "Copied!".
const copiedSignal = (page: Page) =>
  page
    .getByRole('button', { name: 'Copied to clipboard' })
    .or(page.getByRole('tooltip').filter({ hasText: 'Copied!' }))
    .first();

export const given = {
  S03: {
    username: 'webhook_user',
    password: 'webhook_secret_pass',
    data: 'test payload',
  },
  // Each step's credential values, in the order the steps ran, and the
  // output "Fetch" produced
  S04: {
    Login: { secret: '55' },
    Fetch: { pin: 123456, another_secret: 'bar' },
    Post: { token: 'post-only' },
    output: {
      integer: 123456,
      third_no: 125534,
      map: { list: [{ 'any-key': 'some-bars' }] },
      bool: true,
    },
  },
  S05: { body: { patient: 'record' } },
};

// The webhook request S03 stores: its basic auth header, in the body as the
// request a source system sent, and in the request details
export function webhookRequest() {
  const { username, password, data } = given.S03;
  const authorization = `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}`;
  return {
    type: 'http_request' as const,
    body: { headers: { authorization }, data },
    request: { method: 'POST', headers: { authorization } },
  };
}

// @S01 The body is shown formatted and read-only
//   Given a global dataclip whose body is {"patients":[{"id":1}]}
//   When a host page shows it in the dataclip body viewer
//   Then the viewer shows the body as JSON indented by two spaces
//   And the viewer does not accept typing
export async function S01(page: Page, body: object) {
  const formatted = JSON.stringify(body, null, 2);
  await expect.poll(() => viewerText(page)).toBe(formatted);

  await viewer(page).locator('.view-line').first().click();
  await expect(viewer(page).locator('textarea')).toBeFocused();
  await page.keyboard.type('typed');
  await page.keyboard.press('Enter');

  expect(await viewerText(page)).toBe(formatted);
}

// @S02 The body can be copied
//   Given the dataclip body viewer has loaded a body
//   When I click the "Copy to clipboard" button
//   Then the clipboard holds the body as displayed
//   And the button is labelled "Copied to clipboard" for two seconds
export async function S02(page: Page, body: object) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  const formatted = JSON.stringify(body, null, 2);
  await expect.poll(() => viewerText(page)).toBe(formatted);

  await copyButton(page).click();

  await expect
    .poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toBe(formatted);
  await expect(copiedSignal(page)).toBeVisible();
  await expect(copiedSignal(page)).toBeHidden({ timeout: 4000 });
  await expect(copyButton(page)).toBeVisible();
}

// @S03 A webhook request shows its data and request together, with the webhook secret masked
//   Given workflow "Intake" has a webhook trigger protected by basic auth "webhook_user" with password "webhook_secret_pass"
//   And a request to that webhook stored an http_request dataclip with an "authorization" header and data "test payload"
//   When a host page shows that dataclip in the body viewer
//   Then the viewer shows "data" and "request" keys
//   And it shows "test payload"
//   And it does not show "webhook_secret_pass" or the base64 of "webhook_user:webhook_secret_pass"
//   And it shows "***" in their place
// The host seeds `webhookRequest()` behind that trigger.
export async function S03(page: Page) {
  const { username, password, data } = given.S03;
  await expect.poll(() => flatText(page)).toContain(data);

  const text = await flatText(page);
  expect(text).toContain('"data":');
  expect(text).toContain('"request":');
  expect(text).not.toContain(password);
  expect(text).not.toContain(
    Buffer.from(`${username}:${password}`).toString('base64')
  );
  expect(text).toContain('***');
}

// @S04 A step's output masks credential values used earlier in the same run
//   Given a run where step "Login" used a credential with value "55"
//   And step "Fetch" ran after it with a credential whose values include 123456 and "bar"
//   And step "Post" ran after "Fetch" with another credential
//   And "Fetch" produced an output dataclip containing 123456, 125534 and "some-bars"
//   When a host page shows that output in the body viewer
//   Then 123456 is shown as "***", 125534 as "12***34" and "some-bars" as "some-***s"
//   And values in no credential, such as true, are shown unchanged
// The host seeds the run from `given.S04`.
export async function S04(page: Page) {
  await expect.poll(() => flatText(page)).toContain('12***34');

  const text = await flatText(page);
  expect(text).not.toContain('123456');
  expect(text).not.toContain('125534');
  expect(text).toMatch(/"integer":\s*\*\*\*/);
  expect(text).toContain('some-***s');
  expect(text).toMatch(/"bool":\s*true/);
}

// @S05 The body is refused to anyone without access to the dataclip's project
//   Given dataclip "D" on project "Kenya TB" with body {"patient":"record"}
//   And <who>
//   When the body viewer asks for "D"
//   Then the response is 403 and carries no part of the body
//   And the viewer shows "Failed to load content" with no copy button
// One Examples row; the host sets up <who>. A host page only puts a viewer
// on dataclips the user can read, so the viewer showing the host's own
// dataclip <shown> is pointed at "D": its body request goes to D's address
// instead. `open` opens the host page.
export async function S05(
  page: Page,
  shown: string,
  d: string,
  open: () => Promise<void>
) {
  const response = await page.request.get(`/dataclip/body/${d}`);
  expect.soft(response.status()).toBe(403);
  expect.soft(await response.text()).not.toContain('record');

  const url = `**/dataclip/body/${shown}`;
  await page.route(url, route =>
    route.continue({ url: route.request().url().replace(shown, d) })
  );
  try {
    await open();
    await expect
      .soft(viewer(page))
      .toContainText('Failed to load content', { timeout: 15000 });
    await expect.soft(copyButton(page)).toHaveCount(0);
  } finally {
    await page.unroute(url);
  }
}

// @S06 A body that cannot be loaded says so
//   Given the body request for the dataclip <outcome>
//   When the body viewer loads
//   Then the viewer shows <message>
//   Examples: answers 404 "Dataclip not found"; answers 500 "Failed to load
//   content"; fails on the network "Failed to load content"
// All three rows; `open` opens the host page showing dataclip <shown>.
export async function S06(
  page: Page,
  shown: string,
  open: () => Promise<void>
) {
  const rows: [string, (route: import('@playwright/test').Route) => unknown][] =
    [
      ['Dataclip not found', route => route.fulfill({ status: 404 })],
      ['Failed to load content', route => route.fulfill({ status: 500 })],
      ['Failed to load content', route => route.abort('failed')],
    ];
  const url = `**/dataclip/body/${shown}`;
  for (const [message, answer] of rows) {
    await page.route(url, answer);
    try {
      await open();
      await expect
        .soft(viewer(page), message)
        .toContainText(message, { timeout: 15000 });
    } finally {
      await page.unroute(url);
    }
  }
}
