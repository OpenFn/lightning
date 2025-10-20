import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook } from "@testing-library/react";
import { useForm } from "@tanstack/react-form";
import { useServerValidation } from "#/collaborative-editor/hooks/useServerValidation";
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
    vi.mocked(useWorkflowModule.useWorkflowState).mockReturnValue({
      errors: {
        name: "Name is required",
      },
    } as any);

    // Create form instance and mount a field to initialize its meta
    const { result: formResult } = renderHook(() => {
      const form = useForm({
        defaultValues: { name: "", concurrency: null },
      });

      // Mount the name field to initialize its meta
      form.Field({
        name: "name",
        children: () => null,
      });

      return form;
    });

    // Apply server validation hook
    renderHook(() => useServerValidation(formResult.current));

    // Wait a bit for effect to run
    await new Promise(resolve => setTimeout(resolve, 10));

    // Check that error was injected into field meta
    const fieldMeta = formResult.current.getFieldMeta("name");
    expect(fieldMeta?.errorMap.onServer).toBe("Name is required");
  });

  it("should clear server errors when errors removed from Y.Doc", () => {
    // Start with errors
    vi.mocked(useWorkflowModule.useWorkflowState).mockReturnValue({
      errors: {
        name: "Name is required",
      },
    } as any);

    const { result: formResult } = renderHook(() =>
      useForm({
        defaultValues: { name: "", concurrency: null },
      })
    );

    const { rerender } = renderHook(() =>
      useServerValidation(formResult.current)
    );

    // Verify error is present
    expect(formResult.current.getFieldMeta("name")?.errorMap.onServer).toBe(
      "Name is required"
    );

    // Update mock to clear errors
    vi.mocked(useWorkflowModule.useWorkflowState).mockReturnValue({
      errors: {},
    } as any);

    // Re-render hook with cleared errors
    rerender();

    // Verify error was cleared
    expect(
      formResult.current.getFieldMeta("name")?.errorMap.onServer
    ).toBeUndefined();
  });

  it("should filter errors by prefix for nested entities", () => {
    // Mock errors for multiple jobs
    vi.mocked(useWorkflowModule.useWorkflowState).mockReturnValue({
      errors: {
        "jobs.abc-123.name": "Job name is required",
        "jobs.def-456.name": "Other job name is required",
      },
    } as any);

    const { result: formResult } = renderHook(() =>
      useForm({
        defaultValues: { name: "", body: "" },
      })
    );

    // Apply server validation with prefix for specific job
    renderHook(() => useServerValidation(formResult.current, "jobs.abc-123"));

    // Only abc-123 job error should be injected
    const fieldMeta = formResult.current.getFieldMeta("name");
    expect(fieldMeta?.errorMap.onServer).toBe("Job name is required");

    // def-456 job error should NOT be injected
    const bodyMeta = formResult.current.getFieldMeta("body");
    expect(bodyMeta?.errorMap.onServer).toBeUndefined();
  });

  it("should handle multiple fields with errors", () => {
    vi.mocked(useWorkflowModule.useWorkflowState).mockReturnValue({
      errors: {
        name: "Name is required",
        concurrency: "Must be positive",
      },
    } as any);

    const { result: formResult } = renderHook(() =>
      useForm({
        defaultValues: { name: "", concurrency: null },
      })
    );

    renderHook(() => useServerValidation(formResult.current));

    // Both fields should have errors
    expect(formResult.current.getFieldMeta("name")?.errorMap.onServer).toBe(
      "Name is required"
    );
    expect(
      formResult.current.getFieldMeta("concurrency")?.errorMap.onServer
    ).toBe("Must be positive");
  });
});
