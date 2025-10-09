/**
 * WorkflowEditor - Main workflow editing component
 */

import { useURLState } from "../../react/lib/use-url-state";
import { useSession } from "../hooks/useSession";
import {
  useCurrentJob,
  useNodeSelection,
  useWorkflowState,
} from "../hooks/useWorkflow";

import { CollaborativeMonaco } from "./CollaborativeMonaco";
import { CollaborativeWorkflowDiagram } from "./diagram/CollaborativeWorkflowDiagram";
import { Inspector } from "./inspector";

export function WorkflowEditor() {
  const { hash } = useURLState();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { currentNode, selectNode } = useNodeSelection();
  const { awareness } = useSession();

  // Construct full workflow object from state
  const workflow = useWorkflowState(state =>
    state.workflow
      ? {
          name: state.workflow.name,
          jobs: state.jobs,
          triggers: state.triggers,
          edges: state.edges,
          positions: state.positions,
        }
      : null
  );

  const handleCloseInspector = () => {
    selectNode(null);
  };

  // Show inspector panel if settings is open OR a node is selected
  const showInspector = hash === "settings" || currentNode.node;

  return (
    <div className="relative h-full w-full">
      <CollaborativeWorkflowDiagram inspectorId="inspector" />
      {/* Inspector slides in from the right and appears on top
          This div is also the wrapper which is used to calculate the overlap
          between the inspector and the diagram.  */}
      {workflow && (
        <div
          id="inspector"
          className={`absolute top-0 right-0 h-full transition-transform duration-300 ease-in-out ${
            showInspector
              ? "translate-x-0"
              : "translate-x-full pointer-events-none"
          }`}
        >
          <Inspector
            workflow={workflow}
            currentNode={currentNode}
            onClose={handleCloseInspector}
          />
        </div>
      )}
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
}
