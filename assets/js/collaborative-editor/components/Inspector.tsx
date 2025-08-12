/**
 * Inspector - Side panel component for displaying node details
 * Shows details for jobs, triggers, and edges when selected
 */

import type React from "react";
import type { Workflow } from "../types";

interface JobInspectorProps {
  job: Workflow.Job;
}

const JobInspector: React.FC<JobInspectorProps> = ({ job }) => {
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

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
}

const TriggerInspector: React.FC<TriggerInspectorProps> = ({ trigger }) => {
  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">
          Trigger Details
        </h3>
        <div className="space-y-2">
          <div>
            <label className="text-xs text-gray-500">Name</label>
            <p className="text-sm text-gray-900">{trigger.name}</p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Type</label>
            <p className="text-sm text-gray-900">{trigger.type}</p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Enabled</label>
            <p className="text-sm text-gray-900">
              {trigger.enabled ? "Yes" : "No"}
            </p>
          </div>
          <div>
            <label className="text-xs text-gray-500">ID</label>
            <p className="text-xs text-gray-500 font-mono">{trigger.id}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

interface EdgeInspectorProps {
  edge: Workflow.Edge;
}

const EdgeInspector: React.FC<EdgeInspectorProps> = ({ edge }) => {
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

interface InspectorProps {
  currentNode: {
    node: Workflow.Node | null;
    type: Workflow.NodeType | null;
    id: string | null;
  };
}

export const Inspector: React.FC<InspectorProps> = ({ currentNode }) => {
  if (!currentNode.node || !currentNode.type) {
    return (
      <div className="h-full w-80 bg-white border-l border-gray-200 p-4">
        <div className="flex items-center justify-center h-full text-gray-500">
          <div className="text-center">
            <p className="text-sm">No node selected</p>
            <p className="text-xs mt-1">
              Select a job, trigger, or edge to inspect
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full w-80 bg-white border-l border-gray-200 p-4 overflow-y-auto">
      <div className="mb-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-medium text-gray-900">Inspector</h2>
          <span className="text-xs bg-gray-100 px-2 py-1 rounded">
            {currentNode.type}
          </span>
        </div>
      </div>

      {currentNode.type === "job" && (
        <JobInspector job={currentNode.node as Workflow.Job} />
      )}
      {currentNode.type === "trigger" && (
        <TriggerInspector trigger={currentNode.node as Workflow.Trigger} />
      )}
      {currentNode.type === "edge" && (
        <EdgeInspector edge={currentNode.node as Workflow.Edge} />
      )}
    </div>
  );
};
