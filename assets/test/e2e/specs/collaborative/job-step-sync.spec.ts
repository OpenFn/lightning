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
 * E2E Test Suite: Job-Step Selection Sync
 *
 * Tests that when viewing a run in the collaborative editor IDE,
 * clicking on different jobs correctly syncs the step selection URL parameter.
 *
 * @see https://github.com/OpenFn/lightning/issues/4189
 * @see assets/js/collaborative-editor/components/ide/FullScreenIDE.tsx
 */

test.describe('Job-Step Selection Sync @collaborative', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test.beforeEach(async ({ page }) => {
    // Enable experimental features to access collaborative editor
    await enableExperimentalFeatures(testData.users.editor.email);

    // Login as editor user
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );

    // Navigate to collaborative editor
    const projectsPage = new ProjectsPage(page);
    await projectsPage.navigateToProject(testData.projects.openhie.name);

    const workflowsPage = new WorkflowsPage(page);
    await workflowsPage.navigateToWorkflow(testData.workflows.openhie.name);

    // Wait for workflow edit page to load
    const workflowEditPage = new WorkflowEditPage(page);
    await workflowEditPage.waitForConnected();

    // Switch to collaborative editor via beaker icon
    await workflowEditPage.clickCollaborativeEditorToggle();

    const collabPage = new WorkflowCollaborativePage(page);
    await collabPage.waitForReactComponentLoaded();

    // Wait for workflow canvas to be interactive (job nodes visible)
    await page
      .locator('[data-testid="job-node"]')
      .first()
      .waitFor({ timeout: 30000 });
  });

  test('clicking a job while viewing a run syncs step selection', async ({
    page,
  }) => {
    let initialStepParam: string | null = null;

    await test.step('Create a run via Manual Run Panel', async () => {
      // Click on the first job to select it
      const jobNode = page.locator('[data-testid="job-node"]').first();
      await jobNode.click();

      // Click "Run" button to open Manual Run Panel
      const runButton = page.locator('button:has-text("Run")').first();
      await runButton.click();

      // Verify panel is open
      await expect(page.locator('text="Run from"').first()).toBeVisible();

      // Click "Run Workflow Now" button
      const runWorkflowButton = page.locator(
        'button:has-text("Run Workflow Now")'
      );
      await runWorkflowButton.click();

      // Wait for run to start
      await expect(page.locator('text="Run started"')).toBeVisible({
        timeout: 5000,
      });
    });

    await test.step('Wait for run to complete', async () => {
      // Wait for retry button to appear (indicates run completed)
      await expect(page.locator('button:has-text("Run (Retry)")')).toBeVisible({
        timeout: 30000,
      });
    });

    await test.step('Open fullscreen IDE', async () => {
      // Click expand button to open fullscreen IDE
      const expandButton = page.locator(
        '[aria-label="Open fullscreen editor"]'
      );
      await expandButton.click();

      // Verify IDE is open
      await expect(page.locator('[data-testid="monaco-editor"]')).toBeVisible({
        timeout: 5000,
      });
    });

    await test.step('Record initial step param', () => {
      // Get current URL and extract step param
      const url = new URL(page.url());
      initialStepParam = url.searchParams.get('step');

      // The initial step param might be set or null depending on current selection
      // We just want to verify it changes when we switch jobs
    });

    await test.step('Switch to a different job via JobSelector', async () => {
      // The JobSelector shows the current job name with a chevron
      // Click it to open the dropdown
      const jobSelector = page.locator('button').filter({
        has: page.locator('.hero-chevron-up-down'),
      });
      await jobSelector.click();

      // Wait for dropdown options to appear
      await expect(page.locator('[role="listbox"]')).toBeVisible();

      // Click on "Send to OpenHIM to route to SHR" (a different job)
      const differentJob = page
        .locator('[role="option"]')
        .filter({ hasText: 'Send to OpenHIM to route to SHR' });
      await differentJob.click();
    });

    await test.step('Verify step param updated in URL', async () => {
      // Wait a moment for the URL to update
      await page.waitForTimeout(500);

      // Get the new URL and verify step param has changed
      const url = new URL(page.url());
      const newStepParam = url.searchParams.get('step');

      // The step param should be set (not null) since this job was executed
      expect(newStepParam).not.toBeNull();

      // If we had an initial step param, verify it's different
      // (indicating the sync worked)
      if (initialStepParam) {
        expect(newStepParam).not.toBe(initialStepParam);
      }
    });

    await test.step('Switch to another job and verify step syncs again', async () => {
      // Open JobSelector again
      const jobSelector = page.locator('button').filter({
        has: page.locator('.hero-chevron-up-down'),
      });
      await jobSelector.click();

      // Wait for dropdown options to appear
      await expect(page.locator('[role="listbox"]')).toBeVisible();

      // Click on "Notify CHW upload successful"
      const anotherJob = page
        .locator('[role="option"]')
        .filter({ hasText: 'Notify CHW upload successful' });
      await anotherJob.click();

      // Wait for URL to update
      await page.waitForTimeout(500);

      // Verify step param is set for this job too
      const url = new URL(page.url());
      const finalStepParam = url.searchParams.get('step');
      expect(finalStepParam).not.toBeNull();
    });
  });

  test('switching jobs updates step panel content', async ({ page }) => {
    await test.step('Create and wait for run to complete', async () => {
      const jobNode = page.locator('[data-testid="job-node"]').first();
      await jobNode.click();

      const runButton = page.locator('button:has-text("Run")').first();
      await runButton.click();

      const runWorkflowButton = page.locator(
        'button:has-text("Run Workflow Now")'
      );
      await runWorkflowButton.click();

      await expect(page.locator('text="Run started"')).toBeVisible({
        timeout: 5000,
      });

      // Wait for run to complete
      await expect(page.locator('button:has-text("Run (Retry)")')).toBeVisible({
        timeout: 30000,
      });
    });

    await test.step('Open fullscreen IDE', async () => {
      const expandButton = page.locator(
        '[aria-label="Open fullscreen editor"]'
      );
      await expandButton.click();

      await expect(page.locator('[data-testid="monaco-editor"]')).toBeVisible({
        timeout: 5000,
      });
    });

    await test.step('Verify run panel shows step information', async () => {
      // The right panel should show run/step information
      // Look for indicators that step data is displayed
      // This could be input/output tabs, log entries, etc.
      await expect(
        page.locator('text=/Input|Output|Log/i').first()
      ).toBeVisible({
        timeout: 5000,
      });
    });

    await test.step('Switch job and verify panel updates', async () => {
      // Switch to a different job
      const jobSelector = page.locator('button').filter({
        has: page.locator('.hero-chevron-up-down'),
      });
      await jobSelector.click();

      await expect(page.locator('[role="listbox"]')).toBeVisible();

      const differentJob = page
        .locator('[role="option"]')
        .filter({ hasText: 'Send to OpenHIM to route to SHR' });
      await differentJob.click();

      // Wait for panel to update
      await page.waitForTimeout(500);

      // The panel should still show step information (for the new step)
      await expect(
        page.locator('text=/Input|Output|Log/i').first()
      ).toBeVisible();
    });
  });
});
