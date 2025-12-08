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
import { useAISessionCommands } from '../hooks/useAIChannelRegistry';
import { useAIInitialMessage } from '../hooks/useAIInitialMessage';
import { useAIMode } from '../hooks/useAIMode';
import { useAISession } from '../hooks/useAISession';
import { useResizablePanel } from '../hooks/useResizablePanel';
import {
  useProject,
  useHasReadAIDisclaimer,
  useMarkAIDisclaimerRead,
  useSessionContextLoaded,
} from '../hooks/useSessionContext';
import {
  useIsAIAssistantPanelOpen,
  useUICommands,
  useAIAssistantInitialMessage,
} from '../hooks/useUI';
import { useWorkflowState, useWorkflowActions } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { notifications } from '../lib/notifications';
import type { JobCodeContext } from '../types/ai-assistant';
import { Z_INDEX } from '../utils/constants';
import {
  prepareWorkflowForSerialization,
  serializeWorkflowToYAML,
} from '../utils/workflowSerialization';

import { AIAssistantPanel } from './AIAssistantPanel';
import { MessageList } from './MessageList';

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
  const initialMessage = useAIAssistantInitialMessage();
  const {
    closeAIAssistantPanel,
    toggleAIAssistantPanel,
    clearAIAssistantInitialMessage,
    collapseCreateWorkflowPanel,
  } = useUICommands();
  const { updateSearchParams, params } = useURLState();

  // Track IDE state changes to re-focus chat input when IDE closes
  const isIDEOpen = params.panel === 'editor';
  const [focusTrigger, setFocusTrigger] = useState(0);
  const prevIDEOpenRef = useRef(isIDEOpen);

  useEffect(() => {
    // When IDE closes (was true, now false), increment focus trigger
    if (prevIDEOpenRef.current && !isIDEOpen) {
      setFocusTrigger(prev => prev + 1);
    }
    prevIDEOpenRef.current = isIDEOpen;
  }, [isIDEOpen]);

  // Cmd+K toggles AI Assistant with mutual exclusivity
  useKeyboardShortcut(
    '$mod+k',
    () => {
      // Close create workflow panel when opening AI Assistant
      if (!isAIAssistantPanelOpen) {
        collapseCreateWorkflowPanel();
      }
      toggleAIAssistantPanel();
    },
    0
  );

  const aiStore = useAIStore();
  const {
    sendMessage: sendMessageToChannel,
    loadSessions,
    retryMessage: retryMessageViaChannel,
    updateContext: updateContextViaChannel,
  } = useAISessionCommands();
  const messages = useAIMessages();
  const isLoading = useAIIsLoading();
  const sessionId = useAISessionId();
  const sessionType = useAISessionType();
  const connectionState = useAIConnectionState();
  const sessionContextLoaded = useSessionContextLoaded();
  const hasReadDisclaimer = useHasReadAIDisclaimer();
  const markAIDisclaimerRead = useMarkAIDisclaimerRead();
  const workflowTemplateContext = useAIWorkflowTemplateContext();
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);

  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  const edges = useWorkflowState(state => state.edges);
  const positions = useWorkflowState(state => state.positions);

  const {
    width,
    isResizing,
    handleMouseDown: handleResizeMouseDown,
  } = useResizablePanel({
    storageKey: 'ai-assistant-panel-width',
    defaultWidth: 400,
    direction: 'left',
  });

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

    if (isAIAssistantPanelOpen) {
      updateSearchParams({
        chat: 'true',
      });
    } else {
      // When closing, clear chat param and session params
      updateSearchParams({
        chat: null,
        'w-chat': null,
        'j-chat': null,
      });
    }

    setTimeout(() => {
      isSyncingRef.current = false;
    }, 0);
  }, [isAIAssistantPanelOpen, updateSearchParams]);

  const aiMode = useAIMode();

  const sessionIdFromURL = useMemo(() => {
    if (!aiMode) return null;

    const paramName = aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const sessionId = params[paramName];

    return sessionId;
  }, [aiMode, params]);

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
    // Don't sync session ID to URL when panel is closed
    if (!isAIAssistantPanelOpen) return;
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
    const currentValue = params[currentParamName];

    if (currentValue !== sessionId) {
      updateSearchParams({
        [currentParamName]: sessionId,
        [otherParamName]: null, // Clear the other mode's session
      });
    }
  }, [
    sessionId,
    aiMode,
    params,
    updateSearchParams,
    aiStore,
    isAIAssistantPanelOpen,
  ]);

  // Close handler - URL cleanup happens automatically via the effect above
  // when isAIAssistantPanelOpen becomes false
  const handleClosePanel = closeAIAssistantPanel;

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

  // Handle initial message from template selection
  // When user clicks "AI workflow from description" from LeftPanel,
  // the initial message is stored in UI state and we auto-send it
  useAIInitialMessage({
    initialMessage,
    aiMode,
    sessionId,
    connectionState,
    isAIAssistantPanelOpen,
    aiStore,
    workflowData: { workflow, jobs, triggers, edges, positions },
    updateSearchParams,
    clearAIAssistantInitialMessage,
  });

  const handleShowSessions = useCallback(() => {
    aiStore.clearSession();
    // Clear session list to force reload - ensures fresh data after tab sleep
    aiStore._clearSessionList();

    // Ensure context is initialized for session list loading
    // This handles cases where context might have been lost (e.g., after tab sleep)
    if (aiMode) {
      aiStore._initializeContext(aiMode.mode, aiMode.context);
    }

    // Clear session ID from URL - shows session list
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });
  }, [updateSearchParams, aiStore, aiMode]);

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
        aiStore.setMessageSending();
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
      aiStore.setMessageSending();
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
    // Persist to backend via workflow channel and update local state
    markAIDisclaimerRead();
    // Also update AI store for consistency
    aiStore.markDisclaimerRead();
  }, [aiStore, markAIDisclaimerRead]);

  const [applyingMessageId, setApplyingMessageId] = useState<string | null>(
    null
  );

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
      className="flex h-full flex-shrink-0"
      style={{
        zIndex: Z_INDEX.SIDE_PANEL,
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
            className="w-1 bg-gray-200 hover:bg-primary-500 transition-colors cursor-col-resize flex-shrink-0"
            onMouseDown={handleResizeMouseDown}
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
              onClose={handleClosePanel}
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
              showDisclaimer={sessionContextLoaded && !hasReadDisclaimer}
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
