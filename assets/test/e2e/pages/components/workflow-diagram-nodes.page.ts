import { expect } from '@playwright/test';
import type { Page, Locator } from '@playwright/test';

/**
 * Page Object Model for WorkflowDiagram node interactions
 * Handles node queries, state verification, and visual feedback during drag operations
 */
export class WorkflowDiagramNodesPage {
  protected selectors = {
    nodes: '.react-flow__node',
    jobNodes: '.react-flow__node-job',
    triggerNodes: '.react-flow__node-trigger',
    placeholderNode: '.react-flow__node-placeholder',
    nodeConnector: '[data-handleid="node-connector"]',
    validDropTarget: '[data-valid-drop-target="true"]',
    invalidDropTarget: '[data-valid-drop-target="false"]',
    activeDropTarget: '[data-active-drop-target="true"]',
  };

  constructor(protected page: Page) {}

  /**
   * Find a React Flow node container by its display name/text
   * @param name - The text displayed on the node
   * @returns Locator for the .react-flow__node container
   */
  getByName(name: string): Locator {
    return this.page.locator(this.selectors.nodes).filter({ hasText: name });
  }

  /**
   * Get a job node by its index position in the workflow
   * @param index - Zero-based index of the job node (0 = first job node)
   * @returns Locator for the job node at the specified index
   */
  getJobByIndex(index: number): Locator {
    return this.page.locator(this.selectors.jobNodes).nth(index);
  }

  /**
   * Get all workflow nodes
   */
  get all(): Locator {
    return this.page.locator(this.selectors.nodes);
  }

  /**
   * Get the current placeholder node (there should only be one at a time)
   * @returns Locator for the placeholder node
   */
  get placeholder(): Locator {
    return this.page.locator(this.selectors.placeholderNode);
  }

  /**
   * Verify that a node with the given name exists and is visible
   * @param name - The text displayed on the node
   */
  async verifyExists(name: string): Promise<void> {
    const node = this.getByName(name);
    await expect(node).toBeVisible();
  }

  /**
   * Verify the expected number of nodes are present
   * @param count - Expected number of nodes
   */
  async verifyCount(count: number): Promise<void> {
    await expect(this.all).toHaveCount(count);
  }

  /**
   * Verify a node shows valid drop state during drag
   *
   * @param name - Node display name
   */
  async verifyHasValidDropState(name: string): Promise<void> {
    const node = this.getByName(name);

    // Check for valid drop target attribute or child elements
    const isValid = await node.evaluate(el => {
      return (
        el.getAttribute('data-valid-drop-target') === 'true' ||
        el.querySelector('[data-valid-drop-target="true"]') !== null
      );
    });

    expect(isValid).toBe(true);
  }

  /**
   * Verify a node shows invalid drop state during drag
   *
   * @param name - Node display name
   */
  async verifyHasInvalidDropState(name: string): Promise<void> {
    const node = this.getByName(name);

    const isInvalid = await node.evaluate(el => {
      return (
        el.getAttribute('data-valid-drop-target') === 'false' ||
        el.querySelector('[data-valid-drop-target="false"]') !== null
      );
    });

    expect(isInvalid).toBe(true);
  }

  /**
   * Verify a node displays a specific error message
   *
   * @param name - Node display name
   * @param errorMessage - Expected error message text
   */
  async verifyShowsError(name: string, errorMessage: string): Promise<void> {
    const node = this.getByName(name);

    // Look for error text within the node
    const errorLocator = node.locator(`text="${errorMessage}"`);
    await expect(errorLocator).toBeVisible();
  }

  /**
   * Click on a workflow node by its name
   * @param name - The text displayed on the node
   */
  async click(name: string): Promise<void> {
    const node = this.getByName(name);
    await expect(node).toBeVisible();
    await node.click();
  }

  /**
   * Click on a job node by its index position
   * @param index - Zero-based index of the job node (0 = first job node)
   */
  async clickJobByIndex(index: number): Promise<void> {
    const jobNode = this.getJobByIndex(index);
    await expect(jobNode).toBeVisible();
    await jobNode.click();
  }

  /**
   * Click the plus button on a node to add a new connection
   * @param name - The text displayed on the node
   */
  async clickPlusButtonOn(name: string): Promise<void> {
    const node = this.getByName(name);
    await node.hover(); // Show the plus button

    const plusButton = this.getPlusButton(name);
    await expect(plusButton).toBeVisible();
    await plusButton.click();
  }

  /**
   * Fill in the name of the placeholder node and confirm
   * @param name - The name to give the new node
   */
  async fillPlaceholderName(name: string): Promise<void> {
    await expect(this.placeholder).toBeVisible();

    // Find the textbox within the placeholder node
    const textbox = this.placeholder.locator(
      'input[type="text"], input:not([type]), [role="textbox"]'
    );
    await expect(textbox).toBeVisible();

    await textbox.click();
    await textbox.fill(name);
    await textbox.press('Enter');
  }

  /**
   * Get the plus button (node connector) for a specific node
   * Used for adding connections between nodes
   * @param name - The text displayed on the node
   */
  private getPlusButton(name: string): Locator {
    return this.getByName(name).locator(this.selectors.nodeConnector);
  }
}
