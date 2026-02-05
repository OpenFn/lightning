import {
  ChevronRightIcon,
  ClockIcon,
  DocumentTextIcon,
  SparklesIcon,
  ViewColumnsIcon,
  XMarkIcon,
} from '@heroicons/react/24/outline';
import { ClockIcon as ClockIconSolid } from '@heroicons/react/24/solid';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  type ImperativePanelHandle,
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from 'react-resizable-panels';

import { useKeyboardShortcut } from '#/collaborative-editor/keyboard';
import { useURLState } from '#/react/lib/use-url-state';
import { cn } from '#/utils/cn';

import Docs from '../../../adaptor-docs/Docs';
import Metadata from '../../../metadata-explorer/Explorer';
import type { Dataclip } from '../../api/dataclips';
import * as dataclipApi from '../../api/dataclips';
import { RENDER_MODES } from '../../constants/panel';
import { useCredentialModal } from '../../contexts/CredentialModalContext';
import { useMonacoRef } from '../../contexts/MonacoRefContext';
import { useProjectAdaptors } from '../../hooks/useAdaptors';
import {
  useCredentials,
  useCredentialsCommands,
} from '../../hooks/useCredentials';
import {
  useActiveRun,
  useFollowRun,
  useHistory,
  useHistoryCommands,
  useHistoryError,
  useHistoryLoading,
  useJobMatchesRun,
} from '../../hooks/useHistory';
import { useRunRetry } from '../../hooks/useRunRetry';
import { useMetadata } from '../../hooks/useMetadata';
import { useRunRetryShortcuts } from '../../hooks/useRunRetryShortcuts';
import { useSession } from '../../hooks/useSession';
import { useProject } from '../../hooks/useSessionContext';
import { useVersionMismatch } from '../../hooks/useVersionMismatch';
import { useVersionSelect } from '../../hooks/useVersionSelect';
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
import { CollaborativeMonaco, type MonacoHandle } from '../CollaborativeMonaco';
import { RunBadge } from '../common/RunBadge';
import { ConfigureAdaptorModal } from '../ConfigureAdaptorModal';
import MiniHistory from '../diagram/MiniHistory';
import { VersionMismatchBanner } from '../diagram/VersionMismatchBanner';
import { JobSelector } from '../JobSelector';
import { ManualRunPanel } from '../ManualRunPanel';
import { ManualRunPanelErrorBoundary } from '../ManualRunPanelErrorBoundary';
import { NewRunButton } from '../NewRunButton';
import { RunViewerErrorBoundary } from '../run-viewer/RunViewerErrorBoundary';
import { RunViewerPanel } from '../run-viewer/RunViewerPanel';
import { RunRetryButton } from '../RunRetryButton';
import { SandboxIndicatorBanner } from '../SandboxIndicatorBanner';
import { ShortcutKeys } from '../ShortcutKeys';
import { Tabs } from '../Tabs';
import { Tooltip } from '../Tooltip';

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
  const { params, updateSearchParams } = useURLState();
  const jobIdFromURL = params.job ?? null;
  // Support both 'run' (collaborative) and 'a' (classical) parameter for run ID
  const runIdFromURL = params.run ?? params.a ?? null;
  const stepIdFromURL = params.step ?? null;
  const { selectJob, saveWorkflow } = useWorkflowActions();
  const { selectStep } = useHistoryCommands();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { metadata, isLoading: isMetadataLoading } = useMetadata();
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

  const rightPanelRef = useRef<ImperativePanelHandle>(null);
  // Get shared monaco ref from context (for AI Assistant diff preview)
  // Fallback to local ref if context not available (shouldn't happen)
  const localMonacoRef = useRef<MonacoHandle>(null);
  const monacoRef = useMonacoRef() ?? localMonacoRef;

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

  // Right panel sub-state for when no run is loaded (undefined = panel hidden)
  const [rightPanelSubState, setRightPanelSubState] = useState<
    'history' | 'create-run' | undefined
  >(undefined);

  // Run panel collapsed state (only applies when viewing a run)
  const [isRunPanelCollapsed, setIsRunPanelCollapsed] = useState(false);

  // Derived panel state - run viewer takes precedence, undefined means panel is hidden
  const panelState: 'run-viewer' | 'history' | 'create-run' | undefined =
    followRunId ? 'run-viewer' : rightPanelSubState;

  const handleDataclipChange = useCallback((dataclip: Dataclip | null) => {
    setSelectedDataclipState(dataclip);
    setManuallyUnselectedDataclip(dataclip === null);
  }, []);

  // Declaratively connect to run channel when runIdFromURL changes
  const { run: currentRun, clearRun } = useFollowRun(runIdFromURL);

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

  const handleClearFollowRun = useCallback(() => {
    setFollowRunId(null);
    clearRun(); // call clear run for the history store
    updateSearchParams({ run: null });
    // Reset input state when unloading a run
    setSelectedDataclipState(null);
    setSelectedTab('empty');
    setCustomBody('');
    setManuallyUnselectedDataclip(false);
    setRightPanelSubState(undefined);
  }, [updateSearchParams, clearRun]);

  const handleNavigateToHistory = useCallback(() => {
    // Clear any active run to show history
    setFollowRunId(null);
    clearRun();
    updateSearchParams({ run: null });
    setRightPanelSubState('history');
  }, [updateSearchParams, clearRun]);

  const handleNavigateToCreateRun = useCallback(() => {
    // Reset to fresh state when entering create-run
    setSelectedDataclipState(null);
    setSelectedTab('empty');
    setCustomBody('');
    // Set to true to prevent ManualRunPanel from auto-selecting a dataclip
    setManuallyUnselectedDataclip(true);
    setRightPanelSubState('create-run');
  }, []);

  const handleClosePanel = useCallback(() => {
    // Reset input state when closing panel
    setSelectedDataclipState(null);
    setSelectedTab('empty');
    setCustomBody('');
    setManuallyUnselectedDataclip(false);
    setRightPanelSubState(undefined);
  }, []);

  const handleHistoryRunSelect = useCallback(
    (run: { id: string }) => {
      setFollowRunId(run.id);
      updateSearchParams({ run: run.id });
      // Panel will automatically switch to run-viewer due to derived state
    },
    [updateSearchParams]
  );

  // History data for panel variant
  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const { requestHistory, clearError } = useHistoryCommands();

  // Transform history with selection markers
  const selectedRunId = params.run ?? null;
  const historyWithSelection = useMemo(() => {
    if (!selectedRunId) return history;
    return history.map(workorder => ({
      ...workorder,
      runs: workorder.runs.map(run => ({
        ...run,
        selected: run.id === selectedRunId,
      })),
      selected: workorder.runs.some(run => run.id === selectedRunId),
    }));
  }, [selectedRunId, history]);

  // Find selected run object
  const selectedRun = useMemo(() => {
    if (!selectedRunId) return null;
    for (const workorder of history) {
      const run = workorder.runs.find(r => r.id === selectedRunId);
      if (run) return run;
    }
    return null;
  }, [selectedRunId, history]);

  // Check if the currently selected job matches the loaded run
  const jobMatchesRun = useJobMatchesRun(currentJob?.id || null);
  const shouldShowMismatch =
    !jobMatchesRun && currentRun && isFinalState(currentRun.state);
  const selectedJobName = currentJob?.name || 'This job';

  const followedRunStep = useMemo(() => {
    if (!currentRun || !currentRun.steps || !jobIdFromURL) return null;
    return currentRun.steps.find(s => s.job_id === jobIdFromURL) || null;
  }, [currentRun, jobIdFromURL]);

  useEffect(() => {
    const runId = params.run ?? null;
    if (runId && runId !== followRunId) {
      setManuallyUnselectedDataclip(false);
    }
  }, [params, followRunId]);

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

    const runId = params.run ?? params.a ?? null;
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
    params,
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
  // Track if adaptor picker was opened from configure modal (to return there on close)
  const [adaptorPickerFromConfigure, setAdaptorPickerFromConfigure] =
    useState(false);

  const { projectCredentials, keychainCredentials } = useCredentials();
  const { requestCredentials } = useCredentialsCommands();
  const { projectAdaptors, allAdaptors } = useProjectAdaptors();
  const { updateJob } = useWorkflowActions();

  // Credential modal is managed by the context
  const {
    openCredentialModal,
    isCredentialModalOpen,
    onModalClose,
    onCredentialSaved,
  } = useCredentialModal();

  // converting 'latest' on an adaptor string to the actual version number
  // to be used by components that can't make use of 'latest'
  const currJobAdaptor = useMemo(() => {
    if (!currentJob?.adaptor) {
      const latestCommon = projectAdaptors.find(
        a => a.name === '@openfn/language-common'
      )?.versions?.[0]?.version;
      return `@openfn/language-common@${latestCommon || 'latest'}`;
    }
    const resolved = resolveAdaptor(currentJob.adaptor);
    if (resolved.version !== 'latest') return currentJob?.adaptor;
    const latestVersion = projectAdaptors.find(a => a.name === resolved.package)
      ?.versions?.[0]?.version;
    // If version not found, return original adaptor string
    if (!latestVersion) return currentJob.adaptor;
    return `${resolved.package}@${latestVersion}`;
  }, [projectAdaptors, currentJob?.adaptor]);

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
      // If panel is not open or showing history, open create-run panel (same as New Run button)
      if (panelState === undefined || panelState === 'history') {
        handleNavigateToCreateRun();
      } else {
        void handleRun();
      }
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

  useKeyboardShortcut(
    'Control+h, Meta+h',
    () => {
      if (!isSubmitting && !runIsProcessing) {
        handleNavigateToHistory();
      }
    },
    50, // IDE priority
    { enabled: true }
  );

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

  // Reset input selection state when switching to a different job
  // This ensures the run button state is always valid for the current job
  const prevJobIdRef = useRef<string | null>(null);
  useEffect(() => {
    if (
      jobIdFromURL &&
      prevJobIdRef.current &&
      jobIdFromURL !== prevJobIdRef.current
    ) {
      // Job changed - reset input state to defaults
      setSelectedDataclipState(null);
      setSelectedTab('empty');
      setCustomBody('');
      setManuallyUnselectedDataclip(false);
      // Close panel if we were in create-run state
      if (rightPanelSubState === 'create-run') {
        setRightPanelSubState(undefined);
      }
    }
    prevJobIdRef.current = jobIdFromURL;
  }, [jobIdFromURL, rightPanelSubState]);

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

  // Sync job selection to step URL param when viewing a run
  useEffect(() => {
    if (jobIdFromURL && currentRun?.steps && runIdFromURL) {
      const matchingStep = currentRun.steps.find(
        s => s.job_id === jobIdFromURL
      );
      updateSearchParams({ step: matchingStep?.id || null });
    }
  }, [jobIdFromURL, currentRun, runIdFromURL, updateSearchParams]);

  // Request history when entering history state
  useEffect(() => {
    if (rightPanelSubState === 'history') {
      void requestHistory();
    }
  }, [rightPanelSubState, requestHistory]);

  // Called from ConfigureAdaptorModal "Change" button
  const handleOpenAdaptorPickerFromConfigure = useCallback(() => {
    setIsConfigureModalOpen(false);
    setIsAdaptorPickerOpen(true);
    setAdaptorPickerFromConfigure(true);
  }, []);

  // Called from AdaptorDisplay in header (direct open)
  const handleOpenAdaptorPickerDirect = useCallback(() => {
    setIsAdaptorPickerOpen(true);
    setAdaptorPickerFromConfigure(false);
  }, []);

  const handleOpenCredentialModal = useCallback(
    (adaptorName: string, credentialId?: string) => {
      setIsConfigureModalOpen(false);
      openCredentialModal(adaptorName, credentialId, 'ide');
    },
    [openCredentialModal]
  );

  const handleAdaptorSelect = useCallback(
    (adaptorName: string) => {
      if (!currentJob) return;

      const packageMatch = adaptorName.match(/(.+?)(@|$)/);
      const newPackage = packageMatch ? packageMatch[1] : adaptorName;
      const fullAdaptor = `${newPackage}@latest`;

      updateJob(currentJob.id, { adaptor: fullAdaptor });

      setIsAdaptorPickerOpen(false);
      setAdaptorPickerFromConfigure(false);
      // Always open configure modal after selecting an adaptor
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

  // Register callback to reopen configure modal when credential modal closes (only when opened from IDE)
  useEffect(() => {
    return onModalClose('ide', () => {
      setIsConfigureModalOpen(true);
    });
  }, [onModalClose]);

  // Register callback to handle credential saved - update job and refresh credentials (only when opened from IDE)
  useEffect(() => {
    return onCredentialSaved('ide', payload => {
      // Update the job's credential assignment
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

      // Refresh credentials list
      void requestCredentials();
    });
  }, [onCredentialSaved, currentJob, updateJob, requestCredentials]);

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

  // Detect version mismatch between run and current workflow
  const run = useActiveRun();
  const versionMismatch = useVersionMismatch(run?.id ?? null);
  const handleVersionSelect = useVersionSelect();

  const handleGoToVersion = useCallback(() => {
    if (versionMismatch) {
      handleVersionSelect(versionMismatch.runVersion);
    }
  }, [versionMismatch, handleVersionSelect]);

  // Check loading state but don't use early return (violates rules of hooks)
  // Only check for job existence, not ytext/awareness
  // ytext and awareness persist during disconnection for offline editing

  // Detect if job is truly missing vs still loading
  // Job is missing if: URL has job ID, workflow is loaded, but job doesn't exist in workflow
  const isJobMissing =
    jobIdFromURL &&
    workflow &&
    workflow.jobs &&
    !workflow.jobs.some(j => j.id === jobIdFromURL);

  // Show loading spinner if no current job and job is not confirmed missing
  const isLoading = !currentJob && !isJobMissing;

  // If loading, render loading state at the end instead of early return
  if (isLoading) {
    return (
      <div
        className="absolute inset-0 z-50 bg-gray-100 flex
          items-center justify-center"
      >
        <div className="flex items-center justify-center h-full w-full">
          <span className="relative inline-flex">
            <div className="inline-flex">
              <p className="text-gray-600">Loading IDE</p>
            </div>
            <span className="flex absolute h-3 w-3 right-0 -mr-5">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-3 w-3 bg-primary-500"></span>
            </span>
          </span>
        </div>
      </div>
    );
  }

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
            {/* Job Selector - show when workflow loaded, even if no job selected */}
            {workflow && (
              <div className="shrink-0">
                <JobSelector
                  currentJob={currentJob}
                  jobs={sortedJobs}
                  onChange={handleJobSelect}
                />
              </div>
            )}

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
                  onChangeAdaptor={handleOpenAdaptorPickerDirect}
                  isReadOnly={isReadOnly}
                />
              </div>
            )}

            {/* Docs/Metadata toggle buttons */}
            <div className="flex items-center gap-1 shrink-0">
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
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            {/* History button - always visible, disabled during submitting/processing */}
            <Tooltip
              content={<ShortcutKeys keys={['mod', 'h']} />}
              side="bottom"
            >
              <button
                type="button"
                onClick={handleNavigateToHistory}
                disabled={isSubmitting || runIsProcessing}
                className={cn(
                  'inline-flex items-center gap-1.5 rounded-md px-3 py-2 text-sm font-semibold shadow-xs transition-colors',
                  'disabled:bg-primary-300 disabled:hover:bg-primary-300 disabled:cursor-not-allowed',
                  isSubmitting || runIsProcessing
                    ? 'bg-primary-300 text-white cursor-not-allowed'
                    : 'bg-primary-600 text-white hover:bg-primary-500'
                )}
              >
                {panelState === 'history' ? (
                  <ClockIconSolid className="h-4 w-4" />
                ) : (
                  <ClockIcon className="h-4 w-4" />
                )}
                History
              </button>
            </Tooltip>

            {/* New Run button - shown when no panel or viewing history */}
            {(panelState === undefined || panelState === 'history') && (
              <NewRunButton onClick={handleNavigateToCreateRun} />
            )}

            {/* Run/Retry button - shown when creating new run or viewing existing run */}
            {(panelState === 'run-viewer' || panelState === 'create-run') && (
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
                  retry: 'Run (Retry)',
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
            )}

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
          <Panel defaultSize={100} minSize={25} className="bg-slate-100">
            <div className="h-full flex flex-col">
              {/* Editor + Docs/Metadata panels */}
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
                        {isJobMissing ? (
                          // Show message when job doesn't exist in current version
                          <div className="p-8">
                            <div className="text-center max-w-md mx-auto">
                              <p className="text-gray-600 text-sm">
                                The job you're trying to view didn't exist in
                                this version of the workflow.
                              </p>
                              <p className="text-gray-500 text-sm mt-2">
                                You can change versions or select another job.
                              </p>
                            </div>
                          </div>
                        ) : currentJob && currentJobYText ? (
                          <CollaborativeMonaco
                            ref={monacoRef}
                            ytext={currentJobYText}
                            awareness={awareness}
                            adaptor={currentJob.adaptor || 'common'}
                            {...(metadata && { metadata })}
                            disabled={!canSave}
                            className="h-full w-full"
                            options={{
                              automaticLayout: true,
                              minimap: { enabled: true },
                              lineNumbers: 'on',
                              wordWrap: 'on',
                            }}
                          />
                        ) : null}
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
                                onChange={tab =>
                                  setSelectedDocsTab(tab as 'docs' | 'metadata')
                                }
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
                            <Docs adaptor={currJobAdaptor} />
                          )}
                          {selectedDocsTab === 'metadata' && (
                            <Metadata
                              adaptor={currJobAdaptor}
                              metadata={isMetadataLoading ? true : metadata}
                            />
                          )}
                        </div>
                      )}
                    </div>
                  </Panel>
                </PanelGroup>
              </div>
            </div>
          </Panel>

          {/* Resize Handle - only show when right panel is visible */}
          {panelState && (
            <PanelResizeHandle
              className="w-1 bg-gray-200 hover:bg-blue-400
              transition-colors cursor-col-resize"
            />
          )}

          {/* Right Panel - ManualRunPanel or RunViewerPanel (only rendered when panelState exists) */}
          {panelState && (
            <Panel
              ref={rightPanelRef}
              defaultSize={
                panelState === 'run-viewer' && isRunPanelCollapsed ? 3 : 30
              }
              minSize={25}
              collapsible={panelState === 'run-viewer'}
              collapsedSize={3}
              onCollapse={() => setIsRunPanelCollapsed(true)}
              onExpand={() => setIsRunPanelCollapsed(false)}
              className="bg-gray-50 border-l border-gray-200"
            >
              {/* Collapsed run panel - vertical header */}
              {panelState === 'run-viewer' &&
              isRunPanelCollapsed &&
              followRunId ? (
                <div className="h-full flex flex-col items-center pt-3 bg-gray-50 overflow-hidden">
                  {/* Rotated Run badge - using actual RunBadge component */}
                  <button
                    type="button"
                    className="cursor-pointer bg-transparent border-none p-0"
                    style={{
                      writingMode: 'vertical-rl',
                      textOrientation: 'mixed',
                    }}
                    onClick={() => {
                      setIsRunPanelCollapsed(false);
                      rightPanelRef.current?.expand();
                    }}
                    title="Expand run panel"
                    aria-label="Expand run panel"
                  >
                    <RunBadge
                      runId={followRunId}
                      onClose={handleClearFollowRun}
                      variant={shouldShowMismatch ? 'warning' : 'default'}
                    />
                  </button>
                  {/* Vertical tab labels */}
                  <div className="flex flex-col items-center gap-1 mt-3">
                    {(
                      [
                        { value: 'log', label: 'Logs' },
                        { value: 'input', label: 'Input' },
                        { value: 'output', label: 'Output' },
                      ] as const
                    ).map(tab => (
                      <button
                        key={tab.value}
                        type="button"
                        className={cn(
                          'text-xs px-1 py-1 rounded whitespace-nowrap hover:bg-gray-200 transition-colors',
                          activeRightTab === tab.value
                            ? 'text-primary-600 font-medium'
                            : 'text-gray-500'
                        )}
                        style={{
                          writingMode: 'vertical-rl',
                          textOrientation: 'mixed',
                        }}
                        onClick={() => {
                          setActiveRightTab(tab.value);
                          setIsRunPanelCollapsed(false);
                          rightPanelRef.current?.expand();
                        }}
                        title={`View ${tab.label}`}
                      >
                        {tab.label}
                      </button>
                    ))}
                  </div>
                </div>
              ) : (
                <div className="h-full flex flex-col">
                  {/* Version mismatch banner - shown when viewing a run from different version */}
                  {panelState === 'run-viewer' && versionMismatch && (
                    <VersionMismatchBanner
                      runVersion={versionMismatch.runVersion}
                      currentVersion={versionMismatch.currentVersion}
                      onGoToVersion={handleGoToVersion}
                      className="py-1"
                    />
                  )}

                  {/* Panel heading - only for run-viewer */}
                  {panelState === 'run-viewer' && (
                    <div className="shrink-0">
                      <div className="flex items-center justify-between px-3 py-1">
                        {/* Close run chip */}
                        <Tooltip
                          content={
                            shouldShowMismatch
                              ? `${selectedJobName} was not part of this run. Pick another job or deselect the run.`
                              : undefined
                          }
                          side="bottom"
                        >
                          <RunBadge
                            runId={followRunId}
                            onClose={handleClearFollowRun}
                            variant={shouldShowMismatch ? 'warning' : 'default'}
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
                        {/* Collapse button */}
                        <button
                          onClick={() => {
                            setIsRunPanelCollapsed(true);
                            rightPanelRef.current?.collapse();
                          }}
                          className="p-1 hover:bg-gray-100 rounded transition-colors ml-2"
                          aria-label="Collapse panel"
                          title="Collapse panel"
                        >
                          <ChevronRightIcon className="h-4 w-4 text-gray-500" />
                        </button>
                      </div>
                    </div>
                  )}

                  {/* Panel content */}
                  <div className="flex-1 overflow-hidden bg-white">
                    {panelState === 'run-viewer' && followRunId ? (
                      <RunViewerErrorBoundary>
                        <RunViewerPanel
                          followRunId={followRunId}
                          onClearFollowRun={handleClearFollowRun}
                          activeTab={activeRightTab}
                          onTabChange={setActiveRightTab}
                        />
                      </RunViewerErrorBoundary>
                    ) : panelState === 'history' ? (
                      <MiniHistory
                        variant="panel"
                        collapsed={false}
                        history={historyWithSelection}
                        onCollapseHistory={() => {}} // Not used in panel variant
                        selectRunHandler={handleHistoryRunSelect}
                        onDeselectRun={handleClearFollowRun}
                        selectedRun={selectedRun}
                        loading={historyLoading}
                        error={historyError}
                        onRetry={() => {
                          clearError();
                          void requestHistory();
                        }}
                        onBack={handleClosePanel}
                      />
                    ) : workflow && projectId && workflowId ? (
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
                          onClosePanel={handleClosePanel}
                          renderMode={RENDER_MODES.EMBEDDED}
                          saveWorkflow={saveWorkflow}
                          onRunSubmitted={handleRunSubmitted}
                          onTabChange={setSelectedTab}
                          onDataclipChange={handleDataclipChange}
                          onCustomBodyChange={setCustomBody}
                          selectedTab={selectedTab}
                          selectedDataclip={selectedDataclipState}
                          customBody={customBody}
                          disableAutoSelection
                        />
                      </ManualRunPanelErrorBoundary>
                    ) : null}
                  </div>
                </div>
              )}
            </Panel>
          )}
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
            onOpenAdaptorPicker={handleOpenAdaptorPickerFromConfigure}
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
            onClose={() => {
              setIsAdaptorPickerOpen(false);
              // Only return to configure modal if opened from there
              if (adaptorPickerFromConfigure) {
                setIsConfigureModalOpen(true);
              }
              setAdaptorPickerFromConfigure(false);
            }}
            onSelect={handleAdaptorSelect}
            projectAdaptors={projectAdaptors}
          />
        </>
      )}
    </div>
  );
}
