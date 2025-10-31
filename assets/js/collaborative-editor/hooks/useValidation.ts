import { useEffect } from "react";

import { useWorkflowActions, useWorkflowState } from "./useWorkflow";

/**
 * Simple type for TanStack Form instance
 * We use this minimal interface to avoid complex generic constraints
 */
interface FormInstance {
  state: {
    values: Record<string, unknown>;
    fieldMeta: Record<string, unknown>;
  };
  store: {
    subscribe: (callback: () => void) => () => void;
  };
  getFieldMeta: (fieldName: string) => {
    errors?: unknown[];
    isTouched?: boolean;
    isDirty?: boolean;
  } | null;
  setFieldMeta: (
    fieldName: string,
    updater: (old: unknown) => unknown
  ) => void;
}

const NO_ERRORS={}

/**
 * Hook to integrate collaborative validation with TanStack Form
 *
 * Handles both server validation errors (from Ecto) and client
 * validation errors (from TanStack Form/Zod), making both visible to
 * all users through Y.Doc synchronization.
 *
 * Features:
 * - Reads stable errors from Immer state (server + all clients merged)
 * - Writes client validation errors to Y.Doc via debounced store method
 * - Store handles merge+dedupe automatically
 * - No feedback loops - errors are referentially stable via Immer
 *
 * @param form - TanStack Form instance
 * @param errorPath - Optional dot-separated path to entity
 *   Examples:
 *     - undefined → workflow-level errors
 *     - "jobs.abc-123" → job-specific errors
 *     - "triggers.xyz-789" → trigger-specific errors
 */
export function useValidation(form: FormInstance, errorPath?: string) {
  const { setClientErrors } = useWorkflowActions();

  // Read stable errors from store (Immer provides referential stability)
  const collaborativeErrors = useWorkflowState(state => {
    if (!errorPath) {
      return state.workflow?.errors || {};
    }

    const [entityType, entityId] = errorPath.split(".");
    const entityCollection = state[
      entityType as "jobs" | "triggers" | "edges"
    ];

    // Validate entity type at runtime - dynamic path parsing
    // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
    if (!entityCollection) {
      return {};
    }

    const entity = entityCollection.find(
      (e: { id: string }) => e.id === entityId
    );
    return entity?.errors || NO_ERRORS;
  });

  // Subscribe to form validation state changes and write to Y.Doc
  useEffect(() => {
    const unsubscribe = form.store.subscribe(() => {
      const formState = form.state;

      // Extract client validation errors from form
      const clientErrors: Record<string, string[]> = {};

      Object.keys(formState.values).forEach(fieldName => {
        const fieldMeta = form.getFieldMeta(fieldName);

        // Only include fields that have been touched/interacted with
        // This preserves server errors for untouched fields
        if (fieldMeta?.isTouched || fieldMeta?.isDirty) {
          if (fieldMeta?.errors && fieldMeta.errors.length > 0) {
            // Field has validation errors
            clientErrors[fieldName] = fieldMeta.errors.map((e: unknown) =>
              typeof e === "string" ? e : String(e)
            );
          } else {
            // Field is valid - send empty array to clear
            clientErrors[fieldName] = [];
          }
        }
      });

      // Write to store (debounced, with merge+dedupe)
      setClientErrors(errorPath || "workflow", clientErrors);
    });

    return () => unsubscribe();
  }, [form, setClientErrors, errorPath]);

  // Inject collaborative errors into TanStack Form
  useEffect(() => {
    // Clear all previous collaborative errors first
    Object.keys(form.state.values).forEach(fieldName => {
      const currentMeta = form.getFieldMeta(fieldName);
      if (currentMeta) {
        form.setFieldMeta(fieldName, (old: unknown) => {
          const oldRecord = old as Record<string, unknown>;
          return {
            ...oldRecord,
            errorMap: {
              ...(oldRecord["errorMap"] as Record<string, unknown>),
              collaborative: undefined,
            },
          };
        });
      }
    });

    // Inject collaborative errors
    Object.entries(collaborativeErrors).forEach(
      ([fieldName, errorMessages]) => {
        if (fieldName in form.state.values) {
          const fieldMeta = form.getFieldMeta(fieldName);

          // Skip injection if field already has validation errors from TanStack Form
          // This prevents duplicates for the user who created the error
          // Other users will still see the error since they don't have validation errors
          if (fieldMeta?.errors && fieldMeta.errors.length > 0) {
            return;
          }

          const errorMessage =
            Array.isArray(errorMessages) && errorMessages.length > 0
              ? errorMessages[0]
              : undefined;

          form.setFieldMeta(fieldName, (old: unknown) => {
            const oldRecord = (old as Record<string, unknown> | undefined) ?? {};
            const oldErrorMap =
              (oldRecord.errorMap as Record<string, unknown> | undefined) ?? {};
            return {
              ...oldRecord,
              errorMap: {
                ...oldErrorMap,
                collaborative: errorMessage,
              },
            };
          });
        }
      }
    );
  }, [collaborativeErrors, form]);
}
