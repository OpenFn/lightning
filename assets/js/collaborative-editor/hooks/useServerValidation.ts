import { useEffect } from "react";

import { useWorkflowState } from "./useWorkflow";

/**
 * Hook to inject server validation errors from Y.Doc into TanStack Form
 * fields
 *
 * Errors are denormalized onto entities in the WorkflowStore, so this hook
 * simply reads the errors property from the relevant entity.
 *
 * Usage:
 * ```tsx
 * // Workflow-level form (no path)
 * const form = useAppForm({ defaultValues: { name: "" } });
 *
 * // Job-specific form (with path)
 * const form = useAppForm(
 *   { defaultValues: { name: "" } },
 *   `jobs.${jobId}`
 * );
 * ```
 *
 * @param form - TanStack Form instance
 * @param errorPath - Optional dot-separated path to entity
 *   (e.g., "jobs.abc-123")
 */
export function useServerValidation(
  form: any, // TanStack Form instance (FormApi has complex generics)
  errorPath?: string
) {
  // Select the right errors based on errorPath
  const relevantErrors = useWorkflowState(state => {
    if (!errorPath) {
      // Workflow-level form - read from workflow.errors
      return state.workflow?.errors || {};
    }

    // Entity form - parse errorPath like "jobs.abc-123"
    const [entityType, entityId] = errorPath.split(".");
    const entity = state[entityType as "jobs" | "triggers" | "edges"]?.find(
      (e: any) => e.id === entityId
    );
    return entity?.errors || {};
  });

  useEffect(() => {
    // Clear previous server errors from all fields
    Object.keys(form.state.values).forEach(fieldName => {
      const currentMeta = form.getFieldMeta(fieldName as any);
      if (currentMeta) {
        form.setFieldMeta(fieldName as any, (old: any) => ({
          ...old,
          errorMap: {
            ...(old?.errorMap || {}),
            onServer: undefined,
          },
        }));
      }
    });

    // Inject new server errors into form fields
    Object.entries(relevantErrors).forEach(([fieldName, errorMessages]) => {
      if (fieldName in form.state.values) {
        const errorMessage =
          Array.isArray(errorMessages) && errorMessages.length > 0
            ? errorMessages[0]
            : undefined;

        form.setFieldMeta(fieldName as any, (old: any) => ({
          ...old,
          errorMap: {
            ...(old?.errorMap || {}),
            onServer: errorMessage,
          },
        }));
      }
    });
  }, [relevantErrors]); // Much simpler dependency!
}
