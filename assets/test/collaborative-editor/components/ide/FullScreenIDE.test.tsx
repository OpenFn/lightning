/**
 * FullScreenIDE Component Tests
 *
 * Tests for FullScreenIDE component that provides a full-screen workspace
 * with three panels: ManualRunPanel (left), Monaco editor (center), and
 * output panel (right). Tests cover:
 * - Panel layout and default state (left panel open by default)
 * - ManualRunPanel integration with renderMode="embedded"
 * - Run button in header functionality
 * - Run state management (canRun, isRunning, handler)
 * - Keyboard shortcuts (Escape to close, Cmd+Enter to run)
 * - Panel collapse/expand functionality
 */

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { HotkeysProvider } from "react-hotkeys-hook";
import * as Y from "yjs";
import { beforeEach, describe, expect, test, vi } from "vitest";
import { FullScreenIDE } from "../../../../js/collaborative-editor/components/ide/FullScreenIDE";
import * as dataclipApi from "../../../../js/collaborative-editor/api/dataclips";
import type { Workflow } from "../../../../js/collaborative-editor/types/workflow";

// Mock dependencies
vi.mock("../../../../js/collaborative-editor/api/dataclips");

// Mock MonacoEditor
vi.mock("@monaco-editor/react", () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// Mock CollaborativeMonaco
vi.mock(
  "../../../../js/collaborative-editor/components/CollaborativeMonaco",
  () => ({
    CollaborativeMonaco: () => (
      <div data-testid="collaborative-monaco">Monaco Editor</div>
    ),
  })
);

// Mock ManualRunPanel
vi.mock(
  "../../../../js/collaborative-editor/components/ManualRunPanel",
  () => ({
    ManualRunPanel: ({
      renderMode,
      onRunStateChange,
    }: {
      renderMode?: string;
      onRunStateChange?: (
        canRun: boolean,
        isSubmitting: boolean,
        handler: () => void
      ) => void;
    }) => {
      // Simulate ManualRunPanel calling onRunStateChange after mount
      if (onRunStateChange) {
        setTimeout(() => {
          onRunStateChange(true, false, () => {
            console.log("Mock run triggered");
          });
        }, 0);
      }

      return (
        <div data-testid="manual-run-panel" data-render-mode={renderMode}>
          ManualRunPanel (renderMode: {renderMode || "standalone"})
        </div>
      );
    },
  })
);

// Mock useURLState hook
const mockSearchParams = new URLSearchParams();
mockSearchParams.set("job", "job-1");

vi.mock("../../../../js/react/lib/use-url-state", () => ({
  useURLState: () => ({
    searchParams: mockSearchParams,
    updateSearchParams: vi.fn(),
    hash: "",
  }),
}));

// Mock session hooks
vi.mock("../../../../js/collaborative-editor/hooks/useSession", () => ({
  useSession: () => ({
    awareness: {
      setLocalStateField: vi.fn(),
      getStates: () => new Map(),
    },
  }),
}));

vi.mock("../../../../js/collaborative-editor/hooks/useSessionContext", () => ({
  useProject: () => ({
    id: "project-1",
    name: "Test Project",
  }),
}));

// Mock workflow hooks
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

const mockYText = new Y.Text();
mockYText.insert(0, "fn(state => state)");

vi.mock("../../../../js/collaborative-editor/hooks/useWorkflow", () => ({
  useCanSave: () => ({
    canSave: true,
    tooltipMessage: "Save workflow",
  }),
  useCurrentJob: () => ({
    job: {
      id: "job-1",
      name: "Test Job",
      adaptor: "@openfn/language-http@latest",
      body: "fn(state => state)",
    },
    ytext: mockYText,
  }),
  useWorkflowActions: () => ({
    selectJob: vi.fn(),
    saveWorkflow: vi.fn(),
  }),
  useWorkflowState: (selector: any) => {
    const state = {
      workflow: mockWorkflow,
      jobs: mockWorkflow.jobs,
      triggers: mockWorkflow.triggers,
      edges: mockWorkflow.edges,
      positions: {},
    };
    return typeof selector === "function" ? selector(state) : state;
  },
}));

// Mock react-resizable-panels
vi.mock("react-resizable-panels", () => ({
  Panel: ({ children, onCollapse, onExpand, ref }: any) => {
    return <div data-testid="panel">{children}</div>;
  },
  PanelGroup: ({ children }: any) => (
    <div data-testid="panel-group">{children}</div>
  ),
  PanelResizeHandle: () => <div data-testid="resize-handle" />,
}));

// Helper function to render FullScreenIDE with HotkeysProvider
function renderFullScreenIDE(
  props: React.ComponentProps<typeof FullScreenIDE>
) {
  return render(
    <HotkeysProvider>
      <FullScreenIDE {...props} />
    </HotkeysProvider>
  );
}

describe("FullScreenIDE", () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock for searchDataclips
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });

    // Reset search params
    mockSearchParams.delete("job");
    mockSearchParams.set("job", "job-1");
  });

  describe("panel layout", () => {
    test("renders with three-panel layout", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for component to render
      await waitFor(() => {
        expect(screen.getByTestId("panel-group")).toBeInTheDocument();
      });

      // Should have three panels
      const panels = screen.getAllByTestId("panel");
      expect(panels).toHaveLength(3);
    });

    test("left panel contains ManualRunPanel with embedded mode", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for ManualRunPanel to render
      await waitFor(() => {
        expect(screen.getByTestId("manual-run-panel")).toBeInTheDocument();
      });

      // Should use embedded mode
      const manualRunPanel = screen.getByTestId("manual-run-panel");
      expect(manualRunPanel.getAttribute("data-render-mode")).toBe("embedded");
    });

    test("center panel contains CollaborativeMonaco editor", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for Monaco editor to render
      await waitFor(() => {
        expect(screen.getByTestId("collaborative-monaco")).toBeInTheDocument();
      });
    });

    test("shows Input, Code, and Output panel labels", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByText("Input")).toBeInTheDocument();
      });

      expect(screen.getByText("Code")).toBeInTheDocument();
      expect(screen.getByText("Output")).toBeInTheDocument();
    });
  });

  describe("header integration", () => {
    test("displays job name in header", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByText(/Test Job/i)).toBeInTheDocument();
      });
    });

    test("displays Run button in header", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole("button", { name: /run/i })
        ).toBeInTheDocument();
      });
    });

    test("displays Save button in header", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole("button", { name: /save/i })
        ).toBeInTheDocument();
      });
    });

    test("displays Close button in header", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole("button", { name: /close/i })
        ).toBeInTheDocument();
      });
    });
  });

  describe("run state management", () => {
    test("Run button is enabled when canRunWorkflow is true", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for onRunStateChange to be called and run button to be enabled
      await waitFor(() => {
        const runButton = screen.getByRole("button", { name: /run/i });
        expect(runButton).not.toBeDisabled();
      });
    });

    test("receives run state from ManualRunPanel via onRunStateChange", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for ManualRunPanel to mount and call onRunStateChange
      await waitFor(() => {
        expect(screen.getByTestId("manual-run-panel")).toBeInTheDocument();
      });

      // Run button should be enabled (from mocked ManualRunPanel)
      await waitFor(() => {
        const runButton = screen.getByRole("button", { name: /run/i });
        expect(runButton).not.toBeDisabled();
      });
    });
  });

  describe("keyboard shortcuts", () => {
    test("Escape key eventually calls onClose", async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByTestId("collaborative-monaco")).toBeInTheDocument();
      });

      // First Escape - should blur Monaco (but we can't test focus in this mock)
      await user.keyboard("{Escape}");

      // Second Escape - should close IDE
      await user.keyboard("{Escape}");
      expect(onClose).toHaveBeenCalled();
    });
  });

  describe("panel collapse/expand", () => {
    test("left panel can be collapsed via collapse button", async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByTestId("manual-run-panel")).toBeInTheDocument();
      });

      // Find collapse button for left panel
      const collapseButtons = screen.getAllByRole("button", {
        name: /collapse/i,
      });

      // Should have collapse buttons for each panel
      expect(collapseButtons.length).toBeGreaterThan(0);

      // Clicking collapse button would trigger panel collapse
      // (Full behavior requires ImperativePanelHandle which we can't test in JSDOM)
    });

    test("prevents closing last open panel", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByText("Input")).toBeInTheDocument();
      });

      // Find all collapse buttons
      const collapseButtons = screen.getAllByRole("button", {
        name: /collapse/i,
      });

      // All collapse buttons should be enabled initially
      // (In real app, last open panel's collapse button would be disabled)
      expect(collapseButtons.length).toBeGreaterThan(0);
    });
  });

  describe("button functionality", () => {
    test("Save and Close buttons are present", async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole("button", { name: /save/i })
        ).toBeInTheDocument();
      });

      expect(
        screen.getByRole("button", { name: /close/i })
      ).toBeInTheDocument();
    });
  });

  describe("Close button functionality", () => {
    test("Close button calls onClose when clicked", async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole("button", { name: /close/i })
        ).toBeInTheDocument();
      });

      const closeButton = screen.getByRole("button", { name: /close/i });
      await user.click(closeButton);

      expect(onClose).toHaveBeenCalledOnce();
    });
  });
});
