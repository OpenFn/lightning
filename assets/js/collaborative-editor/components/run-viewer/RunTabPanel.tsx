import { useRef, useState } from 'react';
import {
  type ImperativePanelHandle,
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from 'react-resizable-panels';

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

  const metaPanelRef = useRef<ImperativePanelHandle>(null);
  const stepsPanelRef = useRef<ImperativePanelHandle>(null);
  const [isMetaCollapsed, setIsMetaCollapsed] = useState(false);
  const [isStepsCollapsed, setIsStepsCollapsed] = useState(false);

  if (!run || !project) {
    return <div className="p-4 text-gray-500">No run data</div>;
  }

  return (
    <PanelGroup direction="horizontal" className="h-full">
      {/* Run metadata */}
      <Panel
        ref={metaPanelRef}
        defaultSize={50}
        minSize={30}
        collapsible
        collapsedSize={2}
        onCollapse={() => setIsMetaCollapsed(true)}
        onExpand={() => setIsMetaCollapsed(false)}
      >
        {isMetaCollapsed ? (
          <button
            onClick={() => metaPanelRef.current?.expand()}
            className="h-full w-full flex items-center justify-center text-xs font-medium text-gray-400
              uppercase tracking-wide hover:text-gray-600 transition-colors cursor-pointer whitespace-nowrap writing-mode-vertical"
            style={{ writingMode: 'vertical-rl' }}
          >
            Meta
          </button>
        ) : (
          <div className="h-full overflow-auto border-r border-gray-200 p-4">
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

              <div className="flex items-center justify-between gap-4 text-sm">
                <dt className="font-medium text-gray-600">Status</dt>
                <dd>
                  <StatePill state={run.state} />
                </dd>
              </div>

              <div className="flex items-center justify-between gap-4 text-sm">
                <dt className="font-medium text-gray-600">Duration</dt>
                <dd className="text-gray-900">
                  <ElapsedIndicator
                    startedAt={run.started_at}
                    finishedAt={run.finished_at}
                  />
                </dd>
              </div>

              {run.started_at && (
                <div className="flex items-center justify-between gap-4 text-sm">
                  <dt className="font-medium text-gray-600">Started</dt>
                  <dd className="text-gray-900">
                    {new Date(run.started_at).toLocaleString()}
                  </dd>
                </div>
              )}

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
            </dl>
          </div>
        )}
      </Panel>

      {/* Resize handle */}
      <PanelResizeHandle className="w-1 bg-gray-200 hover:bg-blue-400 transition-colors cursor-col-resize" />

      {/* Steps list */}
      <Panel
        ref={stepsPanelRef}
        defaultSize={50}
        minSize={30}
        collapsible
        collapsedSize={2}
        onCollapse={() => setIsStepsCollapsed(true)}
        onExpand={() => setIsStepsCollapsed(false)}
      >
        {isStepsCollapsed ? (
          <button
            onClick={() => stepsPanelRef.current?.expand()}
            className="h-full w-full flex items-center justify-center text-xs font-medium text-gray-400
              uppercase tracking-wide hover:text-gray-600 transition-colors cursor-pointer whitespace-nowrap"
            style={{ writingMode: 'vertical-rl' }}
          >
            Steps
          </button>
        ) : (
          <div className="h-full overflow-auto p-4">
            <p className="mb-3 text-sm font-medium text-gray-600">
              Steps (this run)
            </p>
            <StepList
              steps={run.steps}
              selectedStepId={selectedStepId}
              onSelectStep={selectStep}
            />
          </div>
        )}
      </Panel>
    </PanelGroup>
  );
}
