// Scenarios from annotations/shared/shared-project-header.md
// that reach a page without a project: the global picker, the role menu and
// the account menu. Each opens `path` itself.
import { expect, type Page } from '@playwright/test';

import {
  exec,
  expectAt,
  experimentalSwitch,
  extraProjectFor,
  makeSupportUser,
  open,
  preferencesOf,
  seedProject,
  setPreferences,
  signInAs,
  sql,
  user,
} from '../steps';

const OWNER = 'owner@openfn.org';
// A seeded user who is not the caller, so "other members only" holds
const otherThan = (email: string) =>
  email === OWNER ? 'super@openfn.org' : OWNER;

// When I open the project picker
async function openPicker(page: Page) {
  await page.keyboard.press('ControlOrMeta+p');
  await expect(picker(page)).toBeFocused();
}

const option = (page: Page, name: string) =>
  page.getByRole('option', { name, exact: true });

// A nested option carries a turn-down arrow in front of its icon
const arrow = (page: Page, name: string) =>
  option(page, name).locator('[class*="hero-arrow-turn-down-right"]');

// Given project "<name>" is a sandbox of <parent>
function sandboxOf(
  parent: { id: string },
  name: string,
  members: Parameters<typeof seedProject>[1]
) {
  const child = seedProject(name, members);
  exec(
    `update projects set parent_id = '${parent.id}' where id = '${child.id}'`
  );
  return child;
}

const picker = (page: Page) =>
  page.getByRole('combobox', { name: 'Search projects...' });

// The option the picker highlights. The highlight has no ARIA state (no
// aria-activedescendant; aria-selected marks the current project), so it is
// the one option painted with a background.
async function highlightedOption(page: Page) {
  await page.mouse.move(0, 0); // hovering an option highlights it too
  const painted = () =>
    page
      .getByRole('listbox')
      .getByRole('option')
      .evaluateAll(options =>
        options
          .filter(
            o => getComputedStyle(o).backgroundColor !== 'rgba(0, 0, 0, 0)'
          )
          .map(o => o.textContent!.trim())
      );
  await expect.poll(painted).toHaveLength(1);
  return (await painted())[0];
}

// @S11 The picker opens from the keyboard
//   Given I am on any page in the live layout
//   When I press Ctrl+P, or Cmd+P on a Mac
//   Then the project picker opens with the search box focused
//   When I press the down arrow and Enter
//   Then I am taken to the highlighted project
export async function S11(page: Page, path: string, email: string) {
  // The picker opens on the first project; a second one gives the down arrow
  // a project to move to rather than wrapping round to "View all projects".
  const second = extraProjectFor(email, 'zz-scenario-second-project');
  try {
    await pickWithKeyboard(page, path, email);
  } finally {
    second.remove();
  }
}

async function pickWithKeyboard(page: Page, path: string, email: string) {
  await signInAs(page, email);
  await open(page, path);

  await page.keyboard.press('ControlOrMeta+p');
  await expect(picker(page)).toBeFocused();

  await page.keyboard.press('ArrowDown');
  const highlighted = await highlightedOption(page);
  const [project] = sql<{ id: string }>(
    `select p.id from projects p join project_users pu on pu.project_id = p.id
     where pu.user_id = '${user(email).id}' and p.name = $n$${highlighted}$n$`
  );
  expect(project, `"${highlighted}" should be one of my projects`).toBeTruthy();
  await page.keyboard.press('Enter');

  await expectAt(page, new RegExp(`^/projects/${project.id}(/|$)`));
}

// @S10 Switching from a page that has no equivalent lands on one that does
//   Given I am a member of "Kenya TB"
//   And I am on <page>
//   When I pick "Kenya TB" in the project picker
//   Then I am on <landing> of "Kenya TB"
// One Examples row: <page> is `path`, <landing> the project path `landing`
// (for example "/w", the workflows page).
export async function S10(
  page: Page,
  path: string,
  email: string,
  landing: string
) {
  const kenya = extraProjectFor(email, 'Kenya TB');
  try {
    await signInAs(page, email);
    await open(page, path);

    await page.keyboard.press('ControlOrMeta+p');
    await picker(page).fill('Kenya TB');
    await page.getByRole('option', { name: 'Kenya TB' }).click();

    await expectAt(page, `/projects/${kenya.id}${landing}`);
  } finally {
    kenya.remove();
  }
}

// @S12 The picker leads to the full projects list
//   When I open the project picker
//   And I choose "View all projects"
//   Then I am on "/projects"
export async function S12(page: Page, path: string, email: string) {
  await signInAs(page, email);
  await open(page, path);

  await page.keyboard.press('ControlOrMeta+p');
  await page.getByRole('option', { name: 'View all projects' }).click();

  await expectAt(page, '/projects');
}

// @S13 Confirmed users and non-verifying instances show no confirmation banner
//   Given my email is confirmed, or the instance does not require email verification
//   When I open any page with the header
//   Then I do not see the account confirmation banner
export async function S13(page: Page, path: string, email: string) {
  const [{ confirmed }] = sql<{ confirmed: boolean }>(
    `select confirmed_at is not null as confirmed from users where id = '${user(email).id}'`
  );
  expect(confirmed, `${email} should be confirmed`).toBe(true);
  await signInAs(page, email);

  await open(page, path);

  await expect(page.getByText('Please confirm your account')).toHaveCount(0);
  await expect(
    page.getByRole('link', { name: 'Resend confirmation email' })
  ).toHaveCount(0);
}

// @S17 Superusers reach administration; everyone else reaches help
//   Given I am a superuser
//   When I open <path>
//   Then the side menu shows "Admin Menu" linking to "/settings/projects" and "Sys Info" linking to "/dashboard"
//   Given I am an editor who is not a superuser
//   When I open <path>
//   Then the side menu shows "Documentation", "Community" and "Support"
export async function S17(page: Page, path: string) {
  await signInAs(page, 'super@openfn.org');
  await open(page, path);
  const menu = page.getByRole('navigation');
  await expect(menu.getByRole('link', { name: 'Admin Menu' })).toHaveAttribute(
    'href',
    '/settings/projects'
  );
  await expect(menu.getByRole('link', { name: 'Sys Info' })).toHaveAttribute(
    'href',
    '/dashboard'
  );

  await page.context().clearCookies();
  await signInAs(page, 'editor@openfn.org');
  await open(page, path);
  for (const name of ['Documentation', 'Community', 'Support'])
    await expect(menu.getByRole('link', { name })).toBeVisible();
  await expect(menu.getByRole('link', { name: 'Admin Menu' })).toHaveCount(0);
}

// @S18 The account menu shows who I am and where my account settings are
//   Given I am signed in as "<email>"
//   When I open the account menu
//   Then I see "Signed in as" and "<email>"
//   And I see "Projects", "User Profile", "Credentials", "API Tokens" and "Log out"
export async function S18(page: Page, path: string, email: string) {
  const [{ name }] = sql<{ name: string }>(
    `select first_name || ' ' || last_name as name from users where id = '${user(email).id}'`
  );
  await signInAs(page, email);
  await open(page, path);

  await page.getByRole('button', { name: new RegExp(`${name}$`) }).click();

  const menu = page.getByRole('menu');
  await expect(menu.getByText('Signed in as')).toBeVisible();
  await expect(
    menu.getByText(user(email).email, { exact: true })
  ).toBeVisible();
  for (const name of [
    'Projects',
    'User Profile',
    'Credentials',
    'API Tokens',
    'Log out',
  ])
    await expect(menu.getByRole('menuitem', { name })).toBeVisible();
}

// @S04 The picker lists only projects I can reach, with the current one marked
//   Given I am a member of "project-1" and "project-2"
//   And "project-3" exists with other members only
//   When I open "project-1" and open the project picker
//   Then I see "project-1" marked as current and "project-2"
//   And I do not see "project-3"
// On a page without a project nothing is current, so only the lists are checked.
export async function S04(page: Page, path: string, email: string) {
  const OTHER = otherThan(email);
  const one = seedProject('project-1', { [email]: 'editor' });
  const two = seedProject('project-2', { [email]: 'editor' });
  const three = seedProject('project-3', { [OTHER]: 'owner' });
  try {
    await signInAs(page, email);
    await open(page, path);
    await openPicker(page);

    await expect(option(page, 'project-1')).toBeVisible();
    await expect(option(page, 'project-2')).toBeVisible();
    await expect(option(page, 'project-3')).toHaveCount(0);
  } finally {
    for (const p of [one, two, three]) p.remove();
  }
}

// @S05 Sandboxes nest under the nearest project I can see
//   Given project "Malawi HIV" has sandbox "dev", which has sandbox "feature"
//   And I am a member of "Malawi HIV" and "feature" but not "dev"
//   When I open the project picker
//   Then "feature" is listed directly under "Malawi HIV"
//   And "dev" is not listed
//   And if I am a member of "feature" only, "feature" is listed at the top level
export async function S05(page: Page, path: string, email: string) {
  const OTHER = otherThan(email);
  const malawi = seedProject('Malawi HIV', {
    [email]: 'editor',
    [OTHER]: 'owner',
  });
  const dev = sandboxOf(malawi, 'dev', { [OTHER]: 'owner' });
  const feature = sandboxOf(dev, 'feature', { [email]: 'editor' });
  try {
    await signInAs(page, email);
    await open(page, path);
    await openPicker(page);

    await expect(option(page, 'Malawi HIV')).toBeVisible();
    await expect(option(page, 'feature')).toBeVisible();
    await expect(arrow(page, 'feature')).toBeVisible();
    await expect(option(page, 'dev')).toHaveCount(0);

    exec(`delete from project_users where project_id = '${malawi.id}'
            and user_id = '${user(email).id}'`);
    await open(page, path);
    await openPicker(page);

    await expect(option(page, 'Malawi HIV')).toHaveCount(0);
    await expect(option(page, 'feature')).toBeVisible();
    await expect(arrow(page, 'feature')).toHaveCount(0);
  } finally {
    for (const p of [feature, dev, malawi]) p.remove();
  }
}

// @S06 Projects scheduled for deletion are not offered
//   Given I am a member of "Malawi HIV" and "Old pilot"
//   And "Old pilot" is scheduled for deletion
//   When I open the project picker
//   Then I do not see "Old pilot"
export async function S06(page: Page, path: string, email: string) {
  const malawi = seedProject('Malawi HIV', { [email]: 'editor' });
  const old = seedProject('Old pilot', { [email]: 'editor' });
  exec(`update projects set scheduled_deletion = now() + interval '7 days'
        where id = '${old.id}'`);
  try {
    await signInAs(page, email);
    await open(page, path);
    await openPicker(page);

    await expect(option(page, 'Malawi HIV')).toBeVisible();
    await expect(option(page, 'Old pilot')).toHaveCount(0);
  } finally {
    old.remove();
    malawi.remove();
  }
}

// @S07 Support users see projects that allow support access
//   Given I am a support user with no role on project "Malawi HIV"
//   And "Malawi HIV" allows support access
//   When I open the project picker
//   Then I see "Malawi HIV"
export async function S07(page: Page, path: string, email: string) {
  const OTHER = otherThan(email);
  const restore = makeSupportUser(email);
  const malawi = seedProject(
    'Malawi HIV',
    { [OTHER]: 'owner' },
    { allowSupportAccess: true }
  );
  const closed = seedProject('Kenya TB', { [OTHER]: 'owner' });
  try {
    await signInAs(page, email);
    await open(page, path);
    await openPicker(page);

    await expect(option(page, 'Malawi HIV')).toBeVisible();
    await expect(option(page, 'Kenya TB')).toHaveCount(0);
  } finally {
    closed.remove();
    malawi.remove();
    restore();
  }
}

// @S08 Searching matches the full path and keeps parents in view
//   Given I can reach "Malawi HIV" with sandbox "dev" and "Kenya TB" with sandbox "dev"
//   When I open the project picker and type "hiv/d"
//   Then I see "Malawi HIV" and its "dev"
//   And I do not see "Kenya TB"
export async function S08(page: Page, path: string, email: string) {
  const malawi = seedProject('Malawi HIV', { [email]: 'editor' });
  const malawiDev = sandboxOf(malawi, 'dev', { [email]: 'editor' });
  const kenya = seedProject('Kenya TB', { [email]: 'editor' });
  const kenyaDev = sandboxOf(kenya, 'dev', { [email]: 'editor' });
  try {
    await signInAs(page, email);
    await open(page, path);
    await openPicker(page);

    await picker(page).fill('hiv/d');

    await expect(option(page, 'Malawi HIV')).toBeVisible();
    await expect(option(page, 'dev')).toHaveCount(1);
    await expect(arrow(page, 'dev')).toBeVisible();
    await expect(option(page, 'Kenya TB')).toHaveCount(0);
  } finally {
    for (const p of [kenyaDev, malawiDev, kenya, malawi]) p.remove();
  }
}

// @S09 Switching project keeps me in the same section and tab
//   Given I am a member of "Malawi HIV" and "Kenya TB"
//   And I am on the collaborators tab of "Malawi HIV" settings
//   When I pick "Kenya TB" in the project picker
//   Then I am on the collaborators tab of "Kenya TB" settings
// Starts on a project settings page, whatever page the host is.
export async function S09(page: Page, email: string) {
  const malawi = seedProject('Malawi HIV', { [email]: 'owner' });
  const kenya = seedProject('Kenya TB', { [email]: 'owner' });
  try {
    await signInAs(page, email);
    await open(page, `/projects/${malawi.id}/settings#collaborators`);

    await openPicker(page);
    await option(page, 'Kenya TB').click();

    await expectAt(page, `/projects/${kenya.id}/settings`);
    await expect.poll(() => new URL(page.url()).hash).toBe('#collaborators');
  } finally {
    kenya.remove();
    malawi.remove();
  }
}

// @S02 The picker button names the current project
//   Given I am an editor on project "Malawi HIV"
//   When I open the project's workflows page
//   Then the project picker button reads "Malawi HIV"
export async function S02(
  page: Page,
  email: string,
  at?: { path: string; project: string }
) {
  if (at) {
    // A host page that is itself under the project
    await signInAs(page, email);
    await open(page, at.path);
    await expect(
      page.getByRole('button', { name: at.project, exact: true })
    ).toBeVisible();
    return;
  }
  const malawi = seedProject('Malawi HIV', { [email]: 'editor' });
  try {
    await signInAs(page, email);
    await open(page, `/projects/${malawi.id}/w`);

    await expect(
      page.getByRole('button', { name: 'Malawi HIV', exact: true })
    ).toBeVisible();
  } finally {
    malawi.remove();
  }
}

// @S03 A sandbox is labelled and coloured as a sandbox
//   Given project "Malawi HIV" has a sandbox "dev" with colour "#E33D63"
//   And I am an editor on both
//   When I open the workflows page of sandbox "dev"
//   Then the picker button reads "Malawi HIV:dev" on a "#E33D63" background with a beaker icon
// The beaker has no text of its own, so the label and colour carry the check.
export async function S03(
  page: Page,
  email: string,
  at?: { path: string; label: string }
) {
  if (at) {
    // A host page that is itself under the sandbox "dev" coloured "#E33D63"
    await signInAs(page, email);
    await open(page, at.path);
    const button = page.getByRole('button', { name: at.label });
    await expect(button).toBeVisible();
    await expect(button).toHaveCSS('background-color', 'rgb(227, 61, 99)');
    return;
  }
  const malawi = seedProject('Malawi HIV', { [email]: 'editor' });
  const dev = sandboxOf(malawi, 'dev', { [email]: 'editor' });
  exec(`update projects set color = '#E33D63' where id = '${dev.id}'`);
  try {
    await signInAs(page, email);
    await open(page, `/projects/${dev.id}/w`);

    const button = page.getByRole('button', { name: 'Malawi HIV:dev' });
    await expect(button).toBeVisible();
    await expect(button).toHaveCSS('background-color', 'rgb(227, 61, 99)');
  } finally {
    dev.remove();
    malawi.remove();
  }
}

// The experimental-mode indicators S16 looks for: the side menu's
// "Experimental" (and "Channels" on a project page) and, in the account menu,
// "Experimental features on" with its link back to the profile. Opens the
// account menu. S16 and profile-experimental-features S06 both use it.
export async function experimentalIndicators(
  page: Page,
  email: string,
  shown: boolean,
  channels = false
) {
  const [{ name }] = sql<{ name: string }>(
    `select first_name || ' ' || last_name as name from users where id = '${user(email).id}'`
  );
  const menu = page.getByRole('navigation');
  const accountMenu = page.getByRole('menu');
  await page.getByRole('button', { name: new RegExp(`${name}$`) }).click();
  const exp = expect.configure({ timeout: shown ? 5000 : 2000 });
  const count = shown ? 1 : 0;
  await exp(menu.getByText('Experimental', { exact: true })).toHaveCount(count);
  if (channels)
    await exp(menu.getByRole('link', { name: 'Channels' })).toHaveCount(count);
  await exp(accountMenu.getByText('Experimental features on')).toHaveCount(
    count
  );
  await exp(
    page.getByRole('link', { name: 'Turn off in your profile' })
  ).toHaveCount(count);
}

// @S16 Experimental features add Channels and say so
//   Given I have experimental features turned on
//   When I open <path>
//   Then the side menu shows "Experimental" (and "Channels" on a project page)
//   And the account menu says "Experimental features on" with a link "Turn off in your profile"
//   When I turn experimental features off
//   Then none of these appear
export async function S16(
  page: Page,
  path: string,
  email: string,
  { channels = false }: { channels?: boolean } = {}
) {
  const indicators = (shown: boolean) =>
    experimentalIndicators(page, email, shown, channels);

  await signInAs(page, email);
  setPreferences(email, { experimental_features: true });
  await open(page, path);
  await indicators(true);

  await page.getByRole('link', { name: 'Turn off in your profile' }).click();
  await expectAt(page, '/profile');
  await page.locator('.phx-connected').first().waitFor();
  await experimentalSwitch(page).click();
  await expect
    .poll(() => preferencesOf(email).experimental_features)
    .toBe(false);

  // The page's own menus keep the old state until it is reloaded
  await open(page, path);
  await indicators(false);
}

// @S01 Breadcrumbs show where I am and link back up
//   Given I am an editor on project "Malawi HIV"
//   When I open <path>
//   Then the breadcrumbs show the project picker, then <crumbs>
//   And the last crumb is not a link
// `crumbs` are the crumbs after the picker, each with its link; the last has
// none. The picker names the project.
export async function S01(
  page: Page,
  path: string,
  email: string,
  project: string,
  crumbs: { name: string; href?: string }[]
) {
  expect(crumbs[crumbs.length - 1].href, 'the last crumb is no link').toBe(
    undefined
  );
  await signInAs(page, email);
  await open(page, path);

  const trail = page.getByRole('navigation', { name: 'Breadcrumbs' });
  await expect(
    trail.getByRole('button', { name: project, exact: true })
  ).toBeVisible();
  await expect
    .poll(async () =>
      (await trail.getByRole('listitem').allInnerTexts())
        .map(text => text.trim())
        .slice(-crumbs.length)
    )
    .toEqual(crumbs.map(crumb => crumb.name));
  for (const { name, href } of crumbs) {
    const link = trail.getByRole('link', { name, exact: true });
    if (href) await expect(link).toHaveAttribute('href', href);
    else await expect(link).toHaveCount(0);
  }
}

// @S15 The side menu leads to each area of the project and marks the current one
//   Given I am a viewer on project "Malawi HIV"
//   When I open <path>
//   Then the side menu shows "Workflows", "Sandboxes", "History" and "Settings" for "Malawi HIV"
//   And <current> is marked as current
export async function S15(
  page: Page,
  path: string,
  email: string,
  projectId: string,
  current: string
) {
  await signInAs(page, email);
  await open(page, path);

  // The side menu is the navigation that holds "Sandboxes"
  const menu = page
    .getByRole('navigation')
    .filter({ has: page.getByRole('link', { name: 'Sandboxes' }) });
  const areas = {
    Workflows: `/projects/${projectId}/w`,
    Sandboxes: `/projects/${projectId}/sandboxes`,
    History: `/projects/${projectId}/history`,
    Settings: `/projects/${projectId}/settings`,
  };
  for (const [name, href] of Object.entries(areas)) {
    const link = menu.getByRole('link', { name, exact: true });
    await expect(link).toHaveAttribute('href', href);
    if (name === current)
      await expect(link).toHaveAttribute('aria-current', 'page');
    else await expect(link).not.toHaveAttribute('aria-current', 'page');
  }
}
