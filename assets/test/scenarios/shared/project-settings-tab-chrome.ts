// Scenarios from annotations/shared/shared-project-settings-tab-chrome.md.
// Every project settings tab hosts these; the host seeds the project and
// signs in, and the functions hold the When and Then. How either version
// draws the tabs and panels is in pages/project-settings.ts.
import { expect, type Page } from '@playwright/test';

import {
  TABS,
  changeDataStorageSetting,
  chooseTab,
  expectSelected,
  openSettings,
  panel,
  roleNotice,
  sandboxBanner,
  settingsPath,
  tab,
  type TabLabel,
} from '../pages/project-settings';
import { open, reload } from '../steps';

const LABELS = Object.keys(TABS) as TabLabel[];

const heading = (page: Page, label: TabLabel, name: string) =>
  panel(page, label).getByRole('heading', { name, exact: true });

// @S01 Project settings opens on the Setup tab
//   Given I am an editor on project "Malawi HIV"
//   When I visit "/projects/<project_id>/settings" with no fragment
//   Then the "Setup" tab is selected
//   And I see "Project setup"
//   And no other tab's panel is visible
export async function S01(page: Page, projectId: string) {
  await open(page, settingsPath(projectId));

  await expectSelected(page, 'Setup');
  await expect(heading(page, 'Setup', 'Project setup')).toBeVisible();
  for (const label of LABELS.filter(l => l !== 'Setup'))
    await expect(panel(page, label)).toBeHidden();
}

// @S02 A link to a tab opens that tab
//   Given I am an admin on project "Malawi HIV"
//   When I visit "/projects/<project_id>/settings#data-storage"
//   Then the "Data Storage" tab is selected
//   And I see "Data storage"
//   And the "Setup" panel is not visible
export async function S02(page: Page, projectId: string) {
  await open(page, settingsPath(projectId, 'Data Storage'));

  await expectSelected(page, 'Data Storage');
  await expect(heading(page, 'Data Storage', 'Data storage')).toBeVisible();
  await expect(panel(page, 'Setup')).toBeHidden();
}

// @S03 Choosing a tab puts it in the address bar
//   Given I am on project "Malawi HIV" settings on the "Setup" tab
//   When I click the "Collaboration" tab
//   Then the URL ends in "#collaboration"
//   And I see "Project collaboration"
//   When I reload the page
//   Then the "Collaboration" tab is still selected
export async function S03(page: Page, projectId: string) {
  await openSettings(page, projectId, 'Setup');

  await tab(page, 'Collaboration').click();
  await expect.poll(() => new URL(page.url()).hash).toBe('#collaboration');
  await expect(
    heading(page, 'Collaboration', 'Project collaboration')
  ).toBeVisible();

  await reload(page);
  await expectSelected(page, 'Collaboration');
}

// @S04 The open tab survives a server update
//   Given I am an admin on project "Malawi HIV" settings on the "Data Storage" tab
//   When I change a data storage setting and the page re-renders
//   Then the "Data Storage" tab is still selected
//   And the "Setup" panel is still hidden
export async function S04(page: Page, projectId: string) {
  await openSettings(page, projectId, 'Data Storage');

  await changeDataStorageSetting(page);

  await expectSelected(page, 'Data Storage');
  await expect(panel(page, 'Data Storage')).toBeVisible();
  await expect(panel(page, 'Setup')).toBeHidden();
}

// @S05 Read-only members still see every tab
//   Given I am a viewer on project "Malawi HIV"
//   When I open the project's settings
//   Then I see the tabs "Setup", "Credentials", "Collections", "Webhook Security", "Collaboration", "Security", "Sync to GitHub", "Data Storage" and "History Exports"
//   And none of them is disabled
export async function S05(page: Page, projectId: string) {
  await openSettings(page, projectId);

  for (const label of LABELS) {
    await expect(tab(page, label)).toBeVisible();
    await expect(tab(page, label)).not.toHaveAttribute('aria-disabled', 'true');
    await expect(tab(page, label)).toBeEnabled();
  }
}

// @S06 Members who can't change a tab are told why
//   Given I am a <role> on project "Malawi HIV"
//   When I open the project's settings on the "<tab>" tab
//   Then I see "Role based permissions: You cannot modify this project's <message>"
export async function S06(
  page: Page,
  projectId: string,
  label: TabLabel,
  message: string
) {
  await openSettings(page, projectId, label);

  await expect(roleNotice(panel(page, label))).toContainText(message);
}

// The role notice examples: role, tab, the end of the notice
export const S06_EXAMPLES: ['viewer' | 'editor', TabLabel, string][] = [
  ['viewer', 'Setup', 'basic settings, but you can export a copy.'],
  ['viewer', 'Credentials', 'available credentials.'],
  ['editor', 'Collections', 'available collections.'],
  ['editor', 'Webhook Security', 'webhook auth methods.'],
  [
    'editor',
    'Collaboration',
    'collaboration settings, but you can change your notification preferences.',
  ],
  ['editor', 'Security', 'multi-factor authentication settings.'],
  ['viewer', 'Sync to GitHub', 'version control configuration.'],
  [
    'editor',
    'Sync to GitHub',
    'version control configuration but you can initiate a sync.',
  ],
  ['editor', 'Data Storage', 'data storage settings.'],
];

// @S07 Members who can change a tab see no notice
//   Given I am an admin on project "Malawi HIV"
//   When I open the project's settings
//   Then I do not see "Role based permissions" on any tab
export async function S07(page: Page, projectId: string) {
  await openSettings(page, projectId);
  for (const label of LABELS) {
    await chooseTab(page, label);
    await expect(roleNotice(panel(page, label))).toHaveCount(0);
  }
}

// @S08 Sandbox tabs say whether changes reach the parent
//   Given I am an owner of sandbox "dev" of project "Malawi HIV"
//   When I open the settings of sandbox "dev" on the "<tab>" tab
//   Then I see "<copy>"
export async function S08(
  page: Page,
  sandboxId: string,
  label: TabLabel,
  copy: string
) {
  await openSettings(page, sandboxId, label);

  await expect(panel(page, label).getByText(copy)).toBeVisible();
}

// The sandbox banner examples: tab, the copy it shows
const LOCAL =
  'Changes you make here only apply to this sandbox and do not sync to the parent project on merge.';
const MERGED =
  'Changes you make here will sync to the parent project on merge.';
export const S08_EXAMPLES: [TabLabel, string][] = [
  ['Setup', LOCAL],
  ['Collaboration', LOCAL],
  ['Sync to GitHub', LOCAL],
  ['Data Storage', LOCAL],
  ['History Exports', LOCAL],
  ['Credentials', MERGED],
  ['Collections', MERGED],
];

// @S09 Inherited settings point to the parent that owns them
//   Given I am an owner of sandbox "dev" of project "Malawi HIV"
//   When I open the settings of sandbox "dev" on the "Security" tab
//   Then I see "These settings are inherited from the parent project (Malawi HIV) and cannot be changed here."
//   And "Malawi HIV" links to "/projects/<parent_id>/settings"
export async function S09(
  page: Page,
  sandboxId: string,
  parent: { id: string; name: string }
) {
  await openSettings(page, sandboxId, 'Security');

  const security = panel(page, 'Security');
  await expect(security).toContainText(
    `These settings are inherited from the parent project (${parent.name}) and cannot be changed here.`
  );
  await expect(
    security.getByRole('link', { name: parent.name, exact: true })
  ).toHaveAttribute('href', settingsPath(parent.id));
}

// @S10 A project that isn't a sandbox shows no sandbox banner
//   Given I am an owner of project "Malawi HIV", which has no parent
//   When I open the project's settings
//   Then I see no sandbox banner on any tab
export async function S10(page: Page, projectId: string) {
  await openSettings(page, projectId);
  for (const label of LABELS) {
    await chooseTab(page, label);
    await expect(sandboxBanner(panel(page, label))).toHaveCount(0);
  }
}
