// Scenarios from annotations/views/history-channel-logs.md.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names (a viewer unless it says otherwise). owner@openfn.org owns every
// project and seeds its channels through Lightning. super@openfn.org is the
// third member a test needs. Every project is seeded by the test and removed
// again afterwards, with its channels and their logged requests. Requests are
// stored on the node as the proxy stores them.
import { expect, test, type Page } from '@playwright/test';

import {
  channelChip,
  channelChoices,
  chooseChannel,
  clearChannelButton,
  historyTab,
  listedRequests,
  requestCell,
  requestRow,
} from './pages/history-channel-logs';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  changeRoleOnNode,
  channelLogsPath,
  exec,
  expectAt,
  historySearchBox,
  keepAccount,
  keepNoData,
  lookOf,
  makeSupportUser,
  manifest,
  open,
  queryOf,
  removeChannelsOf,
  removeMemberOnNode,
  removeMfaOf,
  scheduleDeletionOnNode,
  seedChannel,
  seedChannelRequests,
  seedWorkspace,
  setPreferences,
  setSupportAccessOnNode,
  shortId,
  signInAs,
  type ChannelRequestSeed,
  type SeededChannelRequest,
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

// Given project <name> exists with these members (owner@openfn.org owns it);
// removed after the test with its channels — returns its id
function givenProject(
  members: Record<string, Role> = { [ME]: 'viewer' },
  { name = 'Malawi HIV', ...rest }: Partial<WorkspaceSeed> = {}
) {
  const owned = Object.values(members).includes('owner')
    ? members
    : { ...members, [OWNER]: 'owner' as const };
  const by = Object.entries(owned).find(([, r]) => r === 'owner')![0];
  const w = seedWorkspace({ name, members: owned, ...rest }, by);
  cleanups.push(w.remove);
  const id = w.id(name);
  // Runs before the project is removed: logged requests would stop it
  cleanups.push(() => removeChannelsOf(id));
  return { id, w, by };
}

// Given project <projectId> has channel <name>, which logged <requests> —
// returns the channel's id and the requests
function givenChannel(
  projectId: string,
  name: string,
  requests: ChannelRequestSeed[] = []
) {
  const id = seedChannel(projectId, { name }, OWNER);
  return { id, requests: seedChannelRequests(id, requests) };
}

// <n> requests <step> minutes apart from 1 January 2026 at <hour>:<offset>,
// oldest first
const requestsAt = (n: number, hour: string, offset = 0, step = 2) =>
  Array.from({ length: n }, (_, i) => ({
    at: `2026-01-01 ${hour}:${String(offset + i * step).padStart(2, '0')}:00`,
  }));

const ids = (requests: SeededChannelRequest[]) =>
  requests.map(r => shortId(r.requestId));

// Given I have experimental features enabled and am signed in
async function signedInWithFlag(page: Page, email = ME) {
  setPreferences(email, { experimental_features: true });
  await signInAs(page, email);
}

// Given I have experimental features enabled, when I open the channel logs
// tab of <projectId> (filtered to <channelId>)
async function onLogs(page: Page, projectId: string, channelId?: string) {
  await signedInWithFlag(page);
  await open(page, channelLogsPath(projectId, channelId));
}

// Then the list shows exactly these requests, newest first
const expectListed = (page: Page, requests: SeededChannelRequest[]) =>
  expect.poll(() => listedRequests(page)).toEqual(ids(requests));

const newestFirst = (requests: SeededChannelRequest[]) =>
  [...requests].reverse();

const pageLink = (page: Page, n: number) =>
  page
    .getByRole('navigation', { name: 'Pagination' })
    .getByRole('link', { name: String(n), exact: true });

const ALL_CHANNELS = /^\s*All channels\s*$/i;

// @S01 @variant:experimental-features
// Scenario: Members see the project's channel requests, newest first
//   Given I have experimental features enabled
//   And channel "test-channel" in my project received a request on 1 January and another on 2 January
//   When I open the channel logs tab
//   Then I see both requests
//   And the 2 January request is listed first
//   And each row shows the channel name "test-channel"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const { requests } = givenChannel(id, 'test-channel', [
    { at: '2026-01-01 10:00:00' },
    { at: '2026-01-02 10:00:00' },
  ]);

  await onLogs(page, id);

  await expectListed(page, newestFirst(requests));
  for (const r of requests)
    await expect(
      await requestCell(page, requestRow(page, r.requestId), 'Channel name')
    ).toHaveText('test-channel');
});

// @S02 @variant:experimental-features
// Scenario: A project with no channel requests says so
//   Given I have experimental features enabled
//   And no request has passed through any channel in my project
//   When I open the channel logs tab
//   Then I see "No channel requests found."
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, 'quiet-channel');

  await onLogs(page, id);

  await expect(page.getByText('No channel requests found.')).toBeVisible();
  expect(await listedRequests(page)).toEqual([]);
});

// @S03 @variant:experimental-features
// Scenario: Requests from other projects are never listed
//   Given I have experimental features enabled
//   And a channel in project "Kenya TB" has received a request
//   And I am a member of "Malawi HIV" but not of "Kenya TB"
//   When I open the "Malawi HIV" channel logs tab
//   Then I do not see the "Kenya TB" request
//   And when I open "Malawi HIV" channel logs with "filters[channel_id]" set to the "Kenya TB" channel's id
//   Then I see no requests
// The Value is that Kenya TB's request never shows. Malawi HIV has a request
// of its own, so the list is known to be drawn. With Kenya TB's channel in
// the URL today's tab lists nothing, while the port treats an unknown
// channel as any channel (annotation 6.1); either way Kenya TB's stays out.
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = givenProject();
  const kenya = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const mine = givenChannel(malawi.id, 'malawi-channel', [
    { at: '2026-01-01 10:00:00' },
  ]);
  const theirs = givenChannel(kenya.id, 'kenya-channel', [
    { at: '2026-01-02 10:00:00' },
  ]);
  const [kenyaRequest] = theirs.requests;

  await onLogs(page, malawi.id);

  await expectListed(page, mine.requests);
  await expect(requestRow(page, kenyaRequest.requestId)).toHaveCount(0);

  await open(page, channelLogsPath(malawi.id, theirs.id));

  await expect(channelChip(page)).toBeVisible();
  await expect(requestRow(page, kenyaRequest.requestId)).toHaveCount(0);
  expect(await listedRequests(page)).not.toContain(
    shortId(kenyaRequest.requestId)
  );
});

// @S04 @variant:experimental-features
// Scenario: Each row shows the request's path, status and error message
//   Given I have experimental features enabled
//   And request "A" reached the destination at path "/some/upstream/path" and succeeded
//   And request "B" failed in the proxy with error message "connect timeout"
//   When I open the channel logs tab
//   Then row "A" shows path "/some/upstream/path" and status "Success"
//   And row "B" shows error message "connect timeout" and status "Error"
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const {
    requests: [a, b],
  } = givenChannel(id, 'test-channel', [
    { at: '2026-01-01 10:00:00', path: '/some/upstream/path' },
    { at: '2026-01-01 10:01:00', state: 'error', error: 'connect timeout' },
  ]);

  await onLogs(page, id);

  const rowA = requestRow(page, a.requestId);
  await expect(await requestCell(page, rowA, 'Request path')).toHaveText(
    '/some/upstream/path'
  );
  await expect(await requestCell(page, rowA, 'Status')).toHaveText('Success');

  const rowB = requestRow(page, b.requestId);
  await expect(await requestCell(page, rowB, 'Error message')).toHaveText(
    'connect timeout'
  );
  await expect(await requestCell(page, rowB, 'Status')).toHaveText('Error');
});

// @S05 @variant:experimental-features
// Scenario Outline: Request states show as labelled pills
//   Given I have experimental features enabled
//   And a channel request in state <state>
//   When I open the channel logs tab
//   Then its status reads <label>
//   Examples:
//     | state   | label       |
//     | pending | In progress |
//     | success | Success     |
//     | failed  | Failed      |
//     | timeout | Timeout     |
//     | error   | Error       |
// Every example is one request on one page; the labels are matched in any
// letter case (today's reads "In Progress", annotation 6.2).
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const examples = [
    ['pending', 'In progress'],
    ['success', 'Success'],
    ['failed', 'Failed'],
    ['timeout', 'Timeout'],
    ['error', 'Error'],
  ] as const;
  const { id } = givenProject();
  const { requests } = givenChannel(
    id,
    'test-channel',
    examples.map(([state], i) => ({ at: `2026-01-01 10:0${i}:00`, state }))
  );

  await onLogs(page, id);

  for (const [i, [, label]] of examples.entries())
    await expect
      .soft(
        await requestCell(
          page,
          requestRow(page, requests[i].requestId),
          'Status'
        )
      )
      .toHaveText(new RegExp(`^\\s*${label}\\s*$`, 'i'));
});

// @S06 @variant:experimental-features
// Scenario: Filter by channel from the dropdown
//   Given I have experimental features enabled
//   And channels "channel-one" and "channel-two" each have a request
//   When I open the channel logs tab
//   And I open the "Channel is any" chip and choose "channel-one"
//   Then the URL carries "filters[channel_id]=<channel-one id>"
//   And I see only "channel-one"'s request
//   And the chip reads "Channel is channel-one"
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const one = givenChannel(id, 'channel-one', [{ at: '2026-01-01 10:00:00' }]);
  const two = givenChannel(id, 'channel-two', [{ at: '2026-01-01 10:01:00' }]);

  await onLogs(page, id);
  await expectListed(page, [...two.requests, ...one.requests]);
  await expect(channelChip(page)).toHaveText(/^\s*Channel is\s+any\s*$/);

  await chooseChannel(page, 'channel-one');

  await expect.poll(() => queryOf(page)['filters[channel_id]']).toBe(one.id);
  await expectListed(page, one.requests);
  await expect(channelChip(page)).toHaveText(
    /^\s*Channel is\s+channel-one\s*$/
  );
});

// @S07 @variant:experimental-features
// Scenario: Clearing the channel filter lists every channel again
//   Given I have experimental features enabled
//   And I am viewing channel logs filtered to "channel-one"
//   When I click "Clear filter" on the channel chip
//   Then I see requests from every channel in the project
//   And the chip reads "Channel is any"
//   And choosing "All channels" from the dropdown does the same
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const one = givenChannel(id, 'channel-one', [{ at: '2026-01-01 10:00:00' }]);
  const two = givenChannel(id, 'channel-two', [{ at: '2026-01-01 10:01:00' }]);
  const every = [...two.requests, ...one.requests];

  await onLogs(page, id, one.id);
  await expectListed(page, one.requests);

  await clearChannelButton(page).click();

  await expectListed(page, every);
  await expect(channelChip(page)).toHaveText(/^\s*Channel is\s+any\s*$/);
  await expect(clearChannelButton(page)).toHaveCount(0);

  await open(page, channelLogsPath(id, one.id));
  await expectListed(page, one.requests);

  await chooseChannel(page, ALL_CHANNELS);

  await expectListed(page, every);
  await expect(channelChip(page)).toHaveText(/^\s*Channel is\s+any\s*$/);
});

// @S08 @variant:experimental-features
// Scenario: The dropdown lists the project's channels by name
//   Given I have experimental features enabled
//   And my project has channels "bravo" and "alpha"
//   When I open the channel chip's dropdown
//   Then I see "All channels", "alpha", "bravo" in that order
//   And no channel from another project
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const other = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  givenChannel(id, 'bravo');
  givenChannel(id, 'alpha');
  givenChannel(other.id, 'charlie');

  await onLogs(page, id);
  await channelChip(page).click();

  await expect(channelChoices(page)).toHaveCount(3);
  const [all, ...names] = (await channelChoices(page).allInnerTexts()).map(t =>
    t.trim()
  );
  expect(all).toMatch(ALL_CHANNELS);
  expect(names).toEqual(['alpha', 'bravo']);
});

// @S09 @variant:experimental-features
// Scenario: Clicking a row's channel name filters to that channel
//   Given I have experimental features enabled
//   And requests from "channel-one" and "channel-two" are listed
//   When I click "channel-one" in a row
//   Then I see only "channel-one"'s requests
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const one = givenChannel(id, 'channel-one', [
    { at: '2026-01-01 10:00:00' },
    { at: '2026-01-01 10:02:00' },
  ]);
  const two = givenChannel(id, 'channel-two', [{ at: '2026-01-01 10:01:00' }]);

  await onLogs(page, id);
  await expectListed(page, [one.requests[1], ...two.requests, one.requests[0]]);

  const row = requestRow(page, one.requests[0].requestId);
  await (await requestCell(page, row, 'Channel name'))
    .getByRole('link', { name: 'channel-one', exact: true })
    .click();

  await expectListed(page, newestFirst(one.requests));
});

// @S10 @variant:experimental-features
// Scenario: Arriving from the channels page shows that channel's requests
//   Given I have experimental features enabled
//   When I follow a link to channel logs with "filters[channel_id]" set to "channel-one"
//   Then I see only "channel-one"'s requests and the chip reads "Channel is channel-one"
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const one = givenChannel(id, 'channel-one', [{ at: '2026-01-01 10:00:00' }]);
  givenChannel(id, 'channel-two', [{ at: '2026-01-01 10:01:00' }]);

  await onLogs(page, id, one.id);

  await expectListed(page, one.requests);
  await expect(channelChip(page)).toHaveText(
    /^\s*Channel is\s+channel-one\s*$/
  );
});

// @S11 @variant:experimental-features
// Scenario: Paging keeps the channel filter
//   Given I have experimental features enabled
//   And "channel-one" has 15 requests and "channel-two" has 5
//   And I am viewing channel logs filtered to "channel-one"
//   Then I see "Showing 1 to 10 of 15 total results"
//   When I go to page 2
//   Then I see the remaining 5 "channel-one" requests and no "channel-two" request
// "channel-two"'s requests fall between "channel-one"'s, so page 2 without
// the filter would hold some of them.
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const one = givenChannel(id, 'channel-one', requestsAt(15, '10'));
  const two = givenChannel(id, 'channel-two', requestsAt(5, '10', 1));
  const ones = newestFirst(one.requests);

  await onLogs(page, id, one.id);

  await expectListed(page, ones.slice(0, 10));
  await expect(
    page.getByText(/Showing\s+1\s+to\s+10\s+of\s+15\s+total results/)
  ).toBeVisible();

  await pageLink(page, 2).click();

  await expectListed(page, ones.slice(10));
  for (const r of two.requests)
    await expect(requestRow(page, r.requestId)).toHaveCount(0);
});

// @S12 @variant:experimental-features
// Scenario: Changing the channel filter returns to page 1
//   Given I have experimental features enabled
//   And I am on page 2 of all channel requests
//   When I choose a channel from the dropdown
//   Then I am on page 1 of that channel's requests
// "channel-two"'s 5 requests are the oldest, so page 2 of all 13 shows only
// 3 of them, and page 1 of "channel-two" shows all 5.
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, 'channel-one', requestsAt(8, '11'));
  const two = givenChannel(id, 'channel-two', requestsAt(5, '10'));
  const twos = newestFirst(two.requests);

  await onLogs(page, id);
  await pageLink(page, 2).click();
  await expectListed(page, twos.slice(2));

  await chooseChannel(page, 'channel-two');

  await expectListed(page, twos);
  expect(queryOf(page).page ?? '1').toBe('1');
});

// @S13 @variant:experimental-features
// Scenario: A request's ID opens its detail page
//   Given I have experimental features enabled
//   And request "A" is listed
//   Then its ID cell shows the first 8 characters of its request ID, with the full ID on hover
//   And it links to "/projects/<project_id>/history/channels/<A's id>"
test('@S13', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const {
    requests: [a],
  } = givenChannel(id, 'test-channel', [{ at: '2026-01-01 10:00:00' }]);

  await onLogs(page, id);

  const link = (
    await requestCell(page, requestRow(page, a.requestId), 'Request ID')
  ).getByRole('link');
  await expect(link).toHaveText(shortId(a.requestId));
  // The full ID is what pointing at it shows
  await link.hover();
  await expect(link).toHaveAccessibleDescription(a.requestId);

  await link.click();

  await expectAt(page, `/projects/${id}/history/channels/${a.id}`);
});

// @S14 @variant:experimental-features
// Scenario: A request whose path was not kept shows a placeholder
//   Given I have experimental features enabled
//   And my project keeps no input or output data
//   And a request has passed through one of its channels
//   When I open the channel logs tab
//   Then its path cell reads "—"
//   And the flow "flow-zero-persistence-channel-requests" ends on this tab
// The request is stored through Lightning's own rule for what the project
// keeps, which drops the path it was given.
test('@S14', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  keepNoData(id);
  const {
    requests: [a],
  } = givenChannel(id, 'test-channel', [
    { at: '2026-01-01 10:00:00', path: '/some/upstream/path' },
  ]);

  await onLogs(page, id);

  await expect(
    await requestCell(page, requestRow(page, a.requestId), 'Request path')
  ).toHaveText('—');
});

// @S15 @variant:experimental-features
// Scenario: Members move between work orders and channel logs
//   Given I have experimental features enabled
//   When I open the channel logs tab
//   Then the "Channel logs" tab is selected
//   And the work orders filters and table are not shown
//   When I click "Work orders"
//   Then I am on "/projects/<project_id>/history"
// "Selected" is the look: the two tabs look different, and after the click
// "Work orders" takes the look "Channel logs" had.
test('@S15', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, 'test-channel', [{ at: '2026-01-01 10:00:00' }]);

  await onLogs(page, id);

  const channelLogs = historyTab(page, 'Channel Logs');
  const workOrders = historyTab(page, 'Work Orders');
  await expect(channelLogs).toBeVisible();
  const selected = await lookOf(channelLogs);
  expect(await lookOf(workOrders)).not.toBe(selected);
  await expect(historySearchBox(page)).toHaveCount(0);

  await workOrders.click();

  await expectAt(page, `/projects/${id}/history`);
  await expect
    .poll(() => lookOf(historyTab(page, 'Work Orders')))
    .toBe(selected);
});

// Inherited shared annotations, run on the channel logs tab without
// experimental features (the list draws the same; annotation 6.1)
const PENDING = { tag: '@pending' };
const PASSING = { tag: ['@passing-old', '@passing-new'] };

// Given project "Malawi HIV" (or <name>) with these members and a channel
// that logged one request
function givenLogsPage(
  members: Record<string, Role> = { [ME]: 'owner' },
  name = 'Malawi HIV'
) {
  const project = givenProject(members, { name });
  const channel = givenChannel(project.id, 'ch-1', [
    { at: '2026-01-01 10:00:00' },
  ]);
  return { ...project, channel, path: channelLogsPath(project.id) };
}

test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S01(page, givenLogsPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on history-channel-logs',
    PASSING,
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, givenLogsPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S03(page, givenLogsPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on history-channel-logs',
    PASSING,
    async ({ page, browser }) => {
      const h = givenLogsPage();
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
      `shared-authenticated-session@${id} on history-channel-logs`,
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
    'shared-project-scope@S01 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      await projectScope.S01(page, givenLogsPage().path);
    }
  );

  test(
    'shared-project-scope@S02 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      await projectScope.S02(page, givenLogsPage().path, ME, channelChip(page));
    }
  );

  test(
    'shared-project-scope@S03 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      await projectScope.S03(
        page,
        givenLogsPage({ [OWNER]: 'owner' }).path,
        ME
      );
    }
  );

  test(
    'shared-project-scope@S04 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [OWNER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.id}'`
      );
      await projectScope.S04(page, h.path, OWNER);
    }
  );

  test(
    'shared-project-scope@S05 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage();
      exec(`update projects set requires_mfa = true where id = '${h.id}'`);
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on history-channel-logs',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenLogsPage({ [OWNER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, channelChip(page));
    }
  );

  test(
    'shared-project-scope@S07 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'editor', [OWNER]: 'owner' });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.id, ME, OWNER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'admin', [OWNER]: 'owner' });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.id, ME, 'viewer'),
        channelChip(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on history-channel-logs',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenLogsPage({ [OWNER]: 'owner' });
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
    'shared-project-scope@S10 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'editor', [OWNER]: 'owner' });
      await projectScope.S10(page, h.path, ME, () =>
        scheduleDeletionOnNode(h.id)
      );
    }
  );

  // shared-project-scope S11 and S12 are not run on this page: they are about
  // an open workflow editor (archived sandbox, deleted workflow), and this
  // page holds no workflow open.
});

test.describe('shared-usage-limits-banner', () => {
  test(
    'shared-usage-limits-banner@S01 on history-channel-logs',
    PENDING,
    () => {
      test.skip(
        true,
        'variant usage-limited is not configured on this instance'
      );
    }
  );

  test(
    'shared-usage-limits-banner@S02 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      await usageLimitsBanner.S02(
        page,
        givenLogsPage().path,
        ME,
        channelChip(page)
      );
    }
  );
});

// The picker scenarios seed their own "Malawi HIV", so this page's project
// has another name.
test.describe('shared-project-header', () => {
  const HOST = 'Channel logs host';

  // Today's breadcrumb ends in "History" on this tab (annotation 6.2)
  test(
    'shared-project-header@S01 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S01(page, h.path, ME, HOST, [{ name: 'History' }]);
    }
  );

  test(
    'shared-project-header@S02 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on history-channel-logs',
    PASSING,
    async ({ page }) => {
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
      await projectHeader.S03(page, ME, {
        path: channelLogsPath(w.id('dev')),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on history-channel-logs`,
      PASSING,
      async ({ page }) => {
        const h = givenLogsPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on history-channel-logs',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, whatever page hosts the header
  test(
    'shared-project-header@S09 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // A channel filter names a channel that exists only in this project, so
  // the tab filtered to it has no equivalent in "Kenya TB". Today the picker
  // lands on History's work orders tab (annotation 6.2).
  test(
    'shared-project-header@S10 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S10(
        page,
        channelLogsPath(h.id, h.channel.id),
        ME,
        '/history'
      );
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on history-channel-logs`,
      PASSING,
      async ({ page }) => {
        const h = givenLogsPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test('shared-project-header@S14 on history-channel-logs', PENDING, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

  // This tab marks "History" in the side menu
  test(
    'shared-project-header@S15 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'viewer' }, HOST);
      await projectHeader.S15(page, h.path, ME, h.id, 'History');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  // A superuser needs a role on the project to open this page at all
  test(
    'shared-project-header@S17 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage({ [ME]: 'viewer', [THIRD]: 'viewer' }, HOST);
      await projectHeader.S17(page, h.path);
    }
  );
});

// Inherited from shared-local-datetime: the "Started At" column.
test.describe('shared-local-datetime', () => {
  // Given "ch-1" logged a request that started at <utc>, and today is <today>
  async function startedAt(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    const { id } = givenProject();
    const {
      requests: [r],
    } = givenChannel(id, 'ch-1', [{ at: utc }]);
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, channelLogsPath(id));
    return requestCell(page, requestRow(page, r.requestId), 'Started at');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on history-channel-logs',
      PASSING,
      async ({ page }) => {
        await localDatetime.S01(
          page,
          await startedAt(page, localDatetime.given.S01)
        );
      }
    );
  });

  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on history-channel-logs`,
      PASSING,
      async ({ page }) => {
        await localDatetime[id](
          page,
          await startedAt(page, localDatetime.given[id])
        );
      }
    );

  // shared-local-datetime S03 and S07 are not run on this page:
  // not_reachable_here does not exclude them, but the Started At column uses
  // the default format (never relative_detailed), and every logged request
  // has a start time.
});

// This tab puts no flash of its own: it has no action, and nothing redirects
// to it with one.
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S06 on history-channel-logs',
    PASSING,
    async ({ page }) => {
      const h = givenLogsPage();
      const notMine = givenLogsPage({ [OWNER]: 'owner' }, 'Kenya TB');
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
// excludes the run state pill, step icon, elapsed indicator and cancel
// (S01 to S14), and S15 to S18 are the editor run viewer. The channel state
// pill this tab shows is covered by S05 above.
