import type {
  WorkflowRunHistory,
  WorkOrderStates,
} from '#/workflow-store/store';
import React, { useState } from 'react';
import formatDate from '../utils/formatDate';
import { timeSpent } from '../utils/timeSpent';
import truncateUid from '../utils/truncateUID';
import { renderIcon } from './components/RunIcons';

// TODO: to be put somewhere else
const STATE_ICONS = {
  rejected: 'hero-x-circle',
  pending: 'hero-clock',
  running: 'hero-play-circle',
  available: 'hero-clock',
  claimed: 'hero-arrow-right-circle',
  started: 'hero-play-circle',
  success: 'hero-check-circle',
  failed: 'hero-x-circle',
  crashed: 'hero-exclamation-triangle',
  cancelled: 'hero-no-symbol',
  killed: 'hero-shield-exclamation',
  exception: 'hero-exclamation-circle',
  lost: 'hero-question-mark-circle',
};

const StatePill: React.FC<{ state: WorkOrderStates }> = ({ state }) => {
  return renderIcon(state, { size: 6 });
};

interface MiniHistoryProps {
  collapsed: boolean;
  history: WorkflowRunHistory;
  selectRunHandler: (runId: string, version: number) => void;
  onCollapseHistory: () => void;
}

export default function MiniHistory({
  history,
  selectRunHandler,
  collapsed = true,
  onCollapseHistory,
}: MiniHistoryProps) {
  const [expandedWorder, setExpandedWorder] = useState('');
  const [isCollapsed, setIsCollapsed] = useState(collapsed);

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
  }


  return (
    <div
      className={`absolute left-2 top-2 bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden ${isCollapsed ? 'w-44' : 'w-88'
        }`}
    >
      {/* Header */}
      <div
        className={`flex items-center cursor-pointer justify-between px-3 py-2 border-gray-200 bg-gray-50 ${isCollapsed ? 'border-b-0' : 'border-b'
          }`}
        onClick={() => historyToggle()}
      >
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-gray-700">
            {isCollapsed ? 'View history' : 'Recent Activities'}
          </h3>
          <a
            href={`#`}
            className="text-gray-400 hover:text-gray-600 transition-colors"
            title="View full history for this workflow"
          >
            <span className="hero-arrow-top-right-on-square w-4 h-4"></span>
          </a>
        </div>

        <div
          className="text-gray-400 hover:text-gray-600 transition-colors cursor-pointer"
          title="Collapse panel"
        >
          {isCollapsed ? (
            <span className="hero-chevron-right w-4 h-4"></span>
          ) : (
            <span className="hero-chevron-left w-4 h-4"></span>
          )}
        </div>
      </div>

      {/* Content */}
      <div
        className={`overflow-y-auto no-scrollbar ${isCollapsed ? 'h-0' : 'h-82'
          }`}
      >
        {history.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-gray-500">
            <span className="hero-clock w-8 h-8 mb-2 opacity-50"></span>
            <p className="text-sm font-medium">No recent activity</p>
            <p className="text-xs text-gray-400 mt-1">
              Run your workflow to see execution history
            </p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {history.map(workorder => (
              <div key={workorder.id}>
                {/* Workorder Row */}
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
                        {formatDate(new Date(workorder.last_activity))}
                      </span>
                    </div>
                    <StatePill key={workorder.id} state={workorder.state} />
                  </div>
                </div>

                {/* Runs */}
                {(expandedWorder === workorder.id || workorder.selected) &&
                  workorder.runs.map(run => (
                    <div
                      key={run.id}
                      className={[
                        "px-3 py-1.5 text-xs hover:bg-gray-50 transition-colors cursor-pointer border-l-2",
                        run.selected
                          ? "bg-indigo-50 border-l-indigo-500"
                          : " border-l-transparent",
                      ].join(" ")}
                      onClick={() => run.selected ? onCollapseHistory() : selectRunHandler(run.id, workorder.version)}
                    >
                      <div className="flex items-center justify-between w-full">
                        <div className="flex items-center gap-2 min-w-0 flex-1">
                          <span className={`hero-x-mark w-4 h-4 text-gray-400 ${run.selected ? "visible" : "invisible"}`}></span>
                          <span className="text-gray-500 truncate">
                            {truncateUid(run.id)}
                          </span>
                          <span className="text-gray-500 font-mono">
                            {run.started_at
                              ? formatDate(new Date(run.started_at))
                              : formatDate(new Date(run.finished_at))}
                          </span>
                          <span className="text-gray-400 text-xs">
                            {!run.started_at || !run.finished_at
                              ? '-ms'
                              : timeSpent(run.started_at, run.finished_at)}
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
