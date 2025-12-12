import { useEffect } from 'react';

import { useWorkflowActions, useWorkflowState } from './useWorkflow';

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
  setFieldMeta: (fieldName: string, updater: (old: unknown) => unknown) => void;
}

const NO_ERRORS = {};

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
export function useValidation(
  form: FormInstance,
  errorPath?: string,
  isServerUpdate?: boolean
) {
  const { setClientErrors } = useWorkflowActions();

  // Read stable errors from store (Immer provides referential stability)
  const collaborativeErrors = useWorkflowState(state => {
    if (!errorPath) {
      return state.workflow?.errors || {};
    }

    const [entityType, entityId] = errorPath.split('.');
    const entityCollection = state[entityType as 'jobs' | 'triggers' | 'edges'];

    // Validate entity type at runtime - dynamic path parsing

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
          // Get client validation errors (exclude collaborative errors from errorMap)
          const meta = fieldMeta as unknown as Record<string, unknown>;
          const errorMap = (meta?.errorMap as Record<string, unknown>) || {};

          // Filter out collaborative errors - only send client validation errors
          const clientValidationErrors = (fieldMeta?.errors || []).filter(
            (error: unknown) => {
              // If this error matches the collaborative error, exclude it
              const collaborativeError = errorMap.collaborative;
              return error !== collaborativeError;
            }
          );

          if (clientValidationErrors.length > 0) {
            // Field has client validation errors
            clientErrors[fieldName] = clientValidationErrors.map(
              (e: unknown) => (typeof e === 'string' ? e : String(e))
            );
          } else {
            // Field is valid or only has collaborative errors - send empty array to clear
            clientErrors[fieldName] = [];
          }
        }
      });

      // Write to store (debounced, with merge+dedupe)
      setClientErrors(errorPath || 'workflow', clientErrors, isServerUpdate);
    });

    return () => unsubscribe();
  }, [form, setClientErrors, errorPath]);

  // Inject collaborative errors into TanStack Form
  useEffect(() => {
    // Track which fields currently have collaborative errors
    const fieldsWithErrors = new Set(Object.keys(collaborativeErrors));

    // Process all form fields
    Object.keys(form.state.values).forEach(fieldName => {
      const currentMeta = form.getFieldMeta(fieldName);

      // If field metadata doesn't exist yet, we'll create it when setting errors
      const hasCollaborativeError = fieldsWithErrors.has(fieldName);
      const fieldMeta = currentMeta || {};

      // Check if field has CLIENT validation errors (excluding collaborative)
      const meta = fieldMeta as unknown as Record<string, unknown>;
      const errorMap = (meta?.errorMap as Record<string, unknown>) || {};
      const collaborativeError = errorMap.collaborative;

      const hasClientValidationErrors = (fieldMeta?.errors || []).some(
        (error: unknown) => error !== collaborativeError
      );

      // Skip if field has client validation errors (prevents duplicates)
      // But don't skip if it only has collaborative errors - we might need to clear them
      if (hasClientValidationErrors) {
        return;
      }

      // Determine what the collaborative error should be
      const errorMessage = hasCollaborativeError
        ? Array.isArray(collaborativeErrors[fieldName]) &&
          collaborativeErrors[fieldName].length > 0
          ? collaborativeErrors[fieldName][0]
          : undefined
        : undefined;

      // Only update if the collaborative error changed
      const oldRecord = (currentMeta || {}) as Record<string, unknown>;
      const oldErrorMap =
        (oldRecord['errorMap'] as Record<string, unknown> | undefined) ?? {};
      const currentCollaborativeError = oldErrorMap.collaborative;

      if (currentCollaborativeError !== errorMessage) {
        form.setFieldMeta(fieldName, (old: unknown) => {
          const rec = (old || {}) as Record<string, unknown>;
          const errMap =
            (rec['errorMap'] as Record<string, unknown> | undefined) ?? {};

          return {
            ...rec,
            // CRITICAL: Explicitly preserve dirty/touched state
            // Without this, form changes don't sync after server errors
            isTouched: rec.isTouched,
            isDirty: rec.isDirty,
            errorMap: {
              ...errMap,
              collaborative: errorMessage,
            },
          };
        });
      }
    });
  }, [collaborativeErrors, form]);
}
