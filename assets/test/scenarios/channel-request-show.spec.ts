// Scenarios from annotations/views/channel-request-show.md.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names (a viewer unless it says otherwise) and turns my experimental
// features on, since the page needs them. owner@openfn.org owns every project
// and seeds its channels through Lightning. super@openfn.org is the third
// member a test needs. Every project is seeded by the test and removed again
// afterwards, with its channels and their logged requests. Requests are
// stored on the node as the proxy stores them.
import { expect, test, type Page } from '@playwright/test';

import {
  group,
  section,
  segmentTitles,
  toggle,
  valueOf,
} from './pages/channel-request-show';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import {
  addWebhookAuthMethodOnNode,
  changeRoleOnNode,
  exec,
  expectAt,
  expectTooltip,
  keepAccount,
  keepNoData,
  makeSupportUser,
  manifest,
  open,
  projectCredentialId,
  removeChannelsOf,
  removeMemberOnNode,
  removeMfaOf,
  renameChannelOnNode,
  scheduleDeletionOnNode,
  seedChannel,
  seedChannelRequests,
  seedWorkspace,
  setPreferences,
  setSupportAccessOnNode,
  shortId,
  signInAs,
  sql,
  user,
  type ChannelRequestSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Tests turn on my experimental features (and some disable or MFA me)
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it),
// each with experimental features on; removed after the test with its
// channels — returns its id
function givenProject(
  members: Record<string, Role> = { [ME]: 'viewer' },
  { name = 'Malawi HIV', ...rest }: Partial<WorkspaceSeed> = {}
) {
  const owned = Object.values(members).includes('owner')
    ? members
    : { ...members, [OWNER]: 'owner' as const };
  for (const email of Object.keys(owned)) {
    if (email !== ME) cleanups.push(keepAccount(email));
    setPreferences(email, { experimental_features: true });
  }
  const by = Object.entries(owned).find(([, r]) => r === 'owner')![0];
  const w = seedWorkspace({ name, members: owned, ...rest }, by);
  cleanups.push(w.remove);
  const id = w.id(name);
  // Runs before the project is removed: logged requests would stop it
  cleanups.push(() => removeChannelsOf(id));
  return { id, w, by };
}

// Given channel <name> in project <projectId> logged these requests —
// returns the channel's id and each request's id
function givenRequests(
  projectId: string,
  requests: ChannelRequestSeed[],
  name = 'orders-proxy'
) {
  const channelId = seedChannel(projectId, { name }, OWNER);
  return {
    channelId,
    ids: seedChannelRequests(channelId, requests).map(r => r.id),
  };
}

const requestPath = (projectId: string, id: string) =>
  `/projects/${projectId}/history/channels/${id}`;

// When I sign in and open request <id> of project <projectId>
async function openRequest(page: Page, projectId: string, id: string) {
  await signInAs(page, ME);
  await open(page, requestPath(projectId, id));
}

// Given a channel in my project logged this one request, when I open it —
// returns the project's and request's ids
async function onRequest(
  page: Page,
  seed: Omit<ChannelRequestSeed, 'at'> & { at?: string },
  members?: Record<string, Role>
) {
  const { id: projectId } = givenProject(members);
  const {
    channelId,
    ids: [id],
  } = givenRequests(projectId, [{ at: '2026-01-01 10:00:00', ...seed }]);
  await openRequest(page, projectId, id);
  return { projectId, channelId, id };
}

const JSON_HEADERS = [['content-type', 'application/json']];
const HASH = 'a3f1c9e07b2d4e5f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f';
const HASH_2 = HASH.split('').reverse().join('');

const copyButton = (page: Page, name: string) =>
  page.getByRole('button', { name, exact: true });

const clipboard = (page: Page) =>
  page.evaluate(() => navigator.clipboard.readText());

// @S01 @variant:experimental-features
// Scenario: A successful request shows its summary
//   Given a channel "orders-proxy" in my project
//   And a successful request "POST /api/v1/data?format=json" that got status 200 after 350 ms
//   When I open the request
//   Then I see "POST", "/api/v1/data", "?format=json" and "200"
//   And the state pill reads "Success" (labels owned by shared-run-components channel_state_pill)
//   And I see "orders-proxy", the client IP, the destination URL, the start and completed times and "350 ms"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    completedAt: '2026-01-01 10:00:00.350',
    request: { client_identity: '203.0.113.7' },
    event: {
      request_method: 'POST',
      request_path: '/api/v1/data',
      request_query_string: 'format=json',
      response_status: 200,
      latency_us: 350_000,
    },
  });

  await expect(page.getByText('POST', { exact: true })).toBeVisible();
  await expect(page.getByText('/api/v1/data').first()).toBeVisible();
  await expect(page.getByText('?format=json', { exact: true })).toBeVisible();
  await expect(page.getByText('200', { exact: true }).first()).toBeVisible();
  await expect(page.getByText('Success', { exact: true })).toBeVisible();

  await expect(page.getByRole('link', { name: 'orders-proxy' })).toBeVisible();
  await expect(valueOf(group(page, 'Client'), 'IP')).toHaveText('203.0.113.7');
  await expect(valueOf(group(page, 'Destination'), 'URL')).toHaveText(
    'https://destination.example.com/data'
  );
  const timing = group(page, 'Timing');
  await expect(valueOf(timing, 'Started')).toHaveText(/\d/);
  await expect(valueOf(timing, 'Completed')).toHaveText(/\d/);
  await expect(valueOf(timing, 'Latency')).toHaveText(/^\s*350 ms\s*$/);
});

// @S02 @variant:experimental-features
// Scenario: Secret headers are shown redacted
//   Given a request whose "authorization" header was stored as "[REDACTED]"
//   When I open the request
//   Then the request headers list "authorization" with the value "[REDACTED]" shown in italics
//   And other headers such as "content-type" show their values
// The italics are the look; the Value is that the secret is not shown.
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    event: {
      request_method: 'GET',
      request_path: '/patients',
      request_headers: [
        ['authorization', '[REDACTED]'],
        ['content-type', 'application/json'],
      ],
      response_status: 200,
    },
  });

  const headers = section(section(page, 'Request'), 'Headers');
  await expect(valueOf(headers, 'authorization')).toHaveText('[REDACTED]');
  await expect(valueOf(headers, 'content-type')).toHaveText('application/json');
});

// @S03 @variant:experimental-features
// Scenario: Text bodies are shown with their type, size and hash
//   Given a request with a JSON request body and a JSON response body
//   When I open the request
//   Then each body shows its text, a "JSON" label, its size, a copy button and the first 16 characters of its SHA256 hash
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const sent = '{"patient":"A1"}';
  const got = '{"status":"stored","count":1}';
  await onRequest(page, {
    event: {
      request_method: 'POST',
      request_path: '/patients',
      request_headers: JSON_HEADERS,
      request_body_preview: sent,
      request_body_size: sent.length,
      request_body_hash: HASH,
      response_status: 200,
      response_headers: JSON_HEADERS,
      response_body_preview: got,
      response_body_size: got.length,
      response_body_hash: HASH_2,
    },
  });

  for (const [card, body, hash] of [
    ['Request', sent, HASH],
    ['Response', got, HASH_2],
  ]) {
    const shown = section(section(page, card), 'Body');
    await expect.soft(shown).toContainText(body);
    await expect.soft(shown.getByText('JSON', { exact: true })).toBeVisible();
    await expect
      .soft(shown.getByText(`${body.length} B`, { exact: true }).first())
      .toBeVisible();
    await expect.soft(shown).toContainText(`SHA256: ${hash.slice(0, 16)}`);
  }
  await expect(copyButton(page, 'Copy body')).toHaveCount(2);
});

// @S04 @variant:experimental-features
// Scenario: A truncated body says it is a preview
//   Given a response body of 10 KB of which a 2 KB preview was stored
//   When I open the request
//   Then below the body I see "Preview: 2.0 KB of 10.0 KB"
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    event: {
      request_method: 'GET',
      request_path: '/export',
      response_status: 200,
      response_headers: [['content-type', 'text/plain']],
      response_body_preview: 'x'.repeat(2048),
      response_body_size: 10_240,
      response_body_hash: HASH,
    },
  });

  await expect(section(section(page, 'Response'), 'Body')).toContainText(
    /Preview:\s*2\.0 KB of 10\.0 KB/
  );
});

// @S05 @variant:experimental-features
// Scenario: Binary bodies show metadata only
//   Given a response with content type "application/octet-stream", size 4096 bytes and hash "binaryhash123"
//   When I open the request
//   Then the response body shows "application/octet-stream", "4.0 KB" and "SHA256: binaryhash123"
//   And no body text is shown
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    event: {
      request_method: 'GET',
      request_path: '/files/1',
      response_status: 200,
      response_headers: [['content-type', 'application/octet-stream']],
      response_body_preview: 'PK\u0003\u0004binary-bytes',
      response_body_size: 4096,
      response_body_hash: 'binaryhash123',
    },
  });

  const body = section(section(page, 'Response'), 'Body');
  await expect(
    body.getByText('application/octet-stream', { exact: true })
  ).toBeVisible();
  await expect(body.getByText('4.0 KB', { exact: true }).first()).toBeVisible();
  await expect(body).toContainText('SHA256: binaryhash123');
  await expect(body).not.toContainText('binary-bytes');
  await expect(copyButton(page, 'Copy body')).toHaveCount(0);
});

// @S06 @variant:experimental-features
// Scenario: A body that was sized but not stored says so
//   Given a request body of 2048 bytes with no preview stored
//   When I open the request
//   Then the request body reads "Body not captured (2.0 KB)"
//   And an empty body with size 0 reads "No body"
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    event: {
      request_method: 'POST',
      request_path: '/patients',
      request_headers: JSON_HEADERS,
      request_body_size: 2048,
      response_status: 204,
      response_headers: JSON_HEADERS,
      response_body_size: 0,
    },
  });

  await expect(section(section(page, 'Request'), 'Body')).toContainText(
    /Body not captured\s*\(2\.0 KB\)/
  );
  await expect(
    section(section(page, 'Response'), 'Body').getByText('No body', {
      exact: true,
    })
  ).toBeVisible();
});

// @S07 @variant:experimental-features
// Scenario: A transport error explains why there was no response
//   Given a request in state "error" whose error is "econnrefused"
//   When I open the request
//   Then the response section reads "No response received"
//   And it explains "Connection refused" in plain words and shows the code "econnrefused"
//   And the timing section shows a single "Total" bar
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    state: 'error',
    event: {
      type: 'error',
      request_method: 'POST',
      request_path: '/patients',
      error_message: 'econnrefused',
      latency_us: 1500,
    },
  });

  const response = section(page, 'Response');
  await expect(response).toContainText('No response received');
  await expect(response).toContainText('Connection refused');
  await expect(
    response.getByText('econnrefused', { exact: true })
  ).toBeVisible();
  expect(await segmentTitles(page)).toEqual([
    expect.stringMatching(/^Total: /),
  ]);
});

// @S08 @variant:experimental-features
// Scenario: A credential error says the request was never sent
//   Given a request in state "error" whose error is "credential_missing_auth_fields"
//   When I open the request
//   Then the response section reads "Request not sent — credential error"
//   And it says the configured credential "is missing required authentication fields" and shows the code
//   And there is no timing section
// The request has a duration, so a timing section would show if allowed.
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    state: 'error',
    event: {
      type: 'error',
      request_method: 'POST',
      request_path: '/patients',
      error_message: 'credential_missing_auth_fields',
      latency_us: 1200,
    },
  });

  const response = section(page, 'Response');
  await expect(response).toContainText('Request not sent — credential error');
  await expect(response).toContainText(
    'is missing required authentication fields'
  );
  await expect(
    response.getByText('credential_missing_auth_fields', { exact: true })
  ).toBeVisible();
  await expect(toggle(page, 'Timing')).toHaveCount(0);
});

// @S09 @variant:experimental-features
// Scenario: A timed-out request explains the timeout on its state pill
//   Given a request in state "timeout" whose error is "response_timeout"
//   When I hover its "Timeout" state pill
//   Then the tooltip says the destination "accepted the connection but did not send a response in time"
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    state: 'timeout',
    event: {
      type: 'error',
      request_method: 'GET',
      request_path: '/slow',
      error_message: 'response_timeout',
      latency_us: 30_000_000,
    },
  });

  await expectTooltip(
    page,
    page.getByText('Timeout', { exact: true }),
    'accepted the connection but did not send a response in time'
  );
});

// @S10 @variant:experimental-features
// Scenario: Timing is broken into phases when the proxy recorded them
//   Given a request with queue 2 ms, connect 15 ms, send 5 ms, time to first byte 180 ms, receive 65 ms and total 260 ms
//   When I open the request
//   Then the timing bar has segments titled "Queue: 2 ms", "Connect: 15 ms", "Send: 5 ms", "Processing: 158 ms" and "Recv: 65 ms"
//   And it reads "0 ms" to "260 ms" with a "TTFB: 180 ms" marker
//   And the legend includes "Proxy overhead"
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    event: {
      request_method: 'GET',
      request_path: '/patients',
      response_status: 200,
      queue_us: 2000,
      connect_us: 15_000,
      request_send_us: 5000,
      ttfb_us: 180_000,
      response_duration_us: 65_000,
      latency_us: 260_000,
    },
  });

  expect(await segmentTitles(page)).toEqual([
    'Queue: 2 ms',
    'Connect: 15 ms',
    'Send: 5 ms',
    'Processing: 158 ms',
    'Recv: 65 ms',
  ]);
  const timing = section(page, 'Timing');
  await expect(timing.getByText('0 ms', { exact: true })).toBeVisible();
  await expect(timing.getByText('260 ms', { exact: true })).toBeVisible();
  await expect(timing.getByText(/^\s*TTFB: 180 ms\s*$/).first()).toBeVisible();
  await expect(timing.getByText(/^\s*Proxy overhead\s*$/)).toBeVisible();
});

// @S11 @variant:experimental-features
// Scenario: A reused connection is marked instead of showing a connect time
//   Given a request that reused an open connection to the destination
//   When I open the request
//   Then the timing bar shows a "Connect" segment badged "(reused)"
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onRequest(page, {
    event: {
      request_method: 'GET',
      request_path: '/patients',
      response_status: 200,
      queue_us: 0,
      connect_us: 0,
      reused_connection: true,
      request_send_us: 5000,
      ttfb_us: 100_000,
      response_duration_us: 20_000,
      latency_us: 130_000,
    },
  });

  expect(await segmentTitles(page)).toContain('Connect: 0 ms');
  await expect(
    section(page, 'Timing').getByText('(reused)', { exact: true })
  ).toBeVisible();
});

// @S12 @variant:experimental-features
// Scenario: Timing degrades when fewer measurements exist
//   Given a request with only time to first byte 280 ms and total 350 ms
//   When I open the request
//   Then the timing bar has "TTFB: 280 ms" and "Download: 70 ms" segments and no "Proxy overhead"
//   And a request with only a total of 420 ms shows a single "Total: 420 ms" segment
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject();
  const event = { request_method: 'GET', request_path: '/patients' };
  const {
    ids: [partial, minimal],
  } = givenRequests(projectId, [
    {
      at: '2026-01-01 10:00:00',
      event: { ...event, ttfb_us: 280_000, latency_us: 350_000 },
    },
    { at: '2026-01-01 10:01:00', event: { ...event, latency_us: 420_000 } },
  ]);

  await openRequest(page, projectId, partial);

  expect(await segmentTitles(page)).toEqual([
    'TTFB: 280 ms',
    'Download: 70 ms',
  ]);
  await expect(section(page, 'Timing')).not.toContainText('Proxy overhead');

  await open(page, requestPath(projectId, minimal));

  expect(await segmentTitles(page)).toEqual(['Total: 420 ms']);
});

// @S13 @variant:experimental-features
// Scenario: The request shows which client key and destination credential it used
//   Given client auth method "Prod API key" of type API key matched the request
//   And the channel sent it with destination credential "Destination API"
//   When I open the request
//   Then client auth reads "Prod API key (API key)"
//   And destination auth reads "Destination API"
//   And a request with no client auth configured reads "None"
//   And the flow "flow-channel-proxy-request" is what recorded the matched method
// The requests are stored as that flow records them; the flow itself is
// not run here.
test('@S13', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject(
    { [ME]: 'viewer' },
    { credentials: ['Destination API'] }
  );
  const method = addWebhookAuthMethodOnNode(projectId, 'Prod API key', OWNER);
  const {
    ids: [authed, unauthed],
  } = givenRequests(projectId, [
    {
      at: '2026-01-01 10:00:00',
      request: {
        client_auth_type: 'api',
        client_webhook_auth_method_id: method,
        destination_credential_id: projectCredentialId(
          projectId,
          'Destination API'
        ),
      },
    },
    { at: '2026-01-01 10:01:00' },
  ]);

  await openRequest(page, projectId, authed);

  await expect(valueOf(group(page, 'Client'), 'Auth')).toHaveText(
    /^\s*Prod API key \(API key\)\s*$/
  );
  await expect(valueOf(group(page, 'Destination'), 'Auth')).toHaveText(
    /^\s*Destination API\s*$/
  );

  await open(page, requestPath(projectId, unauthed));

  await expect(valueOf(group(page, 'Client'), 'Auth')).toHaveText(
    /^\s*None\s*$/
  );
});

// @S14 @variant:experimental-features
// Scenario: A deleted auth method or credential is labelled deleted
//   Given a request whose client auth method has since been deleted
//   And whose destination credential has since been deleted
//   When I open the request
//   Then client auth reads "(deleted) (API key)"
//   And destination auth reads "(deleted)"
// Both are deleted from the database as Lightning deletes them, after the
// request was stored (annotation 6.1 expects today's page to read "None").
// @pending on today's Lightning: client auth reads "API key" and destination auth "None", with no "(deleted)".
test('@S14', { tag: '@pending' }, async ({ page }) => {
  const { id: projectId } = givenProject(
    { [ME]: 'viewer' },
    { credentials: ['Destination API'] }
  );
  const method = addWebhookAuthMethodOnNode(projectId, 'Prod API key', OWNER);
  const credential = projectCredentialId(projectId, 'Destination API');
  const {
    ids: [id],
  } = givenRequests(projectId, [
    {
      at: '2026-01-01 10:00:00',
      request: {
        client_auth_type: 'api',
        client_webhook_auth_method_id: method,
        destination_credential_id: credential,
      },
    },
  ]);
  exec(`delete from webhook_auth_methods where id = '${method}';
        delete from project_credentials where id = '${credential}'`);

  await openRequest(page, projectId, id);

  await expect
    .soft(valueOf(group(page, 'Client'), 'Auth'))
    .toHaveText(/^\s*\(deleted\) \(API key\)\s*$/);
  await expect
    .soft(valueOf(group(page, 'Destination'), 'Auth'))
    .toHaveText(/^\s*\(deleted\)\s*$/);
});

// @S15 @variant:experimental-features
// Scenario: Context shows the config the request ran on and flags later changes
//   Given a request made on channel config version 1
//   And the channel has since been renamed, making it version 2
//   When I open the request and expand "Context"
//   Then I see the destination URL, channel name and config version 1 from that time
//   And a "Config changed" badge
// The version is read from the channel when the request is stored, rather
// than assumed to be 1.
test('@S15', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject();
  const {
    channelId,
    ids: [id],
  } = givenRequests(projectId, [{ at: '2026-01-01 10:00:00' }]);
  const [{ lock_version: version }] = sql<{ lock_version: number }>(
    `select lock_version from channels where id = '${channelId}'`
  );
  renameChannelOnNode(channelId, 'orders-proxy-v2', OWNER);

  await openRequest(page, projectId, id);
  await toggle(page, 'Context').click();

  const context = section(page, 'Context');
  await expect(valueOf(context, 'Destination URL')).toHaveText(
    'https://destination.example.com/data'
  );
  await expect(valueOf(context, 'Channel Name')).toHaveText('orders-proxy');
  await expect(valueOf(context, 'Config Version')).toHaveText(
    new RegExp(`^\\s*${version}(?!\\d)`)
  );
  await expect(
    context.getByText('Config changed', { exact: true })
  ).toBeVisible();
});

// @S16 @variant:experimental-features
// Scenario: Admin sees that request data was not kept and where to change that
//   Given I am an admin and the project keeps no request or response data
//   And a request was recorded as wiped by the flow "flow-zero-persistence-channel-requests"
//   When I open the request
//   Then instead of the request and response sections I see "No Request/Response Data here!"
//   And "Request/Response data for this channel request has not been retained"
//   And a "this policy" link to "/projects/<project_id>/settings#data-storage" "for future requests"
//   And I do not see "rerun this work order"
// The request is stored through Lightning's own rule for what the project
// keeps, which wipes it.
test('@S16', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject({ [ME]: 'admin' });
  keepNoData(projectId);
  const {
    ids: [id],
  } = givenRequests(projectId, [{ at: '2026-01-01 10:00:00', path: '/data' }]);

  await openRequest(page, projectId, id);

  await expect(
    page.getByText('No Request/Response Data here!', { exact: true })
  ).toBeVisible();
  await expect(
    page.getByText(
      /Request\/Response data for this channel request has not been\s+retained/
    )
  ).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'this policy', exact: true })
  ).toHaveAttribute('href', `/projects/${projectId}/settings#data-storage`);
  await expect(page.getByText(/for future requests/)).toBeVisible();
  await expect(page.getByText(/rerun this work order/)).toHaveCount(0);
  await expect(toggle(page, 'Request')).toHaveCount(0);
  await expect(toggle(page, 'Response')).toHaveCount(0);
});

// @S17 @variant:experimental-features
// Scenario: Non-admin on a wiped request is told whom to ask
//   Given I am an editor and "admin@example.com" is an admin on the project
//   And a wiped request
//   When I open the request
//   Then I see "Contact one of your project admins for more information."
//   And hovering "project admins" shows "admin@example.com"
//   And there is no link to the data storage settings
// The admin is super@openfn.org.
test('@S17', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject({ [ME]: 'editor', [THIRD]: 'admin' });
  keepNoData(projectId);
  const {
    ids: [id],
  } = givenRequests(projectId, [{ at: '2026-01-01 10:00:00', path: '/data' }]);

  await openRequest(page, projectId, id);

  await expect(
    page.getByText(
      /Contact one of your\s+project admins\s+for more information\./
    )
  ).toBeVisible();
  await expectTooltip(
    page,
    page.getByText('project admins', { exact: true }),
    user(THIRD).email
  );
  await expect(page.getByRole('link', { name: 'this policy' })).toHaveCount(0);
});

// @S18 @variant:experimental-features
// Scenario: A request from another project cannot be opened
//   Given a channel request belonging to another project
//   When I open "/projects/<my project>/history/channels/<that request id>"
//   Then I am redirected to "/projects/<my project>/history"
//   And I am also redirected there for "/projects/<my project>/history/channels/not-a-uuid"
test('@S18', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const mine = givenProject();
  const theirs = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const {
    ids: [id],
  } = givenRequests(theirs.id, [{ at: '2026-01-01 10:00:00', path: '/x' }]);

  await signInAs(page, ME);
  await page.goto(requestPath(mine.id, id));
  await expectAt(page, `/projects/${mine.id}/history`);

  await page.goto(requestPath(mine.id, 'not-a-uuid'));
  await expectAt(page, `/projects/${mine.id}/history`);
});

// @S19 @variant:default
// Scenario: Without experimental features the page is not available
//   Given I have not enabled experimental features
//   When I open a channel request in my project
//   Then I am redirected to "/projects/<project_id>/history"
// The same request opens once the features are on, so the redirect is
// what the setting does.
test('@S19', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject();
  const {
    ids: [id],
  } = givenRequests(projectId, [{ at: '2026-01-01 10:00:00', path: '/x' }]);
  setPreferences(ME, { experimental_features: false });

  await signInAs(page, ME);
  await page.goto(requestPath(projectId, id));
  await expectAt(page, `/projects/${projectId}/history`);

  setPreferences(ME, { experimental_features: true });
  await open(page, requestPath(projectId, id));
  await expectAt(page, requestPath(projectId, id));
});

// @S20 @variant:experimental-features
// Scenario: Breadcrumbs lead back to the channel logs and the channel name to its settings
//   Given a request on channel "orders-proxy"
//   When I open the request
//   Then the breadcrumbs read "History", "Channels" and "Channel Request" with the request's short id
//   And "Channels" links to "/projects/<project_id>/history/channels"
//   And "orders-proxy" links to "/projects/<project_id>/channels/<channel_id>/edit"
test('@S20', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { projectId, channelId, id } = await onRequest(page, { path: '/x' });

  const trail = page.getByRole('navigation', { name: 'Breadcrumbs' });
  await expect
    .poll(async () =>
      (await trail.getByRole('listitem').allInnerTexts())
        .map(text => text.trim().replace(/\s+/g, ' '))
        .slice(-3)
    )
    .toEqual(['History', 'Channels', `Channel Request ${shortId(id)}`]);
  await expect(
    trail.getByRole('link', { name: 'Channels', exact: true })
  ).toHaveAttribute('href', `/projects/${projectId}/history/channels`);
  await expect(
    page.getByRole('link', { name: 'orders-proxy', exact: true })
  ).toHaveAttribute(
    'href',
    `/projects/${projectId}/channels/${channelId}/edit`
  );
});

// @S21 @variant:experimental-features
// Scenario: The request id, bodies and hashes can be copied
//   Given a request with a JSON response body
//   When I click "Copy request ID", "Copy body" or "Copy hash"
//   Then the full request id, the body preview or the full hash is copied to the clipboard
test('@S21', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const body = '{"status":"stored"}';
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  const { id } = await onRequest(page, {
    event: {
      request_method: 'GET',
      request_path: '/patients',
      response_status: 200,
      response_headers: JSON_HEADERS,
      response_body_preview: body,
      response_body_size: body.length,
      response_body_hash: HASH,
    },
  });

  for (const [name, copied] of [
    ['Copy request ID', id],
    ['Copy body', body],
    ['Copy hash', HASH],
  ]) {
    await page.evaluate(() => navigator.clipboard.writeText('untouched'));
    await copyButton(page, name).click();
    await expect.poll(() => clipboard(page)).toBe(copied);
  }
});

// Inherited shared annotations, run on a request page with my experimental
// features on (without them the page redirects, S19)
const PENDING = { tag: '@pending' };
const PASSING = { tag: ['@passing-old', '@passing-new'] };

// Given project "Malawi HIV" (or <name>) with these members and a channel
// that logged one request
function givenRequestPage(
  members: Record<string, Role> = { [ME]: 'owner' },
  name = 'Malawi HIV'
) {
  const project = givenProject(members, { name });
  const {
    channelId,
    ids: [requestId],
  } = givenRequests(project.id, [{ at: '2026-01-01 10:00:00', path: '/x' }]);
  return {
    ...project,
    channelId,
    requestId,
    path: requestPath(project.id, requestId),
  };
}

// Something only the request page shows
const shown = (page: Page) => copyButton(page, 'Copy request ID');

test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on channel-request-show',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S01(page, givenRequestPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on channel-request-show',
    PASSING,
    async ({ page, browser }) => {
      await authenticatedSession.S02(
        page,
        browser,
        givenRequestPage().path,
        ME
      );
    }
  );

  test(
    'shared-authenticated-session@S03 on channel-request-show',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S03(page, givenRequestPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on channel-request-show',
    PASSING,
    async ({ page, browser }) => {
      const h = givenRequestPage();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.id}/w`,
        ME,
        'History'
      );
    }
  );

  // These variants are not configured on this instance
  for (const [id, variant] of [
    ['S04', 'require-email-verification'],
    ['S05', 'require-email-verification'],
    ['S06', 'require-email-verification'],
    ['S08', 'book-demo-banner'],
    ['S09', 'book-demo-banner'],
    ['S10', 'gdpr-banner'],
    ['S11', 'first-setup-open'],
  ])
    test(
      `shared-authenticated-session@${id} on channel-request-show`,
      PENDING,
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

test.describe('shared-project-scope', () => {
  test(
    'shared-project-scope@S01 on channel-request-show',
    PASSING,
    async ({ page }) => {
      await projectScope.S01(page, givenRequestPage().path);
    }
  );

  test(
    'shared-project-scope@S02 on channel-request-show',
    PASSING,
    async ({ page }) => {
      await projectScope.S02(page, givenRequestPage().path, ME, shown(page));
    }
  );

  test(
    'shared-project-scope@S03 on channel-request-show',
    PASSING,
    async ({ page }) => {
      setPreferences(ME, { experimental_features: true });
      await projectScope.S03(
        page,
        givenRequestPage({ [OWNER]: 'owner' }).path,
        ME
      );
    }
  );

  test(
    'shared-project-scope@S04 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [OWNER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.id}'`
      );
      await projectScope.S04(page, h.path, OWNER);
    }
  );

  test(
    'shared-project-scope@S05 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage();
      exec(`update projects set requires_mfa = true where id = '${h.id}'`);
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on channel-request-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenRequestPage({ [OWNER]: 'owner' });
      setPreferences(ME, { experimental_features: true });
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, shown(page));
    }
  );

  test(
    'shared-project-scope@S07 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'editor', [OWNER]: 'owner' });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.id, ME, OWNER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'admin', [OWNER]: 'owner' });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.id, ME, 'viewer'),
        shown(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on channel-request-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenRequestPage({ [OWNER]: 'owner' });
      setPreferences(ME, { experimental_features: true });
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S09(page, h.path, ME, () =>
        setSupportAccessOnNode(h.id, false)
      );
    }
  );

  test(
    'shared-project-scope@S10 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'editor', [OWNER]: 'owner' });
      await projectScope.S10(page, h.path, ME, () =>
        scheduleDeletionOnNode(h.id)
      );
    }
  );

  // shared-project-scope S11 and S12 are not run on this page: they are about
  // an open workflow editor (archived sandbox, deleted workflow), and this
  // page holds no workflow open.
});

// The picker scenarios seed their own "Malawi HIV", so this page's project
// has another name.
test.describe('shared-project-header', () => {
  const HOST = 'Channel request host';

  test(
    'shared-project-header@S01 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S01(page, h.path, ME, HOST, [
        { name: 'History', href: `/projects/${h.id}/history` },
        { name: 'Channels', href: `/projects/${h.id}/history/channels` },
        { name: `Channel Request ${shortId(h.requestId)}` },
      ]);
    }
  );

  test(
    'shared-project-header@S02 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on channel-request-show',
    PASSING,
    async ({ page }) => {
      setPreferences(ME, { experimental_features: true });
      const w = seedWorkspace(
        {
          name: HOST,
          members: { [ME]: 'editor', [OWNER]: 'owner' },
          sandboxes: [
            { name: 'dev', color: '#E33D63', members: { [ME]: 'editor' } },
          ],
        },
        OWNER
      );
      cleanups.push(w.remove);
      const dev = w.id('dev');
      cleanups.push(() => removeChannelsOf(dev));
      const {
        ids: [id],
      } = givenRequests(dev, [{ at: '2026-01-01 10:00:00', path: '/x' }]);
      await projectHeader.S03(page, ME, {
        path: requestPath(dev, id),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on channel-request-show`,
      PASSING,
      async ({ page }) => {
        const h = givenRequestPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on channel-request-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, whatever page hosts the header
  test(
    'shared-project-header@S09 on channel-request-show',
    PASSING,
    async ({ page }) => {
      setPreferences(ME, { experimental_features: true });
      await projectHeader.S09(page, ME);
    }
  );

  // The request exists only in this project, so its page has no equivalent
  // in "Kenya TB"; the page sends a missing request to History.
  test(
    'shared-project-header@S10 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S10(page, h.path, ME, '/history');
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on channel-request-show`,
      PASSING,
      async ({ page }) => {
        const h = givenRequestPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test('shared-project-header@S14 on channel-request-show', PENDING, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

  // This page marks "History" in the side menu
  test(
    'shared-project-header@S15 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'viewer' }, HOST);
      await projectHeader.S15(page, h.path, ME, h.id, 'History');
    }
  );

  // S16 turns the features off, and then this page redirects to History.
  // Its own header is what is checked before that.
  test(
    'shared-project-header@S16 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  // A superuser needs a role on the project to open this page at all
  test(
    'shared-project-header@S17 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage({ [ME]: 'viewer', [THIRD]: 'viewer' }, HOST);
      await projectHeader.S17(page, h.path);
    }
  );
});

// Inherited from shared-local-datetime: the summary's "Started" time, and
// "Completed" for S07.
test.describe('shared-local-datetime', () => {
  // Given a request that started at <utc> (and never completed), and today
  // is <today>, when I open it — returns the summary's timing group
  async function requestAt(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    const { id: projectId } = givenProject();
    const {
      ids: [id],
    } = givenRequests(projectId, [{ at: utc }]);
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, requestPath(projectId, id));
    return group(page, 'Timing');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on channel-request-show',
      PASSING,
      async ({ page }) => {
        const timing = await requestAt(page, localDatetime.given.S01);
        await localDatetime.S01(page, valueOf(timing, 'Started'));
      }
    );
  });

  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on channel-request-show`,
      PASSING,
      async ({ page }) => {
        const timing = await requestAt(page, localDatetime.given[id]);
        await localDatetime[id](page, valueOf(timing, 'Started'));
      }
    );

  test(
    'shared-local-datetime@S07 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const timing = await requestAt(page, { utc: '2026-01-01 10:00:00' });
      await localDatetime.S07(page, valueOf(timing, 'Completed'));
    }
  );

  // shared-local-datetime S03 is not run on this page: Started and
  // Completed use the default format, never relative_detailed.
});

// This page puts no flash of its own: it has no action, and its redirects
// carry none.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S06 on channel-request-show',
    PASSING,
    async ({ page }) => {
      const h = givenRequestPage();
      const notMine = givenRequestPage({ [OWNER]: 'owner' }, 'Kenya TB');
      await signInAs(page, ME);
      await open(page, h.path);

      await flashMessages.S06(
        page,
        () => open(page, notMine.path),
        '/projects',
        page.getByRole('cell', {
          name: manifest().projects[0].name,
          exact: true,
        })
      );
    }
  );

  // shared-flash-messages S01 to S05 are not run on this page: it shows no
  // info or error flash of its own and no action here redirects with one.
  // S07 is on admin pages (settings layout) and S08 on the sign-in and
  // account forms.
});

// shared-run-components is not run on this page: not_reachable_here
// excludes everything but the channel state pill, whose labels
// history-channel-logs S05 owns. S01 above reads "Success" and S09
// "Timeout".
