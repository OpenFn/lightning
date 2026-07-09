import { useCallback, useState } from 'react';

import type { Workflow } from '../../../types/workflow';

import { CronConfigureStep } from './CronConfigureStep';
import { KafkaConfigureStep } from './KafkaConfigureStep';
import { TriggerChooseStep } from './TriggerChooseStep';
import { TriggerPicker } from './TriggerPicker';
import { useTriggerDraft } from './useTriggerDraft';
import { useWebhookTrigger } from './useWebhookTrigger';
import { WebhookConfigureStep } from './WebhookConfigureStep';

interface TriggerEditWizardProps {
  trigger: Workflow.Trigger;
  /**
   * Deep-link target (webhook only): when set, open directly on Configure with
   * this section expanded (from the show panel's inline links). Undefined →
   * start at Choose.
   */
  initialFocus?: 'authentication' | 'response' | undefined;
  /** Close the inspector entirely. */
  onClose: () => void;
  /**
   * Leave the wizard and return to the show panel (Cancel / Finish /
   * back-arrow from Choose). The draft is discarded unless `commit()` ran.
   */
  onDone: () => void;
}

type Step = 'choose' | 'picker' | 'configure';

/**
 * Type-agnostic trigger edit wizard: a single shell that dispatches its Choose
 * and Configure steps by `draft.type`, covering webhook, cron, and kafka.
 *
 * Owns the edit session: a local draft seeded from the current trigger
 * (`useTriggerDraft`), the step state machine, and the Cancel/Back/Finish
 * handlers. This component is mounted fresh per edit (keyed by trigger id at the
 * call site), so the draft always seeds from the current committed trigger.
 *
 * Webhook auth wiring: `useWebhookTrigger` is called unconditionally (hook
 * rules) but only fires its auth-methods request for webhook triggers (guarded
 * inside the hook). For non-webhook triggers we feed `useTriggerDraft` an empty
 * initial id set and a no-op commit, so the draft never touches auth methods.
 *
 * Nothing is persisted until Finish: leaving the wizard discards the local
 * draft, while `finish()` validates and commits it in one shot.
 */
export function TriggerEditWizard({
  trigger,
  initialFocus,
  onClose,
  onDone,
}: TriggerEditWizardProps) {
  const isWebhook = trigger.type === 'webhook';

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
  } = useTriggerDraft(
    trigger,
    isWebhook
      ? {
          initialAuthMethodIds: triggerAuthMethods.map(m => m.id),
          commitAuthMethods,
        }
      : {
          initialAuthMethodIds: [],
          commitAuthMethods: async () => {},
        }
  );

  // Initial step: rest on Choose, or jump straight to Configure on a
  // deep-link. Once mounted, all navigation (back/pick-type/close) uses the
  // wizard's normal step transitions regardless of how this initial step was
  // chosen.
  const [step, setStep] = useState<Step>(initialFocus ? 'configure' : 'choose');

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
        draft={draft}
        mergeDraft={mergeDraft}
        onClose={onClose}
        onReturnToChoose={() => setStep('choose')}
      />
    );
  }

  if (step === 'configure') {
    switch (draft.type) {
      case 'webhook':
        return (
          <WebhookConfigureStep
            draft={draft}
            mergeDraft={mergeDraft}
            draftAuthMethodIds={draftAuthMethodIds}
            setDraftAuthMethodIds={setDraftAuthMethodIds}
            validationError={validationError}
            initialExpand={initialFocus}
            onClose={onClose}
            onCancel={onDone}
            onBack={() => setStep('choose')}
            onFinish={() => void finish()}
          />
        );
      case 'cron':
        return (
          <CronConfigureStep
            draft={draft}
            mergeDraft={mergeDraft}
            validationError={validationError}
            onClose={onClose}
            onBack={() => setStep('choose')}
            onFinish={() => void finish()}
          />
        );
      case 'kafka':
        return (
          <KafkaConfigureStep
            draft={draft}
            mergeDraft={mergeDraft}
            validationError={validationError}
            onClose={onClose}
            onBack={() => setStep('choose')}
            onFinish={() => void finish()}
          />
        );
      default:
        return null;
    }
  }

  // step === 'choose'
  switch (draft.type) {
    case 'webhook':
      return (
        <TriggerChooseStep
          type="webhook"
          webhookUrl={webhookUrl}
          copyText={copyText}
          copyToClipboard={copyToClipboard}
          onClose={onClose}
          onCancel={onDone}
          onChangeType={() => setStep('picker')}
          onNext={() => setStep('configure')}
        />
      );
    case 'cron':
      return (
        <TriggerChooseStep
          type="cron"
          onClose={onClose}
          onBack={onDone}
          onChangeType={() => setStep('picker')}
          onNext={() => setStep('configure')}
        />
      );
    case 'kafka':
      return (
        <TriggerChooseStep
          type="kafka"
          onClose={onClose}
          onBack={onDone}
          onChangeType={() => setStep('picker')}
          onNext={() => setStep('configure')}
        />
      );
    default:
      return null;
  }
}
