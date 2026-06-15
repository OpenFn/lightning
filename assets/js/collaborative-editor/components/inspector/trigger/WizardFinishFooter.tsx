import { Button } from '../../Button';

interface WizardFinishFooterProps {
  /** Validation error to surface above the button after a failed Finish. */
  validationError: string | null;
  /** Validate + commit the draft (Finish). */
  onFinish: () => void;
}

/**
 * The Configure-step footer used by the cron and kafka wizards: a full-width
 * primary **Finish** button with the current `validationError` (if any) shown
 * above it. (The webhook Configure step has its own Cancel/Finish footer.)
 */
export function WizardFinishFooter({
  validationError,
  onFinish,
}: WizardFinishFooterProps) {
  return (
    <div className="space-y-2">
      {validationError && (
        <p className="text-xs text-red-600">{validationError}</p>
      )}
      <Button variant="primary" onClick={onFinish} className="w-full">
        <span className="inline-flex items-center gap-1.5">
          Finish
          <span className="hero-arrow-right-micro h-4 w-4" />
        </span>
      </Button>
    </div>
  );
}
