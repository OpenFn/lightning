import { expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import { LiveViewPage } from './base';

/**
 * Page Object Model for the Workflows listing page
 * Handles workflow creation and listing interactions
 */
export class WorkflowsPage extends LiveViewPage {
  protected selectors = {
    createNewWorkflowButton: 'button:has-text("Create new workflow")',
  };

  constructor(page: Page) {
    super(page);
  }

  /**
   * Click the "Create new workflow" button to navigate to the workflow creation page
   */
  async clickNewWorkflow(): Promise<void> {
    // Wait for LiveView connection
    await this.waitForConnected();

    const createButton = this.page.locator(
      this.selectors.createNewWorkflowButton
    );
    await expect(createButton).toBeVisible();

    // Wait for Phoenix event handlers to be attached to the button
    await this.waitForEventAttached(createButton, 'click');

    // Click the button to navigate to workflow creation page
    await createButton.click();
  }

  /**
   * Navigate to a workflow by clicking its row in the workflows list
   *
   * @param workflowName - The name of the workflow to navigate to
   */
  async navigateToWorkflow(workflowName: string): Promise<void> {
    // Wait for LiveView connection
    await this.waitForConnected();

    // Find the <tr> element that contains the workflow label
    // The <tr> has phx-click and contains an element with aria-label matching the workflow name
    const workflowRow = this.page.locator('tr').filter({
      has: this.page.getByLabel(workflowName),
    });

    await expect(workflowRow).toBeVisible();

    // Wait for Phoenix event handlers to be attached to the row
    await this.waitForEventAttached(workflowRow, 'click');

    // Click the row to navigate to workflow edit page
    await workflowRow.click();

    // Wait for navigation to complete
    await this.page.waitForLoadState('networkidle');
  }
}
