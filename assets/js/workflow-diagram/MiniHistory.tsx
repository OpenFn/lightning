import truncateUid from "../utils/truncateUID";
import type { WorkflowRunHistory, WorkOrderStates } from "#/workflow-store/store";
import formatDate from "../utils/formatDate";
import { useState } from "react";

const StatePill: React.FC<{ state: WorkOrderStates, size?: "normal" | "mini" }> = ({ state, size = "normal" }) => {
  const icon = () => {
    switch (state) {
      case "success":
        return "hero-check";
      case "failed":
        return "hero-exclamation-circle";
      case "crashed":
        return "hero-fire";
      default:
        return "hero-information-circle"
    }
  }

  const colors = () => {
    switch (state) {
      case "success":
        return "bg-green-200 text-green-500";
      case "failed":
        return "bg-red-200 text-red-500";
      case "crashed":
        return "bg-orange-200 text-orange-500";
      default:
        return "bg-slate-200 text-slate-500"
    }
  }
  console.log(size)
  return <span
    className={`inline-flex rounded-full bg-gray-200 justify-center items-center ${colors()} ${size === "normal" ? "w-6 h-6" : "w-4 h-4"}`}>
    <span className={`${icon()} ${size === "normal" ? "w-4 h-4" : "w-3 h-3"}`}></span>
  </span >
};

const formatDuration = (start, end) => {
  if (!start || !end) return "-";
  const durationMs = new Date(end) - new Date(start);
  const minutes = Math.floor(durationMs / 60000);
  return `${minutes} min`;
};

interface MiniHistoryProps {
  history: WorkflowRunHistory;
  selectRunHandler: (runId: string, version: number) => void
}

export default function MiniHistory({
  history,
  selectRunHandler
}: MiniHistoryProps) {
  const [expandedWorder, setExpandedWorder] = useState("");
  const loading = false;

  return (
    <div className="absolute left-2 top-2 h-96 max-h-96 min-w-88 bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-gray-200 bg-gray-50">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-gray-700">Recent Activity</h3>
          <a
            href={`#`}
            className="text-gray-400 hover:text-gray-600 transition-colors"
            title="View full history for this workflow"
          >
            <span className="hero-arrow-down-on-square w-4 h-4"></span>
          </a>
        </div>

        <div
          className="text-gray-400 hover:text-gray-600 transition-colors cursor-pointer"
          title="Collapse panel"
        >
          <span className="hero-chevron-left w-4 h-4" ></span>
        </div>
      </div>

      {/* Content */}
      <div className="overflow-y-auto h-full">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <div className="text-sm text-gray-500">Loading recent activity...</div>
          </div>
        ) : history.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-gray-500">
            <span className="hero-clock w-8 h-8 mb-2 opacity-50" ></span>
            <p className="text-sm font-medium">No recent activity</p>
            <p className="text-xs text-gray-400 mt-1">
              Run your workflow to see execution history
            </p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {history.map((workorder) => (
              <div key={workorder.id}>
                {/* Workorder Row */}
                <div className={`px-3 py-2 hover:bg-gray-50 transition-colors ${workorder.selected ? "border-l-2 border-l-indigo-500" : ""}`}>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2 min-w-0 flex-1">
                      <button
                        onClick={() => setExpandedWorder(prev => prev === workorder.id ? "" : workorder.id)}
                        className="text-gray-400 hover:text-gray-600 transition-colors"
                      >
                        {expandedWorder === workorder.id ? (
                          <span className="hero-chevron-down w-4 h-4" ></span>
                        ) : (
                          <span className="hero-chevron-right w-4 h-4" ></span>
                        )}
                      </button>
                      <span className="text-xs font-semibold text-gray-500 truncate">
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
                  workorder.runs.map((run) => (
                    <div
                      key={run.id}
                      className={[
                        "pl-8 pr-3 py-1.5 text-xs hover:bg-gray-50 transition-colors cursor-pointer",
                        run.selected
                          ? "bg-indigo-50 border-l-2 border-l-indigo-500"
                          : "",
                      ].join(" ")}
                      onClick={() => selectRunHandler(run.id, workorder.version)}
                    >
                      <div className="flex items-center justify-between w-full">
                        <div className="flex items-center gap-2 min-w-0 flex-1">
                          <span className="text-gray-500 truncate">
                            {truncateUid(run.id)}
                          </span>
                          <span className="text-gray-500 font-mono">
                            {run.started_at
                              ? formatDate(new Date(run.started_at))
                              : formatDate(new Date(run.finished_at))}
                          </span>
                          <span className="text-gray-400 text-xs">
                            {formatDuration(run.started_at, run.finished_at)}
                          </span>
                        </div>
                        <StatePill state={run.state} size="mini" />
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
