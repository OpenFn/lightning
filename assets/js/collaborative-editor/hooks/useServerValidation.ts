import type { FormApi } from "@tanstack/react-form";
import jp from "jsonpath";
import { useEffect } from "react";

import { useWorkflowState } from "./useWorkflow";

/**
 * Hook to inject server validation errors from Y.Doc into TanStack Form
 * fields
 *
 * Usage in a form component:
 * ```tsx
 * const form = useAppForm({ ... });
 * useServerValidation(form);
 * ```
 *
 * For nested entities (jobs, edges, triggers):
 * ```tsx
 * const form = useAppForm({ ... });
 * useServerValidation(form, "$.jobs['job-id']");
 * ```
 *
 * When the server returns validation errors (written to Y.Doc), they'll
 * automatically appear in the corresponding form fields as if they were
 * client-side validation errors.
 *
 * Error Structure:
 * - Workflow fields: { name: "error message", concurrency: "error" }
 * - Nested entities: { jobs: { "job-id": { name: "error" } } }
 *
 * @param form - TanStack Form instance
 * @param jsonPath - Optional JSONPath expression to query nested errors
 *   e.g., "$.jobs['job-id']" to get errors for a specific job
 */
export function useServerValidation<TFormData>(
  form: FormApi<TFormData, unknown>,
  jsonPath?: string
) {
  const errors = useWorkflowState(state => state.errors);

  useEffect(() => {
    // Navigate to the relevant errors using JSONPath
    let relevantErrors: Record<string, string> = {};

    if (jsonPath) {
      try {
        // Query the errors object using JSONPath
        const results = jp.query(errors, jsonPath);

        // JSONPath query returns an array of matches
        // We expect a single object with field errors
        if (results.length > 0 && typeof results[0] === "object") {
          relevantErrors = results[0];
        }
      } catch (error) {
        console.error("Invalid JSONPath expression:", jsonPath, error);
      }
    } else {
      // No jsonPath - filter out nested entity errors (jobs, edges, triggers)
      relevantErrors = Object.fromEntries(
        Object.entries(errors).filter(
          ([key]) => !["jobs", "edges", "triggers"].includes(key)
        )
      );
    }

    // Clear previous server errors from all fields
    Object.keys(form.state.values).forEach(fieldName => {
      const currentMeta = form.getFieldMeta(fieldName as any);
      if (currentMeta) {
        form.setFieldMeta(fieldName as any, old => ({
          ...old,
          errorMap: {
            ...(old?.errorMap || {}),
            onServer: undefined,
          },
        }));
      }
    });

    // Inject new server errors into form fields
    Object.entries(relevantErrors).forEach(([fieldName, errorMessage]) => {
      // Check if this field exists in the form
      if (fieldName in form.state.values) {
        form.setFieldMeta(fieldName as any, old => ({
          ...old,
          errorMap: {
            ...(old?.errorMap || {}),
            onServer: errorMessage,
          },
        }));
      }
    });
  }, [errors, jsonPath]); // Removed 'form' from dependencies - it's always the same instance
}
