import { formatRelative } from 'date-fns';
import React, { useState } from 'react';

import { relativeLocale } from '../../../hooks';
import { duration } from '../../../utils/duration';
import truncateUid from '../../../utils/truncateUID';
import type { RunSummary, WorkOrder } from '../../types/history';

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

export const StatePill: React.FC<{ state: string; mini?: boolean }> = ({
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

interface HistoryListProps {
  history: WorkOrderWithSelection[];
  selectRunHandler: (run: RunSummary) => void;
  onDeselectRun?: (() => void) | undefined;
  loading?: boolean;
  error?: string | null;
  onRetry?: (() => void) | undefined;
  onWorkOrderClick?: ((workorderId: string) => void) | undefined;
  onRunClick?: ((runId: string) => void) | undefined;
}

export function HistoryList({
  history,
  selectRunHandler,
  onDeselectRun,
  loading = false,
  error = null,
  onRetry,
  onWorkOrderClick,
  onRunClick,
}: HistoryListProps) {
  const [expandedWorder, setExpandedWorder] = useState('');
  const now = new Date();

  const expandWorkorderHandler = (workorder: WorkOrderWithSelection) => {
    const isCurrentlyExpanded = expandedWorder === workorder.id;

    // Only auto-select if expanding (not collapsing) and there's
    // exactly 1 run
    if (
      !isCurrentlyExpanded &&
      workorder.runs.length === 1 &&
      workorder.runs[0]
    ) {
      selectRunHandler(workorder.runs[0]);
    }

    setExpandedWorder(prev => (prev === workorder.id ? '' : workorder.id));
  };

  const handleWorkOrderLinkClick = (
    e: React.MouseEvent,
    workorderId: string
  ) => {
    e.preventDefault();
    e.stopPropagation();
    onWorkOrderClick?.(workorderId);
  };

  const handleRunLinkClick = (e: React.MouseEvent, runId: string) => {
    e.preventDefault();
    e.stopPropagation();
    onRunClick?.(runId);
  };

  // Loading state
  if (loading) {
    return (
      <div
        className="flex flex-col items-center justify-center p-8
          text-gray-500"
      >
        <div
          className="animate-spin rounded-full h-8 w-8 border-b-2
            border-gray-900 mb-2"
        ></div>
        <p className="text-sm font-medium">Loading history...</p>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div
        className="flex flex-col items-center justify-center p-8
          text-gray-500"
      >
        <span
          className="hero-exclamation-triangle w-8 h-8 mb-2
            text-red-500"
        ></span>
        <p className="text-sm font-semibold text-gray-700 mb-1">
          Failed to load history
        </p>
        <p className="text-xs text-gray-500 mb-3">{error}</p>
        {onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="text-xs text-blue-600 hover:text-blue-700
              font-medium"
          >
            Try again
          </button>
        )}
      </div>
    );
  }

  // Empty state
  if (history.length === 0) {
    return (
      <div
        className="flex flex-col items-center justify-center p-8
          text-center"
      >
        <span
          className="hero-rectangle-stack w-12 h-12 text-gray-300 mb-4
            opacity-50"
        ></span>
        <p className="text-sm font-medium text-gray-700 mb-1">
          No related history
        </p>
        <p className="text-xs text-gray-500">
          Why not run it a few times to see some history?
        </p>
      </div>
    );
  }

  // History list
  return (
    <div className="divide-y divide-gray-100">
      {history.map(workorder => (
        <div key={workorder.id}>
          {/* Work order header */}
          <div className="px-3 py-2 hover:bg-gray-50 transition-colors">
            {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
            <div
              className="flex items-center justify-between
                cursor-pointer w-full text-left"
              onClick={() => expandWorkorderHandler(workorder)}
            >
              <div className="flex items-center gap-2 min-w-0 flex-1 mr-2">
                {/* Chevron button */}
                <button
                  type="button"
                  className="flex items-center text-gray-400
                    hover:text-gray-600 transition-colors"
                  aria-label={
                    expandedWorder === workorder.id
                      ? 'Collapse work order details'
                      : 'Expand work order details'
                  }
                  onClick={e => {
                    e.stopPropagation();
                    expandWorkorderHandler(workorder);
                  }}
                >
                  {workorder.selected ? (
                    <span
                      className="hero-chevron-down w-4 h-4
                        font-bold text-indigo-600"
                    ></span>
                  ) : expandedWorder === workorder.id ? (
                    <span className="hero-chevron-down w-4 h-4"></span>
                  ) : (
                    <span className="hero-chevron-right w-4 h-4"></span>
                  )}
                </button>

                {/* UUID link */}
                <button
                  type="button"
                  className="link-uuid"
                  title={workorder.id}
                  aria-label={`View full details for work order ${truncateUid(workorder.id)}`}
                  onClick={e => handleWorkOrderLinkClick(e, workorder.id)}
                >
                  {truncateUid(workorder.id)}
                </button>

                <span className="text-xs text-gray-800">&bull;</span>

                {/* Timestamp */}
                <span className="text-xs text-gray-500">
                  {formatRelative(new Date(workorder.last_activity), now, {
                    locale: relativeLocale,
                  })}
                </span>
              </div>

              {/* State pill */}
              <StatePill
                key={workorder.id}
                state={workorder.state}
                mini={true}
              />
            </div>
          </div>

          {/* Runs list */}
          {(expandedWorder === workorder.id || workorder.selected) &&
            workorder.runs.map(run => (
              // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
              <div
                key={run.id}
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
                    onDeselectRun?.();
                  } else {
                    selectRunHandler(run);
                  }
                }}
              >
                <div
                  className="flex items-center justify-between
                    w-full mr-2"
                >
                  <div className="flex items-center gap-2 min-w-0 flex-1">
                    {run.selected && (
                      <button
                        type="button"
                        onClick={e => {
                          e.preventDefault();
                          e.stopPropagation();
                          onDeselectRun?.();
                        }}
                        className="flex items-center text-gray-400
                          hover:text-gray-600 transition-colors"
                        aria-label="Deselect run"
                      >
                        <span className="hero-x-mark w-4 h-4"></span>
                      </button>
                    )}
                    {!run.selected && (
                      <span className="w-4 h-4 invisible"></span>
                    )}

                    {/* UUID link */}
                    <button
                      type="button"
                      className="link-uuid"
                      title={run.id}
                      aria-label={`View full details for run ${truncateUid(run.id)}`}
                      onClick={e => handleRunLinkClick(e, run.id)}
                    >
                      {truncateUid(run.id)}
                    </button>

                    {(run.started_at || run.finished_at) && (
                      <>
                        <span className="text-xs text-gray-800">&bull;</span>
                        {formatRelative(
                          new Date(
                            (run.started_at || run.finished_at) as string
                          ),
                          now,
                          {
                            locale: relativeLocale,
                          }
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

                  {/* State pill */}
                  <div className="flex items-center gap-1">
                    <StatePill state={run.state} mini={true} />
                  </div>
                </div>
              </div>
            ))}
        </div>
      ))}
    </div>
  );
}
