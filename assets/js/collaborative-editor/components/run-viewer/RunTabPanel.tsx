import {
  useActiveRun,
  useHistoryCommands,
  useSelectedStepId,
} from '../../hooks/useHistory';
import { useProject } from '../../hooks/useSessionContext';

import { ElapsedIndicator } from './ElapsedIndicator';
import { StatePill } from './StatePill';
import { StepList } from './StepList';

/**
 * Displays a short version of a UUID (first 8 characters)
 */
function displayShortUuid(uuid: string): string {
  return uuid.slice(0, 8);
}

export function RunTabPanel() {
  const run = useActiveRun();
  const selectedStepId = useSelectedStepId();
  const { selectStep } = useHistoryCommands();
  const project = useProject();

  if (!run || !project) {
    return <div className="p-4 text-gray-500">No run data</div>;
  }

  return (
    <div className="flex h-full flex-col overflow-auto">
      {/* Run metadata */}
      <div className="border-b border-gray-200 p-4">
        <dl className="space-y-3">
          <div className="flex items-center justify-between gap-4 text-sm">
            <dt className="font-medium text-gray-600">Work Order</dt>
            <dd>
              <a
                href={`/projects/${project.id}/history?filters[workorder_id]=${run.work_order_id}`}
                className="link-uuid"
                title={`View work order ${run.work_order_id}`}
              >
                {displayShortUuid(run.work_order_id)}
              </a>
            </dd>
          </div>

          <div className="flex items-center justify-between gap-4 text-sm">
            <dt className="font-medium text-gray-600">Run</dt>
            <dd>
              <a
                href={`/projects/${project.id}/runs/${run.id}${selectedStepId ? `?step=${selectedStepId}` : ''}`}
                className="link-uuid"
                title={`View run ${run.id}`}
              >
                {displayShortUuid(run.id)}
              </a>
            </dd>
          </div>

          {(run.created_by || run.starting_trigger) && (
            <div className="flex items-center justify-between gap-4 text-sm">
              <dt className="font-medium text-gray-600">Started by</dt>
              <dd className="text-right text-gray-900">
                {run.created_by?.email ||
                  (run.starting_trigger
                    ? `${run.starting_trigger.type} trigger`
                    : 'Unknown')}
              </dd>
            </div>
          )}

          {run.started_at && (
            <div className="flex items-center justify-between gap-4 text-sm">
              <dt className="font-medium text-gray-600">Started</dt>
              <dd className="text-gray-900">
                {new Date(run.started_at).toLocaleString()}
              </dd>
            </div>
          )}

          <div className="flex items-center justify-between gap-4 text-sm">
            <dt className="font-medium text-gray-600">Duration</dt>
            <dd className="text-gray-900">
              <ElapsedIndicator
                startedAt={run.started_at}
                finishedAt={run.finished_at}
              />
            </dd>
          </div>

          <div className="flex items-center justify-between gap-4 text-sm">
            <dt className="font-medium text-gray-600">Status</dt>
            <dd>
              <StatePill state={run.state} />
            </dd>
          </div>
        </dl>
      </div>

      {/* Steps list */}
      <div className="flex-1 overflow-auto p-4">
        <h3 className="mb-3 text-sm font-semibold text-gray-900">Steps</h3>
        <StepList
          steps={run.steps}
          selectedStepId={selectedStepId}
          onSelectStep={selectStep}
        />
      </div>
    </div>
  );
}
