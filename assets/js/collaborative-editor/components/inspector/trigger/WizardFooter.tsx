import { Button } from '../../Button';
import { InspectorFooter } from '../InspectorFooter';

interface WizardFooterProps {
  /** Primary button label: 'Next' on Choose, 'Finish' on Configure. */
  primaryLabel: 'Next' | 'Finish';
  /** Primary action (Next advances the step; Finish validates + commits). */
  onPrimary: () => void;
  /**
   * Cancel action. When provided, the footer renders a ghost **Cancel** on the
   * left and the primary button on the right (the webhook steps, which have no
   * header back arrow). When omitted, the primary button is full-width (the
   * cron/kafka steps, which exit via the header back arrow instead).
   */
  onCancel?: (() => void) | undefined;
  /** Validation error surfaced in red above the buttons (Configure steps). */
  validationError?: string | null | undefined;
}

/**
 * Shared footer for the trigger edit wizard's Choose and Configure steps.
 *
 * Replaces the three near-identical footers that used to live across the
 * per-step components: the only axes that vary are the primary label
 * (Next/Finish), whether a Cancel button is shown, and whether a validation
 * error is surfaced — all expressed as props here so the markup lives once.
 */
export function WizardFooter({
  primaryLabel,
  onPrimary,
  onCancel,
  validationError,
}: WizardFooterProps) {
  const primaryButton = (
    <Button
      variant="primary"
      onClick={onPrimary}
      className={onCancel ? '' : 'w-full'}
    >
      <span className="inline-flex items-center gap-1.5">
        {primaryLabel}
        <span className="hero-arrow-right-micro h-4 w-4" />
      </span>
    </Button>
  );

  return (
    <div className="space-y-2">
      {validationError && (
        <p className="text-xs text-red-600">{validationError}</p>
      )}
      {onCancel ? (
        <InspectorFooter
          leftButtons={
            <Button variant="ghost" onClick={onCancel}>
              Cancel
            </Button>
          }
          rightButtons={primaryButton}
        />
      ) : (
        primaryButton
      )}
    </div>
  );
}
