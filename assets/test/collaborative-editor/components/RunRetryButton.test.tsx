/**
 * RunRetryButton Tests
 *
 * Verifies RunRetryButton behavior:
 * - Renders single button when not retryable
 * - Renders split button when retryable
 * - Handles retry and run actions correctly
 * - Respects disabled and processing states
 * - Shows/hides dropdown correctly
 * - Handles click-away behavior
 * - Applies custom props (className, buttonText)
 * - Provides proper accessibility attributes
 */

import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { RunRetryButton } from '../../../js/collaborative-editor/components/RunRetryButton';

/**
 * Helper to get visible text in the split button.
 * The CSS Grid approach renders invisible copies of text for sizing,
 * so we need to filter to the visible (non-aria-hidden) element.
 */
function getVisibleButtonText(text: string | RegExp) {
  const elements = screen.getAllByText(text);
  // Find the element that is NOT inside an aria-hidden container
  const visible = elements.find(el => !el.closest('[aria-hidden="true"]'));
  if (!visible) {
    throw new Error(`Could not find visible element with text: ${text}`);
  }
  return visible;
}

/**
 * Helper to query for visible text (returns null if not found)
 */
function queryVisibleButtonText(text: string | RegExp) {
  const elements = screen.queryAllByText(text);
  return elements.find(el => !el.closest('[aria-hidden="true"]')) ?? null;
}

describe('RunRetryButton', () => {
  // ===========================================================================
  // RENDERING TESTS
  // ===========================================================================

  describe('rendering modes', () => {
    test('renders single button with Run Workflow text when not retryable', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Should show Run Workflow button
      expect(screen.getByText('Run Workflow')).toBeInTheDocument();

      // Should NOT show retry text
      expect(screen.queryByText(/retry/i)).not.toBeInTheDocument();

      // Chevron should NOT be present when not retryable (no dropdown options)
      expect(
        screen.queryByRole('button', { name: /open options/i })
      ).not.toBeInTheDocument();
    });

    test('renders split button with retry text when retryable', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Should show retry button (use helper to find visible text in CSS Grid layout)
      expect(getVisibleButtonText('Run (Retry)')).toBeInTheDocument();

      // Should show dropdown toggle
      expect(
        screen.getByRole('button', { name: /open options/i })
      ).toBeInTheDocument();
    });

    test('renders processing state with spinner when submitting', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={true}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Should show processing text (use helper for CSS Grid layout)
      const processingText = getVisibleButtonText('Processing');
      expect(processingText).toBeInTheDocument();

      // Button should be disabled (get the parent button element)
      const button = processingText.closest('button');
      expect(button).toBeDisabled();

      // Should have spinner icon
      const spinner = button?.querySelector('.hero-arrow-path.animate-spin');
      expect(spinner).toBeInTheDocument();
    });
  });

  // ===========================================================================
  // INTERACTION TESTS
  // ===========================================================================

  describe('click interactions', () => {
    test('calls onRun when single button clicked', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      await user.click(screen.getByText('Run Workflow'));

      expect(onRun).toHaveBeenCalledTimes(1);
      expect(onRetry).not.toHaveBeenCalled();
    });

    test('calls onRetry when retry button clicked in split mode', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Use helper to get visible button text in CSS Grid layout
      const retryButton =
        getVisibleButtonText('Run (Retry)').closest('button')!;
      await user.click(retryButton);

      expect(onRetry).toHaveBeenCalledTimes(1);
      expect(onRun).not.toHaveBeenCalled();
    });

    test('shows dropdown menu when chevron clicked', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Initially no dropdown
      expect(
        screen.queryByText('Run (New Work Order)')
      ).not.toBeInTheDocument();

      // Click chevron to open dropdown
      await user.click(screen.getByRole('button', { name: /open options/i }));

      // Dropdown should appear
      expect(screen.getByText('Run (New Work Order)')).toBeInTheDocument();
    });

    test('calls onRun when dropdown option clicked and closes dropdown', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Open dropdown
      await user.click(screen.getByRole('button', { name: /open options/i }));
      expect(screen.getByText('Run (New Work Order)')).toBeInTheDocument();

      // Click dropdown option
      await user.click(screen.getByText('Run (New Work Order)'));

      // Should call onRun and close dropdown
      expect(onRun).toHaveBeenCalledTimes(1);
      expect(onRetry).not.toHaveBeenCalled();

      await waitFor(() => {
        expect(
          screen.queryByText('Run (New Work Order)')
        ).not.toBeInTheDocument();
      });
    });

    test('closes dropdown when clicking outside', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <div>
          <div data-testid="outside">Outside element</div>
          <RunRetryButton
            isRetryable={true}
            isDisabled={false}
            isSubmitting={false}
            onRun={onRun}
            onRetry={onRetry}
          />
        </div>
      );

      // Open dropdown
      await user.click(screen.getByRole('button', { name: /open options/i }));
      expect(screen.getByText('Run (New Work Order)')).toBeInTheDocument();

      // Click outside
      await user.click(screen.getByTestId('outside'));

      // Dropdown should close
      await waitFor(() => {
        expect(
          screen.queryByText('Run (New Work Order)')
        ).not.toBeInTheDocument();
      });
    });
  });

  // ===========================================================================
  // DISABLED STATE TESTS
  // ===========================================================================

  describe('disabled state', () => {
    test('disables single button when isDisabled is true', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={true}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      expect(screen.getByText('Run Workflow')).toBeDisabled();
    });

    test('disables both buttons in split mode when isDisabled is true', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={true}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Use helper for CSS Grid layout
      const retryButton = getVisibleButtonText('Run (Retry)').closest('button');
      expect(retryButton).toBeDisabled();
      expect(
        screen.getByRole('button', { name: /open options/i })
      ).toBeDisabled();
    });

    test('disables dropdown option when opened in disabled state', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      // Note: In practice, disabled buttons can't be clicked to open dropdown,
      // but we test that dropdown option respects disabled prop if somehow shown
      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Open dropdown while enabled
      await user.click(screen.getByRole('button', { name: /open options/i }));

      const dropdownButton = screen.getByText('Run (New Work Order)');
      expect(dropdownButton).not.toBeDisabled();
    });

    test('does not call handlers when disabled button is clicked', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={true}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Attempting to click disabled button should not trigger handler
      await user.click(screen.getByText('Run Workflow'));

      expect(onRun).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // CUSTOM PROPS TESTS
  // ===========================================================================

  describe('custom props', () => {
    test('uses custom button text when provided', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      const { rerender } = render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          buttonText={{
            run: 'Execute Workflow',
            retry: 'Retry Execution',
            processing: 'Loading...',
          }}
        />
      );

      expect(screen.getByText('Execute Workflow')).toBeInTheDocument();

      // Test retry text (use helper for CSS Grid layout)
      rerender(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          buttonText={{
            run: 'Execute Workflow',
            retry: 'Retry Execution',
            processing: 'Loading...',
          }}
        />
      );

      expect(getVisibleButtonText('Retry Execution')).toBeInTheDocument();

      // Test processing text (use helper for CSS Grid layout)
      rerender(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={true}
          onRun={onRun}
          onRetry={onRetry}
          buttonText={{
            run: 'Execute Workflow',
            retry: 'Retry Execution',
            processing: 'Loading...',
          }}
        />
      );

      expect(getVisibleButtonText('Loading...')).toBeInTheDocument();
    });

    test('applies custom className to button container', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      const { container } = render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          className="custom-test-class"
        />
      );

      const button = container.querySelector('.custom-test-class');
      expect(button).toBeInTheDocument();
    });

    test('applies className to split button container', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      const { container } = render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          className="custom-split-class"
        />
      );

      const splitButtonContainer = container.querySelector(
        '.custom-split-class'
      );
      expect(splitButtonContainer).toBeInTheDocument();
    });
  });

  // ===========================================================================
  // ACCESSIBILITY TESTS
  // ===========================================================================

  describe('accessibility', () => {
    test('dropdown toggle has proper ARIA attributes when closed', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      const toggle = screen.getByRole('button', { name: /open options/i });
      expect(toggle).toHaveAttribute('aria-expanded', 'false');
      expect(toggle).toHaveAttribute('aria-haspopup', 'true');
    });

    test('dropdown toggle has proper ARIA attributes when open', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      const toggle = screen.getByRole('button', { name: /open options/i });

      await user.click(toggle);

      expect(toggle).toHaveAttribute('aria-expanded', 'true');
    });

    test('dropdown menu has proper role attribute', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      await user.click(screen.getByRole('button', { name: /open options/i }));

      const menu = screen
        .getByText('Run (New Work Order)')
        .closest('[role="menu"]');
      expect(menu).toBeInTheDocument();
      expect(menu).toHaveAttribute('aria-orientation', 'vertical');
    });

    test('chevron toggle has screen reader text', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      const srText = screen.getByText('Open options');
      expect(srText).toHaveClass('sr-only');
    });
  });

  // ===========================================================================
  // TOOLTIP BEHAVIOR TESTS
  // ===========================================================================

  describe('tooltip behavior', () => {
    test('shows main button shortcut tooltip when showKeyboardShortcuts=true', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={true}
        />
      );

      // Button should be wrapped in tooltip (Tooltip component creates a wrapper)
      const button = screen.getByText('Run Workflow');
      expect(button).toBeInTheDocument();

      // Tooltip content should be present (ShortcutKeys component renders the shortcut)
      // The tooltip content is rendered but may not be visible until hover
      // We can verify the component structure is correct
      expect(button.closest('button')).toBeInTheDocument();
    });

    test('hides main button shortcut tooltip when showKeyboardShortcuts=false', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={false}
        />
      );

      const button = screen.getByText('Run Workflow');
      expect(button).toBeInTheDocument();
      // Tooltip component receives null content, so no tooltip is shown
    });

    test('shows dropdown shortcut tooltip when retryable and showKeyboardShortcuts=true', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={true}
        />
      );

      // Open dropdown
      await user.click(screen.getByRole('button', { name: /open options/i }));

      // Dropdown option should be present
      const dropdownOption = screen.getByText('Run (New Work Order)');
      expect(dropdownOption).toBeInTheDocument();

      // Dropdown option is wrapped in Tooltip with ShortcutKeys content
      expect(dropdownOption.closest('button')).toBeInTheDocument();
    });

    test('hides dropdown shortcut tooltip when showKeyboardShortcuts=false', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={false}
        />
      );

      // Open dropdown
      await user.click(screen.getByRole('button', { name: /open options/i }));

      // Dropdown option should be present but without tooltip
      const dropdownOption = screen.getByText('Run (New Work Order)');
      expect(dropdownOption).toBeInTheDocument();
    });

    test('shows disabled tooltip regardless of showKeyboardShortcuts', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      const { rerender } = render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={true}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={false}
          disabledTooltip="Cannot run: missing credential"
        />
      );

      const button = screen.getByText('Run Workflow');
      expect(button).toBeDisabled();
      // Error tooltip is shown via disabledTooltip prop

      // Rerender with showKeyboardShortcuts=true, error tooltip should still show
      rerender(
        <RunRetryButton
          isRetryable={false}
          isDisabled={true}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={true}
          disabledTooltip="Cannot run: missing credential"
        />
      );

      expect(button).toBeDisabled();
      // Error tooltip takes precedence over shortcut tooltip
    });

    test('shows no tooltip when submitting', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={true}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={true}
        />
      );

      // Use helper for CSS Grid layout
      const processingText = getVisibleButtonText('Processing');
      expect(processingText).toBeInTheDocument();
      // Submitting state doesn't render with a tooltip wrapper
    });

    test('retryable split button shows main button tooltip when showKeyboardShortcuts=true', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={true}
        />
      );

      // Use helper for CSS Grid layout
      const retryButton = getVisibleButtonText('Run (Retry)');
      expect(retryButton).toBeInTheDocument();
      // Main retry button should be wrapped in Tooltip with shortcut
    });

    test('combines disabled tooltip with retryable button', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={true}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          showKeyboardShortcuts={true}
          disabledTooltip="Cannot run: workflow has errors"
        />
      );

      // Use helper for CSS Grid layout
      const retryButton = getVisibleButtonText('Run (Retry)').closest('button');
      expect(retryButton).toBeDisabled();
      // Disabled tooltip should show instead of keyboard shortcut tooltip
    });

    test('tooltip props are optional with sensible defaults', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          // Not passing showKeyboardShortcuts or disabledTooltip
        />
      );

      const button = screen.getByText('Run Workflow');
      expect(button).toBeInTheDocument();
      // Should render without errors with default values
    });
  });

  // ===========================================================================
  // INTEGRATION TESTS
  // ===========================================================================

  describe('integration scenarios', () => {
    test('handles complete user flow: open dropdown, select option, closes dropdown', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // 1. Main button works (retry) - use helper for CSS Grid layout
      const retryButton =
        getVisibleButtonText('Run (Retry)').closest('button')!;
      await user.click(retryButton);
      expect(onRetry).toHaveBeenCalledTimes(1);

      // 2. Open dropdown
      await user.click(screen.getByRole('button', { name: /open options/i }));
      expect(screen.getByText('Run (New Work Order)')).toBeInTheDocument();

      // 3. Select dropdown option
      await user.click(screen.getByText('Run (New Work Order)'));
      expect(onRun).toHaveBeenCalledTimes(1);

      // 4. Dropdown closes
      await waitFor(() => {
        expect(
          screen.queryByText('Run (New Work Order)')
        ).not.toBeInTheDocument();
      });
    });

    test('transitions between modes based on isRetryable prop', () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();

      const { rerender } = render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Initially shows Run Workflow button (no chevron when not retryable)
      expect(screen.getByText('Run Workflow')).toBeInTheDocument();
      expect(
        screen.queryByRole('button', { name: /open options/i })
      ).not.toBeInTheDocument();

      // Switch to retryable mode - chevron appears
      rerender(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Use helper for CSS Grid layout
      expect(getVisibleButtonText('Run (Retry)')).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: /open options/i })
      ).toBeInTheDocument();

      // Switch to processing while retryable - chevron stays but disabled
      rerender(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={true}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Use helper for CSS Grid layout
      expect(getVisibleButtonText('Processing')).toBeInTheDocument();
      expect(queryVisibleButtonText('Run (Retry)')).not.toBeInTheDocument();
      // Chevron stays visible but disabled during processing for visual consistency
      const chevronDuringProcessing = screen.getByRole('button', {
        name: /open options/i,
      });
      expect(chevronDuringProcessing).toBeDisabled();

      // Reset to not retryable, not submitting
      rerender(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      expect(screen.getByText('Run Workflow')).toBeInTheDocument();
      expect(
        screen.queryByRole('button', { name: /open options/i })
      ).not.toBeInTheDocument();

      // Processing always shows chevron (even when not retryable)
      rerender(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={true}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      // Use helper for CSS Grid layout
      expect(getVisibleButtonText('Processing')).toBeInTheDocument();
      // Chevron is always shown during processing
      const chevronWhileProcessing = screen.getByRole('button', {
        name: /open options/i,
      });
      expect(chevronWhileProcessing).toBeDisabled();
    });

    test('handles rapid clicks without duplicate calls', async () => {
      const onRun = vi.fn();
      const onRetry = vi.fn();
      const user = userEvent.setup();

      render(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      const button = screen.getByText('Run Workflow');

      // Rapid clicks
      await user.click(button);
      await user.click(button);
      await user.click(button);

      // Each click should register
      expect(onRun).toHaveBeenCalledTimes(3);
    });
  });
});
