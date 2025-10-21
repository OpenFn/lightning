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
 * Server validation is determined by error key patterns:
 * - Workflow fields: "name", "concurrency"
 * - Job fields: "jobs.{job-id}.name", "jobs.{job-id}.body"
 * - Trigger fields: "triggers.{trigger-id}.cron_expression"
 * - Edge fields: "edges.{edge-id}.condition_expression"
 *
 * @param formOptions - Standard TanStack Form options
 * @param errorPrefix - Optional prefix to filter errors for nested entities
 *                      (e.g., "jobs.abc-123" for a specific job)
 * @returns TanStack Form instance with automatic server validation
 *
 * @example
 * // Workflow-level form (no prefix)
 * const form = useAppForm({ defaultValues: { name: "" } });
 *
 * @example
 * // Job-specific form (with prefix)
 * const form = useAppForm({ defaultValues: { name: "" } }, `jobs.${jobId}`);
 */
export function useAppForm<TFormData>(
  formOptions: FormOptions<TFormData>,
  errorPrefix?: string
) {
  const form = useBaseAppForm(formOptions);

  // Automatically inject server validation errors from Y.Doc
  useServerValidation(form, errorPrefix);

  return form;
}
