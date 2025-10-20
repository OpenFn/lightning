import type { FormApi } from "@tanstack/react-form";
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
 * When the server returns validation errors (written to Y.Doc), they'll
 * automatically appear in the corresponding form fields as if they were
 * client-side validation errors.
 *
 * Error Key Format:
 * - Workflow fields: "name", "concurrency"
 * - Job fields: "jobs.{job-id}.name", "jobs.{job-id}.body"
 * - Trigger fields: "triggers.{trigger-id}.cron_expression"
 * - Edge fields: "edges.{edge-id}.condition_expression"
 *
 * @param form - TanStack Form instance
 * @param prefix - Optional prefix to filter errors (e.g., "jobs.abc-123"
 * for a specific job)
 */
export function useServerValidation<TFormData>(
  form: FormApi<TFormData, unknown>,
  prefix?: string
) {
  const errors = useWorkflowState(state => state.errors);

  useEffect(() => {
    // Filter errors by prefix if provided
    const relevantErrors = prefix
      ? Object.entries(errors).filter(([key]) => key.startsWith(prefix))
      : Object.entries(errors);

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
    relevantErrors.forEach(([errorKey, errorMessage]) => {
      // Extract field name from error key
      // "name" -> "name"
      // "jobs.abc-123.name" -> "name" (if prefix is "jobs.abc-123")
      // "concurrency" -> "concurrency"
      const fieldName = prefix
        ? errorKey.substring(prefix.length + 1) // Remove prefix + dot
        : errorKey;

      // Check if this field exists in the form
      if (fieldName in form.state.values) {
        const currentMeta = form.getFieldMeta(fieldName as any);
        if (currentMeta) {
          form.setFieldMeta(fieldName as any, old => ({
            ...old,
            errorMap: {
              ...(old?.errorMap || {}),
              onServer: errorMessage,
            },
          }));
        }
      }
    });
  }, [errors, form, prefix]);
}
