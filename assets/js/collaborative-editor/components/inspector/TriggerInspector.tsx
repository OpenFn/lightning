import { useCallback, useEffect, useState } from 'react';

import { Tooltip } from '../../../components/Tooltip';
import { usePermissions } from '../../hooks/useSessionContext';
import {
  useWorkflowActions,
  useWorkflowReadOnly,
} from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { NewRunButton } from '../NewRunButton';
import { Toggle } from '../Toggle';

import { InspectorFooter } from './InspectorFooter';
import { InspectorLayout } from './InspectorLayout';
import { WebhookEditWizard } from './trigger/WebhookEditWizard';
import { WebhookShowPanel, type EditFocus } from './trigger/WebhookShowPanel';
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

  // View-state machine. The read-only "show" panel is the resting state for a
  // webhook trigger; "edit" hands off to the WebhookEditWizard (Choose →
  // Configure over a local draft). Cron/Kafka ignore this and render the legacy
  // TriggerForm.
  const [view, setView] = useState<'show' | 'edit'>('show');
  // When the user enters edit via an inline deep link ("Add authentication" /
  // "Configure default response status"), jump straight to Configure with that
  // section expanded. `undefined` = the plain Edit button → Choose step.
  const [editFocus, setEditFocus] = useState<EditFocus | undefined>(undefined);

  // Reset to the resting state whenever a different trigger is selected.
  useEffect(() => {
    setView('show');
    setEditFocus(undefined);
  }, [trigger.id]);

  const handleEnabledChange = useCallback(
    (enabled: boolean) => {
      updateTrigger(trigger.id, { enabled });
    },
    [trigger.id, updateTrigger]
  );

  // Determine toggle disabled state and tooltip
  const isToggleDisabled = !permissions?.can_edit_workflow || isReadOnly;

  const toggleTooltip =
    isReadOnly || !permissions?.can_edit_workflow
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
          disabled={isReadOnly}
        />
      }
    />
  );

  // Webhook resting state: read-only show panel, no footer (per design the
  // Toggle and NewRunButton are dropped here — running lives on the header and
  // enable/disable on the canvas).
  if (trigger.type === 'webhook' && view === 'show') {
    return (
      <WebhookShowPanel
        trigger={trigger}
        onClose={onClose}
        onEdit={focus => {
          setEditFocus(focus);
          setView('edit');
        }}
      />
    );
  }

  // Webhook edit: the wizard owns the entire Choose → Configure flow over a
  // local draft (mounted fresh per edit so the draft seeds from the current
  // trigger). Finish/Cancel return to the show panel.
  if (trigger.type === 'webhook' && view === 'edit') {
    return (
      <WebhookEditWizard
        trigger={trigger}
        initialFocus={editFocus}
        onClose={onClose}
        onDone={() => {
          setView('show');
          setEditFocus(undefined);
        }}
      />
    );
  }

  // Cron/Kafka: unchanged legacy form with the enabled toggle + run footer.
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
