import { useMemo } from 'react';
import { HotkeysProvider } from 'react-hotkeys-hook';

import { SocketProvider } from '../react/contexts/SocketProvider';
import { useURLState } from '../react/lib/use-url-state';
import type { WithActionProps } from '../react/lib/with-props';

import { BreadcrumbLink, BreadcrumbText } from './components/Breadcrumbs';
import { Header } from './components/Header';
import { LoadingBoundary } from './components/LoadingBoundary';
import { Toaster } from './components/ui/Toaster';
import { VersionDebugLogger } from './components/VersionDebugLogger';
import { VersionDropdown } from './components/VersionDropdown';
import { WorkflowEditor } from './components/WorkflowEditor';
import { LiveViewActionsProvider } from './contexts/LiveViewActionsContext';
import { SessionProvider } from './contexts/SessionProvider';
import { StoreProvider } from './contexts/StoreProvider';
import {
  useLatestSnapshotLockVersion,
  useProject,
} from './hooks/useSessionContext';
import { useIsRunPanelOpen } from './hooks/useUI';
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
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  // Get run panel state for Header tooltip logic
  const isRunPanelOpen = useIsRunPanelOpen();

  // Detect IDE mode
  const { searchParams } = useURLState();
  const isIDEOpen = searchParams.get('panel') === 'editor';

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

  // Build breadcrumbs for Canvas mode only (IDE has its own breadcrumbs in FullScreenIDE)
  const breadcrumbElements = useMemo(() => {
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
    projectId,
    projectName,
    projectEnv,
    currentWorkflowName,
    workflowId,
    workflowFromStore?.lock_version,
    latestSnapshotLockVersion,
    handleVersionSelect,
  ]);

  return (
    <>
      {/* Only render Header for Canvas mode - IDE mode has its own Header in FullScreenIDE */}
      {!isIDEOpen && (
        <Header
          key="canvas-header"
          {...(projectId !== undefined && { projectId })}
          workflowId={workflowId}
          isRunPanelOpen={isRunPanelOpen}
        >
          {breadcrumbElements}
        </Header>
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
    <KeyboardProvider>
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
    </KeyboardProvider>
  );
};
