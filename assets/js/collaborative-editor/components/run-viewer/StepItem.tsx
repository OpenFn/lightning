import { useURLState } from '../../../react/lib/use-url-state';
import { cn } from '../../../utils/cn';
import { useWorkflowState } from '../../hooks/useWorkflow';
import type { StepDetail } from '../../types/history';
import { Tooltip } from '../Tooltip';

import { ElapsedIndicator } from './ElapsedIndicator';
import { StepIcon } from './StepIcon';

interface StepItemProps {
  step: StepDetail;
  selected: boolean;
  runInsertedAt: string;
}

export function StepItem({ step, selected, runInsertedAt }: StepItemProps) {
  const { searchParams, updateSearchParams } = useURLState();

  // Look up job name from workflow state if not included in step
  const jobName = useWorkflowState(
    state => {
      if (step.job?.name) {
        return step.job.name;
      }
      const job = state.jobs.find(j => j.id === step.job_id);
      return job?.name || 'Unknown Job';
    },
    [step.job_id, step.job?.name]
  );

  const handleInspect = (e: React.MouseEvent) => {
    e.stopPropagation();

    // Get current run ID and panel from URL to preserve context
    const currentRunId = searchParams.get('run');
    const currentPanel = searchParams.get('panel');

    // Build updates object, only including panel if it exists
    const updates: Record<string, string | null> = {
      job: step.job_id,
      run: currentRunId, // Preserve run context
      step: step.id, // Update to this step
    };

    // Only include panel in updates if it exists (avoids deleting it)
    if (currentPanel) {
      updates.panel = currentPanel;
    }

    updateSearchParams(updates);
  };

  // Determine if this step is from a previous run (cloned)
  const isClone = new Date(step.inserted_at) < new Date(runInsertedAt);

  return (
    <button
      type="button"
      onClick={handleInspect}
      className={cn(
        'relative flex items-center space-x-3 p-2 rounded w-full text-left',
        'cursor-pointer border-r-4 transition-colors',
        selected
          ? 'border-primary-500 bg-primary-50 font-semibold'
          : 'border-transparent hover:border-gray-300 hover:bg-gray-50'
      )}
    >
      <StepIcon exitReason={step.exit_reason} errorType={step.error_type} />

      <div
        className={cn(
          'flex-1 min-w-0 flex items-center space-x-2',
          isClone && 'opacity-50'
        )}
      >
        {isClone && (
          <Tooltip
            content="This step was originally executed in a previous run. It was skipped in this run; the original output has been used as the starting point for downstream jobs."
            side="bottom"
          >
            <span
              className="hero-paper-clip h-3 w-3 flex-shrink-0 text-gray-500"
              aria-label="Cloned from previous run"
              role="img"
            />
          </Tooltip>
        )}
        <span className="text-sm truncate">{jobName}</span>
      </div>

      <div className="flex-shrink-0 text-xs text-gray-500">
        <ElapsedIndicator
          startedAt={step.started_at}
          finishedAt={step.finished_at}
        />
      </div>
    </button>
  );
}
