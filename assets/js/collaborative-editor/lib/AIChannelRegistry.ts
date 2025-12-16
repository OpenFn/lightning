/**
 * # AI Channel Registry
 *
 * Manages Phoenix Channel lifecycle for AI Assistant sessions with reference counting.
 *
 * ## Problem Solved
 * - Eliminates race conditions when switching between AI sessions/modes
 * - Prevents duplicate connections
 * - Enables fast context switching by reusing existing channels
 * - Centralizes channel management logic
 *
 * ## Architecture
 *
 * ```
 * Component A → subscribe('ai_assistant:job_code:session-1')
 *   ↓
 * Registry → getOrCreateChannel(topic)
 *   ↓
 * Phoenix Channel → join() + event handlers
 *
 * Component A unmounts → unsubscribe('ai_assistant:job_code:session-1')
 *   ↓
 * Registry → decrement ref count
 *   ↓
 * If refs = 0 → schedule cleanup (10s delay)
 *   ↓
 * If not resubscribed → channel.leave()
 * ```
 *
 * ## Usage
 *
 * ```typescript
 * const registry = new AIChannelRegistry(socket, store);
 *
 * // Component subscribes (joins if needed)
 * const channelId = useId();
 * useEffect(() => {
 *   registry.subscribe(topic, channelId, context);
 *   return () => registry.unsubscribe(topic, channelId);
 * }, [topic]);
 *
 * // Send message through registry
 * registry.sendMessage(topic, content, options);
 * ```
 */

import _logger from '#/utils/logger';

import type { ChannelError } from '../hooks/useChannel';
import { formatChannelErrorMessage } from '../lib/errors';
import { notifications } from '../lib/notifications';
import type {
  AIAssistantStore,
  JobCodeContext,
  Message,
  MessageOptions,
  MessageStatus,
  SessionType,
  WorkflowTemplateContext,
} from '../types/ai-assistant';

const logger = _logger.ns('AIChannelRegistry').seal();

// Phoenix Channel types (incomplete in library)
type ChannelCallback = (payload: unknown) => void;

interface PhoenixChannel {
  join: () => PhoenixPush;
  on: (event: string, callback: ChannelCallback) => void;
  off: (event: string, callback: ChannelCallback) => void;
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
  error?: string;
}

/**
 * Channel entry with reference counting and cleanup timer
 */
interface ChannelEntry {
  topic: string;
  channel: PhoenixChannel;
  subscribers: Set<string>; // Component IDs
  status: 'connecting' | 'connected' | 'error';
  context: JobCodeContext | WorkflowTemplateContext;
  cleanupTimer: NodeJS.Timeout | null;
  // Store handler references for cleanup
  handlers: {
    newMessage: ChannelCallback;
    messageStatusChanged: ChannelCallback;
  };
}

/**
 * Channel Registry for AI Assistant
 *
 * Manages Phoenix Channel connections with reference counting and lazy cleanup.
 */
export class AIChannelRegistry {
  private channels = new Map<string, ChannelEntry>();
  private socket: PhoenixSocket;
  private store: AIAssistantStore;
  // Cleanup delay for graceful session switching (not panel close)
  // Short enough to not waste resources, long enough to handle accidental clicks
  private cleanupDelayMs = 2_000; // 2 seconds

  constructor(socket: PhoenixSocket, store: AIAssistantStore) {
    this.socket = socket;
    this.store = store;
  }

  /**
   * Subscribe to a channel topic
   *
   * - Creates and joins channel if it doesn't exist
   * - Increments reference count if channel already exists
   * - Cancels any pending cleanup timer
   *
   * @param topic - Channel topic (e.g., 'ai_assistant:job_code:session-1')
   * @param subscriberId - Unique ID for the subscriber (use React.useId())
   * @param context - Session context (job or workflow)
   */
  subscribe(
    topic: string,
    subscriberId: string,
    context: JobCodeContext | WorkflowTemplateContext
  ): void {
    const entry = this.channels.get(topic);

    if (entry) {
      // Channel already exists - add subscriber
      logger.debug('Reusing existing channel', { topic, subscriberId });
      entry.subscribers.add(subscriberId);

      // Cancel cleanup if scheduled
      if (entry.cleanupTimer) {
        clearTimeout(entry.cleanupTimer);
        entry.cleanupTimer = null;
      }

      // Update store connection state to reflect the reused channel
      // This ensures UI shows correct state when resubscribing
      if (entry.status === 'connected') {
        this.store._setConnectionState('connected');

        // If this is a session channel (not 'new' or 'list'), restore session state
        const sessionIdMatch = topic.match(/:([^:]+)$/);
        const sessionId = sessionIdMatch?.[1];
        if (sessionId && sessionId !== 'new' && sessionId !== 'list') {
          // Extract session type from topic
          const sessionTypeMatch = topic.match(/ai_assistant:([^:]+):/);
          const sessionType = sessionTypeMatch?.[1] as SessionType;

          // Restore session in store (messages will be fetched by channel if needed)
          if (sessionType) {
            this.store._setSession({
              id: sessionId,
              session_type: sessionType,
              messages: [], // Messages will be loaded by the component
            });
          }
        }
      } else if (entry.status === 'connecting') {
        this.store._setConnectionState('connecting');
      } else if (entry.status === 'error') {
        this.store._setConnectionState('error', 'Channel connection failed');
      }

      return;
    }

    // Create new channel entry
    logger.debug('Creating new channel', { topic, subscriberId });

    // Set store to connecting state BEFORE creating channel
    // This ensures UI shows loading indicator while channel joins
    // Passing undefined clears any previous connection error
    this.store._setConnectionState('connecting', undefined);

    const channel = this.socket.channel(topic, this.buildJoinParams(context));

    // Set up event handlers and get references for cleanup
    const handlers = this.setupEventHandlers(channel);

    const newEntry: ChannelEntry = {
      topic,
      channel,
      subscribers: new Set([subscriberId]),
      status: 'connecting',
      context,
      cleanupTimer: null,
      handlers,
    };

    this.channels.set(topic, newEntry);

    // Join channel
    this.joinChannel(newEntry);
  }

  /**
   * Unsubscribe from a channel topic
   *
   * - Decrements reference count
   * - Schedules cleanup if no subscribers remain (with delay for graceful switching)
   *
   * @param topic - Channel topic
   * @param subscriberId - Unique ID for the subscriber
   */
  unsubscribe(topic: string, subscriberId: string): void {
    const entry = this.channels.get(topic);

    if (!entry) {
      logger.warn('Cannot unsubscribe: channel not found', {
        topic,
        subscriberId,
      });
      return;
    }

    entry.subscribers.delete(subscriberId);
    logger.debug('Unsubscribed from channel', {
      topic,
      subscriberId,
      remainingSubscribers: entry.subscribers.size,
    });

    // Schedule cleanup if no subscribers remain
    if (entry.subscribers.size === 0) {
      logger.debug('No subscribers remaining, scheduling cleanup', { topic });
      entry.cleanupTimer = setTimeout(() => {
        this.cleanup(topic);
      }, this.cleanupDelayMs);
    }
  }

  /**
   * Unsubscribe and immediately cleanup (no delay)
   * Use this when panel is closing, not just switching sessions
   *
   * @param topic - Channel topic
   * @param subscriberId - Unique ID for the subscriber
   */
  unsubscribeImmediate(topic: string, subscriberId: string): void {
    const entry = this.channels.get(topic);

    if (!entry) {
      logger.warn('Cannot unsubscribe: channel not found', {
        topic,
        subscriberId,
      });
      return;
    }

    entry.subscribers.delete(subscriberId);
    logger.debug('Unsubscribed from channel (immediate)', {
      topic,
      subscriberId,
      remainingSubscribers: entry.subscribers.size,
    });

    // Immediate cleanup if no subscribers remain
    if (entry.subscribers.size === 0) {
      logger.debug('No subscribers remaining, immediate cleanup', { topic });
      this.cleanup(topic);
    }
  }

  /**
   * Send a message through the channel
   *
   * @param topic - Channel topic
   * @param content - Message content
   * @param options - Message options (attach_code, attach_logs, etc.)
   */
  sendMessage(topic: string, content: string, options?: MessageOptions): void {
    const entry = this.channels.get(topic);

    if (!entry) {
      logger.error('Cannot send message: channel not found', { topic });
      return;
    }

    if (entry.status !== 'connected') {
      logger.error('Cannot send message: channel not connected', {
        topic,
        status: entry.status,
      });
      return;
    }

    const payload: Record<string, unknown> = {
      content,
      ...options,
    };

    logger.debug('Sending message', { topic, payload });

    entry.channel
      .push('new_message', payload)
      .receive('ok', (response: unknown) => {
        const typedResponse = response as MessageResponse;
        this.store._addMessage(typedResponse.message);

        // If there's an error in the response, show notification
        if (typedResponse.error) {
          notifications.alert({
            title: 'Message limit exceeded',
            description: typedResponse.error,
          });
        }
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ChannelError;
        logger.error('Failed to send message', {
          type: typedResponse.type,
          errors: typedResponse.errors,
          payload,
        });

        // Show notification for all errors
        const message = formatChannelErrorMessage({
          type: typedResponse.type,
          errors: typedResponse.errors || {},
        });
        notifications.alert({
          title: 'Failed to send message',
          description: message,
        });

        this.store._setConnectionState('connected');
      })
      .receive('timeout', () => {
        logger.error('Message send timeout');
        this.store._setConnectionState('connected');
      });
  }

  /**
   * Retry a failed message
   *
   * @param topic - Channel topic
   * @param messageId - Message ID to retry
   */
  retryMessage(topic: string, messageId: string): void {
    const entry = this.channels.get(topic);

    if (!entry) {
      logger.error('Cannot retry message: channel not found', { topic });
      return;
    }

    entry.channel
      .push('retry_message', { message_id: messageId })
      .receive('ok', (response: unknown) => {
        const typedResponse = response as MessageResponse;
        this.store._updateMessageStatus(
          typedResponse.message.id,
          typedResponse.message.status
        );
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ChannelError;
        logger.error('Failed to retry message', typedResponse);

        // Show notification for retry errors
        const message = formatChannelErrorMessage({
          type: typedResponse.type,
          errors: typedResponse.errors || {},
        });
        notifications.alert({
          title: 'Failed to retry message',
          description: message,
        });

        // Keep the message status as 'error' and clear loading state
        this.store._updateMessageStatus(messageId, 'error');
      });
  }

  /**
   * Mark disclaimer as read through the channel
   *
   * @param topic - Channel topic
   */
  markDisclaimerRead(topic: string): void {
    const entry = this.channels.get(topic);

    if (!entry) {
      logger.error('Cannot mark disclaimer: channel not found', { topic });
      return;
    }

    entry.channel
      .push('mark_disclaimer_read', {})
      .receive('ok', () => {
        this.store.markDisclaimerRead();
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ChannelError;
        logger.error('Failed to mark disclaimer', typedResponse);
      });
  }

  /**
   * Load sessions list through the channel
   *
   * @param topic - Channel topic
   * @param offset - Pagination offset
   * @param limit - Number of sessions to fetch
   */
  loadSessions(topic: string, offset = 0, limit = 20): Promise<void> {
    const entry = this.channels.get(topic);

    if (!entry) {
      logger.error('Cannot load sessions: channel not found', { topic });
      return Promise.reject(new Error('Channel not found'));
    }

    return new Promise<void>((resolve, reject) => {
      entry.channel
        .push('list_sessions', { offset, limit })
        .receive('ok', (response: unknown) => {
          // Backend returns SessionListResponse type
          const typedResponse =
            response as import('../types/ai-assistant').SessionListResponse;
          this.store._setSessionList(typedResponse);
          resolve();
        })
        .receive('error', (response: unknown) => {
          const typedResponse = response as ChannelError;
          logger.error('Failed to load sessions via channel', typedResponse);
          const message = formatChannelErrorMessage(typedResponse);
          reject(new Error(message));
        })
        .receive('timeout', () => {
          logger.error('Load sessions timeout');
          reject(new Error('Request timeout'));
        });
    });
  }

  /**
   * Update job context through the channel
   *
   * @param topic - Channel topic
   * @param context - Updated context fields
   */
  updateContext(
    topic: string,
    context: {
      job_adaptor?: string;
      job_body?: string;
      job_name?: string;
    }
  ): void {
    const entry = this.channels.get(topic);

    if (!entry) {
      logger.error('Cannot update context: channel not found', { topic });
      return;
    }

    this.store.updateContext(context);

    entry.channel
      .push('update_context', context)
      .receive('ok', () => {})
      .receive('error', (response: unknown) => {
        const typedResponse = response as ChannelError;
        logger.error('Failed to update context', typedResponse);
      })
      .receive('timeout', () => {
        logger.error('Context update timeout');
      });
  }

  /**
   * Get channel status
   *
   * @param topic - Channel topic
   * @returns Channel status or null if not found
   */
  getChannelStatus(topic: string): 'connecting' | 'connected' | 'error' | null {
    const entry = this.channels.get(topic);
    return entry?.status ?? null;
  }

  /**
   * Check if a channel has active subscribers
   *
   * @param topic - Channel topic
   * @returns true if channel has subscribers
   */
  hasSubscribers(topic: string): boolean {
    const entry = this.channels.get(topic);
    return (entry?.subscribers.size ?? 0) > 0;
  }

  /**
   * Destroy all channels (cleanup on unmount)
   */
  destroy(): void {
    logger.debug('Destroying all channels', {
      count: this.channels.size,
    });

    for (const entry of this.channels.values()) {
      if (entry.cleanupTimer) {
        clearTimeout(entry.cleanupTimer);
      }
      // Remove event handlers to prevent memory leaks
      entry.channel.off('new_message', entry.handlers.newMessage);
      entry.channel.off(
        'message_status_changed',
        entry.handlers.messageStatusChanged
      );
      entry.channel.leave();
    }

    this.channels.clear();
  }

  /**
   * Set up event handlers for a channel
   * Returns handler references for cleanup
   */
  private setupEventHandlers(
    channel: PhoenixChannel
  ): ChannelEntry['handlers'] {
    const newMessageHandler: ChannelCallback = (payload: unknown) => {
      const typedPayload = payload as { message: Message };
      this.store._addMessage(typedPayload.message);
    };

    const messageStatusChangedHandler: ChannelCallback = (payload: unknown) => {
      const typedPayload = payload as {
        message_id: string;
        status: MessageStatus;
      };
      this.store._updateMessageStatus(
        typedPayload.message_id,
        typedPayload.status
      );
    };

    channel.on('new_message', newMessageHandler);
    channel.on('message_status_changed', messageStatusChangedHandler);

    return {
      newMessage: newMessageHandler,
      messageStatusChanged: messageStatusChangedHandler,
    };
  }

  /**
   * Join a channel and handle responses
   */
  private joinChannel(entry: ChannelEntry): void {
    logger.debug('Joining channel', { topic: entry.topic });

    entry.channel
      .join()
      .receive('ok', (response: unknown) => {
        const typedResponse = response as JoinResponse;

        entry.status = 'connected';
        this.store._setConnectionState('connected');

        if (typedResponse.session_id) {
          this.store._setSession({
            id: typedResponse.session_id,
            session_type: typedResponse.session_type,
            messages: typedResponse.messages || [],
          });
        }

        // Set disclaimer state from backend
        if (typedResponse.has_read_disclaimer) {
          this.store.markDisclaimerRead();
        }

        logger.debug('Channel joined successfully', { topic: entry.topic });
      })
      .receive('error', (response: unknown) => {
        const typedResponse = response as ChannelError;
        logger.error('Failed to join channel', typedResponse);

        entry.status = 'error';

        const errorMessage = formatChannelErrorMessage(typedResponse);

        if (
          errorMessage === 'session not found' ||
          errorMessage === 'session type mismatch'
        ) {
          logger.warn(
            'Session issue detected, clearing session ID from store',
            errorMessage
          );
          this.store._clearSession();
        }

        if (
          errorMessage.includes('Ecto.NoResultsError') ||
          errorMessage.includes('expected at least one result') ||
          errorMessage.includes('join crashed')
        ) {
          logger.error(
            'Job not found - either not saved yet or deleted during workflow update',
            typedResponse
          );
          this.store._clearSession();

          // Show notification
          notifications.alert({
            title: 'Job not available',
            description:
              "This job hasn't been saved to the database yet, or was deleted. Please save the workflow first.",
          });
        }

        this.store._setConnectionState('error', errorMessage || 'Join failed');
      })
      .receive('timeout', () => {
        logger.error('Channel join timeout');
        entry.status = 'error';
        this.store._setConnectionState('error', 'Connection timeout');
      });
  }

  /**
   * Clean up a channel (leave and remove from registry)
   */
  private cleanup(topic: string): void {
    const entry = this.channels.get(topic);

    if (!entry) {
      return;
    }

    // Double-check no subscribers were added during cleanup delay
    if (entry.subscribers.size > 0) {
      logger.debug('Channel gained subscribers, cancelling cleanup', { topic });
      return;
    }

    logger.debug('Cleaning up channel', { topic });

    // Remove event handlers to prevent memory leaks
    entry.channel.off('new_message', entry.handlers.newMessage);
    entry.channel.off(
      'message_status_changed',
      entry.handlers.messageStatusChanged
    );

    entry.channel.leave();
    this.channels.delete(topic);

    // Reset store connection state when the last channel is cleaned up
    // This ensures UI doesn't show stale "connecting" state
    if (this.channels.size === 0) {
      this.store._setConnectionState('disconnected');
    }
  }

  /**
   * Build join parameters based on context
   */
  private buildJoinParams(
    context: JobCodeContext | WorkflowTemplateContext
  ): Record<string, string | boolean | undefined> {
    const params: Record<string, string | boolean | undefined> = {};

    // Determine session type from context
    if ('job_id' in context) {
      // JobCodeContext
      params['job_id'] = context.job_id;

      if (context.follow_run_id) {
        params['follow_run_id'] = context.follow_run_id;
      }
      if (context.job_name) {
        params['job_name'] = context.job_name;
      }
      if (context.job_body) {
        params['job_body'] = context.job_body;
      }
      if (context.job_adaptor) {
        params['job_adaptor'] = context.job_adaptor;
      }
      if (context.workflow_id) {
        params['workflow_id'] = context.workflow_id;
      }
      if (context.content) {
        params['content'] = context.content;
      }
      if (context.attach_code) {
        params['attach_code'] = true;
      }
      if (context.attach_logs) {
        params['attach_logs'] = true;
      }
      if (context.attach_io_data) {
        params['attach_io_data'] = true;
      }
      if (context.step_id) {
        params['step_id'] = context.step_id;
      }
    } else {
      // WorkflowTemplateContext
      params['project_id'] = context.project_id;

      if (context.workflow_id) {
        params['workflow_id'] = context.workflow_id;
      }
      if (context.code) {
        params['code'] = context.code;
      }
      if (context.content) {
        params['content'] = context.content;
      }
    }

    return params;
  }
}
