import { expect } from '@playwright/test';
import type { Page, Locator } from '@playwright/test';

/**
 * Base class for Phoenix LiveView pages
 * Provides common functionality for LiveView interactions
 */
export abstract class LiveViewPage {
  protected baseSelectors = {
    phoenixMain: 'div[data-phx-main]',
    flashMessage: '[id^="flash-"][phx-hook="Flash"]',
  };

  constructor(protected page: Page) {}

  async clickMenuItem(itemText: string): Promise<void> {
    await this.page
      .locator('#side-menu')
      .getByRole('link', { name: itemText })
      .click();
  }

  /**
   * Wait for the Phoenix LiveView connection to be established
   *
   * This is important when navigating between different LiveView sessions,
   * such as moving from a project view to a workflow edit view, which requires
   * a new WebSocket connection. Waiting for the "phx-connected" class ensures
   * that the LiveView is ready to handle user interactions.
   */
  async waitForConnected(): Promise<void> {
    const locator = this.page.locator(this.baseSelectors.phoenixMain);
    await expect(locator).toBeVisible();
    await expect(locator).toContainClass('phx-connected');
  }

  /**
   * Assert that a flash message with the given text is visible
   * @param text - The text content to look for in the flash message
   */
  async expectFlashMessage(text: string): Promise<void> {
    const flashMessage = this.page
      .locator(this.baseSelectors.flashMessage)
      .filter({ hasText: text });
    await expect(flashMessage).toBeVisible();
  }

  /**
   * Wait for the Phoenix LiveView WebSocket to be settled
   *
   * This _hopefully_ ensures that any pending messages have been processed.
   *
   * NOTE: still needs to be verified.
   */
  async waitForSocketSettled(): Promise<void> {
    await this.page.waitForFunction(() => {
      return new Promise(resolve => {
        window.liveSocket.socket.ping(resolve);
      });
    });
  }

  /**
   * Wait for Phoenix LiveView event handlers to be attached to an element
   *
   * This is particularly useful when moving between LiveView sessions, where
   * a new WebSocket connection is established and event handlers may not
   * be immediately attached to elements.
   *
   * @param locator - Playwright locator for the element
   * @param eventType - The type of event to wait for (e.g., 'click')
   * @param timeout - Timeout in milliseconds (default: 5000)
   */
  async waitForEventAttached(
    locator: Locator,
    eventType: string = 'click',
    timeout: number = 5000
  ): Promise<void> {
    // First get the element selector to use in waitForFunction
    const elementHandle = await locator.elementHandle();
    if (!elementHandle) {
      throw new Error('Element not found for event attachment check');
    }

    await this.page.waitForFunction(
      ({ elementHandle, eventType }) => {
        // Check for Phoenix LiveView click handler
        if (eventType === 'click' && elementHandle.hasAttribute('phx-click')) {
          // For Phoenix LiveView, check if the main container is connected
          const isPhxConnected = document
            .querySelector('[data-phx-main]')
            ?.classList.contains('phx-connected');
          return isPhxConnected;
        }

        // For other event types, check for actual event listeners
        const listeners = (elementHandle as any).getEventListeners?.() || {};
        return listeners[eventType] && listeners[eventType].length > 0;
      },
      { elementHandle, eventType },
      { timeout }
    );
  }
}
