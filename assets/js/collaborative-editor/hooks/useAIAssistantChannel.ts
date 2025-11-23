/**
 * useAIAssistantChannel Hook
 *
 * Manages Phoenix Channel connection for AI Assistant communication.
 * Handles session creation, message sending, and real-time updates.
 *
 * ## Usage:
 *
 * ```typescript
 * const aiStore = useAIStore();
 * const { sendMessage, retryMessage } = useAIAssistantChannel(aiStore);
 *
 * // Send a message
 * sendMessage('How do I fetch data from DHIS2?', {
 *   attach_code: true,
 *   attach_logs: false
 * });
 * ```
 *
 * ## Features:
 * - Automatic connection/reconnection based on store state
 * - Real-time message updates via Phoenix Channel
 * - Error handling and retry logic
 * - Type-safe message sending for both session types
 */

import { useEffect, useRef, useCallback, useSyncExternalStore } from 'react';

import { useSocket } from '../../react/contexts/SocketProvider';
import _logger from '../../utils/logger';
import type {
  AIAssistantState,
  AIAssistantStore,
  Message,
  MessageOptions,
  MessageStatus,
  SessionType,
} from '../types/ai-assistant';

const logger = _logger.ns('useAIAssistantChannel').seal();

// Phoenix Channel type (incomplete in library, so we define what we need)
interface PhoenixChannel {
  join: () => PhoenixPush;
  on: (event: string, callback: (payload: unknown) => void) => void;
  push: (event: string, payload: unknown) => PhoenixPush;
  leave: () => PhoenixPush;
}

interface PhoenixPush {
  receive: (
    status: string,
    callback: (response: unknown) => void
  ) => PhoenixPush;
}

interface PhoenixSocket {
  channel: (topic: string, params: Record<string, unknown>) => PhoenixChannel;
  isConnected: () => boolean;
}

interface JoinResponse {
  session_id: string;
  session_type: SessionType;
  messages: Message[];
}

interface MessageResponse {
  message: Message;
}

interface ErrorResponse {
  reason: string;
  errors?: Record<string, string[]>;
}

export const useAIAssistantChannel = (store: AIAssistantStore) => {
  const { socket } = useSocket();
  const channelRef = useRef<PhoenixChannel | null>(null);

  // Subscribe to connection state changes
  const connectionState = useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.connectionState)
  );

  // Subscribe to session list loading requests
  const sessionListLoading = useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionListLoading)
  );

  /**
   * Join AI Assistant channel
   */
  const joinChannel = useCallback(() => {
    const state = store.getSnapshot(); // Get fresh state

    if (!socket || !state.sessionType) {
      logger.warn('Cannot join channel: socket or session type missing');
      return;
    }

    // Cast socket to our interface (Phoenix types are incomplete)
    const phoenixSocket = socket as unknown as PhoenixSocket;

    // Determine topic based on session type and ID
    const sessionId = state.sessionId || 'new';
    const topic = `ai_assistant:${state.sessionType}:${sessionId}`;

    logger.debug('Joining AI Assistant channel', { topic });

    // Create channel
    const channel = phoenixSocket.channel(topic, buildJoinParams(state));

    // Set up event listeners before joining
    channel.on('new_message', (payload: unknown) => {
      const typedPayload = payload as { message: Message };
      logger.debug('Received new message', typedPayload);
      store._addMessage(typedPayload.message);
    });

    channel.on('message_status_changed', (payload: unknown) => {
      const typedPayload = payload as {
        message_id: string;
        status: MessageStatus;
      };
      logger.debug('Message status changed', typedPayload);
      store._updateMessageStatus(typedPayload.message_id, typedPayload.status);
    });

    // Join channel
    channel
      .join()
      .receive('ok', (response: unknown) => {
        const typedResponse = response as JoinResponse;
        logger.info('Successfully joined AI Assistant channel', typedResponse);
        store._setConnectionState('connected');

        // Set session data from response
        if (typedResponse.session_id) {
          store._setSession({
            id: typedResponse.session_id,
            session_type: typedResponse.session_type,
            messages: typedResponse.messages || [],
          });
        }
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ErrorResponse;
        logger.error('Failed to join AI Assistant channel', typedResponse);

        // If session not found, clear it from store (user can reconnect to create new)
        if (typedResponse.reason === 'session not found') {
          logger.warn('Stored session not found, clearing session ID');
          store._clearSession();
        }

        store._setConnectionState(
          'error',
          typedResponse.reason || 'Join failed'
        );
      })
      .receive('timeout', () => {
        logger.error('Channel join timeout');
        store._setConnectionState('error', 'Connection timeout');
      });

    channelRef.current = channel;
  }, [socket, store]);

  /**
   * Leave AI Assistant channel
   */
  const leaveChannel = useCallback(() => {
    if (channelRef.current) {
      logger.debug('Leaving AI Assistant channel');
      channelRef.current.leave();
      channelRef.current = null;
    }
  }, []);

  /**
   * Send a message to the AI
   */
  const sendMessage = useCallback(
    (content: string, options?: MessageOptions) => {
      const channel = channelRef.current;
      if (!channel) {
        logger.error('Cannot send message: channel not connected');
        return;
      }

      logger.debug('Sending message', { content, options });

      // Build payload based on session type and options
      const payload: Record<string, unknown> = {
        content,
        ...options,
      };

      channel
        .push('new_message', payload)
        .receive('ok', (response: unknown) => {
          const typedResponse = response as MessageResponse;
          logger.debug('Message sent successfully', typedResponse);
          // Add the user message to the store
          store._addMessage(typedResponse.message);
        })
        .receive('error', (response: unknown) => {
          const typedResponse = response as ErrorResponse;
          logger.error('Failed to send message', {
            reason: typedResponse.reason,
            errors: typedResponse.errors,
            payload,
          });
          store._setConnectionState('connected'); // Reset sending state
          // TODO: Show error toast with details
        })
        .receive('timeout', () => {
          logger.error('Message send timeout');
          store._setConnectionState('connected'); // Reset sending state
          // TODO: Show error toast
        });
    },
    [store]
  );

  /**
   * Retry a failed message
   */
  const retryMessage = useCallback(
    (messageId: string) => {
      const channel = channelRef.current;
      if (!channel) {
        logger.error('Cannot retry message: channel not connected');
        return;
      }

      logger.debug('Retrying message', { messageId });

      channel
        .push('retry_message', { message_id: messageId })
        .receive('ok', (response: unknown) => {
          const typedResponse = response as MessageResponse;
          logger.debug('Message retry successful', typedResponse);
          store._updateMessageStatus(
            typedResponse.message.id,
            typedResponse.message.status
          );
        })
        .receive('error', (response: unknown) => {
          const typedResponse = response as ErrorResponse;
          logger.error('Failed to retry message', typedResponse);
          // TODO: Show error toast
        });
    },
    [store]
  );

  /**
   * Mark AI disclaimer as read
   */
  const markDisclaimerRead = useCallback(() => {
    const channel = channelRef.current;
    if (!channel) {
      logger.error('Cannot mark disclaimer: channel not connected');
      return;
    }

    logger.debug('Marking disclaimer as read');

    channel
      .push('mark_disclaimer_read', {})
      .receive('ok', () => {
        logger.debug('Disclaimer marked as read');
        store.markDisclaimerRead();
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ErrorResponse;
        logger.error('Failed to mark disclaimer', typedResponse);
      });
  }, [store]);

  /**
   * Load session list from backend
   */
  const fetchSessionList = useCallback(
    (offset: number = 0, limit: number = 20) => {
      const channel = channelRef.current;
      if (!channel) {
        logger.error('Cannot load sessions: channel not connected');
        return;
      }

      logger.debug('Fetching session list', { offset, limit });

      channel
        .push('list_sessions', { offset, limit })
        .receive('ok', (response: unknown) => {
          const typedResponse =
            response as import('../types/ai-assistant').SessionListResponse;
          logger.debug('Session list loaded', typedResponse);
          store._setSessionList(typedResponse);
        })
        .receive('error', (response: unknown) => {
          const typedResponse = response as ErrorResponse;
          logger.error('Failed to load session list', typedResponse);
          // Reset loading state on error
          store._setSessionList({
            sessions: [],
            pagination: {
              total_count: 0,
              has_next_page: false,
              has_prev_page: false,
            },
          });
        });
    },
    [store]
  );

  // Effect: Connect/disconnect based on store state
  useEffect(() => {
    if (connectionState === 'connecting' && socket) {
      joinChannel();
    } else if (connectionState === 'disconnected') {
      leaveChannel();
    }
    // If connected, stay connected (do nothing)
  }, [connectionState, socket, joinChannel, leaveChannel]);

  // Effect: Load session list when requested
  useEffect(() => {
    if (sessionListLoading && connectionState === 'connected') {
      fetchSessionList();
    }
  }, [sessionListLoading, connectionState, fetchSessionList]);

  // Separate effect for cleanup on unmount only
  useEffect(() => {
    return () => {
      leaveChannel();
    };
  }, []); // Empty deps - only run on mount/unmount

  return {
    sendMessage,
    retryMessage,
    markDisclaimerRead,
    fetchSessionList,
  };
};

/**
 * Build join parameters based on session state
 */
function buildJoinParams(
  state: AIAssistantState
): Record<string, string | undefined> {
  const params: Record<string, string | undefined> = {};

  if (state.sessionType === 'job_code' && state.jobCodeContext) {
    params['job_id'] = state.jobCodeContext.job_id;

    if (state.jobCodeContext.follow_run_id) {
      params['follow_run_id'] = state.jobCodeContext.follow_run_id;
    }

    // If this is a new session, include the initial content
    if (!state.sessionId) {
      params['content'] = 'Hello, I need help with my job.';
    }
  } else if (
    state.sessionType === 'workflow_template' &&
    state.workflowTemplateContext
  ) {
    params['project_id'] = state.workflowTemplateContext.project_id;

    if (state.workflowTemplateContext.workflow_id) {
      params['workflow_id'] = state.workflowTemplateContext.workflow_id;
    }

    if (state.workflowTemplateContext.code) {
      params['code'] = state.workflowTemplateContext.code;
    }

    // If this is a new session, include the initial content
    if (!state.sessionId) {
      params['content'] = 'Help me build a workflow';
    }
  }

  return params;
}
