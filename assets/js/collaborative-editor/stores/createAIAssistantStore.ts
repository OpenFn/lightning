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
 * LocalStorage helpers for session persistence
 */
const SESSION_STORAGE_KEY = 'ai_assistant_sessions';

interface StoredSessions {
  [workflowId: string]: {
    sessionId: string;
    sessionType: SessionType;
    timestamp: number;
  };
}

const loadStoredSession = (
  workflowId: string
): { sessionId: string; sessionType: SessionType } | null => {
  try {
    const stored = localStorage.getItem(SESSION_STORAGE_KEY);
    if (!stored) return null;

    const sessions = JSON.parse(stored) as StoredSessions;
    const session = sessions[workflowId];

    if (!session) return null;

    // Clear sessions older than 7 days
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
    if (session.timestamp < sevenDaysAgo) {
      delete sessions[workflowId];
      localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(sessions));
      return null;
    }

    return { sessionId: session.sessionId, sessionType: session.sessionType };
  } catch (error) {
    logger.error('Failed to load stored session', error);
    return null;
  }
};

const saveSession = (
  workflowId: string,
  sessionId: string,
  sessionType: SessionType
) => {
  try {
    const stored = localStorage.getItem(SESSION_STORAGE_KEY);
    const sessions: StoredSessions = stored
      ? (JSON.parse(stored) as StoredSessions)
      : {};

    sessions[workflowId] = {
      sessionId,
      sessionType,
      timestamp: Date.now(),
    };

    localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(sessions));
  } catch (error) {
    logger.error('Failed to save session', error);
  }
};

const clearStoredSession = (workflowId: string) => {
  try {
    const stored = localStorage.getItem(SESSION_STORAGE_KEY);
    if (!stored) return;

    const sessions = JSON.parse(stored) as StoredSessions;
    delete sessions[workflowId];
    localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(sessions));
  } catch (error) {
    logger.error('Failed to clear stored session', error);
  }
};

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
   * Load stored session for a workflow (if it exists in localStorage)
   * @returns Session ID if found, null otherwise
   */
  const loadStoredSessionForWorkflow = (workflowId: string): string | null => {
    const stored = loadStoredSession(workflowId);
    if (stored) {
      logger.debug('Found stored session', { workflowId, stored });
      return stored.sessionId;
    }
    return null;
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

    const workflowId = getWorkflowIdFromContext();
    if (workflowId) {
      clearStoredSession(workflowId);
    }

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
   * Request to load the session list
   * Actual loading happens in the channel hook
   */
  const loadSessionList = () => {
    logger.debug('Requesting session list');

    state = produce(state, draft => {
      draft.sessionListLoading = true;
    });

    notify('loadSessionList');
  };

  /**
   * Clear session data (used when stored session is invalid)
   * @internal Called by useAIAssistantChannel hook
   */
  const _clearSession = () => {
    logger.debug('Clearing invalid session');

    const workflowId = getWorkflowIdFromContext();
    if (workflowId) {
      clearStoredSession(workflowId);
    }

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
      draft.isLoading = false;
      draft.isSending = false;
    });

    // Save session to localStorage for persistence across reloads
    const workflowId = getWorkflowIdFromContext();
    if (workflowId) {
      saveSession(workflowId, session.id, session.session_type);
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

      // If it's an assistant message, we're no longer loading
      if (message.role === 'assistant') {
        draft.isLoading = false;
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
    loadStoredSessionForWorkflow,

    // Internal updates (prefixed with _)
    _setConnectionState,
    _setSession,
    _clearSession,
    _addMessage,
    _updateMessageStatus,
    _setSessionList,
  };
};

export type AIAssistantStoreInstance = ReturnType<
  typeof createAIAssistantStore
>;
