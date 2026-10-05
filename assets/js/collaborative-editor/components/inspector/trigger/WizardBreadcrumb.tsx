import { cn } from '#/utils/cn';

export type WizardStep = 'choose' | 'configure';

interface WizardBreadcrumbProps {
  /** The currently active wizard step. */
  step: WizardStep;
  /**
   * Navigate to a step by clicking its crumb. Only backward navigation is
   * offered (clicking "Choose" while on "Configure"); the wizard has no header
   * back arrow, so this breadcrumb is the way back. Omit for a static display.
   */
  onNavigate?: (step: WizardStep) => void;
}

/**
 * Renders the `Choose › Configure` breadcrumb for the webhook edit wizard. The
 * active step is emphasised (bold) while the inactive step is muted. When
 * `onNavigate` is provided, the already-visited "Choose" crumb becomes a button
 * that returns to that step.
 */
export function WizardBreadcrumb({ step, onNavigate }: WizardBreadcrumbProps) {
  // "Choose" is navigable only when we're past it (on Configure).
  const canGoToChoose = step === 'configure' && Boolean(onNavigate);

  return (
    <nav
      aria-label="Wizard steps"
      className="flex items-center gap-1.5 text-xs"
    >
      {canGoToChoose ? (
        <button
          type="button"
          onClick={() => onNavigate?.('choose')}
          className="text-slate-400 hover:text-slate-600 focus:outline-none"
        >
          Choose
        </button>
      ) : (
        <span
          className={cn(
            step === 'choose'
              ? 'font-semibold text-slate-900 underline'
              : 'text-slate-400'
          )}
        >
          Choose
        </span>
      )}
      <span aria-hidden="true" className="text-slate-300">
        ›
      </span>
      <span
        className={cn(
          step === 'configure'
            ? 'font-semibold text-slate-900 underline'
            : 'text-slate-400'
        )}
      >
        Configure
      </span>
    </nav>
  );
}
