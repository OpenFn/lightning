import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useHotkeys, useHotkeysContext } from 'react-hotkeys-hook';
import {
  type ImperativePanelHandle,
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from 'react-resizable-panels';

import { useUICommands } from '#/collaborative-editor/hooks/useUI';
import { cn } from '#/utils/cn';

import { useURLState } from '../../../react/lib/use-url-state';
import * as dataclipApi from '../../api/dataclips';
import type { Dataclip } from '../../api/dataclips';
import { HOTKEY_SCOPES } from '../../constants/hotkeys';
import { RENDER_MODES } from '../../constants/panel';
import { useLiveViewActions } from '../../contexts/LiveViewActionsContext';
import { useProjectAdaptors } from '../../hooks/useAdaptors';
import {
  useCredentials,
  useCredentialsCommands,
} from '../../hooks/useCredentials';
import { useFollowRun, useHistoryCommands } from '../../hooks/useHistory';
import { useRunRetry } from '../../hooks/useRunRetry';
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
import { ManualRunPanelErrorBoundary } from '../ManualRunPanelErrorBoundary';
import { RunViewerErrorBoundary } from '../run-viewer/RunViewerErrorBoundary';
import { RunViewerPanel } from '../run-viewer/RunViewerPanel';
import { SandboxIndicatorBanner } from '../SandboxIndicatorBanner';
import { Tabs } from '../Tabs';

import { IDEHeader } from './IDEHeader';
import { PanelToggleButton } from './PanelToggleButton';

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
  const jobIdFromURL = searchParams.get('job');
  // Support both 'run' (collaborative) and 'a' (classical) parameter for run ID
  const runIdFromURL = searchParams.get('run') || searchParams.get('a');
  const stepIdFromURL = searchParams.get('step');
  const { selectJob, saveWorkflow } = useWorkflowActions();
  const { selectStep } = useHistoryCommands();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const awareness = useSession(selectAwareness);
  const { canSave, tooltipMessage } = useCanSave();
  const repoConnection = useProjectRepoConnection();
  const { openGitHubSyncModal } = useUICommands();
  const { canRun: canRunSnapshot, tooltipMessage: runTooltipMessage } =
    useCanRun();

  const snapshotVersion = useWorkflowState(
    state => state.workflow?.lock_version
  );
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

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

  const project = useProject();
  const projectId = project?.id;
  const workflowId = useWorkflowState(state => state.workflow?.id);

  const leftPanelRef = useRef<ImperativePanelHandle>(null);
  const centerPanelRef = useRef<ImperativePanelHandle>(null);
  const rightPanelRef = useRef<ImperativePanelHandle>(null);

  const [isLeftCollapsed, setIsLeftCollapsed] = useState(false);
  const [isCenterCollapsed, setIsCenterCollapsed] = useState(false);
  const [isRightCollapsed, setIsRightCollapsed] = useState(true);

  const [followRunId, setFollowRunId] = useState<string | null>(null);
  const [selectedDataclipState, setSelectedDataclipState] = useState<any>(null);
  const [selectedTab, setSelectedTab] = useState<
    'empty' | 'custom' | 'existing'
  >('empty');
  const [customBody, setCustomBody] = useState('');
  const [manuallyUnselectedDataclip, setManuallyUnselectedDataclip] =
    useState(false);

  const handleDataclipChange = useCallback((dataclip: any) => {
    setSelectedDataclipState(dataclip);
    setManuallyUnselectedDataclip(dataclip === null);
  }, []);

  const handleRunSubmitted = useCallback(
    (runId: string, dataclip?: Dataclip) => {
      setFollowRunId(runId);
      updateSearchParams({ run: runId });
      setManuallyUnselectedDataclip(false);

      // If a dataclip was created (from custom body), select it and switch to existing tab
      if (dataclip) {
        setSelectedDataclipState(dataclip);
        setSelectedTab('existing');
        setCustomBody('');
      }

      if (rightPanelRef.current?.isCollapsed()) {
        rightPanelRef.current.expand();
      }
    },
    [updateSearchParams]
  );

  const runContext = jobIdFromURL
    ? { type: 'job' as const, id: jobIdFromURL }
    : {
        type: 'trigger' as const,
        id: workflow?.triggers[0]?.id || '',
      };

  // Declaratively connect to run channel when runIdFromURL changes
  const currentRun = useFollowRun(runIdFromURL);

  const followedRunStep = useMemo(() => {
    if (!currentRun || !currentRun.steps || !jobIdFromURL) return null;
    return currentRun.steps.find(s => s.job_id === jobIdFromURL) || null;
  }, [currentRun, jobIdFromURL]);

  useEffect(() => {
    const runId = searchParams.get('run');
    if (runId && runId !== followRunId) {
      setManuallyUnselectedDataclip(false);
    }
  }, [searchParams, followRunId]);

  useEffect(() => {
    const inputDataclipId = followedRunStep?.input_dataclip_id;

    if (
      !inputDataclipId ||
      !jobIdFromURL ||
      !projectId ||
      manuallyUnselectedDataclip
    ) {
      return;
    }

    // Only auto-select if no dataclip is currently selected
    // This allows users to manually select different dataclips
    if (selectedDataclipState !== null) {
      return;
    }

    const runId = searchParams.get('run') || searchParams.get('a');
    if (!runId) {
      return;
    }

    const fetchDataclip = async () => {
      try {
        const response = await dataclipApi.getRunDataclip(
          projectId,
          runId,
          jobIdFromURL
        );

        if (response.dataclip) {
          setSelectedDataclipState(response.dataclip);
          setManuallyUnselectedDataclip(false);
        }
      } catch (error) {
        console.error('Failed to fetch dataclip for retry:', error);
      }
    };

    void fetchDataclip();
  }, [
    followedRunStep?.input_dataclip_id,
    jobIdFromURL,
    projectId,
    searchParams,
    manuallyUnselectedDataclip,
  ]);

  const {
    handleRun,
    handleRetry,
    isSubmitting,
    isRetryable,
    runIsProcessing,
    canRun: canRunFromHook,
  } = useRunRetry({
    projectId: projectId || '',
    workflowId: workflowId || '',
    runContext,
    selectedTab,
    selectedDataclip: selectedDataclipState,
    customBody,
    canRunWorkflow: canRunSnapshot,
    workflowRunTooltipMessage: runTooltipMessage,
    saveWorkflow,
    onRunSubmitted: handleRunSubmitted,
    edgeId: null,
    workflowEdges: workflow?.edges || [],
  });

  type RightPanelTab = 'run' | 'log' | 'input' | 'output';
  const [activeRightTab, setActiveRightTab] = useState<RightPanelTab>('run');

  useEffect(() => {
    if (activeRightTab) {
      localStorage.setItem('lightning.ide-run-viewer-tab', activeRightTab);
    }
  }, [activeRightTab]);

  useEffect(() => {
    const savedTab = localStorage.getItem('lightning.ide-run-viewer-tab');
    if (savedTab && ['run', 'log', 'input', 'output'].includes(savedTab)) {
      setActiveRightTab(savedTab as RightPanelTab);
    }
  }, []);

  const [isConfigureModalOpen, setIsConfigureModalOpen] = useState(false);
  const [isAdaptorPickerOpen, setIsAdaptorPickerOpen] = useState(false);
  const [isCredentialModalOpen, setIsCredentialModalOpen] = useState(false);

  const { projectCredentials, keychainCredentials } = useCredentials();
  const { requestCredentials } = useCredentialsCommands();
  const { projectAdaptors, allAdaptors } = useProjectAdaptors();
  const { pushEvent, handleEvent } = useLiveViewActions();
  const { updateJob } = useWorkflowActions();

  const { enableScope, disableScope } = useHotkeysContext();

  useEffect(() => {
    enableScope(HOTKEY_SCOPES.IDE);
    return () => {
      disableScope(HOTKEY_SCOPES.IDE);
    };
  }, [enableScope, disableScope]);

  useEffect(() => {
    if (jobIdFromURL) {
      selectJob(jobIdFromURL);
    }
  }, [jobIdFromURL, selectJob]);

  useEffect(() => {
    if (runIdFromURL && runIdFromURL !== followRunId) {
      setFollowRunId(runIdFromURL);

      if (rightPanelRef.current?.isCollapsed()) {
        rightPanelRef.current.expand();
      }
    }
  }, [runIdFromURL, followRunId]);

  useEffect(() => {
    if (stepIdFromURL && runIdFromURL) {
      selectStep(stepIdFromURL);
    }
  }, [stepIdFromURL, runIdFromURL, selectStep]);

  const handleSave = () => {
    if (!canSave) {
      notifications.alert({
        title: 'Cannot save',
        description: tooltipMessage,
      });
      return;
    }
    void saveWorkflow();
  };

  const handleCollapseLeftPanel = () => {
    leftPanelRef.current?.collapse();
  };

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

      const packageMatch = adaptorName.match(/(.+?)(@|$)/);
      const newPackage = packageMatch ? packageMatch[1] : adaptorName;
      const fullAdaptor = `${newPackage}@latest`;

      updateJob(currentJob.id, { adaptor: fullAdaptor });

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

      updateJob(currentJob.id, jobUpdates);

      // setIsConfigureModalOpen(false);
    },
    [currentJob, projectCredentials, keychainCredentials, updateJob]
  );

  useEffect(() => {
    const handleModalClose = () => {
      setIsCredentialModalOpen(false);
      setTimeout(() => {
        setIsConfigureModalOpen(true);
      }, 200);
      setTimeout(() => {
        pushEvent('close_credential_modal', {});
      }, 500);
    };

    const element = document.getElementById('collaborative-editor-react');
    element?.addEventListener('close_credential_modal', handleModalClose);

    return () => {
      element?.removeEventListener('close_credential_modal', handleModalClose);
    };
  }, [pushEvent]);

  useEffect(() => {
    const cleanup = handleEvent('credential_saved', (payload: any) => {
      if (!currentJob) return;

      setIsCredentialModalOpen(false);

      const { credential, is_project_credential } = payload;
      const credentialId = is_project_credential
        ? credential.project_credential_id
        : credential.id;

      updateJob(currentJob.id, {
        project_credential_id: is_project_credential ? credentialId : null,
        keychain_credential_id: is_project_credential ? null : credentialId,
      });

      void requestCredentials();

      setTimeout(() => {
        setIsConfigureModalOpen(true);
      }, 200);
    });

    return cleanup;
  }, [handleEvent, currentJob, updateJob, requestCredentials]);

  useHotkeys(
    'escape',
    event => {
      const activeElement = document.activeElement;
      const isMonacoFocused = activeElement?.closest('.monaco-editor');

      if (isMonacoFocused) {
        (activeElement as HTMLElement).blur();
        event.preventDefault();
      } else {
        onClose();
      }
    },
    {
      enabled: true,
      scopes: [HOTKEY_SCOPES.IDE],
      enableOnFormTags: true,
    },
    [onClose]
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

  const openPanelCount =
    (!isLeftCollapsed ? 1 : 0) +
    (!isCenterCollapsed ? 1 : 0) +
    (!isRightCollapsed ? 1 : 0);

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
                      onTabChange={setSelectedTab}
                      onDataclipChange={handleDataclipChange}
                      onCustomBodyChange={setCustomBody}
                      selectedTab={selectedTab}
                      selectedDataclip={selectedDataclipState}
                      customBody={customBody}
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
            onAdaptorChange={handleAdaptorChange}
            onVersionChange={handleVersionChange}
            onCredentialChange={handleCredentialChange}
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
