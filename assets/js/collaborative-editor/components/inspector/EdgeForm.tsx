import {
  useStore,
  type AnyFieldMetaBase,
  type Updater,
} from '@tanstack/react-form';
import { useMemo } from 'react';

import {
  useWorkflowActions,
  useWorkflowReadOnly,
} from '../../hooks/useWorkflow';
import { useWatchFields } from '../../stores/common';
import { EdgeSchema, ExprEdgeSchema } from '../../types/edge';
import type { Workflow } from '../../types/workflow';
import { isEdgeFromTrigger } from '../../utils/workflowGraph';
import { useAppForm } from '../form';
import { createZodValidator } from '../form/createZodValidator';
import { ErrorMessage } from '../form/error-message';
import { Tooltip } from '../Tooltip';

interface EdgeFormProps {
  edge: Workflow.Edge;
}

/**
 * Pure form component for edge configuration.
 * Handles condition label, type, expression, and enabled toggle.
 * Does NOT include delete functionality - that's in EdgeInspector.
 */
export function EdgeForm({ edge }: EdgeFormProps) {
  const { updateEdge } = useWorkflowActions();
  const { isReadOnly } = useWorkflowReadOnly();

  // Initialize form
  const form = useAppForm(
    {
      defaultValues: {
        ...edge,
        condition_expression: edge.condition_expression || '',
      },
      listeners: {
        onChange: ({ formApi, fieldApi }) => {
          if (fieldApi.name === 'condition_type') {
            // mark condition_expr as dirty to cause revalidation when select changes
            formApi.setFieldMeta('condition_expression', {
              isDirty: true,
              isTouched: true,
            } as Updater<AnyFieldMetaBase>);
          }
          if (edge.id) {
            updateEdge(edge.id, formApi.state.values);
          }
        },
      },
      validators: {
        onChange: ({ value, formApi }) => {
          // conditionally picking edge schema. zod.refine doesn't seem to work
          const edgeSchema =
            formApi.state.values['condition_type'] === 'js_expression'
              ? ExprEdgeSchema
              : EdgeSchema;
          return createZodValidator(edgeSchema)({ value });
        },
      },
    },
    `edges.${edge.id}` // Server validation automatically filtered to this edge
  );

  // Sync Y.js changes
  useWatchFields(
    edge as unknown as Record<string, unknown>,
    changedFields => {
      Object.entries(changedFields).forEach(([key, value]) => {
        if (key in form.state.values) {
          form.setFieldValue(
            key as keyof typeof form.state.values,
            value as never
          );
        }
      });
    },
    ['condition_label', 'condition_type', 'condition_expression', 'enabled']
  );

  // Condition options based on source
  const conditionOptions = useMemo(() => {
    const isSourceTrigger = isEdgeFromTrigger(edge);

    if (isSourceTrigger) {
      return [
        { value: 'always', label: 'Always' },
        { value: 'js_expression', label: 'Matches a Javascript Expression' },
      ];
    }

    return [
      { value: 'on_job_success', label: 'On Success' },
      { value: 'on_job_failure', label: 'On Failure' },
      { value: 'always', label: 'Always' },
      { value: 'js_expression', label: 'Matches a Javascript Expression' },
    ];
  }, [edge]);

  // Watch condition type
  const conditionType = useStore(
    form.store,
    state => state.values.condition_type
  );
  const showExpressionEditor = conditionType === 'js_expression';

  // Unsafe keyword detection
  const conditionExpression = useStore(
    form.store,
    state => state.values.condition_expression || ''
  );
  const isExpressionUnsafe =
    /(\bimport\b|\brequire\b|\bprocess\b|\bawait\b|\beval\b)/.test(
      conditionExpression
    );

  return (
    <div className="px-6 py-6 space-y-4">
      {/* Label Field */}
      <form.AppField name="condition_label">
        {field => <field.TextField label="Label" disabled={isReadOnly} />}
      </form.AppField>

      {/* Condition Type Dropdown */}
      <form.AppField name="condition_type">
        {field => (
          <field.SelectField
            label="Condition"
            options={conditionOptions}
            disabled={isReadOnly}
          />
        )}
      </form.AppField>

      {/* JS Expression Editor (conditional) */}
      {showExpressionEditor && (
        <div className="space-y-2">
          <form.Field name="condition_expression">
            {field => (
              <div>
                <div className="flex items-center gap-2 mb-2">
                  <label
                    htmlFor={field.name}
                    className="text-sm font-medium text-slate-800"
                  >
                    JS Expression
                  </label>
                  {isExpressionUnsafe && (
                    <Tooltip
                      content="Expression contains potentially unsafe functions"
                      side="top"
                    >
                      <span className="hero-exclamation-triangle text-yellow-600 h-4 w-4 inline-flex" />
                    </Tooltip>
                  )}
                </div>
                <textarea
                  id={field.name}
                  value={field.state.value || ''}
                  onChange={e => field.handleChange(e.target.value)}
                  placeholder="eg: !state.error"
                  disabled={isReadOnly}
                  className="block w-full h-24 px-3 py-2 rounded-md border-slate-300
                               font-mono text-slate-200 bg-slate-700 text-sm
                               focus:border-slate-400 focus:ring-0
                               disabled:opacity-50 disabled:cursor-not-allowed"
                />
                <ErrorMessage meta={field.state.meta} />
              </div>
            )}
          </form.Field>

          <details className="text-xs text-slate-600">
            <summary className="cursor-pointer hover:text-slate-800">
              How to write expressions
            </summary>
            <div className="mt-2 space-y-1">
              <p>
                Use the state from the previous step to decide whether this step
                should run.
              </p>
              <p>
                Must be a single JavaScript expression with `state` in scope.
              </p>
              <p>
                Check{' '}
                <a
                  href="https://docs.openfn.org/documentation/build/paths#writing-javascript-expressions-for-custom-path-conditions"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-indigo-600 hover:underline"
                >
                  docs.openfn.org
                </a>{' '}
                for more details.
              </p>
            </div>
          </details>
        </div>
      )}

      {/* Info text for trigger edges */}
      {edge.source_trigger_id && (
        <p className="text-xs text-slate-600 italic mt-4">
          This path will be active if its trigger is enabled
        </p>
      )}
    </div>
  );
}
