import type React from "react";
import type { Workflow } from "../types";

interface EdgeInspectorProps {
  edge: Workflow.Edge;
}

export const EdgeInspector: React.FC<EdgeInspectorProps> = ({ edge }) => {
  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">Edge Details</h3>
        <div className="space-y-2">
          <div>
            <label className="text-xs text-gray-500">Source</label>
            <p className="text-sm text-gray-900">
              {edge.source_job_id
                ? `Job: ${edge.source_job_id}`
                : edge.source_trigger_id
                  ? `Trigger: ${edge.source_trigger_id}`
                  : "Unknown"}
            </p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Target</label>
            <p className="text-sm text-gray-900">Job: {edge.target_job_id}</p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Condition</label>
            <p className="text-sm text-gray-900">
              {edge.condition || "Always"}
            </p>
          </div>
          <div>
            <label className="text-xs text-gray-500">ID</label>
            <p className="text-xs text-gray-500 font-mono">{edge.id}</p>
          </div>
        </div>
      </div>
    </div>
  );
};
