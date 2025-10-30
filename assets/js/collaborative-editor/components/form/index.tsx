import type { FormOptions } from "@tanstack/react-form";
import { createFormHook, createFormHookContexts } from "@tanstack/react-form";

import { useServerValidation } from "#/collaborative-editor/hooks/useServerValidation";

import { NumberField } from "./number-field";
import { SelectField } from "./select-field";
import { TextField } from "./text-field";
import { ToggleField } from "./toggle-field";

export const { fieldContext, formContext, useFieldContext } =
  createFormHookContexts();

// Create the base form hook from TanStack Form
const { useAppForm: useBaseAppForm } = createFormHook({
  fieldContext,
  formContext,
  fieldComponents: {
    TextField,
    SelectField,
    ToggleField,
    NumberField,
  },
  formComponents: {},
});

/**
 * Enhanced useAppForm that automatically integrates server validation from
 * Y.Doc
 *
 * Errors are denormalized onto entities in the WorkflowStore, so this hook
 * passes the errorPath directly to useServerValidation for entity lookup.
 *
 * @param formOptions - Standard TanStack Form options
 * @param errorPath - Optional dot-separated path to entity.
 *                    Examples:
 *                      - undefined → workflow-level errors
 *                      - "jobs.abc-123" → filters to that job's errors
 *                      - "triggers.xyz-789" → filters to that trigger's errors
 *                      - "edges.edge-456" → filters to that edge's errors
 * @returns TanStack Form instance with automatic server validation
 *
 * @example
 * // Workflow-level form (no path)
 * const form = useAppForm({ defaultValues: { name: "" } });
 *
 * @example
 * // Job-specific form (with path)
 * const form = useAppForm({ defaultValues: { name: "" } }, `jobs.${jobId}`);
 */
export function useAppForm<TFormData>(
  formOptions: FormOptions<TFormData>,
  errorPath?: string
) {
  const form = useBaseAppForm(formOptions);

  useServerValidation(form, errorPath);

  return form;
}
