import { useCallback, useState } from 'react';

import { createDefaultTrigger } from '#/collaborative-editor/types/trigger';

import { useWorkflowActions } from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';

import { TriggerPicker } from './TriggerPicker';
import { useTriggerDraft } from './useTriggerDraft';
import { useWebhookTrigger } from './useWebhookTrigger';
import { WebhookChooseStep } from './WebhookChooseStep';
import { WebhookConfigureStep } from './WebhookConfigureStep';

interface WebhookEditWizardProps {
  trigger: Workflow.Trigger;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Leave the wizard and return to the show panel (Cancel or Finish). */
  onDone: () => void;
}

type Step = 'choose' | 'picker' | 'configure';

/**
 * Container for the webhook edit wizard (#4798). Owns the edit session: a local
 * draft seeded from the current trigger, the step state machine, and the
 * Cancel/Back/Finish handlers.
 *
 * This component is mounted fresh per edit (keyed by trigger id at the call
 * site), so the draft always seeds from the current committed trigger.
 *
 * Nothing is persisted until Finish: `cancel()` simply unmounts (the draft is
 * local), while `finish()` validates and commits the draft in one shot.
 */
export function WebhookEditWizard({
  trigger,
  onClose,
  onDone,
}: WebhookEditWizardProps) {
  const { updateTrigger } = useWorkflowActions();
  const {
    webhookUrl,
    copyText,
    copyToClipboard,
    triggerAuthMethods,
    commitAuthMethods,
  } = useWebhookTrigger(trigger);

  const {
    draft,
    mergeDraft,
    draftAuthMethodIds,
    setDraftAuthMethodIds,
    validationError,
    commit,
  } = useTriggerDraft(trigger, {
    initialAuthMethodIds: triggerAuthMethods.map(m => m.id),
    commitAuthMethods,
  });

  const [step, setStep] = useState<Step>('choose');

  // Cancel: the draft is purely local, so discarding it just means leaving the
  // wizard. No persistence happens.
  const cancel = useCallback(() => {
    onDone();
  }, [onDone]);

  const finish = useCallback(async () => {
    const result = await commit();
    if (result.ok) {
      onDone();
    }
    // On failure, stay on Configure; `validationError` surfaces the reason.
  }, [commit, onDone]);

  if (step === 'picker') {
    return (
      <TriggerPicker
        onClose={onClose}
        onBack={() => setStep('choose')}
        onPickDraftType={type => {
          // Re-confirming the type the draft already has must NOT reset its
          // config to defaults — only an actual type change applies defaults.
          if (draft.type !== type) {
            mergeDraft(createDefaultTrigger(type) as Partial<Workflow.Trigger>);
          }
          setStep('choose');
        }}
        onCommitType={type => {
          // Cron/Kafka have no wizard yet in this webhook-first phase, so we
          // commit the type switch immediately and hand back to the show panel,
          // which renders the legacy TriggerForm for that type.
          updateTrigger(trigger.id, createDefaultTrigger(type));
          onDone();
        }}
      />
    );
  }

  if (step === 'configure') {
    return (
      <WebhookConfigureStep
        draft={draft}
        mergeDraft={mergeDraft}
        draftAuthMethodIds={draftAuthMethodIds}
        setDraftAuthMethodIds={setDraftAuthMethodIds}
        validationError={validationError}
        onClose={onClose}
        onCancel={cancel}
        onBack={() => setStep('choose')}
        onFinish={() => void finish()}
      />
    );
  }

  return (
    <WebhookChooseStep
      webhookUrl={webhookUrl}
      copyText={copyText}
      copyToClipboard={copyToClipboard}
      onClose={onClose}
      onCancel={cancel}
      onChangeType={() => setStep('picker')}
      onNext={() => setStep('configure')}
    />
  );
}
