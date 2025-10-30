import {
  useCurrentRun,
  useRunActions,
  useSelectedStepId,
} from "../../hooks/useRun";
import { ElapsedIndicator } from "./ElapsedIndicator";
import { StatePill } from "./StatePill";
import { StepList } from "./StepList";

export function RunTabPanel() {
  const run = useCurrentRun();
  const selectedStepId = useSelectedStepId();
  const { selectStep } = useRunActions();

  if (!run) {
    return <div className="p-4 text-gray-500">No run data</div>;
  }

  return (
    <div className="h-full flex flex-col overflow-auto p-4">
      {/* Run metadata */}
      <dl className="space-y-2 mb-4">
        <div className="flex justify-between text-sm">
          <dt className="font-medium text-gray-700">Work Order</dt>
          <dd className="text-gray-900 font-mono text-xs">
            {run.work_order_id.slice(0, 8)}...
          </dd>
        </div>

        <div className="flex justify-between text-sm">
          <dt className="font-medium text-gray-700">Run</dt>
          <dd className="text-gray-900 font-mono text-xs">
            {run.id.slice(0, 8)}...
          </dd>
        </div>

        {(run.created_by || run.starting_trigger) && (
          <div className="flex justify-between text-sm">
            <dt className="font-medium text-gray-700">Started by</dt>
            <dd className="text-gray-900">
              {run.created_by?.email ||
                (run.starting_trigger
                  ? `${run.starting_trigger.type} trigger`
                  : "Unknown")}
            </dd>
          </div>
        )}

        {run.started_at && (
          <div className="flex justify-between text-sm">
            <dt className="font-medium text-gray-700">Started</dt>
            <dd className="text-gray-900">
              {new Date(run.started_at).toLocaleString()}
            </dd>
          </div>
        )}

        <div className="flex justify-between text-sm">
          <dt className="font-medium text-gray-700">Duration</dt>
          <dd className="text-gray-900">
            <ElapsedIndicator
              startedAt={run.started_at}
              finishedAt={run.finished_at}
            />
          </dd>
        </div>

        <div className="flex justify-between text-sm items-center">
          <dt className="font-medium text-gray-700">Status</dt>
          <dd>
            <StatePill state={run.state} />
          </dd>
        </div>
      </dl>

      {/* Steps list */}
      <div className="flex-1 overflow-auto">
        <h3 className="text-sm font-medium text-gray-700 mb-2">Steps:</h3>
        <StepList
          steps={run.steps}
          selectedStepId={selectedStepId}
          onSelectStep={selectStep}
        />
      </div>
    </div>
  );
}
