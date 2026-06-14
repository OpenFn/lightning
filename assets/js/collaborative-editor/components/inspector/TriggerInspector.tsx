import { useEffect, useState } from 'react';

import type { Workflow } from '../../types/workflow';

import { CronShowPanel } from './trigger/CronShowPanel';
import { KafkaShowPanel } from './trigger/KafkaShowPanel';
import { TriggerEditWizard } from './trigger/TriggerEditWizard';
import { WebhookShowPanel, type EditFocus } from './trigger/WebhookShowPanel';

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onOpenRunPanel: (context: { jobId?: string; triggerId?: string }) => void;
}

/**
 * TriggerInspector - Composition layer for trigger configuration.
 *
 * Dispatches by trigger type to a read-only "show / resting" panel, and hands
 * off to the unified {@link TriggerEditWizard} for editing (and for the future
 * typeless case, which has no show panel — the wizard starts at its picker).
 */
export function TriggerInspector({
  trigger,
  onClose,
  onOpenRunPanel: _onOpenRunPanel,
}: TriggerInspectorProps) {
  // View-state machine. The read-only "show" panel is the resting state for a
  // typed trigger; "edit" hands off to the unified wizard (Choose → Configure
  // over a local draft).
  const [view, setView] = useState<'show' | 'edit'>('show');
  // When the user enters edit via an inline deep link ("Add authentication" /
  // "Configure default response status"), jump straight to Configure with that
  // section expanded. `undefined` = the plain Edit button → Choose step. Only
  // the webhook show panel produces a non-undefined focus.
  const [editFocus, setEditFocus] = useState<EditFocus | undefined>(undefined);

  // Reset to the resting state whenever a different trigger is selected.
  useEffect(() => {
    setView('show');
    setEditFocus(undefined);
  }, [trigger.id]);

  // A typeless trigger has no show panel; route it straight to the wizard,
  // which starts at its picker so the user can choose a type.
  if (view === 'edit' || !trigger.type) {
    return (
      <TriggerEditWizard
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

  // Resting state: read-only show panel per type. Per design these panels drop
  // the Enabled toggle + Run button (running lives on the header, enable/disable
  // on the canvas).
  switch (trigger.type) {
    case 'webhook':
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
    case 'cron':
      return (
        <CronShowPanel
          trigger={trigger}
          onClose={onClose}
          onEdit={() => setView('edit')}
        />
      );
    case 'kafka':
      return (
        <KafkaShowPanel
          trigger={trigger}
          onClose={onClose}
          onEdit={() => setView('edit')}
        />
      );
    default:
      return null;
  }
}
