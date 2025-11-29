import { useMemo, useState, useRef, useEffect, useCallback } from 'react';
import YAML from 'yaml';

import { SocketProvider } from '../react/contexts/SocketProvider';
import { useURLState } from '../react/lib/use-url-state';
import type { WithActionProps } from '../react/lib/with-props';
import {
  convertWorkflowStateToSpec,
  parseWorkflowYAML,
  convertWorkflowSpecToState,
} from '../yaml/util';

import { AIAssistantPanel } from './components/AIAssistantPanel';
import { MessageList } from './components/MessageList';
import { BreadcrumbLink, BreadcrumbText } from './components/Breadcrumbs';
import { Header } from './components/Header';
import { FullScreenIDE } from './components/ide/FullScreenIDE';
import { LoadingBoundary } from './components/LoadingBoundary';
import { Toaster } from './components/ui/Toaster';
import { VersionDebugLogger } from './components/VersionDebugLogger';
import { VersionDropdown } from './components/VersionDropdown';
import { WorkflowEditor } from './components/WorkflowEditor';
import { LiveViewActionsProvider } from './contexts/LiveViewActionsContext';
import { SessionProvider } from './contexts/SessionProvider';
import { StoreProvider } from './contexts/StoreProvider';
import {
  useAIConnectionState,
  useAIIsLoading,
  useAIMessages,
  useAISessionId,
  useAISessionType,
  useAIStore,
  useAIWorkflowTemplateContext,
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
import { useNodeSelection } from './hooks/useWorkflow';
import { useVersionSelect } from './hooks/useVersionSelect';
import { useWorkflowState, useWorkflowActions } from './hooks/useWorkflow';
import { useKeyboardShortcut, KeyboardProvider } from './keyboard';
import { notifications } from './lib/notifications';

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
  const { closeAIAssistantPanel, toggleAIAssistantPanel } = useUICommands();
  const { updateSearchParams, searchParams } = useURLState();

  useKeyboardShortcut(
    '$mod+k',
    () => {
      toggleAIAssistantPanel();
    },
    0
  );

  const aiStore = useAIStore();
  const {
    sendMessage: sendMessageToChannel,
    loadSessions,
    updateContext,
    retryMessage: retryMessageViaChannel,
  } = useAIAssistantChannel(aiStore);
  const messages = useAIMessages();
  const isLoading = useAIIsLoading();
  const sessionId = useAISessionId();
  const sessionType = useAISessionType();
  const connectionState = useAIConnectionState();
  const workflowTemplateContext = useAIWorkflowTemplateContext();
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);

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

  const aiMode = useAIMode();

  const prevModeRef = useRef<string | null>(null);
  const prevSessionIdRef = useRef<string | null>(null);
  const prevJobIdRef = useRef<string | null>(null);

  const sessionIdFromURL = useMemo(() => {
    if (!aiMode) return null;

    const paramName = aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const sessionId = searchParams.get(paramName);

    return sessionId;
  }, [aiMode, searchParams]);

  useEffect(() => {
    if (!isAIAssistantPanelOpen || !aiMode) return;

    const state = aiStore.getSnapshot();
    const { mode, context } = aiMode;

    const isModeSwitch = state.sessionType && state.sessionType !== mode;
    const jobIdChanged =
      mode === 'job_code' &&
      state.jobCodeContext &&
      (context as import('./types/ai-assistant').JobCodeContext).job_id !==
        state.jobCodeContext.job_id;

    if (isModeSwitch || jobIdChanged) {
      updateSearchParams({
        'w-chat': null,
        'j-chat': null,
      });
    }
  }, [isAIAssistantPanelOpen, aiMode, updateSearchParams, aiStore]);

  useEffect(() => {
    if (!isAIAssistantPanelOpen || !aiMode) {
      prevModeRef.current = null;
      prevSessionIdRef.current = null;
      prevJobIdRef.current = null;
      return;
    }

    const state = aiStore.getSnapshot();
    const { mode, context } = aiMode;

    const currentJobId =
      mode === 'job_code'
        ? (context as import('./types/ai-assistant').JobCodeContext).job_id
        : null;

    const modeChanged = prevModeRef.current !== mode;
    const sessionIdChanged = prevSessionIdRef.current !== sessionIdFromURL;
    const jobIdChangedFromPrev = prevJobIdRef.current !== currentJobId;

    if (
      !modeChanged &&
      !sessionIdChanged &&
      !jobIdChangedFromPrev &&
      prevModeRef.current !== null
    ) {
      return;
    }

    prevModeRef.current = mode;
    prevSessionIdRef.current = sessionIdFromURL;
    prevJobIdRef.current = currentJobId;

    // STEP 1: Check if we're switching modes (job ↔ workflow)
    const isModeSwitch = state.sessionType && state.sessionType !== mode;

    if (isModeSwitch) {
      if (state.connectionState !== 'disconnected') {
        aiStore.disconnect();
      }
      aiStore._clearSession();
      aiStore._clearSessionList();
    }

    // STEP 2: Initialize context for current mode
    // This MUST happen before any session loading
    const jobIdChanged =
      mode === 'job_code' &&
      state.jobCodeContext &&
      (context as import('./types/ai-assistant').JobCodeContext).job_id !==
        state.jobCodeContext.job_id;

    const needsContextInit =
      !state.sessionType ||
      (mode === 'job_code' && !state.jobCodeContext) ||
      (mode === 'workflow_template' && !state.workflowTemplateContext) ||
      jobIdChanged;

    if (needsContextInit || isModeSwitch) {
      if (jobIdChanged || isModeSwitch) {
        if (state.connectionState !== 'disconnected') {
          aiStore.disconnect();
        }
        aiStore._clearSession();
        aiStore._clearSessionList();
      }

      aiStore.connect(mode, context, undefined);
      aiStore.disconnect();
    }

    // STEP 3: Load session if there's one in URL, otherwise we're done
    // IMPORTANT: Don't load session from URL if job just changed - that session belongs to the old job
    if (!sessionIdFromURL || jobIdChanged) {
      return;
    }

    // STEP 4: Connect to the session from URL
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

    aiStore.connect(mode, finalContext, sessionIdFromURL);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    isAIAssistantPanelOpen,
    aiMode,
    aiStore,
    sessionIdFromURL,
    // NOTE: Intentionally NOT including workflow, jobs, triggers, edges, positions
    // We use refs (prevModeRef, prevSessionIdRef) to track actual changes
    // Including these would cause reconnections on every Y.js edit
  ]);

  useEffect(() => {
    if (!sessionId || !aiMode) return;

    const state = aiStore.getSnapshot();
    const sessionType = state.sessionType;

    // CRITICAL: Only sync to URL if session type matches current mode
    // This prevents syncing a workflow session ID to job mode URL (or vice versa)
    if (sessionType !== aiMode.mode) {
      return;
    }

    const currentParamName =
      aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const currentValue = searchParams.get(currentParamName);

    if (currentValue !== sessionId) {
      updateSearchParams({
        [currentParamName]: sessionId,
      });
    }
  }, [sessionId, aiMode, searchParams, updateSearchParams, aiStore]);

  useEffect(() => {
    if (!isAIAssistantPanelOpen) {
      aiStore.disconnect();
      updateSearchParams({
        'w-chat': null,
        'j-chat': null,
      });
    }
  }, [isAIAssistantPanelOpen, aiStore, updateSearchParams]);

  useEffect(() => {
    if (
      !isAIAssistantPanelOpen ||
      !aiMode ||
      aiMode.mode !== 'job_code' ||
      !sessionId
    ) {
      return;
    }

    const context =
      aiMode.context as import('./types/ai-assistant').JobCodeContext;

    const contextUpdate: {
      job_adaptor?: string;
      job_body?: string;
      job_name?: string;
    } = {};
    if (context.job_adaptor !== undefined)
      contextUpdate.job_adaptor = context.job_adaptor;
    if (context.job_body !== undefined)
      contextUpdate.job_body = context.job_body;
    if (context.job_name !== undefined)
      contextUpdate.job_name = context.job_name;

    updateContext(contextUpdate);
  }, [isAIAssistantPanelOpen, aiMode, sessionId, updateContext]);

  const handleNewConversation = useCallback(() => {
    if (!project) return;

    appliedMessageIdsRef.current.clear();
    aiStore.clearSession();
    aiStore.disconnect();

    setTimeout(() => {
      const state = aiStore.getSnapshot();
      if (state.connectionState === 'disconnected') {
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

        aiStore.connect('workflow_template', context);
      }
    }, 100);
  }, [aiStore, workflow, jobs, triggers, edges, positions, project]);

  const handleSessionSelect = useCallback(
    (selectedSessionId: string) => {
      if (!project) return;

      appliedMessageIdsRef.current.clear();

      aiStore._clearSession();

      aiStore.disconnect();

      setTimeout(() => {
        const state = aiStore.getSnapshot();
        if (state.connectionState === 'disconnected') {
          const currentSessionType = state.sessionType;

          if (!currentSessionType) {
            console.error(
              '[AI Assistant] No session type in store, cannot reconnect'
            );
            return;
          }

          let context: any;

          if (currentSessionType === 'workflow_template') {
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

            context = {
              project_id: project.id,
              ...(workflow?.id && { workflow_id: workflow.id }),
              ...(workflowYAML && { code: workflowYAML }),
            };
          } else {
            context = state.jobCodeContext;
            if (!context) {
              console.error(
                '[AI Assistant] No job context in store, cannot reconnect'
              );
              return;
            }
          }

          aiStore.connect(currentSessionType, context, selectedSessionId);
        }
      }, 100);
    },
    [aiStore, project, workflow, jobs, triggers, edges, positions]
  );

  const handleShowSessions = useCallback(() => {
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });

    aiStore.clearSession();
    aiStore.disconnect();
  }, [updateSearchParams, aiStore]);

  const sendMessage = useCallback(
    (
      content: string,
      messageOptions?: { attach_code?: boolean; attach_logs?: boolean }
    ) => {
      const currentState = aiStore.getSnapshot();

      if (!currentState.sessionId && aiMode) {
        const { mode, context } = aiMode;

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

        aiStore.connect(mode, { ...finalContext, content }, undefined);
        return;
      }

      if (currentState.sessionType === 'workflow_template') {
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

        const options = workflowYAML ? { code: workflowYAML } : undefined;
        aiStore.sendMessage(content);
        sendMessageToChannel(content, options);
      } else if (currentState.sessionType === 'job_code' && messageOptions) {
        aiStore.sendMessage(content);
        sendMessageToChannel(content, messageOptions);
      } else {
        aiStore.sendMessage(content);
        sendMessageToChannel(content);
      }
    },
    [
      workflow,
      jobs,
      triggers,
      edges,
      positions,
      sendMessageToChannel,
      aiStore,
      aiMode,
    ]
  );

  const handleRetryMessage = useCallback(
    (messageId: string) => {
      aiStore.retryMessage(messageId);
      retryMessageViaChannel(messageId);
    },
    [aiStore, retryMessageViaChannel]
  );

  const [applyingMessageId, setApplyingMessageId] = useState<string | null>(
    null
  );

  const appliedMessageIdsRef = useRef<Set<string>>(new Set());

  const { importWorkflow } = useWorkflowActions();

  const handleApplyWorkflow = useCallback(
    async (yaml: string, messageId: string) => {
      setApplyingMessageId(messageId);

      try {
        const workflowSpec = parseWorkflowYAML(yaml);

        const validateIds = (spec: any) => {
          if (spec.jobs) {
            for (const [jobKey, job] of Object.entries(spec.jobs)) {
              const jobItem = job as any;
              if (
                jobItem.id &&
                typeof jobItem.id === 'object' &&
                jobItem.id !== null
              ) {
                throw new Error(
                  `Invalid ID format for job "${jobKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          if (spec.triggers) {
            for (const [triggerKey, trigger] of Object.entries(spec.triggers)) {
              const triggerItem = trigger as any;
              if (
                triggerItem.id &&
                typeof triggerItem.id === 'object' &&
                triggerItem.id !== null
              ) {
                throw new Error(
                  `Invalid ID format for trigger "${triggerKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          if (spec.edges) {
            for (const [edgeKey, edge] of Object.entries(spec.edges)) {
              const edgeItem = edge as any;
              if (
                edgeItem.id &&
                typeof edgeItem.id === 'object' &&
                edgeItem.id !== null
              ) {
                throw new Error(
                  `Invalid ID format for edge "${edgeKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
        };

        validateIds(workflowSpec);

        // CRITICAL: Clear job editor URL params BEFORE importing workflow
        // This must happen FIRST to prevent race conditions where React tries
        // to reconnect to AI Assistant with stale job IDs during the import
        updateSearchParams({
          job: null,
          panel: null,
          'j-chat': null,
        });

        if (sessionType === 'job_code') {
          closeAIAssistantPanel();
        }

        const workflowState = convertWorkflowSpecToState(workflowSpec);

        importWorkflow(workflowState);
      } catch (error) {
        console.error('[AI Assistant] Failed to apply workflow:', error);

        notifications.alert({
          title: 'Failed to apply workflow',
          description:
            error instanceof Error ? error.message : 'Invalid workflow YAML',
        });
      } finally {
        setApplyingMessageId(null);
      }
    },
    [importWorkflow, updateSearchParams, sessionType, closeAIAssistantPanel]
  );

  useEffect(() => {
    if (sessionType !== 'workflow_template' || !messages.length) return;
    if (connectionState !== 'connected') return;

    const messagesWithCode = messages.filter(
      msg => msg.role === 'assistant' && msg.code && msg.status === 'success'
    );

    const latestMessage = messagesWithCode.pop();

    if (
      latestMessage?.code &&
      !appliedMessageIdsRef.current.has(latestMessage.id)
    ) {
      appliedMessageIdsRef.current.add(latestMessage.id);

      void handleApplyWorkflow(latestMessage.code, latestMessage.id);
    }
  }, [
    messages,
    sessionType,
    sessionId,
    connectionState,
    workflowTemplateContext,
    workflow,
    handleApplyWorkflow,
  ]);

  return (
    <div
      className="flex h-full flex-shrink-0 z-[60]"
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
              onShowSessions={handleShowSessions}
              onSendMessage={sendMessage}
              sessionId={sessionId}
              messageCount={messages.length}
              isLoading={isLoading}
              isResizable={true}
              store={aiStore}
              sessionType={sessionType}
              loadSessions={loadSessions}
            >
              <MessageList
                messages={messages}
                isLoading={isLoading}
                onApplyWorkflow={
                  sessionType === 'workflow_template'
                    ? handleApplyWorkflow
                    : undefined
                }
                applyingMessageId={applyingMessageId}
                showAddButtons={sessionType === 'job_code'}
                onRetryMessage={handleRetryMessage}
              />
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
  const projectFromStore = useProject();

  const workflowFromStore = useWorkflowState(state => state.workflow);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  const isRunPanelOpen = useIsRunPanelOpen();

  const { searchParams } = useURLState();
  const isIDEOpen = searchParams.get('panel') === 'editor';

  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;
  const projectEnv = projectFromStore?.env ?? projectEnvFallback;
  const currentWorkflowName = workflowFromStore?.name ?? workflowName;

  const handleVersionSelect = useVersionSelect();

  const breadcrumbElements = useMemo(() => {
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
    <Header
      key="canvas-header"
      {...(projectId !== undefined && { projectId })}
      workflowId={workflowId}
      isRunPanelOpen={isRunPanelOpen}
      isIDEOpen={isIDEOpen}
    >
      {breadcrumbElements}
    </Header>
  );
}

/**
 * IDEWrapper Component
 *
 * Manages the Full Screen IDE rendering and keyboard shortcuts.
 * Must be inside StoreProvider to access workflow and UI state.
 */
interface IDEWrapperProps {
  parentProjectId?: string | null;
  parentProjectName?: string | null;
}

function IDEWrapper({ parentProjectId, parentProjectName }: IDEWrapperProps) {
  const { searchParams, updateSearchParams } = useURLState();
  const { currentNode } = useNodeSelection();

  const isIDEOpen = searchParams.get('panel') === 'editor';
  const selectedJobId = searchParams.get('job');

  useEffect(() => {}, [isIDEOpen, selectedJobId, searchParams]);

  const handleCloseIDE = useCallback(() => {
    updateSearchParams({ panel: null, job: null });
  }, [updateSearchParams]);

  useKeyboardShortcut(
    'Control+e, Meta+e',
    () => {
      if (currentNode.type !== 'job' || !currentNode.node) {
        return;
      }

      updateSearchParams({ panel: 'editor' });
    },
    0,
    {
      enabled: !isIDEOpen,
    }
  );

  if (!isIDEOpen || !selectedJobId) {
    return null;
  }

  return (
    <FullScreenIDE
      jobId={selectedJobId}
      onClose={handleCloseIDE}
      parentProjectId={parentProjectId ?? null}
      parentProjectName={parentProjectName ?? null}
    />
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

  const liveViewActions = {
    pushEvent: props.pushEvent,
    pushEventTo: props.pushEventTo,
    handleEvent: props.handleEvent,
    navigate: props.navigate,
  };

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
          >
            <StoreProvider>
              <LiveViewActionsProvider actions={liveViewActions}>
                <VersionDebugLogger />
                <Toaster />
                <div className="flex-1 min-h-0 overflow-hidden flex flex-col relative">
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
                  <div className="flex-1 min-h-0 overflow-hidden relative">
                    <LoadingBoundary>
                      <div className="h-full w-full">
                        <WorkflowEditor />
                      </div>
                    </LoadingBoundary>
                    <IDEWrapper
                      parentProjectId={rootProjectId}
                      parentProjectName={rootProjectName}
                    />
                  </div>
                </div>
                <AIAssistantPanelWrapper />
              </LiveViewActionsProvider>
            </StoreProvider>
          </SessionProvider>
        </SocketProvider>
      </div>
    </KeyboardProvider>
  );
};
