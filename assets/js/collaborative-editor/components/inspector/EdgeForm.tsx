import { useStore } from "@tanstack/react-form";
import { useEffect, useMemo } from "react";

import { useWorkflowActions } from "../../hooks/useWorkflow";
import { useWatchFields } from "../../stores/common";
import { EdgeSchema } from "../../types/edge";
import type { Workflow } from "../../types/workflow";
import { useAppForm } from "../form";
import { createZodValidator } from "../form/createZodValidator";
import { ErrorMessage } from "../form/error-message";
import { Tooltip } from "../Tooltip";

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

  // Initialize form
  const form = useAppForm({
    defaultValues: edge,
    listeners: {
      onChange: ({ formApi }) => {
        if (edge.id) {
          updateEdge(edge.id, formApi.state.values);
        }
      },
    },
    validators: {
      onChange: createZodValidator(EdgeSchema),
    },
  });

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
    ["condition_label", "condition_type", "condition_expression", "enabled"]
  );

  // Reset form when edge changes
  useEffect(() => {
    form.reset();
  }, [edge.id, form.reset]);

  // Condition options based on source
  const conditionOptions = useMemo(() => {
    const isSourceTrigger = !!edge.source_trigger_id;

    if (isSourceTrigger) {
      return [
        { value: "always", label: "Always" },
        { value: "js_expression", label: "Matches a Javascript Expression" },
      ];
    }

    return [
      { value: "on_job_success", label: "On Success" },
      { value: "on_job_failure", label: "On Failure" },
      { value: "always", label: "Always" },
      { value: "js_expression", label: "Matches a Javascript Expression" },
    ];
  }, [edge.source_trigger_id]);

  // Watch condition type
  const conditionType = useStore(
    form.store,
    state => state.values.condition_type
  );
  const showExpressionEditor = conditionType === "js_expression";

  // Unsafe keyword detection
  const conditionExpression = useStore(
    form.store,
    state => state.values.condition_expression || ""
  );
  const isExpressionUnsafe =
    /(\bimport\b|\brequire\b|\bprocess\b|\bawait\b|\beval\b)/.test(
      conditionExpression
    );

  return (
    <div>
      {/* Label Field */}
      <form.AppField name="condition_label">
        {field => <field.TextField label="Label" />}
      </form.AppField>

      {/* Condition Type Dropdown */}
      <form.AppField name="condition_type">
        {field => (
          <field.SelectField label="Condition" options={conditionOptions} />
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
                  value={field.state.value || ""}
                  onChange={e => field.handleChange(e.target.value)}
                  placeholder="eg: !state.error"
                  className="block w-full h-24 px-3 py-2 rounded-md border-slate-300
                               font-mono text-slate-200 bg-slate-700 text-sm
                               focus:border-slate-400 focus:ring-0"
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
                Check{" "}
                <a
                  href="https://docs.openfn.org/documentation/build/paths#writing-javascript-expressions-for-custom-path-conditions"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-indigo-600 hover:underline"
                >
                  docs.openfn.org
                </a>{" "}
                for more details.
              </p>
            </div>
          </details>
        </div>
      )}

      {/* Enabled toggle (only for job edges) */}
      {!edge.source_trigger_id && (
        <div className="mt-4">
          <form.Field name="enabled">
            {field => (
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={field.state.value ?? true}
                  onChange={e => field.handleChange(e.target.checked)}
                  className="rounded border-slate-300 text-indigo-600
                             focus:ring-indigo-500"
                />
                <span className="text-sm font-medium text-slate-800">
                  Enabled
                </span>
              </label>
            )}
          </form.Field>
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
