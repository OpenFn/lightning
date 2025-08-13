import { useForm } from "@tanstack/react-form";
import type React from "react";
import { useState } from "react";
import { useTriggerFormActions } from "../../contexts/WorkflowStoreProvider";
import type { Workflow } from "../../types";
import { CronFieldBuilder } from "./CronFieldBuilder";

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
}

export const TriggerInspector: React.FC<TriggerInspectorProps> = ({
  trigger,
}) => {
  const { createTriggerForm } = useTriggerFormActions();
  const formConfig = createTriggerForm(trigger);
  const [copySuccess, setCopySuccess] = useState<string>("");

  const form = useForm(formConfig);

  // Generate webhook URL based on trigger ID
  const webhookUrl = `/i/${trigger.id}`;

  // Copy to clipboard function
  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopySuccess("Copied!");
      setTimeout(() => setCopySuccess(""), 2000);
    } catch {
      setCopySuccess("Failed to copy");
      setTimeout(() => setCopySuccess(""), 2000);
    }
  };

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">
          Trigger Configuration
        </h3>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            e.stopPropagation();
            form.handleSubmit();
          }}
          className="space-y-4"
        >
          {/* Trigger Type Selection */}
          <form.Field name="type">
            {(field) => (
              <div>
                <label
                  htmlFor={field.name}
                  className="block text-xs font-medium text-gray-500 mb-1"
                >
                  Trigger Type
                </label>
                <select
                  id={field.name}
                  value={field.state.value}
                  onChange={(e) =>
                    field.handleChange(
                      e.target.value as "webhook" | "cron" | "kafka",
                    )
                  }
                  onBlur={field.handleBlur}
                  className={`
                    block w-full px-3 py-2 border rounded-md text-sm
                    ${
                      field.state.meta.errors.length > 0
                        ? "border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500"
                        : "border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
                    }
                    focus:outline-none focus:ring-1
                  `}
                >
                  <option value="webhook">Webhook</option>
                  <option value="cron">Cron</option>
                  <option value="kafka">Kafka</option>
                </select>
                {field.state.meta.errors.map((error) => (
                  <p key={error} className="mt-1 text-xs text-red-600">
                    {error}
                  </p>
                ))}
              </div>
            )}
          </form.Field>

          {/* Enabled Toggle */}
          <form.Field name="enabled">
            {(field) => (
              <div className="flex items-center">
                <input
                  id={field.name}
                  type="checkbox"
                  checked={field.state.value}
                  onChange={(e) => field.handleChange(e.target.checked)}
                  onBlur={field.handleBlur}
                  className="h-4 w-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
                />
                <label
                  htmlFor={field.name}
                  className="ml-2 text-xs font-medium text-gray-700"
                >
                  Enabled
                </label>
              </div>
            )}
          </form.Field>

          {/* Conditional Trigger Type-Specific Fields */}
          <form.Field name="type">
            {(field) => {
              const currentType = field.state.value;

              if (currentType === "webhook") {
                return (
                  <div className="space-y-4">
                    <div className="border-t pt-4">
                      <h4 className="text-xs font-medium text-gray-700 mb-3">
                        Webhook Configuration
                      </h4>

                      {/* Webhook URL Display */}
                      <div>
                        <label
                          htmlFor="webhook-url"
                          className="block text-xs font-medium text-gray-500 mb-1"
                        >
                          Webhook URL
                        </label>
                        <div className="flex items-center space-x-2">
                          <input
                            id="webhook-url"
                            type="text"
                            value={webhookUrl}
                            readOnly
                            className="flex-1 px-3 py-2 border border-gray-300 rounded-md text-sm bg-gray-50 text-gray-700 cursor-text"
                          />
                          <button
                            type="button"
                            onClick={() => copyToClipboard(webhookUrl)}
                            className="px-3 py-2 text-xs font-medium text-white bg-indigo-600 border border-transparent rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                          >
                            {copySuccess || "Copy"}
                          </button>
                        </div>
                        <p className="mt-1 text-xs text-gray-500">
                          Use this URL to trigger the workflow via HTTP POST
                          requests.
                        </p>
                      </div>
                    </div>
                  </div>
                );
              }

              if (currentType === "cron") {
                return (
                  <div className="space-y-4">
                    <div className="border-t pt-4">
                      <h4 className="text-xs font-medium text-gray-700 mb-3">
                        Cron Schedule Configuration
                      </h4>

                      {/* Cron Expression Field */}
                      <form.Field name="cron_expression">
                        {(cronField) => (
                          <div>
                            <label
                              htmlFor={cronField.name}
                              className="block text-xs font-medium text-gray-500 mb-1"
                            >
                              Schedule Expression
                            </label>
                            <CronFieldBuilder
                              value={cronField.state.value || "0 0 * * *"}
                              onChange={(cronExpr) =>
                                cronField.handleChange(cronExpr)
                              }
                              onBlur={cronField.handleBlur}
                              className=""
                            />
                            {cronField.state.meta.errors.map((error) => (
                              <p
                                key={error}
                                className="mt-1 text-xs text-red-600"
                              >
                                {error}
                              </p>
                            ))}
                          </div>
                        )}
                      </form.Field>
                    </div>
                  </div>
                );
              }

              return null;
            }}
          </form.Field>

          {/* Debug: Current form state */}
          <div className="mt-4 p-3 bg-gray-50 rounded-md">
            <h4 className="text-xs font-medium text-gray-500 mb-2">
              Debug Info
            </h4>
            <pre className="text-xs text-gray-600">
              {JSON.stringify(form.state.values, null, 2)}
            </pre>
          </div>
        </form>
      </div>
    </div>
  );
};
