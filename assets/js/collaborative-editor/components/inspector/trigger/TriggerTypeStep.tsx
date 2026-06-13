import { createDefaultTrigger } from '#/collaborative-editor/types/trigger';

import { useWorkflowActions } from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';

import { TriggerPicker } from './TriggerPicker';

interface TriggerTypeStepProps {
  /** The source trigger (used for the immediate type-switch commit). */
  trigger: Workflow.Trigger;
  /** The local draft (read to avoid resetting config on a no-op re-pick). */
  draft: Workflow.Trigger;
  /** Shallow-merge updates into the draft. */
  mergeDraft: (updates: Partial<Workflow.Trigger>) => void;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Return to the Choose step (back arrow + after applying a draft type). */
  onReturnToChoose: () => void;
  /** Leave the wizard entirely (after switching to a different-wizard type). */
  onLeaveWizard: () => void;
}

/**
 * The shared "Select trigger" picker step for the edit wizards. Both the webhook
 * and cron wizards reach the picker via their Choose step's "Change" action, and
 * the wiring is identical, so it lives here in one place rather than being
 * duplicated per wizard.
 *
 * - `onPickDraftType` applies the picked type's defaults to the LOCAL draft (only
 *   on an actual type change — re-confirming the current type must not reset
 *   config) and returns to Choose.
 * - `onCommitType` switches to a type whose editor lives elsewhere: it commits
 *   the switch immediately via `updateTrigger` and leaves the wizard, letting the
 *   inspector route to the right editor.
 */
export function TriggerTypeStep({
  trigger,
  draft,
  mergeDraft,
  onClose,
  onReturnToChoose,
  onLeaveWizard,
}: TriggerTypeStepProps) {
  const { updateTrigger } = useWorkflowActions();

  return (
    <TriggerPicker
      onClose={onClose}
      onBack={onReturnToChoose}
      onPickDraftType={type => {
        if (draft.type !== type) {
          mergeDraft(createDefaultTrigger(type) as Partial<Workflow.Trigger>);
        }
        onReturnToChoose();
      }}
      onCommitType={type => {
        updateTrigger(trigger.id, createDefaultTrigger(type));
        onLeaveWizard();
      }}
    />
  );
}
