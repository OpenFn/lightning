import { expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import { LiveViewPage } from './base';

/**
 * Page Object Model for the Projects listing page
 * Handles project-related interactions and navigation
 */
export class ProjectsPage extends LiveViewPage {
  protected selectors = {
    // Add more project-specific selectors here as needed
  };

  constructor(page: Page) {
    super(page);
  }

  /**
   * Navigate to a specific project's workflows page
   * @param projectName - The name of the project to navigate to
   */
  async navigateToProject(projectName: string): Promise<void> {
    const projectRow = this.page
      .getByRole('cell', { name: projectName })
      .locator('..');
    await this.waitForEventAttached(projectRow, 'click');
    await expect(projectRow).toBeVisible();
    await projectRow.click();
  }

  /**
   * Navigate to the projects listing page
   */
  async navigateToProjects(): Promise<void> {
    await this.clickMenuItem('Projects');
    await this.waitForConnected();
  }

  /**
   * Verify that a project with the given name is visible in the projects list
   * @param projectName - The name of the project to verify
   */
  async verifyProjectVisible(projectName: string): Promise<void> {
    await expect(
      this.page.getByRole('cell', { name: projectName })
    ).toBeVisible();
  }

  /**
   * Verify that at least one project is visible in the projects list
   */
  async verifyProjectsListNotEmpty(): Promise<void> {
    const projectCells = this.page.getByRole('cell');
    await expect(projectCells).not.toHaveCount(0);
  }
}
