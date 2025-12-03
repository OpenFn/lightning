import { useState, useRef, useEffect, useCallback, useMemo } from 'react';

import { useURLState } from '../../react/lib/use-url-state';
import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import {
  useAIConnectionState,
  useAIHasReadDisclaimer,
  useAIIsLoading,
  useAIMessages,
  useAISessionId,
  useAISessionType,
  useAIStore,
  useAIWorkflowTemplateContext,
} from '../hooks/useAIAssistant';
import { useAISessionCommands } from '../hooks/useAIChannelRegistry';
import { useAIMode } from '../hooks/useAIMode';
import { useAISession } from '../hooks/useAISession';
import { useProject } from '../hooks/useSessionContext';
import { useIsAIAssistantPanelOpen, useUICommands } from '../hooks/useUI';
import { useWorkflowState, useWorkflowActions } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { notifications } from '../lib/notifications';
import type { JobCodeContext } from '../types/ai-assistant';
import { serializeWorkflowToYAML } from '../utils/workflowSerialization';

import { AIAssistantPanel } from './AIAssistantPanel';
import { MessageList } from './MessageList';

// Helper functions removed - no longer needed with registry-based approach

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
): import('../utils/workflowSerialization').SerializableWorkflow | null {
  if (!workflow || jobs.length === 0) {
    return null;
  }

  return {
    id: workflow.id,
    name: workflow.name,
    jobs: jobs.map((job: unknown) => {
      const j = job as Record<string, unknown>;
      return {
        id: String(j['id']),
        name: String(j['name']),
        adaptor: String(j['adaptor']),
        body: String(j['body']),
      };
    }),
    triggers,
    edges: edges.map((edge: unknown) => {
      const e = edge as Record<string, unknown>;
      const conditionType = e['condition_type'];
      const result: Record<string, unknown> = {
        id: String(e['id']),
        condition_type:
          conditionType && typeof conditionType === 'string'
            ? conditionType
            : 'always',
        enabled: e['enabled'] !== false,
        target_job_id: String(e['target_job_id']),
      };

      const sourceJobId = e['source_job_id'];
      if (sourceJobId && typeof sourceJobId === 'string') {
        result['source_job_id'] = sourceJobId;
      }
      const sourceTriggerId = e['source_trigger_id'];
      if (sourceTriggerId && typeof sourceTriggerId === 'string') {
        result['source_trigger_id'] = sourceTriggerId;
      }
      const conditionLabel = e['condition_label'];
      if (conditionLabel && typeof conditionLabel === 'string') {
        result['condition_label'] = conditionLabel;
      }
      const conditionExpression = e['condition_expression'];
      if (conditionExpression && typeof conditionExpression === 'string') {
        result['condition_expression'] = conditionExpression;
      }

      return result;
    }),
    positions,
  } as import('../utils/workflowSerialization').SerializableWorkflow;
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
    retryMessage: retryMessageViaChannel,
    markDisclaimerRead: markDisclaimerReadViaChannel,
    updateContext: updateContextViaChannel,
  } = useAISessionCommands();
  const messages = useAIMessages();
  const isLoading = useAIIsLoading();
  const sessionId = useAISessionId();
  const sessionType = useAISessionType();
  const connectionState = useAIConnectionState();
  const hasReadDisclaimer = useAIHasReadDisclaimer();
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

  const sessionIdFromURL = useMemo(() => {
    if (!aiMode) return null;

    const paramName = aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const sessionId = searchParams.get(paramName);

    return sessionId;
  }, [aiMode, searchParams]);

  // Use registry-based session management
  useAISession({
    isOpen: isAIAssistantPanelOpen,
    aiMode,
    sessionIdFromURL,
    workflowData: {
      workflow,
      jobs,
      triggers,
      edges,
      positions,
    },
    onSessionIdChange: newSessionId => {
      if (!aiMode) return;

      // When mode changes, clear the other mode's session param
      if (aiMode.mode === 'workflow_template') {
        updateSearchParams({
          'w-chat': newSessionId,
          'j-chat': null, // Clear job session when in workflow mode
        });
      } else {
        updateSearchParams({
          'j-chat': newSessionId,
          'w-chat': null, // Clear workflow session when in job mode
        });
      }
    },
  });

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
    const otherParamName =
      aiMode.mode === 'workflow_template' ? 'j-chat' : 'w-chat';
    const currentValue = searchParams.get(currentParamName);

    if (currentValue !== sessionId) {
      updateSearchParams({
        [currentParamName]: sessionId,
        [otherParamName]: null, // Clear the other mode's session
      });
    }
  }, [sessionId, aiMode, searchParams, updateSearchParams, aiStore]);

  // NOTE: We intentionally DO NOT clear URL params when panel closes.
  // The session ID in the URL serves as "memory" so reopening the panel
  // resumes the previous session. The registry handles channel cleanup
  // via useAISession's cleanup effect, and will recreate the channel
  // when the panel reopens with the same session ID in the URL.

  // Push job context updates to backend when job body/adaptor/name changes
  // This ensures the AI has access to the current code when "Attach code" is checked
  useEffect(() => {
    // Only update context for active job_code sessions
    if (
      !isAIAssistantPanelOpen ||
      !sessionId ||
      sessionType !== 'job_code' ||
      !aiMode ||
      aiMode.mode !== 'job_code'
    ) {
      return;
    }

    const context = aiMode.context as JobCodeContext;
    if (context.job_body !== undefined || context.job_adaptor !== undefined) {
      updateContextViaChannel({
        job_body: context.job_body,
        job_adaptor: context.job_adaptor,
        job_name: context.job_name,
      });
    }
  }, [
    isAIAssistantPanelOpen,
    sessionId,
    sessionType,
    aiMode,
    updateContextViaChannel,
  ]);

  const handleNewConversation = useCallback(() => {
    if (!project) return;

    appliedMessageIdsRef.current.clear();
    aiStore.clearSession();

    // Clear session ID from URL - useAISession will handle creating new session
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });
  }, [aiStore, project, updateSearchParams]);

  const handleSessionSelect = useCallback(
    (selectedSessionId: string) => {
      if (!project || !aiMode) return;

      appliedMessageIdsRef.current.clear();
      aiStore._clearSession();

      // Update URL with selected session ID - useAISession will handle loading it
      if (aiMode.mode === 'workflow_template') {
        updateSearchParams({
          'w-chat': selectedSessionId,
          'j-chat': null,
        });
      } else {
        updateSearchParams({
          'j-chat': selectedSessionId,
          'w-chat': null,
        });
      }
    },
    [aiStore, project, aiMode, updateSearchParams]
  );

  const handleShowSessions = useCallback(() => {
    aiStore.clearSession();

    // Clear session ID from URL - shows session list
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });
  }, [updateSearchParams, aiStore]);

  const sendMessage = useCallback(
    (
      content: string,
      messageOptions?: { attach_code?: boolean; attach_logs?: boolean }
    ) => {
      const currentState = aiStore.getSnapshot();

      // If no session exists, we need to include content in context for first message
      if (!currentState.sessionId && aiMode) {
        const { mode, context } = aiMode;

        // Prepare context with content and message options for channel join
        let finalContext = {
          ...context,
          content,
          // Include attach_code/attach_logs so backend knows to include them in first message
          ...(messageOptions?.attach_code && { attach_code: true }),
          ...(messageOptions?.attach_logs && { attach_logs: true }),
        };

        // Add workflow YAML if in workflow mode
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
              finalContext = { ...finalContext, code: workflowYAML };
            }
          }
        }

        // Initialize store with context including content
        aiStore.connect(mode, finalContext, undefined);

        // Update URL to trigger subscription to "new" channel
        // useAISession will see the URL change and subscribe with the context (including content)
        if (mode === 'workflow_template') {
          updateSearchParams({ 'w-chat': 'new', 'j-chat': null });
        } else {
          updateSearchParams({ 'j-chat': 'new', 'w-chat': null });
        }

        // Mark message as sending in store
        aiStore.sendMessage(content);
        return;
      }

      // For existing sessions, prepare options and send
      let options:
        | { attach_code?: boolean; attach_logs?: boolean; code?: string }
        | undefined = {
        ...messageOptions, // Include attach_code and attach_logs
      };

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

        if (workflowYAML) {
          options = { ...options, code: workflowYAML };
        }
      }

      // Update store state and send through registry
      aiStore.sendMessage(content);
      sendMessageToChannel(content, options);
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
      updateSearchParams,
    ]
  );

  const handleRetryMessage = useCallback(
    (messageId: string) => {
      aiStore.retryMessage(messageId);
      retryMessageViaChannel(messageId);
    },
    [aiStore, retryMessageViaChannel]
  );

  const handleMarkDisclaimerRead = useCallback(() => {
    aiStore.markDisclaimerRead();
    markDisclaimerReadViaChannel();
  }, [aiStore, markDisclaimerReadViaChannel]);

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
    (yaml: string, messageId: string) => {
      setApplyingMessageId(messageId);

      try {
        const workflowSpec = parseWorkflowYAML(yaml);

        const validateIds = (spec: Record<string, unknown>) => {
          if (spec['jobs']) {
            for (const [jobKey, job] of Object.entries(
              spec['jobs'] as object
            )) {
              const jobItem = job as Record<string, unknown>;
              if (
                jobItem['id'] &&
                typeof jobItem['id'] === 'object' &&
                jobItem['id'] !== null
              ) {
                throw new Error(
                  `Invalid ID format for job "${jobKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          if (spec['triggers']) {
            for (const [triggerKey, trigger] of Object.entries(
              spec['triggers'] as object
            )) {
              const triggerItem = trigger as Record<string, unknown>;
              if (
                triggerItem['id'] &&
                typeof triggerItem['id'] === 'object' &&
                triggerItem['id'] !== null
              ) {
                throw new Error(
                  `Invalid ID format for trigger "${triggerKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          if (spec['edges']) {
            for (const [edgeKey, edge] of Object.entries(
              spec['edges'] as object
            )) {
              const edgeItem = edge as Record<string, unknown>;
              if (
                edgeItem['id'] &&
                typeof edgeItem['id'] === 'object' &&
                edgeItem['id'] !== null
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
    [importWorkflow]
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
          <button
            type="button"
            data-testid="ai-panel-resize-handle"
            className="w-1 bg-gray-200 hover:bg-blue-400 transition-colors cursor-col-resize flex-shrink-0"
            onMouseDown={handleMouseDown}
            aria-label="Resize AI Assistant panel"
            onKeyDown={e => {
              if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
                e.preventDefault();
              }
            }}
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
              sessionType={sessionType}
              loadSessions={loadSessions}
              focusTrigger={focusTrigger}
              connectionState={sessionId ? connectionState : 'connected'}
              showDisclaimer={
                connectionState === 'connected' && !hasReadDisclaimer
              }
              onAcceptDisclaimer={handleMarkDisclaimerRead}
            >
              <MessageList
                messages={messages}
                isLoading={isLoading}
                onApplyWorkflow={
                  sessionType === 'workflow_template'
                    ? (yaml, messageId) => {
                        void handleApplyWorkflow(yaml, messageId);
                      }
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
