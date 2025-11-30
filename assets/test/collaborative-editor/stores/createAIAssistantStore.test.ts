/**
 * createAIAssistantStore - Tests for AI Assistant store
 *
 * Tests the AI Assistant Zustand store which manages:
 * - Connection state (connected, disconnected, connecting, error)
 * - Messages (user and assistant)
 * - Sessions (history)
 * - Context (job code or workflow template)
 * - Error handling
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import type { AIAssistantStore } from '../../../js/collaborative-editor/types/ai-assistant';
import {
  createMockAIMessage,
  createMockAISession,
  createMockJobCodeContext,
  createMockWorkflowTemplateContext,
} from '../__helpers__/aiAssistantHelpers';

describe('createAIAssistantStore', () => {
  let store: AIAssistantStore;

  beforeEach(() => {
    store = createAIAssistantStore();
  });

  afterEach(() => {
    store.disconnect();
    vi.clearAllMocks();
  });

  describe('Initial State', () => {
    it('should initialize with default state', () => {
      const state = store.getSnapshot();

      expect(state.connectionState).toBe('disconnected');
      expect(state.messages).toEqual([]);
      expect(state.sessionList).toEqual([]);
      expect(state.sessionId).toBeNull();
      expect(state.sessionType).toBeNull();
      expect(state.jobCodeContext).toBeNull();
      expect(state.workflowTemplateContext).toBeNull();
      expect(state.connectionError).toBeUndefined();
      expect(state.isLoading).toBe(false);
      expect(state.isSending).toBe(false);
    });
  });

  describe('Connection Management', () => {
    it('should connect with job_code session type', () => {
      const context = createMockJobCodeContext();

      store.connect('job_code', context);

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('connecting');
      expect(state.sessionType).toBe('job_code');
      expect(state.jobCodeContext).toEqual(context);
      expect(state.workflowTemplateContext).toBeNull();
    });

    it('should connect with workflow_template session type', () => {
      const context = createMockWorkflowTemplateContext();

      store.connect('workflow_template', context);

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('connecting');
      expect(state.sessionType).toBe('workflow_template');
      expect(state.workflowTemplateContext).toEqual(context);
      expect(state.jobCodeContext).toBeNull();
    });

    it('should transition to connected state', () => {
      const context = createMockJobCodeContext();
      store.connect('job_code', context);

      store._setConnectionState('connected');

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('connected');
    });

    it('should handle connection errors', () => {
      const context = createMockJobCodeContext();
      store.connect('job_code', context);

      const errorMessage = 'Connection failed';
      store._setConnectionState('error', errorMessage);

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('error');
      expect(state.connectionError).toBe(errorMessage);
    });

    it('should disconnect but preserve session data', () => {
      const context = createMockJobCodeContext();
      store.connect('job_code', context);
      store._addMessage(createMockAIMessage());

      store.disconnect();

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('disconnected');
      // Messages and context are preserved across disconnects
      expect(state.messages.length).toBeGreaterThan(0);
      expect(state.jobCodeContext).toEqual(context);
    });

    it('should allow reconnection with different session type', () => {
      const context1 = createMockJobCodeContext();
      const context2 = createMockWorkflowTemplateContext();

      store.connect('job_code', context1);
      store._setConnectionState('connected');
      store.disconnect();

      // Reconnect with different type
      store.connect('workflow_template', context2);

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('connecting');
      expect(state.sessionType).toBe('workflow_template');
      expect(state.workflowTemplateContext).toEqual(context2);
    });
  });

  describe('Message Management', () => {
    beforeEach(() => {
      const context = createMockJobCodeContext();
      store.connect('job_code', context);
      store._setConnectionState('connected');
    });

    it('should add a user message', () => {
      const message = createMockAIMessage({ role: 'user', content: 'Hello' });

      store._addMessage(message);

      const state = store.getSnapshot();
      expect(state.messages).toHaveLength(1);
      expect(state.messages[0]).toEqual(message);
    });

    it('should add an assistant message', () => {
      const message = createMockAIMessage({
        role: 'assistant',
        content: 'Hi there!',
      });

      store._addMessage(message);

      const state = store.getSnapshot();
      expect(state.messages).toHaveLength(1);
      expect(state.messages[0].role).toBe('assistant');
    });

    it('should add multiple messages in order', () => {
      const msg1 = createMockAIMessage({ role: 'user', content: 'First' });
      const msg2 = createMockAIMessage({
        role: 'assistant',
        content: 'Second',
      });
      const msg3 = createMockAIMessage({ role: 'user', content: 'Third' });

      store._addMessage(msg1);
      store._addMessage(msg2);
      store._addMessage(msg3);

      const state = store.getSnapshot();
      expect(state.messages).toHaveLength(3);
      expect(state.messages[0].content).toBe('First');
      expect(state.messages[1].content).toBe('Second');
      expect(state.messages[2].content).toBe('Third');
    });

    it('should update message status', () => {
      const message = createMockAIMessage({
        id: 'msg-1',
        role: 'assistant',
        status: 'pending',
      });

      store._addMessage(message);
      store._updateMessageStatus('msg-1', 'success');

      const state = store.getSnapshot();
      expect(state.messages[0].status).toBe('success');
      expect(state.isLoading).toBe(false);
    });

    it('should set loading state for processing messages', () => {
      const message = createMockAIMessage({
        id: 'msg-1',
        role: 'assistant',
        status: 'pending',
      });

      store._addMessage(message);
      store._updateMessageStatus('msg-1', 'processing');

      const state = store.getSnapshot();
      expect(state.messages[0].status).toBe('processing');
      expect(state.isLoading).toBe(true);
    });

    it('should clear session and messages', () => {
      store._addMessage(createMockAIMessage());
      store._addMessage(createMockAIMessage());

      store.clearSession();

      const state = store.getSnapshot();
      expect(state.messages).toEqual([]);
      expect(state.sessionId).toBeNull();
    });
  });

  describe('Session Management', () => {
    beforeEach(() => {
      const context = createMockJobCodeContext();
      store.connect('job_code', context);
      store._setConnectionState('connected');
    });

    it('should set session from backend', () => {
      const session = {
        id: 'session-123',
        session_type: 'job_code' as const,
        messages: [
          createMockAIMessage({ role: 'user' }),
          createMockAIMessage({ role: 'assistant' }),
        ],
      };

      store._setSession(session);

      const state = store.getSnapshot();
      expect(state.sessionId).toBe('session-123');
      expect(state.messages).toHaveLength(2);
    });

    it('should load existing session by ID', () => {
      const sessionId = 'session-123';

      store.loadSession(sessionId);

      const state = store.getSnapshot();
      expect(state.sessionId).toBe(sessionId);
      expect(state.connectionState).toBe('connecting');
      expect(state.messages).toEqual([]); // Cleared until session loads
    });

    it('should set session list', () => {
      const response = {
        sessions: [
          createMockAISession({ id: 'session-1' }),
          createMockAISession({ id: 'session-2' }),
        ],
        pagination: {
          total_count: 2,
          has_next_page: false,
          has_prev_page: false,
        },
      };

      store._setSessionList(response);

      const state = store.getSnapshot();
      expect(state.sessionList).toHaveLength(2);
      expect(state.sessionList[0].id).toBe('session-1');
      expect(state.sessionList[1].id).toBe('session-2');
      expect(state.sessionListPagination).toEqual(response.pagination);
    });
  });

  describe('Context Updates', () => {
    it('should update job code context fields', () => {
      const initialContext = createMockJobCodeContext({
        job_body: 'initial code',
        job_adaptor: '@openfn/language-common@latest',
      });
      store.connect('job_code', initialContext);

      store.updateContext({
        job_body: 'updated code',
        job_adaptor: '@openfn/language-http@latest',
      });

      const state = store.getSnapshot();
      expect(state.jobCodeContext?.job_body).toBe('updated code');
      expect(state.jobCodeContext?.job_adaptor).toBe(
        '@openfn/language-http@latest'
      );
    });

    it('should update only specified context fields', () => {
      const initialContext = createMockJobCodeContext({
        job_body: 'initial code',
        job_name: 'Initial Job',
      });
      store.connect('job_code', initialContext);

      // Only update job_body
      store.updateContext({
        job_body: 'updated code',
      });

      const state = store.getSnapshot();
      expect(state.jobCodeContext?.job_body).toBe('updated code');
      expect(state.jobCodeContext?.job_name).toBe('Initial Job'); // Unchanged
    });
  });

  describe('Error Handling', () => {
    it('should set connection error', () => {
      const errorMessage = 'Something went wrong';

      store._setConnectionState('error', errorMessage);

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('error');
      expect(state.connectionError).toBe(errorMessage);
    });

    it('should clear error on successful connection', () => {
      store._setConnectionState('error', 'Error message');
      store._setConnectionState('connected');

      const state = store.getSnapshot();
      expect(state.connectionState).toBe('connected');
      expect(state.connectionError).toBeUndefined();
    });
  });

  describe('State Subscriptions', () => {
    it('should notify subscribers on state changes', () => {
      const subscriber = vi.fn();

      store.subscribe(subscriber);
      store._setConnectionState('connected');

      expect(subscriber).toHaveBeenCalled();
    });

    it('should not notify unsubscribed listeners', () => {
      const subscriber = vi.fn();

      const unsubscribe = store.subscribe(subscriber);
      unsubscribe();

      store._setConnectionState('connected');

      expect(subscriber).not.toHaveBeenCalled();
    });
  });

  describe('getSnapshot', () => {
    it('should return current state snapshot', () => {
      const context = createMockJobCodeContext();
      store.connect('job_code', context);

      const snapshot1 = store.getSnapshot();
      store._addMessage(createMockAIMessage());
      const snapshot2 = store.getSnapshot();

      expect(snapshot1.messages).toHaveLength(0);
      expect(snapshot2.messages).toHaveLength(1);
    });
  });
});
