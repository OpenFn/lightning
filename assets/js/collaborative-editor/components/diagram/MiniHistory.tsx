/**
 * # MiniHistory Component
 *
 * Displays workflow execution history (work orders and runs) in a
 * collapsible floating panel on the canvas.
 *
 * ## Features:
 * - Collapsible panel with expand/collapse toggle
 * - Work order list with status pills
 * - Expandable run details within each work order
 * - Navigation to full history view
 * - Navigation to individual work order/run detail views
 * - Empty state when no history available
 *
 * ## Usage:
 * ```typescript
 * <MiniHistory
 *   collapsed={historyCollapsed}
 *   history={workflowHistory}
 *   onCollapseHistory={() => setHistoryCollapsed(!historyCollapsed)}
 *   selectRunHandler={(run) => console.log('Selected run:', run.id)}
 * />
 * ```
 */

import { formatRelative } from 'date-fns';
import React, { useState } from 'react';

import { relativeLocale } from '../../../hooks';
import { duration } from '../../../utils/duration';
import truncateUid from '../../../utils/truncateUID';
import { useProject } from '../../hooks/useSessionContext';
import { useWorkflowState } from '../../hooks/useWorkflow';
import type { RunSummary, WorkOrder } from '../../types/history';
import {
  navigateToRun,
  navigateToWorkOrderHistory,
  navigateToWorkflowHistory,
} from '../../utils/navigation';
import { RunBadge } from '../common/RunBadge';

// Extended types with selection state for UI
type RunWithSelection = RunSummary & { selected?: boolean };
type WorkOrderWithSelection = Omit<WorkOrder, 'runs'> & {
  runs: RunWithSelection[];
  selected?: boolean;
};

const CHIP_STYLES: Record<string, string> = {
  // only workorder states...
  rejected: 'bg-red-300 text-gray-800',
  pending: 'bg-gray-200 text-gray-800',
  running: 'bg-blue-200 text-blue-800',
  //  run and workorder states...
  available: 'bg-gray-200 text-gray-800',
  claimed: 'bg-blue-200 text-blue-800',
  started: 'bg-blue-200 text-blue-800',
  success: 'bg-green-200 text-green-800',
  failed: 'bg-red-200 text-red-800',
  crashed: 'bg-orange-200 text-orange-800',
  cancelled: 'bg-gray-500 text-gray-800',
  killed: 'bg-yellow-200 text-yellow-800',
  exception: 'bg-gray-800 text-white',
  lost: 'bg-gray-800 text-white',
};

const displayTextFromState = (state: string): string => {
  if (state.length === 0) return '';
  return state.charAt(0).toUpperCase() + state.substring(1);
};

const StatePill: React.FC<{ state: string; mini?: boolean }> = ({
  state,
  mini = false,
}) => {
  const classes = CHIP_STYLES[state] || CHIP_STYLES['pending'];
  const text = displayTextFromState(state);

  const baseClasses =
    'my-auto whitespace-nowrap rounded-full text-center ' +
    'align-baseline font-medium leading-none';
  const sizeClasses = mini ? 'py-1 px-2 text-[10px]' : 'py-2 px-4 text-xs';

  return (
    <span className={`${baseClasses} ${sizeClasses} ${classes}`}>{text}</span>
  );
};

// Extracted RunItem component for displaying individual runs
interface RunItemProps {
  run: RunWithSelection;
  now: Date;
  onSelect: (run: RunSummary) => void;
  onDeselect: (() => void) | undefined;
  onNavigateToRun: (e: React.MouseEvent, runId: string) => void;
}

const RunItem: React.FC<RunItemProps> = ({
  run,
  now,
  onSelect,
  onDeselect,
  onNavigateToRun,
}) => (
  /*
    Mouse-only clickable area - keyboard users can navigate to
    the run detail page using the UUID link button below.
  */
  // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
  <div
    className={[
      'px-3 py-1.5 text-xs hover:bg-gray-50 ' +
        'transition-colors cursor-pointer border-l-2 ' +
        'w-full text-left',
      run.selected
        ? 'bg-indigo-50 border-l-indigo-500'
        : ' border-l-transparent',
    ].join(' ')}
    onClick={e => {
      e.stopPropagation();
      if (run.selected) {
        onDeselect?.();
      } else {
        onSelect(run);
      }
    }}
  >
    <div className="flex items-center justify-between w-full mr-2">
      <div className="flex items-center gap-2 min-w-0 flex-1">
        {run.selected && (
          <button
            type="button"
            onClick={e => {
              e.preventDefault();
              e.stopPropagation();
              onDeselect?.();
            }}
            className="flex items-center text-gray-400
              hover:text-gray-600 transition-colors"
            aria-label="Deselect run"
          >
            <span className="hero-x-mark w-4 h-4" />
          </button>
        )}
        {!run.selected && <span className="w-4 h-4 invisible" />}
        <button
          type="button"
          onClick={e => onNavigateToRun(e, run.id)}
          className="link-uuid"
          title={run.id}
          aria-label={`View full details for run ${truncateUid(run.id)}`}
        >
          {truncateUid(run.id)}
        </button>
        {(run.started_at || run.finished_at) && (
          <>
            <span className="text-xs text-gray-800">&bull;</span>
            {formatRelative(
              new Date((run.started_at || run.finished_at) as string),
              now,
              { locale: relativeLocale }
            )}
          </>
        )}
        {run.started_at && run.finished_at && (
          <>
            <span className="text-xs text-gray-800">&bull;</span>
            <span className="text-gray-400 text-xs">
              {duration(run.started_at, run.finished_at)}
            </span>
          </>
        )}
      </div>
      <div className="flex items-center gap-1">
        <StatePill state={run.state} mini={true} />
      </div>
    </div>
  </div>
);

// Extracted WorkOrderItem component for displaying work orders with their runs
interface WorkOrderItemProps {
  workorder: WorkOrderWithSelection;
  isExpanded: boolean;
  now: Date;
  onExpand: (workorder: WorkOrderWithSelection) => void;
  onSelectRun: (run: RunSummary) => void;
  onDeselectRun: (() => void) | undefined;
  onNavigateToWorkorder: (e: React.MouseEvent, workorderId: string) => void;
  onNavigateToRun: (e: React.MouseEvent, runId: string) => void;
}

const WorkOrderItem: React.FC<WorkOrderItemProps> = ({
  workorder,
  isExpanded,
  now,
  onExpand,
  onSelectRun,
  onDeselectRun,
  onNavigateToWorkorder,
  onNavigateToRun,
}) => (
  <div>
    <div className="px-3 py-2 hover:bg-gray-50 transition-colors">
      {/*
        Mouse-only clickable area for convenience - keyboard users
        can use the chevron button and UUID link below for full accessibility.
        This matches the LiveView implementation's keyboard navigation pattern.
      */}
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
      <div
        className="flex items-center justify-between cursor-pointer w-full text-left"
        onClick={e => {
          e.stopPropagation();
          onExpand(workorder);
        }}
      >
        <div className="flex items-center gap-2 min-w-0 flex-1 mr-2">
          <button
            type="button"
            onClick={e => {
              e.preventDefault();
              e.stopPropagation();
              onExpand(workorder);
            }}
            className="flex items-center text-gray-400
              hover:text-gray-600 transition-colors"
            aria-label={`${isExpanded ? 'Collapse' : 'Expand'} work order details`}
          >
            {workorder.selected ? (
              <span className="hero-chevron-down w-4 h-4 font-bold text-indigo-600" />
            ) : isExpanded ? (
              <span className="hero-chevron-down w-4 h-4" />
            ) : (
              <span className="hero-chevron-right w-4 h-4" />
            )}
          </button>
          <button
            type="button"
            onClick={e => onNavigateToWorkorder(e, workorder.id)}
            className="link-uuid"
            title={workorder.id}
            aria-label={`View full details for work order ${truncateUid(workorder.id)}`}
          >
            {truncateUid(workorder.id)}
          </button>
          <span className="text-xs text-gray-800">&bull;</span>
          <span className="text-xs text-gray-500">
            {formatRelative(new Date(workorder.last_activity), now, {
              locale: relativeLocale,
            })}
          </span>
        </div>
        <StatePill state={workorder.state} mini={true} />
      </div>
    </div>

    {(isExpanded || workorder.selected) &&
      workorder.runs.map(run => (
        <RunItem
          key={run.id}
          run={run}
          now={now}
          onSelect={onSelectRun}
          onDeselect={onDeselectRun}
          onNavigateToRun={onNavigateToRun}
        />
      ))}
  </div>
);

interface MiniHistoryProps {
  collapsed: boolean;
  history: WorkOrderWithSelection[];
  onCollapseHistory: () => void;
  selectRunHandler: (run: RunSummary) => void;
  onDeselectRun?: () => void;
  selectedRun?: RunSummary | null;
  loading?: boolean;
  error?: string | null;
  onRetry?: () => void;
  // New props for panel variant
  variant?: 'floating' | 'panel';
  onBack?: () => void;
}

export default function MiniHistory({
  history,
  selectRunHandler,
  collapsed = true,
  onCollapseHistory,
  onDeselectRun,
  selectedRun,
  loading = false,
  error = null,
  onRetry,
  variant = 'floating',
  onBack,
}: MiniHistoryProps) {
  const [expandedWorder, setExpandedWorder] = useState('');
  const now = new Date();

  // Get project and workflow IDs from state for navigation
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);

  // Clear expanded work order when panel collapses
  React.useEffect(() => {
    if (collapsed) {
      setExpandedWorder('');
    }
  }, [collapsed]);

  const expandWorkorderHandler = (workorder: WorkOrderWithSelection) => {
    const isCurrentlyExpanded = expandedWorder === workorder.id;

    // Only auto-select if expanding (not collapsing) and there's exactly 1 run
    if (
      !isCurrentlyExpanded &&
      workorder.runs.length === 1 &&
      workorder.runs[0]
    ) {
      selectRunHandler(workorder.runs[0]);
    }

    setExpandedWorder(prev => (prev === workorder.id ? '' : workorder.id));
  };

  const historyToggle = () => {
    onCollapseHistory();
  };

  const gotoHistory = (e: React.MouseEvent | React.KeyboardEvent) => {
    e.preventDefault();
    e.stopPropagation();

    if (project?.id && workflow?.id) {
      navigateToWorkflowHistory(project.id, workflow.id);
    }
  };

  const handleNavigateToWorkorderHistory = (
    e: React.MouseEvent,
    workorderId: string
  ) => {
    e.preventDefault();
    e.stopPropagation();

    if (project?.id) {
      navigateToWorkOrderHistory(project.id, workorderId);
    }
  };

  const handleNavigateToRunView = (e: React.MouseEvent, runId: string) => {
    e.preventDefault();
    e.stopPropagation();

    if (project?.id) {
      navigateToRun(project.id, runId);
    }
  };

  // Panel variant header with back button
  const PanelHeader = () => (
    <div
      className="flex items-center px-3 py-2 border-b
        border-gray-200 bg-gray-50"
    >
      <h3 className="text-sm font-medium text-gray-700 mr-1">Run History</h3>
      <button
        type="button"
        onClick={gotoHistory}
        className="text-gray-400 hover:text-gray-600 transition-colors"
        aria-label="View full history for this workflow"
      >
        <span className="hero-rectangle-stack w-4 h-4" />
      </button>
      <div className="flex-1" />
      <button
        type="button"
        onClick={onBack}
        className="p-1 mr-2 text-gray-400 hover:text-gray-600
          hover:bg-gray-100 rounded transition-colors"
        aria-label="Back to landing"
      >
        <span className="hero-x-mark w-4 h-4" />
      </button>
    </div>
  );

  // Panel variant - no absolute positioning, no collapse, uses back button
  if (variant === 'panel') {
    return (
      <div className="flex flex-col h-full bg-white">
        <PanelHeader />
        <div className="flex-1 overflow-y-auto">
          {loading && !history.length ? (
            <div
              className="flex flex-col items-center justify-center
                p-8 text-gray-500"
            >
              <div
                className="animate-spin rounded-full h-8 w-8
                  border-b-2 border-gray-900 mb-2"
              />
              <p className="text-sm font-medium">Loading history...</p>
            </div>
          ) : error ? (
            <div
              className="flex flex-col items-center justify-center
                p-8 text-gray-500"
            >
              <span
                className="hero-exclamation-triangle w-8 h-8
                  mb-2 text-red-500"
              />
              <p className="text-sm font-medium text-red-600">
                Failed to load history
              </p>
              <p className="text-xs text-gray-400 mt-1">{error}</p>
              {onRetry && (
                <button
                  type="button"
                  onClick={onRetry}
                  className="mt-3 px-3 py-1 text-xs bg-blue-500
                    text-white rounded hover:bg-blue-600"
                >
                  Retry
                </button>
              )}
            </div>
          ) : history.length === 0 ? (
            <div
              className="flex flex-col items-center justify-center
                p-8 text-gray-500"
            >
              <span
                className="hero-rectangle-stack w-8 h-8
                  mb-2 opacity-50"
              />
              <p className="text-sm font-medium">No related history</p>
              <p className="text-xs text-gray-400 mt-1">
                Why not run it a few times to see some history?
              </p>
            </div>
          ) : (
            <div className="divide-y divide-gray-100">
              {history.map(workorder => (
                <WorkOrderItem
                  key={workorder.id}
                  workorder={workorder}
                  isExpanded={expandedWorder === workorder.id}
                  now={now}
                  onExpand={expandWorkorderHandler}
                  onSelectRun={selectRunHandler}
                  onDeselectRun={onDeselectRun}
                  onNavigateToWorkorder={handleNavigateToWorkorderHistory}
                  onNavigateToRun={handleNavigateToRunView}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // Floating variant - existing implementation
  return (
    <div
      className={`absolute left-4 top-6 bg-white border
        border-gray-200 rounded-lg shadow-sm overflow-hidden z-40
        transition-all duration-300 ease-in-out`}
    >
      {/*
        Mouse-only clickable area for header - keyboard users can use the
        "view full history" button or chevron icon for navigation.
      */}
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
      <div
        className={`flex items-center cursor-pointer justify-between
          px-3 py-2 border-gray-200 bg-gray-50 hover:bg-gray-100
          transition-colors w-full text-left
          ${collapsed ? 'border-b-0' : 'border-b'}`}
        onClick={() => historyToggle()}
      >
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-gray-700">
            {collapsed ? 'View History' : 'Recent History'}
          </h3>
          <button
            id="view-history"
            type="button"
            className="text-gray-400 hover:text-gray-600
              transition-colors flex items-center"
            aria-label="View full history for this workflow"
            onClick={gotoHistory}
            onKeyDown={e => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                gotoHistory(e);
              }
            }}
          >
            <span className="hero-rectangle-stack w-4 h-4"></span>
          </button>
          {loading && history.length ? (
            <span className="hero-arrow-path size-4 animate-spin"></span>
          ) : null}
        </div>

        <div
          className="text-gray-400 hover:text-gray-600 transition-colors
            cursor-pointer ml-3"
          title="Collapse panel"
        >
          {collapsed ? (
            <span className="hero-chevron-right w-4 h-4"></span>
          ) : (
            <span className="hero-chevron-left w-4 h-4"></span>
          )}
        </div>
      </div>

      {/* Show run chip when collapsed and run selected */}
      {collapsed && selectedRun && (
        <div className="px-3 py-2 border-t border-gray-200">
          <RunBadge runId={selectedRun.id} onClose={() => onDeselectRun?.()} />
        </div>
      )}

      <div
        className={`overflow-y-auto no-scrollbar max-h-82
          transition-opacity duration-200 ${
            collapsed ? 'opacity-0 h-0 hidden' : 'opacity-100'
          }`}
      >
        {loading && !history.length ? (
          <div
            className="flex flex-col items-center justify-center
            p-8 text-gray-500"
          >
            <div
              className="animate-spin rounded-full h-8 w-8
              border-b-2 border-gray-900 mb-2"
            ></div>
            <p className="text-sm font-medium">Loading history...</p>
          </div>
        ) : error ? (
          <div
            className="flex flex-col items-center justify-center
            p-8 text-gray-500"
          >
            <span
              className="hero-exclamation-triangle w-8 h-8
              mb-2 text-red-500"
            ></span>
            <p className="text-sm font-medium text-red-600">
              Failed to load history
            </p>
            <p className="text-xs text-gray-400 mt-1">{error}</p>
            {onRetry && (
              <button
                type="button"
                onClick={onRetry}
                className="mt-3 px-3 py-1 text-xs bg-blue-500
                  text-white rounded hover:bg-blue-600"
              >
                Retry
              </button>
            )}
          </div>
        ) : history.length === 0 ? (
          <div
            className="flex flex-col items-center justify-center
            p-8 text-gray-500"
          >
            <span
              className="hero-rectangle-stack w-8 h-8
              mb-2 opacity-50"
            ></span>
            <p className="text-sm font-medium">No related history</p>
            <p className="text-xs text-gray-400 mt-1">
              Why not run it a few times to see some history?
            </p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {history.map(workorder => (
              <WorkOrderItem
                key={workorder.id}
                workorder={workorder}
                isExpanded={expandedWorder === workorder.id}
                now={now}
                onExpand={expandWorkorderHandler}
                onSelectRun={selectRunHandler}
                onDeselectRun={onDeselectRun}
                onNavigateToWorkorder={handleNavigateToWorkorderHistory}
                onNavigateToRun={handleNavigateToRunView}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
