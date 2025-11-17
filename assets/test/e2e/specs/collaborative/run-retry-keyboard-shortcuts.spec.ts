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
 * E2E Test Suite: Run/Retry Keyboard Shortcuts
 *
 * Tests keyboard shortcuts for running and retrying workflows:
 * - Cmd+Enter (Mac) / Ctrl+Enter (Windows/Linux): Run or Retry
 * - Cmd+Shift+Enter / Ctrl+Shift+Enter: Force New Work Order
 *
 * These shortcuts work in:
 * - Manual Run Panel
 * - Fullscreen IDE (Monaco editor)
 * - IDE Header
 *
 * @see assets/js/collaborative-editor/components/ManualRunPanel.tsx
 * @see assets/js/collaborative-editor/components/ide/IDEHeader.tsx
 * @see assets/js/collaborative-editor/hooks/useRunRetry.ts
 */

test.describe('Run/Retry Keyboard Shortcuts @collaborative @critical', () => {
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
    // We don't strictly need full "Synced" state for keyboard shortcut tests
    await page
      .locator('[data-testid="job-node"]')
      .first()
      .waitFor({ timeout: 30000 });
  });

  test('Cmd+Enter triggers run from Manual Run Panel', async ({
    page,
    browserName,
  }) => {
    await test.step('Open Manual Run Panel', async () => {
      // Click on a job to open inspector
      const jobNode = page.locator('[data-testid="job-node"]').first();
      await jobNode.click();

      // Click "Run" button to open Manual Run Panel
      const runButton = page.locator('button:has-text("Run")').first();
      await runButton.click();

      // Verify panel is open
      await expect(page.locator('text="Run from"').first()).toBeVisible();
    });

    await test.step('Press Cmd+Enter to trigger run', async () => {
      // Get the modifier key based on platform
      const modifierKey = browserName === 'webkit' ? 'Meta' : 'Control';

      // Press keyboard shortcut
      await page.keyboard.press(`${modifierKey}+Enter`);

      // Verify run was triggered - look for success notification
      await expect(page.locator('text="Run started"')).toBeVisible({
        timeout: 5000,
      });

      await expect(
        page.locator('text="Saved latest changes and created new work order"')
      ).toBeVisible();
    });
  });

  test('Cmd+Enter triggers retry when following a run', async ({
    page,
    browserName,
  }) => {
    await test.step('Create a run first', async () => {
      // Click on a job
      const jobNode = page.locator('[data-testid="job-node"]').first();
      await jobNode.click();

      // Open Manual Run Panel
      const runButton = page.locator('button:has-text("Run")').first();
      await runButton.click();

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

    await test.step('Verify button shows retry mode', async () => {
      // Button should now show "Run (retry)"
      await expect(page.locator('button:has-text("Run (retry)")')).toBeVisible({
        timeout: 10000,
      });
    });

    await test.step('Press Cmd+Enter to trigger retry', async () => {
      const modifierKey = browserName === 'webkit' ? 'Meta' : 'Control';

      // Press keyboard shortcut
      await page.keyboard.press(`${modifierKey}+Enter`);

      // Verify retry was triggered
      await expect(page.locator('text="Retry started"')).toBeVisible({
        timeout: 5000,
      });

      await expect(
        page.locator(
          'text="Saved latest changes and re-running with previous input"'
        )
      ).toBeVisible();
    });
  });

  test('Cmd+Shift+Enter forces new work order', async ({
    page,
    browserName,
  }) => {
    await test.step('Create a run to enable retry mode', async () => {
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

      // Wait for retry mode
      await expect(page.locator('button:has-text("Run (retry)")')).toBeVisible({
        timeout: 10000,
      });
    });

    await test.step('Press Cmd+Shift+Enter to force new work order', async () => {
      const modifierKey = browserName === 'webkit' ? 'Meta' : 'Control';

      // Press keyboard shortcut with Shift
      await page.keyboard.press(`${modifierKey}+Shift+Enter`);

      // Verify NEW run was started (not retry)
      await expect(page.locator('text="Run started"')).toBeVisible({
        timeout: 5000,
      });

      // Should see "new work order" message, not "retry" message
      await expect(
        page.locator('text="Saved latest changes and created new work order"')
      ).toBeVisible();
    });
  });

  test('Keyboard shortcuts work in Monaco editor (IDE)', async ({
    page,
    browserName,
  }) => {
    await test.step('Open fullscreen IDE', async () => {
      // Click on a job
      const jobNode = page.locator('[data-testid="job-node"]').first();
      await jobNode.click();

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

    await test.step('Focus Monaco editor and press Cmd+Enter', async () => {
      // Click into Monaco editor to focus it
      const monacoEditor = page.locator('[data-testid="monaco-editor"]');
      await monacoEditor.click();

      const modifierKey = browserName === 'webkit' ? 'Meta' : 'Control';

      // Press keyboard shortcut while focused in editor
      await page.keyboard.press(`${modifierKey}+Enter`);

      // Verify run was triggered
      await expect(page.locator('text="Run started"')).toBeVisible({
        timeout: 5000,
      });
    });
  });

  test('Keyboard shortcuts respect disabled state', async ({
    page,
    browserName,
  }) => {
    await test.step('Open Manual Run Panel', async () => {
      const jobNode = page.locator('[data-testid="job-node"]').first();
      await jobNode.click();

      const runButton = page.locator('button:has-text("Run")').first();
      await runButton.click();
    });

    await test.step('Try to run without selecting input', async () => {
      // Switch to "existing" tab without selecting a dataclip
      const existingTab = page.locator('button:has-text("Existing")');
      await existingTab.click();

      const modifierKey = browserName === 'webkit' ? 'Meta' : 'Control';

      // Press keyboard shortcut
      await page.keyboard.press(`${modifierKey}+Enter`);

      // Verify NO run notification appears (should be disabled)
      await expect(page.locator('text="Run started"')).not.toBeVisible({
        timeout: 2000,
      });
    });
  });

  test('Split button dropdown works with mouse clicks', async ({ page }) => {
    await test.step('Create a run to enable split button', async () => {
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

      // Wait for split button to appear
      await expect(page.locator('button:has-text("Run (retry)")')).toBeVisible({
        timeout: 10000,
      });
    });

    await test.step('Click main button to retry', async () => {
      const retryButton = page.locator('button:has-text("Run (retry)")');
      await retryButton.click();

      await expect(page.locator('text="Retry started"')).toBeVisible({
        timeout: 5000,
      });
    });
  });

  test("Split button dropdown shows 'New Work Order' option", async ({
    page,
  }) => {
    await test.step('Create a run to enable split button', async () => {
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

      await expect(page.locator('button:has-text("Run (retry)")')).toBeVisible({
        timeout: 10000,
      });
    });

    await test.step("Open dropdown and click 'New Work Order'", async () => {
      // Click chevron to open dropdown
      const chevron = page.locator('[aria-label="Open run options"]');
      await chevron.click();

      // Verify dropdown is open
      await expect(page.locator('text="Run (New Work Order)"')).toBeVisible();

      // Click the dropdown option
      const newWorkOrderOption = page.locator('text="Run (New Work Order)"');
      await newWorkOrderOption.click();

      // Verify new run (not retry)
      await expect(page.locator('text="Run started"')).toBeVisible({
        timeout: 5000,
      });
      await expect(
        page.locator('text="Saved latest changes and created new work order"')
      ).toBeVisible();
    });
  });

  test('Run state updates in real-time via WebSocket', async ({ page }) => {
    await test.step('Create a run', async () => {
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
    });

    await test.step('Verify button changes to Processing state', async () => {
      // Button should show processing state
      await expect(page.locator('button:has-text("Processing")')).toBeVisible({
        timeout: 5000,
      });
    });

    await test.step('Verify button changes to Retry when complete', async () => {
      // Wait for run to complete and button to change to retry
      await expect(page.locator('button:has-text("Run (retry)")')).toBeVisible({
        timeout: 30000,
      });
    });
  });

  test('Cross-platform modifier keys work correctly', async ({
    page,
    browserName,
  }) => {
    await test.step('Verify correct modifier key for platform', async () => {
      const jobNode = page.locator('[data-testid="job-node"]').first();
      await jobNode.click();

      const runButton = page.locator('button:has-text("Run")').first();
      await runButton.click();

      // Test platform-specific modifier
      if (browserName === 'webkit') {
        // Mac: Use Command (Meta)
        await page.keyboard.press('Meta+Enter');
      } else {
        // Windows/Linux: Use Control
        await page.keyboard.press('Control+Enter');
      }

      // Both should trigger run
      await expect(page.locator('text="Run started"')).toBeVisible({
        timeout: 5000,
      });
    });
  });
});
