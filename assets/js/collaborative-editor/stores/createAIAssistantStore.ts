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
  MessageOptions,
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
  // Single Immer-managed state object
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

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'AIAssistantStore',
    excludeKeys: [], // All state is serializable
    maxAge: 100, // Keep more actions for AI conversations
  });

  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
    listeners.forEach(listener => {
      listener();
    });
  };

  /**
   * Helper to extract workflow ID from current context
   */
  const getWorkflowIdFromContext = (): string | null => {
    if (state.workflowTemplateContext?.workflow_id) {
      return state.workflowTemplateContext.workflow_id;
    }
    return null;
  };

  /**
   * Helper to generate storage key based on current mode and context
   * Returns the localStorage key to use for persisting the session ID
   */
  const getStorageKeyFromContext = (): string | null => {
    if (state.sessionType === 'job_code' && state.jobCodeContext?.job_id) {
      return `ai-job-${state.jobCodeContext.job_id}`;
    }
    if (state.sessionType === 'workflow_template') {
      if (state.workflowTemplateContext?.workflow_id) {
        return `ai-workflow-${state.workflowTemplateContext.workflow_id}`;
      }
      if (state.workflowTemplateContext?.project_id) {
        return `ai-project-${state.workflowTemplateContext.project_id}`;
      }
    }
    return null;
  };

  // ===========================================================================
  // CORE STORE INTERFACE
  // ===========================================================================

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): AIAssistantState => state;

  const withSelector = createWithSelector(getSnapshot);

  // ===========================================================================
  // COMMANDS (CQS pattern - State mutations)
  // ===========================================================================

  /**
   * Connect to AI Assistant session
   * Creates a new session or reconnects to an existing one
   */
  const connect = (
    sessionType: SessionType,
    context: JobCodeContext | WorkflowTemplateContext,
    sessionId?: string
  ) => {
    logger.debug('Connecting to AI Assistant', {
      sessionType,
      sessionId,
      context,
    });

    state = produce(state, draft => {
      draft.connectionState = 'connecting';
      draft.sessionType = sessionType;
      draft.sessionId = sessionId ?? null;
      draft.connectionError = undefined;

      // Store context based on session type
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
    logger.debug('Disconnecting from AI Assistant');

    state = produce(state, draft => {
      draft.connectionState = 'disconnected';
      draft.isLoading = false;
      draft.isSending = false;
      // Keep: sessionId, sessionType, messages, context - these persist
    });

    notify('disconnect');
  };

  /**
   * Send a message to the AI
   */
  const sendMessage = (content: string, options?: MessageOptions) => {
    logger.debug('Sending message to AI', { content, options });

    state = produce(state, draft => {
      draft.isSending = true;
      draft.isLoading = true;
    });

    notify('sendMessage');

    // Note: Actual sending happens in the channel hook
    // This just updates the UI state optimistically
  };

  /**
   * Retry a failed message
   */
  const retryMessage = (messageId: string) => {
    logger.debug('Retrying message', { messageId });

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
    logger.debug('Marking AI disclaimer as read');

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
    logger.debug('Clearing session to start new conversation');

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
    logger.debug('Loading session', { sessionId });

    // Disconnect current session and reconnect to the new one
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
    logger.debug('Updating job context', { context });

    state = produce(state, draft => {
      if (draft.jobCodeContext) {
        // Update only the provided fields
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

    logger.debug('Loading session list via HTTP API', {
      offset,
      limit,
      append,
    });

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
        // Include workflow_id to filter sessions by workflow (matching legacy editor)
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
      logger.debug('Sessions loaded via HTTP', { data, append });

      if (append) {
        // Append new sessions to existing list
        _appendSessionList(data);
      } else {
        // Replace session list
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
    logger.debug('Clearing invalid session');

    state = produce(state, draft => {
      draft.sessionId = null;
      draft.messages = [];
    });

    notify('_clearSession');
  };

  // ===========================================================================
  // INTERNAL STATE UPDATES (Called by channel hook)
  // ===========================================================================

  /**
   * Update connection state
   * @internal Called by useAIAssistantChannel hook
   */
  const _setConnectionState = (
    connectionState: ConnectionState,
    error?: string
  ) => {
    logger.debug('Connection state changed', { connectionState, error });

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
    logger.debug('Session loaded', { session });

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

    // Save session to localStorage with mode-specific key
    const storageKey = getStorageKeyFromContext();
    if (storageKey) {
      try {
        localStorage.setItem(storageKey, session.id);
        logger.debug('Saved session to storage', {
          storageKey,
          sessionId: session.id,
        });
      } catch (error) {
        logger.error('Failed to save session to localStorage', error);
      }
    }

    notify('_setSession');
  };

  /**
   * Add a new message (from user or AI)
   * @internal Called by useAIAssistantChannel hook
   */
  const _addMessage = (message: Message) => {
    logger.debug('Adding message', { message });

    state = produce(state, draft => {
      // Check if message already exists (avoid duplicates)
      const exists = draft.messages.some(m => m.id === message.id);
      if (!exists) {
        draft.messages.push(message);
      }

      draft.isSending = false;

      // Handle loading state based on message role and status
      if (message.role === 'user') {
        // User message added - keep isLoading true to show waiting state
        // The assistant hasn't responded yet, so we should keep showing loading
        // Don't modify draft.isLoading here - let it stay true
      } else if (message.role === 'assistant') {
        // Only stop loading if assistant message is in a final state
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
  const _updateMessageStatus = (messageId: string, status: string) => {
    logger.debug('Updating message status', { messageId, status });

    state = produce(state, draft => {
      const message = draft.messages.find(m => m.id === messageId);
      if (message) {
        message.status = status as Message['status'];

        // Update loading state based on status
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
    logger.debug('Session list loaded', { response });

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
    logger.debug('Appending sessions to list', { response });

    state = produce(state, draft => {
      // Append new sessions, avoiding duplicates
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
    logger.debug('Clearing session list');

    state = produce(state, draft => {
      draft.sessionList = [];
      draft.sessionListPagination = null;
      // Don't set sessionListLoading here - it should only be managed by loadSessionList()
      // Setting it to true here can cause infinite loading if loadSessionList() never gets called
      draft.sessionListLoading = false;
    });

    notify('_clearSessionList');
  };

  devtools.connect();

  // ===========================================================================
  // PUBLIC INTERFACE
  // ===========================================================================

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Commands
    connect,
    disconnect,
    sendMessage,
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
  };
};

export type AIAssistantStoreInstance = ReturnType<
  typeof createAIAssistantStore
>;
