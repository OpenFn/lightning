// Scenarios from annotations/views/project-settings-github-sync.md. The
// shared session, scope, banner, header, flash and tab chrome scenarios run
// once for every settings tab, in project-settings-setup.spec.ts.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names, and a GitHub account when it says so. owner@openfn.org owns the
// projects I don't. GitHub is a stand-in on the Lightning node and the
// instance's GitHub app is set up for the test, so every test here is
// @serial.
import { expect, test, type Page } from '@playwright/test';

import { followToGithub, githubLink } from './pages/profile';
import {
  acceptBox,
  chooseIn,
  chooseRepo,
  chosenIn,
  configPathBox,
  connectionChecked,
  githubDialog,
  offeredIn,
  openSettings,
  panel,
  refreshButton,
  removeIntegration,
  sendGithubRequest,
  shownIn,
  type GithubForm,
  type GithubRequest,
} from './pages/project-settings';
import * as flashMessages from './shared/flash-messages';
import {
  auditEventsOf,
  connectRepoOnNode,
  exec,
  expectTooltip,
  githubTokenFor,
  repoConnectionOf,
  seedWorkspace,
  signInAs,
  standInGithub,
  submit,
  user,
  watchLiveView,
  withLimiterRefusing,
  type GithubToken,
  type GithubWorld,
  type StandInGithub,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PROJECT = 'Malawi HIV';

const PASSING_OLD = { tag: ['@passing-old', '@serial'] };
const PASSING_BOTH = { tag: ['@passing-old', '@passing-new', '@serial'] };

const AMARA = 'User: amara';
const REPO = 'amara/hiv-sync';
// GitHub as most tests find it: my installation "User: amara" (1234) can
// see amara/hiv-sync, whose branches are main and dev
const WORLD: GithubWorld = {
  installations: [
    { id: 1234, login: 'amara', repos: { [REPO]: ['main', 'dev'] } },
  ],
};
const CONNECTED = { repo: REPO, branch: 'main', installation: '1234' };

const CONNECT = /Connect Branch/i;
const SYNC = /Initiate Sync/i;
const RECONNECT = /Click here to reconnect/i;
// The connect button's whole name, for submit()
const CONNECT_NAME = 'Connect Branch & Initiate First Sync';

let github: StandInGithub;
let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given GitHub holds <world>
function givenGithub(world: GithubWorld = WORLD) {
  github = standInGithub(world);
  cleanups.push(github.restore);
}

// Given I have a connected GitHub account (a token like <kind>)
function givenMyGithub(kind: GithubToken = 'fresh') {
  githubTokenFor(user(ME).id, kind);
  cleanups.push(() =>
    exec(
      `update users set github_oauth_token = null where id = '${user(ME).id}'`
    )
  );
}

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given I am a <role> on project "Malawi HIV" (owner@openfn.org owns it
// unless I do)
function givenProject(role: Role, extra: Partial<WorkspaceSeed> = {}) {
  const members: Record<string, Role> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const w = seedWorkspace(
    { name: PROJECT, members, ...extra },
    role === 'owner' ? ME : OTHER
  );
  cleanups.push(w.remove);
  return w;
}

// Given I am a <role> on project "Malawi HIV", which is connected
function givenConnected(role: Role, extra: Partial<WorkspaceSeed> = {}) {
  const id = givenProject(role, extra).id(PROJECT);
  connectRepoOnNode(id, CONNECTED);
  return id;
}

// When I open the project's "Sync to GitHub" tab, watching the LiveView
// from sign-in on (a watch started later never sees the socket)
async function onGithub(page: Page, id: string) {
  await signInAs(page, ME);
  const lv = watchLiveView(page);
  await openSettings(page, id, 'Sync to GitHub');
  return Object.assign(panel(page, 'Sync to GitHub'), { lv });
}

const connectButton = (page: Page) =>
  panel(page, 'Sync to GitHub').getByRole('button', { name: CONNECT });
const syncButton = (page: Page) =>
  panel(page, 'Sync to GitHub').getByRole('button', { name: SYNC });
const reconnectButton = (page: Page) =>
  panel(page, 'Sync to GitHub').getByRole('button', { name: RECONNECT });

const deployFile = (id: string) => `.github/workflows/openfn-${id}-deploy.yml`;
const PULL_FILE = '.github/workflows/openfn-pull.yml';

// The requests that started the sync workflow in GitHub
const dispatches = () =>
  github
    .requests()
    .filter(
      r =>
        r.method === 'post' &&
        r.url.endsWith('/actions/workflows/openfn-pull.yml/dispatches')
    );

// The requests that wrote anything to a repo
const writes = () =>
  github
    .requests()
    .filter(r => r.method !== 'get' && r.url.includes('/repos/'));

// When I choose <direction> and tick the confirmation
async function confirmDirection(
  page: Page,
  direction: 'Export' | 'Import',
  configPath?: string
) {
  const tab = panel(page, 'Sync to GitHub');
  await tab
    .getByRole('radio', {
      name: new RegExp(`${direction} from|${direction} to`),
    })
    .check();
  if (configPath !== undefined) await configPathBox(tab).fill(configPath);
  await acceptBox(tab).check();
}

// @S01
// Scenario: Admin connects a branch and exports the project to GitHub
//   Given I am an admin on project "Malawi HIV" with a connected GitHub account
//   And my GitHub installation "User: amara" can see repository "amara/hiv-sync" with branch "main"
//   When I select installation "User: amara", repository "amara/hiv-sync" and branch "main"
//   And I leave "OpenFn --> GitHub: Export to GitHub (default, non-destructive)" selected
//   And I tick the confirmation checkbox
//   And I click "Connect Branch & Initiate First Sync"
//   Then I see "Connection made successfully"
//   And I see "Repository: amara/hiv-sync" and branch "main"
//   And an audit event "repo_connection_created" is recorded for the project
//   And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
test('@S01', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);

  await chooseRepo(page, AMARA, REPO, 'main');
  await expect(
    tab.getByRole('radio', { name: /Export to GitHub/ })
  ).toBeChecked();
  await acceptBox(tab).check();
  await connectButton(page).click();

  await expect(
    flashMessages.toast(page, 'Connection made successfully')
  ).toBeVisible();
  await expect(tab.getByRole('link', { name: REPO })).toBeVisible();
  await expect.poll(() => shownIn(tab)).toContain('main');
  expect(repoConnectionOf(id)).toMatchObject({ repo: REPO, branch: 'main' });
  expect(auditEventsOf(id).map(e => e.event)).toContain(
    'repo_connection_created'
  );
  expect(dispatches()).toHaveLength(1);
});

// @S02
// Scenario: Admin connects a branch to import an existing project from GitHub
//   Given I am an admin on project "Malawi HIV" with a connected GitHub account
//   When I select an installation, repository "amara/hiv-sync" and branch "main"
//   And I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
//   And I enter "./config.json" in "Path to config (required)"
//   And I tick the confirmation checkbox
//   And I click "Connect Branch & Initiate First Sync"
//   Then I see "Connection made successfully"
//   And no sync to GitHub is started
test('@S02', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  await onGithub(page, id);

  await chooseRepo(page, AMARA, REPO, 'main');
  await confirmDirection(page, 'Import', './config.json');
  await connectButton(page).click();

  await expect(
    flashMessages.toast(page, 'Connection made successfully')
  ).toBeVisible();
  expect(repoConnectionOf(id)).toMatchObject({ repo: REPO, branch: 'main' });
  expect(dispatches()).toHaveLength(0);
});

// @S03
// Scenario: Importing from GitHub needs a config path
//   Given I am an admin filling in the connect form on project "Malawi HIV"
//   When I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
//   And I leave "Path to config (required)" empty
//   Then "Connect Branch & Initiate First Sync" stays disabled
//   And the "Advanced: use new YAML config format" option is not shown
// (The Value is that no import is set up without a file, so this checks that
// nothing is connected, through the form and past it. Whether the YAML
// option shows is an open decision, not checked.)
test('@S03', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const { lv } = await onGithub(page, id);

  await chooseRepo(page, AMARA, REPO, 'main');
  await confirmDirection(page, 'Import', '');
  await submit(page, CONNECT_NAME);
  await sendGithubRequest(page, lv, 'save', {
    installation: '1234',
    repo: REPO,
    branch: 'main',
    direction: 'import',
  });

  expect(repoConnectionOf(id)).toBeUndefined();
  expect(writes()).toHaveLength(0);
  expect(lv.crashes()).toBe(0);
});

// @S04
// Scenario Outline: The connect confirmation spells out what will be overwritten
//   Given I am an admin filling in the connect form on project "Malawi HIV"
//   And I have selected repository "amara/hiv-sync" and branch "main"
//   When I choose "<direction>"
//   Then I see "I understand that" followed by the files ".github/workflows/openfn-pull.yml", ".github/workflows/openfn-<project_id>-deploy.yml"
//   And I <see_or_not> "my current OpenFn project will be destroyed"
//   And "Connect Branch & Initiate First Sync" stays disabled until I tick the box
//
//   Examples:
//     | direction                                                            | see_or_not |
//     | OpenFn --> GitHub: Export to GitHub (default, non-destructive)       | do not see |
//     | GitHub --> OpenFn: Import from GitHub (overwrite this project)       | see        |
// (Disabled until ticked is checked by its effect: an unticked submit
// connects nothing.)
for (const [direction, destroyed] of [
  ['Export', false],
  ['Import', true],
] as const) {
  test(`@S04 ${direction}`, PASSING_BOTH, async ({ page }) => {
    givenGithub();
    givenMyGithub();
    const id = givenProject('admin').id(PROJECT);
    const tab = await onGithub(page, id);

    await chooseRepo(page, AMARA, REPO, 'main');
    await tab
      .getByRole('radio', { name: new RegExp(`${direction} (to|from) GitHub`) })
      .check();
    if (direction === 'Import') await configPathBox(tab).fill('./config.json');

    const warning = tab.getByText(/I understand that/);
    await expect(warning).toContainText(PULL_FILE);
    await expect(warning).toContainText(deployFile(id));
    if (destroyed) await expect(warning).toContainText(/will be destroyed/);
    else await expect(warning).not.toContainText(/destroyed/);

    await submit(page, CONNECT_NAME);
    expect(repoConnectionOf(id)).toBeUndefined();
  });
}

// @S05
// Scenario: Connect stays disabled until installation, repository and branch are chosen
//   Given I am an admin filling in the connect form on project "Malawi HIV"
//   When I have not chosen a branch
//   Then "Connect Branch & Initiate First Sync" is disabled
//   And if the form is submitted anyway I see "This field can't be blank"
// (The Value is that nothing incomplete reaches GitHub: checked through the
// form and past it, by what GitHub and the database got.)
test('@S05', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const { lv } = await onGithub(page, id);

  await expect
    .poll(() => offeredIn(page, 'GitHub Installation'))
    .toContain(AMARA);
  await chooseIn(page, 'GitHub Installation', AMARA);
  await expect.poll(() => offeredIn(page, 'Repository')).toContain(REPO);
  await chooseIn(page, 'Repository', REPO);
  await submit(page, CONNECT_NAME);
  await sendGithubRequest(page, lv, 'save', {
    installation: '1234',
    repo: REPO,
  });

  expect(repoConnectionOf(id)).toBeUndefined();
  expect(writes()).toHaveLength(0);
  expect(lv.crashes()).toBe(0);
});

// @S06
// Scenario: Repository and branch lists follow the choice above them
//   Given I am an admin with access to installation "User: amara" holding repository "amara/hiv-sync"
//   When I select installation "User: amara"
//   Then "Repository" lists "amara/hiv-sync"
//   When I select repository "amara/hiv-sync"
//   Then "Branch" lists that repository's branches
//   When I clear the installation
//   Then no repository and no branch is selected
test('@S06', PASSING_BOTH, async ({ page }) => {
  givenGithub({
    installations: [
      ...WORLD.installations!,
      {
        id: 5678,
        login: 'openfn',
        type: 'Organization',
        repos: { 'openfn/other': ['trunk'] },
      },
    ],
  });
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  await onGithub(page, id);

  await expect
    .poll(() => offeredIn(page, 'GitHub Installation'))
    .toContain(AMARA);
  await chooseIn(page, 'GitHub Installation', AMARA);
  await expect.poll(() => offeredIn(page, 'Repository')).toEqual([REPO]);
  await chooseIn(page, 'Repository', REPO);
  await expect.poll(() => offeredIn(page, 'Branch')).toEqual(['dev', 'main']);
  await chooseIn(page, 'Branch', 'main');

  await chooseIn(page, 'GitHub Installation', null);
  await expect.poll(() => chosenIn(page, 'Repository')).toBe('');
  await expect.poll(() => chosenIn(page, 'Branch')).toBe('');
});

// @S07
// Scenario: Refreshing installations picks up a newly installed GitHub App
//   Given I am an admin on the connect form and my installations failed to load
//   When the GitHub App is now installed on my account
//   And I click the refresh button next to "GitHub Installation"
//   Then "GitHub Installation" lists the new installation
test('@S07', PASSING_BOTH, async ({ page }) => {
  givenGithub({
    answers: [
      {
        method: 'get',
        path: '/user/installations',
        status: 500,
        body: { message: 'Server Error' },
      },
    ],
  });
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);
  await expect
    .poll(() => shownIn(tab))
    .toContain('Unable to load GitHub installations');

  github.holds(WORLD);
  await refreshButton(page, 'GitHub Installation').click();

  await expect
    .poll(() => offeredIn(page, 'GitHub Installation'))
    .toEqual([AMARA]);
});

// @S08
// Scenario: Refreshing branches picks up a branch created after the page loaded
//   Given I am an admin with repository "amara/hiv-sync" selected, listing branch "main"
//   When branch "openfn" is created in GitHub
//   And I click the refresh button next to "Branch"
//   Then "Branch" lists "main" and "openfn"
//   And no branch is selected
test('@S08', PASSING_BOTH, async ({ page }) => {
  givenGithub({
    installations: [{ id: 1234, login: 'amara', repos: { [REPO]: ['main'] } }],
  });
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  await onGithub(page, id);
  await chooseRepo(page, AMARA, REPO, 'main');

  github.holds({
    installations: [
      { id: 1234, login: 'amara', repos: { [REPO]: ['main', 'openfn'] } },
    ],
  });
  await refreshButton(page, 'Branch').click();

  await expect
    .poll(() => offeredIn(page, 'Branch'))
    .toEqual(['main', 'openfn']);
  await expect.poll(() => chosenIn(page, 'Branch')).toBe('');
});

// @S09
// Scenario: Branches are never listed for an installation the user can't access
//   Given I am an admin whose GitHub account can access installation "1234" only
//   When the form is submitted with installation "9999" and a repository in it
//   Then "Branch" lists no branches
//   And clicking the refresh button next to "Branch" still lists no branches
// (The Value is that GitHub is never asked for that repository's branches.)
test('@S09', PASSING_BOTH, async ({ page }) => {
  givenGithub({
    installations: [
      ...WORLD.installations!,
      {
        id: 9999,
        login: 'tenant',
        mine: false,
        repos: { 'tenant/private': ['secret-plans'] },
      },
    ],
  });
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const { lv } = await onGithub(page, id);
  await expect
    .poll(() => offeredIn(page, 'GitHub Installation'))
    .toEqual([AMARA]);

  const theirs: GithubForm = { installation: '9999', repo: 'tenant/private' };
  await sendGithubRequest(page, lv, 'validate', theirs);
  await expect.poll(() => offeredIn(page, 'Branch')).toEqual([]);
  const sent = lv.events();
  await refreshButton(page, 'Branch').click();
  await lv.answered(sent + 1);

  await expect.poll(() => offeredIn(page, 'Branch')).toEqual([]);
  expect(
    github.requests().filter(r => r.url.includes('/repos/tenant/private'))
  ).toHaveLength(0);
  expect(lv.crashes()).toBe(0);
});

// @S10 @variant:sandbox
// Scenario: A sandbox can't claim a branch already linked in its project family
//   Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main"
//   And I am an admin of its sandbox "dev"
//   When I select "amara/hiv-sync" and branch "main" on the sandbox's connect form
//   Then I see "this branch is already linked to another project in the same project family; use a different branch"
//   And "Connect Branch & Initiate First Sync" is disabled
//   When I select branch "dev"
//   Then that message is gone
// (Disabled is checked by its effect: submitting connects nothing.)
test('@S10', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const w = givenProject('admin', {
    sandboxes: [{ name: 'dev', members: { [ME]: 'admin' } }],
  });
  connectRepoOnNode(w.id(PROJECT), CONNECTED);
  const sandbox = w.id('dev');
  const tab = await onGithub(page, sandbox);
  const taken = /already linked to another project in the same project family/;

  await chooseRepo(page, AMARA, REPO, 'main');
  await expect(tab.getByText(taken)).toBeVisible();
  await acceptBox(tab).check();
  await submit(page, CONNECT_NAME);
  expect(repoConnectionOf(sandbox)).toBeUndefined();

  await chooseIn(page, 'Branch', 'dev');
  await expect(tab.getByText(taken)).toHaveCount(0);
});

// @S11
// Scenario: Admin without installations is told to install the GitHub App
//   Given I am an admin with a connected GitHub account and no GitHub App installations
//   When I open the "Sync to GitHub" tab
//   Then I see "No GitHub installations found"
//   And I see "You haven't installed the OpenFn GitHub App yet, or you may have uninstalled it."
//   And "Install or manage GitHub app installations" opens the app's GitHub page in a new tab
test('@S11', PASSING_BOTH, async ({ page }) => {
  givenGithub({});
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);

  await expect
    .poll(() => shownIn(tab))
    .toContain('No GitHub installations found');
  await expect
    .poll(() => shownIn(tab))
    .toContain(
      "You haven't installed the OpenFn GitHub App yet, or you may have uninstalled it."
    );
  const install = tab.getByRole('link', {
    name: 'Install or manage GitHub app installations',
  });
  await expect(install).toHaveAttribute(
    'href',
    'https://github.com/apps/scenario-app'
  );
  await expect(install).toHaveAttribute('target', '_blank');
});

// @S12
// Scenario: A GitHub outage while loading installations is reported
//   Given I am an admin with a connected GitHub account
//   And GitHub returns an error when listing my installations
//   When I open the "Sync to GitHub" tab
//   Then I see "Unable to load GitHub installations"
//   And I see "There was a problem connecting to GitHub. Refresh the page or contact support if the problem persists."
//   And "GitHub Installation" is disabled
// (Disabled is not the Value here; the message is.)
test('@S12', PASSING_BOTH, async ({ page }) => {
  givenGithub({
    answers: [
      {
        method: 'get',
        path: '/user/installations',
        status: 500,
        body: { message: 'Server Error' },
      },
    ],
  });
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);

  await expect
    .poll(() => shownIn(tab))
    .toContain('Unable to load GitHub installations');
  await expect
    .poll(() => shownIn(tab))
    .toContain(
      'There was a problem connecting to GitHub. Refresh the page or contact support if the problem persists.'
    );
});

// @S13
// Scenario: Admin without a GitHub account is asked to connect one
//   Given I am an admin on project "Malawi HIV" with no GitHub account connected
//   And the project has no GitHub connection
//   When I open the "Sync to GitHub" tab
//   Then I see "Connect your OpenFn account to GitHub"
//   And I see a "Connect your GitHub Account" link that opens GitHub in a new tab
//   And the flow "flow-github-connect" can start from this link
test('@S13', PASSING_OLD, async ({ page }) => {
  givenGithub();
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);

  await expect
    .poll(() => shownIn(tab))
    .toContain('Connect your OpenFn account to GitHub');
  const link = githubLink(page, 'Connect');
  await expect(link).toHaveAttribute('target', '_blank');
  const asked = await followToGithub(page, link);
  expect(asked.pathname).toBe('/login/oauth/authorize');
  expect(asked.searchParams.get('client_id')).toBe(github.clientId);
});

// @S14
// Scenario: Admin with an expired GitHub token is asked to reconnect it
//   Given I am an admin whose GitHub refresh token has expired
//   And the project has no GitHub connection
//   When I open the "Sync to GitHub" tab
//   Then I see "Reconnect your GitHub Account"
//   And I do not see the connect form
test('@S14', PASSING_OLD, async ({ page }) => {
  givenGithub();
  givenMyGithub('lapsed');
  const id = givenProject('admin').id(PROJECT);
  await onGithub(page, id);

  await expect(githubLink(page, 'Reconnect')).toBeVisible();
  await expect(connectButton(page)).toHaveCount(0);
});

// @S15
// Scenario Outline: Only admins see how to connect a project
//   Given I am a <role> on project "Malawi HIV", which has no GitHub connection
//   And I have a connected GitHub account
//   When I open the "Sync to GitHub" tab
//   Then I do not see "Connect your OpenFn account to GitHub"
//   And I do not see "Create/update GitHub installations or modify permissions."
//
//   Examples:
//     | role   |
//     | viewer |
//     | editor |
for (const role of ['viewer', 'editor'] as const) {
  test(`@S15 ${role}`, PASSING_BOTH, async ({ page }) => {
    givenGithub();
    givenMyGithub();
    const id = givenProject(role).id(PROJECT);
    const tab = await onGithub(page, id);

    await expect(tab).toBeVisible();
    await expect
      .poll(() => shownIn(tab))
      .not.toContain('Connect your OpenFn account to GitHub');
    await expect
      .poll(() => shownIn(tab))
      .not.toContain(
        'Create/update GitHub installations or modify permissions.'
      );
    await expect(connectButton(page)).toHaveCount(0);
  });
}

// @S16 @variant:github-disabled
// Scenario: An instance without a GitHub app says so
//   Given the instance has no GitHub app configured
//   And I am a viewer on project "Malawi HIV"
//   When I open the "Sync to GitHub" tab
//   Then I see "Version Control is not configured for this Lightning instance. Contact the superuser for more information."
test('@S16', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  github.removeApp();
  const id = givenProject('viewer').id(PROJECT);
  const tab = await onGithub(page, id);

  await expect
    .poll(() => shownIn(tab))
    .toContain(
      'Version Control is not configured for this Lightning instance. Contact the superuser for more information.'
    );
});

// @S17
// Scenario: Everyone on the project sees the saved connection
//   Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main" through installation "1234"
//   And I am a viewer on the project
//   When I open the "Sync to GitHub" tab
//   Then I see "Repository:" linking to "https://www.github.com/amara/hiv-sync"
//   And I see "Branch:" "main", "GitHub Installation ID:" "1234", "Path to config:" and "Sync version:"
//   And I do not see the connect form
test('@S17', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  const id = givenConnected('viewer');
  const tab = await onGithub(page, id);

  await expect(tab.getByRole('link', { name: REPO })).toHaveAttribute(
    'href',
    /^https:\/\/(www\.)?github\.com\/amara\/hiv-sync$/
  );
  await expect.poll(() => shownIn(tab)).toMatch(/Branch:\s*main/);
  await expect.poll(() => shownIn(tab)).toMatch(/Installation ID:\s*1234/);
  await expect.poll(() => shownIn(tab)).toContain('Path to config:');
  await expect.poll(() => shownIn(tab)).toContain('Sync version:');
  await expect(connectButton(page)).toHaveCount(0);
});

// @S18
// Scenario: A healthy connection is confirmed
//   Given project "Malawi HIV" is connected and the repo has its workflow files, config and API secret
//   When I open the "Sync to GitHub" tab
//   Then I eventually see "Your repository is properly configured."
//   And I do not see "Click here to reconnect"
test('@S18', PASSING_OLD, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenConnected('admin');
  const tab = await onGithub(page, id);

  await expect
    .poll(() => shownIn(tab))
    .toContain('Your repository is properly configured.');
  await expect(reconnectButton(page)).toHaveCount(0);
});

// @S19
// Scenario: A broken connection is flagged and admins can reconnect
//   Given project "Malawi HIV" is connected but the deploy workflow file is missing on the branch
//   And I am an admin whose GitHub account can access the connection's installation
//   When I open the "Sync to GitHub" tab
//   Then I eventually see "Your GitHub project is not properly connected with Lightning."
//   And I see "There was a problem connecting to GitHub"
//   And I see "Click here to reconnect"
//   And "Initiate Sync to Branch" is disabled
// (Whether sync stays off on a broken connection is not the Value, which is
// that the team finds out and can repair it.)
test('@S19', PASSING_OLD, async ({ page }) => {
  givenMyGithub();
  const id = givenConnected('admin');
  givenGithub({ ...WORLD, missing: [deployFile(id)] });
  const tab = await onGithub(page, id);

  await expect
    .poll(() => shownIn(tab))
    .toContain('Your GitHub project is not properly connected with Lightning.');
  await expect
    .poll(() => shownIn(tab))
    .toContain('There was a problem connecting to GitHub');
  await expect(reconnectButton(page)).toBeVisible();
});

// @S20
// Scenario Outline: Reconnect is offered only to admins who can reach the installation
//   Given project "Malawi HIV" has a broken GitHub connection
//   And I am a <role> who <access> the connection's installation
//   When I open the "Sync to GitHub" tab
//   Then I do not see "Click here to reconnect"
//
//   Examples:
//     | role   | access              |
//     | viewer | can access          |
//     | editor | can access          |
//     | admin  | cannot access       |
//     | owner  | cannot access       |
for (const [role, access] of [
  ['viewer', true],
  ['editor', true],
  ['admin', false],
  ['owner', false],
] as const) {
  test(`@S20 ${role}`, PASSING_OLD, async ({ page }) => {
    givenMyGithub();
    const id = givenConnected(role);
    givenGithub({
      installations: [{ ...WORLD.installations![0], mine: access }],
      missing: [deployFile(id)],
    });
    const tab = await onGithub(page, id);

    await expect
      .poll(() => shownIn(tab))
      .toContain(
        'Your GitHub project is not properly connected with Lightning.'
      );
    await expect(reconnectButton(page)).toHaveCount(0);
  });
}

// @S21
// Scenario: Admin reconnects a broken connection
//   Given project "Malawi HIV" has a broken GitHub connection
//   And I am an admin whose GitHub account can access its installation
//   When I click "Click here to reconnect"
//   And in "Reconnect to GitHub" I keep "OpenFn --> GitHub" selected, tick the confirmation and click "Reconnect"
//   Then I see "Connected to GitHub"
//   And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
test('@S21', PASSING_OLD, async ({ page }) => {
  givenMyGithub();
  const id = givenConnected('admin');
  givenGithub({ ...WORLD, missing: [deployFile(id)] });
  await onGithub(page, id);

  await reconnectButton(page).click();
  const dialog = githubDialog(page, 'Reconnect to GitHub');
  await expect(
    dialog.getByRole('radio', { name: /Export to GitHub/ })
  ).toBeChecked();
  await acceptBox(dialog).check();
  await dialog.getByRole('button', { name: 'Reconnect', exact: true }).click();

  await expect(flashMessages.toast(page, 'Connected to GitHub')).toBeVisible();
  expect(writes().some(r => r.url.includes(`/repos/${REPO}/git/`))).toBe(true);
  expect(dispatches()).toHaveLength(1);
});

// @S22
// Scenario: Editor starts a sync
//   Given project "Malawi HIV" is connected and verified
//   And I am an editor with no GitHub account connected
//   When I click "Initiate Sync to Branch"
//   Then I see "GitHub sync initiated"
//   And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
test('@S22', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  const id = givenConnected('editor');
  await onGithub(page, id);
  await connectionChecked(page);

  await syncButton(page).click();

  await expect(
    flashMessages.toast(page, 'GitHub sync initiated')
  ).toBeVisible();
  const [dispatch] = dispatches();
  expect(JSON.parse(dispatch.body).inputs).toMatchObject({
    projectId: id,
    branch: 'main',
  });
});

// @S23
// Scenario: Viewers can't start a sync and are told who can
//   Given project "Malawi HIV" is connected
//   And I am a viewer on the project
//   When I open the "Sync to GitHub" tab
//   Then "Initiate Sync to Branch" is disabled with the tooltip "Contact an editor or admin to sync."
//   And I do not see "Remove Integration."
test('@S23', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  const id = givenConnected('viewer');
  await onGithub(page, id);
  await connectionChecked(page);

  await expect(syncButton(page)).toBeDisabled();
  await expectTooltip(
    page,
    syncButton(page),
    'Contact an editor or admin to sync.'
  );
  await expect(removeIntegration(page)).toHaveCount(0);
});

// @S24
// Scenario Outline: The server refuses actions a role isn't allowed, even if the control is bypassed
//   Given project "Malawi HIV" is connected
//   And I am a <role> on the project
//   When a "<event>" event reaches the GitHub sync component
//   Then I see "You are not authorized to perform this action"
//   And the connection is unchanged
//
//   Examples:
//     | role   | event             |
//     | viewer | initiate-sync     |
//     | viewer | reconnect         |
//     | editor | reconnect         |
//     | viewer | delete-connection |
//     | editor | delete-connection |
//     | editor | save              |
// (Checked by effect, the way a crafted request is: the connection, GitHub
// and no crash. A connect needs the project to have no connection, so the
// "save" row removes it once the page is open.)
for (const [role, kind] of [
  ['viewer', 'initiate-sync'],
  ['viewer', 'reconnect'],
  ['editor', 'reconnect'],
  ['viewer', 'delete-connection'],
  ['editor', 'delete-connection'],
  ['editor', 'save'],
] as [Role, GithubRequest][]) {
  test(`@S24 ${role} ${kind}`, PASSING_BOTH, async ({ page }) => {
    givenGithub();
    givenMyGithub();
    const id = givenConnected(role);
    const tab = await onGithub(page, id);
    await connectionChecked(page);
    const { lv } = tab;
    const before = writes().length;

    if (kind === 'save')
      exec(`delete from project_repo_connections where project_id = '${id}'`);
    await sendGithubRequest(page, lv, kind, {
      installation: '1234',
      repo: REPO,
      branch: 'dev',
    });

    expect(repoConnectionOf(id)).toEqual(
      kind === 'save'
        ? undefined
        : expect.objectContaining({ repo: REPO, branch: 'main' })
    );
    // Minting an installation token changes nothing in the repo
    expect(writes().slice(before)).toHaveLength(0);
    expect(lv.crashes()).toBe(0);
  });
}

// @S25
// Scenario: Admin removes the integration after confirming
//   Given project "Malawi HIV" is connected to "amara/hiv-sync"
//   And I am an admin on the project
//   When I click "Remove Integration."
//   Then I see "Remove Integration?" and "You are about to disconnect this project from GitHub."
//   When I click "Disconnect"
//   Then I see "Connection removed successfully"
//   And the project has no GitHub connection
//   And an audit event "repo_connection_removed" is recorded for the project
test('@S25', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenConnected('admin');
  await onGithub(page, id);

  await removeIntegration(page).click();
  const dialog = githubDialog(page, 'Remove Integration?');
  await expect(dialog).toContainText(
    'You are about to disconnect this project from GitHub.'
  );
  await dialog.getByRole('button', { name: 'Disconnect', exact: true }).click();

  await expect(
    flashMessages.toast(page, 'Connection removed successfully')
  ).toBeVisible();
  expect(repoConnectionOf(id)).toBeUndefined();
  expect(auditEventsOf(id).map(e => e.event)).toContain(
    'repo_connection_removed'
  );
});

// @S26
// Scenario: Removal succeeds even when GitHub cleanup can't
//   Given project "Malawi HIV" is connected
//   And I am an admin with no GitHub account connected
//   When I remove the integration
//   Then I see "Connection removed successfully"
//   And the project has no GitHub connection
test('@S26', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  const id = givenConnected('admin');
  await onGithub(page, id);

  await removeIntegration(page).click();
  await githubDialog(page, 'Remove Integration?')
    .getByRole('button', { name: 'Disconnect', exact: true })
    .click();

  await expect(
    flashMessages.toast(page, 'Connection removed successfully')
  ).toBeVisible();
  expect(repoConnectionOf(id)).toBeUndefined();
});

// @S27 @variant:github-sync-limited
// Scenario: A GitHub sync plan limit blocks connecting and syncing and says why
//   Given the usage limiter refuses GitHub sync for project "Malawi HIV" with a banner message
//   And I am an admin on the project
//   When I open the "Sync to GitHub" tab
//   Then I see the limiter's banner message
//   And "Connect Branch & Initiate First Sync" is disabled
// (Blocking is checked by its effect: a connect sent past the form makes
// nothing.)
test('@S27', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  cleanups.push(
    withLimiterRefusing('github_sync', 'GitHub sync is not in your plan', {
      banner: true,
    })
  );
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);
  const { lv } = tab;

  await expect
    .poll(() => shownIn(tab))
    .toContain('GitHub sync is not in your plan');
  await sendGithubRequest(page, lv, 'save', {
    installation: '1234',
    repo: REPO,
    branch: 'main',
  });

  expect(repoConnectionOf(id)).toBeUndefined();
  expect(writes()).toHaveLength(0);
  expect(lv.crashes()).toBe(0);
});

// @S28 @variant:github-sync-limited
// Scenario: The limit is checked again when the action runs
//   Given I am an admin on the connect form of project "Malawi HIV"
//   And the usage limiter starts refusing GitHub sync with "Plan limit reached"
//   When I submit the connect form
//   Then I see "Plan limit reached"
//   And the project has no GitHub connection
test('@S28', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);
  await chooseRepo(page, AMARA, REPO, 'main');
  await acceptBox(tab).check();

  cleanups.push(
    withLimiterRefusing('github_sync', 'Plan limit reached', { banner: true })
  );
  await connectButton(page).click();

  await expect(flashMessages.toast(page, 'Plan limit reached')).toBeVisible();
  expect(repoConnectionOf(id)).toBeUndefined();
});

// @S29
// Scenario: Colliding names stop a sync before anything reaches GitHub
//   Given project "Malawi HIV" is connected
//   And it has workflows "My Flow" and "My-Flow"
//   And I am an admin on the project
//   When I click "Initiate Sync to Branch"
//   Then I see an error naming "My Flow" and "My-Flow"
//   And no workflow is dispatched in GitHub
test('@S29', PASSING_BOTH, async ({ page }) => {
  givenGithub();
  givenMyGithub();
  const id = givenConnected('admin', { workflows: ['My Flow', 'My-Flow'] });
  await onGithub(page, id);
  await connectionChecked(page);

  await syncButton(page).click();

  const error = page.getByRole('alert').filter({ hasText: 'My-Flow' });
  await expect(error).toContainText('My Flow');
  expect(dispatches()).toHaveLength(0);
});

// @S30
// Scenario: GitHub's own error message is shown when a connect fails
//   Given I am an admin submitting the connect form on project "Malawi HIV"
//   And GitHub refuses a file write with message "Resource not accessible by integration"
//   When the connect runs
//   Then I see "GitHub Error: Resource not accessible by integration"
//   And the project has no GitHub connection
test('@S30', PASSING_BOTH, async ({ page }) => {
  givenGithub({
    ...WORLD,
    answers: [
      {
        method: 'post',
        path: '/git/blobs',
        status: 403,
        body: { message: 'Resource not accessible by integration' },
      },
    ],
  });
  givenMyGithub();
  const id = givenProject('admin').id(PROJECT);
  const tab = await onGithub(page, id);
  await chooseRepo(page, AMARA, REPO, 'main');
  await acceptBox(tab).check();
  await connectButton(page).click();

  await expect(
    flashMessages.toast(
      page,
      'GitHub Error: Resource not accessible by integration'
    )
  ).toBeVisible();
  expect(repoConnectionOf(id)).toBeUndefined();
});
