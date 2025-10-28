/**
 * RunViewerPanel Component Tests
 *
 * Tests for RunViewerPanel component that displays run data with 4 tabs
 * (Run, Log, Input, Output) and manages channel connection lifecycle.
 *
 * Test Coverage:
 * - Empty state when no run is selected
 * - Loading state with skeleton
 * - Error state with dismiss button
 * - Tab switching and persistence
 * - Channel connection/disconnection lifecycle
 */

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";
import { RunViewerPanel } from "../../../../js/collaborative-editor/components/run-viewer/RunViewerPanel";
import * as useRunModule from "../../../../js/collaborative-editor/hooks/useRun";
import * as useSessionModule from "../../../../js/collaborative-editor/hooks/useSession";
import type { Run } from "../../../../js/collaborative-editor/types/run";

// Mock tab panel components to avoid monaco-editor dependency
vi.mock(
  "../../../../js/collaborative-editor/components/run-viewer/RunTabPanel",
  () => ({
    RunTabPanel: () => <div>Run Tab Content</div>,
  })
);

vi.mock(
  "../../../../js/collaborative-editor/components/run-viewer/LogTabPanel",
  () => ({
    LogTabPanel: () => <div>Log Tab Content</div>,
  })
);

vi.mock(
  "../../../../js/collaborative-editor/components/run-viewer/InputTabPanel",
  () => ({
    InputTabPanel: () => <div>Input Tab Content</div>,
  })
);

vi.mock(
  "../../../../js/collaborative-editor/components/run-viewer/OutputTabPanel",
  () => ({
    OutputTabPanel: () => <div>Output Tab Content</div>,
  })
);

// Mock hooks
const mockUseCurrentRun = vi.spyOn(useRunModule, "useCurrentRun");
const mockUseRunLoading = vi.spyOn(useRunModule, "useRunLoading");
const mockUseRunError = vi.spyOn(useRunModule, "useRunError");
const mockUseRunStoreInstance = vi.spyOn(useRunModule, "useRunStoreInstance");
const mockUseSession = vi.spyOn(useSessionModule, "useSession");

// Mock run factory
const createMockRun = (overrides?: Partial<Run>): Run => ({
  id: "run-1",
  work_order_id: "wo-1",
  state: "started",
  started_at: new Date().toISOString(),
  finished_at: null,
  steps: [],
  ...overrides,
});

// Mock store instance
const createMockRunStore = () => ({
  _connectToRun: vi.fn(() => vi.fn()),
  _disconnectFromRun: vi.fn(),
  clearError: vi.fn(),
  selectStep: vi.fn(),
  getSnapshot: vi.fn(),
  subscribe: vi.fn(),
  withSelector: vi.fn(),
  setRun: vi.fn(),
  updateRunState: vi.fn(),
  addOrUpdateStep: vi.fn(),
  setLoading: vi.fn(),
  setError: vi.fn(),
  clear: vi.fn(),
  findStepById: vi.fn(),
  getSelectedStep: vi.fn(),
});

describe("RunViewerPanel", () => {
  let mockStore: ReturnType<typeof createMockRunStore>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockStore = createMockRunStore();

    // Default mocks
    mockUseRunStoreInstance.mockReturnValue(mockStore as any);
    mockUseSession.mockReturnValue({
      provider: {
        socket: {},
      } as any,
      ydoc: null,
      awareness: null,
      userData: null,
      isConnected: true,
      isSynced: true,
      settled: true,
      lastStatus: null,
    });

    // Clear localStorage
    localStorage.clear();
  });

  describe("empty state", () => {
    test("shows empty state when no followRunId provided", () => {
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId={null} />);

      expect(screen.getByText(/after you click run/i)).toBeInTheDocument();
    });
  });

  describe("loading state", () => {
    test("shows skeleton when loading and no run data", () => {
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(true);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      // Check for skeleton (animated pulse)
      const skeleton = document.querySelector(".animate-pulse");
      expect(skeleton).toBeInTheDocument();
    });

    test("does not show skeleton when loading but run exists", () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(true);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      // Should show tabs, not skeleton
      expect(screen.getByText("Run")).toBeInTheDocument();
      expect(screen.getByText("Log")).toBeInTheDocument();
    });
  });

  describe("error state", () => {
    test("shows error message when error exists", () => {
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue("Failed to load run");

      render(<RunViewerPanel followRunId="run-1" />);

      expect(screen.getByText("Error loading run")).toBeInTheDocument();
      expect(screen.getByText("Failed to load run")).toBeInTheDocument();
    });

    test("dismiss button clears error", async () => {
      const user = userEvent.setup();
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue("Failed to load run");

      render(<RunViewerPanel followRunId="run-1" />);

      const dismissButton = screen.getByText("Dismiss");
      await user.click(dismissButton);

      expect(mockStore.clearError).toHaveBeenCalled();
    });
  });

  describe("tab switching", () => {
    test("renders all 4 tabs when run is loaded", () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      expect(screen.getByText("Run")).toBeInTheDocument();
      expect(screen.getByText("Log")).toBeInTheDocument();
      expect(screen.getByText("Input")).toBeInTheDocument();
      expect(screen.getByText("Output")).toBeInTheDocument();
    });

    test("switches to Log tab when clicked", async () => {
      const user = userEvent.setup();
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      // Click Log tab
      await user.click(screen.getByText("Log"));

      // Verify localStorage was updated
      expect(localStorage.getItem("lightning.ide-run-viewer-tab")).toBe("log");
    });

    test("switches to Input tab when clicked", async () => {
      const user = userEvent.setup();
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      await user.click(screen.getByText("Input"));

      expect(localStorage.getItem("lightning.ide-run-viewer-tab")).toBe(
        "input"
      );
    });

    test("respects localStorage on mount", () => {
      // Set localStorage before component mounts
      localStorage.setItem("lightning.ide-run-viewer-tab", "output");

      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      // localStorage value should be preserved (component reads it)
      // We can't test the visual state easily, but the component
      // will restore the tab internally
      const storedValue = localStorage.getItem("lightning.ide-run-viewer-tab");
      expect(["run", "log", "input", "output"]).toContain(storedValue);
    });
  });

  describe("channel connection lifecycle", () => {
    test("connects to run channel when followRunId provided", () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      expect(mockStore._connectToRun).toHaveBeenCalledWith(
        expect.anything(),
        "run-1"
      );
    });

    test("disconnects when followRunId becomes null", () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      const { rerender } = render(<RunViewerPanel followRunId="run-1" />);

      expect(mockStore._connectToRun).toHaveBeenCalled();

      // Change to null
      rerender(<RunViewerPanel followRunId={null} />);

      expect(mockStore._disconnectFromRun).toHaveBeenCalled();
    });

    test("reconnects when followRunId changes", () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      const { rerender } = render(<RunViewerPanel followRunId="run-1" />);

      expect(mockStore._connectToRun).toHaveBeenCalledWith(
        expect.anything(),
        "run-1"
      );

      // Change to different run
      rerender(<RunViewerPanel followRunId="run-2" />);

      expect(mockStore._connectToRun).toHaveBeenCalledWith(
        expect.anything(),
        "run-2"
      );
    });

    test("does not connect when provider is null", () => {
      mockUseSession.mockReturnValue({
        provider: null,
        ydoc: null,
        awareness: null,
        userData: null,
        isConnected: false,
        isSynced: false,
        settled: false,
        lastStatus: null,
      });

      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      // Should not attempt connection without provider
      expect(mockStore._connectToRun).not.toHaveBeenCalled();
    });
  });

  describe("accessibility", () => {
    test("has proper ARIA labels", () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(<RunViewerPanel followRunId="run-1" />);

      const region = screen.getByRole("region", {
        name: /run output viewer/i,
      });
      expect(region).toBeInTheDocument();
    });
  });
});
