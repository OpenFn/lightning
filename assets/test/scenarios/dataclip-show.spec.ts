// Scenarios from annotations/views/dataclip-show.md.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names (a viewer unless it says otherwise). owner@openfn.org owns every
// project and builds its workflows, runs and credentials through Lightning.
// super@openfn.org is the third member a test needs. Every project is seeded
// by the test and removed again afterwards, with its runs, dataclips and the
// credentials its steps used.
import { expect, test, type Page } from '@playwright/test';

import { detail, detailLabel } from './pages/dataclip-show';
import * as authenticatedSession from './shared/authenticated-session';
import * as bodyViewer from './shared/dataclip-body-viewer';
import * as flashMessages from './shared/flash-messages';
import * as localDatetime from './shared/local-datetime';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import * as usageLimitsBanner from './shared/usage-limits-banner';
import {
  changeRoleOnNode,
  dataclipPath,
  exec,
  expectAt,
  keepAccount,
  keepNoData,
  makeSupportUser,
  manifest,
  open,
  removeMemberOnNode,
  removeMfaOf,
  removeWorkflowData,
  runPath,
  scheduleDeletionOnNode,
  seedDataclip,
  seedRun,
  seedWorkspace,
  setSupportAccessOnNode,
  shortId,
  signInAs,
  type DataclipSeed,
  type DataclipType,
  type RunSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests disable or MFA me
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it);
// removed after the test with its runs and dataclips — returns its id
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
  // Runs before the project is removed: runs and steps hold references
  cleanups.push(() => removeWorkflowData(id));
  return { id, w, by };
}

// Given project <projectId> has a run seeded by its owner — returns its ids.
// Its credentials are removed after the project.
function givenRun(projectId: string, seed: RunSeed) {
  const run = seedRun(projectId, seed, OWNER);
  cleanups.unshift(run.removeCredentials);
  return run;
}

// When I sign in and open dataclip <id> of project <projectId>
async function openDataclip(page: Page, projectId: string, id: string) {
  await signInAs(page, ME);
  await open(page, dataclipPath(projectId, id));
}

// Given my project has this dataclip, when I open its page — returns the
// project's and dataclip's ids
async function onDataclip(
  page: Page,
  seed: DataclipSeed,
  members?: Record<string, Role>
) {
  const { id: projectId } = givenProject(members);
  const id = seedDataclip(projectId, seed);
  await openDataclip(page, projectId, id);
  return { projectId, id };
}

// The panel heading only the dataclip page shows
const detailsHeading = (page: Page) =>
  page.getByText('Dataclip Details', { exact: true });

const WIPED_MESSAGE =
  "This dataclip's data has been wiped in accordance with the project's data retention policy.";

// Then I see the wiped panel, and no body viewer
async function expectWipedPanel(page: Page, wipedOn: RegExp) {
  await expect(detail(page, 'Wiped')).toHaveText(wipedOn);
  await expect(
    page.getByText('No Data Available', { exact: true })
  ).toBeVisible();
  await expect(page.getByText(WIPED_MESSAGE)).toBeVisible();
  await expect(bodyViewer.viewer(page)).toHaveCount(0);
  await expect(bodyViewer.copyButton(page)).toHaveCount(0);
}

// @S01
// Scenario: The details panel identifies the dataclip
//   Given project "Malawi HIV" has a step result dataclip with body {"foo": "bar"}
//   When I open its dataclip page
//   Then the breadcrumb reads "Dataclip" followed by the first eight characters of its id
//   And the "Dataclip Details" panel shows "ID" with the full id
//   And it shows "Type", "Created" and "Updated"
//   And it does not show "Wiped"
test('@S01', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id } = await onDataclip(page, {
    type: 'step_result',
    body: { foo: 'bar' },
  });

  const lastCrumb = page
    .getByRole('navigation', { name: 'Breadcrumbs' })
    .getByRole('listitem')
    .last();
  await expect
    .poll(async () => (await lastCrumb.innerText()).replace(/\s+/g, ' ').trim())
    .toMatch(new RegExp(`^Dataclip ?${shortId(id)}$`));
  await expect(detailsHeading(page)).toBeVisible();
  await expect(detail(page, 'ID')).toHaveText(id);
  await expect(detail(page, 'Type')).toHaveText('step_result');
  await expect(detail(page, 'Created')).toHaveText(/\d/);
  await expect(detail(page, 'Updated')).toHaveText(/\d/);
  await expect(detailLabel(page, 'Wiped')).toHaveCount(0);
});

// @S02
// Scenario Outline: The type pill says where the data came from
//   Given a dataclip of type <type>
//   When I open its dataclip page
//   Then "Type" shows a pill reading <label>
//   Examples: http_request, step_result, saved_input, global, kafka, each
//   labelled with its own name
// The pill's colour is the look; the Value is the label.
test('@S02', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject();
  const types: DataclipType[] = [
    'http_request',
    'step_result',
    'saved_input',
    'global',
    'kafka',
  ];
  await signInAs(page, ME);
  for (const type of types) {
    const id = seedDataclip(projectId, { type, body: { kind: type } });
    await open(page, dataclipPath(projectId, id));
    await expect.soft(detail(page, 'Type'), type).toHaveText(type);
  }
});

// @S03
// Scenario: The body is shown formatted and read-only
//   Given a global dataclip whose body is {"patients":[{"id":1}]}
//   When I open its dataclip page
//   Then the viewer shows the body as JSON indented by two spaces
//   And the viewer does not accept typing
test('@S03', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const body = { patients: [{ id: 1 }] };
  await onDataclip(page, { type: 'global', body });

  await bodyViewer.S01(page, body);
});

// @S04
// Scenario: The body can be copied
//   Given I am on a dataclip page whose body has loaded
//   When I click "Copy to clipboard"
//   Then the clipboard holds the body as displayed
//   And the button reads "Copied!" for two seconds
test('@S04', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const body = { patient: { name: 'Ada' } };
  await onDataclip(page, { type: 'saved_input', body });

  await bodyViewer.S02(page, body);
});

// @S05
// Scenario: A webhook request shows its data and request together, with webhook credentials hidden
//   Given workflow "Intake" has a webhook trigger protected by basic auth "webhook_user" with password "webhook_secret_pass"
//   And a request to that webhook stored an http_request dataclip with an "authorization" header and data "test payload"
//   When I open the dataclip page
//   Then the viewer shows "data" and "request" keys
//   And it shows "test payload"
//   And it does not show "webhook_secret_pass" or its base64 basic auth value
//   And it shows "***" in their place
test('@S05', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject();
  const { username, password } = bodyViewer.given.S03;
  const run = givenRun(projectId, {
    basicAuth: [username, password],
    input: bodyViewer.webhookRequest(),
  });
  await openDataclip(page, projectId, run.inputId);

  await bodyViewer.S03(page);
});

// @S06
// Scenario: A step's output hides the credential values the step used
//   Given step "Fetch" ran with a credential whose values include the number 1234 and the string "some-secret"
//   And "Fetch" produced an output dataclip containing those values
//   When I open that output's dataclip page
//   Then those values are shown masked with "***"
//   And values not in the credential are shown unchanged
test('@S06', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject();
  const run = givenRun(projectId, {
    steps: [
      {
        name: 'Fetch',
        credential: { pin: 1234, token: 'some-secret' },
        output: { pin: 1234, token: 'some-secret', note: 'kept', ok: true },
      },
    ],
  });
  await openDataclip(page, projectId, run.outputs.Fetch);

  const text = async () =>
    (await bodyViewer.viewerText(page)).replace(/\n/g, '');
  await expect.poll(text).toContain('kept');
  const shown = await text();
  expect(shown).not.toContain('1234');
  expect(shown).not.toContain('some-secret');
  expect(shown).toMatch(/"pin":\s*\*\*\*/);
  expect(shown).toMatch(/"token":\s*"\*\*\*"/);
  expect(shown).toMatch(/"ok":\s*true/);
});

// @S07
// Scenario: A dataclip from another project cannot be opened
//   Given I am an editor on project "Malawi HIV"
//   And dataclip "D" belongs to project "Kenya TB"
//   When I visit "/projects/<Malawi HIV id>/dataclips/<D id>/show"
//   Then I am on the "Malawi HIV" history page
//   And I see "Dataclip not found"
//   And the same happens for an id that does not exist or is not a valid id
// I am an editor on "Kenya TB" too, so only the project in the URL refuses.
test('@S07', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const malawi = givenProject({ [ME]: 'editor' });
  const kenya = givenProject({ [ME]: 'editor' }, { name: 'Kenya TB' });
  const d = seedDataclip(kenya.id, { type: 'global', body: { from: 'kenya' } });
  await signInAs(page, ME);

  for (const id of [d, '00000000-0000-4000-8000-000000000000', 'not-an-id']) {
    await page.goto(dataclipPath(malawi.id, id));
    await expectAt(page, `/projects/${malawi.id}/history`);
    await expect
      .soft(flashMessages.toast(page, 'Dataclip not found'), id)
      .toBeVisible();
  }
});

// @S08
// Scenario: A non-member cannot open the page
//   Given dataclip "D" belongs to project "Kenya TB"
//   And I am not on "Kenya TB"
//   When I visit "/projects/<Kenya TB id>/dataclips/<D id>/show"
//   Then shared-project-scope S03 holds
test('@S08', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const kenya = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
  const d = seedDataclip(kenya.id, { type: 'global', body: { from: 'kenya' } });

  await projectScope.S03(page, dataclipPath(kenya.id, d), ME);
});

// @S09
// Scenario: A wiped dataclip says its data was erased, and when
//   Given project "Malawi HIV" has a step result dataclip that the retention policy wiped on 1 March
//   When I open its dataclip page
//   Then the details panel shows "Wiped" with that time
//   And I see "No Data Available"
//   And I see "This dataclip's data has been wiped in accordance with the project's data retention policy."
//   And no body viewer is shown
// 1 March of last year, so the time shows its date (shared-local-datetime S02).
test('@S09', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  await onDataclip(page, {
    type: 'step_result',
    body: { foo: 'bar' },
    at: '2025-02-28 10:00:00',
    wipedAt: '2025-03-01 09:15:00',
  });

  await expectWipedPanel(page, /^\s*2025-03-01,/);
});

// @S10
// Scenario: A zero-persistence run's final output opens as wiped
//   Given project "Malawi HIV" does not retain data
//   And a run of "Intake" has finished with a final output
//   When I follow "Final Output" on the run page
//   Then the flow "flow-zero-persistence-runs" ends on this page with the wiped panel from S09
// The run finishes through Lightning, which wipes the final output as the
// project's retention policy says. The Final Output link reads the output's
// short id.
test('@S10', { tag: ['@passing-old', '@passing-new'] }, async ({ page }) => {
  const { id: projectId } = givenProject();
  keepNoData(projectId);
  const run = givenRun(projectId, {
    steps: [{ name: 'Fetch' }],
    finalState: { patients: 3 },
  });
  expect(run.finalId, 'the run has a final output').not.toBeNull();
  await signInAs(page, ME);
  await open(page, runPath(projectId, run.runId));

  await page
    .getByRole('link', { name: shortId(run.finalId!), exact: true })
    .click();

  await expectAt(page, dataclipPath(projectId, run.finalId!));
  await expectWipedPanel(page, /\d/);
});

// ---------------------------------------------------------------------------
// Inherited shared annotations, run on a dataclip page
const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING = { tag: ['@passing-old', '@passing-new'] };

// Given project "Malawi HIV" (or <name>) with these members and a dataclip
function givenDataclipPage(
  members: Record<string, Role> = { [ME]: 'owner' },
  name = 'Malawi HIV'
) {
  const project = givenProject(members, { name });
  const dataclipId = seedDataclip(project.id, {
    type: 'step_result',
    body: { shared: true },
  });
  return {
    ...project,
    dataclipId,
    path: dataclipPath(project.id, dataclipId),
  };
}

test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on dataclip-show',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S01(page, givenDataclipPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on dataclip-show',
    PASSING,
    async ({ page, browser }) => {
      await authenticatedSession.S02(
        page,
        browser,
        givenDataclipPage().path,
        ME
      );
    }
  );

  test(
    'shared-authenticated-session@S03 on dataclip-show',
    PASSING,
    async ({ page }) => {
      await authenticatedSession.S03(page, givenDataclipPage().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on dataclip-show',
    PASSING,
    async ({ page, browser }) => {
      const h = givenDataclipPage();
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
    test(`shared-authenticated-session@${id} on dataclip-show`, PENDING, () => {
      test.skip(true, `variant ${variant} is not configured on this instance`);
    });
});

test.describe('shared-project-scope', () => {
  test(
    'shared-project-scope@S01 on dataclip-show',
    PASSING,
    async ({ page }) => {
      await projectScope.S01(page, givenDataclipPage().path);
    }
  );

  test(
    'shared-project-scope@S02 on dataclip-show',
    PASSING,
    async ({ page }) => {
      await projectScope.S02(
        page,
        givenDataclipPage().path,
        ME,
        detailsHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S03 on dataclip-show',
    PASSING,
    async ({ page }) => {
      await projectScope.S03(
        page,
        givenDataclipPage({ [OWNER]: 'owner' }).path,
        ME
      );
    }
  );

  test(
    'shared-project-scope@S04 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [OWNER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.id}'`
      );
      await projectScope.S04(page, h.path, OWNER);
    }
  );

  test(
    'shared-project-scope@S05 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage();
      exec(`update projects set requires_mfa = true where id = '${h.id}'`);
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  // A support user sees every project that allows support access
  test(
    'shared-project-scope@S06 on dataclip-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenDataclipPage({ [OWNER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(page, h.path, ME, detailsHeading(page));
    }
  );

  test(
    'shared-project-scope@S07 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor', [OWNER]: 'owner' });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.id, ME, OWNER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'admin', [OWNER]: 'owner' });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.id, ME, 'viewer'),
        detailsHeading(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on dataclip-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenDataclipPage({ [OWNER]: 'owner' });
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
    'shared-project-scope@S10 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor', [OWNER]: 'owner' });
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
  test('shared-usage-limits-banner@S01 on dataclip-show', PENDING, () => {
    test.skip(true, 'variant usage-limited is not configured on this instance');
  });

  test(
    'shared-usage-limits-banner@S02 on dataclip-show',
    PASSING,
    async ({ page }) => {
      await usageLimitsBanner.S02(
        page,
        givenDataclipPage().path,
        ME,
        detailsHeading(page)
      );
    }
  );
});

// The picker scenarios seed their own "Malawi HIV", so this page's project
// has another name.
test.describe('shared-project-header', () => {
  const HOST = 'Dataclip host';

  test(
    'shared-project-header@S01 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S01(page, h.path, ME, HOST, [
        { name: `Dataclip ${shortId(h.dataclipId)}` },
      ]);
    }
  );

  test(
    'shared-project-header@S02 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on dataclip-show',
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
      const dev = w.id('dev');
      cleanups.push(() => removeWorkflowData(dev));
      const d = seedDataclip(dev, { type: 'global', body: { in: 'dev' } });
      await projectHeader.S03(page, ME, {
        path: dataclipPath(dev, d),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on dataclip-show`,
      PASSING,
      async ({ page }) => {
        const h = givenDataclipPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on dataclip-show',
    { tag: ['@passing-old', '@passing-new', '@serial'] },
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // S09 starts on a project settings page, whatever page hosts the header
  test(
    'shared-project-header@S09 on dataclip-show',
    PASSING,
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // A dataclip exists only in its own project: the Examples row "a
  // dataclip's page" lands on the history page
  test(
    'shared-project-header@S10 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S10(page, h.path, ME, '/history');
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on dataclip-show`,
      PASSING,
      async ({ page }) => {
        const h = givenDataclipPage({ [ME]: 'editor' }, HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test('shared-project-header@S14 on dataclip-show', PENDING, () => {
    test.skip(
      true,
      'variant require-email-verification is not configured on this instance'
    );
  });

  // A dataclip is reached from History, so that is the area it belongs to.
  // Today the page marks no area (shared-project-header 6.2).
  // Fails on today's Lightning: no side-menu link is marked current.
  test(
    'shared-project-header@S15 on dataclip-show',
    { tag: '@passing-new' },
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'viewer' }, HOST);
      await projectHeader.S15(page, h.path, ME, h.id, 'History');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor' }, HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  // A superuser needs a role on the project to open this page at all
  test(
    'shared-project-header@S17 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'viewer', [THIRD]: 'viewer' }, HOST);
      await projectHeader.S17(page, h.path);
    }
  );
});

// Inherited from shared-local-datetime: "Created" in the details panel.
// "Updated" and "Wiped" use the same component.
test.describe('shared-local-datetime', () => {
  // Given a dataclip stored at <utc>, and today is <today>
  async function created(
    page: Page,
    { utc, today }: { utc: string; today?: string }
  ) {
    const { id: projectId } = givenProject();
    const id = seedDataclip(projectId, {
      type: 'global',
      body: { at: utc },
      at: utc,
    });
    await signInAs(page, ME);
    if (today) await page.clock.setFixedTime(today);
    await open(page, dataclipPath(projectId, id));
    return detail(page, 'Created');
  }

  test.describe(() => {
    test.use({ timezoneId: localDatetime.given.S01.timezoneId });
    test(
      'shared-local-datetime@S01 on dataclip-show',
      PASSING,
      async ({ page }) => {
        await localDatetime.S01(
          page,
          await created(page, localDatetime.given.S01)
        );
      }
    );
  });

  for (const id of ['S02', 'S04', 'S05', 'S06'] as const)
    test(
      `shared-local-datetime@${id} on dataclip-show`,
      PASSING,
      async ({ page }) => {
        await localDatetime[id](
          page,
          await created(page, localDatetime.given[id])
        );
      }
    );

  // shared-local-datetime S03 and S07 are not run on this page:
  // not_reachable_here does not exclude them, but the details use the
  // default format (never relative_detailed), Created and Updated are always
  // set, and Wiped is shown only when it is.
});

test.describe('shared-dataclip-body-viewer', () => {
  test(
    'shared-dataclip-body-viewer@S01 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const body = { patients: [{ id: 1 }] };
      await onDataclip(page, { type: 'global', body });
      await bodyViewer.S01(page, body);
    }
  );

  test(
    'shared-dataclip-body-viewer@S02 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const body = { patients: [{ id: 1 }] };
      await onDataclip(page, { type: 'global', body });
      await bodyViewer.S02(page, body);
    }
  );

  test(
    'shared-dataclip-body-viewer@S03 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const { id: projectId } = givenProject();
      const { username, password } = bodyViewer.given.S03;
      const run = givenRun(projectId, {
        basicAuth: [username, password],
        input: bodyViewer.webhookRequest(),
      });
      await openDataclip(page, projectId, run.inputId);
      await bodyViewer.S03(page);
    }
  );

  test(
    'shared-dataclip-body-viewer@S04 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const { id: projectId } = givenProject();
      const { Login, Fetch, Post, output } = bodyViewer.given.S04;
      const run = givenRun(projectId, {
        steps: [
          { name: 'Login', credential: Login },
          { name: 'Fetch', credential: Fetch, output },
          { name: 'Post', credential: Post },
        ],
      });
      await openDataclip(page, projectId, run.outputs.Fetch);
      await bodyViewer.S04(page);
    }
  );

  // Each Examples row is its own "Kenya TB"; my own dataclip page is on
  // "Malawi HIV", which I can read.
  // Fails on the port: the copy button stays when the body failed to load.
  test(
    'shared-dataclip-body-viewer@S05 on dataclip-show',
    PASSING_OLD,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'viewer' });
      const kenya = (members: Record<string, Role>) => {
        const { id } = givenProject(members, { name: 'Kenya TB' });
        return {
          id,
          d: seedDataclip(id, {
            type: 'global',
            body: bodyViewer.given.S05.body,
          }),
        };
      };
      const notMine = kenya({ [OWNER]: 'owner' });
      const scheduled = kenya({ [ME]: 'viewer' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${scheduled.id}'`
      );
      const mfa = kenya({ [ME]: 'viewer' });
      exec(`update projects set requires_mfa = true where id = '${mfa.id}'`);
      removeMfaOf(ME);

      await signInAs(page, ME);
      for (const k of [notMine, scheduled, mfa])
        await bodyViewer.S05(page, h.dataclipId, k.d, () => open(page, h.path));
    }
  );

  test(
    'shared-dataclip-body-viewer@S06 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'viewer' });
      await signInAs(page, ME);
      await bodyViewer.S06(page, h.dataclipId, () => open(page, h.path));
    }
  );
});

// The page's own flash: an error, carried to History when the dataclip is not
// in the project (S07).
test.describe('shared-flash-messages', () => {
  test(
    'shared-flash-messages@S02 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage({ [ME]: 'editor' });
      const other = givenDataclipPage({ [ME]: 'editor' }, 'Kenya TB');
      await signInAs(page, ME);
      await flashMessages.S02(page, 'Dataclip not found', async () => {
        await page.goto(dataclipPath(h.id, other.dataclipId));
      });
    }
  );

  test(
    'shared-flash-messages@S06 on dataclip-show',
    PASSING,
    async ({ page }) => {
      const h = givenDataclipPage();
      const notMine = givenDataclipPage({ [OWNER]: 'owner' }, 'Kenya TB');
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

  // shared-flash-messages S01, S03, S04 and S05 are not run on this page:
  // they need an info flash, and this page puts only the error above. S07 is
  // on admin pages (settings layout) and S08 on the sign-in and account
  // forms.
});
