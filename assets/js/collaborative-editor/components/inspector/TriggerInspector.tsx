import { useWorkflowReadOnly } from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { NewRunButton } from '../NewRunButton';

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
  const { isReadOnly } = useWorkflowReadOnly();

  // Build footer with run button
  const footer = (
    <InspectorFooter
      rightButtons={
        <NewRunButton
          onClick={() => onOpenRunPanel({ triggerId: trigger.id })}
          tooltipSide="top"
          disabled={isReadOnly}
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
