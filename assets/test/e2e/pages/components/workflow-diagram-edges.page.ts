import { expect } from '@playwright/test';
import type { Page, Locator } from '@playwright/test';

/**
 * Page Object Model for WorkflowDiagram edge interactions
 * Handles edge queries, drag-and-drop operations, and edge-related verifications
 */
export class WorkflowDiagramEdgesPage {
  protected selectors = {
    edges: '.react-flow__edge',
    edgePath: '.react-flow__edge-path',
    nodeConnector: '[data-handleid="node-connector"]', // The plus button IS a ReactFlow handle
    nodes: '.react-flow__node',
  };

  constructor(protected page: Page) {}

  /**
   * Get the total count of edges in the workflow
   * @returns The number of edges
   */
  async getCount(): Promise<number> {
    const edges = this.page.locator(this.selectors.edges);
    return await edges.count();
  }

  /**
   * Drag an edge from source to target node
   * This performs the complete drag operation using ReactFlow handles
   *
   * Implementation based on XYFlow's working Playwright tests with modifications
   * for our hidden handles (opacity-0 group-hover:opacity-100)
   *
   * Key insight from DOM inspection:
   * - The node-connector IS a ReactFlow Handle (has react-flow__handle class)
   * - It's hidden until we hover the node (group-hover pattern)
   * - Dragging creates edges, clicking creates placeholders
   *
   * @param sourceName - Source node display name
   * @param targetName - Target node display name
   */
  async dragFromTo(sourceName: string, targetName: string): Promise<void> {
    const sourceNode = this.getNodeByName(sourceName);
    const targetNode = this.getNodeByName(targetName);

    // Hover source node to make handle visible
    await sourceNode.hover();
    await this.page.waitForTimeout(200);

    const sourceHandle = sourceNode.locator(this.selectors.nodeConnector);
    await expect(sourceHandle).toBeVisible();

    // Get handle position
    const handleBox = await sourceHandle.boundingBox();
    if (!handleBox) {
      throw new Error('Could not get source handle bounding box');
    }

    const handleX = handleBox.x + handleBox.width / 2;
    const handleY = handleBox.y + handleBox.height / 2;

    // XYFlow pattern: hover handle → mouse down
    await this.page.mouse.move(handleX, handleY);
    await this.page.waitForTimeout(100);
    await this.page.mouse.down();
    await this.page.waitForTimeout(100);

    // Get target node position - hover directly to it
    const targetBox = await targetNode.boundingBox();
    if (!targetBox) {
      throw new Error('Could not get target node bounding box');
    }

    const targetX = targetBox.x + targetBox.width / 2;
    const targetY = targetBox.y + targetBox.height / 2;

    // Move to target with steps (important for ReactFlow to track drag)
    await this.page.mouse.move(targetX, targetY, { steps: 5 });
    await this.page.waitForTimeout(200);

    // Mouse up on target
    await this.page.mouse.up();
    await this.page.waitForTimeout(200);
  }

  /**
   * Start dragging an edge from a node
   * This hovers over the node and clicks the plus button (node connector)
   *
   * NOTE: This method is used by validation tests (TC-3724-02 through TC-3724-08)
   * that check if invalid connections are prevented. It does NOT trigger the
   * visual feedback system (onConnectStart) - use beginDrag() for that.
   *
   * @param sourceName - The node to drag from
   */
  async startDraggingFrom(sourceName: string): Promise<void> {
    const node = this.getNodeByName(sourceName);
    await node.hover();

    const plusButton = node.locator(this.selectors.nodeConnector);
    await expect(plusButton).toBeVisible();
    await plusButton.click();
  }

  /**
   * Begin an edge drag operation that triggers visual feedback
   * This actually performs a mouse drag gesture which triggers React Flow's
   * onConnectStart event and activates the visual feedback system.
   *
   * Implementation based on XYFlow issue #4775:
   * React Flow v12 requires initial movement to exceed nodeDragThreshold: 1
   * to distinguish drag from click, then continues with larger movement.
   *
   * The mouse button is left down after this method completes, so you can
   * hover over targets to see visual feedback, then call releaseDrag()
   * to cancel the operation.
   *
   * @param sourceName - The node to drag from
   */
  async beginDrag(sourceName: string): Promise<void> {
    const node = this.getNodeByName(sourceName);
    await node.hover();

    const plusButton = node.locator(this.selectors.nodeConnector);
    await expect(plusButton).toBeVisible();

    // Get the bounding box of the plus button to start the drag
    const bbox = await plusButton.boundingBox();
    if (!bbox) {
      throw new Error('Could not get plus button bounding box');
    }

    // Start drag by moving to button center and pressing mouse down
    const centerX = bbox.x + bbox.width / 2;
    const centerY = bbox.y + bbox.height / 2;

    await this.page.mouse.move(centerX, centerY);
    await this.page.mouse.down();

    // CRITICAL: Move at least 2 pixels to exceed nodeDragThreshold: 1
    // This ensures ReactFlow registers the operation as a drag, not a click
    await this.page.mouse.move(centerX + 2, centerY + 2);
    await this.page.waitForTimeout(50);

    // Move the mouse significantly to trigger the drag state and onConnectStart
    // ReactFlow requires substantial movement to recognize a drag operation
    // Move 100 pixels down and to the right with steps for smooth movement
    await this.page.mouse.move(centerX + 100, centerY + 100, { steps: 10 });

    // Wait for React Flow to process the drag start and update DOM
    await this.page.waitForTimeout(200);
  }

  /**
   * Release an edge drag operation
   * Releases the mouse button and presses Escape to cancel the connection
   */
  async releaseDrag(): Promise<void> {
    // Release mouse button first
    await this.page.mouse.up();
    // Then press Escape to cancel any pending connection state
    await this.page.keyboard.press('Escape');
  }

  /**
   * Helper method to find a React Flow node by display name
   * @param nodeName - The text displayed on the node
   * @returns Locator for the .react-flow__node container
   */
  private getNodeByName(nodeName: string): Locator {
    return this.page
      .locator(this.selectors.nodes)
      .filter({ hasText: nodeName });
  }
}
