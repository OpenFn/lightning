/**
 * MiniHistory Component Tests
 *
 * Tests the MiniHistory component behavior including:
 * - Collapsed/expanded states
 * - Empty state display
 * - Work order and run list rendering
 * - Status pill colors and states
 * - User interactions (collapse, expand, selection)
 * - Navigation behavior
 *
 * Test Philosophy:
 * - Group related assertions to test complete behaviors
 * - Focus on user-facing behavior, not implementation details
 * - Use descriptive test names that explain the behavior being tested
 */

import { describe, expect, test, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";
import MiniHistory from "../../../../js/collaborative-editor/components/diagram/MiniHistory";
import {
  createMockWorkOrder,
  mockHistoryList,
  mockMultiRunWorkOrder,
  mockSelectedWorkOrder,
  allRunStates,
  createWorkOrdersForAllStates,
} from "../../fixtures/historyData";

// Mock date-fns formatRelative to avoid locale issues in tests
vi.mock("date-fns", async () => {
  const actual = await vi.importActual("date-fns");
  return {
    ...actual,
    formatRelative: vi.fn(() => "2 hours ago"),
  };
});

// Mock the hooks module to avoid Phoenix LiveView dependencies in tests
vi.mock("../../../../js/hooks", () => ({
  relativeLocale: {},
}));

// Mock window.location for navigation tests
const mockLocation = {
  href: "http://localhost/projects/test-project-id/w/test-workflow-id",
  pathname: "/projects/test-project-id/w/test-workflow-id",
};

Object.defineProperty(window, "location", {
  value: mockLocation,
  writable: true,
});

describe("MiniHistory", () => {
  beforeEach(() => {
    // Reset location before each test
    mockLocation.href =
      "http://localhost/projects/test-project-id/w/test-workflow-id";
    mockLocation.pathname = "/projects/test-project-id/w/test-workflow-id";
  });

  // ==========================================================================
  // COLLAPSED STATE
  // ==========================================================================

  describe("renders correctly in collapsed state", () => {
    test("displays minimal UI with expand button and view history link", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={true}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Header shows "View History" text when collapsed
      expect(screen.getByText("View History")).toBeInTheDocument();

      // View full history button is present
      const viewHistoryButton = screen.getByRole("button", {
        name: /View full history for this workflow/i,
      });
      expect(viewHistoryButton).toBeInTheDocument();

      // Chevron is present (right-pointing chevron for collapsed state)
      const chevronIcon = screen
        .getByText("View History")
        .closest("div")
        ?.querySelector("span[class*='chevron']");
      expect(chevronIcon).toBeInTheDocument();

      // Work order list is hidden
      expect(screen.queryByText(/e2107d46/)).not.toBeInTheDocument();
    });

    test("toggles when header is clicked", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={true}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Click anywhere in the header section
      const header = screen.getByText("View History").parentElement;
      fireEvent.click(header!);

      expect(onCollapseHistory).toHaveBeenCalledTimes(1);
    });
  });

  // ==========================================================================
  // EXPANDED STATE
  // ==========================================================================

  describe("renders correctly in expanded state", () => {
    test("displays full UI with work order list", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Header shows "Recent History" when expanded
      expect(screen.getByText("Recent History")).toBeInTheDocument();

      // Chevron is present (left-pointing chevron for expanded state)
      const chevronIcon = screen
        .getByText("Recent History")
        .closest("div")
        ?.querySelector("span[class*='chevron']");
      expect(chevronIcon).toBeInTheDocument();

      // Work order list is visible - check for truncated work order IDs
      expect(screen.getByText(/e2107d46/)).toBeInTheDocument();
      expect(screen.getByText(/547d11ad/)).toBeInTheDocument();
    });

    test("collapses when header is clicked", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Click the header element
      const header = screen.getByText("Recent History").parentElement;
      fireEvent.click(header!);

      expect(onCollapseHistory).toHaveBeenCalledTimes(1);
    });
  });

  // ==========================================================================
  // EMPTY STATE
  // ==========================================================================

  describe("displays empty state correctly", () => {
    test("shows helpful message when no history is available", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Empty state displays icon and message
      expect(screen.getByText("No related history")).toBeInTheDocument();
      expect(
        screen.getByText(/Why not run it a few times to see some history?/i)
      ).toBeInTheDocument();

      // Empty state icon is present
      const emptyStateIcon = screen
        .getByText("No related history")
        .closest("div")
        ?.querySelector("span.hero-rectangle-stack");
      expect(emptyStateIcon).toBeInTheDocument();
    });

    test("does not display work order list when empty", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // No work order IDs should be visible
      expect(screen.queryByText(/e2107d46/)).not.toBeInTheDocument();
      expect(screen.queryByText(/547d11ad/)).not.toBeInTheDocument();
    });
  });

  // ==========================================================================
  // WORK ORDER LIST RENDERING
  // ==========================================================================

  describe("work order list renders correctly", () => {
    test("displays all work orders with truncated IDs, status pills, and timestamps", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // All work orders are displayed with truncated IDs (first 8 characters)
      expect(screen.getByText(/e2107d46/)).toBeInTheDocument(); // Success
      expect(screen.getByText(/547d11ad/)).toBeInTheDocument(); // Failed
      expect(screen.getByText(/6443ba23/)).toBeInTheDocument(); // Crashed
      expect(screen.getByText(/b18b25b7/)).toBeInTheDocument(); // Running

      // Status pills are present for each work order
      expect(screen.getByText("Success")).toBeInTheDocument();
      expect(screen.getByText("Failed")).toBeInTheDocument();
      expect(screen.getByText("Crashed")).toBeInTheDocument();
      expect(screen.getByText("Started")).toBeInTheDocument();

      // Relative timestamps are displayed
      const timestamps = screen.getAllByText(/ago|yesterday|today/i);
      expect(timestamps.length).toBeGreaterThan(0);
    });

    test("work order chevron indicates collapsed state by default", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // All work orders should have right-pointing chevrons (collapsed)
      const chevrons = screen
        .getByText(/e2107d46/)
        .closest("div")
        ?.querySelectorAll("span.hero-chevron-right");
      expect(chevrons!.length).toBeGreaterThan(0);
    });

    test("clicking work order expands to show runs", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const history = [mockMultiRunWorkOrder]; // Work order with 3 runs

      render(
        <MiniHistory
          collapsed={false}
          history={history}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Runs should not be visible initially
      expect(screen.queryByText(/8c7087f8/)).not.toBeInTheDocument();

      // Click the work order row (find the button and click its parent container)
      const workOrderId = screen.getByText(/b65107f9/);
      const workOrderRow = workOrderId.closest(".px-3");
      fireEvent.click(workOrderRow!);

      // All runs should now be visible
      expect(screen.getByText(/8c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/9c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/ac7087f8/)).toBeInTheDocument();
    });

    test("clicking work order with single run calls selectRunHandler directly", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const singleRunWorkOrder = createMockWorkOrder({
        id: "single-run-wo",
        runs: [
          {
            id: "single-run-id",
            state: "success",
            started_at: "2025-10-23T20:00:00Z",
            finished_at: "2025-10-23T20:00:01Z",
            error_type: null,
            selected: false,
          },
        ],
      });

      render(
        <MiniHistory
          collapsed={false}
          history={[singleRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Click work order row
      const workOrderId = screen.getByText(/single-ru/);
      const workOrderRow = workOrderId.closest(".px-3");
      fireEvent.click(workOrderRow!);

      // Should call selectRunHandler with the run
      expect(selectRunHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          id: "single-run-id",
          state: "success",
        })
      );
    });
  });

  // ==========================================================================
  // RUN LIST RENDERING
  // ==========================================================================

  describe("run list renders correctly when work order expanded", () => {
    test("displays all runs with IDs, timestamps, durations, and status pills", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Expand work order by clicking the row
      const workOrderId = screen.getByText(/b65107f9/);
      const workOrderRow = workOrderId.closest(".px-3");
      fireEvent.click(workOrderRow!);

      // All runs are visible with truncated IDs
      expect(screen.getByText(/8c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/9c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/ac7087f8/)).toBeInTheDocument();

      // Duration is shown for completed runs (format: "X.XXs")
      const durations = screen.getAllByText(/\d+\.\d+s/);
      expect(durations.length).toBe(3); // One for each run
    });

    test("run selection highlights selected run and displays X icon", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Selected work order should be auto-expanded and show the selected run
      const selectedRun = screen.getByText(/d1f87a82/);
      expect(selectedRun).toBeInTheDocument();

      // Selected run should have special styling
      const runElement = selectedRun.closest("div");
      expect(runElement?.className).toContain("bg-indigo-50");
      expect(runElement?.className).toContain("border-l-indigo-500");

      // X icon should be visible for selected run
      const xIcon = runElement?.querySelector("span.hero-x-mark");
      expect(xIcon).toBeInTheDocument();
      expect(xIcon?.className).toContain("visible");
    });

    test("clicking run calls selectRunHandler", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Expand work order
      const workOrderId = screen.getByText(/b65107f9/);
      const workOrderRow = workOrderId.closest(".px-3");
      fireEvent.click(workOrderRow!);

      // Click a run (click the run row, not just the text)
      const runId = screen.getByText(/8c7087f8/);
      const runRow = runId.closest("div[class*='px-3']");
      fireEvent.click(runRow!);

      // Should call selectRunHandler
      expect(selectRunHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          id: "8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9",
          state: "success",
        })
      );
    });

    test("clicking selected run calls onCollapseHistory to deselect", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Click the already selected run (click the row container)
      const selectedRun = screen.getByText(/d1f87a82/);
      const runRow = selectedRun.closest("div[class*='px-3']");
      fireEvent.click(runRow!);

      // Should call onCollapseHistory (to deselect)
      expect(onCollapseHistory).toHaveBeenCalledTimes(1);
      expect(selectRunHandler).not.toHaveBeenCalled();
    });
  });

  // ==========================================================================
  // STATUS PILLS
  // ==========================================================================

  describe("status pills show correct colors for each state", () => {
    test.each([
      {
        state: "success",
        expectedColor: "bg-green-200",
        textColor: "text-green-800",
      },
      {
        state: "failed",
        expectedColor: "bg-red-200",
        textColor: "text-red-800",
      },
      {
        state: "crashed",
        expectedColor: "bg-orange-200",
        textColor: "text-orange-800",
      },
      {
        state: "started",
        expectedColor: "bg-blue-200",
        textColor: "text-blue-800",
      },
      {
        state: "available",
        expectedColor: "bg-gray-200",
        textColor: "text-gray-800",
      },
      {
        state: "claimed",
        expectedColor: "bg-blue-200",
        textColor: "text-blue-800",
      },
      {
        state: "cancelled",
        expectedColor: "bg-gray-500",
        textColor: "text-gray-800",
      },
      {
        state: "killed",
        expectedColor: "bg-yellow-200",
        textColor: "text-yellow-800",
      },
      {
        state: "exception",
        expectedColor: "bg-gray-800",
        textColor: "text-white",
      },
      { state: "lost", expectedColor: "bg-gray-800", textColor: "text-white" },
    ])(
      "$state state has correct colors",
      ({ state, expectedColor, textColor }) => {
        const onCollapseHistory = vi.fn();
        const selectRunHandler = vi.fn();
        const workOrder = createMockWorkOrder({
          id: `test-wo-${state}`,
          state: state as any,
          runs: [
            {
              id: `test-run-${state}`,
              state: state as any,
              started_at: "2025-10-23T20:00:00Z",
              finished_at: "2025-10-23T20:00:01Z",
              error_type: null,
              selected: false,
            },
          ],
        });

        render(
          <MiniHistory
            collapsed={false}
            history={[workOrder]}
            onCollapseHistory={onCollapseHistory}
            selectRunHandler={selectRunHandler}
          />
        );

        // Find the status pill by text (capitalize first letter)
        const pillText = state.charAt(0).toUpperCase() + state.slice(1);
        const pill = screen.getByText(pillText);

        // Check that the pill has the correct color classes
        expect(pill.className).toContain(expectedColor);
        expect(pill.className).toContain(textColor);
      }
    );

    test("all possible states render with appropriate colors", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const allStateWorkOrders = createWorkOrdersForAllStates();

      render(
        <MiniHistory
          collapsed={false}
          history={allStateWorkOrders}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Verify all states are rendered
      allRunStates.forEach(state => {
        const pillText = state.charAt(0).toUpperCase() + state.slice(1);
        expect(screen.getByText(pillText)).toBeInTheDocument();
      });
    });
  });

  // ==========================================================================
  // NAVIGATION BEHAVIOR
  // ==========================================================================

  describe("navigation behavior", () => {
    test("clicking view full history button navigates to history page", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const viewHistoryButton = screen.getByRole("button", {
        name: /View full history for this workflow/i,
      });

      fireEvent.click(viewHistoryButton);

      // Should navigate to history page with workflow filter
      expect(mockLocation.href).toContain("/history");
      expect(mockLocation.href).toContain(
        "filters[workflow_id]=test-workflow-id"
      );
    });

    test("view history button supports keyboard navigation", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const viewHistoryButton = screen.getByRole("button", {
        name: /View full history for this workflow/i,
      });

      // Test Enter key
      fireEvent.keyDown(viewHistoryButton, { key: "Enter" });
      expect(mockLocation.href).toContain("/history");
    });

    test("clicking work order ID navigates to work order detail page", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const workOrderLink = screen.getByText(/e2107d46/);
      fireEvent.click(workOrderLink);

      // Should navigate to work order detail page
      expect(mockLocation.href).toContain("/projects/test-project-id/history");
      expect(mockLocation.href).toContain(
        "filters[workorder_id]=e2107d46-cf29-4930-b11b-cbcfcf83549d"
      );
    });

    test("clicking run ID navigates to run detail page", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Expand work order
      const workOrderId = screen.getByText(/b65107f9/);
      const workOrderRow = workOrderId.closest(".px-3");
      fireEvent.click(workOrderRow!);

      // Click run ID link directly (find the button within the run)
      const runLink = screen.getByText(/8c7087f8/).closest("button");
      fireEvent.click(runLink!);

      // Should navigate to run detail page
      expect(mockLocation.href).toContain(
        "/projects/test-project-id/runs/8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9"
      );
    });
  });

  // ==========================================================================
  // AUTO-EXPAND SELECTED WORK ORDER
  // ==========================================================================

  describe("auto-expand behavior for selected items", () => {
    test("automatically expands panel when work order is selected", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      // Start with collapsed state but selected work order
      render(
        <MiniHistory
          collapsed={true}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Panel should auto-expand because of selected item
      expect(screen.getByText("Recent History")).toBeInTheDocument();
      expect(screen.getByText(/7f0419b6/)).toBeInTheDocument();
    });

    test("selected work order is automatically expanded to show runs", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Selected work order should be expanded, showing its run
      expect(screen.getByText(/d1f87a82/)).toBeInTheDocument();

      // Chevron should point down for expanded selected work order
      const chevron = screen
        .getByText(/7f0419b6/)
        .closest("div")
        ?.querySelector("span.hero-chevron-down");
      expect(chevron).toBeInTheDocument();
    });
  });

  // ==========================================================================
  // ACCESSIBILITY
  // ==========================================================================

  describe("accessibility", () => {
    test("view history button has descriptive aria-label", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const button = screen.getByRole("button", {
        name: /View full history for this workflow/i,
      });
      expect(button).toHaveAttribute(
        "aria-label",
        "View full history for this workflow"
      );
    });

    test("work order and run links have title attributes with full IDs", () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Work order link (button) has full ID in title
      const workOrderButton = screen.getByText(/b65107f9/).closest("button");
      expect(workOrderButton).toHaveAttribute(
        "title",
        "b65107f9-2a5f-4bd1-b97d-b8500a58f621"
      );

      // Expand to see runs
      const workOrderId = screen.getByText(/b65107f9/);
      const workOrderRow = workOrderId.closest(".px-3");
      fireEvent.click(workOrderRow!);

      // Run links (buttons) have full IDs in title
      const runButton = screen.getByText(/8c7087f8/).closest("button");
      expect(runButton).toHaveAttribute(
        "title",
        "8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9"
      );
    });
  });
});
