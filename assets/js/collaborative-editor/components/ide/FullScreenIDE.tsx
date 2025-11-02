import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useHotkeys, useHotkeysContext } from "react-hotkeys-hook";
import {
  type ImperativePanelHandle,
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from "react-resizable-panels";

import { cn } from "#/utils/cn";

import { useURLState } from "../../../react/lib/use-url-state";
import * as dataclipApi from "../../api/dataclips";
import { RENDER_MODES } from "../../constants/panel";
import {
  useCurrentRun,
  useRunActions,
  useRunStoreInstance,
} from "../../hooks/useRun";
import { useLiveViewActions } from "../../contexts/LiveViewActionsContext";
import { useProjectAdaptors } from "../../hooks/useAdaptors";
import {
  useCredentials,
  useCredentialsCommands,
} from "../../hooks/useCredentials";
import { useSession } from "../../hooks/useSession";
import { useRunRetry } from "../../hooks/useRunRetry";
import {
  useLatestSnapshotLockVersion,
  useProject,
  useProjectRepoConnection,
} from "../../hooks/useSessionContext";
import {
  useCanRun,
  useCanSave,
  useCurrentJob,
  useWorkflowActions,
  useWorkflowState,
} from "../../hooks/useWorkflow";
import { notifications } from "../../lib/notifications";
import { AdaptorSelectionModal } from "../AdaptorSelectionModal";
import { CollaborativeMonaco } from "../CollaborativeMonaco";
import { ConfigureAdaptorModal } from "../ConfigureAdaptorModal";
import { ManualRunPanel } from "../ManualRunPanel";
import { ManualRunPanelErrorBoundary } from "../ManualRunPanelErrorBoundary";
import { RunViewerPanel } from "../run-viewer/RunViewerPanel";
import { RunViewerErrorBoundary } from "../run-viewer/RunViewerErrorBoundary";
import { SandboxIndicatorBanner } from "../SandboxIndicatorBanner";
import { Tabs } from "../Tabs";

import { IDEHeader } from "./IDEHeader";
import { PanelToggleButton } from "./PanelToggleButton";
import { useUICommands } from "#/collaborative-editor/hooks/useUI";

/**
 * Resolves an adaptor specifier into its package name and version
 * @param adaptor - Full NPM package string like "@openfn/language-common@1.4.3"
 * @returns Tuple of package name and version, or null if parsing fails
 */
function resolveAdaptor(adaptor: string): {
  package: string | null;
  version: string | null;
} {
  const regex = /^(@[^@]+)@(.+)$/;
  const match = adaptor.match(regex);
  if (!match) return { package: null, version: null };
  const [, packageName, version] = match;

  return {
    package: packageName || null,
    version: version || null,
  };
}

// Stable selector functions to prevent useEffect re-runs
const selectProvider = (state: any) => state.provider;
const selectAwareness = (state: any) => state.awareness;

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
  // Support both 'run' (collaborative) and 'a' (classical) parameter for run ID
  const runIdFromURL = searchParams.get("run") || searchParams.get("a");
  const stepIdFromURL = searchParams.get("step");
  const { selectJob, saveWorkflow } = useWorkflowActions();
  const { selectStep } = useRunActions();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  // Get provider and awareness with stable selector functions
  // Using stable functions defined outside component to prevent useEffect re-runs
  const awareness = useSession(selectAwareness);
  const provider = useSession(selectProvider);
  const { canSave, tooltipMessage } = useCanSave();
  const runStore = useRunStoreInstance();
  // Get UI commands from store
  const repoConnection = useProjectRepoConnection();
  const { openGitHubSyncModal } = useUICommands();
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

  // Follow run state for right panel
  const [followRunId, setFollowRunId] = useState<string | null>(null);

  // Track selected dataclip for retry functionality
  const [selectedDataclip, setSelectedDataclip] = useState<any>(null);

  // Handler for run submission - auto-expands right panel and updates URL
  const handleRunSubmitted = useCallback(
    (runId: string) => {
      setFollowRunId(runId);
      updateSearchParams({ run: runId });

      // Auto-expand right panel if collapsed
      if (rightPanelRef.current?.isCollapsed()) {
        rightPanelRef.current.expand();
      }
    },
    [updateSearchParams]
  );

  // Determine run context (job from URL)
  const runContext = jobIdFromURL
    ? { type: "job" as const, id: jobIdFromURL }
    : {
        type: "trigger" as const,
        id: workflow?.triggers[0]?.id || "",
      };

  // Get current run from RunStore for retry detection
  const currentRun = useCurrentRun();

  // Get step for current job from followed run
  const followedRunStep = useMemo(() => {
    if (!currentRun || !currentRun.steps || !jobIdFromURL) return null;
    return currentRun.steps.find(s => s.job_id === jobIdFromURL) || null;
  }, [currentRun, jobIdFromURL]);

  // Auto-fetch and select dataclip when following a run
  // This enables retry functionality in the IDE
  // Fetch once when input_dataclip_id becomes available
  useEffect(() => {
    const inputDataclipId = followedRunStep?.input_dataclip_id;

    // Early returns: conditions where we shouldn't fetch
    if (!inputDataclipId || !jobIdFromURL || !projectId) {
      return;
    }

    // Skip if we already have the correct dataclip
    if (selectedDataclip?.id === inputDataclipId) {
      return;
    }

    // Get run ID from URL (support both 'run' and 'a' parameters)
    const runId = searchParams.get("run") || searchParams.get("a");
    if (!runId) {
      return;
    }

    // Fetch the dataclip for this run
    const fetchDataclip = async () => {
      try {
        const response = await dataclipApi.getRunDataclip(
          projectId,
          runId,
          jobIdFromURL
        );

        if (response.dataclip) {
          setSelectedDataclip(response.dataclip);
        }
      } catch (error) {
        console.error("Failed to fetch dataclip for retry:", error);
      }
    };

    void fetchDataclip();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    followedRunStep?.input_dataclip_id,
    jobIdFromURL,
    projectId,
    searchParams,
  ]);

  // Use run/retry hook for all run logic
  const {
    handleRun,
    handleRetry,
    isSubmitting,
    isRetryable,
    runIsProcessing,
    canRun: canRunFromHook,
  } = useRunRetry({
    projectId: projectId || "",
    workflowId: workflowId || "",
    runContext,
    selectedTab: selectedDataclip ? "existing" : "empty",
    selectedDataclip,
    customBody: "{}",
    canRunWorkflow: canRunSnapshot,
    workflowRunTooltipMessage: runTooltipMessage,
    saveWorkflow,
    onRunSubmitted: handleRunSubmitted,
    edgeId: null,
    workflowEdges: workflow?.edges || [],
  });

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

  // Adaptor configuration modal state
  const [isConfigureModalOpen, setIsConfigureModalOpen] = useState(false);
  const [isAdaptorPickerOpen, setIsAdaptorPickerOpen] = useState(false);
  const [isCredentialModalOpen, setIsCredentialModalOpen] = useState(false);

  // Adaptor and credential data
  const { projectCredentials, keychainCredentials } = useCredentials();
  const { requestCredentials } = useCredentialsCommands();
  const { projectAdaptors, allAdaptors } = useProjectAdaptors();
  const { pushEvent, handleEvent } = useLiveViewActions();
  const { updateJob } = useWorkflowActions();

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

  // Connect to run channel when URL has run parameter
  // This keeps the connection alive independently of panel collapse state
  useEffect(() => {
    if (!runIdFromURL || !provider) {
      runStore._disconnectFromRun();
      return;
    }

    const cleanup = runStore._connectToRun(provider, runIdFromURL);
    return cleanup;
  }, [runIdFromURL, provider, runStore]);

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
      selectStep(stepIdFromURL);
    }
  }, [stepIdFromURL, runIdFromURL, selectStep]);

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

  // Adaptor modal handlers
  const handleOpenAdaptorPicker = useCallback(() => {
    setIsConfigureModalOpen(false);
    setIsAdaptorPickerOpen(true);
  }, []);

  const handleOpenCredentialModal = useCallback(
    (adaptorName: string) => {
      setIsConfigureModalOpen(false);
      setIsCredentialModalOpen(true);
      pushEvent("open_credential_modal", { schema: adaptorName });
    },
    [pushEvent]
  );

  const handleAdaptorSelect = useCallback(
    (adaptorName: string) => {
      if (!currentJob) return;

      // Extract package name and set version to "latest"
      const packageMatch = adaptorName.match(/(.+?)(@|$)/);
      const newPackage = packageMatch ? packageMatch[1] : adaptorName;
      const fullAdaptor = `${newPackage}@latest`;

      // Update job in Y.Doc
      updateJob(currentJob.id, { adaptor: fullAdaptor });

      // Close adaptor picker and reopen configure modal
      setIsAdaptorPickerOpen(false);
      setIsConfigureModalOpen(true);
    },
    [currentJob, updateJob]
  );

  // Handler for adaptor changes - immediately syncs to Y.Doc
  const handleAdaptorChange = useCallback(
    (adaptorPackage: string) => {
      if (!currentJob) return;

      // Get current version from job
      const { version: currentVersion } = resolveAdaptor(
        currentJob.adaptor || '@openfn/language-common@latest'
      );

      // Build new adaptor string with current version
      const newAdaptor = `${adaptorPackage}@${currentVersion || 'latest'}`;

      // Persist to Y.Doc
      updateJob(currentJob.id, { adaptor: newAdaptor });
    },
    [currentJob, updateJob]
  );

  // Handler for version changes - immediately syncs to Y.Doc
  const handleVersionChange = useCallback(
    (version: string) => {
      if (!currentJob) return;

      // Get current adaptor package from job
      const { package: adaptorPackage } = resolveAdaptor(
        currentJob.adaptor || '@openfn/language-common@latest'
      );

      // Build new adaptor string with new version
      const newAdaptor = `${adaptorPackage}@${version}`;

      // Persist to Y.Doc
      updateJob(currentJob.id, { adaptor: newAdaptor });
    },
    [currentJob, updateJob]
  );

  // Handler for credential changes - immediately syncs to Y.Doc
  const handleCredentialChange = useCallback(
    (credentialId: string | null) => {
      if (!currentJob) return;

      // Build the Y.Doc updates
      const jobUpdates: {
        project_credential_id: string | null;
        keychain_credential_id: string | null;
      } = {
        project_credential_id: null,
        keychain_credential_id: null,
      };

      // Update credential if selected
      if (credentialId) {
        const isProjectCredential = projectCredentials.some(
          c => c.project_credential_id === credentialId
        );
        const isKeychainCredential = keychainCredentials.some(
          c => c.id === credentialId
        );

        if (isProjectCredential) {
          jobUpdates.project_credential_id = credentialId;
        } else if (isKeychainCredential) {
          jobUpdates.keychain_credential_id = credentialId;
        }
      }

      // Persist to Y.Doc
      updateJob(currentJob.id, jobUpdates);
    },
    [currentJob, projectCredentials, keychainCredentials, updateJob]
  );

  // Listen for credential modal close event
  useEffect(() => {
    const handleModalClose = () => {
      setIsCredentialModalOpen(false);
      setTimeout(() => {
        setIsConfigureModalOpen(true);
      }, 200);
      setTimeout(() => {
        pushEvent("close_credential_modal_complete", {});
      }, 500);
    };

    const element = document.getElementById("collaborative-editor-react");
    element?.addEventListener("close_credential_modal", handleModalClose);

    return () => {
      element?.removeEventListener("close_credential_modal", handleModalClose);
    };
  }, [pushEvent]);

  // Listen for credential saved event
  useEffect(() => {
    const cleanup = handleEvent("credential_saved", (payload: any) => {
      if (!currentJob) return;

      setIsCredentialModalOpen(false);

      const { credential, is_project_credential } = payload;
      const credentialId = is_project_credential
        ? credential.project_credential_id
        : credential.id;

      // Update job with new credential
      updateJob(currentJob.id, {
        project_credential_id: is_project_credential ? credentialId : null,
        keychain_credential_id: is_project_credential ? null : credentialId,
      });

      // Reload credentials
      void requestCredentials();

      // Reopen configure modal
      setTimeout(() => {
        setIsConfigureModalOpen(true);
      }, 200);
    });

    return cleanup;
  }, [handleEvent, currentJob, updateJob, requestCredentials]);

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
    'mod+enter',
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
        jobId={currentJob.id}
        jobName={currentJob.name}
        jobAdaptor={currentJob.adaptor || undefined}
        jobCredentialId={
          currentJob.project_credential_id ||
          currentJob.keychain_credential_id ||
          null
        }
        snapshotVersion={snapshotVersion}
        latestSnapshotVersion={latestSnapshotLockVersion}
        workflowId={workflowId}
        projectId={projectId}
        onClose={onClose}
        onSave={handleSave}
        onRun={handleRun}
        onRetry={handleRetry}
        isRetryable={isRetryable}
        canRun={
          canRunSnapshot && canRunFromHook && !isSubmitting && !runIsProcessing
        }
        isRunning={isSubmitting || runIsProcessing}
        canSave={canSave}
        saveTooltip={tooltipMessage}
        runTooltip={runTooltipMessage}
        onEditAdaptor={() => setIsConfigureModalOpen(true)}
        onChangeAdaptor={handleOpenAdaptorPicker}
        repoConnection={repoConnection}
        openGitHubSyncModal={openGitHubSyncModal}
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
            minSize={25}
            collapsible
            collapsedSize={2}
            onCollapse={() => setIsLeftCollapsed(true)}
            onExpand={() => setIsLeftCollapsed(false)}
            className="bg-slate-100 border-r border-gray-200"
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
                      <PanelToggleButton
                        onClick={toggleLeftPanel}
                        disabled={openPanelCount === 1}
                        ariaLabel="Collapse left panel"
                      />
                    </>
                  ) : (
                    <button
                      onClick={toggleLeftPanel}
                      className="ml-2 text-xs font-medium text-gray-400
                        uppercase tracking-wide hover:text-gray-600
                        transition-colors cursor-pointer"
                    >
                      Input
                    </button>
                  )}
                </div>
              </div>

              {/* Panel content */}
              {workflow && projectId && workflowId && (
                <div
                  className={cn(
                    "flex-1 overflow-hidden bg-white",
                    isLeftCollapsed && "hidden"
                  )}
                >
                  <ManualRunPanelErrorBoundary
                    onClose={handleCollapseLeftPanel}
                  >
                    <ManualRunPanel
                      workflow={workflow}
                      projectId={projectId}
                      workflowId={workflowId}
                      jobId={jobIdFromURL ?? null}
                      triggerId={null}
                      onClose={handleCollapseLeftPanel}
                      renderMode={RENDER_MODES.EMBEDDED}
                      saveWorkflow={saveWorkflow}
                      onRunSubmitted={handleRunSubmitted}
                    />
                  </ManualRunPanelErrorBoundary>
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
            minSize={25}
            collapsible
            collapsedSize={2}
            onCollapse={() => setIsCenterCollapsed(true)}
            onExpand={() => setIsCenterCollapsed(false)}
            className="bg-slate-100"
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
                      <PanelToggleButton
                        onClick={toggleCenterPanel}
                        disabled={openPanelCount === 1}
                        ariaLabel="Collapse code panel"
                      />
                    </>
                  ) : (
                    <button
                      onClick={toggleCenterPanel}
                      className="ml-2 text-xs font-medium text-gray-400
                        uppercase tracking-wide hover:text-gray-600
                        transition-colors cursor-pointer"
                    >
                      Code
                    </button>
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
            minSize={25}
            collapsible
            collapsedSize={2}
            onCollapse={() => setIsRightCollapsed(true)}
            onExpand={() => setIsRightCollapsed(false)}
            className="bg-slate-100 bg-gray-50 border-l border-gray-200"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading with tabs */}
              <div
                className={`shrink-0 transition-transform ${
                  isRightCollapsed ? "rotate-90" : ""
                }`}
              >
                <div className="flex items-center justify-between px-3 py-1">
                  {!isRightCollapsed ? (
                    <>
                      {/* Tabs as header content */}
                      <div className="flex-1">
                        <Tabs
                          value={activeRightTab}
                          onChange={setActiveRightTab}
                          variant="underline"
                          options={[
                            { value: "run", label: "Run" },
                            { value: "log", label: "Log" },
                            { value: "input", label: "Input" },
                            { value: "output", label: "Output" },
                          ]}
                        />
                      </div>
                      {/* Collapse button */}
                      <PanelToggleButton
                        onClick={toggleRightPanel}
                        disabled={openPanelCount === 1}
                        ariaLabel="Collapse right panel"
                      />
                    </>
                  ) : (
                    <button
                      onClick={toggleRightPanel}
                      className="ml-2 text-xs font-medium text-gray-400
                        uppercase tracking-wide hover:text-gray-600
                        transition-colors cursor-pointer"
                    >
                      Output
                    </button>
                  )}
                </div>
              </div>

              {/* Panel content */}
              {!isRightCollapsed && (
                <div className="flex-1 overflow-hidden bg-white">
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

      {/* Adaptor Configuration Modals */}
      {currentJob && (
        <>
          <ConfigureAdaptorModal
            isOpen={isConfigureModalOpen}
            onClose={() => setIsConfigureModalOpen(false)}
            onAdaptorChange={handleAdaptorChange}
            onVersionChange={handleVersionChange}
            onCredentialChange={handleCredentialChange}
            onOpenAdaptorPicker={handleOpenAdaptorPicker}
            onOpenCredentialModal={handleOpenCredentialModal}
            currentAdaptor={
              resolveAdaptor(
                currentJob.adaptor || "@openfn/language-common@latest"
              ).package || "@openfn/language-common"
            }
            currentVersion={
              resolveAdaptor(
                currentJob.adaptor || "@openfn/language-common@latest"
              ).version || "latest"
            }
            currentCredentialId={
              currentJob.project_credential_id ||
              currentJob.keychain_credential_id ||
              null
            }
            allAdaptors={allAdaptors}
          />

          <AdaptorSelectionModal
            isOpen={isAdaptorPickerOpen}
            onClose={() => setIsAdaptorPickerOpen(false)}
            onSelect={handleAdaptorSelect}
            projectAdaptors={projectAdaptors}
          />
        </>
      )}
    </div>
  );
}
