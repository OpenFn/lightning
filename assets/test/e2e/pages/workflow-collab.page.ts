import { expect, type Locator, type Page } from '@playwright/test';
import { LiveViewPage } from './base/liveview.page';
import { JobInspectorPage } from './components/job-inspector.page';

/**
 * Page Object Model for the Collaborative Workflow Editor
 *
 * Handles interactions with the React-based collaborative editor interface.
 * This editor uses Yjs for real-time collaboration and Phoenix Channels for
 * server communication.
 */
export class WorkflowCollaborativePage extends LiveViewPage {
  protected selectors = {
    // Main container
    collaborativeEditor: '[data-testid="collaborative-editor"]',

    // Connection status (via CollaborationWidget)
    syncStatus: 'text=Synced',
    connectedStatus: 'text=Connected',

    // Error indicators - use specific error UI components, not generic text
    // Note: We look for actual error/alert components, not workflow content
    errorAlert: '[role="alert"] >> text=/error/i',
    socketError: 'text=/socket (error|disconnected)/i',
  };

  /**
   * Get the job inspector page object for interacting with job
   * properties.
   *
   * @returns JobInspectorPage instance for the current page
   */
  get jobInspector(): JobInspectorPage {
    return new JobInspectorPage(this.page);
  }

  /**
   * Wait for the collaborative editor React component to load and render.
   *
   * This method waits for:
   * 1. Main container element to be visible
   * 2. Network to settle (React app fully loaded)
   *
   * It does NOT wait for sync status - use waitForSynced() for that.
   */
  async waitForReactComponentLoaded(): Promise<void> {
    // Wait for main container
    const container = this.page.locator(this.selectors.collaborativeEditor);
    await expect(container).toBeVisible({ timeout: 10000 });

    // Wait for React hydration to complete
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for the collaborative editor to reach "Synced" state.
   *
   * This indicates that:
   * - Phoenix Socket is connected
   * - Yjs Phoenix Channel is connected
   * - Y.Doc has synced with server
   * - Workflow data is loaded and ready
   */
  async waitForSynced(): Promise<void> {
    const syncStatus = this.page.locator(this.selectors.syncStatus);
    await expect(syncStatus).toBeVisible({ timeout: 15000 });
  }

  /**
   * Verify that no error states are displayed in the collaborative editor.
   *
   * Checks for:
   * - Alert components with error messages (role="alert")
   * - Socket connection errors or disconnection messages
   *
   * Note: Uses specific UI component selectors to avoid false positives
   * from workflow content (e.g., job names containing "failed").
   */
  async verifyNoErrors(): Promise<void> {
    // Check for error alerts (actual error UI components)
    const errorAlert = this.page.locator(this.selectors.errorAlert);
    await expect(errorAlert).not.toBeVisible();

    // Check for socket errors or disconnection
    const socketError = this.page.locator(this.selectors.socketError);
    await expect(socketError).not.toBeVisible();
  }

  /**
   * Get the main collaborative editor container element.
   */
  get container(): Locator {
    return this.page.locator(this.selectors.collaborativeEditor);
  }

  /**
   * Get the save workflow button
   */
  get saveButton(): Locator {
    return this.page.locator('[data-testid="save-workflow-button"]');
  }

  /**
   * Click the save workflow button
   */
  async saveWorkflow(): Promise<void> {
    await this.saveButton.click();
  }

  /**
   * Verify the workflow URL matches the expected components.
   *
   * Builds a URL from the provided components and verifies the page is on
   * that URL. This makes it explicit what URL structure is being validated.
   *
   * @param options - URL components
   * @param options.projectId - Project ID
   * @param options.workflowId - Workflow ID
   * @param options.path - Path suffix (e.g., '/legacy', '/edit')
   * @param options.query - Optional query parameters
   * @param options.hash - Optional URL hash
   *
   * @example
   * ```typescript
   * // Verify collaborative editor URL
   * await page.verifyUrl({
   *   projectId: '123',
   *   workflowId: '456',
   *   path: '/legacy'
   * });
   *
   * // With query params and hash
   * await page.verifyUrl({
   *   projectId: '123',
   *   workflowId: '456',
   *   path: '/edit',
   *   query: { step: '2' },
   *   hash: 'job-abc'
   * });
   * ```
   */
  async verifyUrl(options: {
    projectId: string;
    workflowId: string;
    path: string;
    query?: Record<string, string>;
    hash?: string;
  }): Promise<void> {
    let url = `/projects/${options.projectId}/w/${options.workflowId}${options.path}`;

    if (options.query) {
      const queryString = new URLSearchParams(options.query).toString();
      url += `?${queryString}`;
    }

    if (options.hash) {
      url += `#${options.hash}`;
    }

    await expect(this.page).toHaveURL(url);
  }
}
