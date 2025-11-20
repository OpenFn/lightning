import { expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import { WorkflowDiagramEdgesPage } from './workflow-diagram-edges.page';
import { WorkflowDiagramNodesPage } from './workflow-diagram-nodes.page';

/**
 * Page Object Model for the WorkflowDiagram React component
 * Handles interactions with React Flow canvas and workflow nodes
 */
export class WorkflowDiagramPage {
  // Sub-POMs for edges and nodes
  readonly edges: WorkflowDiagramEdgesPage;
  readonly nodes: WorkflowDiagramNodesPage;

  protected selectors = {
    reactFlow: '.react-flow',
    viewport: '.react-flow__viewport',
    fitViewButton: '.react-flow__controls-button[data-tooltip="Fit view"]',
  };

  constructor(protected page: Page) {
    this.edges = new WorkflowDiagramEdgesPage(page);
    this.nodes = new WorkflowDiagramNodesPage(page);
  }

  /**
   * Verify that React Flow is present and working
   */
  async verifyReactFlowPresent(): Promise<void> {
    const reactFlowContainer = this.page.locator(this.selectors.reactFlow);
    await expect(reactFlowContainer).toBeVisible();

    const reactFlowViewport = this.page.locator(this.selectors.viewport);
    await expect(reactFlowViewport).toBeVisible();
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
