import { useEffect, useState } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import type { Workflow } from '../../types/workflow';

import {
  CronShowPanel,
  type EditFocus,
  KafkaShowPanel,
  TriggerEditWizard,
  WebhookShowPanel,
} from './trigger';

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onOpenRunPanel: (context: { jobId?: string; triggerId?: string }) => void;
}

/**
 * TriggerInspector - Composition layer for trigger configuration.
 *
 * Dispatches by trigger type to a read-only "show / resting" panel, and hands
 * off to the unified {@link TriggerEditWizard} for editing.
 */
export function TriggerInspector({
  trigger,
  onClose,
  onOpenRunPanel: _onOpenRunPanel,
}: TriggerInspectorProps) {
  const { params, updateSearchParams } = useURLState();

  // `?trigger_view=picker` is a one-shot launch signal (set by the
  // build-from-scratch redirect), not durable UI state: it only decides what
  // this component mounts into on its very first render. Read with a lazy
  // initializer so it's captured once, then cleared below (both from the URL
  // and from this flag) — otherwise every later "Edit" click within the same
  // TriggerInspector instance would keep re-opening the picker instead of the
  // normal Choose step.
  const [startedOnPicker, setStartedOnPicker] = useState(
    () => params['trigger_view'] === 'picker'
  );

  // View-state machine. The read-only "show" panel is the resting state for a
  // typed trigger; "edit" hands off to the unified wizard (Choose → Configure
  // over a local draft). A fresh instance is mounted per trigger id (keyed by
  // the caller), so this only ever needs to compute its starting state once.
  const [view, setView] = useState<'show' | 'edit'>(() =>
    startedOnPicker ? 'edit' : 'show'
  );
  // When the user enters edit via an inline deep link ("Add authentication" /
  // "Configure default response status"), jump straight to Configure with that
  // section expanded. `undefined` = the plain Edit button → Choose step. Only
  // the webhook show panel produces a non-undefined focus.
  const [editFocus, setEditFocus] = useState<EditFocus | undefined>(undefined);

  useEffect(() => {
    if (!startedOnPicker) return;
    updateSearchParams({ trigger_view: null });
    // TriggerEditWizard already captured startOnPicker in its own initial
    // state by the time this effect runs, so clearing the flag here doesn't
    // affect the picker that's already open — it only prevents a *future*
    // Edit click (via the show panel) from reopening the picker again.
    setStartedOnPicker(false);
    // Run once on mount only: this is consuming the one-shot signal captured
    // above, not reacting to subsequent param changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The "edit" view is reachable only via a show panel's Edit button, which is
  // already disabled when the user can't edit the workflow, so no extra
  // permission gate is needed here.
  if (view === 'edit') {
    return (
      <TriggerEditWizard
        trigger={trigger}
        initialFocus={editFocus}
        startOnPicker={startedOnPicker}
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
