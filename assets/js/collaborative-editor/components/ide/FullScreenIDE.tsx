import { useCallback, useEffect, useRef, useState } from 'react';
import { useHotkeys, useHotkeysContext } from 'react-hotkeys-hook';
import {
  type ImperativePanelHandle,
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from 'react-resizable-panels';

import { cn } from '#/utils/cn';
import _logger from '#/utils/logger';

import { useURLState } from '../../../react/lib/use-url-state';
import { useRunStoreInstance } from '../../hooks/useRun';
import { useLiveViewActions } from '../../contexts/LiveViewActionsContext';
import { useProjectAdaptors } from '../../hooks/useAdaptors';
import {
  useCredentials,
  useCredentialsCommands,
} from '../../hooks/useCredentials';
import { useRunStoreInstance } from '../../hooks/useRun';
import { useSession } from '../../hooks/useSession';
import {
  useLatestSnapshotLockVersion,
  useProject,
  useProjectRepoConnection,
} from '../../hooks/useSessionContext';
import {
  useCanRun,
  useCanSave,
  useCurrentJob,
  useWorkflowActions,
  useWorkflowState,
} from '../../hooks/useWorkflow';
import { notifications } from '../../lib/notifications';
import { AdaptorSelectionModal } from '../AdaptorSelectionModal';
import { CollaborativeMonaco } from '../CollaborativeMonaco';
import { ConfigureAdaptorModal } from '../ConfigureAdaptorModal';
import { ManualRunPanel } from '../ManualRunPanel';
import { RunViewerPanel } from '../run-viewer/RunViewerPanel';
import { RunViewerErrorBoundary } from '../run-viewer/RunViewerErrorBoundary';
import { SandboxIndicatorBanner } from '../SandboxIndicatorBanner';
import { Tabs } from '../Tabs';

import { IDEHeader } from './IDEHeader';
import { PanelToggleButton } from './PanelToggleButton';
import { useUICommands } from '#/collaborative-editor/hooks/useUI';

const logger = _logger.ns('FullScreenIDE').seal();

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
  const jobIdFromURL = searchParams.get('job');
  const runIdFromURL = searchParams.get('run');
  const stepIdFromURL = searchParams.get('step');
  const { selectJob, saveWorkflow } = useWorkflowActions();
  const runStore = useRunStoreInstance();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { awareness } = useSession();
  const { canSave, tooltipMessage } = useCanSave();
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

  // Run state from ManualRunPanel
  const [canRunWorkflow, setCanRunWorkflow] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const [runHandler, setRunHandler] = useState<(() => void) | null>(null);
  const [retryHandler, setRetryHandler] = useState<(() => void) | null>(null);
  const [isRetryable, setIsRetryable] = useState(false);
  const [runIsProcessing, setRunIsProcessing] = useState(false);

  // Follow run state for right panel
  const [followRunId, setFollowRunId] = useState<string | null>(null);

  // Right panel tab state
  type RightPanelTab = 'run' | 'log' | 'input' | 'output';
  const [activeRightTab, setActiveRightTab] = useState<RightPanelTab>('run');

  // Persist right panel tab to localStorage
  useEffect(() => {
    if (activeRightTab) {
      localStorage.setItem('lightning.ide-run-viewer-tab', activeRightTab);
    }
  }, [activeRightTab]);

  // Restore tab from localStorage on mount
  useEffect(() => {
    const savedTab = localStorage.getItem('lightning.ide-run-viewer-tab');
    if (savedTab && ['run', 'log', 'input', 'output'].includes(savedTab)) {
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
    enableScope('ide');
    return () => {
      disableScope('ide');
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
        title: 'Cannot save',
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
    runHandler: () => void,
    retryHandler?: () => void,
    isRetryable?: boolean,
    processing?: boolean
  ) => {
    setCanRunWorkflow(canRun);
    setIsRunning(isSubmitting);
    setRunHandler(() => runHandler);
    setRetryHandler(retryHandler ? () => retryHandler : null);
    setIsRetryable(isRetryable ?? false);
    setRunIsProcessing(processing ?? false);
  };

  // Handler for Run button
  const handleRunClick = () => {
    if (!canRunSnapshot) {
      notifications.alert({
        title: 'Cannot run',
        description: runTooltipMessage,
      });
      return;
    }

    if (!canRunWorkflow || isRunning || runIsProcessing || !runHandler) {
      return;
    }

    runHandler();
  };

  // Handler for Retry button
  const handleRetryClick = () => {
    if (!canRunSnapshot) {
      notifications.alert({
        title: 'Cannot run',
        description: runTooltipMessage,
      });
      return;
    }

    if (!canRunWorkflow || isRunning || runIsProcessing || !retryHandler) {
      return;
    }

    retryHandler();
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
      pushEvent('open_credential_modal', { schema: adaptorName });
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

  const handleConfigureSave = useCallback(
    (config: {
      adaptorPackage: string;
      adaptorVersion: string;
      credentialId: string | null;
    }) => {
      if (!currentJob) return;

      // Build the Y.Doc updates (only Job schema fields)
      const jobUpdates: {
        adaptor: string;
        project_credential_id: string | null;
        keychain_credential_id: string | null;
      } = {
        adaptor: `${config.adaptorPackage}@${config.adaptorVersion}`,
        project_credential_id: null,
        keychain_credential_id: null,
      };

      // Update credential if selected
      if (config.credentialId) {
        const isProjectCredential = projectCredentials.some(
          c => c.project_credential_id === config.credentialId
        );
        const isKeychainCredential = keychainCredentials.some(
          c => c.id === config.credentialId
        );

        if (isProjectCredential) {
          jobUpdates.project_credential_id = config.credentialId;
        } else if (isKeychainCredential) {
          jobUpdates.keychain_credential_id = config.credentialId;
        }
      }

      // Persist to Y.Doc
      updateJob(currentJob.id, jobUpdates);

      // Close modal
      setIsConfigureModalOpen(false);
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
        pushEvent('close_credential_modal_complete', {});
      }, 500);
    };

    const element = document.getElementById('collaborative-editor-react');
    element?.addEventListener('close_credential_modal', handleModalClose);

    return () => {
      element?.removeEventListener('close_credential_modal', handleModalClose);
    };
  }, [pushEvent]);

  // Listen for credential saved event
  useEffect(() => {
    const cleanup = handleEvent('credential_saved', (payload: any) => {
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
    'escape',
    event => {
      // Check if Monaco editor has focus
      const activeElement = document.activeElement;
      const isMonacoFocused = activeElement?.closest('.monaco-editor');

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
      scopes: ['ide'],
      enableOnFormTags: true, // Allow Escape even in Monaco editor
    },
    [onClose]
  );

  // Note: Keyboard shortcuts for Cmd+Enter and Cmd+Shift+Enter are handled
  // in IDEHeader component to avoid duplicate handlers. IDEHeader uses scoped
  // hotkeys that work even when Monaco editor has focus.

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
        onRun={handleRunClick}
        onRetry={handleRetryClick}
        isRetryable={isRetryable}
        canRun={
          canRunSnapshot && canRunWorkflow && !isRunning && !runIsProcessing
        }
        isRunning={isRunning || runIsProcessing}
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
                  isLeftCollapsed ? 'rotate-90' : ''
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
                    'flex-1 overflow-hidden bg-white',
                    isLeftCollapsed && 'hidden'
                  )}
                >
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
                  isCenterCollapsed ? 'rotate-90' : ''
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
                    adaptor={currentJob.adaptor || 'common'}
                    disabled={!canSave}
                    className="h-full w-full"
                    options={{
                      automaticLayout: true,
                      minimap: { enabled: true },
                      lineNumbers: 'on',
                      wordWrap: 'on',
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
                  isRightCollapsed ? 'rotate-90' : ''
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
                            { value: 'run', label: 'Run' },
                            { value: 'log', label: 'Log' },
                            { value: 'input', label: 'Input' },
                            { value: 'output', label: 'Output' },
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
            onSave={handleConfigureSave}
            onOpenAdaptorPicker={handleOpenAdaptorPicker}
            onOpenCredentialModal={handleOpenCredentialModal}
            currentAdaptor={
              resolveAdaptor(
                currentJob.adaptor || '@openfn/language-common@latest'
              ).package || '@openfn/language-common'
            }
            currentVersion={
              resolveAdaptor(
                currentJob.adaptor || '@openfn/language-common@latest'
              ).version || 'latest'
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
