import {
  DocumentTextIcon,
  SparklesIcon,
  ViewColumnsIcon,
  XMarkIcon,
} from '@heroicons/react/24/outline';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  type ImperativePanelHandle,
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from 'react-resizable-panels';

import { useKeyboardShortcut } from '#/collaborative-editor/keyboard';
import { cn } from '#/utils/cn';

import Docs from '../../../adaptor-docs/Docs';
import Metadata from '../../../metadata-explorer/Explorer';
import { useURLState } from '../../../react/lib/use-url-state';
import type { Dataclip } from '../../api/dataclips';
import * as dataclipApi from '../../api/dataclips';
import { RENDER_MODES } from '../../constants/panel';
import { useLiveViewActions } from '../../contexts/LiveViewActionsContext';
import { useProjectAdaptors } from '../../hooks/useAdaptors';
import {
  useCredentials,
  useCredentialsCommands,
} from '../../hooks/useCredentials';
import {
  useFollowRun,
  useHistoryCommands,
  useJobMatchesRun,
} from '../../hooks/useHistory';
import { useRunRetry } from '../../hooks/useRunRetry';
import { useRunRetryShortcuts } from '../../hooks/useRunRetryShortcuts';
import { useSession } from '../../hooks/useSession';
import { useProject } from '../../hooks/useSessionContext';
import {
  useCanRun,
  useCanSave,
  useCurrentJob,
  useWorkflowActions,
  useWorkflowReadOnly,
  useWorkflowState,
} from '../../hooks/useWorkflow';
import { isFinalState } from '../../types/history';
import { edgesToAdjList, getJobOrdinals } from '../../utils/workflowGraph';
import { AdaptorDisplay } from '../AdaptorDisplay';
import { AdaptorSelectionModal } from '../AdaptorSelectionModal';
import { CollaborativeMonaco } from '../CollaborativeMonaco';
import { RunBadge } from '../common/RunBadge';
import { ConfigureAdaptorModal } from '../ConfigureAdaptorModal';
import { JobSelector } from '../JobSelector';
import { ManualRunPanel } from '../ManualRunPanel';
import { ManualRunPanelErrorBoundary } from '../ManualRunPanelErrorBoundary';
import { RunViewerErrorBoundary } from '../run-viewer/RunViewerErrorBoundary';
import { RunViewerPanel } from '../run-viewer/RunViewerPanel';
import { RunRetryButton } from '../RunRetryButton';
import { SandboxIndicatorBanner } from '../SandboxIndicatorBanner';
import { ShortcutKeys } from '../ShortcutKeys';
import { Tabs } from '../Tabs';
import { Tooltip } from '../Tooltip';

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
  useEffect(() => {
    return () => {};
  }, []);

  const { searchParams, updateSearchParams } = useURLState();
  const jobIdFromURL = searchParams.get('job');
  // Support both 'run' (collaborative) and 'a' (classical) parameter for run ID
  const runIdFromURL = searchParams.get('run') || searchParams.get('a');
  const stepIdFromURL = searchParams.get('step');
  const { selectJob, saveWorkflow } = useWorkflowActions();
  const { selectStep } = useHistoryCommands();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const awareness = useSession(selectAwareness);
  const { canSave } = useCanSave();

  const workflow = useWorkflowState(state =>
    state.workflow
      ? {
          ...state.workflow,
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

  const centerPanelRef = useRef<ImperativePanelHandle>(null);
  const rightPanelRef = useRef<ImperativePanelHandle>(null);

  const [isCenterCollapsed, setIsCenterCollapsed] = useState(false);
  const [isRightCollapsed, setIsRightCollapsed] = useState(false);

  // Docs/Metadata panel state
  const [isDocsCollapsed, setIsDocsCollapsed] = useState<boolean>(() => {
    const saved = localStorage.getItem('lightning.ide.docsPanel.collapsed');
    return saved ? JSON.parse(saved) === true : false;
  });
  const [docsOrientation, setDocsOrientation] = useState<
    'horizontal' | 'vertical'
  >(() => {
    const saved = localStorage.getItem('lightning.ide.docsPanel.orientation');
    return (saved as 'horizontal' | 'vertical') || 'horizontal';
  });
  const [selectedDocsTab, setSelectedDocsTab] = useState<'docs' | 'metadata'>(
    'docs'
  );
  const docsPanelRef = useRef<ImperativePanelHandle>(null);

  const [followRunId, setFollowRunId] = useState<string | null>(null);
  const [selectedDataclipState, setSelectedDataclipState] =
    useState<Dataclip | null>(null);
  const [selectedTab, setSelectedTab] = useState<
    'empty' | 'custom' | 'existing'
  >('empty');
  const [customBody, setCustomBody] = useState('');
  const [manuallyUnselectedDataclip, setManuallyUnselectedDataclip] =
    useState(false);

  const handleDataclipChange = useCallback((dataclip: Dataclip | null) => {
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

  const { isConnected, settled } = useSession();
  const isSessionReady = isConnected && settled;

  const currentRun = useFollowRun(isSessionReady ? runIdFromURL : null);

  // Check if the currently selected job matches the loaded run
  const jobMatchesRun = useJobMatchesRun(currentJob?.id || null);
  const shouldShowMismatch =
    !jobMatchesRun && currentRun && isFinalState(currentRun.state);
  const selectedStepName = currentJob?.name || 'This step';

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

    // Only auto-select if no dataclip is currently selected OR
    // if the selected dataclip doesn't match the expected one for this step
    if (
      selectedDataclipState !== null &&
      selectedDataclipState.id === inputDataclipId
    ) {
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
    selectedDataclipState,
  ]);

  type RightPanelTab = 'log' | 'input' | 'output';
  const [activeRightTab, setActiveRightTab] = useState<RightPanelTab>('log');

  useEffect(() => {
    if (activeRightTab) {
      localStorage.setItem('lightning.ide-run-viewer-tab', activeRightTab);
    }
  }, [activeRightTab]);

  useEffect(() => {
    const savedTab = localStorage.getItem('lightning.ide-run-viewer-tab');
    if (savedTab && ['log', 'input', 'output'].includes(savedTab)) {
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

  // Run/Retry functionality for IDE Header
  const { canRun: canRunSnapshot, tooltipMessage: runTooltipMessage } =
    useCanRun();
  const runContext = jobIdFromURL
    ? { type: 'job' as const, id: jobIdFromURL }
    : { type: 'trigger' as const, id: workflow?.triggers[0]?.id || '' };

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

  // Enable run/retry keyboard shortcuts in IDE
  useRunRetryShortcuts({
    onRun: () => {
      void handleRun();
    },
    onRetry: () => {
      void handleRetry();
    },
    canRun:
      canRunSnapshot &&
      canRunFromHook &&
      !isSubmitting &&
      !runIsProcessing &&
      jobMatchesRun,
    isRunning: isSubmitting || runIsProcessing,
    isRetryable,
    priority: 50, // IDE priority
  });

  // Handle job selection from JobSelector
  const sortedJobs = useMemo(() => {
    const allJobs = workflow?.jobs || [];
    const adjList = edgesToAdjList(workflow?.edges || []);
    const ordinals = getJobOrdinals(adjList.list, adjList.trigger_id);
    return [...allJobs].sort((a, b) => {
      return (ordinals[a.id] || Infinity) - (ordinals[b.id] || Infinity);
    });
  }, [workflow?.edges, workflow?.jobs]);

  const handleJobSelect = useCallback(
    (job: any) => {
      updateSearchParams({ job: job.id });
      selectJob(job.id);
      // Update selected step to match the new job
      if (currentRun?.steps) {
        const matchingStep = currentRun.steps.find(s => s.job_id === job.id);
        selectStep(matchingStep?.id || null);
      }
    },
    [updateSearchParams, selectJob, currentRun, selectStep]
  );

  // Handle close IDE
  const handleCloseIDE = useCallback(() => {
    onClose();
  }, [onClose]);

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

  const handleOpenAdaptorPicker = useCallback(() => {
    setIsConfigureModalOpen(false);
    setIsAdaptorPickerOpen(true);
  }, []);

  const handleOpenCredentialModal = useCallback(
    (adaptorName: string, credentialId?: string) => {
      setIsConfigureModalOpen(false);
      setIsCredentialModalOpen(true);
      pushEvent('open_credential_modal', {
        schema: adaptorName,
        credential_id: credentialId,
      });
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
      setIsCredentialModalOpen(false);

      // If we have a current job, update its credential assignment
      // (this happens when creating a new credential and selecting it)
      if (currentJob) {
        const { credential, is_project_credential } = payload;
        const credentialId = is_project_credential
          ? credential.project_credential_id
          : credential.id;

        updateJob(currentJob.id, {
          project_credential_id: is_project_credential ? credentialId : null,
          keychain_credential_id: is_project_credential ? null : credentialId,
        });
      }

      // Always refresh credentials and reopen configure modal
      void requestCredentials();

      setTimeout(() => {
        setIsConfigureModalOpen(true);
      }, 200);
    });

    return cleanup;
  }, [handleEvent, currentJob, updateJob, requestCredentials]);

  useKeyboardShortcut(
    'Escape, Control+e, Meta+e',
    () => {
      const activeElement = document.activeElement;
      const isMonacoFocused = activeElement?.closest('.monaco-editor');

      if (isMonacoFocused) {
        (activeElement as HTMLElement).blur();
      } else {
        onClose();
      }
    },
    50, // IDE priority
    {
      enabled:
        !isConfigureModalOpen && !isAdaptorPickerOpen && !isCredentialModalOpen,
    }
  );

  // Save docs panel collapsed state to localStorage
  useEffect(() => {
    localStorage.setItem(
      'lightning.ide.docsPanel.collapsed',
      JSON.stringify(isDocsCollapsed)
    );
  }, [isDocsCollapsed]);

  // IMPORTANT: All hooks must be called before any early returns
  const { isReadOnly } = useWorkflowReadOnly();

  // Check loading state but don't use early return (violates rules of hooks)
  // Only check for job existence, not ytext/awareness
  // ytext and awareness persist during disconnection for offline editing
  const isLoading = !currentJob;

  // If loading, render loading state at the end instead of early return
  if (isLoading) {
    return (
      <div
        className="absolute inset-0 z-50 bg-white flex
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
    (!isCenterCollapsed ? 1 : 0) + (!isRightCollapsed ? 1 : 0);

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

  const toggleDocsPanel = () => {
    if (isDocsCollapsed) {
      docsPanelRef.current?.expand();
    } else {
      docsPanelRef.current?.collapse();
    }
  };

  const toggleDocsOrientation = () => {
    const newOrientation =
      docsOrientation === 'horizontal' ? 'vertical' : 'horizontal';
    setDocsOrientation(newOrientation);
    localStorage.setItem('lightning.ide.docsPanel.orientation', newOrientation);
  };

  const handleDocsTabChange = (tab: 'docs' | 'metadata') => {
    setSelectedDocsTab(tab);
    if (isDocsCollapsed) {
      docsPanelRef.current?.expand();
    }
  };

  return (
    <div className="absolute inset-0 z-49 bg-white flex flex-col">
      <SandboxIndicatorBanner
        parentProjectId={parentProjectId}
        parentProjectName={parentProjectName}
        projectName={project?.name}
        position="relative"
      />

      {/* IDE Heading Bar */}
      <div className="flex-none bg-white border-b border-gray-200">
        <div className="flex items-center justify-between px-4 py-2">
          <div className="flex items-center gap-3 flex-1 min-w-0">
            {/* Job Selector */}
            <div className="shrink-0">
              <JobSelector
                currentJob={currentJob}
                jobs={sortedJobs}
                onChange={handleJobSelect}
              />
            </div>

            {/* Adaptor Display with Version Dropdown */}
            {currentJob && (
              <div className="flex items-center gap-3 shrink-0">
                <AdaptorDisplay
                  adaptor={
                    currentJob.adaptor || '@openfn/language-common@latest'
                  }
                  credentialId={
                    currentJob.project_credential_id ||
                    currentJob.keychain_credential_id ||
                    null
                  }
                  size="sm"
                  onEdit={() => setIsConfigureModalOpen(true)}
                  onChangeAdaptor={handleOpenAdaptorPicker}
                  isReadOnly={isReadOnly}
                />
              </div>
            )}
          </div>

          <div className="flex items-center gap-2 shrink-0">
            {/* Run/Retry button */}
            <RunRetryButton
              isRetryable={isRetryable}
              isDisabled={
                !(
                  canRunSnapshot &&
                  canRunFromHook &&
                  !isSubmitting &&
                  !runIsProcessing &&
                  jobMatchesRun
                )
              }
              isSubmitting={isSubmitting || runIsProcessing}
              onRun={() => {
                void handleRun();
              }}
              onRetry={() => {
                void handleRetry();
              }}
              buttonText={{
                run: 'Run',
                retry: 'Run (retry)',
                processing: 'Processing',
              }}
              variant="primary"
              dropdownPosition="down"
              showKeyboardShortcuts={true}
              disabledTooltip={
                !jobMatchesRun
                  ? 'Selected job was not part of this run'
                  : runTooltipMessage
              }
            />

            {/* Close button */}
            <Tooltip content={<ShortcutKeys keys={['esc']} />} side="bottom">
              <button
                onClick={handleCloseIDE}
                className="p-1 hover:bg-gray-100 rounded transition-colors"
                aria-label="Close IDE"
              >
                <XMarkIcon className="h-5 w-5 text-gray-500" />
              </button>
            </Tooltip>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-hidden">
        <PanelGroup
          direction="horizontal"
          autoSaveId="lightning.ide-layout"
          className="h-full"
        >
          {/* Center Panel - CollaborativeMonaco Editor with nested Docs/Metadata */}
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
                <div className="flex items-center justify-between px-4 py-1">
                  {!isCenterCollapsed ? (
                    <>
                      <div
                        className="text-xs font-medium text-gray-400
                        uppercase tracking-wide"
                      >
                        Code - {currentJob?.name || 'Untitled'}
                      </div>
                      <div className="flex items-center gap-1">
                        {/* Docs/Metadata toggle buttons */}
                        <button
                          onClick={() => handleDocsTabChange('docs')}
                          className={cn(
                            'flex items-center gap-1 px-2 py-1 text-xs rounded transition-colors',
                            selectedDocsTab === 'docs' && !isDocsCollapsed
                              ? 'bg-primary-100 text-primary-800'
                              : 'text-gray-400 hover:text-gray-600 hover:bg-gray-100'
                          )}
                          title="Show adaptor documentation"
                        >
                          <DocumentTextIcon className="h-3.5 w-3.5" />
                          Docs
                        </button>
                        <button
                          onClick={() => handleDocsTabChange('metadata')}
                          className={cn(
                            'flex items-center gap-1 px-2 py-1 text-xs rounded transition-colors',
                            selectedDocsTab === 'metadata' && !isDocsCollapsed
                              ? 'bg-primary-100 text-primary-800'
                              : 'text-gray-400 hover:text-gray-600 hover:bg-gray-100'
                          )}
                          title="Show metadata explorer"
                        >
                          <SparklesIcon className="h-3.5 w-3.5" />
                          Metadata
                        </button>
                        <PanelToggleButton
                          onClick={toggleCenterPanel}
                          disabled={openPanelCount === 1}
                          isCollapsed={isCenterCollapsed}
                          ariaLabel="Collapse code panel"
                        />
                      </div>
                    </>
                  ) : (
                    <button
                      onClick={toggleCenterPanel}
                      className="ml-2 text-xs font-medium text-gray-400
                        uppercase tracking-wide hover:text-gray-600
                        transition-colors cursor-pointer whitespace-nowrap"
                    >
                      Code - {currentJob?.name || 'Untitled'}
                    </button>
                  )}
                </div>
              </div>

              {/* Nested PanelGroup for Editor + Docs/Metadata */}
              {!isCenterCollapsed && (
                <div className="flex-1 overflow-hidden">
                  <PanelGroup
                    key={docsOrientation}
                    direction={docsOrientation}
                    autoSaveId="lightning.ide-docs-layout"
                    className="h-full"
                  >
                    {/* Monaco Editor Panel */}
                    <Panel defaultSize={60} minSize={25}>
                      <div className="h-full flex flex-col">
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
                      </div>
                    </Panel>

                    {/* Resize Handle */}
                    {!isDocsCollapsed && (
                      <PanelResizeHandle
                        className={cn(
                          'bg-gray-200 hover:bg-blue-400 transition-colors',
                          docsOrientation === 'horizontal'
                            ? 'w-1 cursor-col-resize'
                            : 'h-1 cursor-row-resize'
                        )}
                      />
                    )}

                    {/* Docs/Metadata Panel */}
                    <Panel
                      ref={docsPanelRef}
                      defaultSize={40}
                      minSize={20}
                      collapsible
                      collapsedSize={0}
                      onCollapse={() => setIsDocsCollapsed(true)}
                      onExpand={() => setIsDocsCollapsed(false)}
                      className="bg-white"
                    >
                      <div className="h-full flex flex-col">
                        {/* Docs panel header with controls */}
                        {!isDocsCollapsed && (
                          <div className="shrink-0">
                            <div className="flex items-center justify-between px-3 pt-2 pb-1">
                              <div className="flex-1">
                                <Tabs
                                  value={selectedDocsTab}
                                  onChange={tab => setSelectedDocsTab(tab)}
                                  variant="pills"
                                  options={[
                                    {
                                      value: 'docs',
                                      label: 'Docs',
                                      icon: DocumentTextIcon,
                                    },
                                    {
                                      value: 'metadata',
                                      label: 'Metadata',
                                      icon: SparklesIcon,
                                    },
                                  ]}
                                />
                              </div>
                              <div className="flex items-center gap-1 pl-2">
                                <button
                                  onClick={toggleDocsOrientation}
                                  className="p-1 hover:bg-gray-100 rounded transition-colors"
                                  title="Toggle panel orientation"
                                >
                                  <ViewColumnsIcon
                                    className={cn(
                                      'h-4 w-4 text-gray-500',
                                      docsOrientation === 'vertical' &&
                                        'rotate-90'
                                    )}
                                  />
                                </button>
                                <button
                                  onClick={toggleDocsPanel}
                                  className="p-1 hover:bg-gray-100 rounded transition-colors"
                                  aria-label="Close docs panel"
                                  title="Close docs panel"
                                >
                                  <XMarkIcon className="h-4 w-4 text-gray-500" />
                                </button>
                              </div>
                            </div>
                          </div>
                        )}

                        {/* Docs/Metadata content */}
                        {!isDocsCollapsed && (
                          <div className="flex-1 overflow-auto p-2">
                            {selectedDocsTab === 'docs' && (
                              <Docs
                                adaptor={
                                  currentJob.adaptor ||
                                  '@openfn/language-common@latest'
                                }
                              />
                            )}
                            {selectedDocsTab === 'metadata' && (
                              <Metadata
                                adaptor={
                                  currentJob.adaptor ||
                                  '@openfn/language-common@latest'
                                }
                                metadata={null}
                              />
                            )}
                          </div>
                        )}
                      </div>
                    </Panel>
                  </PanelGroup>
                </div>
              )}
            </div>
          </Panel>

          {/* Resize Handle */}
          <PanelResizeHandle
            className="w-1 bg-gray-200 hover:bg-blue-400
            transition-colors cursor-col-resize"
          />

          {/* Right Panel - ManualRunPanel or RunViewerPanel */}
          <Panel
            ref={rightPanelRef}
            defaultSize={30}
            minSize={30}
            collapsible
            collapsedSize={2}
            onCollapse={() => setIsRightCollapsed(true)}
            onExpand={() => setIsRightCollapsed(false)}
            className="bg-slate-100 bg-gray-50 border-l border-gray-200"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading with tabs or title */}
              <div
                className={`shrink-0 transition-transform ${
                  isRightCollapsed ? 'rotate-90' : ''
                }`}
              >
                <div className="flex items-center justify-between px-4 py-1">
                  {!isRightCollapsed ? (
                    <>
                      {followRunId ? (
                        <>
                          {/* Close run chip */}
                          <Tooltip
                            content={
                              shouldShowMismatch
                                ? `${selectedStepName} was not part of this run. Pick another step or deselect the run.`
                                : undefined
                            }
                            side="bottom"
                          >
                            <RunBadge
                              runId={followRunId}
                              onClose={() => {
                                setFollowRunId(null);
                                updateSearchParams({ run: null });
                              }}
                              variant={
                                shouldShowMismatch ? 'warning' : 'default'
                              }
                              className="mr-3"
                            />
                          </Tooltip>
                          {/* Tabs as header content when showing run */}
                          <div className="flex-1">
                            <Tabs
                              value={activeRightTab}
                              onChange={setActiveRightTab}
                              variant="underline"
                              options={[
                                { value: 'log', label: 'Logs' },
                                { value: 'input', label: 'Input' },
                                { value: 'output', label: 'Output' },
                              ]}
                            />
                          </div>
                        </>
                      ) : (
                        <>
                          {/* Simple title when showing manual run panel */}
                          <div
                            className="text-xs font-medium text-gray-400
                            uppercase tracking-wide"
                          >
                            New Run (Select Input)
                          </div>
                        </>
                      )}
                      {/* Collapse button */}
                      <PanelToggleButton
                        onClick={toggleRightPanel}
                        disabled={openPanelCount === 1}
                        isCollapsed={isRightCollapsed}
                        ariaLabel="Collapse right panel"
                      />
                    </>
                  ) : (
                    <button
                      onClick={toggleRightPanel}
                      className="ml-2 text-xs font-medium text-gray-400
                        uppercase tracking-wide hover:text-gray-600
                        transition-colors cursor-pointer whitespace-nowrap"
                    >
                      {followRunId
                        ? `Run - ${followRunId.slice(0, 7)}`
                        : 'New Run (Select Input)'}
                    </button>
                  )}
                </div>
              </div>

              {/* Panel content */}
              {!isRightCollapsed && (
                <div className="flex-1 overflow-hidden bg-white">
                  {followRunId ? (
                    <RunViewerErrorBoundary>
                      <RunViewerPanel
                        followRunId={followRunId}
                        onClearFollowRun={() => setFollowRunId(null)}
                        activeTab={activeRightTab}
                        onTabChange={setActiveRightTab}
                      />
                    </RunViewerErrorBoundary>
                  ) : (
                    workflow &&
                    projectId &&
                    workflowId && (
                      <ManualRunPanelErrorBoundary
                        onClose={() => rightPanelRef.current?.collapse()}
                      >
                        <ManualRunPanel
                          workflow={workflow}
                          projectId={projectId}
                          workflowId={workflowId}
                          jobId={jobIdFromURL ?? null}
                          triggerId={null}
                          onClose={() => rightPanelRef.current?.collapse()}
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
                    )
                  )}
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
