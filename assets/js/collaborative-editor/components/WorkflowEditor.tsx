/**
 * WorkflowEditor - Main workflow editing component
 */

import { useState } from "react";

import { useURLState } from "../../react/lib/use-url-state";
import type { WorkflowState as YAMLWorkflowState } from "../../yaml/types";
import { useIsNewWorkflow } from "../hooks/useSessionContext";
import {
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
  useWorkflowStoreContext,
} from "../hooks/useWorkflow";

import { useProject } from "../hooks/useSessionContext";
import { CollaborativeWorkflowDiagram } from "./diagram/CollaborativeWorkflowDiagram";
import { FullScreenIDE } from "./ide/FullScreenIDE";
import { Inspector } from "./inspector";
import { LeftPanel } from "./left-panel";
import { SandboxIndicatorBanner } from "./SandboxIndicatorBanner";

interface WorkflowEditorProps {
  parentProjectId?: string | null;
  parentProjectName?: string | null;
}

export function WorkflowEditor({
  parentProjectId,
  parentProjectName,
}: WorkflowEditorProps = {}) {
  const { hash, searchParams, updateSearchParams } = useURLState();
  const { currentNode, selectNode } = useNodeSelection();
  const workflowStore = useWorkflowStoreContext();
  const isNewWorkflow = useIsNewWorkflow();
  const { saveWorkflow } = useWorkflowActions();
  const project = useProject();

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

  // Check if IDE should be open
  const isIDEOpen = searchParams.get("editor") === "open";
  const selectedJobId = searchParams.get("job");

  const handleCloseInspector = () => {
    selectNode(null);
  };

  // Show inspector panel if settings is open OR a node is selected
  const showInspector = hash === "settings" || currentNode.node;

  const handleMethodChange = (method: "template" | "import" | "ai" | null) => {
    updateSearchParams({ method });
  };

  const handleImport = async (workflowState: YAMLWorkflowState) => {
    // Validate workflow name with server before importing
    try {
      const validatedState =
        await workflowStore.validateWorkflowName(workflowState);

      workflowStore.importWorkflow(validatedState);
    } catch (error) {
      console.error("Failed to validate workflow name:", error);
      // Fall back to original state if validation fails
      workflowStore.importWorkflow(workflowState);
    }
  };

  const handleCloseLeftPanel = () => {
    setShowLeftPanel(false);
    updateSearchParams({ method: null });
  };

  const handleSaveAndClose = async () => {
    await saveWorkflow();
    handleCloseLeftPanel();
  };

  const handleCloseIDE = () => {
    updateSearchParams({ editor: null });
  };

  return (
    <div className="relative flex h-full w-full">
      {/* Canvas and Inspector - hidden when IDE open */}
      {!isIDEOpen && (
        <>
          {/* Main content area - flex grows to fill remaining space */}
          <div
            className={`flex-1 relative transition-all duration-300 ease-in-out ${
              showLeftPanel ? "ml-[33.333333%]" : "ml-0"
            }`}
          >
            <SandboxIndicatorBanner
              parentProjectId={parentProjectId}
              parentProjectName={parentProjectName}
              projectName={project?.name}
            />
            <CollaborativeWorkflowDiagram inspectorId="inspector" />

            {/* Inspector slides in from the right and appears on top
                This div is also the wrapper which is used to calculate the overlap
                between the inspector and the diagram.  */}
            {workflow && (
              <div
                id="inspector"
                className={`absolute top-0 right-0 h-full transition-transform duration-300 ease-in-out z-10 ${
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
        </>
      )}

      {/* Full-Screen IDE - replaces canvas when open */}
      {isIDEOpen && selectedJobId && (
        <FullScreenIDE
          jobId={selectedJobId}
          onClose={handleCloseIDE}
          parentProjectId={parentProjectId}
          parentProjectName={parentProjectName}
        />
      )}
    </div>
  );
}
