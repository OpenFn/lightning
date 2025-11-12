import { formatRelative } from 'date-fns';
import React, { useState } from 'react';

import type { WorkflowRunHistory } from '#/workflow-store/store';

import { relativeLocale } from '../hooks';
import { cn } from '../utils/cn';
import { duration } from '../utils/duration';
import truncateUid from '../utils/truncateUID';

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

const displayTextFromState = (state: string): string =>
  `${state[0]?.toUpperCase()}${state.substring(1)}`;

const StatePill: React.FC<{ state: string; mini?: boolean }> = ({
  state,
  mini = false,
}) => {
  const classes = CHIP_STYLES[state] || CHIP_STYLES['pending'];
  const text = displayTextFromState(state);

  const baseClasses =
    'my-auto whitespace-nowrap rounded-full text-center align-baseline font-medium leading-none';
  const sizeClasses = mini ? 'py-1 px-2 text-[10px]' : 'py-2 px-4 text-xs';

  return <span className={cn(baseClasses, sizeClasses, classes)}>{text}</span>;
};

interface MiniHistoryProps {
  collapsed: boolean;
  history: WorkflowRunHistory;
  drawerWidth: number;
  selectRunHandler: (runId: string, version: number) => void;
  onCollapseHistory: () => void;
  hasSnapshotMismatch?: boolean;
  missingNodeCount?: number;
}

export default function MiniHistory({
  history,
  selectRunHandler,
  collapsed = true,
  onCollapseHistory,
  drawerWidth,
  hasSnapshotMismatch = false,
  missingNodeCount = 0,
}: MiniHistoryProps) {
  const [expandedWorder, setExpandedWorder] = useState('');
  const [isCollapsed, setIsCollapsed] = useState(collapsed);

  const now = new Date();

  // to ensure panel is not collapsed when there's a selected item in history
  // at time this component will be rendered before data reaches store. that makes the panel collapse
  const selectedItem = history.find(w => w.selected)?.id;
  React.useEffect(() => {
    if (selectedItem) {
      setIsCollapsed(false);
    }
  }, [selectedItem]);

  const expandWorkorderHandler = (workorder: WorkflowRunHistory[number]) => {
    if (workorder.runs.length === 1 && workorder.runs[0]) {
      selectRunHandler(workorder.runs[0].id, workorder.version);
    }
    setExpandedWorder(prev => (prev === workorder.id ? '' : workorder.id));
  };

  const historyToggle = () => {
    setIsCollapsed(p => !p);
  };

  const gotoHistory = (e: React.MouseEvent | React.KeyboardEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const currentUrl = new URL(window.location.href);
    const nextUrl = new URL(currentUrl);
    const paths = nextUrl.pathname.split('/');
    const wIdx = paths.indexOf('w');
    const workflowPaths = paths.splice(wIdx, paths.length - wIdx);
    nextUrl.pathname = paths.join('/') + `/history`;
    nextUrl.search = `?filters[workflow_id]=${
      workflowPaths[workflowPaths.length - 1]
    }`;
    window.location = nextUrl.toString();
  };

  const navigateToWorkorderHistory = (
    e: React.MouseEvent,
    workorderId: string
  ) => {
    e.preventDefault();
    e.stopPropagation();
    const currentUrl = new URL(window.location.href);
    const nextUrl = new URL(currentUrl);
    const paths = nextUrl.pathname.split('/');
    const projectIndex = paths.indexOf('projects');
    const projectId = projectIndex !== -1 ? paths[projectIndex + 1] : null;

    if (projectId) {
      nextUrl.pathname = `/projects/${projectId}/history`;
      nextUrl.search = `?filters[workorder_id]=${workorderId}`;
      window.location = nextUrl.toString();
    }
  };

  const navigateToRunView = (e: React.MouseEvent, runId: string) => {
    e.preventDefault();
    e.stopPropagation();
    const currentUrl = new URL(window.location.href);
    const nextUrl = new URL(currentUrl);
    const paths = nextUrl.pathname.split('/');
    const projectIndex = paths.indexOf('projects');
    const projectId = projectIndex !== -1 ? paths[projectIndex + 1] : null;

    if (projectId) {
      nextUrl.pathname = `/projects/${projectId}/runs/${runId}`;
      window.location = nextUrl.toString();
    }
  };

  return (
    <div
      className={`absolute left-4 top-16 bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden z-40`}
      style={{
        transform: `translateX(${drawerWidth.toString()}px)`,
        transition: 'transform 300ms ease-in-out',
      }}
    >
      <div
        className={cn(
          'flex items-center cursor-pointer justify-between px-3 py-2 border-gray-200 bg-gray-50 hover:bg-gray-100 transition-colors',
          isCollapsed ? 'border-b-0' : 'border-b'
        )}
        onClick={() => historyToggle()}
      >
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-gray-700">
            {isCollapsed ? 'View History' : 'Recent History'}
          </h3>
          <button
            id="view-history"
            type="button"
            className="text-gray-400 hover:text-gray-600 transition-colors flex items-center"
            phx-hook="Tooltip"
            data-placement="top"
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
          className="text-gray-400 hover:text-gray-600 transition-colors cursor-pointer ml-3"
          title="Collapse panel"
        >
          {isCollapsed ? (
            <span className="hero-chevron-right w-4 h-4"></span>
          ) : (
            <span className="hero-chevron-left w-4 h-4"></span>
          )}
        </div>
      </div>

      <div
        className={cn(
          'overflow-y-auto no-scrollbar max-h-82',
          isCollapsed ? 'hidden' : 'block'
        )}
      >
        {history.length === 0 ? (
          <div className="flex flex-col items-center justify-center p-8 text-gray-500">
            <span className="hero-rectangle-stack w-8 h-8 mb-2 opacity-50"></span>
            <p className="text-sm font-medium">No related history</p>
            <p className="text-xs text-gray-400 mt-1">
              Why not run it a few times to see some history?
            </p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {history.map(workorder => (
              <div key={workorder.id}>
                <div className="px-3 py-2 hover:bg-gray-50 transition-colors">
                  <div
                    className="flex items-center justify-between cursor-pointer"
                    onClick={() => expandWorkorderHandler(workorder)}
                  >
                    <div className="flex items-center gap-2 min-w-0 flex-1 mr-2">
                      <button
                        onClick={e => {
                          e.preventDefault();
                          e.stopPropagation();
                          setExpandedWorder(prev =>
                            prev === workorder.id ? '' : workorder.id
                          );
                        }}
                        className="flex items-center text-gray-400 hover:text-gray-600 transition-colors"
                      >
                        {workorder.selected ? (
                          <span className="hero-chevron-down w-4 h-4 font-bold text-indigo-600"></span>
                        ) : expandedWorder === workorder.id ? (
                          <span className="hero-chevron-down w-4 h-4"></span>
                        ) : (
                          <span className="hero-chevron-right w-4 h-4"></span>
                        )}
                      </button>
                      <button
                        onClick={e =>
                          navigateToWorkorderHistory(e, workorder.id)
                        }
                        className="link-uuid"
                        title={workorder.id}
                      >
                        {truncateUid(workorder.id)}
                      </button>
                      <span className="text-xs text-gray-800">&bull;</span>
                      <span className="text-xs text-gray-500">
                        {formatRelative(
                          new Date(workorder.last_activity),
                          now,
                          { locale: relativeLocale }
                        )}
                      </span>
                    </div>
                    <StatePill
                      key={workorder.id}
                      state={workorder.state}
                      mini={true}
                    />
                  </div>
                </div>

                {(expandedWorder === workorder.id || workorder.selected) &&
                  workorder.runs.map(run => (
                    <div
                      key={run.id}
                      className={cn(
                        'px-3 py-1.5 text-xs hover:bg-gray-50 transition-colors cursor-pointer border-l-2',
                        run.selected
                          ? 'bg-indigo-50 border-l-indigo-500'
                          : 'border-l-transparent'
                      )}
                      onClick={() =>
                        run.selected
                          ? onCollapseHistory()
                          : selectRunHandler(run.id, workorder.version)
                      }
                    >
                      <div className="flex items-center justify-between w-full mr-2">
                        <div className="flex items-center gap-2 min-w-0 flex-1">
                          <span
                            className={cn(
                              'hero-x-mark w-4 h-4 text-gray-400',
                              run.selected ? 'visible' : 'invisible'
                            )}
                          ></span>
                          <button
                            onClick={e => navigateToRunView(e, run.id)}
                            className="link-uuid"
                            title={run.id}
                          >
                            {truncateUid(run.id)}
                          </button>
                          {(run.started_at || run.finished_at) && (
                            <>
                              <span className="text-xs text-gray-800">
                                &bull;
                              </span>
                              {formatRelative(
                                new Date(run.started_at || run.finished_at),
                                now,
                                {
                                  locale: relativeLocale,
                                }
                              )}
                            </>
                          )}
                          {run.started_at && run.finished_at && (
                            <>
                              <span className="text-xs text-gray-800">
                                &bull;
                              </span>
                              <span className="text-gray-400 text-xs">
                                {duration(run.started_at, run.finished_at)}
                              </span>
                            </>
                          )}
                        </div>
                        <div className="flex items-center gap-1">
                          <StatePill state={run.state} mini={true} />
                          {hasSnapshotMismatch && run.selected && (
                            <div
                              className="flex items-center justify-center"
                              phx-hook="Tooltip"
                              data-placement="right"
                              aria-label={`This run had ${missingNodeCount} step${
                                missingNodeCount !== 1 ? 's' : ''
                              } that ${
                                missingNodeCount !== 1 ? 'are' : 'is'
                              } no longer visible in the current workflow version.`}
                            >
                              <span className="hero-exclamation-triangle-mini w-3 h-3 text-yellow-600"></span>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
