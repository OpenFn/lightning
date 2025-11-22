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

import React from 'react';

import { useProject } from '../../hooks/useSessionContext';
import { useWorkflowState } from '../../hooks/useWorkflow';
import type { RunSummary, WorkOrder } from '../../types/history';
import {
  navigateToRun,
  navigateToWorkOrderHistory,
  navigateToWorkflowHistory,
} from '../../utils/navigation';

import { HistoryList } from './HistoryList';

// Extended types with selection state for UI
type RunWithSelection = RunSummary & { selected?: boolean };
type WorkOrderWithSelection = Omit<WorkOrder, 'runs'> & {
  runs: RunWithSelection[];
  selected?: boolean;
};

interface MiniHistoryProps {
  collapsed: boolean;
  history: WorkOrderWithSelection[];
  onCollapseHistory: () => void;
  selectRunHandler: (run: RunSummary) => void;
  onDeselectRun?: () => void;
  loading?: boolean;
  error?: string | null;
  onRetry?: () => void;
}

export default function MiniHistory({
  history,
  selectRunHandler,
  collapsed = true,
  onCollapseHistory,
  onDeselectRun,
  loading = false,
  error = null,
  onRetry,
}: MiniHistoryProps) {
  // Get project and workflow IDs from state for navigation
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);

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

  const handleNavigateToWorkorderHistory = (workorderId: string) => {
    if (project?.id) {
      navigateToWorkOrderHistory(project.id, workorderId);
    }
  };

  const handleNavigateToRunView = (runId: string) => {
    if (project?.id) {
      navigateToRun(project.id, runId);
    }
  };

  return (
    <div
      className={`absolute left-6 top-6 bg-white border
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

      {/* Content - HistoryList */}
      <div
        className={`overflow-y-auto no-scrollbar max-h-82
          transition-opacity duration-200 ${
            collapsed ? 'opacity-0 h-0 hidden' : 'opacity-100'
          }`}
      >
        <HistoryList
          history={history}
          selectRunHandler={selectRunHandler}
          onDeselectRun={onDeselectRun}
          loading={loading}
          error={error}
          onRetry={onRetry}
          onWorkOrderClick={handleNavigateToWorkorderHistory}
          onRunClick={handleNavigateToRunView}
        />
      </div>
    </div>
  );
}
