import { expect } from "@playwright/test";
import type { Locator, Page } from "@playwright/test";
import { WorkflowDiagramPage, JobFormPage } from "./components";
import { LiveViewPage } from "./base";

/**
 * Page Object Model for the Workflow Edit page
 * Handles interactions with the workflow editor interface
 */
export class WorkflowEditPage extends LiveViewPage {
  readonly diagram: WorkflowDiagramPage;

  protected selectors = {
    createButton: "#create_workflow_btn",
    newWorkflowPanel: "#new-workflow-panel",
    runButton: '[data-testid="run-workflow-btn"]',
    saveButton: 'button:has-text("Save")',
    topBar: '[data-testid="top-bar"]',
    unsavedChangesIndicator:
      '.absolute.-m-1.rounded-full.bg-danger-500.w-3.h-3[data-is-dirty="true"]',
    workflowNameInput: 'input[name="workflow[name]"]',
  };

  constructor(page: Page) {
    super(page);
    this.diagram = new WorkflowDiagramPage(page);
  }

  /**
   * Get a JobFormPage instance for a specific job index
   * @param jobIndex - The index of the job (0-based)
   */
  jobForm(jobIndex: number = 0): JobFormPage {
    return new JobFormPage(this.page, jobIndex);
  }

  /**
   * Save the current workflow
   */
  async clickSaveWorkflow(): Promise<void> {
    const topBar = this.page.locator(this.selectors.topBar);
    const saveButton = topBar.locator(this.selectors.saveButton);
    await expect(saveButton).toBeVisible();
    await saveButton.click();
  }

  /**
   * Set the workflow name
   * @param name - The name for the workflow
   */
  async setWorkflowName(name: string): Promise<void> {
    const nameInput = this.page.locator(this.selectors.workflowNameInput);
    await expect(nameInput).toBeVisible();
    await nameInput.fill(name);
  }

  /**
   * Assert that the unsaved changes indicator (red dot) is visible
   * This appears as a small red circle near the save button when there are unsaved changes
   */
  unsavedChangesIndicator(): Locator {
    const topBar = this.page.locator(this.selectors.topBar);
    const saveButton = topBar.locator(this.selectors.saveButton);

    // Find the save button's parent container which should contain the unsaved indicator
    const saveButtonContainer = saveButton
      .locator("..")
      .locator("..")
      .locator("..");
    const unsavedIndicator = saveButtonContainer.locator(
      this.selectors.unsavedChangesIndicator
    );

    return unsavedIndicator;
  }

  /**
   * Select workflow type from the new workflow panel
   * @param typeText - The display text of the workflow type (e.g., "Event-based Workflow")
   */
  async selectWorkflowType(typeText: string): Promise<void> {
    // Wait for the new workflow panel to be visible
    await expect(
      this.page.locator(this.selectors.newWorkflowPanel)
    ).toBeVisible();

    // Find the label containing the type text and click its associated radio button
    const label = this.page.locator("label").filter({ hasText: typeText });
    await expect(label).toBeVisible();
    await label.click();
  }

  /**
   * Click the Create button to create the selected workflow
   */
  async clickCreateWorkflow(): Promise<void> {
    await expect(this.page.locator(this.selectors.createButton)).toBeVisible();
    await this.page.locator(this.selectors.createButton).click();
  }
}
