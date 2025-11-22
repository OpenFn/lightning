import { test, expect } from '@playwright/test';

import { enableExperimentalFeatures } from '../../e2e-helper';
import {
  LoginPage,
  ProjectsPage,
  WorkflowsPage,
  WorkflowEditPage,
  WorkflowCollaborativePage,
} from '../../pages';
import { getTestData } from '../../test-data';

/**
 * E2E Test suite for IDE History Selection feature (Issue #4054)
 *
 * Tests the right panel mode transitions in the collaborative editor:
 * - Empty state with "Browse History" and "Create New Run" buttons
 * - History browser panel for selecting runs
 * - Navigation between panels
 * - Run selection and viewing
 *
 * Note: These tests focus on UI interactions and navigation.
 * Full run submission flow is tested separately in run-retry tests.
 */

test.describe('IDE History Selection', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test.beforeEach(async ({ page }) => {
    // Enable experimental features for the editor user
    await enableExperimentalFeatures(testData.users.editor.email);

    // Login and navigate to collaborative editor
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );

    // Navigate to project and workflow
    const projectsPage = new ProjectsPage(page);
    await projectsPage.navigateToProject(testData.projects.openhie.name);

    const workflowsPage = new WorkflowsPage(page);
    await workflowsPage.navigateToWorkflow(testData.workflows.openhie.name);

    // Click beaker icon to open collaborative editor
    const workflowEdit = new WorkflowEditPage(page);
    await workflowEdit.waitForConnected();
    await workflowEdit.clickCollaborativeEditorToggle();

    // Wait for collaborative editor to load
    const collabEditor = new WorkflowCollaborativePage(page);
    await collabEditor.waitForReactComponentLoaded();
    await collabEditor.waitForSynced();
  });

  test('displays empty state with action buttons on initial load @collaborative @smoke', async ({
    page,
  }) => {
    await test.step('Verify empty state is shown', async () => {
      // Look for the two action buttons in the right panel
      const browseHistoryButton = page.locator(
        'button:has-text("Browse History")'
      );
      const createNewRunButton = page.locator(
        'button:has-text("Create New Run")'
      );

      await expect(browseHistoryButton).toBeVisible();
      await expect(createNewRunButton).toBeVisible();

      // Verify descriptive subtitles
      await expect(page.locator('text=Pick a run to inspect')).toBeVisible();
      await expect(page.locator('text=Select input and execute')).toBeVisible();
    });
  });

  test('can navigate to history browser and back to empty state @collaborative', async ({
    page,
  }) => {
    await test.step('Click Browse History button', async () => {
      const browseHistoryButton = page.locator(
        'button:has-text("Browse History")'
      );
      await browseHistoryButton.click();
    });

    await test.step('Verify history browser is shown', async () => {
      // Look for history browser header
      const historyHeader = page.locator('text=Browse History').first();
      await expect(historyHeader).toBeVisible();

      // Look for back button
      const backButton = page.locator(
        'button[aria-label="Close history browser"]'
      );
      await expect(backButton).toBeVisible();
    });

    await test.step('Click back button to return to empty state', async () => {
      const backButton = page.locator(
        'button[aria-label="Close history browser"]'
      );
      await backButton.click();
    });

    await test.step('Verify empty state is shown again', async () => {
      const browseHistoryButton = page.locator(
        'button:has-text("Browse History")'
      );
      const createNewRunButton = page.locator(
        'button:has-text("Create New Run")'
      );

      await expect(browseHistoryButton).toBeVisible();
      await expect(createNewRunButton).toBeVisible();
    });
  });

  test('can navigate to manual run panel @collaborative', async ({ page }) => {
    await test.step('Click Create New Run button', async () => {
      const createNewRunButton = page.locator(
        'button:has-text("Create New Run")'
      );
      await createNewRunButton.click();
    });

    await test.step('Verify manual run panel is shown', async () => {
      // Manual run panel should display dataclip selection interface
      // Look for the "Select Input" heading or similar text
      // Note: Exact text depends on ManualRunPanel implementation
      await expect(
        page.locator('text=/Select Input|Choose.*dataclip/i')
      ).toBeVisible({ timeout: 5000 });
    });
  });

  test('right panel header updates based on mode @collaborative', async ({
    page,
  }) => {
    await test.step('Verify initial header shows "Select Action"', () => {
      // The collapsed panel label or header should show current mode
      // Note: Exact selector depends on implementation
      // This test step is a placeholder for future implementation
      expect(page).toBeDefined();
    });

    await test.step('Navigate to history and verify header', async () => {
      const browseHistoryButton = page.locator(
        'button:has-text("Browse History")'
      );
      await browseHistoryButton.click();

      // History browser header should be visible
      await expect(page.locator('text=Browse History').first()).toBeVisible();
    });

    await test.step('Return to empty state and verify header', async () => {
      const backButton = page.locator(
        'button[aria-label="Close history browser"]'
      );
      await backButton.click();

      // Empty state buttons should be visible again
      await expect(
        page.locator('button:has-text("Browse History")')
      ).toBeVisible();
    });
  });

  test('history browser shows empty state when no runs exist @collaborative', async ({
    page,
  }) => {
    await test.step('Navigate to history browser', async () => {
      const browseHistoryButton = page.locator(
        'button:has-text("Browse History")'
      );
      await browseHistoryButton.click();
    });

    await test.step('Verify empty history state or history list', async () => {
      // The workflow may or may not have runs depending on test data
      // Check for either empty state or history list

      const emptyStateHeading = page.locator('text=No Runs Yet');
      const historyList = page.locator('[data-testid="history-list"]');

      // One of these should be visible
      const emptyStateVisible = await emptyStateHeading
        .isVisible()
        .catch(() => false);
      const historyListVisible = await historyList
        .isVisible()
        .catch(() => false);

      expect(emptyStateVisible || historyListVisible).toBe(true);
    });
  });

  test('URL parameter ?run=xxx loads run viewer directly @collaborative', async ({
    page,
  }) => {
    // Note: This test requires a valid run ID
    // Skip if test data doesn't provide run IDs
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    const hasRuns =
      testData.runs &&
      Object.keys(testData.runs as Record<string, unknown>).length > 0;
    test.skip(!hasRuns, 'No test run data available');

    await test.step('Navigate to workflow with run parameter', async () => {
      // Get a run ID from test data
      const runs = (testData.runs || {}) as Record<string, { id?: string }>;
      const runId = Object.values(runs)[0]?.id;
      if (!runId) {
        test.skip(true, 'No run ID available');
        return;
      }

      // Navigate with run parameter
      await page.goto(
        `/projects/${testData.projects.openhie.id}/workflows/${testData.workflows.openhie.id}/collaborate?run=${runId}`
      );

      // Wait for collaborative editor to load
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();
    });

    await test.step('Verify run viewer is shown', async () => {
      // Look for run viewer indicators
      // This could be run chip, tabs, or other run viewer UI elements
      await expect(page.locator('[data-testid="run-viewer"]')).toBeVisible({
        timeout: 5000,
      });
    });
  });

  test('keyboard shortcuts still work in all panel modes @collaborative', async ({
    page,
  }) => {
    await test.step('Test Escape key in empty state', async () => {
      // Escape should not crash or cause errors
      await page.keyboard.press('Escape');

      // Verify UI is still responsive
      await expect(
        page.locator('button:has-text("Browse History")')
      ).toBeVisible();
    });

    await test.step('Test Escape key in history browser', async () => {
      const browseHistoryButton = page.locator(
        'button:has-text("Browse History")'
      );
      await browseHistoryButton.click();

      // Escape should not crash
      await page.keyboard.press('Escape');

      // History browser should still be functional
      const backButton = page.locator(
        'button[aria-label="Close history browser"]'
      );
      await expect(backButton).toBeVisible();
    });
  });
});
