import type { FormOptions } from '@tanstack/react-form';
import { createFormHook, createFormHookContexts } from '@tanstack/react-form';

import { useValidation } from '#/collaborative-editor/hooks/useValidation';

import { NumberField } from './number-field';
import { SelectField } from './select-field';
import { TextField } from './text-field';
import { TextAreaField } from './textarea-field';
import { ToggleField } from './toggle-field';

export const { fieldContext, formContext, useFieldContext } =
  createFormHookContexts();

// Create the base form hook from TanStack Form
const { useAppForm: useBaseAppForm } = createFormHook({
  fieldContext,
  formContext,
  fieldComponents: {
    TextField,
    TextAreaField,
    SelectField,
    ToggleField,
    NumberField,
  },
  formComponents: {},
});

export type useAppBaseFormType = ReturnType<
  typeof createFormHook
>['useAppForm'];

/**
 * Enhanced useAppForm that automatically integrates collaborative
 * validation from Y.Doc
 *
 * All validation errors (server-side Ecto validation AND client-side
 * TanStack Form/Zod validation) flow through Y.Doc's errorsMap, making
 * them visible to all connected users in real-time.
 *
 * @param formOptions - Standard TanStack Form options
 * @param errorPath - Optional dot-separated path to entity.
 *                    Examples:
 *                      - undefined → workflow-level errors
 *                      - "jobs.abc-123" → filters to that job's errors
 *                      - "triggers.xyz-789" → filters to that trigger's errors
 *                      - "edges.edge-456" → filters to that edge's errors
 * @returns TanStack Form instance with automatic collaborative validation
 *
 * @example
 * // Workflow-level form (no path)
 * const form = useAppForm({ defaultValues: { name: "" } });
 *
 * @example
 * // Job-specific form (with path)
 * const form = useAppForm({ defaultValues: { name: "" } }, `jobs.${jobId}`);
 */
export function useAppForm(
  formOptions: Parameters<useAppBaseFormType>[0],
  errorPath?: string
) {
  const form = useBaseAppForm(formOptions);

  useValidation(form, errorPath);

  return form;
}
