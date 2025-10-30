import { useEffect, useRef, useState } from "react";
import { useHotkeys, useHotkeysContext } from "react-hotkeys-hook";
import {
  type ImperativePanelHandle,
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from "react-resizable-panels";

import _logger from "#/utils/logger";

import { useURLState } from "../../../react/lib/use-url-state";
import { useRunStoreInstance } from "../../hooks/useRun";
import { useSession } from "../../hooks/useSession";
import {
  useLatestSnapshotLockVersion,
  useProject,
} from "../../hooks/useSessionContext";
import {
  useCanRun,
  useCanSave,
  useCurrentJob,
  useWorkflowActions,
  useWorkflowState,
} from "../../hooks/useWorkflow";
import { notifications } from "../../lib/notifications";
import { CollaborativeMonaco } from "../CollaborativeMonaco";
import { ManualRunPanel } from "../ManualRunPanel";
import { RunViewerErrorBoundary } from "../run-viewer/RunViewerErrorBoundary";
import { RunViewerPanel } from "../run-viewer/RunViewerPanel";
import { SandboxIndicatorBanner } from "../SandboxIndicatorBanner";
import { Tabs } from "../Tabs";

import { IDEHeader } from "./IDEHeader";

const logger = _logger.ns("FullScreenIDE").seal();

interface FullScreenIDEProps {
  jobId?: string;
  onClose: () => void;
  parentProjectId?: string | null | undefined;
  parentProjectName?: string | null | undefined;
}

/**
 * Full-Screen IDE component
 *
 * Provides a full-screen workspace for editing job code with:
 * - Header with job name and action buttons
 * - 3 resizable, collapsible panels (left, center, right)
 * - CollaborativeMonaco editor in center panel
 * - Placeholder content in left and right panels
 * - Keyboard shortcut (Escape to close)
 *
 * Panel layout persists to localStorage automatically.
 */
export function FullScreenIDE({
  onClose,
  parentProjectId,
  parentProjectName,
}: FullScreenIDEProps) {
  const { searchParams, updateSearchParams } = useURLState();
  const jobIdFromURL = searchParams.get("job");
  const runIdFromURL = searchParams.get("run");
  const stepIdFromURL = searchParams.get("step");
  const { selectJob, saveWorkflow } = useWorkflowActions();
  const runStore = useRunStoreInstance();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { awareness } = useSession();
  const { canSave, tooltipMessage } = useCanSave();
  const { canRun: canRunSnapshot, tooltipMessage: runTooltipMessage } =
    useCanRun();

  // Get version information for header
  const snapshotVersion = useWorkflowState(
    state => state.workflow?.lock_version
  );
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  // Construct workflow object from store state for ManualRunPanel
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

  // Get project ID and workflow ID for ManualRunPanel
  const project = useProject();
  const projectId = project?.id;
  const workflowId = useWorkflowState(state => state.workflow?.id);

  const leftPanelRef = useRef<ImperativePanelHandle>(null);
  const centerPanelRef = useRef<ImperativePanelHandle>(null);
  const rightPanelRef = useRef<ImperativePanelHandle>(null);

  const [isLeftCollapsed, setIsLeftCollapsed] = useState(false);
  const [isCenterCollapsed, setIsCenterCollapsed] = useState(false);
  const [isRightCollapsed, setIsRightCollapsed] = useState(true);

  // Run state from ManualRunPanel
  const [canRunWorkflow, setCanRunWorkflow] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const [runHandler, setRunHandler] = useState<(() => void) | null>(null);

  // Follow run state for right panel
  const [followRunId, setFollowRunId] = useState<string | null>(null);

  // Right panel tab state
  type RightPanelTab = "run" | "log" | "input" | "output";
  const [activeRightTab, setActiveRightTab] = useState<RightPanelTab>("run");

  // Persist right panel tab to localStorage
  useEffect(() => {
    if (activeRightTab) {
      localStorage.setItem("lightning.ide-run-viewer-tab", activeRightTab);
    }
  }, [activeRightTab]);

  // Restore tab from localStorage on mount
  useEffect(() => {
    const savedTab = localStorage.getItem("lightning.ide-run-viewer-tab");
    if (savedTab && ["run", "log", "input", "output"].includes(savedTab)) {
      setActiveRightTab(savedTab as RightPanelTab);
    }
  }, []);

  const { enableScope, disableScope } = useHotkeysContext();

  // Enable/disable ide scope based on whether IDE is open
  useEffect(() => {
    enableScope("ide");
    return () => {
      disableScope("ide");
    };
  }, [enableScope, disableScope]);

  // Sync URL job ID to workflow store selection
  useEffect(() => {
    if (jobIdFromURL) {
      selectJob(jobIdFromURL);
    }
  }, [jobIdFromURL, selectJob]);

  // Sync URL run_id to followRunId
  useEffect(() => {
    if (runIdFromURL && runIdFromURL !== followRunId) {
      setFollowRunId(runIdFromURL);

      // Auto-expand right panel for deep links
      if (rightPanelRef.current?.isCollapsed()) {
        rightPanelRef.current.expand();
      }
    }
  }, [runIdFromURL, followRunId]);

  // Sync stepIdFromURL to RunStore
  useEffect(() => {
    if (stepIdFromURL && runIdFromURL) {
      runStore.selectStep(stepIdFromURL);
    }
  }, [stepIdFromURL, runIdFromURL, runStore]);

  // Handler for Save button
  const handleSave = () => {
    // Centralized validation - both button and keyboard shortcut use this
    if (!canSave) {
      // Show toast with the reason why save is disabled
      notifications.alert({
        title: "Cannot save",
        description: tooltipMessage,
      });
      return;
    }
    void saveWorkflow();
  };

  // Handler for collapsing left panel (no close button in IDE context)
  const handleCollapseLeftPanel = () => {
    leftPanelRef.current?.collapse();
  };

  // Handler for run submission - auto-expands right panel and updates URL
  const handleRunSubmitted = (runId: string) => {
    setFollowRunId(runId);
    updateSearchParams({ run: runId });

    // Auto-expand right panel if collapsed
    if (rightPanelRef.current?.isCollapsed()) {
      rightPanelRef.current.expand();
    }
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

  // Handler for Run button in header
  const handleRunClick = () => {
    // Centralized validation - both button and keyboard shortcut use this

    // Check snapshot/permission restrictions first (these have clear messages)
    if (!canRunSnapshot) {
      notifications.alert({
        title: "Cannot run",
        description: runTooltipMessage,
      });
      return;
    }

    // Check runtime conditions (no toast needed - these are transient states)
    if (!canRunWorkflow || isRunning || !runHandler) {
      return;
    }

    runHandler();
  };

  // Handle Escape key to close the IDE
  // Two-step behavior: first Escape removes focus from Monaco, second closes IDE
  useHotkeys(
    "escape",
    event => {
      // Check if Monaco editor has focus
      const activeElement = document.activeElement;
      const isMonacoFocused = activeElement?.closest(".monaco-editor");

      if (isMonacoFocused) {
        // First Escape: blur Monaco editor to remove focus
        (activeElement as HTMLElement).blur();
        event.preventDefault();
      } else {
        // Second Escape: close IDE
        onClose();
      }
    },
    {
      enabled: true,
      scopes: ["ide"],
      enableOnFormTags: true, // Allow Escape even in Monaco editor
    },
    [onClose]
  );

  // Handle Cmd/Ctrl+Enter to trigger workflow run
  // No scope restriction to ensure it works even when Monaco has focus
  useHotkeys(
    "mod+enter",
    event => {
      event.preventDefault();
      event.stopPropagation();

      // Use centralized handler with validation
      handleRunClick();
    },
    {
      enabled: true,
      enableOnFormTags: true, // Allow in Monaco editor
      preventDefault: true, // Prevent Monaco's default behavior
      enableOnContentEditable: true, // Work in Monaco's contentEditable
    },
    [handleRunClick]
  );

  // Loading state: Wait for Y.Text and awareness to be ready
  if (!currentJob || !currentJobYText || !awareness) {
    return (
      <div
        className="fixed inset-0 z-50 bg-white flex
          items-center justify-center"
      >
        <div className="text-center">
          <div
            className="hero-arrow-path size-8 animate-spin
            text-blue-500 mx-auto"
            aria-hidden="true"
          />
          <p className="text-gray-500 mt-2">Loading editor...</p>
        </div>
      </div>
    );
  }

  // Check how many panels are open
  const openPanelCount =
    (!isLeftCollapsed ? 1 : 0) +
    (!isCenterCollapsed ? 1 : 0) +
    (!isRightCollapsed ? 1 : 0);

  // Toggle handlers for panel collapse/expand
  const toggleLeftPanel = () => {
    if (!isLeftCollapsed && openPanelCount === 1) return;
    if (isLeftCollapsed) {
      leftPanelRef.current?.expand();
    } else {
      leftPanelRef.current?.collapse();
    }
  };

  const toggleCenterPanel = () => {
    if (!isCenterCollapsed && openPanelCount === 1) return;
    if (isCenterCollapsed) {
      centerPanelRef.current?.expand();
    } else {
      centerPanelRef.current?.collapse();
    }
  };

  const toggleRightPanel = () => {
    if (!isRightCollapsed && openPanelCount === 1) return;
    if (isRightCollapsed) {
      rightPanelRef.current?.expand();
    } else {
      rightPanelRef.current?.collapse();
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-white flex flex-col">
      {/* Header with Run, Save, Close buttons */}
      <IDEHeader
        jobName={currentJob.name}
        snapshotVersion={snapshotVersion}
        latestSnapshotVersion={latestSnapshotLockVersion}
        workflowId={workflowId}
        onClose={onClose}
        onSave={handleSave}
        onRun={handleRunClick}
        canRun={canRunSnapshot && canRunWorkflow && !isRunning}
        isRunning={isRunning}
        canSave={canSave}
        saveTooltip={tooltipMessage}
        runTooltip={runTooltipMessage}
      />
      <SandboxIndicatorBanner
        parentProjectId={parentProjectId}
        parentProjectName={parentProjectName}
        projectName={project?.name}
        position="relative"
      />

      {/* 3-panel layout */}
      <div className="flex-1 overflow-hidden">
        <PanelGroup
          direction="horizontal"
          autoSaveId="lightning.ide-layout"
          className="h-full"
        >
          {/* Left Panel - ManualRunPanel */}
          <Panel
            ref={leftPanelRef}
            defaultSize={25}
            minSize={15}
            collapsible
            collapsedSize={2}
            onCollapse={() => setIsLeftCollapsed(true)}
            onExpand={() => setIsLeftCollapsed(false)}
            className="bg-gray-50 border-r border-gray-200"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading */}
              <div
                className={`shrink-0 transition-transform ${
                  isLeftCollapsed ? "rotate-90" : ""
                }`}
              >
                <div className="flex items-center justify-between px-3 py-1">
                  {!isLeftCollapsed ? (
                    <>
                      <div
                        className="text-xs font-medium text-gray-400
                        uppercase tracking-wide"
                      >
                        Input
                      </div>
                      <button
                        onClick={toggleLeftPanel}
                        disabled={openPanelCount === 1}
                        className="text-slate-500 hover:text-slate-600
                          hover:bg-slate-400 rounded-full p-1
                          disabled:opacity-30 disabled:cursor-not-allowed
                          transition-colors"
                        aria-label="Collapse left panel"
                      >
                        <span
                          className="hero-minus-circle w-5 h-5"
                          aria-hidden="true"
                        />
                      </button>
                    </>
                  ) : (
                    <>
                      <button
                        onClick={toggleLeftPanel}
                        className="text-xs font-medium text-gray-400
                          uppercase tracking-wide hover:text-gray-600
                          transition-colors cursor-pointer"
                      >
                        Input
                      </button>
                      <button
                        onClick={toggleLeftPanel}
                        className="text-slate-500 hover:text-slate-600
                          hover:bg-slate-400 rounded-full p-1
                          transition-colors"
                        aria-label="Expand left panel"
                      >
                        <span
                          className="hero-plus-circle w-5 h-5"
                          aria-hidden="true"
                        />
                      </button>
                    </>
                  )}
                </div>
              </div>

              {/* Panel content */}
              {!isLeftCollapsed && workflow && projectId && workflowId && (
                <div className="flex-1 overflow-hidden">
                  <ManualRunPanel
                    workflow={workflow}
                    projectId={projectId}
                    workflowId={workflowId}
                    jobId={jobIdFromURL ?? null}
                    triggerId={null}
                    onClose={handleCollapseLeftPanel}
                    renderMode="embedded"
                    onRunStateChange={handleRunStateChange}
                    saveWorkflow={saveWorkflow}
                    onRunSubmitted={handleRunSubmitted}
                  />
                </div>
              )}
            </div>
          </Panel>

          {/* Resize Handle */}
          <PanelResizeHandle
            className="w-1 bg-gray-200 hover:bg-blue-400
            transition-colors cursor-col-resize"
          />

          {/* Center Panel - CollaborativeMonaco Editor */}
          <Panel
            ref={centerPanelRef}
            defaultSize={100}
            minSize={15}
            collapsible
            collapsedSize={2}
            onCollapse={() => setIsCenterCollapsed(true)}
            onExpand={() => setIsCenterCollapsed(false)}
            className="bg-white"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading */}
              <div
                className={`shrink-0 border-b border-gray-100 transition-transform ${
                  isCenterCollapsed ? "rotate-90" : ""
                }`}
              >
                <div className="flex items-center justify-between px-3 py-1">
                  {!isCenterCollapsed ? (
                    <>
                      <div
                        className="text-xs font-medium text-gray-400
                        uppercase tracking-wide"
                      >
                        Code
                      </div>
                      <button
                        onClick={toggleCenterPanel}
                        disabled={openPanelCount === 1}
                        className="text-slate-500 hover:text-slate-600
                          hover:bg-slate-400 rounded-full p-1
                          disabled:opacity-30 disabled:cursor-not-allowed
                          transition-colors"
                        aria-label="Collapse code panel"
                      >
                        <span
                          className="hero-minus-circle w-5 h-5"
                          aria-hidden="true"
                        />
                      </button>
                    </>
                  ) : (
                    <>
                      <button
                        onClick={toggleCenterPanel}
                        className="text-xs font-medium text-gray-400
                          uppercase tracking-wide hover:text-gray-600
                          transition-colors cursor-pointer"
                      >
                        Code
                      </button>
                      <button
                        onClick={toggleCenterPanel}
                        className="text-slate-500 hover:text-slate-600
                          hover:bg-slate-400 rounded-full p-1
                          transition-colors"
                        aria-label="Expand code panel"
                      >
                        <span
                          className="hero-plus-circle w-5 h-5"
                          aria-hidden="true"
                        />
                      </button>
                    </>
                  )}
                </div>
              </div>

              {/* Editor */}
              {!isCenterCollapsed && (
                <div className="flex-1 overflow-hidden">
                  <CollaborativeMonaco
                    ytext={currentJobYText}
                    awareness={awareness}
                    adaptor={currentJob.adaptor || "common"}
                    disabled={!canSave}
                    className="h-full w-full"
                    options={{
                      automaticLayout: true,
                      minimap: { enabled: true },
                      lineNumbers: "on",
                      wordWrap: "on",
                    }}
                  />
                </div>
              )}
            </div>
          </Panel>

          {/* Resize Handle */}
          <PanelResizeHandle
            className="w-1 bg-gray-200 hover:bg-blue-400
            transition-colors cursor-col-resize"
          />

          {/* Right Panel - Placeholder for Run / Logs / Step I/O */}
          <Panel
            ref={rightPanelRef}
            defaultSize={1}
            minSize={15}
            collapsible
            collapsedSize={2}
            onCollapse={() => setIsRightCollapsed(true)}
            onExpand={() => setIsRightCollapsed(false)}
            className="bg-gray-50 border-l border-gray-200"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading with tabs */}
              <div
                className={`shrink-0 bg-slate-50 transition-transform ${
                  isRightCollapsed ? "rotate-90" : ""
                }`}
              >
                <div className="flex items-center justify-between px-2">
                  {!isRightCollapsed ? (
                    <>
                      {/* Tabs as header content */}
                      <div className="flex-1">
                        <Tabs
                          value={activeRightTab}
                          onChange={setActiveRightTab}
                          options={[
                            { value: "run", label: "Run" },
                            { value: "log", label: "Log" },
                            { value: "input", label: "Input" },
                            { value: "output", label: "Output" },
                          ]}
                        />
                      </div>
                      {/* Collapse button */}
                      <button
                        onClick={toggleRightPanel}
                        disabled={openPanelCount === 1}
                        className="text-slate-500 hover:text-slate-600
                          hover:bg-slate-400 rounded-full p-1
                          disabled:opacity-30 disabled:cursor-not-allowed
                          transition-colors ml-2"
                        aria-label="Collapse right panel"
                      >
                        <span
                          className="hero-minus-circle w-5 h-5"
                          aria-hidden="true"
                        />
                      </button>
                    </>
                  ) : (
                    <>
                      {/* Collapsed state - clickable label */}
                      <button
                        onClick={toggleRightPanel}
                        className="text-xs font-medium text-gray-400
                          uppercase tracking-wide hover:text-gray-600
                          transition-colors cursor-pointer"
                      >
                        Output
                      </button>
                      {/* Expand icon */}
                      <button
                        onClick={toggleRightPanel}
                        className="text-slate-500 hover:text-slate-600
                          hover:bg-slate-400 rounded-full p-1
                          transition-colors"
                        aria-label="Expand right panel"
                      >
                        <span
                          className="hero-plus-circle w-5 h-5"
                          aria-hidden="true"
                        />
                      </button>
                    </>
                  )}
                </div>
              </div>

              {/* Panel content */}
              {!isRightCollapsed && (
                <div className="flex-1 overflow-hidden">
                  <RunViewerErrorBoundary>
                    <RunViewerPanel
                      followRunId={followRunId}
                      onClearFollowRun={() => setFollowRunId(null)}
                      activeTab={activeRightTab}
                      onTabChange={setActiveRightTab}
                    />
                  </RunViewerErrorBoundary>
                </div>
              )}
            </div>
          </Panel>
        </PanelGroup>
      </div>
    </div>
  );
}
