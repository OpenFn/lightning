/**
 * WorkflowEditor - Main workflow editing component
 * Replaces TodoList with workflow-specific functionality
 */

import type React from "react";
import { useSession } from "../contexts/SessionProvider";
import {
  useCurrentJob,
  useNodeSelection,
} from "../contexts/WorkflowStoreProvider";
import { CollaborativeMonaco } from "./CollaborativeMonaco";
import { CollaborativeWorkflowDiagram } from "./diagram/CollaborativeWorkflowDiagram";
import { Inspector } from "./Inspector";

export const WorkflowEditor: React.FC = () => {
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { currentNode } = useNodeSelection();
  const { awareness } = useSession();

  return (
    <div className="relative h-full w-full flex">
      <div className="flex-1 min-w-0">
        <CollaborativeWorkflowDiagram />
      </div>
      <Inspector currentNode={currentNode} />
      {false && ( // Leaving this here for now, but we'll remove/replace it in the future
        <div className="flex flex-col h-full">
          {/* Main Content */}

          {/* Right Panel - Split vertically */}
          <div className="flex-1 min-w-0 flex flex-col overflow-y-auto">
            {/* Workflow Diagram */}
            <div className="flex-none h-1/3 border-b border-gray-200">
              <CollaborativeWorkflowDiagram />
            </div>

            {/* Bottom Right - Monaco Editor */}
            <div className="flex-1 min-h-0">
              {currentJob && currentJobYText && awareness ? (
                <CollaborativeMonaco
                  ytext={currentJobYText}
                  awareness={awareness}
                  adaptor="common"
                  disabled={false}
                  className="h-full w-full"
                />
              ) : (
                <div className="flex items-center justify-center h-full text-gray-500">
                  <div className="text-center">
                    <p className="text-lg">Select a job to edit</p>
                    <p className="text-sm">
                      Choose a job from the sidebar to start editing with the
                      collaborative Monaco editor
                    </p>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
