/**
 * WorkflowEditor - Main workflow editing component
 */

import { useEffect, useState } from "react";
import { useHotkeys, useHotkeysContext } from "react-hotkeys-hook";

import _logger from "#/utils/logger";

import { useURLState } from "../../react/lib/use-url-state";
import type { WorkflowState as YAMLWorkflowState } from "../../yaml/types";
import { useIsNewWorkflow, useProject } from "../hooks/useSessionContext";
import {
  useIsRunPanelOpen,
  useRunPanelContext,
  useUICommands,
} from "../hooks/useUI";
import {
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
  useWorkflowStoreContext,
  useWorkflowReadOnly,
} from "../hooks/useWorkflow";

import { CollaborativeWorkflowDiagram } from "./diagram/CollaborativeWorkflowDiagram";
import { FullScreenIDE } from "./ide/FullScreenIDE";
import { Inspector } from "./inspector";
import { LeftPanel } from "./left-panel";
import { ManualRunPanel } from "./ManualRunPanel";

const logger = _logger.ns("WorkflowEditor").seal();

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
  const { isReadOnly } = useWorkflowReadOnly();

  // UI state from store
  const isRunPanelOpen = useIsRunPanelOpen();
  const runPanelContext = useRunPanelContext();
  const { closeRunPanel, openRunPanel } = useUICommands();

  // Manage "panel" scope based on whether run panel is open
  // When run panel opens, disable "panel" scope so Inspector Escape doesn't fire
  // When run panel closes, re-enable "panel" scope so Inspector Escape works
  const { activeScopes } = useHotkeysContext();

  useEffect(() => {
    logger.debug({ activeScopes });
  }, [activeScopes]);

  // Update run panel context when selected node changes (if panel is open)
  useEffect(() => {
    if (isRunPanelOpen && currentNode.node) {
      // Panel is open and a node is selected - update context
      if (currentNode.type === "job") {
        openRunPanel({ jobId: currentNode.node.id });
      } else if (currentNode.type === "trigger") {
        openRunPanel({ triggerId: currentNode.node.id });
      } else if (currentNode.type === "edge") {
        // Close panel if edge selected
        closeRunPanel();
      }
    }
    // Don't close when currentNode.node is null - panel can stay open
    // with its initial context
  }, [
    currentNode.type,
    currentNode.node,
    isRunPanelOpen,
    openRunPanel,
    closeRunPanel,
  ]);

  // Get projectId from session context store
  const project = useProject();
  const projectId = project?.id;

  // WorkflowId comes from workflow state
  // LoadingBoundary guarantees workflow is non-null here
  const workflowState = useWorkflowState(state => state.workflow!);
  const workflowId = workflowState.id;

  const [showLeftPanel, setShowLeftPanel] = useState(isNewWorkflow);

  // Run state from ManualRunPanel
  const [canRunWorkflow, setCanRunWorkflow] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const [runHandler, setRunHandler] = useState<(() => void) | null>(null);

  // Construct full workflow object from state
  // LoadingBoundary guarantees workflow is non-null here
  const workflow = useWorkflowState(state => ({
    ...state.workflow!,
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
    positions: state.positions,
  }));

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
  const showInspector = hash === "settings" || Boolean(currentNode.node);

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

  // Callback from ManualRunPanel with run state
  const handleRunStateChange = (
    canRun: boolean,
    isSubmitting: boolean,
    handler: () => void
  ) => {
    setCanRunWorkflow(canRun);
    setIsRunning(isSubmitting);
    setRunHandler(() => handler);
  };

  // Handle Cmd/Ctrl+Enter to open run panel or trigger run
  useHotkeys(
    "mod+enter",
    event => {
      event.preventDefault();

      if (isRunPanelOpen) {
        // Panel is open - trigger run
        if (runHandler && canRunWorkflow && !isRunning) {
          runHandler();
        }
      } else {
        // Panel is closed - open it
        if (currentNode.type === "job" && currentNode.node) {
          openRunPanel({ jobId: currentNode.node.id });
        } else if (currentNode.type === "trigger" && currentNode.node) {
          openRunPanel({ triggerId: currentNode.node.id });
        } else {
          // Nothing selected - open with first trigger (like clicking Run)
          const firstTrigger = workflow.triggers[0];
          if (firstTrigger) {
            openRunPanel({ triggerId: firstTrigger.id });
          }
        }
      }
    },
    {
      enabled: !isIDEOpen, // Disable in canvas when IDE is open
      enableOnFormTags: true,
    },
    [
      isRunPanelOpen,
      runHandler,
      canRunWorkflow,
      isRunning,
      currentNode,
      openRunPanel,
      isIDEOpen,
      workflow,
    ]
  );

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
            <CollaborativeWorkflowDiagram inspectorId="inspector" />

            {/* Inspector slides in from the right and appears on top
                This div is also the wrapper which is used to calculate the overlap
                between the inspector and the diagram.  */}
            <div
              id="inspector"
              className={`absolute top-0 right-0 h-full transition-transform duration-300 ease-in-out z-10 ${
                showInspector
                  ? "translate-x-0"
                  : "translate-x-full pointer-events-none"
              }`}
            >
              <Inspector
                currentNode={currentNode}
                onClose={handleCloseInspector}
                onOpenRunPanel={openRunPanel}
                respondToHotKey={!isRunPanelOpen}
              />
            </div>

            {/* Run panel overlays inspector when open */}
            {isRunPanelOpen && runPanelContext && projectId && workflowId && (
              <div className="absolute inset-y-0 right-0 flex pointer-events-none z-20">
                <ManualRunPanel
                  workflow={workflow}
                  projectId={projectId}
                  workflowId={workflowId}
                  jobId={runPanelContext.jobId ?? null}
                  triggerId={runPanelContext.triggerId ?? null}
                  onClose={closeRunPanel}
                  onRunStateChange={handleRunStateChange}
                  saveWorkflow={saveWorkflow}
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
