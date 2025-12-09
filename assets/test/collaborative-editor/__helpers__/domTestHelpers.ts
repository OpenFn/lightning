import { screen } from '@testing-library/react';

/**
 * DOM Test Helpers
 *
 * Utilities for testing DOM elements, particularly useful when dealing with
 * accessibility patterns like aria-hidden elements used for layout purposes.
 */

/**
 * Gets the visible text element, filtering out aria-hidden elements.
 *
 * This is particularly useful when testing components that use CSS Grid
 * with invisible spacer elements (aria-hidden="true") to reserve space
 * for the longest text variant and prevent layout shifts.
 *
 * @param text - The text to search for (string or RegExp)
 * @returns The visible DOM element containing the text
 * @throws Error if no visible element is found
 *
 * @example
 * // Component renders both visible and invisible text for layout:
 * // <span aria-hidden="true">Processing</span>  <!-- invisible spacer -->
 * // <span>Run (Retry)</span>                    <!-- visible text -->
 *
 * const visibleText = getVisibleButtonText('Run (Retry)');
 * expect(visibleText).toBeInTheDocument();
 */
export function getVisibleButtonText(text: string | RegExp): HTMLElement {
  const elements = screen.getAllByText(text);
  const visible = elements.find(el => !el.closest('[aria-hidden="true"]'));
  if (!visible) {
    throw new Error(`Could not find visible element with text: ${text}`);
  }
  return visible;
}

/**
 * Queries for visible text element, filtering out aria-hidden elements.
 * Returns null if not found (non-throwing variant).
 *
 * @param text - The text to search for (string or RegExp)
 * @returns The visible DOM element or null if not found
 *
 * @example
 * const processingText = queryVisibleButtonText('Processing');
 * expect(processingText).toBeNull(); // Not in processing state
 */
export function queryVisibleButtonText(
  text: string | RegExp
): HTMLElement | null {
  const elements = screen.queryAllByText(text);
  return elements.find(el => !el.closest('[aria-hidden="true"]')) ?? null;
}
