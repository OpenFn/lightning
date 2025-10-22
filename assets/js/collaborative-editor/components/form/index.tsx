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
 * Enhanced useAppForm that automatically integrates server validation from Y.Doc
 *
 * This hook wraps TanStack Form's useForm and automatically injects server
 * validation errors from the WorkflowStore's errors map into form fields.
 *
 * Server validation uses a nested structure:
 * - Workflow fields: { name: "error message" }
 * - Nested entities: { jobs: { "job-id": { name: "error" } } }
 *
 * @param formOptions - Standard TanStack Form options
 * @param errorPath - Optional dot-separated path to filter errors for nested entities.
 *                    Will be converted to a JSONPath expression.
 *                    (e.g., "jobs.abc-123" becomes "$.jobs['abc-123']")
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

  // Convert dot-separated path to JSONPath expression
  // e.g., "jobs.abc-123" becomes "$.jobs['abc-123']"
  const jsonPath = errorPath
    ? `$${errorPath
        .split(".")
        .map(key => `['${key}']`)
        .join("")}`
    : undefined;

  // Automatically inject server validation errors from Y.Doc
  useServerValidation(form, jsonPath);

  return form;
}
