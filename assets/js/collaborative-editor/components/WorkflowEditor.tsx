/**
 * WorkflowEditor - Main workflow editing component
 */

import { useState } from "react";

import { useURLState } from "../../react/lib/use-url-state";
import type { WorkflowState as YAMLWorkflowState } from "../../yaml/types";
import { useSession } from "../hooks/useSession";
import { useIsNewWorkflow } from "../hooks/useSessionContext";
import {
  useCurrentJob,
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
  useWorkflowStoreContext,
} from "../hooks/useWorkflow";

import { CollaborativeMonaco } from "./CollaborativeMonaco";
import { CollaborativeWorkflowDiagram } from "./diagram/CollaborativeWorkflowDiagram";
import { Inspector } from "./inspector";
import { LeftPanel } from "./left-panel";

export function WorkflowEditor() {
  const { hash, searchParams, updateSearchParams } = useURLState();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { currentNode, selectNode } = useNodeSelection();
  const { awareness } = useSession();
  const workflowStore = useWorkflowStoreContext();
  const isNewWorkflow = useIsNewWorkflow();
  const { saveWorkflow } = useWorkflowActions();

  const [showLeftPanel, setShowLeftPanel] = useState(isNewWorkflow);

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

  // Get current creation method from URL
  const currentMethod = searchParams.get("method") as
    | "template"
    | "import"
    | "ai"
    | null;

  // Default to template method if no method specified and panel is open
  const leftPanelMethod = showLeftPanel ? currentMethod || "template" : null;

  const handleCloseInspector = () => {
    selectNode(null);
  };

  // Show inspector panel if settings is open OR a node is selected
  const showInspector = hash === "settings" || currentNode.node;

  const handleMethodChange = (method: "template" | "import" | "ai" | null) => {
    updateSearchParams({ method });
  };

  const handleImport = (workflowState: YAMLWorkflowState) => {
    workflowStore.importWorkflow(workflowState);
  };

  const handleCloseLeftPanel = () => {
    setShowLeftPanel(false);
    updateSearchParams({ method: null });
  };

  const handleSaveAndClose = async () => {
    await saveWorkflow();
    handleCloseLeftPanel();
  };

  return (
    <div className="relative flex h-full w-full">
      {/* Main content area - flex grows to fill remaining space */}
      <div
        className={`flex-1 relative transition-all duration-300 ease-in-out ${
          showLeftPanel ? "ml-[33.333333%]" : "ml-0"
        }`}
      >
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
      </div>

      {/* Left Panel - Workflow creation methods (absolute positioned, slides over) */}
      <LeftPanel
        method={leftPanelMethod}
        onMethodChange={handleMethodChange}
        onImport={handleImport}
        onClosePanel={handleCloseLeftPanel}
        onSave={handleSaveAndClose}
      />

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
