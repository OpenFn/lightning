import { cn } from '#/utils/cn';

export type WizardStep = 'choose' | 'configure';

interface WizardBreadcrumbProps {
  /** The currently active wizard step. */
  step: WizardStep;
}

/**
 * Renders the `Choose › Configure` breadcrumb for the webhook edit wizard. The
 * active step is emphasised (bold) while the inactive step is muted. The Figma
 * "Test" step is out of scope for Phase 1 and intentionally omitted.
 */
export function WizardBreadcrumb({ step }: WizardBreadcrumbProps) {
  return (
    <nav
      aria-label="Wizard steps"
      className="flex items-center gap-1.5 text-xs"
    >
      <span
        className={cn(
          step === 'choose'
            ? 'font-semibold text-slate-900 underline'
            : 'text-slate-400'
        )}
      >
        Choose
      </span>
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
