import { useMemo, useRef } from 'react';

import { useURLState } from '#/react/lib/use-url-state';
import { cn } from '#/utils/cn';

import { SocketProvider } from '../react/contexts/SocketProvider';
import type { WithActionProps } from '../react/lib/with-props';

import { AIAssistantPanelWrapper } from './components/AIAssistantPanelWrapper';
import {
  BreadcrumbLink,
  BreadcrumbProjectPicker,
  BreadcrumbText,
} from './components/Breadcrumbs';
import type { MonacoHandle } from './components/CollaborativeMonaco';
import { Header } from './components/Header';
import { LoadingBoundary } from './components/LoadingBoundary';
import { Toaster } from './components/ui/Toaster';
import { VersionDebugLogger } from './components/VersionDebugLogger';
import { VersionDropdown } from './components/VersionDropdown';
import { WorkflowEditor } from './components/WorkflowEditor';
import { CredentialModalProvider } from './contexts/CredentialModalContext';
import { LiveViewActionsProvider } from './contexts/LiveViewActionsContext';
import { MonacoRefProvider } from './contexts/MonacoRefContext';
import { SessionProvider } from './contexts/SessionProvider';
import { StoreProvider } from './contexts/StoreProvider';
import {
  useLatestSnapshotLockVersion,
  useProject,
} from './hooks/useSessionContext';
import { useIDEFullscreen, useIsRunPanelOpen } from './hooks/useUI';
import { useVersionSelect } from './hooks/useVersionSelect';
import { useWorkflowState } from './hooks/useWorkflow';
import { KeyboardProvider } from './keyboard';

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
  // Initial run data from server to avoid client-side race conditions
  'data-initial-run-data'?: string; // JSON-encoded RunStepsData
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
  isNewWorkflow?: boolean;
}

function BreadcrumbContent({
  workflowId,
  workflowName,
  projectIdFallback,
  projectNameFallback,
  projectEnvFallback,
  isNewWorkflow = false,
}: BreadcrumbContentProps) {
  const projectFromStore = useProject();

  const workflowFromStore = useWorkflowState(state => state.workflow);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  const isRunPanelOpen = useIsRunPanelOpen();
  const isIDEFullscreen = useIDEFullscreen();

  const { params } = useURLState();
  const isIDEOpen = params['panel'] === 'editor';

  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;
  const projectEnv = projectFromStore?.env ?? projectEnvFallback;
  const currentWorkflowName = workflowFromStore?.name ?? workflowName;

  const handleVersionSelect = useVersionSelect();

  const handleProjectPickerClick = (e: React.MouseEvent) => {
    e.preventDefault();
    // Dispatch the event that the global ProjectPicker listens for
    document.body.dispatchEvent(new CustomEvent('open-project-picker'));
  };

  const breadcrumbElements = useMemo(() => {
    return [
      // Project name as picker trigger
      <BreadcrumbProjectPicker
        key="project-picker"
        onClick={handleProjectPickerClick}
      >
        {projectName}
      </BreadcrumbProjectPicker>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="workflows">
        Workflows
      </BreadcrumbLink>,
      <div key="workflow" className="flex items-center gap-2">
        <BreadcrumbText>{currentWorkflowName}</BreadcrumbText>
        <div className="flex items-center gap-1.5">
          {!isNewWorkflow && (
            <VersionDropdown
              currentVersion={workflowFromStore?.lock_version ?? null}
              latestVersion={latestSnapshotLockVersion}
              onVersionSelect={handleVersionSelect}
            />
          )}
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
    projectId,
    projectName,
    projectEnv,
    currentWorkflowName,
    workflowId,
    workflowFromStore?.lock_version,
    latestSnapshotLockVersion,
    handleVersionSelect,
  ]);

  // Animate header hide/show when IDE fullscreen mode changes
  const isHeaderHidden = isIDEFullscreen && isIDEOpen;

  return (
    <div
      className={cn(
        'overflow-hidden transition-[max-height,opacity] duration-200',
        isHeaderHidden ? 'max-h-0 opacity-0' : 'max-h-32 opacity-100'
      )}
    >
      <Header
        key="canvas-header"
        {...(projectId !== undefined && { projectId })}
        workflowId={workflowId}
        isRunPanelOpen={isRunPanelOpen}
        isIDEOpen={isIDEOpen}
      >
        {breadcrumbElements}
      </Header>
    </div>
  );
}

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = props => {
  const workflowId = props['data-workflow-id'];
  const workflowName = props['data-workflow-name'];
  const projectId = props['data-project-id'];
  const projectName = props['data-project-name'];
  const projectEnv = props['data-project-env'];
  const rootProjectId = props['data-root-project-id'] ?? null;
  const rootProjectName = props['data-root-project-name'] ?? null;
  const isNewWorkflow = props['data-is-new-workflow'] === 'true';
  const initialRunData = props['data-initial-run-data'];

  const liveViewActions = {
    pushEvent: props.pushEvent,
    pushEventTo: props.pushEventTo,
    handleEvent: props.handleEvent,
    navigate: props.navigate,
  };

  // Monaco ref for diff preview - shared between FullScreenIDE and AIAssistantPanelWrapper
  const monacoRef = useRef<MonacoHandle>(null);

  return (
    <KeyboardProvider>
      <div
        className="collaborative-editor h-full flex relative"
        data-testid="collaborative-editor"
      >
        <SocketProvider>
          <SessionProvider
            workflowId={workflowId}
            projectId={projectId}
            isNewWorkflow={isNewWorkflow}
            {...(initialRunData !== undefined && { initialRunData })}
          >
            <StoreProvider>
              <LiveViewActionsProvider actions={liveViewActions}>
                <CredentialModalProvider>
                  <MonacoRefProvider monacoRef={monacoRef}>
                    <VersionDebugLogger />
                    <Toaster />
                    <div className="flex-1 min-h-0 overflow-hidden flex flex-col relative">
                      <BreadcrumbContent
                        workflowId={workflowId}
                        workflowName={workflowName}
                        isNewWorkflow={isNewWorkflow}
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
                      <div className="flex-1 min-h-0 overflow-hidden relative">
                        <LoadingBoundary>
                          <div className="h-full w-full">
                            <WorkflowEditor
                              parentProjectId={rootProjectId}
                              parentProjectName={rootProjectName}
                            />
                          </div>
                        </LoadingBoundary>
                      </div>
                    </div>
                    <AIAssistantPanelWrapper />
                  </MonacoRefProvider>
                </CredentialModalProvider>
              </LiveViewActionsProvider>
            </StoreProvider>
          </SessionProvider>
        </SocketProvider>
      </div>
    </KeyboardProvider>
  );
};
