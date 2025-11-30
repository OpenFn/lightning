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
  has_read_disclaimer: boolean;
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

  const connectionState = useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.connectionState)
  );

  /**
   * Join AI Assistant channel
   */
  const joinChannel = useCallback(() => {
    const state = store.getSnapshot();

    if (!socket || !state.sessionType) {
      logger.warn('Cannot join channel: socket or session type missing');
      return;
    }

    // IMPORTANT: Leave any existing channel before joining a new one
    // This prevents duplicate connections when switching sessions/modes
    if (channelRef.current) {
      channelRef.current.leave();
      channelRef.current = null;
    }

    const phoenixSocket = socket as unknown as PhoenixSocket;

    const sessionId = state.sessionId || 'new';
    const topic = `ai_assistant:${state.sessionType}:${sessionId}`;

    const channel = phoenixSocket.channel(topic, buildJoinParams(state));

    channel.on('new_message', (payload: unknown) => {
      const typedPayload = payload as { message: Message };
      store._addMessage(typedPayload.message);
    });

    channel.on('message_status_changed', (payload: unknown) => {
      const typedPayload = payload as {
        message_id: string;
        status: MessageStatus;
      };
      store._updateMessageStatus(typedPayload.message_id, typedPayload.status);
    });

    channel
      .join()
      .receive('ok', (response: unknown) => {
        const typedResponse = response as JoinResponse;

        store._setConnectionState('connected');

        if (typedResponse.session_id) {
          store._setSession({
            id: typedResponse.session_id,
            session_type: typedResponse.session_type,
            messages: typedResponse.messages || [],
          });
        }

        // Set disclaimer state from backend
        if (typedResponse.has_read_disclaimer) {
          store.markDisclaimerRead();
        }
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ErrorResponse;
        logger.error('Failed to join AI Assistant channel', typedResponse);

        if (
          typedResponse.reason === 'session not found' ||
          typedResponse.reason === 'session type mismatch'
        ) {
          logger.warn(
            'Session issue detected, clearing session ID from store',
            typedResponse.reason
          );
          store._clearSession();
        }

        if (
          typedResponse.reason &&
          (typedResponse.reason.includes('Ecto.NoResultsError') ||
            typedResponse.reason.includes('expected at least one result') ||
            typedResponse.reason.includes('join crashed'))
        ) {
          logger.error(
            'Job not found - either not saved yet or deleted during workflow update',
            typedResponse
          );
          store._clearSession();

          setTimeout(() => {
            void import('../lib/notifications')
              .then(({ notifications }) => {
                notifications.alert({
                  title: 'Job not available',
                  description:
                    "This job hasn't been saved to the database yet, or was deleted. Please save the workflow first.",
                });
                return;
              })
              .catch(err => {
                logger.error('Failed to show notification', err);
              });
          }, 100);
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

      const payload: Record<string, unknown> = {
        content,
        ...options,
      };

      channel
        .push('new_message', payload)
        .receive('ok', (response: unknown) => {
          const typedResponse = response as MessageResponse;
          store._addMessage(typedResponse.message);
        })
        .receive('error', (response: unknown) => {
          const typedResponse = response as ErrorResponse;
          logger.error('Failed to send message', {
            reason: typedResponse.reason,
            errors: typedResponse.errors,
            payload,
          });
          store._setConnectionState('connected');
        })
        .receive('timeout', () => {
          logger.error('Message send timeout');
          store._setConnectionState('connected');
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

      channel
        .push('retry_message', { message_id: messageId })
        .receive('ok', (response: unknown) => {
          const typedResponse = response as MessageResponse;
          store._updateMessageStatus(
            typedResponse.message.id,
            typedResponse.message.status
          );
        })
        .receive('error', (response: unknown) => {
          const typedResponse = response as ErrorResponse;
          logger.error('Failed to retry message', typedResponse);
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

    channel
      .push('mark_disclaimer_read', {})
      .receive('ok', () => {
        store.markDisclaimerRead();
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ErrorResponse;
        logger.error('Failed to mark disclaimer', typedResponse);
      });
  }, [store]);

  useEffect(() => {
    if (connectionState === 'connecting' && socket) {
      joinChannel();
    } else if (connectionState === 'disconnected') {
      leaveChannel();
    }
  }, [connectionState, socket, joinChannel, leaveChannel]);

  useEffect(() => {
    return () => {
      leaveChannel();
    };
  }, []);

  /**
   * Load sessions list via channel
   */
  const loadSessions = useCallback(
    (offset = 0, limit = 20) => {
      const channel = channelRef.current;
      if (!channel) {
        logger.error('Cannot load sessions: channel not connected');
        return Promise.reject(new Error('Channel not connected'));
      }

      return new Promise<void>((resolve, reject) => {
        channel
          .push('list_sessions', { offset, limit })
          .receive('ok', (response: unknown) => {
            const typedResponse = response as {
              sessions: unknown[];
              pagination: {
                total_count: number;
                has_next_page: boolean;
                has_prev_page: boolean;
              };
            };
            store._setSessionList(typedResponse);
            resolve();
          })
          .receive('error', (response: unknown) => {
            const typedResponse = response as ErrorResponse;
            logger.error('Failed to load sessions via channel', typedResponse);
            reject(
              new Error(typedResponse.reason || 'Failed to load sessions')
            );
          })
          .receive('timeout', () => {
            logger.error('Load sessions timeout');
            reject(new Error('Request timeout'));
          });
      });
    },
    [store]
  );

  /**
   * Update job context (adaptor, body, name) for the active session
   */
  const updateContext = useCallback(
    (context: {
      job_adaptor?: string;
      job_body?: string;
      job_name?: string;
    }) => {
      const channel = channelRef.current;
      if (!channel) {
        logger.error('Cannot update context: channel not connected');
        return;
      }

      store.updateContext(context);

      channel
        .push('update_context', context)
        .receive('ok', () => {})
        .receive('error', (response: unknown) => {
          const typedResponse = response as ErrorResponse;
          logger.error('Failed to update context', typedResponse);
        })
        .receive('timeout', () => {
          logger.error('Context update timeout');
        });
    },
    [store]
  );

  return {
    sendMessage,
    retryMessage,
    markDisclaimerRead,
    loadSessions,
    updateContext,
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

    if (state.jobCodeContext.job_name) {
      params['job_name'] = state.jobCodeContext.job_name;
    }
    if (state.jobCodeContext.job_body) {
      params['job_body'] = state.jobCodeContext.job_body;
    }
    if (state.jobCodeContext.job_adaptor) {
      params['job_adaptor'] = state.jobCodeContext.job_adaptor;
    }
    if (state.jobCodeContext.workflow_id) {
      params['workflow_id'] = state.jobCodeContext.workflow_id;
    }

    if (!state.sessionId && state.jobCodeContext.content) {
      params['content'] = state.jobCodeContext.content;
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

    if (!state.sessionId && state.workflowTemplateContext.content) {
      params['content'] = state.workflowTemplateContext.content;
    }
  }

  return params;
}
