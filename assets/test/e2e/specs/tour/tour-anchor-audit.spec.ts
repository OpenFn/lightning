import { readFileSync } from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

import { test, expect, type Page } from '@playwright/test';

import { enableExperimentalFeatures } from '../../e2e-helper';
import {
  LoginPage,
  ProjectsPage,
  WorkflowCollaborativePage,
  WorkflowsPage,
} from '../../pages';
import { WorkflowDiagramPage } from '../../pages/components/workflow-diagram.page';
import { getTestData } from '../../test-data';

/**
 * Guided-tour DOM contract audit
 *
 * The tour planner (assets/js/tour/plan.ts) turns priv/app_map.json into
 * selectors it expects to find in the DOM:
 *
 * - `#side-menu a[href="<resolved sidebar path>"]` for project-section pages
 * - `#user-menu-trigger`, then `[role="menu"] a[href="<path>"]` for
 *   user-section pages
 * - `#<hash>-tab` for every tab on a tabbed page
 * - `[data-tour-anchor="<id>"]` for every element spotlight
 *
 * Nothing else ties the app map to the markup, so an anchor can rot silently.
 * This spec is the tripwire: pure existence assertions, driven by the app map
 * read from disk, performing only the preconditions each anchor documents
 * (its `hint` in the app map). It deliberately does not exercise tour
 * behaviour — see assets/test/tour/ for that.
 */

// --- App map, read from priv/app_map.json at the repo root ----------------

/** Shapes mirror AppMapPage/AppMapTab/AppMapElement in assets/js/tour/plan.ts. */
interface AppMapTab {
  hash: string;
  label: string;
}

interface AppMapElement {
  id: string;
  label: string;
  hint?: string | null;
  /** Id of the element that must be acted on before this one is on screen. */
  requires?: string | null;
}

interface AppMapPage {
  id: string;
  path: string;
  label: string;
  section: 'project' | 'user' | 'admin' | 'auth';
  tabs?: AppMapTab[];
  elements?: AppMapElement[];
}

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../../..'
);

const appMap = JSON.parse(
  readFileSync(path.join(repoRoot, 'priv', 'app_map.json'), 'utf-8')
) as AppMapPage[];

function appMapPage(id: string): AppMapPage {
  const page = appMap.find(p => p.id === id);
  if (!page) throw new Error(`app_map.json has no page with id "${id}"`);
  return page;
}

// --- Contract constants, mirroring assets/js/tour/plan.ts -----------------

/**
 * Sidebar-linkable project pages, keyed by the path suffix after
 * `/projects/:project_id`. Mirrors SIDEBAR_PATH_SUFFIXES in plan.ts, which in
 * turn mirrors lib/lightning_web/live/components/menu.ex.
 */
const SIDEBAR_PATH_SUFFIXES = [
  '/w',
  '/channels',
  '/sandboxes',
  '/history',
  '/settings',
];

/**
 * Sidebar entries that only render under a per-user gate, so their absence is
 * not anchor rot. `/channels` is behind the experimental-features flag
 * (menu.ex `project_items`); the planner falls back to direct navigation when
 * a sidebar link is missing, so a soft assertion is the honest check.
 */
const GATED_SIDEBAR_SUFFIXES = new Set(['/channels']);

/** Mirrors USER_MENU_PATHS in plan.ts (the user-menu dropdown hrefs). */
const USER_MENU_PATHS = [
  '/projects',
  '/profile',
  '/credentials',
  '/profile/tokens',
];

function tourAnchor(page: Page, id: string) {
  return page.locator(`[data-tour-anchor="${id}"]`);
}

/**
 * Existence audit for one anchor: at least one visible match. Not exactly
 * one — the runner's findAnchor (assets/js/tour/runner.ts) takes the first
 * *visible* match on purpose, because anchors like canvas-step sit on every
 * job node.
 */
async function expectAnchor(page: Page, id: string): Promise<void> {
  const visible = tourAnchor(page, id).filter({ visible: true });
  await expect(
    visible.first(),
    `a visible [data-tour-anchor="${id}"] should exist`
  ).toBeVisible();
}

test.describe('Guided tour DOM contract @tour', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test('project sidebar and user menu carry the tour navigation hooks', async ({
    page,
  }) => {
    const workflowsPage = new WorkflowsPage(page);
    const projectId = testData.projects.openhie.id;

    await test.step('Log in and open the project workflows page', async () => {
      await page.goto('/');
      const loginPage = new LoginPage(page);
      await loginPage.loginIfNeeded(
        testData.users.admin.email,
        testData.users.admin.password
      );
      await page.goto(`/projects/${projectId}/w`);
      await workflowsPage.waitForConnected();
    });

    const sideMenu = page.locator('#side-menu');

    await test.step('#side-menu exists', async () => {
      await expect(sideMenu).toBeVisible();
    });

    // Every project-section app-map page whose path is exactly
    // `/projects/:project_id<suffix>` for a sidebar suffix must have a
    // sidebar link the planner can spotlight.
    const sidebarPages = appMap.filter(
      p =>
        p.section === 'project' &&
        SIDEBAR_PATH_SUFFIXES.some(
          suffix => p.path === `/projects/:project_id${suffix}`
        )
    );
    expect(sidebarPages.length).toBeGreaterThan(0);

    for (const sidebarPage of sidebarPages) {
      const suffix = sidebarPage.path.replace('/projects/:project_id', '');
      const href = `/projects/${projectId}${suffix}`;

      await test.step(`#side-menu links to ${href} (${sidebarPage.label})`, async () => {
        const link = sideMenu.locator(`a[href="${href}"]`);

        if (GATED_SIDEBAR_SUFFIXES.has(suffix) && (await link.count()) === 0) {
          test.info().annotations.push({
            type: 'note',
            description:
              `Sidebar link ${href} absent: gated behind the per-user ` +
              'experimental-features flag (menu.ex project_items). The tour ' +
              'planner falls back to direct navigation for missing sidebar ' +
              'entries, so this is not anchor rot.',
          });
          return;
        }

        await expect(link).toBeVisible();
      });
    }

    await test.step('#user-menu-trigger opens a [role="menu"] with the user-section links', async () => {
      const trigger = page.locator('#user-menu-trigger');
      await expect(trigger).toBeVisible();
      await trigger.click();

      const menu = page.locator('[role="menu"]');
      await expect(menu).toBeVisible();

      // Every user-section app-map page reachable from the user menu must
      // have a link in it. `.first()` because the experimental-features
      // notice adds a second /profile link when that flag is on.
      const userMenuPages = appMap.filter(
        p => p.section === 'user' && USER_MENU_PATHS.includes(p.path)
      );
      expect(userMenuPages.length).toBeGreaterThan(0);

      for (const userPage of userMenuPages) {
        const link = menu.locator(`a[href="${userPage.path}"]`);
        await expect(
          link.first(),
          `[role="menu"] should link to ${userPage.path} (${userPage.label})`
        ).toBeVisible();
      }
    });
  });

  test('project settings renders a #<hash>-tab for every app-map tab', async ({
    page,
  }) => {
    const projectsPage = new ProjectsPage(page);
    const projectId = testData.projects.openhie.id;
    const settingsEntry = appMapPage('project_settings');
    const tabs = settingsEntry.tabs ?? [];
    expect(tabs.length).toBeGreaterThan(0);

    await test.step('Log in as admin and open project settings', async () => {
      await page.goto('/');
      const loginPage = new LoginPage(page);
      await loginPage.loginIfNeeded(
        testData.users.admin.email,
        testData.users.admin.password
      );
      await page.goto(`/projects/${projectId}/settings`);
      await projectsPage.waitForConnected();
    });

    // All nine tabs render unconditionally for a project admin
    // (settings.html.heex has no :if on any <:tab>), so assert hard.
    for (const tab of tabs) {
      await test.step(`#${tab.hash}-tab exists (${tab.label})`, async () => {
        await expect(page.locator(`#${tab.hash}-tab`)).toBeVisible();
      });
    }
  });

  test('workflow editor renders a data-tour-anchor for every app-map element', async ({
    page,
  }) => {
    const workflowEdit = appMapPage('workflow_edit');
    const elements = workflowEdit.elements ?? [];
    expect(elements.length).toBeGreaterThan(0);

    // Elements grouped by the anchor their `requires` field names. The audit
    // satisfies each precondition the way the tour does: by acting on the
    // required anchor itself.
    const requiring = (req: string | null) =>
      elements.filter(e => (e.requires ?? null) === req).map(e => e.id);

    await test.step('The audit covers the app map exactly', () => {
      // Tripwire: an element whose `requires` names an anchor this audit does
      // not know how to activate fails here, before anything loads.
      const handledPreconditions = [
        null,
        'settings-panel-toggle',
        'canvas-step',
        'open-editor',
      ];
      const unhandled = elements.filter(
        e => !handledPreconditions.includes(e.requires ?? null)
      );
      expect(
        unhandled.map(e => `${e.id} (requires ${String(e.requires)})`)
      ).toEqual([]);
    });

    const collabEditor = new WorkflowCollaborativePage(page);
    const diagram = new WorkflowDiagramPage(page);

    await test.step('Log in and open the collaborative editor', async () => {
      // Per-user precondition for collaborative specs — see
      // .claude/guidelines/e2e/collaborative-testing.md.
      await enableExperimentalFeatures(testData.users.editor.email);

      await page.goto('/');
      const loginPage = new LoginPage(page);
      await loginPage.loginIfNeeded(
        testData.users.editor.email,
        testData.users.editor.password
      );

      // Not WorkflowCollaborativePage.open(): its waitForSynced() gate waits
      // for `text=Synced`, which nothing renders (collaborative-testing.md
      // §Two things that will stop you before you start). The diagram
      // appearing is the real "workflow data loaded" signal.
      await page.goto(
        `/projects/${testData.projects.openhie.id}/w/${testData.workflows.openhie.id}`
      );
      await collabEditor.waitForReactComponentLoaded();
      await diagram.verifyReactFlowPresent();
    });

    await test.step('Anchors visible on editor load (no `requires`)', async () => {
      for (const id of requiring(null)) {
        await expectAnchor(page, id);
      }
    });

    await test.step('Anchors requiring settings-panel-toggle (workflow settings panel)', async () => {
      await tourAnchor(page, 'settings-panel-toggle').click();
      for (const id of requiring('settings-panel-toggle')) {
        await expectAnchor(page, id);
      }
      // Toggle closed again so the canvas is back in charge.
      await tourAnchor(page, 'settings-panel-toggle').click();
      await expect(tourAnchor(page, 'code-panel-toggle')).toHaveCount(0);
    });

    await test.step('Anchors requiring canvas-step (job inspector)', async () => {
      // Act on the precondition anchor itself: click a step on the canvas,
      // which opens its configuration panel.
      await tourAnchor(page, 'canvas-step')
        .filter({ visible: true })
        .first()
        .click();
      await collabEditor.jobInspector.waitForVisible();
      for (const id of requiring('canvas-step')) {
        await expectAnchor(page, id);
      }
    });

    await test.step('Anchors requiring open-editor (full-screen code editor)', async () => {
      // Act on the open-editor anchor (the inspector's Code button) to reach
      // the full-screen IDE.
      await tourAnchor(page, 'open-editor').click();
      for (const id of requiring('open-editor')) {
        await expectAnchor(page, id);
      }
    });
  });
});
