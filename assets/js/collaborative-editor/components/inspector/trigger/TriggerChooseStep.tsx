import { InspectorLayout } from '../InspectorLayout';

import { TriggerTypeBadge } from './TriggerTypeBadge';
import { WebhookUrlField } from './WebhookUrlField';
import { WizardBreadcrumb } from './WizardBreadcrumb';
import { WizardFooter } from './WizardFooter';

type ChooseType = 'webhook' | 'cron' | 'kafka';

const TITLES: Record<ChooseType, string> = {
  webhook: 'On webhook call',
  cron: 'On a schedule',
  kafka: 'Kafka',
};

interface TriggerChooseStepProps {
  /** The trigger type whose badge (and, for webhook, URL field) is shown. */
  type: ChooseType;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Open the trigger-type picker (Change). */
  onChangeType: () => void;
  /** Advance to the Configure step (Next). */
  onNext: () => void;
  /**
   * Exit the wizard via the header back arrow. Used by cron/kafka, whose Figma
   * design has a header arrow rather than a footer Cancel. Mutually exclusive
   * with `onCancel` (webhook).
   */
  onBack?: () => void;
  /**
   * Exit the wizard via a footer **Cancel** button. Used by webhook, which has
   * no header back arrow. Mutually exclusive with `onBack` (cron/kafka).
   */
  onCancel?: () => void;
  /** Webhook only: the read-only ingest URL to display below the type chip. */
  webhookUrl?: string;
  /** Webhook only: copy-button label ('' | 'Copied!' | 'Failed'). */
  copyText?: string;
  /** Webhook only: copies the given text to the clipboard. */
  copyToClipboard?: (text: string) => Promise<void>;
}

/**
 * The wizard's "Choose" step for every trigger type (#4787). Shows the current
 * type badge with a **Change** action into the picker, then (webhook only) the
 * read-only ingest URL. Two exit shapes, by type: webhook uses a footer
 * **Cancel** (`onCancel`), cron/kafka use a header back arrow (`onBack`) — the
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
  webhookUrl,
  copyText,
  copyToClipboard,
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

        {/* Webhook URL (read-only) — only the webhook Choose step has it. */}
        {type === 'webhook' && webhookUrl !== undefined && (
          <WebhookUrlField
            url={webhookUrl}
            copyText={copyText ?? ''}
            onCopy={url => void copyToClipboard?.(url)}
          />
        )}
      </div>
    </InspectorLayout>
  );
}
