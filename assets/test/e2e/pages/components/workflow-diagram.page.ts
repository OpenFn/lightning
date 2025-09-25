import { expect } from "@playwright/test";
import type { Page, Locator } from "@playwright/test";
import { LiveViewPage } from "../base";

/**
 * Page Object Model for the WorkflowDiagram React component
 * Handles interactions with React Flow canvas and workflow nodes
 */
export class WorkflowDiagramPage extends LiveViewPage {
  protected selectors = {
    reactFlow: ".react-flow",
    viewport: ".react-flow__viewport",
    nodes: ".react-flow__node",
    jobNodes: ".react-flow__node-job",
    placeholderNode: ".react-flow__node-placeholder",
    nodeWithDataAttribute: '[data-a-node="true"]',
    nodeConnector: '[data-handleid="node-connector"]',
    fitViewButton: '.react-flow__controls-button[data-tooltip="Fit view"]',
  };

  constructor(page: Page) {
    super(page);
  }

  /**
   * Find a workflow node by its display name/text
   * @param nodeName - The text displayed on the node (e.g., "Fetch User Data")
   * @returns Locator for the node's group container
   */
  getNodeByName(nodeName: string): Locator {
    return this.page
      .locator(this.selectors.nodeWithDataAttribute)
      .filter({ hasText: nodeName });
  }

  /**
   * Find a React Flow node container by its display name/text
   * @param nodeName - The text displayed on the node
   * @returns Locator for the .react-flow__node container
   */
  getReactFlowNodeByName(nodeName: string): Locator {
    return this.page
      .locator(this.selectors.nodes)
      .filter({ hasText: nodeName });
  }

  /**
   * Click on a workflow node by its name
   * @param nodeName - The text displayed on the node
   */
  async clickNode(nodeName: string): Promise<void> {
    const node = this.getNodeByName(nodeName);
    await expect(node).toBeVisible();
    await node.click();
  }

  /**
   * Verify that a node with the given name exists and is visible
   * @param nodeName - The text displayed on the node
   */
  async verifyNodeExists(nodeName: string): Promise<void> {
    const node = this.getNodeByName(nodeName);
    await expect(node).toBeVisible();
  }

  /**
   * Get the plus button (node connector) for a specific node
   * Used for adding connections between nodes
   * @param nodeName - The text displayed on the node
   */
  private getNodePlusButton(nodeName: string): Locator {
    return this.page.locator(
      `${this.selectors.nodeWithDataAttribute}:has-text("${nodeName}") ${this.selectors.nodeConnector}`
    );
  }

  /**
   * Click the plus button on a node to add a new connection
   * @param nodeName - The text displayed on the node
   */
  async clickNodePlusButtonOn(nodeName: string): Promise<void> {
    const node = this.getNodeByName(nodeName);
    await node.hover(); // Show the plus button

    const plusButton = this.getNodePlusButton(nodeName);
    await expect(plusButton).toBeVisible();
    await plusButton.click();
  }

  /**
   * Get a job node by its index position in the workflow
   * @param index - Zero-based index of the job node (0 = first job node)
   * @returns Locator for the job node at the specified index
   */
  getJobNodeByIndex(index: number): Locator {
    return this.page.locator(this.selectors.jobNodes).nth(index);
  }

  /**
   * Click on a job node by its index position
   * @param index - Zero-based index of the job node (0 = first job node)
   */
  async clickJobNodeByIndex(index: number): Promise<void> {
    const jobNode = this.getJobNodeByIndex(index);
    await expect(jobNode).toBeVisible();
    await jobNode.click();
  }

  /**
   * Get the current placeholder node (there should only be one at a time)
   * @returns Locator for the placeholder node
   */
  getPlaceholderNode(): Locator {
    return this.page.locator(this.selectors.placeholderNode);
  }

  /**
   * Fill in the name of the placeholder node and confirm
   * @param nodeName - The name to give the new node
   */
  async fillPlaceholderNodeName(nodeName: string): Promise<void> {
    const placeholderNode = this.getPlaceholderNode();
    await expect(placeholderNode).toBeVisible();

    // Find the textbox within the placeholder node
    const textbox = placeholderNode.locator(
      'input[type="text"], input:not([type]), [role="textbox"]'
    );
    await expect(textbox).toBeVisible();

    await textbox.fill(nodeName);
    await textbox.press("Enter");
  }

  /**
   * Set up a listener for Phoenix LiveView page loading completion and perform an action
   * The listener is set up before the action to avoid context destruction issues
   * @param action - Function to execute after setting up the listener
   */
  async waitForPhoenixPageLoadingStop(
    action: () => Promise<void>
  ): Promise<void> {
    // Set up the listener and perform the action in the same evaluation context
    await this.page.evaluate(async () => {
      return new Promise<void>(resolve => {
        const handler = () => {
          window.removeEventListener("phx:page-loading-stop", handler);
          resolve();
        };
        window.addEventListener("phx:page-loading-stop", handler);
      });
    });

    // Now perform the action that will trigger the navigation/loading
    await action();

    // Wait a bit for the event to fire
    await this.page.waitForTimeout(100);
  }

  /**
   * Click the "Fit view" button in React Flow controls
   * Centers and fits all nodes in the viewport
   */
  async clickFitView(): Promise<void> {
    const fitViewButton = this.page.locator(this.selectors.fitViewButton);
    await expect(fitViewButton).toBeVisible();
    await fitViewButton.click();
  }
}
