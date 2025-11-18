import { useCallback, useMemo, useState } from 'react';
import { HotkeysProvider } from 'react-hotkeys-hook';

import { SocketProvider } from '../react/contexts/SocketProvider';
import { useURLState } from '../react/lib/use-url-state';
import type { WithActionProps } from '../react/lib/with-props';

import { AdaptorDisplay } from './components/AdaptorDisplay';
import { AdaptorSelectionModal } from './components/AdaptorSelectionModal';
import { BreadcrumbLink, BreadcrumbText } from './components/Breadcrumbs';
import { ConfigureAdaptorModal } from './components/ConfigureAdaptorModal';
import { Header } from './components/Header';
import { JobSelector } from './components/JobSelector';
import { LoadingBoundary } from './components/LoadingBoundary';
import { Toaster } from './components/ui/Toaster';
import { VersionDebugLogger } from './components/VersionDebugLogger';
import { VersionDropdown } from './components/VersionDropdown';
import { WorkflowEditor } from './components/WorkflowEditor';
import { HOTKEY_SCOPES } from './constants/hotkeys';
import { LiveViewActionsProvider } from './contexts/LiveViewActionsContext';
import { SessionProvider } from './contexts/SessionProvider';
import { StoreProvider } from './contexts/StoreProvider';
import { useProjectAdaptors } from './hooks/useAdaptors';
import { useCredentials, useCredentialsCommands } from './hooks/useCredentials';
import { useLiveViewActions } from './contexts/LiveViewActionsContext';
import { useRunRetry } from './hooks/useRunRetry';
import { useRunRetryShortcuts } from './hooks/useRunRetryShortcuts';
import {
  useLatestSnapshotLockVersion,
  useProject,
} from './hooks/useSessionContext';
import { useIsRunPanelOpen } from './hooks/useUI';
import { useVersionSelect } from './hooks/useVersionSelect';
import {
  useCanRun,
  useCanSave,
  useCurrentJob,
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
} from './hooks/useWorkflow';
import { notifications } from './lib/notifications';
import type { Job } from './types/job';

export interface CollaborativeEditorDataProps {
  'data-workflow-id': string;
  'data-workflow-name': string;
  'data-project-id': string;
  'data-project-name'?: string;
  'data-project-color'?: string;
  'data-project-env'?: string;
  'data-root-project-id'?: string;
  'data-root-project-name'?: string;
  'data-is-new-workflow'?: string;
}

/**
 * BreadcrumbContent Component
 *
 * Internal component that renders breadcrumbs with store-first, props-fallback pattern.
 * This component must be inside StoreProvider to access sessionContextStore.
 *
 * Migration Strategy:
 * - Tries to get project data from sessionContextStore first
 * - Falls back to props if store data not yet available
 * - This ensures breadcrumbs work during migration and server-side rendering
 * - Eventually props can be removed when all project data flows through store
 */
interface BreadcrumbContentProps {
  workflowId: string;
  workflowName: string;
  projectIdFallback?: string;
  projectNameFallback?: string;
  projectEnvFallback?: string;
}

function BreadcrumbContent({
  workflowId,
  workflowName,
  projectIdFallback,
  projectNameFallback,
  projectEnvFallback,
}: BreadcrumbContentProps) {
  // Get project from store (may be null if not yet loaded)
  const projectFromStore = useProject();

  // Get workflow from store to read the current name
  const workflowFromStore = useWorkflowState(state => state.workflow);
  const workflowEdges = useWorkflowState(state => state.edges);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  // Get run panel state for Header tooltip logic
  const isRunPanelOpen = useIsRunPanelOpen();

  // Detect IDE mode
  const { searchParams, updateSearchParams } = useURLState();
  const isIDEOpen = searchParams.get('panel') === 'editor';
  const jobIdFromURL = searchParams.get('job');

  // Store-first with props-fallback pattern
  // This ensures breadcrumbs work during:
  // 1. Initial server-side render (uses props)
  // 2. Store hydration period (uses props)
  // 3. Full collaborative mode (uses store)
  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;
  const projectEnv = projectFromStore?.env ?? projectEnvFallback;
  const currentWorkflowName = workflowFromStore?.name ?? workflowName;

  // Use shared version selection handler (destroys Y.Doc before switching)
  const handleVersionSelect = useVersionSelect();

  // IDE-specific hooks and state
  const { selectNode } = useNodeSelection();
  const { job: currentJob } = useCurrentJob();
  const allJobs = useWorkflowState(state => state.jobs);
  const { canSave } = useCanSave();
  const { saveWorkflow } = useWorkflowActions();
  const snapshotVersion = workflowFromStore?.lock_version;

  // IDE-specific: Handle job selection from JobSelector
  const handleJobSelect = useCallback(
    (job: Job) => {
      updateSearchParams({ job: job.id });
      selectNode(job.id);
    },
    [updateSearchParams, selectNode]
  );

  // IDE-specific: Handle close IDE
  const handleCloseIDE = useCallback(() => {
    updateSearchParams({ panel: null, job: null });
  }, [updateSearchParams]);

  // IDE-specific: Handle run submission (stay in IDE, update URL to follow run)
  const handleRunSubmitted = useCallback(
    (runId: string) => {
      updateSearchParams({ run: runId });
    },
    [updateSearchParams]
  );

  // IDE-specific: Modal state for adaptor/credential configuration
  const [isConfigureModalOpen, setIsConfigureModalOpen] = useState(false);
  const [isAdaptorPickerOpen, setIsAdaptorPickerOpen] = useState(false);

  // IDE-specific: Get adaptors and credentials for modals
  const { projectAdaptors, allAdaptors } = useProjectAdaptors();
  const { projectCredentials, keychainCredentials } = useCredentials();
  const { requestCredentials } = useCredentialsCommands();
  const { pushEvent } = useLiveViewActions();
  const { updateJob } = useWorkflowActions();

  // Helper function to parse adaptor strings
  const resolveAdaptor = useCallback((adaptor: string | null | undefined) => {
    if (!adaptor) return { package: null, version: null };
    const regex = /^(@[^@]+)@(.+)$/;
    const match = adaptor.match(regex);
    if (!match) return { package: null, version: null };
    const [, packageName, version] = match;
    return {
      package: packageName || null,
      version: version || null,
    };
  }, []);

  // IDE-specific: Handle adaptor changes
  const handleAdaptorChange = useCallback(
    (adaptorPackage: string) => {
      if (!currentJob) return;
      const currentVersion =
        resolveAdaptor(currentJob.adaptor).version || 'latest';
      const newAdaptor = `${adaptorPackage}@${currentVersion}`;
      updateJob(currentJob.id, { adaptor: newAdaptor });
      notifications.success({
        title: 'Adaptor updated',
        description: `Changed to ${adaptorPackage}`,
      });
    },
    [currentJob, updateJob, resolveAdaptor]
  );

  const handleVersionChange = useCallback(
    (version: string) => {
      if (!currentJob) return;
      const currentPackage =
        resolveAdaptor(currentJob.adaptor).package || '@openfn/language-common';
      const newAdaptor = `${currentPackage}@${version}`;
      updateJob(currentJob.id, { adaptor: newAdaptor });
      notifications.success({
        title: 'Version updated',
        description: `Changed to ${version}`,
      });
    },
    [currentJob, updateJob, resolveAdaptor]
  );

  const handleCredentialChange = useCallback(
    (credentialId: string | null) => {
      if (!currentJob) return;
      // Determine credential type based on whether it matches project or keychain credentials
      const isProjectCredential = projectCredentials.some(
        c => c.id === credentialId
      );
      if (isProjectCredential) {
        updateJob(currentJob.id, {
          project_credential_id: credentialId,
          keychain_credential_id: null,
        });
      } else {
        updateJob(currentJob.id, {
          keychain_credential_id: credentialId,
          project_credential_id: null,
        });
      }
    },
    [currentJob, updateJob, projectCredentials]
  );

  const handleAdaptorSelect = useCallback(
    (selectedAdaptor: string) => {
      if (!currentJob) return;
      updateJob(currentJob.id, { adaptor: selectedAdaptor });
      setIsAdaptorPickerOpen(false);
      notifications.success({
        title: 'Adaptor selected',
        description: `Changed to ${selectedAdaptor}`,
      });
    },
    [currentJob, updateJob]
  );

  const handleOpenAdaptorPicker = useCallback(() => {
    setIsConfigureModalOpen(false);
    setIsAdaptorPickerOpen(true);
  }, []);

  const handleOpenCredentialModal = useCallback(
    (adaptorName: string) => {
      setIsConfigureModalOpen(false);
      if (pushEvent) {
        pushEvent('open_credential_modal', { schema: adaptorName });
      }
    },
    [pushEvent]
  );

  // IDE-specific: Run/retry functionality
  const { canRun: canRunSnapshot, tooltipMessage: runTooltipMessage } =
    useCanRun();

  const runContext = useMemo(
    () => ({
      type: 'job' as const,
      id: jobIdFromURL || '',
    }),
    [jobIdFromURL]
  );

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
    selectedTab: 'empty',
    selectedDataclip: null,
    customBody: '',
    canRunWorkflow: canRunSnapshot,
    workflowRunTooltipMessage: runTooltipMessage,
    saveWorkflow,
    onRunSubmitted: isIDEOpen ? handleRunSubmitted : undefined,
    edgeId: null,
    workflowEdges: workflowEdges || [],
  });

  // IDE-specific: Enable run/retry keyboard shortcuts
  useRunRetryShortcuts({
    onRun: handleRun,
    onRetry: handleRetry,
    canRun:
      canRunSnapshot && canRunFromHook && !isSubmitting && !runIsProcessing,
    isRunning: isSubmitting || runIsProcessing,
    isRetryable,
    scope: HOTKEY_SCOPES.IDE,
    enableOnContentEditable: true,
    enabled: isIDEOpen,
  });

  // Build breadcrumbs based on context (Canvas vs IDE)
  const breadcrumbElements = useMemo(() => {
    if (isIDEOpen && currentJob) {
      // IDE mode: Projects > Project > Workflows > Workflow > Job
      return [
        <BreadcrumbLink href="/projects" key="projects">
          Projects
        </BreadcrumbLink>,
        <BreadcrumbLink href={`/projects/${projectId}/w`} key="project">
          {projectName}
        </BreadcrumbLink>,
        <BreadcrumbLink href={`/projects/${projectId}/w`} key="workflows">
          Workflows
        </BreadcrumbLink>,
        <BreadcrumbLink onClick={handleCloseIDE} key="workflow-name">
          {currentWorkflowName}
        </BreadcrumbLink>,
        <JobSelector
          key="job-selector"
          currentJob={currentJob}
          jobs={allJobs}
          onChange={handleJobSelect}
        />,
      ];
    }

    // Canvas mode: Projects > Project > Workflows > Workflow (with version dropdown)
    return [
      <BreadcrumbLink href="/projects" key="projects">
        Projects
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="project">
        {projectName}
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="workflows">
        Workflows
      </BreadcrumbLink>,
      <div key="workflow" className="flex items-center gap-2">
        <BreadcrumbText>{currentWorkflowName}</BreadcrumbText>
        <div className="flex items-center gap-1.5">
          <VersionDropdown
            currentVersion={workflowFromStore?.lock_version ?? null}
            latestVersion={latestSnapshotLockVersion}
            onVersionSelect={handleVersionSelect}
          />
          {projectEnv && (
            <div
              id="canvas-project-env-container"
              className="flex items-middle text-sm font-normal"
            >
              <span
                id="canvas-project-env"
                className="inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium bg-primary-100 text-primary-800"
                title={`Project environment is ${projectEnv}`}
              >
                {projectEnv}
              </span>
            </div>
          )}
        </div>
      </div>,
    ];
  }, [
    isIDEOpen,
    currentJob,
    allJobs,
    projectId,
    projectName,
    projectEnv,
    currentWorkflowName,
    workflowId,
    workflowFromStore?.lock_version,
    latestSnapshotLockVersion,
    handleVersionSelect,
    handleJobSelect,
    handleCloseIDE,
  ]);

  // Build adaptor display for IDE mode
  const adaptorDisplayElement = useMemo(() => {
    if (!isIDEOpen || !currentJob) return undefined;

    return (
      <div className="flex items-center gap-2">
        <AdaptorDisplay
          adaptor={currentJob.adaptor || '@openfn/language-common@latest'}
          credentialId={
            currentJob.project_credential_id ||
            currentJob.keychain_credential_id ||
            null
          }
          size="sm"
          onEdit={() => setIsConfigureModalOpen(true)}
          onChangeAdaptor={() => setIsAdaptorPickerOpen(true)}
          isReadOnly={!canSave}
        />
        <VersionDropdown
          currentVersion={snapshotVersion ?? null}
          latestVersion={latestSnapshotLockVersion}
          onVersionSelect={handleVersionSelect}
        />
      </div>
    );
  }, [
    isIDEOpen,
    currentJob,
    canSave,
    snapshotVersion,
    latestSnapshotLockVersion,
    handleVersionSelect,
  ]);

  return (
    <>
      <Header
        {...(projectId !== undefined && { projectId })}
        workflowId={workflowId}
        isRunPanelOpen={isRunPanelOpen}
        {...(isIDEOpen &&
          adaptorDisplayElement && { adaptorDisplay: adaptorDisplayElement })}
        {...(isIDEOpen && {
          onRunClick: isRetryable ? handleRetry : handleRun,
          canRun:
            canRunSnapshot &&
            canRunFromHook &&
            !isSubmitting &&
            !runIsProcessing,
          runTooltipMessage: runTooltipMessage,
        })}
      >
        {breadcrumbElements}
      </Header>

      {/* IDE Modals - only render when IDE is open */}
      {isIDEOpen && currentJob && (
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
              resolveAdaptor(currentJob.adaptor).package ||
              '@openfn/language-common'
            }
            currentVersion={
              resolveAdaptor(currentJob.adaptor).version || 'latest'
            }
            currentCredentialId={
              currentJob.project_credential_id ||
              currentJob.keychain_credential_id ||
              null
            }
            allAdaptors={allAdaptors}
          />

          <AdaptorSelectionModal
            projectAdaptors={projectAdaptors}
            isOpen={isAdaptorPickerOpen}
            onClose={() => setIsAdaptorPickerOpen(false)}
            onSelect={handleAdaptorSelect}
          />
        </>
      )}
    </>
  );
}

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = props => {
  // Extract data from props (ReactComponent hook passes data attributes as props)
  const workflowId = props['data-workflow-id'];
  const workflowName = props['data-workflow-name'];
  // Migration: Props are now fallbacks, sessionContextStore is primary source
  const projectId = props['data-project-id'];
  const projectName = props['data-project-name'];
  const projectEnv = props['data-project-env'];
  const rootProjectId = props['data-root-project-id'] ?? null;
  const rootProjectName = props['data-root-project-name'] ?? null;
  const isNewWorkflow = props['data-is-new-workflow'] === 'true';

  // Extract LiveView actions from props
  const liveViewActions = {
    pushEvent: props.pushEvent,
    pushEventTo: props.pushEventTo,
    handleEvent: props.handleEvent,
    navigate: props.navigate,
  };

  return (
    <HotkeysProvider>
      <div
        className="collaborative-editor h-full flex flex-col"
        data-testid="collaborative-editor"
      >
        <SocketProvider>
          <SessionProvider
            workflowId={workflowId}
            projectId={projectId}
            isNewWorkflow={isNewWorkflow}
          >
            <StoreProvider>
              <LiveViewActionsProvider actions={liveViewActions}>
                <VersionDebugLogger />
                <Toaster />
                <BreadcrumbContent
                  workflowId={workflowId}
                  workflowName={workflowName}
                  {...(projectId !== undefined && {
                    projectIdFallback: projectId,
                  })}
                  {...(projectName !== undefined && {
                    projectNameFallback: projectName,
                  })}
                  {...(projectEnv !== undefined && {
                    projectEnvFallback: projectEnv,
                  })}
                  {...(rootProjectId !== null && {
                    rootProjectIdFallback: rootProjectId,
                  })}
                  {...(rootProjectName !== null && {
                    rootProjectNameFallback: rootProjectName,
                  })}
                />
                <LoadingBoundary>
                  <div className="flex-1 min-h-0 overflow-hidden">
                    <WorkflowEditor
                      {...(rootProjectId !== null && {
                        parentProjectId: rootProjectId,
                      })}
                      {...(rootProjectName !== null && {
                        parentProjectName: rootProjectName,
                      })}
                    />
                  </div>
                </LoadingBoundary>
              </LiveViewActionsProvider>
            </StoreProvider>
          </SessionProvider>
        </SocketProvider>
      </div>
    </HotkeysProvider>
  );
};
