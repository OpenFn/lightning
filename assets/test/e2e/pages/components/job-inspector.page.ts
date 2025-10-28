import type { Locator, Page } from '@playwright/test';

/**
 * Page Object Model for the Job Inspector Panel
 *
 * Handles interactions with the job inspector panel in the
 * collaborative workflow editor. This component displays and allows
 * editing of job properties including name, adaptor, and credentials.
 */
export class JobInspectorPage {
  constructor(private readonly page: Page) {}

  /**
   * Get the job inspector container element
   */
  get container(): Locator {
    return this.page.locator('[data-testid="job-inspector"]');
  }

  /**
   * Get the job name input field
   */
  get nameInput(): Locator {
    return this.container.locator('input[name="name"]');
  }

  /**
   * Get the adaptor package select dropdown
   */
  get adaptorPackageSelect(): Locator {
    return this.container.locator('select[name="adaptor_package"]');
  }

  /**
   * Get the adaptor version select dropdown
   */
  get adaptorVersionSelect(): Locator {
    return this.container.locator('select[name="adaptor"]');
  }

  /**
   * Get the credential select dropdown
   *
   * This dropdown contains both project and keychain credentials,
   * organized into optgroups.
   */
  get credentialSelect(): Locator {
    return this.container.locator('select[name="credential_id"]');
  }

  /**
   * Fill the job name field
   *
   * @param name - The job name to set
   */
  async setName(name: string): Promise<void> {
    await this.nameInput.fill(name);
  }

  /**
   * Select an adaptor package
   *
   * @param packageName - The adaptor package name (e.g.,
   * "@openfn/language-http")
   */
  async selectAdaptorPackage(packageName: string): Promise<void> {
    await this.adaptorPackageSelect.selectOption(packageName);
  }

  /**
   * Select an adaptor version
   *
   * @param version - The version to select (e.g., "latest", "1.2.3")
   */
  async selectAdaptorVersion(version: string): Promise<void> {
    await this.adaptorVersionSelect.selectOption(version);
  }

  /**
   * Select a credential by its ID
   *
   * @param credentialId - The credential ID (project_credential_id or
   * keychain_credential_id)
   */
  async selectCredential(credentialId: string): Promise<void> {
    await this.credentialSelect.selectOption(credentialId);
  }

  /**
   * Clear the credential selection
   *
   * Selects the placeholder option (empty string) to indicate no
   * credential.
   */
  async clearCredential(): Promise<void> {
    await this.credentialSelect.selectOption('');
  }

  /**
   * Get the currently selected credential ID
   *
   * @returns The selected credential ID, or empty string if none
   * selected
   */
  async getSelectedCredential(): Promise<string> {
    return await this.credentialSelect.inputValue();
  }

  /**
   * Verify the job inspector is visible
   */
  async waitForVisible(): Promise<void> {
    await this.container.waitFor({ state: 'visible' });
  }

  /**
   * Verify the job inspector is hidden
   */
  async waitForHidden(): Promise<void> {
    await this.container.waitFor({ state: 'hidden' });
  }
}
