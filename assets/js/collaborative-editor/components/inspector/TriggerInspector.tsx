import { useCallback } from 'react';

import { usePermissions } from '../../hooks/useSessionContext';
import {
  useCanRun,
  useWorkflowActions,
  useWorkflowReadOnly,
} from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { Button } from '../Button';
import { Toggle } from '../Toggle';
import { Tooltip } from '../Tooltip';

import { InspectorFooter } from './InspectorFooter';
import { InspectorLayout } from './InspectorLayout';
import { TriggerForm } from './TriggerForm';

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onOpenRunPanel: (context: { jobId?: string; triggerId?: string }) => void;
}

/**
 * Renders trigger title based on type, matching old WorkflowEdit behavior
 */
function getTriggerTitle(trigger: Workflow.Trigger): string {
  if (!trigger.type) {
    return 'New Trigger';
  }

  switch (trigger.type) {
    case 'webhook':
      return 'Webhook Trigger';
    case 'cron':
      return 'Cron Trigger';
    case 'kafka':
      return 'Kafka Trigger';
    default:
      return 'Unknown Trigger';
  }
}

/**
 * TriggerInspector - Composition layer for trigger configuration.
 * Currently just wraps form with layout (no actions yet).
 */
export function TriggerInspector({
  trigger,
  onClose,
  onOpenRunPanel,
}: TriggerInspectorProps) {
  const permissions = usePermissions();
  const { updateTrigger } = useWorkflowActions();
  const { isReadOnly } = useWorkflowReadOnly();

  // Use centralized canRun hook for all run permission/state checks
  const { canRun, tooltipMessage: runTooltipMessage } = useCanRun();

  const handleEnabledChange = useCallback(
    (enabled: boolean) => {
      updateTrigger(trigger.id, { enabled });
    },
    [trigger.id, updateTrigger]
  );

  // Build footer with enabled toggle and run button (only if user has permission and not readonly)
  const footer =
    permissions?.can_edit_workflow && !isReadOnly ? (
      <InspectorFooter
        leftButtons={
          <Toggle
            id={`trigger-enabled-${trigger.id}`}
            checked={trigger.enabled}
            onChange={handleEnabledChange}
            label="Enabled"
          />
        }
        rightButtons={
          <Tooltip content={runTooltipMessage} side="top">
            <span className="inline-block">
              <Button
                variant="primary"
                onClick={() => onOpenRunPanel({ triggerId: trigger.id })}
                disabled={!canRun}
              >
                <span className="hero-play-solid h-4 w-4" />
                Run
              </Button>
            </span>
          </Tooltip>
        }
      />
    ) : undefined;

  return (
    <InspectorLayout
      title={getTriggerTitle(trigger)}
      onClose={onClose}
      footer={footer}
    >
      <TriggerForm trigger={trigger} />
    </InspectorLayout>
  );
}
