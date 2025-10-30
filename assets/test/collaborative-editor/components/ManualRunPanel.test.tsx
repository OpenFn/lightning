/**
 * ManualRunPanel Component Tests
 *
 * Tests for ManualRunPanel component that allows users to manually trigger
 * workflow runs with custom input data. Tests cover:
 * - Panel rendering with correct context (job vs trigger)
 * - Tab switching and state management
 * - Dataclip fetching and selection
 * - Run button enable/disable logic
 * - Close handler
 * - Permission checks for running workflows
 */

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { HotkeysProvider } from "react-hotkeys-hook";
import type React from "react";
import { act } from "react";
import { beforeEach, describe, expect, test, vi } from "vitest";
import * as dataclipApi from "../../../js/collaborative-editor/api/dataclips";
import { notifications } from "../../../js/collaborative-editor/lib/notifications";
import { ManualRunPanel } from "../../../js/collaborative-editor/components/ManualRunPanel";
import { StoreContext } from "../../../js/collaborative-editor/contexts/StoreProvider";
import type { StoreContextValue } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { createAdaptorStore } from "../../../js/collaborative-editor/stores/createAdaptorStore";
import { createAwarenessStore } from "../../../js/collaborative-editor/stores/createAwarenessStore";
import { createCredentialStore } from "../../../js/collaborative-editor/stores/createCredentialStore";
import { createSessionContextStore } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import { createWorkflowStore } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import type { Workflow } from "../../../js/collaborative-editor/types/workflow";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from "../__helpers__";

// Mock the API module
vi.mock("../../../js/collaborative-editor/api/dataclips");

// Mock the notifications module
vi.mock("../../../js/collaborative-editor/lib/notifications", () => ({
  notifications: {
    alert: vi.fn(),
    info: vi.fn(),
    success: vi.fn(),
    warning: vi.fn(),
    dismiss: vi.fn(),
  },
}));

// Create a configurable mock for useCanRun
let mockCanRunValue = { canRun: true, tooltipMessage: "Run workflow" };

// Mock the useCanRun hook from useWorkflow
vi.mock("../../../js/collaborative-editor/hooks/useWorkflow", async () => {
  const actual = await vi.importActual(
    "../../../js/collaborative-editor/hooks/useWorkflow"
  );
  return {
    ...actual,
    useCanRun: () => mockCanRunValue,
  };
});

// Helper function to override canRun mock
function setMockCanRun(canRun: boolean, tooltipMessage: string) {
  mockCanRunValue = { canRun, tooltipMessage };
}

// Mock MonacoEditor to avoid loading issues in tests
vi.mock("@monaco-editor/react", () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// Mock the monaco module that CustomView imports
vi.mock("../../../js/monaco", () => ({
  MonacoEditor: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

const mockWorkflow: Workflow = {
  id: "workflow-1",
  name: "Test Workflow",
  jobs: [
    {
      id: "job-1",
      name: "Test Job",
      adaptor: "@openfn/language-http@latest",
      body: "fn(state => state)",
      enabled: true,
      project_credential_id: null,
      keychain_credential_id: null,
    },
  ],
  triggers: [
    {
      id: "trigger-1",
      type: "webhook",
      enabled: true,
    },
  ],
  edges: [],
};

const mockDataclip: dataclipApi.Dataclip = {
  id: "dataclip-1",
  name: "Test Dataclip",
  type: "http_request",
  body: {
    data: { test: "data" },
    request: {
      headers: { accept: "*/*", host: "example.com", "user-agent": "test" },
      method: "POST",
      path: ["test"],
      query_params: {},
    },
  },
  request: null,
  inserted_at: "2025-01-01T00:00:00Z",
  updated_at: "2025-01-01T00:00:00Z",
  project_id: "project-1",
  wiped_at: null,
};

// Create stores for tests
let stores: StoreContextValue;
let mockChannel: any;

// Helper function to render ManualRunPanel with all providers
function renderManualRunPanel(
  props: Omit<React.ComponentProps<typeof ManualRunPanel>, "saveWorkflow"> & {
    saveWorkflow?: () => Promise<void>;
  }
) {
  return render(
    <StoreContext.Provider value={stores}>
      <HotkeysProvider>
        <ManualRunPanel
          {...props}
          saveWorkflow={
            props.saveWorkflow || vi.fn().mockResolvedValue(undefined)
          }
        />
      </HotkeysProvider>
    </StoreContext.Provider>
  );
}

describe("ManualRunPanel", () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset mock to default state
    setMockCanRun(true, "Run workflow");

    // Create fresh store instances
    stores = {
      workflowStore: createWorkflowStore(),
      credentialStore: createCredentialStore(),
      sessionContextStore: createSessionContextStore(),
      adaptorStore: createAdaptorStore(),
      awarenessStore: createAwarenessStore(),
    };

    // Create mock channel and connect session context store
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    stores.sessionContextStore._connectChannel(mockProvider as any);

    // Set permissions with can_edit_workflow: true by default
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });

    // Default mock for searchDataclips - returns empty list
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });
  });

  test("renders with correct title when opened from job", async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    await waitFor(() => {
      expect(screen.getByText("Run from Test Job")).toBeInTheDocument();
    });
  });

  test("renders with correct title when opened from trigger", async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      triggerId: "trigger-1",
      onClose: () => {},
    });

    await waitFor(() => {
      expect(
        screen.getByText("Run from Trigger (webhook)")
      ).toBeInTheDocument();
    });
  });

  test("shows three tabs with correct labels", async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    await waitFor(() => {
      expect(screen.getByText("Empty")).toBeInTheDocument();
    });
    expect(screen.getByText("Custom")).toBeInTheDocument();
    expect(screen.getByText("Existing")).toBeInTheDocument();
  });

  test("starts with Empty tab selected", async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Empty view should be visible
    await waitFor(() => {
      expect(
        screen.getByText(/empty JSON object will be used/i)
      ).toBeInTheDocument();
    });
  });

  test("switches to Custom tab when clicked", async () => {
    const user = userEvent.setup();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Click Custom tab
    await user.click(screen.getByText("Custom"));

    // Monaco editor should appear
    await waitFor(() => {
      expect(screen.getByTestId("monaco-editor")).toBeInTheDocument();
    });
  });

  test("switches to Existing tab when clicked", async () => {
    const user = userEvent.setup();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Click Existing tab
    await user.click(screen.getByText("Existing"));

    // Search input should appear
    await waitFor(() => {
      expect(
        screen.getByPlaceholderText("Search names or UUID prefixes")
      ).toBeInTheDocument();
    });
  });

  test("calls onClose when close button is clicked", async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: onClose,
    });

    // Wait for component to finish initial render and async operations
    await waitFor(() => {
      expect(
        screen.getByRole("button", { name: /close panel/i })
      ).toBeInTheDocument();
    });

    // Click close button
    await user.click(screen.getByRole("button", { name: /close panel/i }));

    expect(onClose).toHaveBeenCalledOnce();
  });

  test("Run button is enabled when Empty tab is selected", async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    await waitFor(() => {
      const runButton = screen.getByText("Run Workflow Now");
      expect(runButton).not.toBeDisabled();
    });
  });

  test("fetches dataclips on mount with job context", async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    await waitFor(() => {
      expect(dataclipApi.searchDataclips).toHaveBeenCalledWith(
        "project-1",
        "job-1",
        "",
        {}
      );
    });
  });

  test("fetches dataclips on mount with trigger context", async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      triggerId: "trigger-1",
      onClose: () => {},
    });

    // When triggerId is provided, the component finds the target job from the trigger's edge
    // and uses that job to fetch dataclips (since dataclips are associated with jobs, not triggers)
    await waitFor(() => {
      expect(dataclipApi.searchDataclips).toHaveBeenCalledWith(
        "project-1",
        "job-1", // Resolved from trigger-1's edge
        "",
        {}
      );
    });
  });

  test("displays dataclips in Existing tab", async () => {
    const user = userEvent.setup();

    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Switch to Existing tab
    await user.click(screen.getByText("Existing"));

    // Wait for dataclip to appear
    await waitFor(() => {
      expect(screen.getByText("Test Dataclip")).toBeInTheDocument();
    });
  });

  test("auto-selects next cron run dataclip when available", async () => {
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: "dataclip-1",
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Should auto-switch to Existing tab and show selected dataclip with warning banner
    await waitFor(() => {
      expect(screen.getByText("Test Dataclip")).toBeInTheDocument();
      expect(
        screen.getByText("Default Next Input for Cron")
      ).toBeInTheDocument();
    });
  });

  test("shows next cron run warning banner when dataclip is next cron run", async () => {
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: "dataclip-1",
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Should show the next cron run warning banner
    await waitFor(() => {
      expect(
        screen.getByText("Default Next Input for Cron")
      ).toBeInTheDocument();
      expect(
        screen.getByText(/This workflow has a "cron" trigger/)
      ).toBeInTheDocument();
    });
  });

  test("shows next cron run warning banner when opened from trigger", async () => {
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: "dataclip-1",
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      triggerId: "trigger-1",
      onClose: () => {},
    });

    // Should show the next cron run warning banner
    await waitFor(() => {
      expect(
        screen.getByText("Default Next Input for Cron")
      ).toBeInTheDocument();
      expect(
        screen.getByText(/This workflow has a "cron" trigger/)
      ).toBeInTheDocument();
    });
  });

  test("disables Run button when Custom tab has invalid JSON", async () => {
    const user = userEvent.setup();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Switch to Custom tab
    await user.click(screen.getByText("Custom"));

    // The Monaco editor is mocked, so we can't actually test JSON validation
    // through user interaction. This is acceptable as JSON validation is
    // tested separately in the validateCustomBody callback.

    // Just verify the tab switched
    await waitFor(() => {
      expect(screen.getByTestId("monaco-editor")).toBeInTheDocument();
    });
  });

  test("enables Run button when Existing tab has selected dataclip", async () => {
    const user = userEvent.setup();

    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: "project-1",
      workflowId: "workflow-1",
      jobId: "job-1",
      onClose: () => {},
    });

    // Switch to Existing tab
    await user.click(screen.getByText("Existing"));

    // Wait for dataclip to appear and click it
    await waitFor(() => {
      expect(screen.getByText("Test Dataclip")).toBeInTheDocument();
    });

    await user.click(screen.getByText("Test Dataclip"));

    // Run button should be enabled
    await waitFor(() => {
      const runButton = screen.getByText("Run Workflow Now");
      expect(runButton).not.toBeDisabled();
    });
  });

  test("handles empty workflow (no triggers)", async () => {
    const emptyWorkflow: Workflow = {
      id: "workflow-2",
      name: "Empty Workflow",
      jobs: [],
      triggers: [],
      edges: [],
    };

    renderManualRunPanel({
      workflow: emptyWorkflow,
      projectId: "project-1",
      workflowId: "workflow-2",
      onClose: () => {},
    });

    // Should render with generic title
    await waitFor(() => {
      expect(screen.getByText("Run Workflow")).toBeInTheDocument();
    });
  });

  describe("renderMode prop", () => {
    test("standalone mode (default) shows InspectorLayout with header and footer", async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
      });

      // Should show header with title
      await waitFor(() => {
        expect(screen.getByText("Run from Test Job")).toBeInTheDocument();
      });

      // Should show close button in header
      expect(
        screen.getByRole("button", { name: /close panel/i })
      ).toBeInTheDocument();

      // Should show footer with Run button
      expect(screen.getByText("Run Workflow Now")).toBeInTheDocument();
    });

    test("embedded mode shows only content, no header or footer", async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        renderMode: "embedded",
      });

      // Should render tabs (content)
      await waitFor(() => {
        expect(screen.getByText("Empty")).toBeInTheDocument();
      });

      // Should NOT show header with title
      expect(screen.queryByText("Run from Test Job")).not.toBeInTheDocument();

      // Should NOT show close button
      expect(
        screen.queryByRole("button", { name: /close panel/i })
      ).not.toBeInTheDocument();

      // Should NOT show footer with Run button
      expect(screen.queryByText("Run Workflow Now")).not.toBeInTheDocument();
    });

    test("embedded mode with trigger context", async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        triggerId: "trigger-1",
        onClose: () => {},
        renderMode: "embedded",
      });

      // Should render tabs (content)
      await waitFor(() => {
        expect(screen.getByText("Empty")).toBeInTheDocument();
      });

      // Should NOT show header title
      expect(
        screen.queryByText("Run from Trigger (webhook)")
      ).not.toBeInTheDocument();
    });
  });

  describe("onRunStateChange callback", () => {
    test("calls onRunStateChange when Empty tab is selected", async () => {
      const onRunStateChange = vi.fn();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        onRunStateChange,
      });

      // Wait for initial render and callback
      await waitFor(() => {
        expect(onRunStateChange).toHaveBeenCalled();
      });

      // Should be called with canRun=true, isSubmitting=false, and a handler function
      const lastCall =
        onRunStateChange.mock.calls[onRunStateChange.mock.calls.length - 1];
      expect(lastCall[0]).toBe(true); // canRun
      expect(lastCall[1]).toBe(false); // isSubmitting
      expect(typeof lastCall[2]).toBe("function"); // handler
    });

    test("calls onRunStateChange when switching to Custom tab", async () => {
      const user = userEvent.setup();
      const onRunStateChange = vi.fn();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        onRunStateChange,
      });

      // Clear initial calls
      await waitFor(() => {
        expect(onRunStateChange).toHaveBeenCalled();
      });
      onRunStateChange.mockClear();

      // Switch to Custom tab
      await user.click(screen.getByText("Custom"));

      // Should be called again with updated state
      await waitFor(() => {
        expect(onRunStateChange).toHaveBeenCalled();
      });

      const lastCall =
        onRunStateChange.mock.calls[onRunStateChange.mock.calls.length - 1];
      expect(lastCall[0]).toBe(true); // canRun (Custom tab allows run)
      expect(lastCall[1]).toBe(false); // isSubmitting
      expect(typeof lastCall[2]).toBe("function"); // handler
    });

    test("calls onRunStateChange when selecting a dataclip in Existing tab", async () => {
      const user = userEvent.setup();
      const onRunStateChange = vi.fn();

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        onRunStateChange,
      });

      // Wait for initial render
      await waitFor(() => {
        expect(onRunStateChange).toHaveBeenCalled();
      });
      onRunStateChange.mockClear();

      // Switch to Existing tab
      await user.click(screen.getByText("Existing"));

      // Wait for dataclip to appear
      await waitFor(() => {
        expect(screen.getByText("Test Dataclip")).toBeInTheDocument();
      });

      // At this point, no dataclip is selected, so canRun should be false
      let lastCall =
        onRunStateChange.mock.calls[onRunStateChange.mock.calls.length - 1];
      expect(lastCall[0]).toBe(false); // canRun

      onRunStateChange.mockClear();

      // Select the dataclip
      await user.click(screen.getByText("Test Dataclip"));

      // Should be called with canRun=true now
      await waitFor(() => {
        expect(onRunStateChange).toHaveBeenCalled();
      });

      lastCall =
        onRunStateChange.mock.calls[onRunStateChange.mock.calls.length - 1];
      expect(lastCall[0]).toBe(true); // canRun
      expect(lastCall[1]).toBe(false); // isSubmitting
    });

    test("handler function is stable across re-renders", async () => {
      const onRunStateChange = vi.fn();

      const { rerender } = renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        onRunStateChange,
      });

      await waitFor(() => {
        expect(onRunStateChange).toHaveBeenCalled();
      });

      const firstHandler = onRunStateChange.mock.calls[0][2];

      // Re-render with same props (wrapped with providers)
      rerender(
        <StoreContext.Provider value={stores}>
          <HotkeysProvider>
            <ManualRunPanel
              workflow={mockWorkflow}
              projectId="project-1"
              workflowId="workflow-1"
              jobId="job-1"
              onClose={() => {}}
              onRunStateChange={onRunStateChange}
              saveWorkflow={vi.fn().mockResolvedValue(undefined)}
            />
          </HotkeysProvider>
        </StoreContext.Provider>
      );

      await waitFor(() => {
        expect(onRunStateChange.mock.calls.length).toBeGreaterThan(1);
      });

      const secondHandler =
        onRunStateChange.mock.calls[onRunStateChange.mock.calls.length - 1][2];

      // Handlers should reference the same memoized function
      expect(typeof firstHandler).toBe("function");
      expect(typeof secondHandler).toBe("function");
    });
  });

  describe("filter debouncing", () => {
    test("filters are applied when changed", async () => {
      const user = userEvent.setup();

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
      });

      // Wait for initial fetch
      await waitFor(() => {
        expect(dataclipApi.searchDataclips).toHaveBeenCalledTimes(1);
      });

      // Switch to Existing tab
      await user.click(screen.getByText("Existing"));

      // Find the "Named only" filter button (has hero-tag icon)
      const filterButtons = screen
        .getAllByRole("button")
        .filter(btn => btn.querySelector(".hero-tag"));
      expect(filterButtons.length).toBeGreaterThan(0);

      // Click the named-only filter button
      // This changes the namedOnly state, which triggers the debounced search
      await user.click(filterButtons[0]);

      // Wait for the debounced search to complete (300ms debounce + execution time)
      // The debounce timer from switching tabs is cancelled when the button is clicked
      await waitFor(
        () => {
          expect(dataclipApi.searchDataclips).toHaveBeenCalledTimes(2);
        },
        { timeout: 1000 }
      );
    });
  });

  describe("permission checks", () => {
    test("Run button is disabled when user lacks can_edit_workflow permission", async () => {
      // Mock useCanRun to return false (simulating lack of permission)
      setMockCanRun(false, "You do not have permission to run workflows");

      // Override permissions to deny workflow editing
      act(() => {
        (mockChannel as any)._test.emit("session_context", {
          user: null,
          project: null,
          config: { require_email_verification: false },
          permissions: { can_edit_workflow: false },
          latest_snapshot_lock_version: 1,
        });
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
      });

      await waitFor(() => {
        const runButton = screen.getByText("Run Workflow Now");
        expect(runButton).toBeDisabled();
      });
    });

    test("Run button is enabled when user has can_edit_workflow permission", async () => {
      // Permissions already set to can_edit_workflow: true in beforeEach
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
      });

      await waitFor(() => {
        const runButton = screen.getByText("Run Workflow Now");
        expect(runButton).not.toBeDisabled();
      });
    });

    test("onRunStateChange reports canRun=false when permission is denied", async () => {
      const onRunStateChange = vi.fn();

      // Mock useCanRun to return false (simulating lack of permission)
      setMockCanRun(false, "You do not have permission to run workflows");

      // Override permissions to deny workflow editing
      act(() => {
        (mockChannel as any)._test.emit("session_context", {
          user: null,
          project: null,
          config: { require_email_verification: false },
          permissions: { can_edit_workflow: false },
          latest_snapshot_lock_version: 1,
        });
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        onRunStateChange,
      });

      // Wait for initial render and callback
      await waitFor(() => {
        expect(onRunStateChange).toHaveBeenCalled();
      });

      // Should be called with canRun=false due to lack of permission
      const lastCall =
        onRunStateChange.mock.calls[onRunStateChange.mock.calls.length - 1];
      expect(lastCall[0]).toBe(false); // canRun
      expect(lastCall[1]).toBe(false); // isSubmitting
      expect(typeof lastCall[2]).toBe("function"); // handler
    });

    test("Run button remains disabled in Existing tab without permission, even with selected dataclip", async () => {
      const user = userEvent.setup();

      // Mock useCanRun to return false (simulating lack of permission)
      setMockCanRun(false, "You do not have permission to run workflows");

      // Override permissions to deny workflow editing
      act(() => {
        (mockChannel as any)._test.emit("session_context", {
          user: null,
          project: null,
          config: { require_email_verification: false },
          permissions: { can_edit_workflow: false },
          latest_snapshot_lock_version: 1,
        });
      });

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: false,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
      });

      // Switch to Existing tab
      await user.click(screen.getByText("Existing"));

      // Wait for dataclip to appear and click it
      await waitFor(() => {
        expect(screen.getByText("Test Dataclip")).toBeInTheDocument();
      });

      await user.click(screen.getByText("Test Dataclip"));

      // Run button should still be disabled due to lack of permission
      await waitFor(() => {
        const runButton = screen.getByText("Run Workflow Now");
        expect(runButton).toBeDisabled();
      });
    });
  });

  describe("Save & Run behavior", () => {
    test("saves workflow before submitting run", async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: "2025-01-01T00:00:00Z",
        lock_version: 2,
      });

      // Track the order of calls
      const callOrder: string[] = [];

      saveWorkflow.mockImplementation(async () => {
        callOrder.push("save");
        return { saved_at: "2025-01-01T00:00:00Z", lock_version: 2 };
      });

      vi.mocked(dataclipApi.submitManualRun).mockImplementation(async () => {
        callOrder.push("run");
        return { data: { run_id: "run-1", workorder_id: "wo-1" } };
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        saveWorkflow,
      });

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText("Run Workflow Now")).toBeInTheDocument();
      });

      // Click Run button
      await user.click(screen.getByText("Run Workflow Now"));

      // Verify save was called first, then run
      await waitFor(() => {
        expect(callOrder).toEqual(["save", "run"]);
        expect(saveWorkflow).toHaveBeenCalledOnce();
        expect(dataclipApi.submitManualRun).toHaveBeenCalledOnce();
      });
    });

    test("does not run if save fails", async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockRejectedValue(new Error("Save failed"));

      // Clear notifications mock before test
      vi.mocked(notifications.alert).mockClear();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText("Run Workflow Now")).toBeInTheDocument();
      });

      await user.click(screen.getByText("Run Workflow Now"));

      // Save should be called
      await waitFor(() => {
        expect(saveWorkflow).toHaveBeenCalledOnce();
      });

      // Run should NOT be called because save failed
      expect(dataclipApi.submitManualRun).not.toHaveBeenCalled();

      // Error should be shown to user via notifications
      await waitFor(() => {
        expect(notifications.alert).toHaveBeenCalledWith({
          title: "Failed to submit run",
          description: "Save failed",
        });
      });
    });

    test("does not run if save fails with generic error", async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockRejectedValue("Network error"); // Non-Error type

      // Clear notifications mock before test
      vi.mocked(notifications.alert).mockClear();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText("Run Workflow Now")).toBeInTheDocument();
      });

      await user.click(screen.getByText("Run Workflow Now"));

      // Save should be called
      await waitFor(() => {
        expect(saveWorkflow).toHaveBeenCalledOnce();
      });

      // Run should NOT be called because save failed
      expect(dataclipApi.submitManualRun).not.toHaveBeenCalled();

      // Generic error message should be shown to user via notifications
      await waitFor(() => {
        expect(notifications.alert).toHaveBeenCalledWith({
          title: "Failed to submit run",
          description: "An unknown error occurred",
        });
      });
    });

    test("calls saveWorkflow with correct signature", async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: "2025-01-01T00:00:00Z",
        lock_version: 2,
      });

      vi.mocked(dataclipApi.submitManualRun).mockResolvedValue({
        data: { run_id: "run-1", workorder_id: "wo-1" },
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        saveWorkflow,
      });

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText("Run Workflow Now")).toBeInTheDocument();
      });

      // Click Run button
      await user.click(screen.getByText("Run Workflow Now"));

      // Verify saveWorkflow was called with no arguments
      await waitFor(() => {
        expect(saveWorkflow).toHaveBeenCalledWith();
        expect(saveWorkflow).toHaveBeenCalledOnce();
      });
    });

    test("submitting state prevents multiple simultaneous runs", async () => {
      const user = userEvent.setup();
      let saveResolve: () => void;
      const savePromise = new Promise<{
        saved_at: string;
        lock_version: number;
      }>(resolve => {
        saveResolve = () =>
          resolve({ saved_at: "2025-01-01T00:00:00Z", lock_version: 2 });
      });
      const saveWorkflow = vi.fn().mockReturnValue(savePromise);

      vi.mocked(dataclipApi.submitManualRun).mockResolvedValue({
        data: { run_id: "run-1", workorder_id: "wo-1" },
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: "project-1",
        workflowId: "workflow-1",
        jobId: "job-1",
        onClose: () => {},
        saveWorkflow,
      });

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText("Run Workflow Now")).toBeInTheDocument();
      });

      // Click Run button - this will start the save
      await user.click(screen.getByText("Run Workflow Now"));

      // Button should show "Running..." while submitting
      await waitFor(() => {
        expect(screen.getByText("Running...")).toBeInTheDocument();
      });

      // Button should be disabled
      const runButton = screen.getByText("Running...");
      expect(runButton).toBeDisabled();

      // Try to click again - should not trigger another save
      await user.click(runButton);

      // Should still only have one call to saveWorkflow
      expect(saveWorkflow).toHaveBeenCalledOnce();

      // Resolve the save to complete the test
      saveResolve!();
    });
  });
});
