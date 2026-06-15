import type { ReactNode } from 'react';

import { useSessionContext } from '../../../hooks/useSessionContext';
import { createDefaultTrigger } from '../../../types/trigger';
import type { Workflow } from '../../../types/workflow';
import { InspectorLayout } from '../InspectorLayout';

type PickableType = 'webhook' | 'cron' | 'kafka';

interface TriggerPickerProps {
  /** The local draft (read to avoid resetting config on a no-op re-pick). */
  draft: Workflow.Trigger;
  /** Shallow-merge updates into the draft. */
  mergeDraft: (updates: Partial<Workflow.Trigger>) => void;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Return to the Choose step (back arrow + after applying a draft type). */
  onReturnToChoose: () => void;
}

interface PickerRowProps {
  icon: string;
  title: string;
  description: string;
  onClick: () => void;
}

function PickerRow({ icon, title, description, onClick }: PickerRowProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-lg p-3 text-left
        transition-colors hover:bg-slate-50 focus:outline-none
        focus:ring-1 focus:ring-indigo-500"
    >
      <span
        className={`${icon} h-5 w-5 shrink-0 text-slate-500`}
        aria-hidden="true"
      />
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-medium text-slate-800">
          {title}
        </span>
        <span className="mt-0.5 block text-xs text-slate-500">
          {description}
        </span>
      </span>
      <span
        className="hero-chevron-right-mini h-4 w-4 shrink-0 text-slate-400"
        aria-hidden="true"
      />
    </button>
  );
}

/**
 * The "What triggers this workflow?" picker step, reached via the Choose step's
 * **Change** action. Lists only the implemented trigger types and owns the
 * wiring that applies a pick — so the wizard just renders `<TriggerPicker>` with
 * the draft handles rather than threading per-type callbacks through a wrapper.
 *
 * Every type applies to the LOCAL draft (only on an actual type change —
 * re-confirming the current type must not reset config) and returns to Choose;
 * nothing is persisted until Finish, so picking a type then Cancelling discards
 * it. The current `enabled` flag is preserved so switching type never silently
 * re-enables a disabled trigger.
 */
export function TriggerPicker({
  draft,
  mergeDraft,
  onClose,
  onReturnToChoose,
}: TriggerPickerProps): ReactNode {
  const { config } = useSessionContext();
  const kafkaEnabled = Boolean(config?.kafka_triggers_enabled);

  const pickDraftType = (type: PickableType) => {
    if (draft.type !== type) {
      // Drop `enabled` from the defaults so the draft keeps the trigger's
      // current enabled state — a type change must not re-enable a disabled one.
      const { enabled: _enabled, ...defaults } = createDefaultTrigger(type);
      mergeDraft(defaults as Partial<Workflow.Trigger>);
    }
    onReturnToChoose();
  };

  return (
    <InspectorLayout
      title="Select trigger"
      onClose={onClose}
      showBackButton
      onBack={onReturnToChoose}
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
            onClick={() => pickDraftType('webhook')}
          />
          <PickerRow
            icon="hero-clock"
            title="On a Schedule"
            description="Schedule workflows to run at specific intervals."
            onClick={() => pickDraftType('cron')}
          />
          {kafkaEnabled && (
            <PickerRow
              icon="hero-queue-list"
              title="Kafka"
              description="Consume messages from a Kafka topic."
              onClick={() => pickDraftType('kafka')}
            />
          )}
        </div>
      </div>
    </InspectorLayout>
  );
}
