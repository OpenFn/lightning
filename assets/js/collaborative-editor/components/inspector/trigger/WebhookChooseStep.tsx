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
        <Button variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
      }
      rightButtons={
        <Button variant="primary" onClick={onNext}>
          Next
        </Button>
      }
    />
  );

  return (
    <InspectorLayout title="Select trigger" onClose={onClose} footer={footer}>
      <div className="space-y-6 p-6">
        <WizardBreadcrumb step="choose" />

        {/* Trigger type badge + Change */}
        <div className="flex items-center justify-between">
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
