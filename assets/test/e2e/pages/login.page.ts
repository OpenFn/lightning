import { expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import { LiveViewPage } from './base';

/**
 * Page Object Model for the Login page
 * Handles user authentication interactions
 */
export class LoginPage extends LiveViewPage {
  protected selectors = {
    loginForm: '#login form',
    emailInput: 'input[name="user[email]"]',
    passwordInput: 'input[name="user[password]"]',
    submitButton: 'button[type="submit"]',
    loginButton: 'button:has-text("Log in")',
  };

  constructor(page: Page) {
    super(page);
  }

  /**
   * Check if the login form is currently visible
   */
  async isLoginFormVisible(): Promise<boolean> {
    const loginForm = this.page.locator(this.selectors.loginForm);
    return await loginForm.isVisible();
  }

  /**
   * Fill in login credentials and submit the form
   * @param email - User email address
   * @param password - User password
   */
  async login(email: string, password: string): Promise<void> {
    await expect(this.page.locator(this.selectors.loginForm)).toBeVisible();

    await this.page.locator(this.selectors.emailInput).fill(email);
    await this.page.locator(this.selectors.passwordInput).fill(password);

    // Try both possible button selectors
    const submitButton = this.page.locator(this.selectors.submitButton);
    const loginButton = this.page.locator(this.selectors.loginButton);

    if (await submitButton.isVisible()) {
      await submitButton.click();
    } else {
      await loginButton.click();
    }

    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Perform login if login form is visible, otherwise skip
   * This is useful for tests that might start on different pages
   * @param email - User email address
   * @param password - User password
   */
  async loginIfNeeded(email: string, password: string): Promise<void> {
    if (await this.isLoginFormVisible()) {
      await this.login(email, password);
    }
  }
}
