import { test, expect } from '@playwright/test';
import { getTestData } from '../../test-data';
import { enableExperimentalFeatures } from '../../e2e-helper';
import {
  LoginPage,
  ProjectsPage,
  WorkflowsPage,
  WorkflowEditPage,
  WorkflowCollaborativePage,
} from '../../pages';

/**
 * Test suite for navigating to the collaborative editor via the beaker icon.
 *
 * The beaker icon appears when:
 * 1. User has experimental features enabled
 * 2. Workflow has a snapshot with lock_version matching the current workflow lock_version
 *
 * Demo data automatically creates snapshots through Workflows.save_workflow/3 and
 * subsequent calls to Jobs.create_job/2 and Workflows.create_edge/2.
 */

test.describe('Collaborative Editor Navigation', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test.beforeEach(async ({ page }) => {
    // Enable experimental features for the editor user
    // Must be done in beforeEach because global setup resets DB
    await enableExperimentalFeatures(testData.users.editor.email);

    // Login as editor user
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );
  });

  test('navigate to collaborative editor via beaker icon @collaborative @smoke', async ({
    page,
  }) => {
    await test.step('Navigate to project', async () => {
      const projectsPage = new ProjectsPage(page);
      await projectsPage.navigateToProject(testData.projects.openhie.name);
    });

    await test.step('Navigate to workflow', async () => {
      const workflowsPage = new WorkflowsPage(page);

      // Use POM method which handles waitForEventAttached
      await workflowsPage.navigateToWorkflow(testData.workflows.openhie.name);

      // Wait for LiveView connection on edit page
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.waitForConnected();
    });

    await test.step('Verify beaker icon is visible', async () => {
      // Beaker icon requires: experimental features + latest snapshot
      const beakerIcon = page.locator(
        'a[aria-label="Switch to collaborative editor (experimental)"]'
      );
      await expect(beakerIcon).toBeVisible({ timeout: 10000 });
    });

    await test.step('Click beaker icon to open collaborative editor', async () => {
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.clickCollaborativeEditorToggle();
    });

    await test.step('Verify collaborative editor loads', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      // Verify URL changed correctly
      await collabEditor.verifyUrl({
        projectId: testData.projects.openhie.id,
        workflowId: testData.workflows.openhie.id,
        path: '/collaborate',
      });

      // Wait for React component to mount
      await collabEditor.waitForReactComponentLoaded();

      // Verify main container is visible
      await expect(collabEditor.container).toBeVisible();

      // Wait for sync status (collaborative features working)
      await collabEditor.waitForSynced();

      // Verify no errors displayed
      await collabEditor.verifyNoErrors();
    });
  });
});
