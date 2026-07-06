/**
 * E2E specs for the AI-First Landing Screen (#4856)
 *
 * Validates the "Where would you like to start?" overlay that appears
 * when navigating to /w/new before any creation path is committed.
 *
 * Two describe blocks:
 *   - "AI-disabled" — always runs; covers the default E2E environment where
 *     no Apollo config is present (data-ai-assistant-enabled="false")
 *   - "AI-enabled" — guarded by a runtime skip when AI config is absent;
 *     exercises the Build with AI entry point
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
  });

  test('Build from scratch lands on the trigger picker, not the webhook show panel', async ({
    page,
  }) => {
    const workflowEdit = new WorkflowEditPage(page);
    await navigateToNewWorkflow(page, projectId);

    await workflowEdit.buildFromScratchCard.click();
    await page.waitForURL(url => !url.pathname.endsWith('/w/new'));
    await page.waitForLoadState('networkidle');

    // The build-from-scratch redirect carries a one-shot ?trigger_view=picker
    // signal (#4895) so the wizard opens straight on "What triggers this
    // workflow?" instead of the webhook show panel — inviting the user to
    // actively choose rather than silently defaulting to webhook.
    await expect(
      page.getByRole('heading', { name: 'What triggers this workflow?' })
    ).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'On webhook call' })
    ).not.toBeVisible();

    // The one-shot signal is stripped after being consumed.
    expect(page.url()).not.toContain('trigger_view');

    // Per #4895: not in the pink/new-workflow toolbar state — the workflow
    // was already persisted by the redirect, so the normal Save button is
    // present (unlike the landing screen, where it's absent entirely).
    await expect(page.getByTestId('save-workflow-button')).toBeVisible();
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
