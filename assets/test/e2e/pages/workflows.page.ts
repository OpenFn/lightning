import { expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import { LiveViewPage } from "./base";

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
    await this.waitForEventAttached(createButton, "click");

    // Click the button to navigate to workflow creation page
    await createButton.click();
  }

  async navigateToWorkflow(workflowName: string): Promise<void> {
    await this.page
      .getByRole("cell", { name: new RegExp(workflowName) })
      .click();
  }

  /**
   * Navigate to a specific project's workflows page
   * TODO: move this to a ProjectsPage class when we have one
   * @param projectName - The name of the project to navigate to
   */
  async navigateToProject(projectName: string): Promise<void> {
    const projectRow = this.page
      .getByRole("cell", { name: projectName })
      .locator("..");
    await this.waitForEventAttached(projectRow, "click");
    await expect(projectRow).toBeVisible();
    await projectRow.click();
  }
}
