// Scenarios from annotations/views/channels-index.md.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns every project and seeds its channels,
// credentials and auth methods through Lightning. super@openfn.org is the
// third member a test needs. Every project is seeded by the test and removed
// again afterwards, with its channels and their logged requests.
import { expect, test, type Locator, type Page } from '@playwright/test';

import {
  channelCell,
  channelRow,
  channelSwitch,
  credentialSelect,
  deleteAndConfirm,
  deleteButton,
  editButton,
  newChannelButton,
  newChannelTipTarget,
  proxyUrlCopy,
  sendDelete,
  sendSave,
  sendToggle,
  totalCard,
} from './pages/channels-index';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  addWebhookAuthMethodOnNode,
  auditEventsOf,
  changeRoleOnNode,
  channelAuthOf,
  channelsOf,
  channelsPath,
  exec,
  expectAt,
  expectTooltip,
  field,
  keepAccount,
  lookOf,
  makeSupportUser,
  manifest,
  modal,
  modalTitle,
  open,
  projectCredentialId,
  queryOf,
  removeChannelsOf,
  removeMemberOnNode,
  removeMfaOf,
  scheduleDeletionOnNode,
  seedChannel,
  seedWorkspace,
  setPreferences,
  setSupportAccessOnNode,
  signInAs,
  sql,
  submit,
  user,
  watchLiveView,
  type ChannelSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it)
// and credentials; removed after the test with its channels — returns its id
function givenProject(
  members: Record<string, Role> = { [ME]: 'editor' },
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

// Given project <projectId> has this channel — returns its id
const givenChannel = (projectId: string, seed: ChannelSeed, by = OWNER) =>
  seedChannel(projectId, seed, by);

// Given project <projectId> has webhook auth method <name> — returns its id
const givenAuthMethod = (projectId: string, name: string, by = OWNER) =>
  addWebhookAuthMethodOnNode(projectId, name, by);

// Given I am signed in and on the channels page of <projectId>
async function onChannels(page: Page, projectId: string, email = ME) {
  await signInAs(page, email);
  await open(page, channelsPath(projectId));
}

// The open modal titled <title>, once it shows
async function dialog(page: Page, title: string) {
  await expect(modalTitle(page, title)).toBeVisible();
  return modal(page, title);
}

// When I click "New Channel" — returns the open form
async function openNewForm(page: Page) {
  await newChannelButton(page).click();
  return dialog(page, 'New Channel');
}

// When I click "Edit" on <name> — returns the open form
async function openEditForm(page: Page, name: string) {
  await editButton(channelRow(page, name)).click();
  return dialog(page, 'Edit Channel');
}

// When I fill the form's name and destination URL
async function fillChannel(form: Locator, name: string, url: string) {
  await field(form, 'Name').fill(name);
  await field(form, 'Destination URL').fill(url);
}

// Then the form has closed and I see <flash>
async function savedWith(page: Page, form: Locator, flash: string) {
  await expect(flashMessages.toast(page, flash)).toBeVisible();
  await expect(form).toBeHidden();
}

// The id of the channel called <name> in project <projectId>
const channelIdOf = (projectId: string, name: string) =>
  channelsOf(projectId).find(c => c.name === name)?.id;

// The audit events recorded for channel <id> by "<email>"
const eventsBy = (id: string, email: string) =>
  auditEventsOf(id)
    .filter(e => e.actor_id === user(email).id)
    .map(e => e.event);

// What my clipboard holds
const clipboard = (page: Page) =>
  page.evaluate(() => navigator.clipboard.readText());

const proxyUrl = (id: string) => new RegExp(`^https?://[^/]+/channels/${id}$`);

const NOT_AUTHORIZED = 'You are not authorized to perform this action.';

// @S01
// Scenario: Member sees the project's channels
//   Given project "Malawi HIV" has channel "lab-results" to "https://destination.example.com/data"
//   And "lab-results" has received 2 requests, the latest on 5 March 2025
//   And project "Malawi HIV" has channel "idle" with no requests
//   When I open the channels page
//   Then I see a row for "lab-results" with destination "https://destination.example.com/data", requests "2" and a last activity time
//   And I see a row for "idle" with requests "0" and last activity "Never"
//   And each row shows whether the channel is enabled
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, {
    name: 'lab-results',
    destination: 'https://destination.example.com/data',
    requests: [{ at: '2025-03-04 09:00:00' }, { at: '2025-03-05 09:00:00' }],
  });
  givenChannel(id, { name: 'idle', enabled: false });

  await onChannels(page, id);

  const lab = channelRow(page, 'lab-results');
  await expect(await channelCell(page, lab, 'Destination')).toContainText(
    'https://destination.example.com/data'
  );
  await expect(await channelCell(page, lab, 'Requests')).toHaveText('2');
  await expect(await channelCell(page, lab, 'Last Activity')).toHaveText(/\d/);

  const idle = channelRow(page, 'idle');
  await expect(await channelCell(page, idle, 'Requests')).toHaveText('0');
  await expect(await channelCell(page, idle, 'Last Activity')).toHaveText(
    'Never'
  );

  await expect(channelSwitch(lab)).toBeChecked();
  await expect(channelSwitch(idle)).not.toBeChecked();
});

// @S02
// Scenario: Totals show channels and requests for the project
//   Given project "Malawi HIV" has 2 channels with 3 requests between them
//   When I open the channels page
//   Then "Total channels" shows 2
//   And "Total requests" shows 3
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, {
    name: 'one',
    requests: [{ at: '2025-03-04 09:00:00' }, { at: '2025-03-05 09:00:00' }],
  });
  givenChannel(id, { name: 'two', requests: [{ at: '2025-03-06 09:00:00' }] });

  await onChannels(page, id);

  await expect(totalCard(page, 'Total Channels')).toHaveText(/(?<!\d)2(?!\d)/);
  await expect(totalCard(page, 'Total Requests')).toHaveText(/(?<!\d)3(?!\d)/);
});

// @S03
// Scenario: Channels from other projects are not listed
//   Given project "Malawi HIV" has channel "mine"
//   And another project has channel "theirs"
//   When I open the channels page on "Malawi HIV"
//   Then I see "mine"
//   And I do not see "theirs"
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const other = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  givenChannel(id, { name: 'mine' });
  givenChannel(other.id, { name: 'theirs' });

  await onChannels(page, id);

  await expect(channelRow(page, 'mine')).toBeVisible();
  await expect(page.getByText('theirs', { exact: true })).toHaveCount(0);
});

// @S04
// Scenario: Copy a channel's proxy URL
//   Given project "Malawi HIV" has channel "lab-results"
//   When I click the proxy URL under "lab-results"
//   Then my clipboard holds "<endpoint url>/channels/<lab-results id>"
//   And the tooltip says "Copied!"
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const lab = givenChannel(id, { name: 'lab-results' });
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);

  await onChannels(page, id);
  await proxyUrlCopy(channelRow(page, 'lab-results')).click();

  await expect.poll(() => clipboard(page)).toMatch(proxyUrl(lab));
  await expect(
    page.getByRole('tooltip').filter({ hasText: 'Copied!' })
  ).toBeVisible();
});

// @S05
// Scenario: Request count opens the channel logs for that channel
//   Given project "Malawi HIV" has channel "lab-results" with requests
//   When I click the request count for "lab-results"
//   Then I am on the channel logs with filters[channel_id] set to "lab-results"
// The filtered list is owned by history-channel-logs.
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const lab = givenChannel(id, {
    name: 'lab-results',
    requests: [{ at: '2025-03-05 09:00:00' }],
  });

  await onChannels(page, id);
  const row = channelRow(page, 'lab-results');
  await (await channelCell(page, row, 'Requests'))
    .getByRole('link', { name: '1', exact: true })
    .click();

  await expectAt(page, `/projects/${id}/history/channels`);
  expect(queryOf(page)['filters[channel_id]']).toBe(lab);
});

// @S06
// Scenario: View all opens the channel logs for every channel
//   When I click "View all" on the total requests card
//   Then I am on the channel logs for project "Malawi HIV" with no channel filter
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, { name: 'lab-results' });

  await onChannels(page, id);
  await totalCard(page, 'Total Requests')
    .getByRole('link', { name: 'View all' })
    .click();

  await expectAt(page, `/projects/${id}/history/channels`);
  expect(queryOf(page)['filters[channel_id]']).toBeUndefined();
});

// @S07
// Scenario: Requests stored without payloads still count
//   Given flow "flow-zero-persistence-channel-requests" has stored 2 requests on channel "lab-results" without their payloads
//   When I open the channels page
//   Then "lab-results" shows requests "2" and a last activity time
// The requests are seeded as already wiped; the wiping is owned by the flow.
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, {
    name: 'lab-results',
    requests: [
      { at: '2025-03-04 09:00:00', wiped: true },
      { at: '2025-03-05 09:00:00', wiped: true },
    ],
  });

  await onChannels(page, id);

  const row = channelRow(page, 'lab-results');
  await expect(await channelCell(page, row, 'Requests')).toHaveText('2');
  await expect(await channelCell(page, row, 'Last Activity')).toHaveText(/\d/);
});

// @S08
// Scenario: Editor creates a channel
//   Given I am an editor on project "Malawi HIV"
//   When I click "New channel"
//   And I enter name "new-channel" and destination URL "https://example.com/destination"
//   And I save
//   Then I am back on the channels list with "Channel created successfully."
//   And "new-channel" is listed and enabled
//   And an audit event "created" is recorded for the channel with me as actor
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();

  await onChannels(page, id);
  const form = await openNewForm(page);
  await fillChannel(form, 'new-channel', 'https://example.com/destination');
  await submit(form, 'Save');

  await savedWith(page, form, 'Channel created successfully.');
  await expectAt(page, channelsPath(id));
  await expect(channelSwitch(channelRow(page, 'new-channel'))).toBeChecked();
  const created = channelIdOf(id, 'new-channel')!;
  expect(eventsBy(created, ME)).toContain('created');
});

// @S09
// Scenario: Name and destination URL are required
//   Given I am on the new channel form
//   When I save with an empty name and an empty destination URL
//   Then the form stays open with "can't be blank"
//   And no channel is created
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();

  await onChannels(page, id);
  const form = await openNewForm(page);
  await submit(form, 'Save');

  await expect(form.getByText(/can't be blank/).first()).toBeVisible();
  await expect(modalTitle(page, 'New Channel')).toBeVisible();
  expect(channelsOf(id)).toEqual([]);
});

// @S10
// Scenario: Destination URL must be an http or https URL with a host
//   Given I am on the new channel form
//   When I save with destination URL "ftp://example.com"
//   Then the form stays open with "must be either a http or https URL"
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();

  await onChannels(page, id);
  const form = await openNewForm(page);
  await fillChannel(form, 'ftp-channel', 'ftp://example.com');
  await submit(form, 'Save');

  await expect(
    form.getByText('must be either a http or https URL')
  ).toBeVisible();
  expect(channelsOf(id)).toEqual([]);
});

// @S11
// Scenario: Channel names are unique within a project
//   Given project "Malawi HIV" has channel "existing"
//   When I create another channel named "existing"
//   Then the form stays open with "A channel with this name already exists in this project"
test('@S11', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenChannel(id, { name: 'existing' });

  await onChannels(page, id);
  const form = await openNewForm(page);
  await fillChannel(form, 'existing', 'https://example.com/destination');
  await submit(form, 'Save');

  await expect(
    form.getByText('A channel with this name already exists in this project')
  ).toBeVisible();
  expect(channelsOf(id).map(c => c.name)).toEqual(['existing']);
});

// @S12
// Scenario: Editor chooses the destination credential from the project's credentials
//   Given project "Malawi HIV" has credentials "My API Key" and "OAuth Token"
//   When I open the new channel form
//   Then "Destination credential" offers "None", "My API Key" and "OAuth Token"
//   When I create a channel with "My API Key"
//   Then the channel has one destination auth method for "My API Key"
//   And an audit event "auth_method_added" is recorded
//   When I create a channel with "None"
//   Then that channel has no destination auth method
test('@S12', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject(
    { [ME]: 'editor' },
    { credentials: ['My API Key', 'OAuth Token'] }
  );

  await onChannels(page, id);
  let form = await openNewForm(page);
  const offered = await credentialSelect(form)
    .getByRole('option')
    .allInnerTexts();
  // "None" first; the project's credentials come in no particular order
  expect(offered[0].trim()).toBe('None');
  expect(
    offered
      .slice(1)
      .map(o => o.trim())
      .sort()
  ).toEqual(['My API Key', 'OAuth Token']);

  await fillChannel(form, 'with-key', 'https://example.com/a');
  await credentialSelect(form).selectOption({ label: 'My API Key' });
  await submit(form, 'Save');
  await savedWith(page, form, 'Channel created successfully.');
  const withKey = channelIdOf(id, 'with-key')!;
  expect(channelAuthOf(withKey).destination).toEqual(['My API Key']);
  expect(eventsBy(withKey, ME)).toContain('auth_method_added');

  form = await openNewForm(page);
  await fillChannel(form, 'no-key', 'https://example.com/b');
  await credentialSelect(form).selectOption({ label: 'None' });
  await submit(form, 'Save');
  await savedWith(page, form, 'Channel created successfully.');
  expect(channelAuthOf(channelIdOf(id, 'no-key')!).destination).toEqual([]);
});

// @S13
// Scenario: Editor attaches client credentials
//   Given project "Malawi HIV" has webhook auth methods "API Key Auth" and "Basic Auth"
//   When I create a channel with "API Key Auth" checked
//   Then the channel has one client auth method for "API Key Auth"
//   And the flow "flow-channel-proxy-request" applies "API Key Auth" to requests on that channel
// The last Then is owned by flow-channel-proxy-request.
test('@S13', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  givenAuthMethod(id, 'API Key Auth');
  givenAuthMethod(id, 'Basic Auth');

  await onChannels(page, id);
  const form = await openNewForm(page);
  await fillChannel(form, 'guarded', 'https://example.com/destination');
  await form.getByRole('checkbox', { name: 'API Key Auth' }).check();
  await submit(form, 'Save');

  await savedWith(page, form, 'Channel created successfully.');
  expect(channelAuthOf(channelIdOf(id, 'guarded')!).clients).toEqual([
    'API Key Auth',
  ]);
});

// Given channel "edit-me" to "https://old.example.com" with client method
// "API Key Auth" (of "API Key Auth" and "Basic Auth") and destination
// credential "My API Key" (of "My API Key" and "Other Key")
function givenEditable() {
  const project = givenProject(
    { [ME]: 'editor' },
    { credentials: ['My API Key', 'Other Key'] }
  );
  givenAuthMethod(project.id, 'API Key Auth');
  givenAuthMethod(project.id, 'Basic Auth');
  const channel = givenChannel(project.id, {
    name: 'edit-me',
    destination: 'https://old.example.com',
    clients: ['API Key Auth'],
    credential: 'My API Key',
  });
  return { id: project.id, channel };
}

// @S14
// Scenario: Edit form opens with the channel's current settings and its proxy URL
//   Given channel "edit-me" to "https://old.example.com" with client method "API Key Auth" and destination credential "My API Key"
//   When I click "Edit" on "edit-me"
//   Then the form shows name "edit-me" and destination URL "https://old.example.com"
//   And "API Key Auth" is checked and "My API Key" is selected
//   And the form shows the channel's proxy URL, which copies on click
test('@S14', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id, channel } = givenEditable();
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);

  await onChannels(page, id);
  const form = await openEditForm(page, 'edit-me');

  await expect(field(form, 'Name')).toHaveValue('edit-me');
  await expect(field(form, 'Destination URL')).toHaveValue(
    'https://old.example.com'
  );
  await expect(
    form.getByRole('checkbox', { name: 'API Key Auth' })
  ).toBeChecked();
  await expect(
    form.getByRole('checkbox', { name: 'Basic Auth' })
  ).not.toBeChecked();
  await expect(credentialSelect(form)).toHaveValue(
    projectCredentialId(id, 'My API Key')
  );

  await proxyUrlCopy(form).click();
  await expect.poll(() => clipboard(page)).toMatch(proxyUrl(channel));
});

// @S15
// Scenario: Editor saves changes to a channel
//   Given I am editing channel "edit-me"
//   When I change the name to "updated-name" and save
//   Then I am back on the list with "Channel updated successfully."
//   And "updated-name" is listed
//   And an audit event "updated" is recorded
test('@S15', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id, channel } = givenEditable();

  await onChannels(page, id);
  const form = await openEditForm(page, 'edit-me');
  await field(form, 'Name').fill('updated-name');
  await submit(form, 'Save');

  await savedWith(page, form, 'Channel updated successfully.');
  await expect(channelRow(page, 'updated-name')).toBeVisible();
  await expect(page.getByText('edit-me', { exact: true })).toHaveCount(0);
  expect(eventsBy(channel, ME)).toContain('updated');
});

// @S16
// Scenario: Editor swaps or clears the destination credential
//   Given channel "c" uses destination credential "Key A"
//   When I select "Key B" and save
//   Then "c" has exactly one destination auth method, for "Key B"
//   And an audit event "auth_method_changed" is recorded
//   When I select "None" and save
//   Then "c" has no destination auth method
//   And an audit event "auth_method_removed" is recorded
test('@S16', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject(
    { [ME]: 'editor' },
    { credentials: ['Key A', 'Key B'] }
  );
  const c = givenChannel(id, { name: 'c', credential: 'Key A' });

  await onChannels(page, id);
  let form = await openEditForm(page, 'c');
  await credentialSelect(form).selectOption({ label: 'Key B' });
  await submit(form, 'Save');
  await savedWith(page, form, 'Channel updated successfully.');
  expect(channelAuthOf(c).destination).toEqual(['Key B']);
  expect(eventsBy(c, ME)).toContain('auth_method_changed');

  form = await openEditForm(page, 'c');
  await credentialSelect(form).selectOption({ label: 'None' });
  await submit(form, 'Save');
  await savedWith(page, form, 'Channel updated successfully.');
  expect(channelAuthOf(c).destination).toEqual([]);
  expect(eventsBy(c, ME)).toContain('auth_method_removed');
});

// @S17
// Scenario: Editor adds and removes client credentials in one save
//   Given channel "c" has client method "Old" and destination credential "Key A"
//   When I uncheck "Old", check "New" and save
//   Then "c" has only client method "New"
//   And "c" still uses destination credential "Key A"
//   And audit events "auth_method_removed" and "auth_method_added" are recorded
test('@S17', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject({ [ME]: 'editor' }, { credentials: ['Key A'] });
  givenAuthMethod(id, 'Old');
  givenAuthMethod(id, 'New');
  const c = givenChannel(id, {
    name: 'c',
    clients: ['Old'],
    credential: 'Key A',
  });

  await onChannels(page, id);
  const form = await openEditForm(page, 'c');
  await form.getByRole('checkbox', { name: 'Old', exact: true }).uncheck();
  await form.getByRole('checkbox', { name: 'New', exact: true }).check();
  await submit(form, 'Save');

  await savedWith(page, form, 'Channel updated successfully.');
  expect(channelAuthOf(c)).toEqual({
    clients: ['New'],
    destination: ['Key A'],
  });
  const events = eventsBy(c, ME);
  expect(events).toContain('auth_method_removed');
  expect(events).toContain('auth_method_added');
});

// @S18
// Scenario: Another project's credential cannot be attached as the destination credential
//   Given another project has credential "victim"
//   When I submit a channel whose destination credential id is "victim", bypassing the dropdown
//   Then the form stays open
//   And no channel is created, or the existing destination credential is unchanged
test('@S18', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const other = givenProject(
    { [OWNER]: 'owner' },
    { name: 'Kenya TB', credentials: ['victim'] }
  );
  const lv = watchLiveView(page);

  await onChannels(page, id);
  await openNewForm(page);
  await sendSave(page, lv, {
    name: 'borrowed',
    destinationUrl: 'https://example.com/destination',
    destinationCredentialId: projectCredentialId(other.id, 'victim'),
  });

  await expect(modalTitle(page, 'New Channel')).toBeVisible();
  expect(channelsOf(id)).toEqual([]);
  expect(lv.crashes()).toBe(0);
});

// @S19
// Scenario: Another project's webhook auth method cannot be attached as a client credential
//   Given another project has webhook auth method "victim"
//   When I submit a channel with "victim" checked, bypassing the checkbox list
//   Then "victim" is attached to no channel
//   And the channel's existing client methods are unchanged
test('@S19', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const other = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const victim = givenAuthMethod(other.id, 'victim');
  const mine = givenAuthMethod(id, 'Mine');
  const c = givenChannel(id, { name: 'c', clients: ['Mine'] });
  const lv = watchLiveView(page);

  await onChannels(page, id);
  await openEditForm(page, 'c');
  await sendSave(
    page,
    lv,
    {
      name: 'c',
      destinationUrl: 'https://destination.example.com/data',
      clientAuthMethodIds: [mine, victim],
    },
    c
  );

  expect(
    sql(
      `select id from channel_auth_methods where webhook_auth_method_id = '${victim}'`
    )
  ).toEqual([]);
  expect(channelAuthOf(c).clients).toEqual(['Mine']);
  expect(lv.crashes()).toBe(0);
});

// @S20
// Scenario: Another project's channel cannot be opened for editing
//   Given a channel belongs to another project
//   When I open /projects/<my project>/channels/<that channel id>/edit, directly or by a client-side patch
//   Then I am sent to my project's channels list with "Channel not found"
// Only the direct visit is driven: a client-side patch lands on the same
// server check.
test('@S20', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const other = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const theirs = givenChannel(other.id, { name: 'theirs' });

  await signInAs(page, ME);
  await page.goto(`${channelsPath(id)}/${theirs}/edit`);

  await expectAt(page, channelsPath(id));
  await expect(flashMessages.toast(page, 'Channel not found')).toBeVisible();
  await expect(page.getByText('theirs', { exact: true })).toHaveCount(0);
});

// @S21
// Scenario: Editor switches a channel off and on
//   Given channel "toggle-me" is enabled
//   When I switch its toggle off
//   Then I see "Channel updated"
//   And "toggle-me" is disabled and its name is greyed
//   And an audit event "updated" is recorded with me as actor
//   And the flow "flow-channel-proxy-request" no longer forwards requests on "toggle-me"
//   When I switch it back on
//   Then "toggle-me" is enabled
// Forwarding is owned by flow-channel-proxy-request.
test('@S21', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const toggled = givenChannel(id, { name: 'toggle-me' });
  givenChannel(id, { name: 'stays-on' });
  const enabledOf = () => channelsOf(id).find(c => c.id === toggled)?.enabled;

  await onChannels(page, id);
  const row = channelRow(page, 'toggle-me');
  const nameOf = (name: string) =>
    channelRow(page, name).getByText(name, { exact: true });
  const onLook = await lookOf(nameOf('toggle-me'));

  await channelSwitch(row).click();
  await expect(flashMessages.toast(page, 'Channel updated')).toBeVisible();
  await expect(channelSwitch(row)).not.toBeChecked();
  await expect.poll(enabledOf).toBe(false);
  await expect.poll(() => lookOf(nameOf('toggle-me'))).not.toBe(onLook);
  expect(await lookOf(nameOf('stays-on'))).toBe(onLook);
  expect(eventsBy(toggled, ME)).toContain('updated');

  await channelSwitch(row).click();
  await expect(channelSwitch(row)).toBeChecked();
  await expect.poll(enabledOf).toBe(true);
});

// @S22
// Scenario: Editor deletes a channel after confirming
//   Given channel "delete-me" exists
//   When I click "Delete" on "delete-me"
//   Then the browser asks 'Delete "delete-me"? This cannot be undone.'
//   When I confirm
//   Then I see "Channel deleted."
//   And "delete-me" is no longer listed
//   And an audit event "deleted" is recorded with me as actor
test('@S22', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const doomed = givenChannel(id, { name: 'delete-me' });

  await onChannels(page, id);
  const asked = await deleteAndConfirm(page, channelRow(page, 'delete-me'));

  expect(asked).toContain('Delete "delete-me"? This cannot be undone.');
  await expect(flashMessages.toast(page, 'Channel deleted.')).toBeVisible();
  await expect(page.getByText('delete-me', { exact: true })).toHaveCount(0);
  expect(channelsOf(id)).toEqual([]);
  expect(eventsBy(doomed, ME)).toContain('deleted');
});

// @S23
// Scenario: Viewer sees channels read-only
//   Given I am a viewer on project "Malawi HIV" with channel "viewer-channel"
//   When I open the channels page
//   Then "New channel" is disabled with tooltip "You are not authorized to perform this action."
//   And there is no "Edit" or "Delete" on "viewer-channel"
//   And the enabled column shows "Enabled" or "Disabled" as text, not a toggle
test('@S23', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject({ [ME]: 'viewer' });
  givenChannel(id, { name: 'viewer-channel' });
  givenChannel(id, { name: 'off-channel', enabled: false });

  await onChannels(page, id);

  await expect(newChannelButton(page)).toBeDisabled();
  await expectTooltip(page, newChannelTipTarget(page), NOT_AUTHORIZED);
  const row = channelRow(page, 'viewer-channel');
  await expect(editButton(row)).toHaveCount(0);
  await expect(deleteButton(row)).toHaveCount(0);
  await expect(channelSwitch(row)).toHaveCount(0);
  await expect(await channelCell(page, row, 'Enabled')).toHaveText('Enabled');
  const off = channelRow(page, 'off-channel');
  await expect(await channelCell(page, off, 'Enabled')).toHaveText('Disabled');
});

// @S24
// Scenario: Viewer opening the new or edit URL is sent back to the list
//   Given I am a viewer on project "Malawi HIV"
//   When I open /projects/<id>/channels/new
//   Then I am on the channels list with "You are not authorized to create channels."
//   When I open /projects/<id>/channels/<channel id>/edit
//   Then I am on the channels list with "You are not authorized to edit channels."
test('@S24', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject({ [ME]: 'viewer' });
  const c = givenChannel(id, { name: 'c' });

  await signInAs(page, ME);
  await page.goto(`${channelsPath(id)}/new`);
  await expectAt(page, channelsPath(id));
  await expect(
    flashMessages.toast(page, 'You are not authorized to create channels.')
  ).toBeVisible();
  await expect(modalTitle(page, 'New Channel')).toHaveCount(0);

  await page.goto(`${channelsPath(id)}/${c}/edit`);
  await expectAt(page, channelsPath(id));
  await expect(
    flashMessages.toast(page, 'You are not authorized to edit channels.')
  ).toBeVisible();
  await expect(modalTitle(page, 'Edit Channel')).toHaveCount(0);
});

// @S25
// Scenario: A crafted toggle or delete from a viewer is refused
//   Given I am a viewer on project "Malawi HIV" with channel "c"
//   When my browser sends "toggle_channel_state" or "delete_channel" for "c"
//   Then I see "You are not authorized to perform this action."
//   And "c" is unchanged
// A crafted request's refusal is checked by its effect, not its message.
test('@S25', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject({ [ME]: 'viewer' });
  const c = givenChannel(id, { name: 'c' });
  const lv = watchLiveView(page);

  await onChannels(page, id);
  await sendToggle(page, lv, c, false);
  await sendDelete(page, lv, c);

  expect(channelsOf(id)).toEqual([
    expect.objectContaining({ id: c, enabled: true }),
  ]);
  expect(lv.crashes()).toBe(0);
});

// @S26
// Scenario: A crafted toggle or delete for another project's channel is refused
//   Given I am an editor on project "Malawi HIV"
//   And channel "theirs" belongs to another project
//   When my browser sends "toggle_channel_state" or "delete_channel" for "theirs"
//   Then I see "Channel not found"
//   And "theirs" is unchanged
// A crafted request's refusal is checked by its effect, not its message.
test('@S26', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  const other = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const theirs = givenChannel(other.id, { name: 'theirs' });
  const lv = watchLiveView(page);

  await onChannels(page, id);
  await sendToggle(page, lv, theirs, false);
  await sendDelete(page, lv, theirs);

  expect(channelsOf(other.id)).toEqual([
    expect.objectContaining({ id: theirs, enabled: true }),
  ]);
  expect(lv.crashes()).toBe(0);
});

// @S27
// Scenario: Destination and client "Add new" links open the right settings tab
//   Given I am on the new channel form
//   Then the destination credential "Add new" link opens project settings at #credentials in a new tab
//   And the client credentials "Add new" link opens project settings at #webhook_security in a new tab
// Tab selection is owned by shared-project-settings-tab-chrome. The
// destination credential's link comes first in both versions.
test('@S27', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();

  await onChannels(page, id);
  const form = await openNewForm(page);
  const links = form.getByRole('link', { name: /^Add New$/i });
  await expect(links).toHaveCount(2);

  for (const [n, hash] of [
    [0, '#credentials'],
    [1, '#webhook_security'],
  ] as const) {
    const [tab] = await Promise.all([
      page.context().waitForEvent('page'),
      links.nth(n).click(),
    ]);
    await tab.waitForLoadState();
    const url = new URL(tab.url());
    expect(url.pathname).toBe(`/projects/${id}/settings`);
    expect(url.hash).toBe(hash);
    await tab.close();
  }
  await expect(modalTitle(page, 'New Channel')).toBeVisible();
});

// @S28 @variant:experimental-features
// Scenario: Channels appear in the project menu for people with experimental features on
//   Given I have experimental features on
//   When I open any page in project "Malawi HIV"
//   Then the side menu shows "Channels", marked active on this page
// The preference is data, so the variant is seeded rather than skipped.
test('@S28', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = givenProject();
  cleanups.push(keepAccount(ME));
  setPreferences(ME, { experimental_features: true });

  await onChannels(page, id);

  const menu = page
    .getByRole('navigation')
    .filter({ has: page.getByRole('link', { name: 'Sandboxes' }) });
  const link = menu.getByRole('link', { name: 'Channels', exact: true });
  await expect(link).toHaveAttribute('href', channelsPath(id));
  await expect(link).toHaveAttribute('aria-current', 'page');
});

// Inherited shared annotations, run on the channels page
const PENDING = { tag: '@pending' };
const PASSING = { tag: ['@passing-old', '@passing-new'] };

// Given project "Malawi HIV" (or <name>) with these members and a channel
function givenChannelsPage(
  members: Record<string, Role> = { [ME]: 'owner' },
  name = 'Malawi HIV'
) {
  const project = givenProject(members, { name });
  givenChannel(project.id, { name: 'ch-1' }, project.by);
  return { ...project, path: channelsPath(project.id) };
}

const channelsHeading = (page: Page) =>
  page.getByRole('heading', { name: /^Channels\s*\(\d+\)$/ });

test.describe('shared-authenticated-session', () => {
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  test(
    'shared-authenticated-session@S01 on channels-index',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S01(page, givenChannelsPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on channels-index',
    PASSING,
    async ({ page, browser }) => {
      await authenticatedSession.S02(
        page,
        browser,
        givenChannelsPage().path,
        ME
      );
    }
  );

  test(
    'shared-authenticated-session@S03 on channels-index',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S03(page, givenChannelsPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on channels-index',
    PASSING,
    async ({ page, browser }) => {
      const h = givenChannelsPage();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.id}/history`,
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
      `shared-authenticated-session@${id} on channels-index`,
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
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  test(
    'shared-project-scope@S01 on channels-index',
    PASSING,
    async ({ page }) => {
      await projectScope.S01(page, givenChannelsPage().path);
    }
  );

  test(
    'shared-project-scope@S02 on channels-index',
    PASSING,
    async ({ page }) => {
      await projectScope.S02(
        page,
        givenChannelsPage().path,
        ME,
        channelsHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S03 on channels-index',
    PASSING,
    async ({ page }) => {
      await projectScope.S03(
        page,
        givenChannelsPage({ [OWNER]: 'owner' }).path,
        ME
      );
    }
  );

  test(
    'shared-project-scope@S04 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [OWNER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.id}'`
      );
      await projectScope.S04(page, h.path, OWNER);
    }
  );

  test(
    'shared-project-scope@S05 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage();
      exec(`update projects set requires_mfa = true where id = '${h.id}'`);
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on channels-index',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenChannelsPage({ [OWNER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, channelsHeading(page));
    }
  );

  test(
    'shared-project-scope@S07 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'editor', [OWNER]: 'owner' });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.id, ME, OWNER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'admin', [OWNER]: 'owner' });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.id, ME, 'viewer'),
        channelsHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on channels-index',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenChannelsPage({ [OWNER]: 'owner' });
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
    'shared-project-scope@S10 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'editor', [OWNER]: 'owner' });
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
  test('shared-usage-limits-banner@S01 on channels-index', PENDING, () => {
    test.skip(true, 'variant usage-limited is not configured on this instance');
  });

  test(
    'shared-usage-limits-banner@S02 on channels-index',
    PASSING,
    async ({ page }) => {
      await usageLimitsBanner.S02(
        page,
        givenChannelsPage().path,
        ME,
        channelsHeading(page)
      );
    }
  );
});

// The picker scenarios seed their own "Malawi HIV", so this page's project
// has another name.
test.describe('shared-project-header', () => {
  // These change the account (disable, MFA, preferences); put it back
  test.beforeEach(() => {
    cleanups.push(keepAccount(ME));
  });

  const HOST = 'Channels host';

  test(
    'shared-project-header@S01 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S01(page, h.path, ME, HOST, [{ name: 'Channels' }]);
    }
  );

  test(
    'shared-project-header@S02 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on channels-index',
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
        path: channelsPath(w.id('dev')),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on channels-index`,
      PASSING,
      async ({ page }) => {
        const h = givenChannelsPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on channels-index',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, whatever page hosts the header
  test(
    'shared-project-header@S09 on channels-index',
    PASSING,
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // This page is the channels page, and the picker lands on the other
  // project's
  test(
    'shared-project-header@S10 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S10(page, h.path, ME, '/channels');
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on channels-index`,
      PASSING,
      async ({ page }) => {
        const h = givenChannelsPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test('shared-project-header@S14 on channels-index', PENDING, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

  // Channels is in the menu only with experimental features on (S28), so
  // none of the four areas S15 checks is marked current here
  test(
    'shared-project-header@S15 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'viewer' }, HOST);
      await projectHeader.S15(page, h.path, ME, h.id, 'Channels');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  test(
    'shared-project-header@S17 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage({ [ME]: 'viewer', [THIRD]: 'viewer' }, HOST);
      await projectHeader.S17(page, h.path);
    }
  );
});

// Inherited from shared-local-datetime: the "Last Activity" column.
test.describe('shared-local-datetime', () => {
  // Given "ch-1"'s latest request started at <utc>, and today is <today>
  async function lastActivity(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    const { id } = givenProject();
    givenChannel(id, { name: 'ch-1', requests: [{ at: utc }] });
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, channelsPath(id));
    return channelCell(page, channelRow(page, 'ch-1'), 'Last Activity');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on channels-index',
      PASSING,
      async ({ page }) => {
        await localDatetime.S01(
          page,
          await lastActivity(page, localDatetime.given.S01)
        );
      }
    );
  });

  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on channels-index`,
      PASSING,
      async ({ page }) => {
        await localDatetime[id](
          page,
          await lastActivity(page, localDatetime.given[id])
        );
      }
    );

  // shared-local-datetime S03 and S07 are not run on this page:
  // not_reachable_here does not exclude them, but the Last Activity column
  // uses the default format (never relative_detailed), and a channel with no
  // requests shows "Never" instead of the placeholder.
});

// This page puts the info flash "Channel deleted." and the error flash "You
// are not authorized to create channels." (a viewer going to /new) itself.
test.describe('shared-flash-messages', () => {
  const INFO = 'Channel deleted.';
  const DENIED = 'You are not authorized to create channels.';

  // Given I am on the channels page; I delete "ch-1"
  async function givenDeletable(page: Page) {
    const h = givenChannelsPage();
    await onChannels(page, h.id);
    return async () => {
      await deleteAndConfirm(page, channelRow(page, 'ch-1'));
    };
  }

  // Given I am a viewer on the channels page; I go to /new
  async function givenViewer(page: Page) {
    const h = givenChannelsPage({ [ME]: 'viewer' });
    await onChannels(page, h.id);
    return async () => {
      await page.goto(`${h.path}/new`);
    };
  }

  test(
    'shared-flash-messages@S01 on channels-index',
    PASSING,
    async ({ page }) => {
      await flashMessages.S01(page, INFO, await givenDeletable(page));
    }
  );

  test(
    'shared-flash-messages@S02 on channels-index',
    PASSING,
    async ({ page }) => {
      await flashMessages.S02(page, DENIED, await givenViewer(page));
    }
  );

  test(
    'shared-flash-messages@S03 on channels-index',
    PASSING,
    async ({ page }) => {
      await flashMessages.S03(page, INFO, await givenDeletable(page));
    }
  );

  test(
    'shared-flash-messages@S04 on channels-index',
    PASSING,
    async ({ page }) => {
      await flashMessages.S04(
        page,
        INFO,
        await givenDeletable(page),
        async () => {
          // Opening the new channel form makes the page render again
          await openNewForm(page);
        }
      );
    }
  );

  test(
    'shared-flash-messages@S06 on channels-index',
    PASSING,
    async ({ page }) => {
      const h = givenChannelsPage();
      const notMine = givenChannelsPage({ [OWNER]: 'owner' }, 'Kenya TB');
      await onChannels(page, h.id);

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

  // shared-flash-messages S05, S07 and S08 are not run on this page: no
  // action here puts an info flash and redirects (save, switch and delete
  // stay on the page), S07 is on admin pages (settings layout) and S08 on the
  // sign-in and account forms.
});
