import { test, expect } from '@playwright/test';
import { getTestData } from '../../test-data';
import { LoginPage } from '../../pages';

test.describe('Job Inspector Configuration Flow', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );
  });

  test('complete job creation and configuration flow', async ({ page }) => {
    await test.step('Navigate to workflow', async () => {
      await page.goto('/projects/1/workflows');
      await page.locator('[data-entity="workflow"]').first().click();

      // Wait for canvas to be visible
      const canvas = page.locator('.react-flow__renderer');
      await expect(canvas).toBeVisible({ timeout: 10000 });
    });

    await test.step('Create new job via connector', async () => {
      // Click connector to add new node
      const firstNode = page.locator('.react-flow__node').first();
      await expect(firstNode).toBeVisible();

      const connector = firstNode.locator('[data-handleid="node-connector"]');
      await connector.click();
    });

    await test.step('Select adaptor from modal', async () => {
      // Wait for adaptor modal
      const modal = page.locator('[role="dialog"]');
      await expect(modal).toBeVisible({ timeout: 5000 });

      // Search for Salesforce adaptor
      const searchInput = page.getByPlaceholder(
        'Search for an adaptor to connect...'
      );
      await expect(searchInput).toBeVisible();
      await searchInput.fill('salesforce');

      // Select Salesforce adaptor
      const salesforceButton = modal
        .locator('button')
        .filter({ hasText: /salesforce/i })
        .first();
      await salesforceButton.click();
    });

    await test.step('Verify inspector auto-opens with job', async () => {
      // Modal should close
      await expect(
        page.getByPlaceholder('Search for an adaptor to connect...')
      ).not.toBeVisible();

      // Inspector should be visible
      // (Inspector is part of main layout, check for job name field)
      const nameInput = page.locator('input[name="name"]').first();
      await expect(nameInput).toBeVisible({ timeout: 3000 });

      // Job name should default to adaptor name
      await expect(nameInput).toHaveValue(/salesforce/i);
    });

    await test.step('Verify adaptor display section (Phase 2R)', async () => {
      // Check for "Adaptor" label
      await expect(page.getByText('Adaptor', { exact: true })).toBeVisible();

      // Check adaptor display shows Salesforce
      await expect(page.getByText('Salesforce')).toBeVisible();

      // Phase 2R: Version is NO LONGER shown in inspector
      // (Version selection moved to ConfigureAdaptorModal)

      // Phase 2R: Check "Connect" button exists (changed from "Change")
      const connectButton = page.getByRole('button', {
        name: /configure/i,
      });
      await expect(connectButton).toBeVisible();
      await expect(connectButton).toHaveText('Connect');
    });

    await test.step('Configure adaptor via Connect button (Phase 3R)', async () => {
      // Click "Connect" button to open ConfigureAdaptorModal
      const connectButton = page.getByRole('button', {
        name: /configure/i,
      });
      await connectButton.click();

      // ConfigureAdaptorModal should open
      await expect(page.getByText('Configure Your Adaptor')).toBeVisible();

      // Verify current adaptor is shown
      await expect(page.getByText('Salesforce')).toBeVisible();

      // Verify version dropdown is visible with current version
      const versionDropdown = page.locator('select').filter({
        has: page.locator('option[value="2.1.0"]'),
      });
      await expect(versionDropdown).toBeVisible();

      // Click "Change" button within modal to change adaptor
      const changeButton = page
        .locator('[role="dialog"]')
        .getByRole('button', { name: /change/i });
      await changeButton.click();

      // Nested AdaptorSelectionModal should open
      await expect(
        page.getByPlaceholder('Search for an adaptor to connect...')
      ).toBeVisible();

      // Search for HTTP adaptor
      const searchInput = page.getByPlaceholder(
        'Search for an adaptor to connect...'
      );
      await searchInput.clear();
      await searchInput.fill('http');

      // Select HTTP adaptor
      const httpButton = page
        .locator('button')
        .filter({ hasText: /^http$/i })
        .first();
      await httpButton.click();

      // Nested modal should close, back to ConfigureAdaptorModal
      await expect(
        page.getByPlaceholder('Search for an adaptor to connect...')
      ).not.toBeVisible();

      // ConfigureAdaptorModal should still be open with Http selected
      await expect(page.getByText('Configure Your Adaptor')).toBeVisible();
      await expect(page.getByText('Http')).toBeVisible({ timeout: 3000 });

      // Save changes
      const saveButton = page
        .locator('[role="dialog"]')
        .getByRole('button', { name: /save/i });
      await saveButton.click();

      // Modal should close
      await expect(page.getByText('Configure Your Adaptor')).not.toBeVisible();

      // Adaptor in inspector should update to Http
      await expect(page.getByText('Http')).toBeVisible({ timeout: 3000 });
    });

    await test.step('Edit job name', async () => {
      const nameInput = page.locator('input[name="name"]').first();
      await nameInput.fill('My HTTP Job');

      // Verify value updated
      await expect(nameInput).toHaveValue('My HTTP Job');
    });

    await test.step('Verify changes persist after navigation', async () => {
      // Click on canvas to deselect (close inspector if needed)
      const canvas = page.locator('.react-flow__renderer');
      await canvas.click({ position: { x: 50, y: 50 } });

      // Wait a moment for any saves to complete
      await page.waitForTimeout(500);

      // Click on the newly created node to reopen inspector
      const newNode = page
        .locator('.react-flow__node')
        .filter({ hasText: 'My HTTP Job' });
      await newNode.click();

      // Verify all changes persisted
      const nameInput = page.locator('input[name="name"]').first();
      await expect(nameInput).toHaveValue('My HTTP Job');
      await expect(page.getByText('Http')).toBeVisible();
    });
  });

  test('inspector opens after drag-to-space node creation', async ({
    page,
  }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });

    // Get first node connector
    const firstNode = page.locator('.react-flow__node').first();
    const connector = firstNode.locator('[data-handleid="node-connector"]');

    // Get connector position and drag to empty space
    const connectorBox = await connector.boundingBox();
    if (!connectorBox) throw new Error('Connector not found');

    await page.mouse.move(
      connectorBox.x + connectorBox.width / 2,
      connectorBox.y + connectorBox.height / 2
    );
    await page.mouse.down();
    await page.mouse.move(connectorBox.x + 300, connectorBox.y + 200);
    await page.mouse.up();

    // Adaptor modal should open
    const modal = page.locator('[role="dialog"]');
    await expect(modal).toBeVisible({ timeout: 5000 });

    // Select HTTP adaptor
    const searchInput = page.getByPlaceholder(
      'Search for an adaptor to connect...'
    );
    await searchInput.fill('http');

    const httpButton = page
      .locator('button')
      .filter({ hasText: /^http$/i })
      .first();
    await httpButton.click();

    // Inspector should auto-open with new job
    const nameInput = page.locator('input[name="name"]').first();
    await expect(nameInput).toBeVisible({ timeout: 3000 });
    await expect(nameInput).toHaveValue(/http/i);
  });

  test('multiple adaptors can be configured sequentially', async ({ page }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });

    // Create first job
    await test.step('Create first job with Salesforce', async () => {
      const firstNode = page.locator('.react-flow__node').first();
      const connector = firstNode.locator('[data-handleid="node-connector"]');
      await connector.click();

      // Select Salesforce
      const searchInput = page.getByPlaceholder(
        'Search for an adaptor to connect...'
      );
      await searchInput.fill('salesforce');

      const salesforceButton = page
        .locator('button')
        .filter({ hasText: /salesforce/i })
        .first();
      await salesforceButton.click();

      // Set name and verify
      const nameInput = page.locator('input[name="name"]').first();
      await expect(nameInput).toBeVisible();
      await nameInput.fill('Job 1');
      await expect(page.getByText('Salesforce')).toBeVisible();
    });

    // Create second job
    await test.step('Create second job with HTTP', async () => {
      // Click away to deselect first job
      const canvas = page.locator('.react-flow__renderer');
      await canvas.click({ position: { x: 50, y: 50 } });

      // Find the newly created "Job 1" node and add another job
      const job1Node = page
        .locator('.react-flow__node')
        .filter({ hasText: 'Job 1' });
      await expect(job1Node).toBeVisible();

      const connector = job1Node.locator('[data-handleid="node-connector"]');
      await connector.click();

      // Select HTTP
      const searchInput = page.getByPlaceholder(
        'Search for an adaptor to connect...'
      );
      await searchInput.fill('http');

      const httpButton = page
        .locator('button')
        .filter({ hasText: /^http$/i })
        .first();
      await httpButton.click();

      // Set name and verify
      const nameInput = page.locator('input[name="name"]').first();
      await expect(nameInput).toBeVisible();
      await nameInput.fill('Job 2');
    });

    // Verify both jobs exist
    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Job 1' })
    ).toBeVisible();
    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Job 2' })
    ).toBeVisible();
  });
});
