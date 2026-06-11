import { Button } from '../../Button';
import { InspectorFooter } from '../InspectorFooter';
import { InspectorLayout } from '../InspectorLayout';

import { TriggerTypeBadge } from './TriggerTypeBadge';
import { WebhookUrlField } from './WebhookUrlField';
import { WizardBreadcrumb } from './WizardBreadcrumb';

interface WebhookChooseStepProps {
  /** The webhook ingest URL to display read-only. */
  webhookUrl: string;
  /** Copy-button label ('' | 'Copied!' | 'Failed'). */
  copyText: string;
  /** Copies the given text to the clipboard. */
  copyToClipboard: (text: string) => Promise<void>;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Discard the draft and leave the wizard (Cancel). */
  onCancel: () => void;
  /** Open the trigger-type picker (Change). */
  onChangeType: () => void;
  /** Advance to the Configure step (Next). */
  onNext: () => void;
}

/**
 * The wizard's "Choose" step. Shows the current trigger type (webhook) with a
 * **Change** action into the picker and the read-only webhook URL. There is no
 * header back arrow here — Cancel is the exit affordance.
 */
export function WebhookChooseStep({
  webhookUrl,
  copyText,
  copyToClipboard,
  onClose,
  onCancel,
  onChangeType,
  onNext,
}: WebhookChooseStepProps) {
  const footer = (
    <InspectorFooter
      leftButtons={
        <Button variant="ghost" onClick={onCancel}>
          Cancel
        </Button>
      }
      rightButtons={
        <Button variant="primary" onClick={onNext}>
          <span className="inline-flex items-center gap-1.5">
            Next
            <span className="hero-arrow-right-micro h-4 w-4" />
          </span>
        </Button>
      }
    />
  );

  return (
    <InspectorLayout title="On webhook call" onClose={onClose} footer={footer}>
      <div className="space-y-6 p-6">
        <WizardBreadcrumb step="choose" />

        {/* Trigger type — chip on the left, "Change" button on the right
            (opens the picker to switch the trigger type). */}
        <div
          className="flex w-full items-center justify-between rounded-lg border
            border-gray-200 bg-white px-3 py-2"
        >
          <TriggerTypeBadge />
          <button
            type="button"
            onClick={onChangeType}
            className="link text-sm font-semibold no-underline"
          >
            Change
          </button>
        </div>

        {/* Webhook URL (read-only) */}
        <WebhookUrlField
          url={webhookUrl}
          copyText={copyText}
          onCopy={url => void copyToClipboard(url)}
        />
      </div>
    </InspectorLayout>
  );
}
