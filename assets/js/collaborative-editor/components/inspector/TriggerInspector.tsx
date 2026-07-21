import { useWorkflowReadOnly } from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { NewRunButton } from '../NewRunButton';

import { InspectorFooter } from './InspectorFooter';
import { InspectorLayout } from './InspectorLayout';
import { TriggerEnabledControl } from './TriggerEnabledControl';
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

  // On a read-only workflow (live on main, pinned, deleted, no-permission) the
  // enable/disable toggle is an edit action and Run is a run-creation action,
  // and neither is allowed. A live workflow is lifecycle-controlled, so runs
  // happen from a sandbox, not here. With no controls left we pass an undefined
  // footer so InspectorLayout collapses the bar entirely instead of leaving an
  // empty bordered strip.
  const footer = isReadOnly ? undefined : (
    <InspectorFooter
      leftButtons={<TriggerEnabledControl trigger={trigger} />}
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
