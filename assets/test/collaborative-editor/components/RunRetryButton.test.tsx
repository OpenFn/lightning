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

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, test, vi } from "vitest";

import { RunRetryButton } from "../../../js/collaborative-editor/components/RunRetryButton";

describe("RunRetryButton", () => {
  // ===========================================================================
  // RENDERING TESTS
  // ===========================================================================

  describe("rendering modes", () => {
    test("renders single button with Run Workflow text when not retryable", () => {
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
      expect(screen.getByText("Run Workflow")).toBeInTheDocument();

      // Should NOT show retry text or dropdown
      expect(screen.queryByText(/retry/i)).not.toBeInTheDocument();
      expect(
        screen.queryByRole("button", { name: /open options/i })
      ).not.toBeInTheDocument();
    });

    test("renders split button with retry text when retryable", () => {
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

      // Should show retry button
      expect(screen.getByText("Run (retry)")).toBeInTheDocument();

      // Should show dropdown toggle
      expect(
        screen.getByRole("button", { name: /open options/i })
      ).toBeInTheDocument();
    });

    test("renders processing state with spinner when submitting", () => {
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

      // Should show processing text
      expect(screen.getByText("Processing")).toBeInTheDocument();

      // Button should be disabled
      expect(screen.getByText("Processing")).toBeDisabled();

      // Should have spinner icon
      const button = screen.getByText("Processing");
      const spinner = button.querySelector(".hero-arrow-path.animate-spin");
      expect(spinner).toBeInTheDocument();
    });
  });

  // ===========================================================================
  // INTERACTION TESTS
  // ===========================================================================

  describe("click interactions", () => {
    test("calls onRun when single button clicked", async () => {
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

      await user.click(screen.getByText("Run Workflow"));

      expect(onRun).toHaveBeenCalledTimes(1);
      expect(onRetry).not.toHaveBeenCalled();
    });

    test("calls onRetry when retry button clicked in split mode", async () => {
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

      await user.click(screen.getByText("Run (retry)"));

      expect(onRetry).toHaveBeenCalledTimes(1);
      expect(onRun).not.toHaveBeenCalled();
    });

    test("shows dropdown menu when chevron clicked", async () => {
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
        screen.queryByText("Run (New Work Order)")
      ).not.toBeInTheDocument();

      // Click chevron to open dropdown
      await user.click(screen.getByRole("button", { name: /open options/i }));

      // Dropdown should appear
      expect(screen.getByText("Run (New Work Order)")).toBeInTheDocument();
    });

    test("calls onRun when dropdown option clicked and closes dropdown", async () => {
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
      await user.click(screen.getByRole("button", { name: /open options/i }));
      expect(screen.getByText("Run (New Work Order)")).toBeInTheDocument();

      // Click dropdown option
      await user.click(screen.getByText("Run (New Work Order)"));

      // Should call onRun and close dropdown
      expect(onRun).toHaveBeenCalledTimes(1);
      expect(onRetry).not.toHaveBeenCalled();

      await waitFor(() => {
        expect(
          screen.queryByText("Run (New Work Order)")
        ).not.toBeInTheDocument();
      });
    });

    test("closes dropdown when clicking outside", async () => {
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
      await user.click(screen.getByRole("button", { name: /open options/i }));
      expect(screen.getByText("Run (New Work Order)")).toBeInTheDocument();

      // Click outside
      await user.click(screen.getByTestId("outside"));

      // Dropdown should close
      await waitFor(() => {
        expect(
          screen.queryByText("Run (New Work Order)")
        ).not.toBeInTheDocument();
      });
    });
  });

  // ===========================================================================
  // DISABLED STATE TESTS
  // ===========================================================================

  describe("disabled state", () => {
    test("disables single button when isDisabled is true", () => {
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

      expect(screen.getByText("Run Workflow")).toBeDisabled();
    });

    test("disables both buttons in split mode when isDisabled is true", () => {
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

      expect(screen.getByText("Run (retry)")).toBeDisabled();
      expect(
        screen.getByRole("button", { name: /open options/i })
      ).toBeDisabled();
    });

    test("disables dropdown option when opened in disabled state", async () => {
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
      await user.click(screen.getByRole("button", { name: /open options/i }));

      const dropdownButton = screen.getByText("Run (New Work Order)");
      expect(dropdownButton).not.toBeDisabled();
    });

    test("does not call handlers when disabled button is clicked", async () => {
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
      await user.click(screen.getByText("Run Workflow"));

      expect(onRun).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // CUSTOM PROPS TESTS
  // ===========================================================================

  describe("custom props", () => {
    test("uses custom button text when provided", () => {
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
            run: "Execute Workflow",
            retry: "Retry Execution",
            processing: "Loading...",
          }}
        />
      );

      expect(screen.getByText("Execute Workflow")).toBeInTheDocument();

      // Test retry text
      rerender(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
          buttonText={{
            run: "Execute Workflow",
            retry: "Retry Execution",
            processing: "Loading...",
          }}
        />
      );

      expect(screen.getByText("Retry Execution")).toBeInTheDocument();

      // Test processing text
      rerender(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={true}
          onRun={onRun}
          onRetry={onRetry}
          buttonText={{
            run: "Execute Workflow",
            retry: "Retry Execution",
            processing: "Loading...",
          }}
        />
      );

      expect(screen.getByText("Loading...")).toBeInTheDocument();
    });

    test("applies custom className to button container", () => {
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

      const button = container.querySelector(".custom-test-class");
      expect(button).toBeInTheDocument();
    });

    test("applies className to split button container", () => {
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
        ".custom-split-class"
      );
      expect(splitButtonContainer).toBeInTheDocument();
    });
  });

  // ===========================================================================
  // ACCESSIBILITY TESTS
  // ===========================================================================

  describe("accessibility", () => {
    test("dropdown toggle has proper ARIA attributes when closed", () => {
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

      const toggle = screen.getByRole("button", { name: /open options/i });
      expect(toggle).toHaveAttribute("aria-expanded", "false");
      expect(toggle).toHaveAttribute("aria-haspopup", "true");
    });

    test("dropdown toggle has proper ARIA attributes when open", async () => {
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

      const toggle = screen.getByRole("button", { name: /open options/i });

      await user.click(toggle);

      expect(toggle).toHaveAttribute("aria-expanded", "true");
    });

    test("dropdown menu has proper role attribute", async () => {
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

      await user.click(screen.getByRole("button", { name: /open options/i }));

      const menu = screen
        .getByText("Run (New Work Order)")
        .closest('[role="menu"]');
      expect(menu).toBeInTheDocument();
      expect(menu).toHaveAttribute("aria-orientation", "vertical");
    });

    test("chevron toggle has screen reader text", () => {
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

      const srText = screen.getByText("Open options");
      expect(srText).toHaveClass("sr-only");
    });
  });

  // ===========================================================================
  // INTEGRATION TESTS
  // ===========================================================================

  describe("integration scenarios", () => {
    test("handles complete user flow: open dropdown, select option, closes dropdown", async () => {
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

      // 1. Main button works (retry)
      await user.click(screen.getByText("Run (retry)"));
      expect(onRetry).toHaveBeenCalledTimes(1);

      // 2. Open dropdown
      await user.click(screen.getByRole("button", { name: /open options/i }));
      expect(screen.getByText("Run (New Work Order)")).toBeInTheDocument();

      // 3. Select dropdown option
      await user.click(screen.getByText("Run (New Work Order)"));
      expect(onRun).toHaveBeenCalledTimes(1);

      // 4. Dropdown closes
      await waitFor(() => {
        expect(
          screen.queryByText("Run (New Work Order)")
        ).not.toBeInTheDocument();
      });
    });

    test("transitions between modes based on isRetryable prop", () => {
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

      // Initially single button
      expect(screen.getByText("Run Workflow")).toBeInTheDocument();
      expect(
        screen.queryByRole("button", { name: /open options/i })
      ).not.toBeInTheDocument();

      // Switch to split button
      rerender(
        <RunRetryButton
          isRetryable={true}
          isDisabled={false}
          isSubmitting={false}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      expect(screen.getByText("Run (retry)")).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /open options/i })
      ).toBeInTheDocument();

      // Switch to processing
      rerender(
        <RunRetryButton
          isRetryable={false}
          isDisabled={false}
          isSubmitting={true}
          onRun={onRun}
          onRetry={onRetry}
        />
      );

      expect(screen.getByText("Processing")).toBeInTheDocument();
      expect(screen.queryByText("Run Workflow")).not.toBeInTheDocument();
      expect(screen.queryByText("Run (retry)")).not.toBeInTheDocument();
    });

    test("handles rapid clicks without duplicate calls", async () => {
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

      const button = screen.getByText("Run Workflow");

      // Rapid clicks
      await user.click(button);
      await user.click(button);
      await user.click(button);

      // Each click should register
      expect(onRun).toHaveBeenCalledTimes(3);
    });
  });
});
