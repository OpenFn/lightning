// Scenarios from annotations/views/project-settings-history-exports.md. The
// shared session, scope, banner, header, flash and tab chrome scenarios run
// once for every settings tab, in project-settings-setup.spec.ts.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns the projects I don't. People who requested
// exports are new accounts made for the test, seeded before the project so
// they are removed after it.
import { expect, test, type Page } from '@playwright/test';

import {
  exportRow,
  openSettings,
  panel,
  sandboxBanner,
} from './pages/project-settings';
import {
  seedExport,
  seedUser,
  seedWorkspace,
  signInAs,
  user,
  type ExportStatus,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';
const PROJECT = 'Malawi HIV';

const PASSING_BOTH = { tag: ['@passing-old', '@passing-new'] };

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

// Given I am a <role> on project <name> (owner@openfn.org owns it unless I do)
function givenProject(
  role: Role,
  name = PROJECT,
  extra: Partial<WorkspaceSeed> = {}
) {
  const members: Record<string, Role> =
    role === 'owner' ? { [ME]: 'owner' } : { [ME]: role, [OTHER]: 'owner' };
  const w = seedWorkspace({ name, members, ...extra }, OTHER);
  cleanups.push(w.remove);
  return w.id(name);
}

// Given <userId> requested a history export on project <id> that is <status>
function givenExport(id: string, userId: string, status: ExportStatus) {
  const e = seedExport(id, userId, status);
  cleanups.push(e.remove);
  return e;
}

// Given I am signed in and on project <id>'s History Exports tab
async function onHistoryExports(page: Page, id: string) {
  await signInAs(page, ME);
  await openSettings(page, id, 'History Exports');
}

const NONE = 'No history exports found for this project.';

// @S01
// Scenario: Members see every export requested on the project
//   Given I am a viewer on project "Malawi HIV"
//   And "Amara Banda" requested a history export that has completed
//   And "Tomas Silva" requested a history export that is in progress
//   When I open the project's settings on the "History Exports" tab
//   Then I see a row requested by "Amara Banda" with status "Completed" and the zip's filename
//   And I see a row requested by "Tomas Silva" with status "In progress" and the filename "Pending"
//   And each row shows when the export was requested
test('@S01', PASSING_BOTH, async ({ page }) => {
  const amara = seedUser('amara', { firstName: 'Amara', lastName: 'Banda' });
  const tomas = seedUser('tomas', { firstName: 'Tomas', lastName: 'Silva' });
  cleanups.push(amara.remove, tomas.remove);
  const id = givenProject('viewer');
  const done = givenExport(id, amara.id, 'completed');
  givenExport(id, tomas.id, 'in_progress');
  await onHistoryExports(page, id);

  const amaras = exportRow(page, 'Amara Banda');
  await expect(amaras).toContainText('Completed');
  await expect(amaras).toContainText(done.filename!);
  const tomass = exportRow(page, 'Tomas Silva');
  await expect(tomass).toContainText(/In progress/i);
  await expect(tomass).toContainText('Pending');
  // A time of day, whether the date is spelled out or said as "today"
  const time = /\d{1,2}:\d{2}/;
  await expect(amaras).toContainText(time);
  await expect(tomass).toContainText(time);
});

// @S02
// Scenario Outline: Any member can start the download of a completed export
//   Given I am a <role> on project "Malawi HIV"
//   And a history export on the project has completed
//   When I open the project's settings on the "History Exports" tab
//   Then that row's "Download" link points to "/project_files/<project_file_id>/download" and opens in a new tab
//   When I click "Download"
//   Then the flow "flow-history-export" continues at controller:project-file-download for that file
// (The flow's own checks are flow-history-export S01, S07 and S08; here the
// download only has to arrive.)
for (const role of ['viewer', 'editor', 'admin', 'owner'] as const) {
  test(`@S02 ${role}`, PASSING_BOTH, async ({ page }) => {
    const id = givenProject(role);
    const done = givenExport(id, user(OTHER).id, 'completed');
    await onHistoryExports(page, id);

    const link = exportRow(page, done.filename!).getByRole('link', {
      name: 'Download',
    });
    await expect(link).toHaveAttribute(
      'href',
      `/project_files/${done.id}/download`
    );
    await expect(link).toHaveAttribute('target', '_blank');
    // The new tab only starts the download, so the download is fetched as
    // that member
    const response = await page.request.get((await link.getAttribute('href'))!);
    expect(response.ok()).toBe(true);
    expect(response.headers()['content-disposition']).toContain(done.filename!);
  });
}

// @S03
// Scenario: A project with no exports says so
//   Given I am an editor on project "Malawi HIV"
//   And nobody has requested a history export on the project
//   When I open the project's settings on the "History Exports" tab
//   Then I see "No history exports found for this project."
//   And I see no exports table
test('@S03', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('editor');
  await onHistoryExports(page, id);

  const tab = panel(page, 'History Exports');
  await expect(tab).toContainText(NONE);
  await expect(tab.getByRole('table')).toHaveCount(0);
});

// @S04
// Scenario: Only this project's exports are listed
//   Given I am an owner of projects "Malawi HIV" and "Kenya TB"
//   And a history export on "Kenya TB" has completed
//   When I open the settings of "Malawi HIV" on the "History Exports" tab
//   Then I see "No history exports found for this project."
test('@S04', PASSING_BOTH, async ({ page }) => {
  const id = givenProject('owner');
  const kenya = givenProject('owner', 'Kenya TB');
  givenExport(kenya, user(ME).id, 'completed');
  await onHistoryExports(page, id);

  await expect(panel(page, 'History Exports')).toContainText(NONE);
});

// @S05 @variant:sandbox
// Scenario: A sandbox lists its own exports, not its parent's
//   Given I am an owner of sandbox "dev" of project "Malawi HIV"
//   And a history export on "Malawi HIV" has completed
//   When I open the settings of sandbox "dev" on the "History Exports" tab
//   Then I see "No history exports found for this project."
//   And I see the sandbox banner (shared-project-settings-tab-chrome S08, row "History Exports")
test('@S05', PASSING_BOTH, async ({ page }) => {
  const w = seedWorkspace(
    { name: PROJECT, members: { [ME]: 'owner' }, sandboxes: [{ name: 'dev' }] },
    ME
  );
  cleanups.push(w.remove);
  givenExport(w.id(PROJECT), user(ME).id, 'completed');
  await onHistoryExports(page, w.id('dev'));

  const tab = panel(page, 'History Exports');
  await expect(tab).toContainText(NONE);
  await expect(sandboxBanner(tab)).toBeVisible();
});
