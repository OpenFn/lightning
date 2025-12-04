/**
 * # AIAssistantStore
 *
 * Manages AI Assistant state including connection, messages, and session context.
 * Follows the useSyncExternalStore + Immer pattern used across the collaborative editor.
 *
 * ## Core Principles:
 * - Immer for referentially stable state updates
 * - Command Query Separation (CQS) for predictable state mutations
 * - Phoenix Channel integration for real-time AI responses
 * - Supports two modes: job_code and workflow_template
 *
 * ## Update Pattern:
 *
 * ### Pattern 3: Direct Immer → Notify (Local State Only)
 * **When to use**: All AI state updates (messages, connection state)
 * **Flow**: Direct Immer update → React notification
 * **Benefits**: Immediate response, simple implementation
 *
 * ```typescript
 * // Example: Add new AI message
 * const addMessage = (message: Message) => {
 *   state = produce(state, draft => {
 *     draft.messages.push(message);
 *     draft.isLoading = false;
 *   });
 *   notify('addMessage');
 * };
 * ```
 *
 * ## Architecture Notes:
 * - State is local to each user (not synchronized via Y.Doc)
 * - Phoenix Channel provides real-time updates from backend
 * - Store is created once per CollaborativeEditor instance
 * - Channel connection managed by useAIAssistantChannel hook
 */

/**
 * ## Redux DevTools Integration
 *
 * This store integrates with Redux DevTools for debugging.
 *
 * **Features:**
 * - Real-time state inspection
 * - Message history tracking
 * - Connection state monitoring
 * - Action replay for debugging
 *
 * **Note:** DevTools is automatically disabled in production builds.
 */

import { produce } from 'immer';

import _logger from '#/utils/logger';

import type {
  AIAssistantState,
  AIAssistantStore,
  ConnectionState,
  JobCodeContext,
  Message,
  MessageStatus,
  Session,
  SessionType,
  WorkflowTemplateContext,
} from '../types/ai-assistant';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('AIAssistantStore').seal();

/**
 * Creates an AI Assistant store instance
 */
export const createAIAssistantStore = (): AIAssistantStore => {
  let state: AIAssistantState = produce(
    {
      connectionState: 'disconnected' as ConnectionState,
      connectionError: undefined,
      sessionId: null,
      sessionType: null,
      messages: [],
      isLoading: false,
      isSending: false,
      sessionList: [],
      sessionListLoading: false,
      sessionListPagination: null,
      jobCodeContext: null,
      workflowTemplateContext: null,
      hasReadDisclaimer: false,
    } as AIAssistantState,
    draft => draft
  );

  const listeners = new Set<() => void>();

  const devtools = wrapStoreWithDevTools({
    name: 'AIAssistantStore',
    excludeKeys: [],
    maxAge: 100,
  });

  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
    listeners.forEach(listener => {
      listener();
    });
  };

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): AIAssistantState => state;

  const withSelector = createWithSelector(getSnapshot);

  /**
   * Connect to AI Assistant session
   * Creates a new session or reconnects to an existing one
   */
  const connect = (
    sessionType: SessionType,
    context: JobCodeContext | WorkflowTemplateContext,
    sessionId?: string
  ) => {
    state = produce(state, draft => {
      draft.connectionState = 'connecting';
      draft.sessionType = sessionType;
      draft.sessionId = sessionId ?? null;
      draft.connectionError = undefined;

      if (sessionType === 'job_code') {
        draft.jobCodeContext = context as JobCodeContext;
        draft.workflowTemplateContext = null;
      } else {
        draft.workflowTemplateContext = context as WorkflowTemplateContext;
        draft.jobCodeContext = null;
      }
    });

    notify('connect');
  };

  /**
   * Disconnect from AI Assistant session
   * Note: Preserves session data (sessionId, messages) so they persist across reconnects
   */
  const disconnect = () => {
    state = produce(state, draft => {
      draft.connectionState = 'disconnected';
      draft.isLoading = false;
      draft.isSending = false;
    });

    notify('disconnect');
  };

  /**
   * Mark the store as currently sending a message.
   * Updates UI state (isSending, isLoading) to show loading indicators.
   * The actual message sending is handled by the channel registry.
   */
  const setMessageSending = () => {
    state = produce(state, draft => {
      draft.isSending = true;
      draft.isLoading = true;
    });

    notify('setMessageSending');
  };

  /**
   * Retry a failed message
   */
  const retryMessage = (messageId: string) => {
    state = produce(state, draft => {
      const message = draft.messages.find(m => m.id === messageId);
      if (message) {
        message.status = 'pending';
        draft.isLoading = true;
      }
    });

    notify('retryMessage');
  };

  /**
   * Mark AI disclaimer as read
   */
  const markDisclaimerRead = () => {
    state = produce(state, draft => {
      draft.hasReadDisclaimer = true;
    });

    notify('markDisclaimerRead');
  };

  /**
   * Clear session and start fresh
   * Forces creation of a new session by clearing sessionId and messages
   */
  const clearSession = () => {
    state = produce(state, draft => {
      draft.sessionId = null;
      draft.messages = [];
      draft.isLoading = false;
      draft.isSending = false;
    });

    notify('clearSession');
  };

  /**
   * Load an existing session by ID
   * Switches to the specified session
   */
  const loadSession = (sessionId: string) => {
    state = produce(state, draft => {
      draft.connectionState = 'connecting';
      draft.sessionId = sessionId;
      draft.messages = [];
      draft.isLoading = true;
    });

    notify('loadSession');
  };

  /**
   * Update job context (adaptor, body, name) for an active session
   * This notifies the AI of changes to the job being edited
   */
  const updateContext = (context: Partial<JobCodeContext>) => {
    state = produce(state, draft => {
      if (draft.jobCodeContext) {
        if (context.job_adaptor !== undefined) {
          draft.jobCodeContext.job_adaptor = context.job_adaptor;
        }
        if (context.job_body !== undefined) {
          draft.jobCodeContext.job_body = context.job_body;
        }
        if (context.job_name !== undefined) {
          draft.jobCodeContext.job_name = context.job_name;
        }
      }
    });

    notify('updateContext');
  };

  /**
   * Load session list via HTTP API (used when no channel connection)
   * When a channel IS connected, the channel's loadSessions should be used instead
   *
   * @param options.offset - Number of sessions to skip (for pagination)
   * @param options.limit - Number of sessions to fetch (default: 20)
   * @param options.append - If true, append to existing list; if false, replace (default: false)
   */
  const loadSessionList = async (
    options: { offset?: number; limit?: number; append?: boolean } = {}
  ) => {
    const { offset = 0, limit = 20, append = false } = options;

    state = produce(state, draft => {
      draft.sessionListLoading = true;
    });
    notify('loadSessionList');

    try {
      const sessionType = state.sessionType;
      const jobContext = state.jobCodeContext;
      const workflowContext = state.workflowTemplateContext;

      if (!sessionType || (!jobContext && !workflowContext)) {
        logger.warn('Cannot load sessions: no session type or context', {
          sessionType,
          hasJobContext: !!jobContext,
          hasWorkflowContext: !!workflowContext,
        });
        state = produce(state, draft => {
          draft.sessionList = [];
          draft.sessionListPagination = {
            total_count: 0,
            has_next_page: false,
            has_prev_page: false,
          };
          draft.sessionListLoading = false;
        });
        notify('_setSessionList');
        return;
      }

      const params = new URLSearchParams();
      params.append('session_type', sessionType);
      params.append('offset', offset.toString());
      params.append('limit', limit.toString());

      if (sessionType === 'job_code' && jobContext) {
        params.append('job_id', jobContext.job_id);
      } else if (sessionType === 'workflow_template' && workflowContext) {
        params.append('project_id', workflowContext.project_id);
        if (workflowContext.workflow_id) {
          params.append('workflow_id', workflowContext.workflow_id);
        }
      }

      const response = await fetch(
        `/api/ai_assistant/sessions?${params.toString()}`
      );

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data =
        (await response.json()) as import('../types/ai-assistant').SessionListResponse;

      if (append) {
        _appendSessionList(data);
      } else {
        _setSessionList(data);
      }
    } catch (error) {
      logger.error('Failed to load sessions via HTTP', { error });
      state = produce(state, draft => {
        if (!append) {
          draft.sessionList = [];
        }
        draft.sessionListPagination = {
          total_count: 0,
          has_next_page: false,
          has_prev_page: false,
        };
        draft.sessionListLoading = false;
      });
      notify('_setSessionList');
    }
  };

  /**
   * Clear session data (used when stored session is invalid)
   * @internal Called by useAIAssistantChannel hook
   */
  const _clearSession = () => {
    state = produce(state, draft => {
      draft.sessionId = null;
      draft.messages = [];
    });

    notify('_clearSession');
  };

  /**
   * Update connection state
   * @internal Called by useAIAssistantChannel hook
   */
  const _setConnectionState = (
    connectionState: ConnectionState,
    error?: string
  ) => {
    state = produce(state, draft => {
      draft.connectionState = connectionState;
      draft.connectionError = error;

      if (connectionState === 'connected') {
        draft.isSending = false;
      }
    });

    notify('_setConnectionState');
  };

  /**
   * Set session data after successful connection
   * @internal Called by useAIAssistantChannel hook
   */
  const _setSession = (session: Session) => {
    state = produce(state, draft => {
      draft.sessionId = session.id;
      draft.sessionType = session.session_type;
      draft.messages = session.messages;

      // Keep isLoading true if there are any messages being processed
      const hasProcessingMessages = session.messages.some(
        m => m.status === 'processing' || m.status === 'pending'
      );

      draft.isLoading = hasProcessingMessages;
      draft.isSending = false;
    });

    notify('_setSession');
  };

  /**
   * Add a new message (from user or AI)
   * @internal Called by useAIAssistantChannel hook
   */
  const _addMessage = (message: Message) => {
    const exists = state.messages.some(m => m.id === message.id);
    if (exists) {
      return;
    }

    state = produce(state, draft => {
      draft.messages.push(message);

      draft.isSending = false;

      if (message.role === 'assistant') {
        if (message.status === 'success' || message.status === 'error') {
          draft.isLoading = false;
        } else if (message.status === 'processing') {
          draft.isLoading = true;
        }
      }
    });

    notify('_addMessage');
  };

  /**
   * Update message status
   * @internal Called by useAIAssistantChannel hook
   */
  const _updateMessageStatus = (messageId: string, status: MessageStatus) => {
    state = produce(state, draft => {
      const message = draft.messages.find(m => m.id === messageId);
      if (message) {
        message.status = status;

        if (status === 'success' || status === 'error') {
          draft.isLoading = false;
        } else if (status === 'processing') {
          draft.isLoading = true;
        }
      }
    });

    notify('_updateMessageStatus');
  };

  /**
   * Set session list from backend response
   * @internal Called by useAIAssistantChannel hook
   */
  const _setSessionList = (
    response: import('../types/ai-assistant').SessionListResponse
  ) => {
    state = produce(state, draft => {
      draft.sessionList = response.sessions;
      draft.sessionListPagination = response.pagination;
      draft.sessionListLoading = false;
    });

    notify('_setSessionList');
  };

  /**
   * Append sessions to existing session list
   * @internal Used for pagination (load more)
   */
  const _appendSessionList = (
    response: import('../types/ai-assistant').SessionListResponse
  ) => {
    state = produce(state, draft => {
      const existingIds = new Set(draft.sessionList.map(s => s.id));
      const newSessions = response.sessions.filter(s => !existingIds.has(s.id));
      draft.sessionList.push(...newSessions);
      draft.sessionListPagination = response.pagination;
      draft.sessionListLoading = false;
    });

    notify('_appendSessionList');
  };

  /**
   * Clear session list
   * Used when switching modes or jobs to prevent showing stale sessions
   * @internal
   */
  const _clearSessionList = () => {
    state = produce(state, draft => {
      draft.sessionList = [];
      draft.sessionListPagination = null;
      draft.sessionListLoading = false;
    });

    notify('_clearSessionList');
  };

  /**
   * Initialize context without changing connection state
   * Used by registry pattern to set context before channel connection
   * Unlike connect(), this does NOT set connectionState to 'connecting'
   * @internal
   */
  const _initializeContext = (
    sessionType: SessionType,
    context: JobCodeContext | WorkflowTemplateContext
  ) => {
    state = produce(state, draft => {
      draft.sessionType = sessionType;

      if (sessionType === 'job_code') {
        draft.jobCodeContext = context as JobCodeContext;
        draft.workflowTemplateContext = null;
      } else {
        draft.workflowTemplateContext = context as WorkflowTemplateContext;
        draft.jobCodeContext = null;
      }
    });

    notify('_initializeContext');
  };

  devtools.connect();

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Commands
    connect,
    disconnect,
    setMessageSending,
    retryMessage,
    markDisclaimerRead,
    clearSession,
    loadSession,
    loadSessionList,
    updateContext,

    // Internal updates (prefixed with _)
    _setConnectionState,
    _setSession,
    _clearSession,
    _clearSessionList,
    _addMessage,
    _updateMessageStatus,
    _setSessionList,
    _appendSessionList,
    _initializeContext,
  };
};

export type AIAssistantStoreInstance = ReturnType<
  typeof createAIAssistantStore
>;
