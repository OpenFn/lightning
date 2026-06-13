import { useCallback, useState } from 'react';

import type { Workflow } from '../../../types/workflow';

import { CronChooseStep } from './CronChooseStep';
import { CronConfigureStep } from './CronConfigureStep';
import { TriggerTypeStep } from './TriggerTypeStep';
import { useTriggerDraft } from './useTriggerDraft';

interface CronEditWizardProps {
  trigger: Workflow.Trigger;
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
 * Container for the cron edit wizard (#4787). Mirrors {@link WebhookEditWizard}:
 * owns a local draft seeded from the current trigger, the step state machine,
 * and the Back/Finish handlers.
 *
 * Cron has no auth methods, so `useTriggerDraft` is given an empty initial
 * id set and a no-op `commitAuthMethods`. Nothing is persisted until Finish:
 * `finish()` validates and commits the draft in one shot.
 */
export function CronEditWizard({
  trigger,
  onClose,
  onDone,
}: CronEditWizardProps) {
  const { draft, mergeDraft, validationError, commit } = useTriggerDraft(
    trigger,
    {
      initialAuthMethodIds: [],
      commitAuthMethods: async () => {},
    }
  );

  const [step, setStep] = useState<Step>('choose');

  const finish = useCallback(async () => {
    const result = await commit();
    if (result.ok) {
      onDone();
    }
    // On failure, stay on Configure; `validationError` surfaces the reason.
  }, [commit, onDone]);

  if (step === 'picker') {
    return (
      <TriggerTypeStep
        trigger={trigger}
        draft={draft}
        mergeDraft={mergeDraft}
        onClose={onClose}
        onReturnToChoose={() => setStep('choose')}
        onLeaveWizard={onDone}
      />
    );
  }

  if (step === 'configure') {
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
  }

  return (
    <CronChooseStep
      onClose={onClose}
      onBack={onDone}
      onChangeType={() => setStep('picker')}
      onNext={() => setStep('configure')}
    />
  );
}
