import { useCallback } from 'react';

import { useLimits, usePermissions } from '../../hooks/useSessionContext';
import {
  useWorkflowActions,
  useWorkflowReadOnly,
} from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { NewRunButton } from '../NewRunButton';
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
  const { isReadOnly, tooltipMessage } = useWorkflowReadOnly();
  const limits = useLimits();

  const handleEnabledChange = useCallback(
    (enabled: boolean) => {
      updateTrigger(trigger.id, { enabled });
    },
    [trigger.id, updateTrigger]
  );

  // Check workflow activation limit
  const workflowActivationLimit = limits.workflow_activation ?? {
    allowed: true,
    message: null,
  };

  // Determine toggle disabled state and tooltip
  const isToggleDisabled =
    !permissions?.can_edit_workflow ||
    isReadOnly ||
    (!trigger.enabled && !workflowActivationLimit.allowed);

  const toggleTooltip =
    !trigger.enabled && !workflowActivationLimit.allowed
      ? workflowActivationLimit.message
      : isReadOnly || !permissions?.can_edit_workflow
        ? tooltipMessage || 'You do not have permission to edit this workflow'
        : 'Enable or disable this trigger';

  // Build footer with enabled toggle and run button
  const footer = (
    <InspectorFooter
      leftButtons={
        <Tooltip content={toggleTooltip} side="top">
          <span className="inline-block">
            <Toggle
              id={`trigger-enabled-${trigger.id}`}
              checked={trigger.enabled}
              onChange={handleEnabledChange}
              label="Enabled"
              disabled={isToggleDisabled}
            />
          </span>
        </Tooltip>
      }
      rightButtons={
        <NewRunButton
          onClick={() => onOpenRunPanel({ triggerId: trigger.id })}
          tooltipSide="top"
        />
      }
    />
  );

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
