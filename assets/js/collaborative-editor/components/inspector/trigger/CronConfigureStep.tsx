import { cn } from '#/utils/cn';

import {
  useWorkflowReadOnly,
  useWorkflowState,
} from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';
import { InspectorLayout } from '../InspectorLayout';

import { CronFieldBuilder } from './CronFieldBuilder';
import { WizardBreadcrumb } from './WizardBreadcrumb';
import { WizardFooter } from './WizardFooter';

interface CronConfigureStepProps {
  /** The local trigger draft. */
  draft: Workflow.Trigger;
  /** Shallow-merge updates into the draft. */
  mergeDraft: (updates: Partial<Workflow.Trigger>) => void;
  /** Validation error to surface near the footer after a failed Finish. */
  validationError: string | null;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Return to the Choose step (header arrow + breadcrumb "Choose" crumb). */
  onBack: () => void;
  /** Validate + commit the draft (Finish). */
  onFinish: () => void;
}

/**
 * The cron wizard's "Configure" step. Binds entirely to the local
 * DRAFT: the {@link CronFieldBuilder} frequency dropdown writes the compiled
 * 5-field cron string into `draft.cron_expression` via `mergeDraft`; nothing is
 * persisted until Finish.
 *
 * Below the schedule is the legacy "Cron Input
 * Source" select bound to `draft.cron_cursor_job_id`.
 */
export function CronConfigureStep({
  draft,
  mergeDraft,
  validationError,
  onClose,
  onBack,
  onFinish,
}: CronConfigureStepProps) {
  const jobs = useWorkflowState(state => state.jobs);
  const { isReadOnly } = useWorkflowReadOnly();

  const footer = (
    <WizardFooter
      primaryLabel="Finish"
      onPrimary={onFinish}
      validationError={validationError}
    />
  );

  return (
    <InspectorLayout
      title="On a schedule"
      onClose={onClose}
      showBackButton
      onBack={onBack}
      footer={footer}
    >
      <div className="space-y-6 p-6">
        <WizardBreadcrumb
          step="configure"
          onNavigate={target => {
            if (target === 'choose') onBack();
          }}
        />

        <div className="space-y-2">
          <h3 className="text-base font-semibold text-slate-900">
            When should this run?
          </h3>
          <CronFieldBuilder
            value={draft.cron_expression ?? ''}
            onChange={expr => mergeDraft({ cron_expression: expr })}
            disabled={isReadOnly}
          />
        </div>

        <div className="space-y-1">
          <label
            htmlFor="cron-cursor-job"
            className="block text-sm font-medium text-slate-800"
          >
            Cron Input Source
          </label>
          <select
            id="cron-cursor-job"
            value={draft.cron_cursor_job_id ?? ''}
            onChange={e =>
              mergeDraft({
                cron_cursor_job_id:
                  e.target.value === '' ? null : e.target.value,
              })
            }
            disabled={isReadOnly}
            className={cn(
              'block w-full rounded-lg border border-gray-200 bg-white',
              'px-3 py-2 text-sm text-slate-700',
              'focus:border-indigo-500 focus:outline-none focus:ring-1',
              'focus:ring-indigo-500',
              'disabled:cursor-not-allowed disabled:opacity-50'
            )}
          >
            <option value="">Final run state (default)</option>
            {jobs.map(job => (
              <option key={job.id} value={job.id}>
                {job.name}
              </option>
            ))}
          </select>
          <p className="text-xs text-slate-500">
            Choose which step&apos;s output to use as input for cron-triggered
            runs.
          </p>
        </div>
      </div>
    </InspectorLayout>
  );
}
