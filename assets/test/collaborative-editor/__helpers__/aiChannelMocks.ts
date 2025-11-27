/**
 * AI Assistant Channel Mock Helpers
 *
 * Specialized mocks for AI Assistant Phoenix Channel interactions.
 * These helpers create mocks that simulate the AI Assistant channel's
 * specific events and response formats.
 *
 * @example
 * import {
 *   createAIAssistantChannelMock,
 *   mockNewMessageResponse
 * } from "./__helpers__";
 */

import { vi } from 'vitest';
import {
  createMockPhoenixChannel,
  createMockChannelPushOk,
} from './channelMocks';
import type { MockPhoenixChannel } from '../mocks/phoenixChannel';
import type {
  AIMessage,
  AISession,
  SessionType,
} from '../../../js/collaborative-editor/types/ai-assistant';
import { createMockAIMessage, createMockAISession } from './aiAssistantHelpers';

/**
 * Pagination metadata for session lists
 */
export interface PaginationMeta {
  total_count: number;
  has_next_page: boolean;
  has_prev_page: boolean;
}

/**
 * Creates a specialized mock Phoenix channel for AI Assistant
 *
 * @param sessionType - Type of AI session ('job_code' or 'workflow_template')
 * @param sessionId - Optional session ID (defaults to 'new' for new sessions)
 * @returns Mocked Phoenix channel configured for AI Assistant
 *
 * @example
 * const mockChannel = createAIAssistantChannelMock('job_code', 'session-123');
 */
export function createAIAssistantChannelMock(
  sessionType: SessionType,
  sessionId: string = 'new'
): MockPhoenixChannel {
  const topic = `ai_assistant:${sessionType}:${sessionId}`;
  return createMockPhoenixChannel(topic);
}

/**
 * Mocks a successful session join response
 *
 * @param channel - Mock Phoenix channel
 * @param session - AI session data to return
 * @param messages - Optional initial messages
 *
 * @example
 * mockSessionJoinResponse(mockChannel, {
 *   id: 'session-123',
 *   session_type: 'job_code',
 *   title: 'My Session'
 * }, [userMessage, assistantMessage]);
 */
export function mockSessionJoinResponse(
  channel: MockPhoenixChannel,
  session: Partial<AISession>,
  messages: AIMessage[] = []
): void {
  const fullSession = createMockAISession(session);

  channel.push = createMockChannelPushOk({
    session_id: fullSession.id,
    session_type: fullSession.session_type,
    messages: messages.map(m => ({
      id: m.id,
      role: m.role,
      content: m.content,
      timestamp: m.timestamp,
    })),
  });
}

/**
 * Mocks a successful new message response
 *
 * @param channel - Mock Phoenix channel
 * @param message - AI message to return
 *
 * @example
 * mockNewMessageResponse(mockChannel, {
 *   id: 'msg-123',
 *   role: 'assistant',
 *   content: 'Here is your answer...'
 * });
 */
export function mockNewMessageResponse(
  channel: MockPhoenixChannel,
  message: Partial<AIMessage>
): void {
  const fullMessage = createMockAIMessage(message);

  channel.push = createMockChannelPushOk({
    message: {
      id: fullMessage.id,
      role: fullMessage.role,
      content: fullMessage.content,
      timestamp: fullMessage.timestamp,
    },
  });
}

/**
 * Mocks a successful list sessions response
 *
 * @param channel - Mock Phoenix channel
 * @param sessions - Array of AI sessions
 * @param pagination - Pagination metadata
 *
 * @example
 * mockListSessionsResponse(mockChannel, [session1, session2], {
 *   total_count: 2,
 *   has_next_page: false,
 *   has_prev_page: false
 * });
 */
export function mockListSessionsResponse(
  channel: MockPhoenixChannel,
  sessions: AISession[],
  pagination: PaginationMeta
): void {
  channel.push = createMockChannelPushOk({
    sessions: sessions.map(s => ({
      id: s.id,
      title: s.title,
      session_type: s.session_type,
      created_at: s.created_at,
      updated_at: s.updated_at,
      message_count: s.message_count,
      workflow_name: s.workflow_name,
      job_name: s.job_name,
    })),
    pagination,
  });
}

/**
 * Mocks a successful context update response
 *
 * @param channel - Mock Phoenix channel
 *
 * @example
 * mockContextUpdateResponse(mockChannel);
 */
export function mockContextUpdateResponse(channel: MockPhoenixChannel): void {
  channel.push = createMockChannelPushOk({
    success: true,
  });
}

/**
 * Emits a new_message event to the channel
 *
 * @param channel - Mock Phoenix channel
 * @param message - AI message to emit
 *
 * @example
 * emitNewMessageEvent(mockChannel, {
 *   id: 'msg-123',
 *   role: 'assistant',
 *   content: 'AI response here'
 * });
 */
export function emitNewMessageEvent(
  channel: MockPhoenixChannel,
  message: Partial<AIMessage>
): void {
  const fullMessage = createMockAIMessage(message);

  channel._test.emit('new_message', {
    message: {
      id: fullMessage.id,
      role: fullMessage.role,
      content: fullMessage.content,
      timestamp: fullMessage.timestamp,
    },
  });
}

/**
 * Emits a message_updated event to the channel (for streaming updates)
 *
 * @param channel - Mock Phoenix channel
 * @param message - Partial or complete AI message
 *
 * @example
 * // Simulate streaming
 * emitMessageUpdatedEvent(mockChannel, {
 *   id: 'msg-123',
 *   content: 'Here is the first part...'
 * });
 *
 * emitMessageUpdatedEvent(mockChannel, {
 *   id: 'msg-123',
 *   content: 'Here is the first part... and more'
 * });
 */
export function emitMessageUpdatedEvent(
  channel: MockPhoenixChannel,
  message: Partial<AIMessage>
): void {
  channel._test.emit('message_updated', {
    message: {
      id: message.id,
      role: message.role,
      content: message.content,
      timestamp: message.timestamp,
    },
  });
}

/**
 * Emits a session_created event to the channel
 *
 * @param channel - Mock Phoenix channel
 * @param session - AI session that was created
 *
 * @example
 * emitSessionCreatedEvent(mockChannel, {
 *   id: 'session-123',
 *   title: 'New Session'
 * });
 */
export function emitSessionCreatedEvent(
  channel: MockPhoenixChannel,
  session: Partial<AISession>
): void {
  const fullSession = createMockAISession(session);

  channel._test.emit('session_created', {
    session: {
      id: fullSession.id,
      title: fullSession.title,
      session_type: fullSession.session_type,
      created_at: fullSession.created_at,
    },
  });
}

/**
 * Emits an error event to the channel
 *
 * @param channel - Mock Phoenix channel
 * @param error - Error message or object
 *
 * @example
 * emitErrorEvent(mockChannel, 'Failed to process request');
 */
export function emitErrorEvent(
  channel: MockPhoenixChannel,
  error: string | { message: string; type?: string }
): void {
  const errorObj =
    typeof error === 'string' ? { message: error, type: 'error' } : error;

  channel._test.emit('error', {
    error: errorObj,
  });
}

/**
 * Creates a mock channel with pre-configured responses for common scenarios
 *
 * @param scenario - Scenario name
 * @returns Configured mock channel
 *
 * @example
 * // Successful message flow
 * const channel = createMockChannelForScenario('successful_message');
 *
 * @example
 * // Error scenario
 * const channel = createMockChannelForScenario('message_error');
 */
export function createMockChannelForScenario(
  scenario:
    | 'successful_message'
    | 'message_error'
    | 'session_list'
    | 'context_update'
    | 'streaming_message'
): MockPhoenixChannel {
  const channel = createMockPhoenixChannel(`ai_assistant:${scenario}`);

  switch (scenario) {
    case 'successful_message':
      mockNewMessageResponse(channel, {
        role: 'assistant',
        content: 'This is a test response from the AI assistant.',
      });
      break;

    case 'message_error':
      channel.push = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'error') {
            callback({
              errors: { base: ['Failed to process message'] },
              type: 'processing_error',
            });
          }
          return { receive: vi.fn() };
        }),
      })) as any;
      break;

    case 'session_list':
      mockListSessionsResponse(
        channel,
        [
          createMockAISession({ id: 'session-1', title: 'Session 1' }),
          createMockAISession({ id: 'session-2', title: 'Session 2' }),
        ],
        {
          total_count: 2,
          has_next_page: false,
          has_prev_page: false,
        }
      );
      break;

    case 'context_update':
      mockContextUpdateResponse(channel);
      break;

    case 'streaming_message':
      // For streaming, we'll emit multiple updates
      channel.push = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'ok') {
            callback({
              message: {
                id: 'msg-stream',
                role: 'assistant',
                content: '',
              },
            });

            // Simulate streaming chunks
            setTimeout(() => {
              emitMessageUpdatedEvent(channel, {
                id: 'msg-stream',
                content: 'First ',
              });
            }, 10);

            setTimeout(() => {
              emitMessageUpdatedEvent(channel, {
                id: 'msg-stream',
                content: 'First part ',
              });
            }, 20);

            setTimeout(() => {
              emitMessageUpdatedEvent(channel, {
                id: 'msg-stream',
                content: 'First part of streaming response.',
              });
            }, 30);
          }
          return { receive: vi.fn() };
        }),
      })) as any;
      break;
  }

  return channel;
}

/**
 * Simulates a complete message exchange with user message and AI response
 *
 * @param channel - Mock Phoenix channel
 * @param userMessage - User's message content
 * @param assistantResponse - AI's response content
 * @param delay - Delay before AI response in ms (default: 100)
 * @returns Promise that resolves after the exchange
 *
 * @example
 * await simulateMessageExchange(
 *   mockChannel,
 *   'Help me create a workflow',
 *   'Here is a workflow template...'
 * );
 */
export async function simulateMessageExchange(
  channel: MockPhoenixChannel,
  userMessage: string,
  assistantResponse: string,
  delay: number = 100
): Promise<void> {
  // First, configure push to accept the user message
  mockNewMessageResponse(channel, {
    role: 'user',
    content: userMessage,
  });

  // After a delay, emit the assistant response
  return new Promise(resolve => {
    setTimeout(() => {
      emitNewMessageEvent(channel, {
        role: 'assistant',
        content: assistantResponse,
      });
      resolve();
    }, delay);
  });
}
