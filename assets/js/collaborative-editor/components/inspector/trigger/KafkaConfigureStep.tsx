import { useState } from 'react';

import { cn } from '#/utils/cn';

import { useWorkflowReadOnly } from '../../../hooks/useWorkflow';
import { createDefaultTrigger } from '../../../types/trigger';
import type { Workflow } from '../../../types/workflow';
import { Button } from '../../Button';
import { InspectorLayout } from '../InspectorLayout';

import { WizardBreadcrumb } from './WizardBreadcrumb';

interface KafkaConfigureStepProps {
  /** The local trigger draft. */
  draft: Workflow.Trigger;
  /** Shallow-merge updates into the draft. */
  mergeDraft: (updates: Partial<Workflow.Trigger>) => void;
  /** Validation error to surface near the footer after a failed Finish. */
  validationError: string | null;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Return to the Choose step (header arrow + breadcrumb "Choose" crumb). */
  onBack: () => void;
  /** Validate + commit the draft (Finish). */
  onFinish: () => void;
}

type KafkaConfig = NonNullable<
  Extract<Workflow.Trigger, { type: 'kafka' }>['kafka_configuration']
>;

type SaslMechanism = 'plain' | 'scram_sha_256' | 'scram_sha_512';

// A complete default kafka_configuration shape used as a safe merge base so a
// partial draft never drops required fields.
const DEFAULT_KAFKA_CONFIG = (
  createDefaultTrigger('kafka') as Extract<Workflow.Trigger, { type: 'kafka' }>
).kafka_configuration;

const inputClass = cn(
  'block w-full rounded-md border border-slate-300 px-3 py-2 text-sm',
  'focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500',
  'disabled:cursor-not-allowed disabled:opacity-50'
);

/**
 * The kafka wizard's "Configure" step (#4787). A full-fidelity port of the
 * legacy `TriggerForm` kafka branch, but bound entirely to the local DRAFT via
 * `mergeDraft` (no TanStack form, no live `updateTrigger`); nothing is persisted
 * until Finish.
 *
 * Mirrors {@link CronConfigureStep}'s chrome: `InspectorLayout` titled "Kafka"
 * with a header back arrow, the Choose › Configure breadcrumb, and a full-width
 * primary **Finish** footer with the `validationError` above it.
 */
export function KafkaConfigureStep({
  draft,
  mergeDraft,
  validationError,
  onClose,
  onBack,
  onFinish,
}: KafkaConfigureStepProps) {
  const { isReadOnly } = useWorkflowReadOnly();
  const [showAdvanced, setShowAdvanced] = useState(false);

  // Always merge against a complete config so required fields survive a partial
  // draft (e.g. an in-progress type switch).
  const config: KafkaConfig = {
    ...DEFAULT_KAFKA_CONFIG,
    ...(draft.kafka_configuration ?? {}),
  };

  const patchConfig = (updates: Partial<KafkaConfig>) => {
    mergeDraft({
      kafka_configuration: { ...config, ...updates },
    } as Partial<Workflow.Trigger>);
  };

  const requiresAuth = config.sasl !== null;

  const footer = (
    <div className="space-y-2">
      {validationError && (
        <p className="text-xs text-red-600">{validationError}</p>
      )}
      <Button variant="primary" onClick={onFinish} className="w-full">
        <span className="inline-flex items-center gap-1.5">
          Finish
          <span className="hero-arrow-right-micro h-4 w-4" />
        </span>
      </Button>
    </div>
  );

  return (
    <InspectorLayout
      title="Kafka"
      onClose={onClose}
      showBackButton
      onBack={onBack}
      footer={footer}
    >
      <div className="space-y-6 p-6">
        <WizardBreadcrumb
          step="configure"
          onNavigate={target => {
            if (target === 'choose') onBack();
          }}
        />

        {/* Connection */}
        <div className="space-y-4">
          <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-700">
            Connection
          </h4>

          <div>
            <label
              htmlFor="kafka-hosts"
              className="mb-1 block text-sm font-medium text-slate-800"
            >
              Kafka Hosts
            </label>
            <input
              id="kafka-hosts"
              type="text"
              value={config.hosts_string || ''}
              onChange={e => patchConfig({ hosts_string: e.target.value })}
              disabled={isReadOnly}
              autoComplete="off"
              placeholder="localhost:9092, broker2:9092"
              className={inputClass}
            />
            <p className="mt-1 text-xs text-slate-500">
              Comma-separated list of host:port pairs
            </p>
          </div>

          <div>
            <label
              htmlFor="kafka-topics"
              className="mb-1 block text-sm font-medium text-slate-800"
            >
              Topics
            </label>
            <input
              id="kafka-topics"
              type="text"
              value={config.topics_string || ''}
              onChange={e => patchConfig({ topics_string: e.target.value })}
              disabled={isReadOnly}
              autoComplete="off"
              placeholder="topic1, topic2, topic3"
              className={inputClass}
            />
            <p className="mt-1 text-xs text-slate-500">
              Comma-separated list of topic names
            </p>
          </div>
        </div>

        {/* Security */}
        <div className="space-y-4 border-t border-slate-200 pt-6">
          <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-700">
            Security
          </h4>

          <div className="flex items-center">
            <input
              id="kafka-ssl"
              type="checkbox"
              checked={config.ssl || false}
              onChange={e => patchConfig({ ssl: e.target.checked })}
              disabled={isReadOnly}
              className="h-4 w-4 rounded border-slate-300 text-indigo-600 focus:ring-indigo-500 disabled:cursor-not-allowed disabled:opacity-50"
            />
            <label
              htmlFor="kafka-ssl"
              className="ml-2 text-sm font-medium text-slate-800"
            >
              Enable SSL/TLS encryption
            </label>
          </div>

          <div>
            <label
              htmlFor="kafka-sasl"
              className="mb-1 block text-sm font-medium text-slate-800"
            >
              SASL Authentication
            </label>
            <select
              id="kafka-sasl"
              value={config.sasl ?? ''}
              onChange={e =>
                patchConfig({
                  sasl:
                    e.target.value === ''
                      ? null
                      : (e.target.value as SaslMechanism),
                })
              }
              disabled={isReadOnly}
              className={inputClass}
            >
              <option value="">No Authentication</option>
              <option value="plain">PLAIN</option>
              <option value="scram_sha_256">SCRAM-SHA-256</option>
              <option value="scram_sha_512">SCRAM-SHA-512</option>
            </select>
          </div>

          {requiresAuth && (
            <div className="space-y-4">
              <div>
                <label
                  htmlFor="kafka-username"
                  className="mb-1 block text-sm font-medium text-slate-800"
                >
                  Username
                </label>
                <input
                  id="kafka-username"
                  type="text"
                  value={config.username || ''}
                  onChange={e => patchConfig({ username: e.target.value })}
                  disabled={isReadOnly}
                  autoComplete="off"
                  className={inputClass}
                />
              </div>

              <div>
                <label
                  htmlFor="kafka-password"
                  className="mb-1 block text-sm font-medium text-slate-800"
                >
                  Password
                </label>
                <input
                  id="kafka-password"
                  type="password"
                  value={config.password || ''}
                  onChange={e => patchConfig({ password: e.target.value })}
                  disabled={isReadOnly}
                  autoComplete="off"
                  className={inputClass}
                />
              </div>
            </div>
          )}
        </div>

        {/* Advanced (collapsible) */}
        <div className="space-y-4 border-t border-slate-200 pt-6">
          <button
            type="button"
            onClick={() => setShowAdvanced(prev => !prev)}
            disabled={isReadOnly}
            className="inline-flex items-center gap-1 text-xs font-semibold uppercase tracking-wide text-slate-700 hover:text-slate-900 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
          >
            <span
              className={cn(
                'hero-chevron-right h-3 w-3 transition-transform',
                showAdvanced && 'rotate-90'
              )}
            />
            Advanced
          </button>

          {showAdvanced && (
            <div className="mt-3 space-y-4">
              <div>
                <label
                  htmlFor="kafka-offset-policy"
                  className="mb-1 block text-sm font-medium text-slate-800"
                >
                  Initial Offset Reset Policy
                </label>
                <select
                  id="kafka-offset-policy"
                  value={config.initial_offset_reset_policy || 'latest'}
                  onChange={e =>
                    patchConfig({
                      initial_offset_reset_policy: e.target.value as
                        | 'earliest'
                        | 'latest',
                    })
                  }
                  disabled={isReadOnly}
                  className={inputClass}
                >
                  <option value="latest">Latest</option>
                  <option value="earliest">Earliest</option>
                </select>
                <p className="mt-1 text-xs text-slate-500">
                  What to do when there is no initial offset
                </p>
              </div>

              <div>
                <label
                  htmlFor="kafka-connect-timeout"
                  className="mb-1 block text-sm font-medium text-slate-800"
                >
                  Connect Timeout (ms)
                </label>
                <input
                  id="kafka-connect-timeout"
                  type="number"
                  min="1000"
                  value={config.connect_timeout || 30000}
                  onChange={e =>
                    patchConfig({ connect_timeout: Number(e.target.value) })
                  }
                  disabled={isReadOnly}
                  autoComplete="off"
                  className={inputClass}
                />
                <p className="mt-1 text-xs text-slate-500">
                  Connection timeout in milliseconds (minimum 1000)
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </InspectorLayout>
  );
}
