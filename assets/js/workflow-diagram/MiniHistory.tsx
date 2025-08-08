import { relativeLocale } from '../hooks';
import type {
  WorkflowRunHistory,
  WorkOrderStates,
} from '#/workflow-store/store';
import { formatRelative } from 'date-fns';
import React, { useState } from 'react';
import { duration } from '../utils/duration';
import truncateUid from '../utils/truncateUID';
import { renderIcon } from './components/RunIcons';

const StatePill: React.FC<{ state: WorkOrderStates }> = ({ state }) => {
  return renderIcon(state, { size: 6 });
};

interface MiniHistoryProps {
  collapsed: boolean;
  history: WorkflowRunHistory;
  drawerWidth: number;
  selectRunHandler: (runId: string, version: number) => void;
  onCollapseHistory: () => void;
}

export default function MiniHistory({
  history,
  selectRunHandler,
  collapsed = true,
  onCollapseHistory,
  drawerWidth,
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

  const gotoHistory = (e: MouseEvent) => {
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

  return (
    <div
      className={`absolute left-4 top-16 bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden z-40 ${
        isCollapsed ? 'w-auto' : 'w-88'
      }`}
      style={{
        transform: `translateX(${drawerWidth}px)`,
        transition: 'transform 500ms ease-in-out',
      }}
    >
      <div
        className={`flex items-center cursor-pointer justify-between px-3 py-2 border-gray-200 bg-gray-50 hover:bg-gray-100 transition-colors ${
          isCollapsed ? 'border-b-0' : 'border-b'
        }`}
        onClick={() => historyToggle()}
      >
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-gray-700">
            {isCollapsed ? 'View History' : 'Recent Activity'}
          </h3>
          <div
            className="text-gray-400 hover:text-gray-600 transition-colors flex items-center"
            title="View full history for this workflow"
            onClick={gotoHistory}
          >
            <span className="hero-arrow-top-right-on-square w-4 h-4"></span>
          </div>
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
        className={`overflow-y-auto no-scrollbar max-h-82 ${
          isCollapsed ? 'hidden' : 'block'
        }`}
      >
        {history.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-gray-500">
            <span className="hero-clock w-8 h-8 mb-2 opacity-50"></span>
            <p className="text-sm font-medium">No related activity</p>
            <p className="text-xs text-gray-400 mt-1">
              Run your workflow to see execution history
            </p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {history.map(workorder => (
              <div key={workorder.id}>
                <div className={`px-3 py-2 hover:bg-gray-50 transition-colors`}>
                  <div
                    className="flex items-center justify-between cursor-pointer"
                    onClick={() => expandWorkorderHandler(workorder)}
                  >
                    <div className="flex items-center gap-2 min-w-0 flex-1">
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
                      <span className="text-xs text-gray-500 truncate">
                        {truncateUid(workorder.id)}
                      </span>
                      <span className="text-xs text-gray-500 font-mono">
                        {formatRelative(
                          new Date(workorder.last_activity),
                          now,
                          { locale: relativeLocale }
                        )}
                      </span>
                    </div>
                    <StatePill key={workorder.id} state={workorder.state} />
                  </div>
                </div>

                {(expandedWorder === workorder.id || workorder.selected) &&
                  workorder.runs.map(run => (
                    <div
                      key={run.id}
                      className={[
                        'px-3 py-1.5 text-xs hover:bg-gray-50 transition-colors cursor-pointer border-l-2',
                        run.selected
                          ? 'bg-indigo-50 border-l-indigo-500'
                          : ' border-l-transparent',
                      ].join(' ')}
                      onClick={() =>
                        run.selected
                          ? onCollapseHistory()
                          : selectRunHandler(run.id, workorder.version)
                      }
                    >
                      <div className="flex items-center justify-between w-full">
                        <div className="flex items-center gap-2 min-w-0 flex-1">
                          <span
                            className={`hero-x-mark w-4 h-4 text-gray-400 ${
                              run.selected ? 'visible' : 'invisible'
                            }`}
                          ></span>
                          <span className="text-gray-500 truncate">
                            {truncateUid(run.id)}
                          </span>
                          <span className="text-gray-500 font-mono">
                            {run.started_at
                              ? formatRelative(new Date(run.started_at), now, {
                                  locale: relativeLocale,
                                })
                              : formatRelative(new Date(run.finished_at), now, {
                                  locale: relativeLocale,
                                })}
                          </span>
                          <span className="text-gray-400 text-xs">
                            {!run.started_at || !run.finished_at
                              ? '-ms'
                              : duration(run.started_at, run.finished_at)}
                          </span>
                        </div>
                        <StatePill state={run.state} />
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
