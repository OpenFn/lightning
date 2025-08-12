import type React from "react";
import type { Workflow } from "../types";

interface JobInspectorProps {
  job: Workflow.Job;
}

export const JobInspector: React.FC<JobInspectorProps> = ({ job }) => {
  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">Job Details</h3>
        <div className="space-y-2">
          <div>
            <label className="text-xs text-gray-500">Name</label>
            <p className="text-sm text-gray-900">{job.name}</p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Adaptor</label>
            <p className="text-sm text-gray-900">{job.adaptor}</p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Enabled</label>
            <p className="text-sm text-gray-900">
              {job.enabled ? "Yes" : "No"}
            </p>
          </div>
          <div>
            <label className="text-xs text-gray-500">ID</label>
            <p className="text-xs text-gray-500 font-mono">{job.id}</p>
          </div>
        </div>
      </div>

      <div>
        <label className="text-xs text-gray-500 mb-1 block">Body Preview</label>
        <div className="bg-gray-50 p-2 rounded text-xs font-mono max-h-32 overflow-y-auto">
          <pre className="whitespace-pre-wrap text-gray-700">
            {job.body || "// No code yet"}
          </pre>
        </div>
      </div>
    </div>
  );
};
