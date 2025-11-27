/**
 * useAIAssistantChannel - Tests for Phoenix Channel integration hook
 *
 * Tests the hook that manages Phoenix Channel connection for AI Assistant,
 * including session creation, message sending, and real-time updates.
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { ReactNode } from 'react';

import { useAIAssistantChannel } from '../../../js/collaborative-editor/hooks/useAIAssistantChannel';
import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import { SocketContext } from '../../../js/react/contexts/SocketProvider';
import {
  createMockPhoenixSocket,
  createMockPhoenixChannel,
} from '../__helpers__/channelMocks';
import {
  createMockJobCodeContext,
  createMockWorkflowTemplateContext,
  createMockAIMessage,
} from '../__helpers__/aiAssistantHelpers';

describe('useAIAssistantChannel', () => {
  let mockStore: ReturnType<typeof createAIAssistantStore>;
  let mockSocket: ReturnType<typeof createMockPhoenixSocket>;
  let mockChannel: ReturnType<typeof createMockPhoenixChannel>;

  const wrapper = ({ children }: { children: ReactNode }) => (
    <SocketContext.Provider value={{ socket: mockSocket as any }}>
      {children}
    </SocketContext.Provider>
  );

  beforeEach(() => {
    mockStore = createAIAssistantStore();
    mockSocket = createMockPhoenixSocket();
    mockChannel = createMockPhoenixChannel('ai_assistant:test');

    // Mock socket.channel to return our mock channel
    mockSocket.channel = vi.fn(() => mockChannel as any);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Channel Connection', () => {
    it('should join channel when connection state is connecting', async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockSocket.channel).toHaveBeenCalledWith(
          expect.stringContaining('ai_assistant:job_code:'),
          expect.any(Object)
        );
      });

      expect(mockChannel.join).toHaveBeenCalled();
    });

    it('should not join channel when no socket', () => {
      const noSocketWrapper = ({ children }: { children: ReactNode }) => (
        <SocketContext.Provider value={{ socket: null }}>
          {children}
        </SocketContext.Provider>
      );

      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper: noSocketWrapper,
      });

      expect(mockSocket.channel).not.toHaveBeenCalled();
    });

    it('should set connection state to connected on successful join', async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockStore.getSnapshot().connectionState).toBe('connected');
      });
    });

    it('should set session data from join response', async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      // Override mock to return session data
      const sessionData = {
        session_id: 'session-123',
        session_type: 'job_code' as const,
        messages: [
          createMockAIMessage({ role: 'user', content: 'Previous message' }),
        ],
      };
      mockChannel.join = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'ok') callback(sessionData);
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        const state = mockStore.getSnapshot();
        expect(state.sessionId).toBe('session-123');
        expect(state.messages).toHaveLength(1);
      });
    });

    it('should handle join error with session not found', async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);
      mockStore._setSession({
        id: 'old-session',
        session_type: 'job_code',
        messages: [],
      });

      // Mock error response
      mockChannel.join = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'error') {
            callback({ reason: 'session not found' });
          }
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        const state = mockStore.getSnapshot();
        expect(state.connectionState).toBe('error');
        expect(state.sessionId).toBeNull(); // Session cleared
      });
    });

    it('should handle join timeout', async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      mockChannel.join = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'timeout') callback();
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        const state = mockStore.getSnapshot();
        expect(state.connectionState).toBe('error');
        expect(state.connectionError).toBe('Connection timeout');
      });
    });

    it('should leave channel when disconnecting', async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      const { unmount } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      await waitFor(() => {
        expect(mockChannel.join).toHaveBeenCalled();
      });

      // Disconnect
      mockStore.disconnect();

      await waitFor(() => {
        expect(mockChannel.leave).toHaveBeenCalled();
      });

      unmount();
    });
  });

  describe('Message Sending', () => {
    beforeEach(async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockStore.getSnapshot().connectionState).toBe('connected');
      });
    });

    it('should send message through channel', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      result.current.sendMessage('Hello AI', { attach_code: true });

      await waitFor(() => {
        expect(mockChannel.push).toHaveBeenCalledWith('new_message', {
          content: 'Hello AI',
          attach_code: true,
        });
      });
    });

    it('should add user message to store on successful send', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      const userMessage = createMockAIMessage({
        role: 'user',
        content: 'Test message',
      });

      // Mock successful response
      mockChannel.push = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'ok') callback({ message: userMessage });
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      result.current.sendMessage('Test message');

      await waitFor(() => {
        const state = mockStore.getSnapshot();
        expect(state.messages).toHaveLength(1);
        expect(state.messages[0].content).toBe('Test message');
      });
    });

    it('should handle message send error', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      mockChannel.push = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'error') {
            callback({ reason: 'Validation error', errors: {} });
          }
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      result.current.sendMessage('Test');

      // Should not crash, error is logged
      await waitFor(() => {
        expect(mockChannel.push).toHaveBeenCalled();
      });
    });

    it('should not send message when channel not connected', () => {
      const disconnectedStore = createAIAssistantStore();

      const { result } = renderHook(
        () => useAIAssistantChannel(disconnectedStore),
        { wrapper }
      );

      result.current.sendMessage('Test');

      expect(mockChannel.push).not.toHaveBeenCalled();
    });
  });

  describe('Message Retry', () => {
    beforeEach(async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockStore.getSnapshot().connectionState).toBe('connected');
      });
    });

    it('should retry failed message', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      result.current.retryMessage('msg-123');

      await waitFor(() => {
        expect(mockChannel.push).toHaveBeenCalledWith('retry_message', {
          message_id: 'msg-123',
        });
      });
    });

    it('should update message status on successful retry', async () => {
      mockStore._addMessage(
        createMockAIMessage({ id: 'msg-123', status: 'error' })
      );

      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      mockChannel.push = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'ok') {
            callback({
              message: { id: 'msg-123', status: 'processing' },
            });
          }
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      result.current.retryMessage('msg-123');

      await waitFor(() => {
        const message = mockStore
          .getSnapshot()
          .messages.find(m => m.id === 'msg-123');
        expect(message?.status).toBe('processing');
      });
    });
  });

  describe('Real-time Updates', () => {
    it('should handle new_message event', async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockChannel.on).toHaveBeenCalledWith(
          'new_message',
          expect.any(Function)
        );
      });

      // Simulate receiving a message
      const onCall = (mockChannel.on as any).mock.calls.find(
        (call: any) => call[0] === 'new_message'
      );
      const messageHandler = onCall[1];

      const newMessage = createMockAIMessage({
        role: 'assistant',
        content: 'AI response',
      });

      messageHandler({ message: newMessage });

      await waitFor(() => {
        const state = mockStore.getSnapshot();
        expect(state.messages).toContainEqual(
          expect.objectContaining({ content: 'AI response' })
        );
      });
    });

    it('should handle message_status_changed event', async () => {
      mockStore._addMessage(
        createMockAIMessage({ id: 'msg-123', status: 'pending' })
      );

      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockChannel.on).toHaveBeenCalledWith(
          'message_status_changed',
          expect.any(Function)
        );
      });

      // Simulate status change
      const onCall = (mockChannel.on as any).mock.calls.find(
        (call: any) => call[0] === 'message_status_changed'
      );
      const statusHandler = onCall[1];

      statusHandler({ message_id: 'msg-123', status: 'success' });

      await waitFor(() => {
        const message = mockStore
          .getSnapshot()
          .messages.find(m => m.id === 'msg-123');
        expect(message?.status).toBe('success');
      });
    });
  });

  describe('Session Loading', () => {
    beforeEach(async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockStore.getSnapshot().connectionState).toBe('connected');
      });
    });

    it('should load sessions via channel', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      const sessionsResponse = {
        sessions: [
          { id: 'session-1', title: 'Session 1' },
          { id: 'session-2', title: 'Session 2' },
        ],
        pagination: {
          total_count: 2,
          has_next_page: false,
          has_prev_page: false,
        },
      };

      mockChannel.push = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'ok') callback(sessionsResponse);
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      await result.current.loadSessions(0, 20);

      expect(mockChannel.push).toHaveBeenCalledWith('list_sessions', {
        offset: 0,
        limit: 20,
      });

      const state = mockStore.getSnapshot();
      expect(state.sessionList).toHaveLength(2);
    });

    it('should reject promise on session load error', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      mockChannel.push = vi.fn(() => ({
        receive: vi.fn((status, callback) => {
          if (status === 'error') callback({ reason: 'Load failed' });
          return { receive: vi.fn(() => ({ receive: vi.fn() })) };
        }),
      })) as any;

      await expect(result.current.loadSessions()).rejects.toThrow(
        'Load failed'
      );
    });
  });

  describe('Context Updates', () => {
    beforeEach(async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockStore.getSnapshot().connectionState).toBe('connected');
      });
    });

    it('should update context via channel', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      const updates = {
        job_body: 'updated code',
        job_adaptor: '@openfn/language-http@latest',
      };

      result.current.updateContext(updates);

      await waitFor(() => {
        expect(mockChannel.push).toHaveBeenCalledWith(
          'update_context',
          updates
        );
      });

      // Should also update store optimistically
      const state = mockStore.getSnapshot();
      expect(state.jobCodeContext?.job_body).toBe('updated code');
    });
  });

  describe('Disclaimer', () => {
    beforeEach(async () => {
      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockStore.getSnapshot().connectionState).toBe('connected');
      });
    });

    it('should mark disclaimer as read via channel', async () => {
      const { result } = renderHook(() => useAIAssistantChannel(mockStore), {
        wrapper,
      });

      result.current.markDisclaimerRead();

      await waitFor(() => {
        expect(mockChannel.push).toHaveBeenCalledWith(
          'mark_disclaimer_read',
          {}
        );
      });

      // Should update store after successful response
      await waitFor(() => {
        expect(mockStore.getSnapshot().hasReadDisclaimer).toBe(true);
      });
    });
  });

  describe('Join Parameters', () => {
    it('should include job_id for job_code sessions', async () => {
      const context = createMockJobCodeContext({ job_id: 'job-123' });
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockSocket.channel).toHaveBeenCalledWith(
          expect.any(String),
          expect.objectContaining({ job_id: 'job-123' })
        );
      });
    });

    it('should include project_id for workflow_template sessions', async () => {
      const context = createMockWorkflowTemplateContext({
        project_id: 'project-123',
      });
      mockStore.connect('workflow_template', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockSocket.channel).toHaveBeenCalledWith(
          expect.any(String),
          expect.objectContaining({ project_id: 'project-123' })
        );
      });
    });

    it('should include workflow_id when available', async () => {
      const context = createMockJobCodeContext({
        workflow_id: 'workflow-123',
      });
      mockStore.connect('job_code', context);

      renderHook(() => useAIAssistantChannel(mockStore), { wrapper });

      await waitFor(() => {
        expect(mockSocket.channel).toHaveBeenCalledWith(
          expect.any(String),
          expect.objectContaining({ workflow_id: 'workflow-123' })
        );
      });
    });
  });
});
