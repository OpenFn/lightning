import type { ReactNode } from 'react';

import { useSessionContext } from '../../../hooks/useSessionContext';
import { InspectorLayout } from '../InspectorLayout';

type PickableType = 'webhook' | 'cron' | 'kafka';

interface TriggerPickerProps {
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Return to the Choose step (back arrow). */
  onBack: () => void;
  /**
   * Apply the picked type to the local DRAFT and return to Choose. Used for
   * webhook (the type the wizard fully supports).
   */
  onPickDraftType: (type: PickableType) => void;
  /**
   * Commit a type switch immediately (no draft). Used for cron/kafka, which
   * have no wizard yet in this webhook-first phase — selecting them switches
   * the trigger type and hands off to the legacy editor on the show panel.
   */
  onCommitType: (type: PickableType) => void;
}

interface PickerRowProps {
  icon: string;
  title: string;
  description: string;
  badge?: string;
  onClick: () => void;
}

function PickerRow({
  icon,
  title,
  description,
  badge,
  onClick,
}: PickerRowProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-start gap-3 rounded-lg border border-slate-200
        p-3 text-left transition-colors hover:border-slate-300 hover:bg-slate-50
        focus:outline-none focus:ring-1 focus:ring-indigo-500"
    >
      <span
        className={`${icon} h-5 w-5 shrink-0 text-slate-500`}
        aria-hidden="true"
      />
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-2">
          <span className="text-sm font-medium text-slate-800">{title}</span>
          {badge && (
            <span
              className="rounded-full bg-indigo-50 px-2 py-0.5 text-xs
                font-medium text-indigo-600"
            >
              {badge}
            </span>
          )}
        </span>
        <span className="mt-0.5 block text-xs text-slate-500">
          {description}
        </span>
      </span>
    </button>
  );
}

/**
 * The "What triggers this workflow?" picker, reached only via the Choose step's
 * **Change** action. Lists only the implemented trigger types.
 *
 * Webhook selection writes the new type's defaults into the local draft and
 * returns to Choose. Cron/Kafka have no dedicated wizard yet, so selecting them
 * commits the type switch immediately (documented webhook-first limitation) and
 * the show panel then renders the legacy `TriggerForm` for that type.
 */
export function TriggerPicker({
  onClose,
  onBack,
  onPickDraftType,
  onCommitType,
}: TriggerPickerProps): ReactNode {
  const { config } = useSessionContext();
  const kafkaEnabled = Boolean(config?.kafka_triggers_enabled);

  return (
    <InspectorLayout
      title="Select trigger"
      onClose={onClose}
      showBackButton
      onBack={onBack}
    >
      <div className="space-y-4 p-6">
        <div>
          <h3 className="text-base font-semibold text-slate-900">
            What triggers this workflow?
          </h3>
          <p className="mt-1 text-sm text-slate-500">
            A trigger is a module that starts this workflow, it could be
            external like a webhook or internal like a timer
          </p>
        </div>

        <div className="space-y-2">
          <PickerRow
            icon="hero-globe-alt"
            title="On webhook call"
            description="Run the workflow, on receiving an HTTP request."
            badge="Popular"
            onClick={() => onPickDraftType('webhook')}
          />
          <PickerRow
            icon="hero-clock"
            title="On a Schedule"
            description="Schedule workflows to run at specific intervals."
            onClick={() => onCommitType('cron')}
          />
          {kafkaEnabled && (
            <PickerRow
              icon="hero-queue-list"
              title="Kafka"
              description="Consume messages from a Kafka topic."
              onClick={() => onCommitType('kafka')}
            />
          )}
        </div>
      </div>
    </InspectorLayout>
  );
}
