import { useState, useRef, useEffect, useCallback, useMemo } from 'react';

import { useURLState } from '../../react/lib/use-url-state';
import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import {
  useAIConnectionState,
  useAIIsLoading,
  useAIMessages,
  useAISessionId,
  useAISessionType,
  useAIStore,
  useAIWorkflowTemplateContext,
} from '../hooks/useAIAssistant';
import { useAIAssistantChannel } from '../hooks/useAIAssistantChannel';
import { useAIMode } from '../hooks/useAIMode';
import { useProject } from '../hooks/useSessionContext';
import { useIsAIAssistantPanelOpen, useUICommands } from '../hooks/useUI';
import { useWorkflowState, useWorkflowActions } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { notifications } from '../lib/notifications';
import { serializeWorkflowToYAML } from '../utils/workflowSerialization';

import { AIAssistantPanel } from './AIAssistantPanel';
import { MessageList } from './MessageList';

/**
 * Helper function to prepare workflow data for serialization.
 * Transforms workflow store state into the format expected by serializeWorkflowToYAML.
 */
function prepareWorkflowForSerialization(
  workflow: { id: string; name: string } | null,
  jobs: unknown[],
  triggers: unknown[],
  edges: unknown[],
  positions: unknown
) {
  if (!workflow || jobs.length === 0) {
    return null;
  }

  return {
    id: workflow.id,
    name: workflow.name,
    jobs: jobs.map((job: unknown) => {
      const j = job as Record<string, unknown>;
      return {
        id: j.id,
        name: j.name,
        adaptor: j.adaptor,
        body: j.body,
      };
    }),
    triggers: triggers,
    edges: edges.map((edge: unknown) => {
      const e = edge as Record<string, unknown>;
      return {
        id: e.id,
        condition_type: e.condition_type || 'always',
        enabled: e.enabled !== false,
        target_job_id: e.target_job_id,
        ...(e.source_job_id && {
          source_job_id: e.source_job_id,
        }),
        ...(e.source_trigger_id && {
          source_trigger_id: e.source_trigger_id,
        }),
        ...(e.condition_label && {
          condition_label: e.condition_label,
        }),
        ...(e.condition_expression && {
          condition_expression: e.condition_expression,
        }),
      };
    }),
    positions: positions,
  };
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
export function AIAssistantPanelWrapper() {
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();
  const { closeAIAssistantPanel, toggleAIAssistantPanel } = useUICommands();
  const { updateSearchParams, searchParams } = useURLState();

  // Track IDE state changes to re-focus chat input when IDE closes
  const isIDEOpen = searchParams.get('panel') === 'editor';
  const [focusTrigger, setFocusTrigger] = useState(0);
  const prevIDEOpenRef = useRef(isIDEOpen);

  useEffect(() => {
    // When IDE closes (was true, now false), increment focus trigger
    if (prevIDEOpenRef.current && !isIDEOpen) {
      setFocusTrigger(prev => prev + 1);
    }
    prevIDEOpenRef.current = isIDEOpen;
  }, [isIDEOpen]);

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

  /**
   * isSyncingRef prevents re-entrant URL updates during panel state changes.
   *
   * Pattern explanation:
   * - When we update URL params, React re-renders with new searchParams
   * - This could trigger another URL update, creating an infinite loop
   * - We use a ref to track ongoing sync operations
   * - setTimeout(..., 0) breaks out of the current execution context,
   *   allowing the URL update to complete before we clear the flag
   *
   * This is a defensive pattern for synchronizing state with URL parameters.
   */
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
      (context as import('../types/ai-assistant').JobCodeContext).job_id !==
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
        ? (context as import('../types/ai-assistant').JobCodeContext).job_id
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
      (context as import('../types/ai-assistant').JobCodeContext).job_id !==
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
    if (mode === 'workflow_template') {
      const workflowData = prepareWorkflowForSerialization(
        workflow,
        jobs,
        triggers,
        edges,
        positions
      );
      if (workflowData) {
        const workflowYAML = serializeWorkflowToYAML(workflowData);
        if (workflowYAML) {
          finalContext = { ...context, code: workflowYAML };
        }
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
      aiMode.context as import('../types/ai-assistant').JobCodeContext;

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

  // Update workflow context when workflow ID changes (e.g., after saving a new workflow)
  // This migrates the session from "unsaved" to "saved" state
  useEffect(() => {
    if (
      !isAIAssistantPanelOpen ||
      !aiMode ||
      aiMode.mode !== 'workflow_template' ||
      !sessionId ||
      !workflow?.id
    ) {
      return;
    }

    const context =
      aiMode.context as import('../types/ai-assistant').WorkflowTemplateContext;

    // Only update if workflow ID changed from what's in the context
    // This handles the case where a workflow is saved for the first time
    if (context.workflow_id !== workflow.id) {
      updateContext({ workflow_id: workflow.id });
    }
  }, [isAIAssistantPanelOpen, aiMode, sessionId, workflow?.id, updateContext]);

  const handleNewConversation = useCallback(() => {
    if (!project) return;

    appliedMessageIdsRef.current.clear();
    aiStore.clearSession();
    aiStore.disconnect();

    setTimeout(() => {
      const state = aiStore.getSnapshot();
      if (state.connectionState === 'disconnected') {
        const workflowData = prepareWorkflowForSerialization(
          workflow,
          jobs,
          triggers,
          edges,
          positions
        );
        const workflowYAML = workflowData
          ? serializeWorkflowToYAML(workflowData)
          : undefined;

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
            const workflowData = prepareWorkflowForSerialization(
              workflow,
              jobs,
              triggers,
              edges,
              positions
            );
            const workflowYAML = workflowData
              ? serializeWorkflowToYAML(workflowData)
              : undefined;

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
        if (mode === 'workflow_template') {
          const workflowData = prepareWorkflowForSerialization(
            workflow,
            jobs,
            triggers,
            edges,
            positions
          );
          if (workflowData) {
            const workflowYAML = serializeWorkflowToYAML(workflowData);
            if (workflowYAML) {
              finalContext = { ...context, code: workflowYAML };
            }
          }
        }

        aiStore.connect(mode, { ...finalContext, content }, undefined);
        return;
      }

      if (currentState.sessionType === 'workflow_template') {
        const workflowData = prepareWorkflowForSerialization(
          workflow,
          jobs,
          triggers,
          edges,
          positions
        );
        const workflowYAML = workflowData
          ? serializeWorkflowToYAML(workflowData)
          : undefined;

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

  /**
   * appliedMessageIdsRef tracks which AI-generated workflows have been automatically applied.
   *
   * Auto-apply behavior:
   * - When the AI responds with YAML code in workflow_template mode, we automatically
   *   apply it to the canvas (see useEffect below)
   * - This ref prevents applying the same message multiple times if the component re-renders
   * - The ref is cleared when:
   *   1. Starting a new conversation (handleNewConversation)
   *   2. Switching to a different session (handleSessionSelect)
   *
   * This provides a smooth UX where users see their workflow update in real-time
   * as the AI generates it, without requiring manual "Apply" button clicks.
   */
  const appliedMessageIdsRef = useRef<Set<string>>(new Set());
  const hasLoadedSessionRef = useRef(false);

  // Reset hasLoadedSessionRef when session changes
  useEffect(() => {
    hasLoadedSessionRef.current = false;
  }, [sessionId]);

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

        // Clear AI Assistant chat param to prevent race conditions where React
        // tries to reconnect to AI Assistant with stale job IDs during import.
        // Keep job/panel params so inspector panels remain open after import.
        updateSearchParams({
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

  /**
   * Auto-apply workflow when AI responds with YAML code.
   *
   * This effect watches for new messages in workflow_template mode and automatically
   * applies the latest workflow YAML to the canvas. This creates a seamless experience
   * where users see their workflow update in real-time as the AI generates it.
   *
   * Conditions for auto-apply:
   * - Session type is 'workflow_template' (not job_code)
   * - There are messages in the conversation
   * - Connection is established (prevents applying during reconnection)
   * - The message has code and hasn't been applied yet (tracked in appliedMessageIdsRef)
   *
   * Note: We only apply the LATEST message with code to avoid applying intermediate
   * drafts if the AI sends multiple responses quickly.
   */
  useEffect(() => {
    if (sessionType !== 'workflow_template' || !messages.length) return;
    if (connectionState !== 'connected') return;

    const messagesWithCode = messages.filter(
      msg => msg.role === 'assistant' && msg.code && msg.status === 'success'
    );

    // On initial session load, mark all existing messages as already applied
    // to prevent re-applying workflows when opening existing sessions
    if (!hasLoadedSessionRef.current) {
      hasLoadedSessionRef.current = true;
      messagesWithCode.forEach(msg => {
        appliedMessageIdsRef.current.add(msg.id);
      });
      return;
    }

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
        overflow: 'hidden',
        transition: isResizing
          ? 'none'
          : 'width 0.4s cubic-bezier(0.4, 0, 0.2, 1)',
      }}
    >
      {isAIAssistantPanelOpen && (
        <>
          <div
            data-testid="ai-panel-resize-handle"
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
              focusTrigger={focusTrigger}
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
