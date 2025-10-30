import { renderHook, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { useAppForm } from "#/collaborative-editor/components/form";
import * as useWorkflowModule from "#/collaborative-editor/hooks/useWorkflow";

// Mock useWorkflowState
vi.mock("#/collaborative-editor/hooks/useWorkflow", () => ({
  useWorkflowState: vi.fn(),
}));

describe("useServerValidation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("should inject server errors into form field meta", async () => {
    // Mock server errors from Y.Doc
    const mockFn = vi.fn(selector => {
      const state = {
        workflow: {
          id: "w-1",
          name: "Workflow",
          errors: { name: ["Name is required"] },
        },
      };
      return selector ? selector(state) : state;
    });
    vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
      mockFn as any
    );

    // Create form using useAppForm (which includes useServerValidation)
    const { result } = renderHook(() =>
      useAppForm({
        defaultValues: { name: "", concurrency: null },
      })
    );

    // Wait for server validation effect to run
    await waitFor(() => {
      const fieldMeta = result.current.getFieldMeta("name");
      expect(fieldMeta?.errorMap?.onServer).toBe("Name is required");
    });
  });

  it("should clear server errors when errors removed from Y.Doc", async () => {
    // Start with errors
    let mockErrors = { name: ["Name is required"] };
    const mockFn = vi.fn(selector => {
      const state = {
        workflow: {
          id: "w-1",
          name: "Workflow",
          errors: mockErrors,
        },
      };
      return selector ? selector(state) : state;
    });
    vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
      mockFn as any
    );

    const { result, rerender } = renderHook(() =>
      useAppForm({
        defaultValues: { name: "", concurrency: null },
      })
    );

    // Verify error is present
    await waitFor(() => {
      expect(result.current.getFieldMeta("name")?.errorMap?.onServer).toBe(
        "Name is required"
      );
    });

    // Update mock to clear errors
    mockErrors = {};

    // Re-render to trigger effect with new errors
    rerender();

    // Verify error was cleared
    await waitFor(() => {
      expect(
        result.current.getFieldMeta("name")?.errorMap?.onServer
      ).toBeUndefined();
    });
  });

  it("should filter errors for specific entity using errorPath", async () => {
    const mockFn = vi.fn(selector => {
      const state = {
        jobs: [
          {
            id: "abc-123",
            name: "Job 1",
            errors: { name: ["Job name is required"] },
          },
          {
            id: "def-456",
            name: "Job 2",
            errors: { name: ["Other job name is required"] },
          },
        ],
      };
      return selector ? selector(state) : state;
    });
    vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
      mockFn as any
    );

    // Use useAppForm with errorPath to select specific job's errors
    const { result } = renderHook(() =>
      useAppForm(
        {
          defaultValues: { name: "", body: "" },
        },
        "jobs.abc-123" // Dot-separated path to entity
      )
    );

    // Wait for server validation effect to run
    await waitFor(() => {
      const fieldMeta = result.current.getFieldMeta("name");
      expect(fieldMeta?.errorMap?.onServer).toBe("Job name is required");
    });

    // def-456 job error should NOT be injected
    const bodyMeta = result.current.getFieldMeta("body");
    expect(bodyMeta?.errorMap?.onServer).toBeUndefined();
  });

  it("should handle multiple fields with errors", async () => {
    const mockFn = vi.fn(selector => {
      const state = {
        workflow: {
          id: "w-1",
          name: "Workflow",
          errors: {
            name: ["Name is required"],
            concurrency: ["Must be positive"],
          },
        },
      };
      return selector ? selector(state) : state;
    });
    vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
      mockFn as any
    );

    const { result } = renderHook(() =>
      useAppForm({
        defaultValues: { name: "", concurrency: null },
      })
    );

    // Wait for server validation effect to run
    await waitFor(() => {
      const nameMeta = result.current.getFieldMeta("name");
      const concurrencyMeta = result.current.getFieldMeta("concurrency");
      expect(nameMeta?.errorMap?.onServer).toBe("Name is required");
      expect(concurrencyMeta?.errorMap?.onServer).toBe("Must be positive");
    });
  });
});
