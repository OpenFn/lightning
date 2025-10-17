/**
 * Inspector - Side panel component for displaying node details
 * Shows details for jobs, triggers, and edges when selected
 */

import { useEffect, useState } from "react";

import { useURLState } from "../../../react/lib/use-url-state";
import type { Workflow } from "../../types/workflow";

import { EdgeInspector } from "./EdgeInspector";
import { JobInspector } from "./JobInspector";
import { TriggerInspector } from "./TriggerInspector";
import { WorkflowSettings } from "./WorkflowSettings";

interface InspectorProps {
  workflow: Workflow;
  currentNode: {
    node: Workflow.Node | null;
    type: Workflow.NodeType | null;
    id: string | null;
  };
  onClose: () => void;
}

export function Inspector({ workflow, currentNode, onClose }: InspectorProps) {
  const { hash, updateHash } = useURLState();
  const [jobFooterButton, setJobFooterButton] = useState<React.ReactNode>(null);

  const hasSelectedNode = currentNode.node && currentNode.type;

  // Settings hash takes precedence, then node inspector
  const mode =
    hash === "settings" ? "settings" : hasSelectedNode ? "node" : null;

  // Clear footer button when mode changes away from job node
  useEffect(() => {
    if (mode !== "node" || currentNode.type !== "job") {
      setJobFooterButton(null);
    }
  }, [mode, currentNode.type]);

  const handleClose = () => {
    if (mode === "settings") {
      updateHash(null);
    } else {
      onClose(); // Clears node selection
    }
  };

  // Don't render if no mode selected
  if (!mode) return null;

  return (
    <div className="pointer-events-auto w-screen max-w-md h-full">
      <div className="relative flex h-full flex-col divide-y divide-gray-200 bg-white shadow-xl">
        <div className="flex min-h-0 flex-1 flex-col overflow-y-auto py-6">
          <div className="px-4 sm:px-6">
            <div className="flex items-start justify-between">
              <h2 className="text-base font-semibold text-gray-900">
                {mode === "settings" ? "Workflow settings" : "Inspector"}
              </h2>
              <div className="ml-3 flex h-7 items-center">
                <button
                  type="button"
                  onClick={handleClose}
                  className="relative rounded-md text-gray-400 hover:text-gray-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                >
                  <span className="absolute -inset-2.5" />
                  <span className="sr-only">Close panel</span>
                  <div className="hero-x-mark size-6" />
                </button>
              </div>
            </div>
            {mode === "node" && hasSelectedNode && (
              <div className="mt-2">
                <span className="text-xs bg-gray-100 px-2 py-1 rounded">
                  {currentNode.type}
                </span>
              </div>
            )}
          </div>
          <div className="relative mt-6 flex-1 px-4 sm:px-6">
            {mode === "settings" ? (
              <WorkflowSettings workflow={workflow} />
            ) : (
              <>
                {currentNode.type === "job" && (
                  <JobInspector
                    key={`job-${currentNode.id}`}
                    job={currentNode.node as Workflow.Job}
                    renderFooter={setJobFooterButton}
                  />
                )}
                {currentNode.type === "trigger" && (
                  <TriggerInspector
                    key={`trigger-${currentNode.id}`}
                    trigger={currentNode.node as Workflow.Trigger}
                  />
                )}
                {currentNode.type === "edge" && (
                  <EdgeInspector
                    key={`edge-${currentNode.id}`}
                    edge={currentNode.node as Workflow.Edge}
                  />
                )}
              </>
            )}
          </div>
        </div>
        <div className="flex shrink-0 justify-end px-4 py-4">
          <button
            type="button"
            onClick={handleClose}
            className="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs inset-ring inset-ring-gray-300 hover:inset-ring-gray-400"
          >
            Cancel
          </button>
          {mode === "settings" && (
            <button
              type="submit"
              className="ml-4 inline-flex justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            >
              Save
            </button>
          )}
          {mode === "node" && currentNode.type === "job" && jobFooterButton && (
            <div className="ml-4">{jobFooterButton}</div>
          )}
        </div>
      </div>
    </div>
  );
}

// Helper function to open workflow settings from external components
export const openWorkflowSettings = () => {
  const newURL =
    window.location.pathname + window.location.search + "#settings";
  history.pushState({}, "", newURL);
};
