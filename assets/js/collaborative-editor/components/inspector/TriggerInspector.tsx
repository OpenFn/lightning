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
  const [copySuccess, setCopySuccess] = useState<string>("");

  // Create form config with Yjs integration
  const formConfig = createTriggerForm(trigger);

  const form = useForm(formConfig);

  // Generate webhook URL based on trigger ID
  const webhookUrl = new URL(
    `/i/${trigger.id}`,
    window.location.origin,
  ).toString();

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
            // form.handleSubmit();
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
                      <form.Field
                        name="cron_expression"
                        listeners={{ onChangeDebounceMs: 2000 }}
                      >
                        {(cronField) => {
                          console.log(cronField.state);
                          return (
                            <div>
                              <label
                                htmlFor={cronField.name}
                                className="block text-xs font-medium text-gray-500 mb-1"
                              >
                                Schedule Expression
                              </label>
                              <CronFieldBuilder
                                value={cronField.state.value}
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
                                  {error.message}
                                </p>
                              ))}
                            </div>
                          );
                        }}
                      </form.Field>
                    </div>
                  </div>
                );
              }

              if (currentType === "kafka") {
                return (
                  <div className="space-y-4">
                    <div className="border-t pt-4">
                      <h4 className="text-xs font-medium text-gray-700 mb-3">
                        Kafka Connection Configuration
                      </h4>

                      {/* Connection Settings */}
                      <div className="space-y-4">
                        {/* Hosts Field */}
                        <form.Field name="kafka_configuration.hosts">
                          {(field) => (
                            <div>
                              <label
                                htmlFor={field.name}
                                className="block text-xs font-medium text-gray-500 mb-1"
                              >
                                Kafka Hosts
                              </label>
                              <input
                                id={field.name}
                                type="text"
                                value={field.state.value || ""}
                                onChange={(e) =>
                                  field.handleChange(e.target.value)
                                }
                                onBlur={field.handleBlur}
                                placeholder="localhost:9092,broker2:9092"
                                className={`
                                  block w-full px-3 py-2 border rounded-md text-sm
                                  ${
                                    field.state.meta.errors.length > 0
                                      ? "border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500"
                                      : "border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
                                  }
                                  focus:outline-none focus:ring-1
                                `}
                              />
                              <p className="mt-1 text-xs text-gray-500">
                                Comma-separated list of host:port pairs
                              </p>
                              {field.state.meta.errors.map((error) => (
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

                        {/* Topics Field */}
                        <form.Field name="kafka_configuration.topics">
                          {(field) => (
                            <div>
                              <label
                                htmlFor={field.name}
                                className="block text-xs font-medium text-gray-500 mb-1"
                              >
                                Topics
                              </label>
                              <input
                                id={field.name}
                                type="text"
                                value={field.state.value || ""}
                                onChange={(e) =>
                                  field.handleChange(e.target.value)
                                }
                                onBlur={field.handleBlur}
                                placeholder="topic1,topic2,topic3"
                                className={`
                                  block w-full px-3 py-2 border rounded-md text-sm
                                  ${
                                    field.state.meta.errors.length > 0
                                      ? "border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500"
                                      : "border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
                                  }
                                  focus:outline-none focus:ring-1
                                `}
                              />
                              <p className="mt-1 text-xs text-gray-500">
                                Comma-separated list of topic names
                              </p>
                              {field.state.meta.errors.map((error) => (
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

                        {/* SSL Configuration */}
                        <form.Field name="kafka_configuration.ssl">
                          {(field) => (
                            <div className="flex items-center">
                              <input
                                id={field.name}
                                type="checkbox"
                                checked={field.state.value || false}
                                onChange={(e) =>
                                  field.handleChange(e.target.checked)
                                }
                                onBlur={field.handleBlur}
                                className="h-4 w-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
                              />
                              <label
                                htmlFor={field.name}
                                className="ml-2 text-xs font-medium text-gray-700"
                              >
                                Enable SSL/TLS encryption
                              </label>
                            </div>
                          )}
                        </form.Field>

                        {/* SASL Configuration */}
                        <form.Field name="kafka_configuration.sasl">
                          {(field) => (
                            <div>
                              <label
                                htmlFor={field.name}
                                className="block text-xs font-medium text-gray-500 mb-1"
                              >
                                SASL Authentication
                              </label>
                              <select
                                id={field.name}
                                value={field.state.value || "none"}
                                onChange={(e) =>
                                  field.handleChange(
                                    e.target.value as
                                      | "none"
                                      | "plain"
                                      | "scram_sha_256"
                                      | "scram_sha_512",
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
                                <option value="none">No Authentication</option>
                                <option value="plain">PLAIN</option>
                                <option value="scram_sha_256">
                                  SCRAM-SHA-256
                                </option>
                                <option value="scram_sha_512">
                                  SCRAM-SHA-512
                                </option>
                              </select>
                              {field.state.meta.errors.map((error) => (
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

                        {/* Conditional Username/Password Fields */}
                        <form.Field name="kafka_configuration.sasl">
                          {(saslField) => {
                            const requiresAuth =
                              saslField.state.value !== "none";

                            if (!requiresAuth) return null;

                            return (
                              <div className="space-y-4 pl-4 border-l-2 border-gray-200">
                                {/* Username Field */}
                                <form.Field name="kafka_configuration.username">
                                  {(field) => (
                                    <div>
                                      <label
                                        htmlFor={field.name}
                                        className="block text-xs font-medium text-gray-500 mb-1"
                                      >
                                        Username
                                      </label>
                                      <input
                                        id={field.name}
                                        type="text"
                                        value={field.state.value || ""}
                                        onChange={(e) =>
                                          field.handleChange(e.target.value)
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
                                      />
                                      {field.state.meta.errors.map((error) => (
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

                                {/* Password Field */}
                                <form.Field name="kafka_configuration.password">
                                  {(field) => (
                                    <div>
                                      <label
                                        htmlFor={field.name}
                                        className="block text-xs font-medium text-gray-500 mb-1"
                                      >
                                        Password
                                      </label>
                                      <input
                                        id={field.name}
                                        type="password"
                                        value={field.state.value || ""}
                                        onChange={(e) =>
                                          field.handleChange(e.target.value)
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
                                      />
                                      {field.state.meta.errors.map((error) => (
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
                            );
                          }}
                        </form.Field>

                        {/* Advanced Settings */}
                        <div className="border-t pt-4">
                          <h5 className="text-xs font-medium text-gray-700 mb-3">
                            Advanced Settings
                          </h5>

                          {/* Initial Offset Reset Policy */}
                          <form.Field name="kafka_configuration.initial_offset_reset_policy">
                            {(field) => (
                              <div>
                                <label
                                  htmlFor={field.name}
                                  className="block text-xs font-medium text-gray-500 mb-1"
                                >
                                  Initial Offset Reset Policy
                                </label>
                                <select
                                  id={field.name}
                                  value={field.state.value || "latest"}
                                  onChange={(e) =>
                                    field.handleChange(
                                      e.target.value as "earliest" | "latest",
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
                                  <option value="latest">Latest</option>
                                  <option value="earliest">Earliest</option>
                                </select>
                                <p className="mt-1 text-xs text-gray-500">
                                  What to do when there is no initial offset
                                </p>
                                {field.state.meta.errors.map((error) => (
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

                          {/* Connect Timeout */}
                          <form.Field name="kafka_configuration.connect_timeout">
                            {(field) => (
                              <div>
                                <label
                                  htmlFor={field.name}
                                  className="block text-xs font-medium text-gray-500 mb-1"
                                >
                                  Connect Timeout (ms)
                                </label>
                                <input
                                  id={field.name}
                                  type="number"
                                  min="1000"
                                  value={field.state.value || 30000}
                                  onChange={(e) =>
                                    field.handleChange(Number(e.target.value))
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
                                />
                                <p className="mt-1 text-xs text-gray-500">
                                  Connection timeout in milliseconds (minimum
                                  1000)
                                </p>
                                {field.state.meta.errors.map((error) => (
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
