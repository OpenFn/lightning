/**
 * WorkflowEditor - Main workflow editing component
 */

import { useEffect, useRef, useState } from "react";
import { useHotkeys, useHotkeysContext } from "react-hotkeys-hook";

import { useURLState } from "../../react/lib/use-url-state";
import type { WorkflowState as YAMLWorkflowState } from "../../yaml/types";
import { SHORTCUT_SCOPES } from "../constants/shortcuts";
import { useIsNewWorkflow, useProject } from "../hooks/useSessionContext";
import {
  useIsRunPanelOpen,
  useRunPanelContext,
  useUICommands,
} from "../hooks/useUI";
import {
  useCanRun,
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
  useWorkflowStoreContext,
} from "../hooks/useWorkflow";
import { notifications } from "../lib/notifications";

import { CollaborativeWorkflowDiagram } from "./diagram/CollaborativeWorkflowDiagram";
import { FullScreenIDE } from "./ide/FullScreenIDE";
import { Inspector } from "./inspector";
import { LeftPanel } from "./left-panel";
import { ManualRunPanel } from "./ManualRunPanel";
import { ManualRunPanelErrorBoundary } from "./ManualRunPanelErrorBoundary";

interface WorkflowEditorProps {
  parentProjectId?: string | null;
  parentProjectName?: string | null;
}

export function WorkflowEditor({
  parentProjectId,
  parentProjectName,
}: WorkflowEditorProps = {}) {
  const { searchParams, updateSearchParams } = useURLState();
  const { currentNode, selectNode } = useNodeSelection();
  const workflowStore = useWorkflowStoreContext();
  const isNewWorkflow = useIsNewWorkflow();
  const { saveWorkflow } = useWorkflowActions();

  // UI state from store
  const isRunPanelOpen = useIsRunPanelOpen();
  const runPanelContext = useRunPanelContext();
  const { closeRunPanel, openRunPanel } = useUICommands();

  // Track if we're programmatically updating to avoid loops
  const isSyncingRef = useRef(false);
  // Track if this is the initial mount to prevent URL stripping on page load
  const isInitialMountRef = useRef(true);

  // Manage "runpanel" scope based on whether run panel is open
  // This allows ManualRunPanel's shortcuts to take priority when panel is open
  const { enableScope, disableScope } = useHotkeysContext();

  useEffect(() => {
    if (isRunPanelOpen) {
      enableScope(SHORTCUT_SCOPES.RUN_PANEL);
    } else {
      disableScope(SHORTCUT_SCOPES.RUN_PANEL);
    }
  }, [isRunPanelOpen, enableScope, disableScope]);

  // Sync URL parameter when run panel opens/closes or context changes (write to URL)
  useEffect(() => {
    if (isSyncingRef.current) return; // Don't update URL if we're syncing from URL

    const panelParam = searchParams.get("panel");

    if (isRunPanelOpen) {
      // Panel is open - only update URL if panel param is missing
      // Don't overwrite job/trigger params - let user selection changes persist
      const contextJobId = runPanelContext?.jobId;
      const contextTriggerId = runPanelContext?.triggerId;

      // Only update if panel param is missing (panel just opened)
      // Don't sync context changes back to URL - Effect 3 handles that
      const needsUpdate = panelParam !== "run";

      if (needsUpdate) {
        isSyncingRef.current = true;
        if (contextJobId) {
          updateSearchParams({
            panel: "run",
            job: contextJobId,
            trigger: null,
          });
        } else if (contextTriggerId) {
          updateSearchParams({
            panel: "run",
            trigger: contextTriggerId,
            job: null,
          });
        } else {
          updateSearchParams({ panel: "run" });
        }
        setTimeout(() => {
          isSyncingRef.current = false;
        }, 0);
      }
    } else if (
      !isRunPanelOpen &&
      panelParam === "run" &&
      !isSyncingRef.current &&
      !isInitialMountRef.current
    ) {
      // Panel closed - remove from URL (but keep job/trigger selection)
      // Don't remove if we're currently syncing or on initial mount
      isSyncingRef.current = true;
      updateSearchParams({ panel: null });
      setTimeout(() => {
        isSyncingRef.current = false;
      }, 0);
    }
  }, [isRunPanelOpen, runPanelContext, searchParams, updateSearchParams]);

  // Sync run panel state from URL parameter (read from URL)
  useEffect(() => {
    const panelParam = searchParams.get("panel");

    if (panelParam === "run" && !isRunPanelOpen) {
      // URL says panel should be open, but it's not - open it
      isSyncingRef.current = true;

      // Check URL params first (more reliable than currentNode on initial load)
      const jobParam = searchParams.get("job");
      const triggerParam = searchParams.get("trigger");

      if (jobParam) {
        openRunPanel({ jobId: jobParam });
      } else if (triggerParam) {
        openRunPanel({ triggerId: triggerParam });
      } else if (currentNode.type === "job" && currentNode.node) {
        // Fallback to currentNode if no URL params
        openRunPanel({ jobId: currentNode.node.id });
      } else if (currentNode.type === "trigger" && currentNode.node) {
        openRunPanel({ triggerId: currentNode.node.id });
      } else {
        // Last resort: open with first trigger if available
        const firstTrigger = workflow?.triggers?.[0];
        if (firstTrigger?.id) {
          openRunPanel({ triggerId: firstTrigger.id });
        }
      }

      // Reset sync flag after a tick
      setTimeout(() => {
        isSyncingRef.current = false;
        isInitialMountRef.current = false;
      }, 0);
    } else if (panelParam !== "run" && isRunPanelOpen) {
      // Panel is open but URL says it shouldn't be - close it
      isSyncingRef.current = true;
      closeRunPanel();

      setTimeout(() => {
        isSyncingRef.current = false;
        isInitialMountRef.current = false;
      }, 0);
    } else {
      // No sync needed - clear initial mount flag
      setTimeout(() => {
        isInitialMountRef.current = false;
      }, 0);
    }
  }, [
    searchParams,
    isRunPanelOpen,
    currentNode.type,
    currentNode.node,
    openRunPanel,
    closeRunPanel,
  ]);

  // Update run panel context when selected node changes (if panel is open)
  useEffect(() => {
    if (isRunPanelOpen && currentNode.node) {
      // Panel is open and a node is selected - update context if different
      if (currentNode.type === "job") {
        // Only update if context is different (prevents redundant updates after Effect 2)
        if (runPanelContext?.jobId !== currentNode.node.id) {
          openRunPanel({ jobId: currentNode.node.id });
        }
      } else if (currentNode.type === "trigger") {
        // Only update if context is different
        if (runPanelContext?.triggerId !== currentNode.node.id) {
          openRunPanel({ triggerId: currentNode.node.id });
        }
      } else if (currentNode.type === "edge") {
        // Keep panel open but show edge context (displays message to user)
        if (runPanelContext?.edgeId !== currentNode.node.id) {
          openRunPanel({ edgeId: currentNode.node.id });
        }
      }
    }
    // Don't close when currentNode.node is null - panel can stay open
    // with its initial context
  }, [
    currentNode.type,
    currentNode.node,
    isRunPanelOpen,
    runPanelContext,
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

  // Check if user can run workflows (handles permissions, snapshots, locks, etc.)
  const { canRun: canOpenRunPanel, tooltipMessage: runDisabledReason } =
    useCanRun();

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

  // Check if IDE should be open (panel=editor)
  const isIDEOpen = searchParams.get("panel") === "editor";
  const selectedJobId = searchParams.get("job");

  const handleCloseInspector = () => {
    selectNode(null);
  };

  // Show inspector panel if settings is open OR a node is selected
  const showInspector =
    searchParams.get("panel") === "settings" || Boolean(currentNode.node);

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
    updateSearchParams({ panel: null });
  };

  // Handle Ctrl/Cmd+E to open IDE for selected job
  useHotkeys(
    "ctrl+e,meta+e",
    event => {
      event.preventDefault();

      // Only work if a job is selected
      if (currentNode.type !== "job" || !currentNode.node) {
        return;
      }

      // Open IDE by setting panel=editor in URL
      updateSearchParams({ panel: "editor" });
    },
    {
      enabled: !isIDEOpen, // Disable when IDE is already open
      enableOnFormTags: true, // Allow in form fields, like Cmd+Enter
    },
    [currentNode, isIDEOpen, updateSearchParams]
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
            {!isRunPanelOpen && (
              <div
                id="inspector"
                className={`absolute top-0 right-0 transition-transform duration-300 ease-in-out z-10 ${
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
            )}

            {/* Run panel replaces inspector when open */}
            {isRunPanelOpen && runPanelContext && projectId && workflowId && (
              <div className="absolute inset-y-0 right-0 flex pointer-events-none z-20">
                <ManualRunPanelErrorBoundary onClose={closeRunPanel}>
                  <ManualRunPanel
                    workflow={workflow}
                    projectId={projectId}
                    workflowId={workflowId}
                    jobId={runPanelContext.jobId ?? null}
                    triggerId={runPanelContext.triggerId ?? null}
                    edgeId={runPanelContext.edgeId ?? null}
                    onClose={closeRunPanel}
                    saveWorkflow={saveWorkflow}
                  />
                </ManualRunPanelErrorBoundary>
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
