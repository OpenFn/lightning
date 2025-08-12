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
  onClose: () => void;
}

export const Inspector: React.FC<InspectorProps> = ({
  currentNode,
  onClose,
}) => {
  if (!currentNode.node || !currentNode.type) {
    return (
      <div className="pointer-events-auto w-screen max-w-md transform">
        <div className="relative flex h-full flex-col divide-y divide-gray-200 bg-white shadow-xl">
          <div className="flex min-h-0 flex-1 flex-col overflow-y-auto py-6">
            <div className="px-4 sm:px-6">
              <div className="flex items-start justify-between">
                <h2 className="text-base font-semibold text-gray-900">
                  Inspector
                </h2>
                <div className="ml-3 flex h-7 items-center">
                  <button
                    type="button"
                    onClick={onClose}
                    className="relative rounded-md text-gray-400 hover:text-gray-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                  >
                    <span className="absolute -inset-2.5" />
                    <span className="sr-only">Close panel</span>
                    <div className="hero-x-mark size-6" />
                  </button>
                </div>
              </div>
            </div>
            <div className="relative mt-6 flex-1 px-4 sm:px-6">
              <div className="flex items-center justify-center h-full text-gray-500">
                <div className="text-center">
                  <p className="text-sm">No node selected</p>
                  <p className="text-xs mt-1">
                    Select a job, trigger, or edge to inspect
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="pointer-events-auto w-screen max-w-md transform">
      <div className="relative flex h-full flex-col divide-y divide-gray-200 bg-white shadow-xl">
        <div className="flex min-h-0 flex-1 flex-col overflow-y-auto py-6">
          <div className="px-4 sm:px-6">
            <div className="flex items-start justify-between">
              <h2 className="text-base font-semibold text-gray-900">
                Inspector
              </h2>
              <div className="ml-3 flex h-7 items-center">
                <button
                  type="button"
                  onClick={onClose}
                  className="relative rounded-md text-gray-400 hover:text-gray-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                >
                  <span className="absolute -inset-2.5" />
                  <span className="sr-only">Close panel</span>
                  <div className="hero-x-mark size-6" />
                </button>
              </div>
            </div>
            <div className="mt-2">
              <span className="text-xs bg-gray-100 px-2 py-1 rounded">
                {currentNode.type}
              </span>
            </div>
          </div>
          <div className="relative mt-6 flex-1 px-4 sm:px-6">
            {currentNode.type === "job" && (
              <JobInspector job={currentNode.node as Workflow.Job} />
            )}
            {currentNode.type === "trigger" && (
              <TriggerInspector
                trigger={currentNode.node as Workflow.Trigger}
              />
            )}
            {currentNode.type === "edge" && (
              <EdgeInspector edge={currentNode.node as Workflow.Edge} />
            )}
          </div>
        </div>
        <div className="flex shrink-0 justify-end px-4 py-4">
          <button
            type="button"
            onClick={onClose}
            className="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs inset-ring inset-ring-gray-300 hover:inset-ring-gray-400"
          >
            Cancel
          </button>
          <button
            type="submit"
            className="ml-4 inline-flex justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
};
