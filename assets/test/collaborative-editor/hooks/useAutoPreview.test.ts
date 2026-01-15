/**
 * useAutoPreview Tests
 *
 * Tests the auto-preview hook that shows diff when AI responds with code.
 * Only the message author should see auto-preview to prevent conflicts in
 * collaborative sessions.
 */

import { renderHook } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import { useAutoPreview } from '../../../js/collaborative-editor/hooks/useAutoPreview';
import type {
  Session,
  Message,
} from '../../../js/collaborative-editor/types/ai-assistant';

describe('useAutoPreview', () => {
  const mockOnPreview = vi.fn();
  const mockCurrentUserId = 'user-123';

  const createMockJobCodeMode = (): AIModeResult => ({
    mode: 'job_code',
    context: {
      job_id: 'job-1',
      job_body: '',
      job_adaptor: '@openfn/language-common',
      attach_code: false,
      attach_logs: false,
    },
    storageKey: 'ai-job-job-1',
  });

  const createMockMessage = (overrides: Partial<Message> = {}): Message => ({
    id: 'msg-1',
    role: 'assistant',
    content: 'Here is your code',
    code: 'fn(state => state);',
    status: 'success',
    inserted_at: new Date().toISOString(),
    user_id: mockCurrentUserId,
    ...overrides,
  });

  const createMockSession = (messages: Message[]): Session => ({
    id: 'session-1',
    session_type: 'job_code',
    messages,
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Mode filtering', () => {
    it('should not preview in workflow_template mode', () => {
      const workflowMode: AIModeResult = {
        mode: 'workflow_template',
        context: { project_id: 'proj-1', workflow_id: 'wf-1' },
        storageKey: 'ai-workflow-wf-1',
      };
      const session = createMockSession([createMockMessage()]);

      renderHook(() =>
        useAutoPreview({
          aiMode: workflowMode,
          session,
          currentUserId: mockCurrentUserId,
          onPreview: mockOnPreview,
        })
      );

      expect(mockOnPreview).not.toHaveBeenCalled();
    });

    it('should not preview when aiMode is null', () => {
      const session = createMockSession([createMockMessage()]);

      renderHook(() =>
        useAutoPreview({
          aiMode: null,
          session,
          currentUserId: mockCurrentUserId,
          onPreview: mockOnPreview,
        })
      );

      expect(mockOnPreview).not.toHaveBeenCalled();
    });

    it('should not preview when aiMode is job_code but session is workflow_template', () => {
      // This scenario happens when:
      // 1. User has a workflow_template session open with YAML code
      // 2. User clicks into a step (job) which changes aiMode to job_code
      // 3. The session is still workflow_template with YAML in message.code
      // We should NOT preview the YAML as if it were job JS code
      const userMessage: Message = {
        id: 'user-msg',
        role: 'user',
        content: 'Create a workflow',
        status: 'success',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const workflowYamlMessage = createMockMessage({
        id: 'yaml-msg',
        code: 'name: My Workflow\njobs:\n  job-1:\n    name: Step 1',
        inserted_at: new Date().toISOString(),
      });

      // Session type is workflow_template (contains YAML)
      const workflowSession: Session = {
        id: 'session-1',
        session_type: 'workflow_template',
        messages: [userMessage, workflowYamlMessage],
      };

      // But aiMode is job_code (user clicked into a job)
      const jobCodeMode = createMockJobCodeMode();

      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: jobCodeMode,
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: workflowSession } }
      );

      // Should NOT preview - session type doesn't match aiMode
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Even after rerender, should still not preview
      rerender({ session: workflowSession });
      expect(mockOnPreview).not.toHaveBeenCalled();
    });

    it('should preview when both aiMode and session are job_code', () => {
      // This is the happy path - aiMode and session type match
      const userMessage: Message = {
        id: 'user-msg',
        role: 'user',
        content: 'Help me write code',
        status: 'success',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const firstAssistant = createMockMessage({
        id: 'first-msg',
        code: 'fn(state => state);',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
      });

      // Both session type and aiMode are job_code
      const jobCodeSession: Session = {
        id: 'session-1',
        session_type: 'job_code',
        messages: [userMessage, firstAssistant],
      };

      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: jobCodeSession } }
      );

      // First render = session load, should not preview
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Add new message
      const userMessage2: Message = {
        id: 'user-msg-2',
        role: 'user',
        content: 'Another question',
        status: 'success',
        inserted_at: new Date(Date.now() - 500).toISOString(),
        user_id: mockCurrentUserId,
      };
      const newAssistant = createMockMessage({
        id: 'new-msg',
        code: 'fn(state => ({ ...state, result: true }));',
        inserted_at: new Date().toISOString(),
      });

      const updatedSession: Session = {
        id: 'session-1',
        session_type: 'job_code',
        messages: [userMessage, firstAssistant, userMessage2, newAssistant],
      };

      rerender({ session: updatedSession });

      // Should preview - both aiMode and session type are job_code
      expect(mockOnPreview).toHaveBeenCalledWith(
        'fn(state => ({ ...state, result: true }));',
        'new-msg'
      );
    });
  });

  describe('Session mount behavior', () => {
    it('should not auto-preview on initial session load', () => {
      const session = createMockSession([createMockMessage()]);

      renderHook(() =>
        useAutoPreview({
          aiMode: createMockJobCodeMode(),
          session,
          currentUserId: mockCurrentUserId,
          onPreview: mockOnPreview,
        })
      );

      // First render = session load, should not preview
      expect(mockOnPreview).not.toHaveBeenCalled();
    });

    it('should not auto-preview existing messages on subsequent renders', () => {
      // This tests a subtle bug: when loading a session with existing code messages,
      // re-renders should NOT trigger auto-preview of those old messages
      const userMessage: Message = {
        id: 'user-msg',
        role: 'user',
        content: 'Old question',
        status: 'success',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const existingCodeMessage = createMockMessage({
        id: 'existing-code',
        code: 'fn(state => state);',
        inserted_at: new Date().toISOString(),
      });
      const session = createMockSession([userMessage, existingCodeMessage]);

      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session } }
      );

      // First render - should not preview (initial load)
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Second render with same session (e.g., from unrelated state change)
      rerender({ session });
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Third render - still should not preview old message
      rerender({ session });
      expect(mockOnPreview).not.toHaveBeenCalled();
    });

    it('should not preview old messages when switching sessions', () => {
      // Session 1 with old messages
      const userMsg1: Message = {
        id: 'user-msg-1',
        role: 'user',
        content: 'Question in session 1',
        status: 'success',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const assistantMsg1 = createMockMessage({
        id: 'assistant-msg-1',
        code: 'session 1 code',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
      });
      const session1 = createMockSession([userMsg1, assistantMsg1]);

      // Session 2 with different old messages
      const userMsg2: Message = {
        id: 'user-msg-2',
        role: 'user',
        content: 'Question in session 2',
        status: 'success',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const assistantMsg2 = createMockMessage({
        id: 'assistant-msg-2',
        code: 'session 2 code',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
      });
      const session2 = {
        id: 'session-2',
        session_type: 'job_code' as const,
        messages: [userMsg2, assistantMsg2],
      };

      // Render with session 1
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: session1 } }
      );

      // First render, no preview (initial load)
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Switch to session 2 (simulating opening an old chat)
      rerender({ session: session2 });

      // Should NOT auto-preview session 2's old message
      // because state should reset when session changes
      expect(mockOnPreview).not.toHaveBeenCalled();
    });

    it('should auto-preview when new message arrives after session loaded', () => {
      // Need a user message and assistant message to establish session loaded state
      const userMessage1: Message = {
        id: 'user-msg-1',
        role: 'user',
        content: 'Help me write code',
        status: 'success',
        inserted_at: new Date(Date.now() - 3000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const firstAssistant = createMockMessage({
        id: 'first-msg',
        code: 'first code',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
      });
      const userMessage2: Message = {
        id: 'user-msg-2',
        role: 'user',
        content: 'Another question',
        status: 'success',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
        user_id: mockCurrentUserId,
      };

      const initialSession = createMockSession([userMessage1, firstAssistant]);
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      // Session loaded, first render complete (sets hasLoadedSessionRef = true)
      expect(mockOnPreview).not.toHaveBeenCalled();

      // New assistant message arrives
      const newAssistant = createMockMessage();
      const updatedSession = createMockSession([
        userMessage1,
        firstAssistant,
        userMessage2,
        newAssistant,
      ]);
      rerender({ session: updatedSession });

      // Should auto-preview new message
      expect(mockOnPreview).toHaveBeenCalledWith(
        'fn(state => state);',
        'msg-1'
      );
    });
  });

  describe('Author filtering', () => {
    it('should only preview if current user authored triggering message', () => {
      const userMessage1: Message = {
        id: 'user-msg-1',
        role: 'user',
        content: 'Help me write code',
        status: 'success',
        inserted_at: new Date(Date.now() - 3000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const firstAssistantMessage = createMockMessage({
        id: 'first-assistant',
        code: 'first code',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
      });
      const userMessage2: Message = {
        id: 'user-msg-2',
        role: 'user',
        content: 'Another question',
        status: 'success',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
        user_id: mockCurrentUserId, // Current user sent this
      };
      const secondAssistantMessage = createMockMessage({
        id: 'assistant-msg',
        inserted_at: new Date().toISOString(),
      });

      // Start with first user message and first assistant message (sets hasLoadedSessionRef = true)
      const initialSession = createMockSession([
        userMessage1,
        firstAssistantMessage,
      ]);
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      // First render sets hasLoadedSessionRef = true, no preview
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Add second user message and second assistant message (should preview now)
      const updatedSession = createMockSession([
        userMessage1,
        firstAssistantMessage,
        userMessage2,
        secondAssistantMessage,
      ]);
      rerender({ session: updatedSession });

      expect(mockOnPreview).toHaveBeenCalledWith(
        'fn(state => state);',
        'assistant-msg'
      );
    });

    it('should not preview if different user authored triggering message', () => {
      const otherUserId = 'user-999';
      const userMessage: Message = {
        id: 'user-msg',
        role: 'user',
        content: 'Help me write code',
        status: 'success',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
        user_id: otherUserId, // Different user
      };
      const assistantMessage = createMockMessage({
        id: 'assistant-msg',
        inserted_at: new Date().toISOString(),
      });

      const initialSession = createMockSession([userMessage]);
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      const updatedSession = createMockSession([userMessage, assistantMessage]);
      rerender({ session: updatedSession });

      // Should NOT preview - different user's message
      expect(mockOnPreview).not.toHaveBeenCalled();
    });
  });

  describe('Duplicate prevention', () => {
    it('should not preview the same message twice', () => {
      const userMessage: Message = {
        id: 'user-msg',
        role: 'user',
        content: 'Question',
        status: 'success',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const assistantMessage = createMockMessage({
        inserted_at: new Date(Date.now() - 1000).toISOString(),
      });

      // Start with messages to set hasLoadedSessionRef = true
      const initialSession = createMockSession([userMessage, assistantMessage]);

      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      // First render sets hasLoadedSessionRef = true, no preview
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Add a new assistant message
      const newAssistantMessage = createMockMessage({
        id: 'msg-2',
        inserted_at: new Date().toISOString(),
      });
      const sessionWithNewMessage = createMockSession([
        userMessage,
        assistantMessage,
        newAssistantMessage,
      ]);
      rerender({ session: sessionWithNewMessage });
      expect(mockOnPreview).toHaveBeenCalledTimes(1);

      // Re-render with same messages (e.g., store update)
      rerender({ session: sessionWithNewMessage });
      expect(mockOnPreview).toHaveBeenCalledTimes(1); // Still 1, not 2
    });

    it('should preview different messages separately', () => {
      const userMessage1: Message = {
        id: 'user-1',
        role: 'user',
        content: 'Question 1',
        status: 'success',
        inserted_at: new Date(Date.now() - 4000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const message1 = createMockMessage({
        id: 'msg-1',
        code: 'code1',
        inserted_at: new Date(Date.now() - 3000).toISOString(),
      });

      const userMessage2: Message = {
        id: 'user-2',
        role: 'user',
        content: 'Question 2',
        status: 'success',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const message2 = createMockMessage({
        id: 'msg-2',
        code: 'code2',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
      });

      const userMessage3: Message = {
        id: 'user-3',
        role: 'user',
        content: 'Question 3',
        status: 'success',
        inserted_at: new Date(Date.now() - 500).toISOString(),
        user_id: mockCurrentUserId,
      };
      const message3 = createMockMessage({
        id: 'msg-3',
        code: 'code3',
        inserted_at: new Date().toISOString(),
      });

      // Start with first conversation to set hasLoadedSessionRef = true
      const initialSession = createMockSession([userMessage1, message1]);
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      // First render sets hasLoadedSessionRef = true, no preview
      expect(mockOnPreview).not.toHaveBeenCalled();

      // Second assistant message arrives
      rerender({
        session: createMockSession([
          userMessage1,
          message1,
          userMessage2,
          message2,
        ]),
      });
      expect(mockOnPreview).toHaveBeenCalledWith('code2', 'msg-2');

      // Third assistant message arrives
      rerender({
        session: createMockSession([
          userMessage1,
          message1,
          userMessage2,
          message2,
          userMessage3,
          message3,
        ]),
      });
      expect(mockOnPreview).toHaveBeenCalledWith('code3', 'msg-3');
      expect(mockOnPreview).toHaveBeenCalledTimes(2);
    });
  });

  describe('Message selection', () => {
    it('should preview most recent message with code', () => {
      const userMessage1: Message = {
        id: 'user-msg-1',
        role: 'user',
        content: 'Question',
        status: 'success',
        inserted_at: new Date(Date.now() - 4000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const older = createMockMessage({
        id: 'old',
        code: 'old code',
        inserted_at: new Date(Date.now() - 3000).toISOString(),
      });
      const userMessage2: Message = {
        id: 'user-msg-2',
        role: 'user',
        content: 'Another question',
        status: 'success',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
        user_id: mockCurrentUserId,
      };
      const newer = createMockMessage({
        id: 'new',
        code: 'new code',
        inserted_at: new Date().toISOString(),
      });

      const initialSession = createMockSession([userMessage1, older]);
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      // First render sets hasLoadedSessionRef = true, no preview
      expect(mockOnPreview).not.toHaveBeenCalled();

      rerender({
        session: createMockSession([userMessage1, older, userMessage2, newer]),
      });

      // Should preview newer message
      expect(mockOnPreview).toHaveBeenCalledWith('new code', 'new');
    });

    it('should ignore messages without code', () => {
      const withoutCode: Message = {
        id: 'no-code',
        role: 'assistant',
        content: 'Just text, no code',
        status: 'success',
        inserted_at: new Date().toISOString(),
        user_id: mockCurrentUserId,
      };

      const initialSession = createMockSession([]);
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      rerender({ session: createMockSession([withoutCode]) });

      expect(mockOnPreview).not.toHaveBeenCalled();
    });

    it('should ignore user role messages', () => {
      const userMessage: Message = {
        id: 'user-1',
        role: 'user',
        content: 'My question',
        code: 'some code', // User messages shouldn't have code, but testing defensive code
        status: 'success',
        inserted_at: new Date().toISOString(),
        user_id: mockCurrentUserId,
      };

      const initialSession = createMockSession([]);
      const { rerender } = renderHook(
        ({ session }) =>
          useAutoPreview({
            aiMode: createMockJobCodeMode(),
            session,
            currentUserId: mockCurrentUserId,
            onPreview: mockOnPreview,
          }),
        { initialProps: { session: initialSession } }
      );

      rerender({ session: createMockSession([userMessage]) });

      expect(mockOnPreview).not.toHaveBeenCalled();
    });
  });
});
