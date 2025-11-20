import type { Page, Locator } from '@playwright/test';

/**
 * Page Object Model for the Job Form component
 * Handles interactions with the job configuration form
 */
export class JobFormPage {
  private jobIndex: number;

  protected selectors = {
    workflowForm: '#workflow-form',
    workflowFormHeader: '#workflow-form div',
    closeNodePanelButton: '[data-testid="CloseNodePanelViaEscape"]',
  };

  constructor(
    protected page: Page,
    jobIndex: number = 0
  ) {
    this.jobIndex = jobIndex;
    this.selectors.workflowForm = `[data-testid='job-pane-${this.jobIndex}']`;
  }

  /**
   * Get the dynamic selector for a job field based on the job index
   */
  private getJobFieldSelector(fieldName: string): string {
    return [
      `select[name="workflow[jobs][${this.jobIndex}][${fieldName}]"]`,
      `input[name="workflow[jobs][${this.jobIndex}][${fieldName}]"]`,
      `textarea[name="workflow[jobs][${this.jobIndex}][${fieldName}]"]`,
    ].join(',');
  }

  /**
   * Get the workflow form container
   *
   * NOTE: form elements are never visible, don't use toBeVisible(); rather
   * use toBeAttached() to check it's in the DOM. Or check for specific fields
   * to be visible.
   */
  get workflowForm(): Locator {
    return this.page.locator(this.selectors.workflowForm);
  }

  /**
   * Get the workflow form header
   */
  get header(): Locator {
    return this.page.locator(`${this.selectors.workflowForm} div.font-bold`);
  }

  /**
   * Get the close node panel button
   */
  get closeNodePanelButton(): Locator {
    return this.page.locator(this.selectors.closeNodePanelButton);
  }

  /**
   * Get the adaptor select dropdown
   */
  get adaptorSelect(): Locator {
    return this.page.locator(`select[name="adaptor_picker[adaptor_name]"]`);
  }

  /**
   * Get the version select dropdown
   */
  get versionSelect(): Locator {
    return this.page.locator(this.getJobFieldSelector('adaptor'));
  }

  /**
   * Get the job name input
   */
  get nameInput(): Locator {
    return this.page.locator(this.getJobFieldSelector('name'));
  }
}
