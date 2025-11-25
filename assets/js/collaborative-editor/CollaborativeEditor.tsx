import { useMemo, useState, useRef, useEffect, useCallback } from 'react';
import { HotkeysProvider } from 'react-hotkeys-hook';
import YAML from 'yaml';

import { SocketProvider } from '../react/contexts/SocketProvider';
import { useURLState } from '../react/lib/use-url-state';
import type { WithActionProps } from '../react/lib/with-props';
import { convertWorkflowStateToSpec } from '../yaml/util';

import { AIAssistantPanel } from './components/AIAssistantPanel';
import { MessageList } from './components/MessageList';
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
  useAIIsLoading,
  useAIMessages,
  useAISessionId,
  useAIStore,
} from './hooks/useAIAssistant';
import { useAIMode } from './hooks/useAIMode';
import { useAIAssistantChannel } from './hooks/useAIAssistantChannel';
import {
  useLatestSnapshotLockVersion,
  useProject,
} from './hooks/useSessionContext';
import {
  useIsAIAssistantPanelOpen,
  useIsRunPanelOpen,
  useUICommands,
} from './hooks/useUI';
import { useVersionSelect } from './hooks/useVersionSelect';
import { useWorkflowState } from './hooks/useWorkflow';

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
 * AIAssistantPanelWrapper Component
 *
 * Wrapper for AI Assistant panel that accesses UI store state.
 * Must be inside StoreProvider to access uiStore.
 *
 * Features:
 * - Smooth CSS animations when opening/closing
 * - Draggable resize handle
 * - Persists width in localStorage
 * - Syncs open/closed state with URL query param (?chat=true)
 */
function AIAssistantPanelWrapper() {
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();
  const { closeAIAssistantPanel } = useUICommands();
  const { updateSearchParams } = useURLState();

  // AI Assistant integration
  const aiStore = useAIStore();
  const { sendMessage: sendMessageToChannel } = useAIAssistantChannel(aiStore);
  const messages = useAIMessages();
  const isLoading = useAIIsLoading();
  const sessionId = useAISessionId();
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);

  // Get workflow data for YAML serialization
  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  const edges = useWorkflowState(state => state.edges);
  const positions = useWorkflowState(state => state.positions);

  const [width, setWidth] = useState(() => {
    const saved = localStorage.getItem('ai-assistant-panel-width');
    return saved ? parseInt(saved, 10) : 400;
  });
  const [isResizing, setIsResizing] = useState(false);
  const startXRef = useRef<number>(0);
  const startWidthRef = useRef<number>(0);
  const isSyncingRef = useRef(false);

  // Sync store state to URL
  useEffect(() => {
    if (isSyncingRef.current) return;

    isSyncingRef.current = true;
    updateSearchParams({
      chat: isAIAssistantPanelOpen ? 'true' : null,
    });
    setTimeout(() => {
      isSyncingRef.current = false;
    }, 0);
  }, [isAIAssistantPanelOpen, updateSearchParams]);

  useEffect(() => {
    if (!isResizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = startXRef.current - e.clientX;
      const newWidth = Math.max(
        300,
        Math.min(800, startWidthRef.current + deltaX)
      );
      setWidth(newWidth);
    };

    const handleMouseUp = () => {
      setIsResizing(false);
      localStorage.setItem('ai-assistant-panel-width', width.toString());
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isResizing, width]);

  const handleMouseDown = (e: React.MouseEvent) => {
    e.preventDefault();
    setIsResizing(true);
    startXRef.current = e.clientX;
    startWidthRef.current = width;
  };

  // Detect current AI mode (job_code or workflow_template)
  const aiMode = useAIMode();

  // Connect to AI when panel opens or mode changes
  useEffect(() => {
    if (!isAIAssistantPanelOpen || !aiMode) return;

    const state = aiStore.getSnapshot();
    const { mode, context, storageKey } = aiMode;

    // Check if we need to switch modes
    const needsModeSwitch = state.sessionType !== mode;

    if (needsModeSwitch) {
      // Disconnect from current session
      if (state.connectionState !== 'disconnected') {
        console.log('[AI Assistant] Switching mode:', {
          from: state.sessionType,
          to: mode,
        });
        aiStore.disconnect();
      }

      // Load stored session for new mode
      const storedSessionId = localStorage.getItem(storageKey);

      // Add workflow YAML for workflow_template mode
      let finalContext = context;
      if (mode === 'workflow_template' && workflow && jobs.length > 0) {
        try {
          const workflowSpec = convertWorkflowStateToSpec(
            {
              id: workflow.id,
              name: workflow.name,
              jobs: jobs.map(job => ({
                id: job.id,
                name: job.name,
                adaptor: job.adaptor,
                body: job.body,
              })),
              triggers: triggers,
              edges: edges.map(edge => ({
                id: edge.id,
                condition_type: edge.condition_type || 'always',
                enabled: edge.enabled !== false,
                target_job_id: edge.target_job_id,
                ...(edge.source_job_id && {
                  source_job_id: edge.source_job_id,
                }),
                ...(edge.source_trigger_id && {
                  source_trigger_id: edge.source_trigger_id,
                }),
                ...(edge.condition_label && {
                  condition_label: edge.condition_label,
                }),
                ...(edge.condition_expression && {
                  condition_expression: edge.condition_expression,
                }),
              })),
              positions: positions,
            },
            false
          );
          const workflowYAML = YAML.stringify(workflowSpec);
          finalContext = { ...context, code: workflowYAML };
        } catch (error) {
          console.error('Failed to serialize workflow to YAML:', error);
        }
      }

      // Connect with new mode and context
      aiStore.connect(mode, finalContext, storedSessionId || undefined);
    } else if (state.connectionState === 'disconnected') {
      // Not switching modes, but disconnected - reconnect with same mode
      const storedSessionId = localStorage.getItem(storageKey);
      aiStore.connect(mode, context, storedSessionId || undefined);
    }
  }, [
    isAIAssistantPanelOpen,
    aiMode,
    workflow,
    jobs,
    triggers,
    edges,
    positions,
    aiStore,
  ]);

  // Disconnect when panel closes
  useEffect(() => {
    if (!isAIAssistantPanelOpen) {
      aiStore.disconnect();
    }
  }, [isAIAssistantPanelOpen, aiStore]);

  // Handler for starting a new conversation
  const handleNewConversation = useCallback(() => {
    if (!project) return;

    // Clear the current session
    aiStore.clearSession();

    // Disconnect and reconnect to create a new session
    aiStore.disconnect();

    // The useEffect above will reconnect automatically when panel reopens
    // For now, just manually trigger reconnect after a brief delay
    setTimeout(() => {
      const state = aiStore.getSnapshot();
      if (state.connectionState === 'disconnected') {
        // Build fresh context
        let workflowYAML: string | undefined = undefined;
        if (workflow && jobs.length > 0) {
          try {
            const workflowSpec = convertWorkflowStateToSpec(
              {
                id: workflow.id,
                name: workflow.name,
                jobs: jobs.map(job => ({
                  id: job.id,
                  name: job.name,
                  adaptor: job.adaptor,
                  body: job.body,
                })),
                triggers: triggers,
                edges: edges.map(edge => ({
                  id: edge.id,
                  condition_type: edge.condition_type || 'always',
                  enabled: edge.enabled !== false,
                  target_job_id: edge.target_job_id,
                  ...(edge.source_job_id && {
                    source_job_id: edge.source_job_id,
                  }),
                  ...(edge.source_trigger_id && {
                    source_trigger_id: edge.source_trigger_id,
                  }),
                  ...(edge.condition_label && {
                    condition_label: edge.condition_label,
                  }),
                  ...(edge.condition_expression && {
                    condition_expression: edge.condition_expression,
                  }),
                })),
                positions: positions,
              },
              false
            );
            workflowYAML = YAML.stringify(workflowSpec);
          } catch (error) {
            console.error('Failed to serialize workflow to YAML:', error);
          }
        }

        const context = {
          project_id: project.id,
          ...(workflow?.id && { workflow_id: workflow.id }),
          ...(workflowYAML && { code: workflowYAML }),
        };

        // Connect with NO session ID to force creation of new session
        aiStore.connect('workflow_template', context);
      }
    }, 100);
  }, [aiStore, workflow, jobs, triggers, edges, positions, project]);

  // Handler for loading an existing session
  const handleSessionSelect = useCallback(
    (selectedSessionId: string) => {
      if (!project) return;

      // Load the selected session by triggering reconnection
      aiStore.loadSession(selectedSessionId);

      // Disconnect and reconnect with the selected session ID
      aiStore.disconnect();

      setTimeout(() => {
        const state = aiStore.getSnapshot();
        if (state.connectionState === 'disconnected') {
          // Build context for reconnection
          let workflowYAML: string | undefined = undefined;
          if (workflow && jobs.length > 0) {
            try {
              const workflowSpec = convertWorkflowStateToSpec(
                {
                  id: workflow.id,
                  name: workflow.name,
                  jobs: jobs.map(job => ({
                    id: job.id,
                    name: job.name,
                    adaptor: job.adaptor,
                    body: job.body,
                  })),
                  triggers: triggers,
                  edges: edges.map(edge => ({
                    id: edge.id,
                    condition_type: edge.condition_type || 'always',
                    enabled: edge.enabled !== false,
                    target_job_id: edge.target_job_id,
                    ...(edge.source_job_id && {
                      source_job_id: edge.source_job_id,
                    }),
                    ...(edge.source_trigger_id && {
                      source_trigger_id: edge.source_trigger_id,
                    }),
                    ...(edge.condition_label && {
                      condition_label: edge.condition_label,
                    }),
                    ...(edge.condition_expression && {
                      condition_expression: edge.condition_expression,
                    }),
                  })),
                  positions: positions,
                },
                false
              );
              workflowYAML = YAML.stringify(workflowSpec);
            } catch (error) {
              console.error('Failed to serialize workflow to YAML:', error);
            }
          }

          const context = {
            project_id: project.id,
            ...(workflow?.id && { workflow_id: workflow.id }),
            ...(workflowYAML && { code: workflowYAML }),
          };

          // Reconnect with the selected session ID
          aiStore.connect('workflow_template', context, selectedSessionId);
        }
      }, 100);
    },
    [aiStore, project, workflow, jobs, triggers, edges, positions]
  );

  // Wrapper function to send messages with workflow code
  const sendMessage = useCallback(
    (content: string) => {
      // Generate current workflow YAML
      let workflowYAML: string | undefined = undefined;
      if (workflow && jobs.length > 0) {
        try {
          const workflowSpec = convertWorkflowStateToSpec(
            {
              id: workflow.id,
              name: workflow.name,
              jobs: jobs.map(job => ({
                id: job.id,
                name: job.name,
                adaptor: job.adaptor,
                body: job.body,
              })),
              triggers: triggers,
              edges: edges.map(edge => ({
                id: edge.id,
                condition_type: edge.condition_type || 'always',
                enabled: edge.enabled !== false,
                target_job_id: edge.target_job_id,
                ...(edge.source_job_id && {
                  source_job_id: edge.source_job_id,
                }),
                ...(edge.source_trigger_id && {
                  source_trigger_id: edge.source_trigger_id,
                }),
                ...(edge.condition_label && {
                  condition_label: edge.condition_label,
                }),
                ...(edge.condition_expression && {
                  condition_expression: edge.condition_expression,
                }),
              })),
              positions: positions,
            },
            false // Don't include IDs in YAML
          );
          workflowYAML = YAML.stringify(workflowSpec);
        } catch (error) {
          console.error('Failed to serialize workflow to YAML:', error);
        }
      }

      // Send message with workflow code
      const options = workflowYAML ? { code: workflowYAML } : undefined;
      sendMessageToChannel(content, options);
    },
    [workflow, jobs, triggers, edges, positions, sendMessageToChannel]
  );

  return (
    <div
      className="flex h-full flex-shrink-0"
      style={{
        width: isAIAssistantPanelOpen ? `${width}px` : '0px',
        transition: isResizing
          ? 'none'
          : 'width 0.4s cubic-bezier(0.4, 0, 0.2, 1)',
      }}
    >
      {isAIAssistantPanelOpen && (
        <>
          <div
            className="w-1 bg-gray-200 hover:bg-blue-400 transition-colors cursor-col-resize flex-shrink-0"
            onMouseDown={handleMouseDown}
          />
          <div className="flex-1 overflow-hidden">
            <AIAssistantPanel
              isOpen={isAIAssistantPanelOpen}
              onClose={closeAIAssistantPanel}
              onNewConversation={handleNewConversation}
              onSessionSelect={handleSessionSelect}
              onSendMessage={sendMessage}
              sessionId={sessionId}
              messageCount={messages.length}
              isLoading={isLoading}
              isResizable={true}
              store={aiStore}
            >
              <MessageList messages={messages} />
            </AIAssistantPanel>
          </div>
        </>
      )}
    </div>
  );
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
    <HotkeysProvider>
      <div
        className="collaborative-editor h-full flex"
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
                {/* Main content area - pushed by AI panel */}
                <div className="flex-1 min-h-0 h-full overflow-hidden flex flex-col">
                  {/* Breadcrumb bar at top */}
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
                  {/* Content area below breadcrumbs */}
                  <div className="flex-1 min-h-0 h-full overflow-hidden">
                    <LoadingBoundary>
                      <div className="h-full w-full">
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
                  </div>
                </div>
                {/* AI Assistant Panel - at root level, pushes everything */}
                <AIAssistantPanelWrapper />
              </LiveViewActionsProvider>
            </StoreProvider>
          </SessionProvider>
        </SocketProvider>
      </div>
    </HotkeysProvider>
  );
};
