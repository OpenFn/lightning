import { useCallback, useState } from 'react';

import type { Workflow } from '../../types/workflow';
import {
  useMarkEnableTriggerWarningSuppressed,
  useSuppressEnableTriggerWarning,
} from '../../hooks/useSessionContext';
import { useWorkflowActions } from '../../hooks/useWorkflow';
import { notifications } from '../../lib/notifications';
import { AlertDialog } from '../AlertDialog';
import { Toggle } from '../Toggle';
import { Tooltip } from '../../../components/Tooltip';

interface TriggerEnabledControlProps {
  trigger: Workflow.Trigger;
}

/**
 * Trigger enable/disable control for non-live (draft or sandbox) workflows.
 *
 * Lives in the trigger inspector footer, left of the Run button, matching the
 * original "Enabled" toggle. The parent only renders it when the workflow is
 * editable (non-live); a live workflow is lifecycle-controlled and shows no
 * toggle.
 *
 * Enabling a trigger on a still-in-development workflow starts routing real
 * events to it, so turning it on (off -> on) is gated behind a warning modal
 * unless the user has chosen to suppress it. Turning it off (on -> off) is
 * immediate and never warns. The server is the real guard and refuses the
 * change on a live non-sandbox workflow.
 */
export function TriggerEnabledControl({ trigger }: TriggerEnabledControlProps) {
  const { setTriggerEnabled } = useWorkflowActions();
  const suppressWarning = useSuppressEnableTriggerWarning();
  const markWarningSuppressed = useMarkEnableTriggerWarningSuppressed();

  const [showWarning, setShowWarning] = useState(false);
  const [dontShowAgain, setDontShowAgain] = useState(false);

  const enableTrigger = useCallback(() => {
    void setTriggerEnabled(trigger.id, true).catch(() => {
      notifications.alert({
        title: 'Could not enable trigger',
        description: 'Please try again.',
      });
    });
  }, [setTriggerEnabled, trigger.id]);

  const handleEnabledChange = useCallback(
    (checked: boolean) => {
      // Disabling is immediate and never warns.
      if (!checked) {
        void setTriggerEnabled(trigger.id, false).catch(() => {
          notifications.alert({
            title: 'Could not disable trigger',
            description: 'Please try again.',
          });
        });
        return;
      }

      // Enabling: skip the warning if the user has already suppressed it.
      if (suppressWarning) {
        enableTrigger();
        return;
      }

      setDontShowAgain(false);
      setShowWarning(true);
    },
    [enableTrigger, setTriggerEnabled, suppressWarning, trigger.id]
  );

  const handleConfirm = useCallback(() => {
    if (dontShowAgain) {
      void markWarningSuppressed();
    }
    enableTrigger();
  }, [dontShowAgain, enableTrigger, markWarningSuppressed]);

  return (
    <>
      <Tooltip content="Enable or disable this trigger" side="top">
        <span className="inline-block">
          <Toggle
            id={`trigger-enabled-${trigger.id}`}
            checked={trigger.enabled}
            onChange={handleEnabledChange}
            label="Enabled"
          />
        </span>
      </Tooltip>

      <AlertDialog
        isOpen={showWarning}
        onClose={() => setShowWarning(false)}
        onConfirm={handleConfirm}
        title="Enable this trigger"
        description="This workflow is still in development. Enabling its trigger means it will start receiving real events. If it is connected to live external systems this can have real consequences, so make sure it points at a development or test environment and is not connected to anything in production before you enable it."
        confirmLabel="Enable trigger"
        cancelLabel="Cancel"
        variant="danger"
      >
        <label className="flex items-center gap-2 text-sm text-gray-700">
          <input
            type="checkbox"
            checked={dontShowAgain}
            onChange={e => setDontShowAgain(e.target.checked)}
            className="h-4 w-4 rounded border-gray-300 text-primary-600 focus:ring-primary-500"
          />
          Don&apos;t show this warning again
        </label>
      </AlertDialog>
    </>
  );
}
