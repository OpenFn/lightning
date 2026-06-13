import { Button } from '../../Button';
import { InspectorLayout } from '../InspectorLayout';

import { TriggerTypeBadge } from './TriggerTypeBadge';
import { WizardBreadcrumb } from './WizardBreadcrumb';

interface CronChooseStepProps {
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Leave the wizard via the header back arrow (→ exit to show panel). */
  onBack: () => void;
  /** Open the trigger-type picker (Change). */
  onChangeType: () => void;
  /** Advance to the Configure step (Next). */
  onNext: () => void;
}

/**
 * The cron wizard's "Choose" step. Mirrors {@link WebhookChooseStep}: shows the
 * current trigger type (cron) with a **Change** action into the picker. Unlike
 * the webhook Choose step, the Figma design has a header back arrow (exits the
 * wizard) rather than a footer Cancel, and the footer holds a single full-width
 * primary **Next** button.
 */
export function CronChooseStep({
  onClose,
  onBack,
  onChangeType,
  onNext,
}: CronChooseStepProps) {
  const footer = (
    <Button variant="primary" onClick={onNext} className="w-full">
      <span className="inline-flex items-center gap-1.5">
        Next
        <span className="hero-arrow-right-micro h-4 w-4" />
      </span>
    </Button>
  );

  return (
    <InspectorLayout
      title="On a Schedule"
      onClose={onClose}
      showBackButton
      onBack={onBack}
      footer={footer}
    >
      <div className="space-y-6 p-6">
        <WizardBreadcrumb step="choose" />

        {/* Trigger type — chip on the left, "Change" button on the right
            (opens the picker to switch the trigger type). */}
        <div
          className="flex w-full items-center justify-between rounded-lg border
            border-gray-200 bg-white px-3 py-2"
        >
          <TriggerTypeBadge type="cron" />
          <button
            type="button"
            onClick={onChangeType}
            className="link text-sm font-semibold no-underline"
          >
            Change
          </button>
        </div>
      </div>
    </InspectorLayout>
  );
}
