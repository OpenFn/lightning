/**
 * useAIAssistant - Tests for AI Assistant hooks
 *
 * Tests the React hooks that provide access to AI Assistant store state.
 * These hooks follow the same pattern as useWorkflow, useUI, etc.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { ReactNode } from 'react';

import {
  useAIStore,
  useAICommands,
  useAIConnectionState,
  useAIConnectionError,
  useAISessionId,
  useAISessionType,
  useAIMessages,
  useAIIsLoading,
  useAIIsSending,
  useAIHasReadDisclaimer,
  useAIJobCodeContext,
  useAIWorkflowTemplateContext,
} from '../../../js/collaborative-editor/hooks/useAIAssistant';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import {
  createMockAIMessage,
  createMockJobCodeContext,
  createMockWorkflowTemplateContext,
} from '../__helpers__/aiAssistantHelpers';

describe('useAIAssistant Hooks', () => {
  let mockStore: ReturnType<typeof createAIAssistantStore>;
  let wrapper: ({ children }: { children: ReactNode }) => JSX.Element;

  beforeEach(() => {
    // Create fresh store for each test to avoid state pollution
    mockStore = createAIAssistantStore();

    // Wrapper component that provides store context
    wrapper = ({ children }: { children: ReactNode }) => (
      <StoreContext.Provider
        value={
          {
            aiAssistantStore: mockStore,
          } as any
        }
      >
        {children}
      </StoreContext.Provider>
    );
  });

  describe('useAIStore', () => {
    it('should return the AI Assistant store', () => {
      const { result } = renderHook(() => useAIStore(), { wrapper });

      expect(result.current).toBe(mockStore);
    });

    it('should throw error when used outside StoreProvider', () => {
      // Spy on console.error to suppress React error boundary output
      const consoleErrorSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      expect(() => {
        renderHook(() => useAIStore());
      }).toThrow('useAIStore must be used within a StoreProvider');

      consoleErrorSpy.mockRestore();
    });
  });

  describe('useAICommands', () => {
    it('should return all command functions', () => {
      const { result } = renderHook(() => useAICommands(), { wrapper });

      expect(result.current).toHaveProperty('connect');
      expect(result.current).toHaveProperty('disconnect');
      expect(result.current).toHaveProperty('setMessageSending');
      expect(result.current).toHaveProperty('retryMessage');
      expect(result.current).toHaveProperty('markDisclaimerRead');
      expect(result.current).toHaveProperty('clearSession');

      expect(typeof result.current.connect).toBe('function');
      expect(typeof result.current.disconnect).toBe('function');
      expect(typeof result.current.setMessageSending).toBe('function');
      expect(typeof result.current.retryMessage).toBe('function');
      expect(typeof result.current.markDisclaimerRead).toBe('function');
      expect(typeof result.current.clearSession).toBe('function');
    });

    it('should allow calling connect command', () => {
      const { result } = renderHook(() => useAICommands(), { wrapper });
      const context = createMockJobCodeContext();

      result.current.connect('job_code', context);

      const state = mockStore.getSnapshot();
      expect(state.connectionState).toBe('connecting');
      expect(state.sessionType).toBe('job_code');
    });

    it('should allow calling disconnect command', () => {
      const { result } = renderHook(() => useAICommands(), { wrapper });
      const context = createMockJobCodeContext();

      mockStore.connect('job_code', context);
      mockStore._setConnectionState('connected');

      result.current.disconnect();

      const state = mockStore.getSnapshot();
      expect(state.connectionState).toBe('disconnected');
    });

    it('should allow calling clearSession command', () => {
      const { result } = renderHook(() => useAICommands(), { wrapper });

      mockStore._addMessage(createMockAIMessage());
      expect(mockStore.getSnapshot().messages.length).toBeGreaterThan(0);

      result.current.clearSession();

      const state = mockStore.getSnapshot();
      expect(state.messages).toEqual([]);
      expect(state.sessionId).toBeNull();
    });

    it('should allow calling markDisclaimerRead command', () => {
      const { result } = renderHook(() => useAICommands(), { wrapper });

      expect(mockStore.getSnapshot().hasReadDisclaimer).toBe(false);

      result.current.markDisclaimerRead();

      expect(mockStore.getSnapshot().hasReadDisclaimer).toBe(true);
    });
  });

  describe('useAIConnectionState', () => {
    it('should return initial connection state', () => {
      const { result } = renderHook(() => useAIConnectionState(), { wrapper });

      expect(result.current).toBe('disconnected');
    });

    it('should update when connection state changes', async () => {
      const { result } = renderHook(() => useAIConnectionState(), { wrapper });

      expect(result.current).toBe('disconnected');

      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      await waitFor(() => {
        expect(result.current).toBe('connecting');
      });

      mockStore._setConnectionState('connected');

      await waitFor(() => {
        expect(result.current).toBe('connected');
      });
    });

    it('should update to error state', async () => {
      const { result } = renderHook(() => useAIConnectionState(), { wrapper });

      mockStore._setConnectionState('error', 'Connection failed');

      await waitFor(() => {
        expect(result.current).toBe('error');
      });
    });
  });

  describe('useAIConnectionError', () => {
    it('should return undefined when no error', () => {
      const { result } = renderHook(() => useAIConnectionError(), { wrapper });

      expect(result.current).toBeUndefined();
    });

    it('should return error message when in error state', async () => {
      const { result } = renderHook(() => useAIConnectionError(), { wrapper });

      const errorMessage = 'Connection failed';
      mockStore._setConnectionState('error', errorMessage);

      await waitFor(() => {
        expect(result.current).toBe(errorMessage);
      });
    });

    it('should clear error when connection succeeds', async () => {
      const { result } = renderHook(() => useAIConnectionError(), { wrapper });

      mockStore._setConnectionState('error', 'Error message');

      await waitFor(() => {
        expect(result.current).toBe('Error message');
      });

      mockStore._setConnectionState('connected');

      await waitFor(() => {
        expect(result.current).toBeUndefined();
      });
    });
  });

  describe('useAISessionId', () => {
    it('should return null when no session', () => {
      const { result } = renderHook(() => useAISessionId(), { wrapper });

      expect(result.current).toBeNull();
    });

    it('should return session ID when session is set', async () => {
      const { result } = renderHook(() => useAISessionId(), { wrapper });

      const session = {
        id: 'session-123',
        session_type: 'job_code' as const,
        messages: [],
      };

      mockStore._setSession(session);

      await waitFor(() => {
        expect(result.current).toBe('session-123');
      });
    });
  });

  describe('useAISessionType', () => {
    it('should return null when no session type set', () => {
      const { result } = renderHook(() => useAISessionType(), { wrapper });

      expect(result.current).toBeNull();
    });

    it('should return job_code session type', async () => {
      const { result } = renderHook(() => useAISessionType(), { wrapper });
      const context = createMockJobCodeContext();

      mockStore.connect('job_code', context);

      await waitFor(() => {
        expect(result.current).toBe('job_code');
      });
    });

    it('should return workflow_template session type', async () => {
      const { result } = renderHook(() => useAISessionType(), { wrapper });
      const context = createMockWorkflowTemplateContext();

      mockStore.connect('workflow_template', context);

      await waitFor(() => {
        expect(result.current).toBe('workflow_template');
      });
    });
  });

  describe('useAIMessages', () => {
    it('should return empty array initially', () => {
      const { result } = renderHook(() => useAIMessages(), { wrapper });

      expect(result.current).toEqual([]);
    });

    it('should return messages when added', async () => {
      const { result } = renderHook(() => useAIMessages(), { wrapper });

      const message1 = createMockAIMessage({ role: 'user', content: 'Hello' });
      const message2 = createMockAIMessage({
        role: 'assistant',
        content: 'Hi there!',
      });

      mockStore._addMessage(message1);

      await waitFor(() => {
        expect(result.current.length).toBe(1);
        expect(result.current[0].content).toBe('Hello');
      });

      mockStore._addMessage(message2);

      await waitFor(() => {
        expect(result.current.length).toBe(2);
        expect(result.current[1].content).toBe('Hi there!');
      });
    });

    it('should clear messages when session is cleared', async () => {
      const { result } = renderHook(() => useAIMessages(), { wrapper });

      mockStore._addMessage(createMockAIMessage());
      mockStore._addMessage(createMockAIMessage());

      await waitFor(() => {
        expect(result.current.length).toBe(2);
      });

      mockStore.clearSession();

      await waitFor(() => {
        expect(result.current).toEqual([]);
      });
    });
  });

  describe('useAIIsLoading', () => {
    it('should return false initially', () => {
      const { result } = renderHook(() => useAIIsLoading(), { wrapper });

      expect(result.current).toBe(false);
    });

    it('should return true when AI is processing', async () => {
      const { result } = renderHook(() => useAIIsLoading(), { wrapper });

      const message = createMockAIMessage({
        id: 'msg-1',
        role: 'assistant',
        status: 'pending',
      });

      mockStore._addMessage(message);
      mockStore._updateMessageStatus('msg-1', 'processing');

      await waitFor(() => {
        expect(result.current).toBe(true);
      });
    });

    it('should return false when message completes', async () => {
      const { result } = renderHook(() => useAIIsLoading(), { wrapper });

      const message = createMockAIMessage({
        id: 'msg-1',
        role: 'assistant',
        status: 'processing',
      });

      mockStore._addMessage(message);

      await waitFor(() => {
        expect(result.current).toBe(true);
      });

      mockStore._updateMessageStatus('msg-1', 'success');

      await waitFor(() => {
        expect(result.current).toBe(false);
      });
    });
  });

  describe('useAIIsSending', () => {
    it('should return false initially', () => {
      const { result } = renderHook(() => useAIIsSending(), { wrapper });

      expect(result.current).toBe(false);
    });

    it('should return false after message is added', async () => {
      const { result } = renderHook(() => useAIIsSending(), { wrapper });

      expect(result.current).toBe(false);

      // Adding a message sets isSending to false
      mockStore._addMessage(createMockAIMessage({ role: 'user' }));

      await waitFor(() => {
        expect(result.current).toBe(false);
      });
    });
  });

  describe('useAIHasReadDisclaimer', () => {
    it('should return false initially', () => {
      const { result } = renderHook(() => useAIHasReadDisclaimer(), {
        wrapper,
      });

      expect(result.current).toBe(false);
    });

    it('should return true after marking as read', async () => {
      const { result } = renderHook(() => useAIHasReadDisclaimer(), {
        wrapper,
      });

      mockStore.markDisclaimerRead();

      await waitFor(() => {
        expect(result.current).toBe(true);
      });
    });
  });

  describe('useAIJobCodeContext', () => {
    it('should return null when no job code context', () => {
      const { result } = renderHook(() => useAIJobCodeContext(), { wrapper });

      expect(result.current).toBeNull();
    });

    it('should return job code context when set', async () => {
      const { result } = renderHook(() => useAIJobCodeContext(), { wrapper });
      const context = createMockJobCodeContext();

      mockStore.connect('job_code', context);

      await waitFor(() => {
        expect(result.current).toEqual(context);
      });
    });

    it('should be null when in workflow_template mode', async () => {
      const { result } = renderHook(() => useAIJobCodeContext(), { wrapper });
      const context = createMockWorkflowTemplateContext();

      mockStore.connect('workflow_template', context);

      await waitFor(() => {
        expect(result.current).toBeNull();
      });
    });
  });

  describe('useAIWorkflowTemplateContext', () => {
    it('should return null when no workflow template context', () => {
      const { result } = renderHook(() => useAIWorkflowTemplateContext(), {
        wrapper,
      });

      expect(result.current).toBeNull();
    });

    it('should return workflow template context when set', async () => {
      const { result } = renderHook(() => useAIWorkflowTemplateContext(), {
        wrapper,
      });
      const context = createMockWorkflowTemplateContext();

      mockStore.connect('workflow_template', context);

      await waitFor(() => {
        expect(result.current).toEqual(context);
      });
    });

    it('should be null when in job_code mode', async () => {
      const { result } = renderHook(() => useAIWorkflowTemplateContext(), {
        wrapper,
      });
      const context = createMockJobCodeContext();

      mockStore.connect('job_code', context);

      await waitFor(() => {
        expect(result.current).toBeNull();
      });
    });
  });

  describe('Hook Integration', () => {
    it('should allow using multiple hooks together', async () => {
      const { result: connectionResult } = renderHook(
        () => useAIConnectionState(),
        { wrapper }
      );
      const { result: messagesResult } = renderHook(() => useAIMessages(), {
        wrapper,
      });
      const { result: sessionTypeResult } = renderHook(
        () => useAISessionType(),
        { wrapper }
      );

      const context = createMockJobCodeContext();
      mockStore.connect('job_code', context);

      await waitFor(() => {
        expect(connectionResult.current).toBe('connecting');
        expect(sessionTypeResult.current).toBe('job_code');
      });

      mockStore._setConnectionState('connected');
      mockStore._addMessage(createMockAIMessage({ role: 'user' }));

      await waitFor(() => {
        expect(connectionResult.current).toBe('connected');
        expect(messagesResult.current.length).toBe(1);
      });
    });
  });
});
