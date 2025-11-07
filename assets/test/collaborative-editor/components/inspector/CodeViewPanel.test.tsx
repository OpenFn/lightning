/**
 * CodeViewPanel Component Tests
 *
 * Tests for CodeViewPanel component that displays workflow as YAML code.
 * Focuses on behavior tests following testing-essentials.md guidelines.
 *
 * Test coverage:
 * - YAML generation and display
 * - Download functionality with filename sanitization
 * - Copy to clipboard with notifications
 * - Error handling
 */

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";
import YAML from "yaml";

import { CodeViewPanel } from "../../../../js/collaborative-editor/components/inspector/CodeViewPanel";

// Mock notifications module
vi.mock("../../../../js/collaborative-editor/lib/notifications", () => ({
  notifications: {
    info: vi.fn(),
    alert: vi.fn(),
  },
}));

// Mock yaml/util with simple pass-through
vi.mock("../../../../js/yaml/util", () => ({
  convertWorkflowStateToSpec: vi.fn((workflowState: any) => ({
    name: workflowState.name,
    jobs: workflowState.jobs || [],
    triggers: workflowState.triggers || [],
    edges: workflowState.edges || [],
  })),
}));

// Mock useWorkflowState hook
vi.mock("../../../../js/collaborative-editor/hooks/useWorkflow", () => {
  let mockState = {
    workflow: null,
    jobs: [],
    triggers: [],
    edges: [],
    positions: {},
  };

  return {
    useWorkflowState: vi.fn(selector => selector(mockState)),
    // Helper functions for tests
    __setMockWorkflowState: (newState: any) => {
      mockState = { ...mockState, ...newState };
    },
    __resetMockWorkflowState: () => {
      mockState = {
        workflow: null,
        jobs: [],
        triggers: [],
        edges: [],
        positions: {},
      };
    },
  };
});

describe("CodeViewPanel", () => {
  let clipboardWriteText: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    // Reset all mocks
    vi.clearAllMocks();

    // Import mock helpers
    const hookModule = await import(
      "../../../../js/collaborative-editor/hooks/useWorkflow"
    );
    (hookModule as any).__resetMockWorkflowState();

    // Mock clipboard API
    clipboardWriteText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText: clipboardWriteText },
      writable: true,
      configurable: true,
    });

    // Mock URL.createObjectURL and revokeObjectURL
    global.URL.createObjectURL = vi.fn().mockReturnValue("blob:mock-url");
    global.URL.revokeObjectURL = vi.fn();
  });

  describe("rendering and YAML generation", () => {
    test("displays loading state when workflow is missing", async () => {
      // Workflow state defaults to null
      render(<CodeViewPanel />);

      expect(screen.getByText("Loading...")).toBeInTheDocument();
    });

    test("generates and displays workflow YAML with correct structure", async () => {
      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );
      (hookModule as any).__setMockWorkflowState({
        workflow: { id: "w1", name: "Test Workflow" },
        jobs: [
          {
            id: "j1",
            name: "Test Job",
            adaptor: "@openfn/language-http@latest",
            body: "fn(state => state)",
          },
        ],
        triggers: [{ id: "t1", type: "webhook", enabled: true }],
        edges: [
          {
            id: "e1",
            source_trigger_id: "t1",
            target_job_id: "j1",
            condition_type: "always",
            enabled: true,
          },
        ],
      });

      render(<CodeViewPanel />);

      const textarea = screen.getByRole("textbox", {
        name: /workflow yaml code/i,
      }) as HTMLTextAreaElement;

      // Verify YAML is displayed
      expect(textarea).toBeInTheDocument();
      expect(textarea.value).toContain("Test Workflow");
      expect(textarea.value).toBeTruthy();

      // Verify it's valid YAML
      expect(() => YAML.parse(textarea.value)).not.toThrow();
    });

    test("handles YAML generation errors gracefully", async () => {
      const consoleErrorSpy = vi
        .spyOn(console, "error")
        .mockImplementation(() => {});

      const yamlUtil = await import("../../../../js/yaml/util");
      vi.mocked(yamlUtil.convertWorkflowStateToSpec).mockImplementationOnce(
        () => {
          throw new Error("YAML generation failed");
        }
      );

      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );
      (hookModule as any).__setMockWorkflowState({
        workflow: { id: "w1", name: "Test" },
        jobs: [],
      });

      render(<CodeViewPanel />);

      const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;
      expect(textarea.value).toContain("# Error generating YAML");

      consoleErrorSpy.mockRestore();
    });
  });

  describe("filename sanitization and download", () => {
    test("sanitizes filename and triggers download correctly", async () => {
      const user = userEvent.setup();
      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );

      // Test multiple filename edge cases in one test (grouped assertions)
      const testCases = [
        { name: "My Workflow", expected: "My-Workflow.yaml" },
        { name: "Test@Workflow#2024!", expected: "TestWorkflow2024.yaml" },
        { name: "Test 🚀 Workflow", expected: "Test--Workflow.yaml" },
      ];

      for (const { name, expected } of testCases) {
        const mockAnchor = {
          href: "",
          download: "",
          click: vi.fn(),
        };
        const createElementSpy = vi
          .spyOn(document, "createElement")
          .mockReturnValue(mockAnchor as any);
        vi.spyOn(document.body, "appendChild").mockImplementation(
          () => mockAnchor as any
        );
        vi.spyOn(document.body, "removeChild").mockImplementation(
          () => mockAnchor as any
        );

        (hookModule as any).__setMockWorkflowState({
          workflow: { id: "w1", name },
          jobs: [],
        });

        const { unmount } = render(<CodeViewPanel />);

        const downloadBtn = screen.getByRole("button", { name: /download/i });
        await user.click(downloadBtn);

        expect(mockAnchor.download).toBe(expected);
        expect(mockAnchor.click).toHaveBeenCalled();

        createElementSpy.mockRestore();
        unmount();
      }
    });

    test("creates blob with correct YAML content and cleans up", async () => {
      const user = userEvent.setup();
      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );

      const mockAnchor = {
        href: "",
        download: "",
        click: vi.fn(),
      };
      vi.spyOn(document, "createElement").mockReturnValue(mockAnchor as any);
      vi.spyOn(document.body, "appendChild").mockImplementation(
        () => mockAnchor as any
      );
      vi.spyOn(document.body, "removeChild").mockImplementation(
        () => mockAnchor as any
      );

      (hookModule as any).__setMockWorkflowState({
        workflow: { id: "w1", name: "Test" },
        jobs: [],
      });

      render(<CodeViewPanel />);

      const downloadBtn = screen.getByRole("button", { name: /download/i });
      await user.click(downloadBtn);

      // Verify blob creation and cleanup
      expect(global.URL.createObjectURL).toHaveBeenCalledWith(expect.any(Blob));
      expect(global.URL.revokeObjectURL).toHaveBeenCalledWith("blob:mock-url");
    });
  });

  describe("copy functionality", () => {
    test("copies YAML to clipboard and shows success notification", async () => {
      const user = userEvent.setup();
      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );
      const notificationsModule = await import(
        "../../../../js/collaborative-editor/lib/notifications"
      );

      (hookModule as any).__setMockWorkflowState({
        workflow: { id: "w1", name: "Test Workflow" },
        jobs: [],
      });

      render(<CodeViewPanel />);

      const copyBtn = screen.getByRole("button", { name: /copy code/i });
      await user.click(copyBtn);

      await waitFor(() => {
        expect(clipboardWriteText).toHaveBeenCalledWith(
          expect.stringContaining("Test Workflow")
        );
        expect(notificationsModule.notifications.info).toHaveBeenCalledWith({
          title: "Code copied",
          description: "Workflow YAML copied to clipboard",
        });
      });
    });

    test("shows error notification when clipboard copy fails", async () => {
      const user = userEvent.setup();
      const consoleErrorSpy = vi
        .spyOn(console, "error")
        .mockImplementation(() => {});
      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );
      const notificationsModule = await import(
        "../../../../js/collaborative-editor/lib/notifications"
      );

      clipboardWriteText.mockRejectedValueOnce(new Error("Clipboard denied"));

      (hookModule as any).__setMockWorkflowState({
        workflow: { id: "w1", name: "Test" },
        jobs: [],
      });

      render(<CodeViewPanel />);

      const copyBtn = screen.getByRole("button", { name: /copy code/i });
      await user.click(copyBtn);

      await waitFor(() => {
        expect(notificationsModule.notifications.alert).toHaveBeenCalledWith({
          title: "Failed to copy",
          description: "Could not copy to clipboard. Please try again.",
        });
      });

      consoleErrorSpy.mockRestore();
    });
  });

  describe("component behavior", () => {
    test("textarea is read-only with correct accessibility", async () => {
      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );

      (hookModule as any).__setMockWorkflowState({
        workflow: { id: "w1", name: "Test" },
        jobs: [],
      });

      render(<CodeViewPanel />);

      const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;

      // Group related assertions for readability
      expect(textarea.readOnly).toBe(true);
      expect(textarea).toHaveAttribute("aria-label", "Workflow YAML code");
      expect(textarea).toHaveAttribute("spellcheck", "false");
    });

    test("renders action buttons", async () => {
      const hookModule = await import(
        "../../../../js/collaborative-editor/hooks/useWorkflow"
      );

      (hookModule as any).__setMockWorkflowState({
        workflow: { id: "w1", name: "Test" },
        jobs: [],
      });

      render(<CodeViewPanel />);

      expect(
        screen.getByRole("button", { name: /download/i })
      ).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /copy code/i })
      ).toBeInTheDocument();
    });
  });
});
