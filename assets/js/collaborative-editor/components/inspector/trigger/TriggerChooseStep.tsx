import { InspectorLayout } from '../InspectorLayout';

import { TriggerTypeBadge } from './TriggerTypeBadge';
import { WizardBreadcrumb } from './WizardBreadcrumb';
import { WizardFooter } from './WizardFooter';

type ChooseType = 'webhook' | 'cron';

const TITLES: Record<ChooseType, string> = {
  webhook: 'On webhook call',
  cron: 'On a schedule',
};

interface TriggerChooseStepProps {
  /** The trigger type whose badge is shown. */
  type: ChooseType;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Open the trigger-type picker (Change). */
  onChangeType: () => void;
  /** Advance to the Configure step (Next). */
  onNext: () => void;
  /**
   * Exit the wizard via the header back arrow. Used by cron, whose
   * design has a header arrow rather than a footer Cancel. Mutually exclusive
   * with `onCancel` (webhook).
   */
  onBack?: () => void;
  /**
   * Exit the wizard via a footer **Cancel** button. Used by webhook, which has
   * no header back arrow. Mutually exclusive with `onBack` (cron).
   */
  onCancel?: () => void;
}

/**
 * The wizard's "Choose" step for every trigger type. Shows the current
 * type badge with a **Change** action into the picker. The URLs are not here.
 * You are choosing a type, and they belong with the field that names them. Two
 * exit shapes, by type: webhook uses a footer **Cancel** (`onCancel`), cron
 * uses a header back arrow (`onBack`) — the
 * difference is carried by which handler the wizard passes, not by separate
 * components.
 */
export function TriggerChooseStep({
  type,
  onClose,
  onChangeType,
  onNext,
  onBack,
  onCancel,
}: TriggerChooseStepProps) {
  const footer = (
    <WizardFooter primaryLabel="Next" onPrimary={onNext} onCancel={onCancel} />
  );

  return (
    <InspectorLayout
      title={TITLES[type]}
      onClose={onClose}
      showBackButton={Boolean(onBack)}
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
          <TriggerTypeBadge type={type} />
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
