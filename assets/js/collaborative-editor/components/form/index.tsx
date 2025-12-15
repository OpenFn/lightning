import { createFormHook, createFormHookContexts } from '@tanstack/react-form';
import { produce } from 'immer';
import { useEffect, useMemo, useRef } from 'react';

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
  formOptions: Parameters<typeof useBaseAppForm>[0],
  errorPath?: string,
  depsArr?: string[]
) {
  const prevStateRef = useRef<Record<string, unknown> | null>(null);
  const form = useBaseAppForm(formOptions);

  const isServerUpdate = useMemo(() => {
    const previousState = prevStateRef.current as Record<string, unknown>;
    const currentState = form.state.values;

    const isServerUpdate =
      previousState === null ? true : deepEqual(previousState, currentState);
    return isServerUpdate;
  }, [form.state.values, prevStateRef]);

  useEffect(() => {
    const storeState = formOptions.defaultValues as Record<string, unknown>;
    const previousState = prevStateRef.current as Record<string, unknown>;

    if (!storeState || !previousState) {
      if (storeState) {
        // this mimics onMount without having an onMount validation
        Object.keys(storeState).forEach(
          key => void form.validateField(key, 'change')
        );
        prevStateRef.current = produce(storeState, () => {});
      }
      return;
    }

    // fire 'change' for all changed fields
    const keys = Object.keys(formOptions.defaultValues || {});
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (depsArr?.length && !depsArr.includes(key)) continue;
      if (previousState[key] !== storeState[key]) {
        // update our reference value for the key
        prevStateRef.current = produce(previousState, draft => {
          draft[key] = storeState[key];
        });
        // set field
        form.setFieldValue(key, storeState[key]);
        // call onchange on them!
        void form.validateField(key, 'change');
      }
    }
  }, [formOptions.defaultValues, form, depsArr]);

  useValidation(form, errorPath, isServerUpdate);

  return form;
}

// we need a better deepEqual check
function deepEqual(a: unknown, b: unknown) {
  return JSON.stringify(a) === JSON.stringify(b);
}
