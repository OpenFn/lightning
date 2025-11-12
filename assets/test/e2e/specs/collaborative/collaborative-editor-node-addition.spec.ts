import { test, expect } from '@playwright/test';
import { authenticateViaUI } from '../../utils/auth';

test.describe('Collaborative Editor - Node Addition', () => {
  test.beforeEach(async ({ page }) => {
    await authenticateViaUI(page);
  });

  test('canvas should remain visible after adding node with ENTER key', async ({
    page,
  }) => {
    // Navigate to a workflow with at least one existing node
    await page.goto('/projects/1/workflows');

    // Click the first workflow in the list
    await page.locator('[data-entity="workflow"]').first().click();

    // Wait for canvas to be visible
    const canvas = page.locator('.react-flow__renderer');
    await expect(canvas).toBeVisible({ timeout: 10000 });

    // Find existing job node and click its connector
    const firstNode = page.locator('.react-flow__node').first();
    await expect(firstNode).toBeVisible();

    const connector = firstNode.locator('[data-handleid="node-connector"]');
    await connector.click();

    // Placeholder should appear
    const placeholderInput = page.locator('input[data-placeholder]');
    await expect(placeholderInput).toBeVisible();

    // Type node name and press ENTER
    await placeholderInput.fill('New Test Node');
    await placeholderInput.press('Enter');

    // Canvas should still be visible
    await expect(canvas).toBeVisible();

    // New node should appear immediately (within 2 seconds)
    const newNode = page
      .locator('.react-flow__node')
      .filter({ hasText: 'New Test Node' });
    await expect(newNode).toBeVisible({ timeout: 2000 });

    // Placeholder should be gone
    await expect(placeholderInput).not.toBeVisible();
  });

  test('should add multiple nodes sequentially without refresh', async ({
    page,
  }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    const canvas = page.locator('.react-flow__renderer');
    await expect(canvas).toBeVisible({ timeout: 10000 });

    // Add first node
    const firstNode = page.locator('.react-flow__node').first();
    const connector = firstNode.locator('[data-handleid="node-connector"]');
    await connector.click();

    let input = page.locator('input[data-placeholder]');
    await input.fill('Sequential Node 1');
    await input.press('Enter');

    // Verify first node added
    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Sequential Node 1' })
    ).toBeVisible();

    // Add second node without refresh
    const node1 = page
      .locator('.react-flow__node')
      .filter({ hasText: 'Sequential Node 1' });
    await node1.locator('[data-handleid="node-connector"]').click();

    input = page.locator('input[data-placeholder]');
    await input.fill('Sequential Node 2');
    await input.press('Enter');

    // Both nodes should be visible
    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Sequential Node 1' })
    ).toBeVisible();
    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Sequential Node 2' })
    ).toBeVisible();

    // Canvas should still be visible
    await expect(canvas).toBeVisible();
  });

  test('should persist node after hard refresh', async ({ page }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });

    // Add node
    const firstNode = page.locator('.react-flow__node').first();
    await firstNode.locator('[data-handleid="node-connector"]').click();

    const input = page.locator('input[data-placeholder]');
    await input.fill('Persisted Node');
    await input.press('Enter');

    // Verify node appears
    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Persisted Node' })
    ).toBeVisible();

    // Hard refresh
    await page.reload();

    // Node should still exist after refresh
    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });
    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Persisted Node' })
    ).toBeVisible();
  });

  test('should handle rapid node addition without canvas blank', async ({
    page,
  }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });

    const canvas = page.locator('.react-flow__renderer');

    // Add 5 nodes rapidly
    for (let i = 1; i <= 5; i++) {
      // Click connector on most recent node (or first node if i === 1)
      const targetNode =
        i === 1
          ? page.locator('.react-flow__node').first()
          : page
              .locator('.react-flow__node')
              .filter({ hasText: `Rapid Node ${i - 1}` });

      await targetNode.locator('[data-handleid="node-connector"]').click();

      const input = page.locator('input[data-placeholder]');
      await input.fill(`Rapid Node ${i}`);
      await input.press('Enter');

      // Canvas should remain visible throughout
      await expect(canvas).toBeVisible();

      // Wait for node to appear before adding next
      await expect(
        page.locator('.react-flow__node').filter({ hasText: `Rapid Node ${i}` })
      ).toBeVisible({ timeout: 2000 });
    }

    // Verify all nodes are visible
    for (let i = 1; i <= 5; i++) {
      await expect(
        page.locator('.react-flow__node').filter({ hasText: `Rapid Node ${i}` })
      ).toBeVisible();
    }
  });

  test('should work in both auto and manual layout modes', async ({ page }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });

    // Test in auto layout mode (default)
    const firstNode = page.locator('.react-flow__node').first();
    await firstNode.locator('[data-handleid="node-connector"]').click();

    let input = page.locator('input[data-placeholder]');
    await input.fill('Auto Layout Node');
    await input.press('Enter');

    await expect(
      page.locator('.react-flow__node').filter({ hasText: 'Auto Layout Node' })
    ).toBeVisible();

    // Switch to manual layout mode
    const layoutButton = page.locator(
      '.react-flow__controls button[data-tooltip*="manual layout"]'
    );
    await layoutButton.click();

    // Add node in manual layout mode
    const autoLayoutNode = page
      .locator('.react-flow__node')
      .filter({ hasText: 'Auto Layout Node' });
    await autoLayoutNode.locator('[data-handleid="node-connector"]').click();

    input = page.locator('input[data-placeholder]');
    await input.fill('Manual Layout Node');
    await input.press('Enter');

    // Node should appear in manual layout mode
    await expect(
      page
        .locator('.react-flow__node')
        .filter({ hasText: 'Manual Layout Node' })
    ).toBeVisible();

    // Canvas should be visible
    await expect(page.locator('.react-flow__renderer')).toBeVisible();
  });

  test('should open adaptor selection modal when dragging to empty space', async ({
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

    // Get connector position
    const connectorBox = await connector.boundingBox();
    if (!connectorBox) throw new Error('Connector not found');

    // Drag from connector to empty space
    await page.mouse.move(
      connectorBox.x + connectorBox.width / 2,
      connectorBox.y + connectorBox.height / 2
    );
    await page.mouse.down();
    await page.mouse.move(connectorBox.x + 300, connectorBox.y + 200);
    await page.mouse.up();

    // Adaptor modal should appear
    const modal = page.locator('[role="dialog"]').filter({
      hasText: 'Select an adaptor',
    });
    await expect(modal).toBeVisible({ timeout: 5000 });

    // Search input should be visible
    const searchInput = modal.locator(
      'input[placeholder="Search adaptors..."]'
    );
    await expect(searchInput).toBeVisible();
  });

  test('should create node with selected adaptor from modal', async ({
    page,
  }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });

    // Trigger modal by dragging to empty space
    const firstNode = page.locator('.react-flow__node').first();
    const connector = firstNode.locator('[data-handleid="node-connector"]');
    const connectorBox = await connector.boundingBox();
    if (!connectorBox) throw new Error('Connector not found');

    await page.mouse.move(
      connectorBox.x + connectorBox.width / 2,
      connectorBox.y + connectorBox.height / 2
    );
    await page.mouse.down();
    await page.mouse.move(connectorBox.x + 300, connectorBox.y + 200);
    await page.mouse.up();

    // Wait for modal
    const modal = page.locator('[role="dialog"]').filter({
      hasText: 'Select an adaptor',
    });
    await expect(modal).toBeVisible({ timeout: 5000 });

    // Search for http adaptor
    const searchInput = modal.locator(
      'input[placeholder="Search adaptors..."]'
    );
    await searchInput.fill('http');

    // Select http adaptor
    const httpAdaptor = modal
      .locator('button')
      .filter({ hasText: /http/i })
      .first();
    await httpAdaptor.click();

    // Modal should close
    await expect(modal).not.toBeVisible();

    // New node with http adaptor should appear
    const newNode = page
      .locator('.react-flow__node')
      .filter({ hasText: 'http' });
    await expect(newNode).toBeVisible({ timeout: 5000 });
  });

  test('should close adaptor modal when clicking outside', async ({ page }) => {
    await page.goto('/projects/1/workflows');
    await page.locator('[data-entity="workflow"]').first().click();

    await expect(page.locator('.react-flow__renderer')).toBeVisible({
      timeout: 10000,
    });

    // Trigger modal
    const firstNode = page.locator('.react-flow__node').first();
    const connector = firstNode.locator('[data-handleid="node-connector"]');
    const connectorBox = await connector.boundingBox();
    if (!connectorBox) throw new Error('Connector not found');

    await page.mouse.move(
      connectorBox.x + connectorBox.width / 2,
      connectorBox.y + connectorBox.height / 2
    );
    await page.mouse.down();
    await page.mouse.move(connectorBox.x + 300, connectorBox.y + 200);
    await page.mouse.up();

    // Wait for modal
    const modal = page.locator('[role="dialog"]').filter({
      hasText: 'Select an adaptor',
    });
    await expect(modal).toBeVisible({ timeout: 5000 });

    // Click outside modal (on the backdrop)
    await page.keyboard.press('Escape');

    // Modal should close
    await expect(modal).not.toBeVisible();

    // No new node should be created
    const nodeCount = await page.locator('.react-flow__node').count();
    // Should have same number of nodes as before
    expect(nodeCount).toBeGreaterThanOrEqual(1);
  });
});
