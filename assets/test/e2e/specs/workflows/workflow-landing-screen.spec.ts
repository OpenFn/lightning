/**
 * E2E specs for the AI-First Landing Screen (#4856)
 *
 * Validates the "Where would you like to start?" overlay that appears
 * when navigating to /w/new before any creation path is committed.
 *
 * Three describe blocks:
 *   - "AI-disabled" — always runs; covers the default E2E environment where
 *     no Apollo config is present (data-ai-assistant-enabled="false")
 *   - "AI-enabled" — guarded by a runtime skip when AI config is absent;
 *     exercises the Build with AI entry point
 *   - "viewer permission denial" — a project viewer can reach /w/new (the
 *     landing screen itself isn't permission-gated) but the underlying
 *     channel join for a new workflow is denied server-side, so Build from
 *     scratch must never succeed in persisting a workflow (#4895)
 *
 * NOTE: Do NOT run these tests directly. They require a running E2E server.
 * Use: cd assets && npm run test:e2e -- --grep "landing screen"
 */

import { test, expect, type Page } from '@playwright/test';

import { LoginPage, WorkflowEditPage } from '../../pages';
import { getTestData } from '../../test-data';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function navigateToNewWorkflow(
  page: Page,
  projectId: string
): Promise<void> {
  await page.goto(`/projects/${projectId}/w/new`);
  await page.waitForLoadState('networkidle');
}

// ---------------------------------------------------------------------------
// AI-disabled context (default E2E environment — no Apollo config)
// ---------------------------------------------------------------------------

test.describe('landing screen — AI-disabled @landing-screen', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;
  let projectId: string;

  test.beforeAll(async () => {
    testData = await getTestData();
    projectId = testData.projects.openhie.id;
  });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );
  });

  test('landing screen is visible at /w/new', async ({ page }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);
    await expect(workflowEdit.landingScreen).toBeVisible();
  });

  test('header (Save/Create button) is absent while landing screen is showing', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);

    await expect(workflowEdit.landingScreen).toBeVisible();
    // BreadcrumbContent is gated on !isNewWorkflow, so save-workflow-button
    // must not be in the DOM at all
    await expect(page.getByTestId('save-workflow-button')).not.toBeAttached();
  });

  test('URL stays at /new while landing screen is visible', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);

    await expect(workflowEdit.landingScreen).toBeVisible();
    expect(page.url()).toContain('/new');
  });

  test('back navigation returns to project workflow list', async ({ page }) => {
    // Navigate from the project workflows list so we have history to go back to
    await page.goto(`/projects/${projectId}/w`);
    await page.waitForLoadState('networkidle');

    await navigateToNewWorkflow(page, projectId);

    const workflowEdit = new WorkflowEditPage(page);
    await expect(workflowEdit.landingScreen).toBeVisible();

    await page.goBack();
    await page.waitForLoadState('networkidle');

    expect(page.url()).toContain(`/projects/${projectId}/w`);
    expect(page.url()).not.toContain('/new');
  });

  test('Browse Templates card is visible', async ({ page }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);
    await expect(workflowEdit.browseTemplatesCard).toBeVisible();
  });

  test('Import YAML link is visible', async ({ page }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);
    await expect(workflowEdit.importYAMLLink).toBeVisible();
  });

  test('Build with AI input is absent when AI is disabled', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);

    await expect(workflowEdit.landingScreen).toBeVisible();
    await expect(workflowEdit.buildWithAIInput).not.toBeAttached();
    await expect(workflowEdit.buildWithAIButton).not.toBeAttached();
    await expect(workflowEdit.aiDisclaimerFooter).not.toBeAttached();
  });

  test('Build from scratch creates a webhook workflow and lands on the canvas', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);

    // Build from scratch runs entirely client-side against the
    // already-open collaborative session: importWorkflow -> saveWorkflow
    // ({ silent: true }) -> dismissLandingScreen. `saveWorkflow`'s own success
    // handler performs the one navigation, from /w/new to the real
    // /w/<workflowId>.
    await workflowEdit.buildFromScratchCard.click();
    await expect(workflowEdit.landingScreen).not.toBeVisible();

    await page.waitForURL(url => !url.pathname.endsWith('/new'));

    // saveWorkflow({ silent: true }) already resolved (it's awaited before
    // dismissLandingScreen runs), so the workflow is persisted and
    // isNewWorkflow has already flipped false: the normal Save button is
    // present (unlike the landing screen, where it's absent entirely) and
    // there are no pending unsaved changes.
    await expect(page.getByTestId('save-workflow-button')).toBeVisible();
    await expect(page.locator('[data-is-dirty]')).not.toBeAttached();
  });
});

// ---------------------------------------------------------------------------
// Viewer permission-denial context
// ---------------------------------------------------------------------------

test.describe('landing screen — viewer permission denial @landing-screen', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;
  let projectId: string;

  test.beforeAll(async () => {
    testData = await getTestData();
    projectId = testData.projects.openhie.id;
  });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.viewer.email,
      testData.users.viewer.password
    );
  });

  test('viewer clicking Build from scratch never creates a workflow', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);

    // A viewer's channel join for action=new is rejected server-side
    // (WorkflowChannel.join/3 requires :create_workflow, which a viewer
    // lacks) before any collaborative session starts. The landing screen
    // itself isn't gated on join success (showLandingScreen defaults to
    // true client-side), so the card is still visible and clickable — the
    // enforcement point is the channel join, not the UI.
    await expect(workflowEdit.landingScreen).toBeVisible();
    await expect(workflowEdit.buildFromScratchCard).toBeVisible();

    await workflowEdit.buildFromScratchCard.click();

    // Whatever the click does under the hood, it must never result in a
    // persisted workflow: the save-workflow-button (only rendered once
    // isNewWorkflow flips false, which only happens after a successful
    // save) must never appear, and the landing screen must not be
    // dismissed as if creation had succeeded.
    await expect(page.getByTestId('save-workflow-button')).not.toBeVisible();
    await expect(workflowEdit.landingScreen).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// AI-enabled context (requires APOLLO_ENDPOINT + APOLLO_API_KEY in env)
// ---------------------------------------------------------------------------

test.describe('landing screen — AI-enabled @landing-screen @ai', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;
  let projectId: string;

  test.beforeAll(async () => {
    testData = await getTestData();
    projectId = testData.projects.openhie.id;
  });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );

    // Skip the entire suite when the server reports AI is not enabled.
    // The React root element carries data-ai-assistant-enabled="true|false"
    // as a server-rendered data attribute.
    await navigateToNewWorkflow(page, projectId);

    const aiEnabled = await page
      .locator('[data-ai-assistant-enabled]')
      .first()
      .getAttribute('data-ai-assistant-enabled');

    if (aiEnabled !== 'true') {
      test.skip();
    }
  });

  test('landing screen is visible at /w/new', async ({ page }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await expect(workflowEdit.landingScreen).toBeVisible();
  });

  test('all three entry points are visible when AI is enabled', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await expect(workflowEdit.landingScreen).toBeVisible();
    await expect(workflowEdit.buildWithAIInput).toBeVisible();
    await expect(workflowEdit.buildWithAIButton).toBeVisible();
    await expect(workflowEdit.browseTemplatesCard).toBeVisible();
    await expect(workflowEdit.importYAMLLink).toBeVisible();
  });

  test('AI disclaimer footer is visible in the Build with AI card', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await expect(workflowEdit.aiDisclaimerFooter).toBeVisible();
    await expect(workflowEdit.aiDisclaimerLearnMoreLink).toHaveAttribute(
      'href',
      'https://www.openfn.org/ai'
    );
    await expect(workflowEdit.aiDisclaimerLearnMoreLink).toHaveAttribute(
      'target',
      '_blank'
    );
  });

  test('Build it button is disabled when prompt is empty', async ({ page }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await expect(workflowEdit.buildWithAIButton).toBeDisabled();
  });

  test('Build it button is enabled after typing a non-whitespace prompt', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await workflowEdit.buildWithAIInput.fill('Send a weekly report');
    await expect(workflowEdit.buildWithAIButton).toBeEnabled();
  });

  test('header (Save/Create button) is absent while landing screen is showing', async ({
    page,
  }) => {
    await expect(page.getByTestId('save-workflow-button')).not.toBeAttached();
  });

  test('URL stays at /new while landing screen is visible', async ({
    page,
  }) => {
    expect(page.url()).toContain('/new');
  });

  test('back navigation returns to project workflow list', async ({ page }) => {
    // Navigate from the project workflows list so we have history to go back to
    await page.goto(`/projects/${projectId}/w`);
    await page.waitForLoadState('networkidle');

    await navigateToNewWorkflow(page, projectId);

    await page.goBack();
    await page.waitForLoadState('networkidle');

    expect(page.url()).toContain(`/projects/${projectId}/w`);
    expect(page.url()).not.toContain('/new');
  });
});
