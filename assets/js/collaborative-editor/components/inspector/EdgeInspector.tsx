import { useStore } from "@tanstack/react-form";
import { useCallback, useEffect, useMemo } from "react";

import { useWorkflowActions, useWorkflowState } from "../../hooks/useWorkflow";
import { useWatchFields } from "../../stores/common";
import { EdgeSchema } from "../../types/edge";
import type { Workflow } from "../../types/workflow";
import { useAppForm } from "../form";
import { createZodValidator } from "../form/createZodValidator";
import { ErrorMessage } from "../form/error-message";

interface EdgeInspectorProps {
  edge: Workflow.Edge;
}

export function EdgeInspector({ edge }: EdgeInspectorProps) {
  const { updateEdge, removeEdge, clearSelection } = useWorkflowActions();
  const { jobs, triggers } = useWorkflowState(state => ({
    jobs: state.jobs,
    triggers: state.triggers,
  }));

  // Initialize form with edge data
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

  // Sync external Y.js changes back into form
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
    [
      "condition_label",
      "condition_type",
      "condition_expression",
      "enabled",
    ] as const
  );

  // Reset form when edge changes
  useEffect(() => {
    form.reset();
  }, [edge.id, form]);

  // Resolve source and target names
  const sourceNode = useMemo(() => {
    if (edge.source_job_id) {
      const job = jobs.find(j => j.id === edge.source_job_id);
      return job ? { type: "Job", name: job.name } : null;
    }
    if (edge.source_trigger_id) {
      const trigger = triggers.find(t => t.id === edge.source_trigger_id);
      return trigger ? { type: "Trigger", name: trigger.type } : null;
    }
    return null;
  }, [edge, jobs, triggers]);

  const targetNode = useMemo(() => {
    const job = jobs.find(j => j.id === edge.target_job_id);
    return job ? { name: job.name } : null;
  }, [edge.target_job_id, jobs]);

  // Determine available options based on source
  const conditionOptions = useMemo(() => {
    const isSourceTrigger = !!edge.source_trigger_id;

    if (isSourceTrigger) {
      return [
        { value: "always", label: "Always" },
        {
          value: "js_expression",
          label: "Matches a Javascript Expression",
        },
      ];
    }

    return [
      { value: "on_job_success", label: "On Success" },
      { value: "on_job_failure", label: "On Failure" },
      { value: "always", label: "Always" },
      {
        value: "js_expression",
        label: "Matches a Javascript Expression",
      },
    ];
  }, [edge.source_trigger_id]);

  // Watch condition_type to show/hide expression editor
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
  const isExpressionUnsafe = /(\bimport\b|\brequire\b|\bprocess\b|\bawait\b|\beval\b)/.test(
    conditionExpression
  );

  const handleDelete = useCallback(() => {
    if (
      window.confirm(
        "Are you sure you want to delete this edge? This action cannot be undone."
      )
    ) {
      removeEdge(edge.id);
      clearSelection();
    }
  }, [edge.id, removeEdge, clearSelection]);

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">Path</h3>

        {/* Source/Target Display */}
        <div className="space-y-2 mb-4 p-3 bg-slate-50 rounded border border-slate-200">
          <div>
            <span className="text-xs text-slate-500 block">Source</span>
            <p className="text-sm text-slate-900">
              {sourceNode
                ? `${sourceNode.type}: ${sourceNode.name}`
                : "Unknown"}
            </p>
          </div>
          <div>
            <span className="text-xs text-slate-500 block">Target</span>
            <p className="text-sm text-slate-900">
              {targetNode ? `Job: ${targetNode.name}` : "Unknown"}
            </p>
          </div>
        </div>

        {/* Label Field */}
        <form.AppField name="condition_label">
          {field => <field.TextField label="Label" />}
        </form.AppField>

        {/* Condition Type Dropdown */}
        <form.AppField name="condition_type">
          {field => (
            <field.SelectField
              label="Condition"
              options={conditionOptions}
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
                      <span
                        className="text-yellow-600"
                        title="Expression contains potentially unsafe functions"
                      >
                        <svg
                          className="w-4 h-4"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                          />
                        </svg>
                      </span>
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
                  Use the state from the previous step to decide whether
                  this step should run.
                </p>
                <p>
                  Must be a single JavaScript expression with `state` in
                  scope.
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
      </div>

      {/* Footer */}
      <div className="border-t border-slate-200 pt-4 mt-6">
        <div className="flex justify-between items-center">
          <div>
            {edge.source_trigger_id ? (
              <p className="text-xs text-slate-600 italic">
                This path will be active if its trigger is enabled
              </p>
            ) : (
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
            )}
          </div>

          {!edge.source_trigger_id && (
            <button
              onClick={handleDelete}
              className="text-sm text-red-600 hover:text-red-700 font-medium"
            >
              Delete
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
