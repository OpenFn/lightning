import { expect } from "@playwright/test";
import type { Page, Locator } from "@playwright/test";
import { LiveViewPage } from "../base/liveview.page";

/**
 * Page Object Model for WorkflowDiagram edge interactions
 * Handles edge queries, drag-and-drop operations, and edge-related verifications
 */
export class WorkflowDiagramEdgesPage extends LiveViewPage {
  protected selectors = {
    edges: ".react-flow__edge",
    edgePath: ".react-flow__edge-path",
    nodeConnector: '[data-handleid="node-connector"]',
    nodes: ".react-flow__node",
  };

  constructor(page: Page) {
    super(page);
  }

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
   * This performs the complete drag operation using mouse events
   *
   * @param sourceName - Source node display name
   * @param targetName - Target node display name
   */
  async dragFromTo(sourceName: string, targetName: string): Promise<void> {
    const sourceNode = this.getNodeByName(sourceName);
    const targetNode = this.getNodeByName(targetName);

    // Hover over source to show plus button
    await sourceNode.hover();

    const plusButton = sourceNode.locator(this.selectors.nodeConnector);
    await expect(plusButton).toBeVisible();

    // Get bounding boxes for drag operation
    const sourceBbox = await sourceNode.boundingBox();
    const targetBbox = await targetNode.boundingBox();

    if (!sourceBbox || !targetBbox) {
      throw new Error("Could not get bounding boxes for drag operation");
    }

    // Start drag from plus button
    await plusButton.hover();
    await this.page.mouse.down();

    // Move mouse to target node center
    const targetX = targetBbox.x + targetBbox.width / 2;
    const targetY = targetBbox.y + targetBbox.height / 2;

    await this.page.mouse.move(targetX, targetY, { steps: 10 });

    // Small delay to ensure React Flow registers the hover
    await this.page.waitForTimeout(200);

    // Drop
    await this.page.mouse.up();
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
      throw new Error("Could not get plus button bounding box");
    }

    // Start drag by moving to button center and pressing mouse down
    const centerX = bbox.x + bbox.width / 2;
    const centerY = bbox.y + bbox.height / 2;

    await this.page.mouse.move(centerX, centerY);
    await this.page.mouse.down();

    // Move the mouse significantly to trigger the drag state and onConnectStart
    // ReactFlow requires substantial movement to recognize a drag operation
    // Move 100 pixels down and to the right
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
    await this.page.keyboard.press("Escape");
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
