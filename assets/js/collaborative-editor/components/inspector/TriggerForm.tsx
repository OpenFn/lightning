import { useCallback, useState } from 'react';

import { TriggerSchema } from '#/collaborative-editor/types/trigger';
import _logger from '#/utils/logger';

import { useWorkflowActions } from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { useAppForm } from '../form';
import { createZodValidator } from '../form/createZodValidator';

import { CronFieldBuilder } from './CronFieldBuilder';

interface TriggerFormProps {
  trigger: Workflow.Trigger;
}

const logger = _logger.ns('TriggerForm').seal();

/**
 * Pure form component for trigger configuration.
 * Handles trigger type, enabled toggle, and type-specific fields
 * (webhook URL, cron expression, kafka config).
 */
export function TriggerForm({ trigger }: TriggerFormProps) {
  const { updateTrigger } = useWorkflowActions();
  const [copySuccess, setCopySuccess] = useState<string>('');
  const [showAdvancedSettings, setShowAdvancedSettings] = useState(false);

  const form = useAppForm({
    defaultValues: trigger,
    listeners: {
      onChange: ({ formApi }) => {
        if (trigger.id) {
          updateTrigger(trigger.id, formApi.state.values);
        }
      },
    },
    validators: {
      onChange: createZodValidator(TriggerSchema),
    },
  });

  // Generate webhook URL based on trigger ID
  const webhookUrl = new URL(
    `/i/${trigger.id}`,
    window.location.origin
  ).toString();

  // Copy to clipboard function
  const copyToClipboard = useCallback((text: string) => {
    void (async () => {
      try {
        await navigator.clipboard.writeText(text);
        setCopySuccess('Copied!');
        setTimeout(() => setCopySuccess(''), 2000);
      } catch {
        setCopySuccess('Failed to copy');
        setTimeout(() => setCopySuccess(''), 2000);
      }
    })();
  }, []);

  return (
    <div className="px-6 py-6 space-y-4">
      <div>
        <form
          onSubmit={e => {
            e.preventDefault();
            e.stopPropagation();
          }}
          className="space-y-4"
        >
          {/* Trigger Type Selection */}
          <form.Field name="type">
            {field => (
              <div className="pb-6 border-b border-slate-200">
                <label
                  htmlFor={field.name}
                  className="block text-sm font-medium text-slate-800 mb-1"
                >
                  Trigger Type
                </label>
                <select
                  id={field.name}
                  value={field.state.value}
                  onChange={e =>
                    field.handleChange(
                      e.target.value as 'webhook' | 'cron' | 'kafka'
                    )
                  }
                  onBlur={field.handleBlur}
                  className={`
                    block w-full px-3 py-2 border rounded-md text-sm
                    ${
                      field.state.meta.errors.length > 0
                        ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                        : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
                    }
                    focus:outline-none focus:ring-1
                  `}
                >
                  <option value="webhook">Webhook</option>
                  <option value="cron">Cron</option>
                  <option value="kafka">Kafka</option>
                </select>
                {field.state.meta.errors.map(error => (
                  <p key={error} className="mt-1 text-xs text-red-600">
                    {error}
                  </p>
                ))}
              </div>
            )}
          </form.Field>

          {/* Conditional Trigger Type-Specific Fields */}
          <form.Field name="type">
            {field => {
              const currentType = field.state.value;

              if (currentType === 'webhook') {
                return (
                  <div className="space-y-4">
                    {/* Webhook URL Display */}
                    <div>
                      <label
                        htmlFor="webhook-url"
                        className="block text-sm font-medium leading-6 text-slate-800"
                      >
                        Webhook URL
                      </label>
                      <div className="mt-2 flex rounded-md shadow-xs">
                        <input
                          id="webhook-url"
                          type="text"
                          value={webhookUrl}
                          readOnly
                          disabled
                          className="block w-full flex-1 rounded-l-lg text-slate-900 disabled:bg-gray-50 disabled:text-gray-500 border border-r-0 border-secondary-300 sm:text-sm sm:leading-6 font-mono"
                        />
                        <button
                          type="button"
                          onClick={() => copyToClipboard(webhookUrl)}
                          className="w-[100px] inline-block relative rounded-r-lg px-3 text-sm font-normal text-gray-900 border border-secondary-300 hover:bg-gray-50"
                        >
                          {copySuccess || 'Copy URL'}
                        </button>
                      </div>
                    </div>
                  </div>
                );
              }

              if (currentType === 'cron') {
                return (
                  <div className="space-y-4">
                    {/* <div className="border-t pt-4"> */}
                    {/* Cron Expression Field */}
                    <form.Field
                      name="cron_expression"
                      listeners={{ onChangeDebounceMs: 2000 }}
                    >
                      {cronField => {
                        logger.log('Cron field state:', cronField.state);
                        return (
                          <div>
                            <CronFieldBuilder
                              value={cronField.state.value}
                              onChange={cronExpr =>
                                cronField.handleChange(cronExpr)
                              }
                              onBlur={cronField.handleBlur}
                              className=""
                            />
                            {cronField.state.meta.errors.map(error => (
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
                    {/* </div> */}
                  </div>
                );
              }

              if (currentType === 'kafka') {
                return (
                  <div className="space-y-6">
                    {/* Connection Settings */}
                    <div className="space-y-4">
                      <h4 className="text-xs font-semibold text-slate-700 uppercase tracking-wide">
                        Connection
                      </h4>
                      {/* Hosts Field */}
                      <form.Field name="kafka_configuration.hosts">
                        {field => (
                          <div>
                            <label
                              htmlFor={field.name}
                              className="block text-sm font-medium text-slate-800 mb-1"
                            >
                              Kafka Hosts
                            </label>
                            <input
                              id={field.name}
                              type="text"
                              value={field.state.value || ''}
                              onChange={e => field.handleChange(e.target.value)}
                              onBlur={field.handleBlur}
                              placeholder="localhost:9092,broker2:9092"
                              className={`
                                  block w-full px-3 py-2 border rounded-md text-sm
                                  ${
                                    field.state.meta.errors.length > 0
                                      ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                                      : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
                                  }
                                  focus:outline-none focus:ring-1
                                `}
                            />
                            <p className="mt-1 text-xs text-slate-500">
                              Comma-separated list of host:port pairs
                            </p>
                            {field.state.meta.errors.map(error => (
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
                        {field => (
                          <div>
                            <label
                              htmlFor={field.name}
                              className="block text-sm font-medium text-slate-800 mb-1"
                            >
                              Topics
                            </label>
                            <input
                              id={field.name}
                              type="text"
                              value={field.state.value || ''}
                              onChange={e => field.handleChange(e.target.value)}
                              onBlur={field.handleBlur}
                              placeholder="topic1,topic2,topic3"
                              className={`
                                  block w-full px-3 py-2 border rounded-md text-sm
                                  ${
                                    field.state.meta.errors.length > 0
                                      ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                                      : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
                                  }
                                  focus:outline-none focus:ring-1
                                `}
                            />
                            <p className="mt-1 text-xs text-slate-500">
                              Comma-separated list of topic names
                            </p>
                            {field.state.meta.errors.map(error => (
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

                    {/* Security Settings */}
                    <div className="space-y-4 border-t border-slate-200 pt-6">
                      <h4 className="text-xs font-semibold text-slate-700 uppercase tracking-wide">
                        Security
                      </h4>
                      {/* SSL Configuration */}
                      <form.Field name="kafka_configuration.ssl">
                        {field => (
                          <div className="flex items-center">
                            <input
                              id={field.name}
                              type="checkbox"
                              checked={field.state.value || false}
                              onChange={e =>
                                field.handleChange(e.target.checked)
                              }
                              onBlur={field.handleBlur}
                              className="h-4 w-4 text-indigo-600 border-slate-300 rounded focus:ring-indigo-500"
                            />
                            <label
                              htmlFor={field.name}
                              className="ml-2 text-sm font-medium text-slate-800"
                            >
                              Enable SSL/TLS encryption
                            </label>
                          </div>
                        )}
                      </form.Field>

                      {/* SASL Configuration */}
                      <form.Field name="kafka_configuration.sasl">
                        {field => (
                          <div>
                            <label
                              htmlFor={field.name}
                              className="block text-sm font-medium text-slate-800 mb-1"
                            >
                              SASL Authentication
                            </label>
                            <select
                              id={field.name}
                              value={field.state.value || 'none'}
                              onChange={e =>
                                field.handleChange(
                                  e.target.value as
                                    | 'none'
                                    | 'plain'
                                    | 'scram_sha_256'
                                    | 'scram_sha_512'
                                )
                              }
                              onBlur={field.handleBlur}
                              className={`
                                  block w-full px-3 py-2 border rounded-md text-sm
                                  ${
                                    field.state.meta.errors.length > 0
                                      ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                                      : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
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
                            {field.state.meta.errors.map(error => (
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
                        {saslField => {
                          const requiresAuth = saslField.state.value !== 'none';

                          if (!requiresAuth) return null;

                          return (
                            <div className="space-y-4 animate-in fade-in slide-in-from-top-2 duration-200">
                              {/* Username Field */}
                              <form.Field name="kafka_configuration.username">
                                {field => (
                                  <div>
                                    <label
                                      htmlFor={field.name}
                                      className="block text-sm font-medium text-slate-800 mb-1"
                                    >
                                      Username
                                    </label>
                                    <input
                                      id={field.name}
                                      type="text"
                                      value={field.state.value || ''}
                                      onChange={e =>
                                        field.handleChange(e.target.value)
                                      }
                                      onBlur={field.handleBlur}
                                      className={`
                                          block w-full px-3 py-2 border rounded-md text-sm
                                          ${
                                            field.state.meta.errors.length > 0
                                              ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                                              : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
                                          }
                                          focus:outline-none focus:ring-1
                                        `}
                                    />
                                    {field.state.meta.errors.map(error => (
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
                                {field => (
                                  <div>
                                    <label
                                      htmlFor={field.name}
                                      className="block text-sm font-medium text-slate-800 mb-1"
                                    >
                                      Password
                                    </label>
                                    <input
                                      id={field.name}
                                      type="password"
                                      value={field.state.value || ''}
                                      onChange={e =>
                                        field.handleChange(e.target.value)
                                      }
                                      onBlur={field.handleBlur}
                                      className={`
                                          block w-full px-3 py-2 border rounded-md text-sm
                                          ${
                                            field.state.meta.errors.length > 0
                                              ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                                              : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
                                          }
                                          focus:outline-none focus:ring-1
                                        `}
                                    />
                                    {field.state.meta.errors.map(error => (
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
                    </div>

                    {/* Advanced Settings - Collapsible */}
                    <div className="space-y-4 border-t border-slate-200 pt-6">
                      <button
                        type="button"
                        onClick={() =>
                          setShowAdvancedSettings(!showAdvancedSettings)
                        }
                        className="text-xs font-semibold text-slate-700 uppercase tracking-wide hover:text-slate-900 focus:outline-none inline-flex items-center gap-1"
                      >
                        <span
                          className={`hero-chevron-right h-3 w-3 transition-transform ${
                            showAdvancedSettings ? 'rotate-90' : ''
                          }`}
                        />
                        Advanced
                      </button>

                      {showAdvancedSettings && (
                        <div className="mt-3 space-y-4">
                          {/* Initial Offset Reset Policy */}
                          <form.Field name="kafka_configuration.initial_offset_reset_policy">
                            {field => (
                              <div>
                                <label
                                  htmlFor={field.name}
                                  className="block text-sm font-medium text-slate-800 mb-1"
                                >
                                  Initial Offset Reset Policy
                                </label>
                                <select
                                  id={field.name}
                                  value={field.state.value || 'latest'}
                                  onChange={e =>
                                    field.handleChange(
                                      e.target.value as 'earliest' | 'latest'
                                    )
                                  }
                                  onBlur={field.handleBlur}
                                  className={`
                                        block w-full px-3 py-2 border rounded-md text-sm
                                        ${
                                          field.state.meta.errors.length > 0
                                            ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                                            : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
                                        }
                                        focus:outline-none focus:ring-1
                                      `}
                                >
                                  <option value="latest">Latest</option>
                                  <option value="earliest">Earliest</option>
                                </select>
                                <p className="mt-1 text-xs text-slate-500">
                                  What to do when there is no initial offset
                                </p>
                                {field.state.meta.errors.map(error => (
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
                            {field => (
                              <div>
                                <label
                                  htmlFor={field.name}
                                  className="block text-sm font-medium text-slate-800 mb-1"
                                >
                                  Connect Timeout (ms)
                                </label>
                                <input
                                  id={field.name}
                                  type="number"
                                  min="1000"
                                  value={field.state.value || 30000}
                                  onChange={e =>
                                    field.handleChange(Number(e.target.value))
                                  }
                                  onBlur={field.handleBlur}
                                  className={`
                                        block w-full px-3 py-2 border rounded-md text-sm
                                        ${
                                          field.state.meta.errors.length > 0
                                            ? 'border-red-300 text-red-900 focus:border-red-500 focus:ring-red-500'
                                            : 'border-slate-300 focus:border-indigo-500 focus:ring-indigo-500'
                                        }
                                        focus:outline-none focus:ring-1
                                      `}
                                />
                                <p className="mt-1 text-xs text-slate-500">
                                  Connection timeout in milliseconds (minimum
                                  1000)
                                </p>
                                {field.state.meta.errors.map(error => (
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
                      )}
                    </div>
                  </div>
                );
              }

              return null;
            }}
          </form.Field>
        </form>
      </div>
    </div>
  );
}
