/**
 * useAIWorkflowApplications - Auto-Application Tests
 *
 * Tests the automatic workflow application behavior:
 * - Auto-apply new workflow YAML from AI responses
 * - Session load guard (don't re-apply existing messages)
 * - Author detection (only auto-apply for message author)
 * - Connection state checking
 */

import { act, renderHook, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import type { MonacoHandle } from '../../../js/collaborative-editor/components/CollaborativeMonaco';
import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import { useAIWorkflowApplications } from '../../../js/collaborative-editor/hooks/useAIWorkflowApplications';
import type { Job } from '../../../js/collaborative-editor/types';
import type {
  Message,
  Session,
  ConnectionState,
} from '../../../js/collaborative-editor/types/ai-assistant';

// Mock modules
vi.mock('../../../js/yaml/util', () => ({
  parseWorkflowYAML: vi.fn((yaml: string) => {
    if (yaml.includes('invalid')) {
      throw new Error('Invalid YAML syntax');
    }
    return {
      name: 'Test Workflow',
      jobs: {
        'job-1': { id: 'job-1', name: 'Job 1', body: 'console.log("test");' },
      },
      triggers: {},
      edges: [],
    };
  }),
  convertWorkflowSpecToState: vi.fn(
    (spec: {
      name: string;
      jobs: Record<string, unknown>;
      triggers?: Record<string, unknown>;
      edges?: unknown[];
    }) => ({
      name: spec.name,
      jobs: spec.jobs,
      triggers: spec.triggers || {},
      edges: spec.edges || [],
    })
  ),
  applyJobCredsToWorkflowState: vi.fn((state: unknown, _creds: unknown) => ({
    ...(state as Record<string, unknown>),
    _credentialsApplied: true,
  })),
  extractJobCredentials: vi.fn((jobs: Job[]) =>
    jobs.reduce(
      (acc: Record<string, string>, job: Job & { credential?: string }) => {
        if (job.credential) {
          acc[job.id] = job.credential;
        }
        return acc;
      },
      {} as Record<string, string>
    )
  ),
}));

describe('useAIWorkflowApplications - auto-application', () => {
  // Mock functions
  const mockImportWorkflow = vi.fn(() => Promise.resolve());
  const mockStartApplyingWorkflow = vi.fn(() => Promise.resolve(true));
  const mockDoneApplyingWorkflow = vi.fn(() => Promise.resolve());
  const mockStartApplyingJobCode = vi.fn(() => Promise.resolve(true));
  const mockDoneApplyingJobCode = vi.fn(() => Promise.resolve());
  const mockUpdateJob = vi.fn();
  const mockSetPreviewingMessageId = vi.fn();
  const mockSetApplyingMessageId = vi.fn();
  const mockClearDiff = vi.fn();
  const mockShowDiff = vi.fn();

  const mockSaveWorkflow = vi.fn(() => Promise.resolve());

  const mockStreamingApplyActions = {
    set: vi.fn(),
    setSaveFailed: vi.fn(),
    clear: vi.fn(),
  };

  const mockWorkflowActions = {
    importWorkflow: mockImportWorkflow,
    startApplyingWorkflow: mockStartApplyingWorkflow,
    doneApplyingWorkflow: mockDoneApplyingWorkflow,
    startApplyingJobCode: mockStartApplyingJobCode,
    doneApplyingJobCode: mockDoneApplyingJobCode,
    updateJob: mockUpdateJob,
    saveWorkflow: mockSaveWorkflow,
  };

  const createMockMonacoRef = () => ({
    current: {
      clearDiff: mockClearDiff,
      showDiff: mockShowDiff,
    } as MonacoHandle,
  });

  const createMockAIMode = (
    mode: 'workflow_template' | 'job_code',
    context: Record<string, unknown> = {}
  ): AIModeResult => ({
    mode: 'workflow_template',
    page: mode,
    context,
    storageKey: `ai-${mode}`,
  });

  const createMockMessage = (overrides: Partial<Message> = {}): Message => ({
    id: 'msg-1',
    role: 'assistant',
    content: 'Here is your code',
    code: 'console.log("new code");',
    status: 'success',
    inserted_at: new Date().toISOString(),
    user_id: 'user-123',
    ...overrides,
  });

  const createMockSession = (
    messages: Message[],
    sessionType: 'workflow_template' | 'job_code' = 'job_code'
  ): Session => ({
    id: 'session-1',
    session_type: sessionType,
    messages,
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });
  describe('auto-application effect', () => {
    it('automatically applies new workflow YAML from AI', async () => {
      const userMessage = createMockMessage({
        id: 'user-msg',
        role: 'user',
        content: 'Create a workflow',
        user_id: 'user-123',
        inserted_at: new Date(Date.now() - 2000).toISOString(),
      });

      const assistantMessage = createMockMessage({
        id: 'assistant-msg',
        role: 'assistant',
        code: 'name: Auto Apply Workflow',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
      });

      const session = createMockSession(
        [userMessage, assistantMessage],
        'workflow_template'
      );

      const appliedMessageIdsRef = { current: new Set<string>() };

      const { rerender } = renderHook(
        ({ currentSession }) =>
          useAIWorkflowApplications({
            sessionId: 'session-1',
            page: 'workflow_template',
            currentSession,
            currentUserId: 'user-123',
            aiMode: createMockAIMode('workflow_template'),
            workflowActions: mockWorkflowActions,
            monacoRef: createMockMonacoRef(),
            jobs: [],
            canApplyChanges: true,
            connectionState: 'connected' as ConnectionState,
            setPreviewingMessageId: mockSetPreviewingMessageId,
            previewingMessageId: null,
            setApplyingMessageId: mockSetApplyingMessageId,
            isNewWorkflow: false,
            isSessionConnected: true,
            isSessionConnecting: false,
            appliedMessageIdsRef,
            streamingApply: null,
            streamingApplyActions: mockStreamingApplyActions,
          }),
        { initialProps: { currentSession: null } }
      );

      // First render - loads session
      rerender({ currentSession: session });

      // Should mark messages as applied on initial load
      await waitFor(() => {
        expect(appliedMessageIdsRef.current.has('assistant-msg')).toBe(true);
        expect(mockImportWorkflow).not.toHaveBeenCalled();
      });

      // Add new message
      const newAssistantMessage = createMockMessage({
        id: 'new-assistant-msg',
        role: 'assistant',
        code: 'name: New Workflow',
        inserted_at: new Date().toISOString(),
      });

      const updatedSession = createMockSession(
        [userMessage, assistantMessage, newAssistantMessage],
        'workflow_template'
      );

      rerender({ currentSession: updatedSession });

      // Should auto-apply new message
      await waitFor(() => {
        expect(mockImportWorkflow).toHaveBeenCalled();
        expect(appliedMessageIdsRef.current.has('new-assistant-msg')).toBe(
          true
        );
      });
    });

    it('does not auto-apply on session mount', async () => {
      const userMessage = createMockMessage({
        id: 'user-msg',
        role: 'user',
        user_id: 'user-123',
      });

      const assistantMessage = createMockMessage({
        id: 'assistant-msg',
        code: 'name: Existing Workflow',
      });

      const session = createMockSession(
        [userMessage, assistantMessage],
        'workflow_template'
      );

      const appliedMessageIdsRef = { current: new Set<string>() };

      renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'workflow_template',
          currentSession: session,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('workflow_template'),
          workflowActions: mockWorkflowActions,
          monacoRef: createMockMonacoRef(),
          jobs: [],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: null,
          setApplyingMessageId: mockSetApplyingMessageId,
          isNewWorkflow: false,
          isSessionConnected: true,
          isSessionConnecting: false,
          appliedMessageIdsRef,
          streamingApply: null,
          streamingApplyActions: mockStreamingApplyActions,
        })
      );

      // On mount the effect marks existing messages as already-applied
      // (so they're never re-imported) without importing them.
      await waitFor(() => {
        expect(appliedMessageIdsRef.current.has('assistant-msg')).toBe(true);
      });
      expect(mockImportWorkflow).not.toHaveBeenCalled();
    });

    it('only auto-applies for message author', async () => {
      const userMessage = createMockMessage({
        id: 'user-msg',
        role: 'user',
        user_id: 'other-user-456', // Different user
        inserted_at: new Date(Date.now() - 2000).toISOString(),
      });

      const assistantMessage = createMockMessage({
        id: 'assistant-msg',
        code: 'name: Workflow',
        inserted_at: new Date(Date.now() - 1000).toISOString(),
      });

      const session = createMockSession(
        [userMessage, assistantMessage],
        'workflow_template'
      );

      const appliedMessageIdsRef = { current: new Set<string>() };

      const { rerender } = renderHook(
        ({ currentSession }) =>
          useAIWorkflowApplications({
            sessionId: 'session-1',
            page: 'workflow_template',
            currentSession,
            currentUserId: 'user-123', // Current user is different
            aiMode: createMockAIMode('workflow_template'),
            workflowActions: mockWorkflowActions,
            monacoRef: createMockMonacoRef(),
            jobs: [],
            canApplyChanges: true,
            connectionState: 'connected' as ConnectionState,
            setPreviewingMessageId: mockSetPreviewingMessageId,
            previewingMessageId: null,
            setApplyingMessageId: mockSetApplyingMessageId,
            isNewWorkflow: false,
            isSessionConnected: true,
            isSessionConnecting: false,
            appliedMessageIdsRef,
            streamingApply: null,
            streamingApplyActions: mockStreamingApplyActions,
          }),
        { initialProps: { currentSession: null } }
      );

      rerender({ currentSession: session });

      // Should mark as applied but NOT import (different user)
      await waitFor(() => {
        expect(appliedMessageIdsRef.current.has('assistant-msg')).toBe(true);
      });
      expect(mockImportWorkflow).not.toHaveBeenCalled();
    });

    it('does not auto-apply when readonly', async () => {
      const userMessage = createMockMessage({
        id: 'user-msg',
        role: 'user',
        user_id: 'user-123',
      });
      const assistantMessage = createMockMessage({
        id: 'assistant-msg',
        code: 'name: Workflow',
      });

      // The assistant message has to ARRIVE, not just be present at mount:
      // the first render with any session consumes the session-load guard,
      // which marks existing messages as applied without importing them. A
      // test that mounts with both messages therefore never reaches the
      // readonly check and would pass whatever canApplyChanges said.
      const { rerender } = renderHook(
        ({ currentSession }: { currentSession: Session }) =>
          useAIWorkflowApplications({
            sessionId: 'session-1',
            page: 'workflow_template',
            currentSession,
            currentUserId: 'user-123',
            aiMode: createMockAIMode('workflow_template'),
            workflowActions: mockWorkflowActions,
            monacoRef: createMockMonacoRef(),
            jobs: [],
            canApplyChanges: false, // Readonly
            connectionState: 'connected' as ConnectionState,
            setPreviewingMessageId: mockSetPreviewingMessageId,
            previewingMessageId: null,
            setApplyingMessageId: mockSetApplyingMessageId,
            isNewWorkflow: false,
            isSessionConnected: true,
            isSessionConnecting: false,
            appliedMessageIdsRef: { current: new Set() },
            streamingApply: null,
            streamingApplyActions: mockStreamingApplyActions,
          }),
        {
          initialProps: {
            currentSession: createMockSession(
              [userMessage],
              'workflow_template'
            ),
          },
        }
      );

      rerender({
        currentSession: createMockSession(
          [userMessage, assistantMessage],
          'workflow_template'
        ),
      });

      // Flush pending effects before asserting. waitFor is no use for a
      // negative assertion - it resolves on the first synchronous pass, so it
      // would report success before the auto-apply effect had a chance to run.
      await act(async () => {});

      expect(mockImportWorkflow).not.toHaveBeenCalled();
    });

    it('does not auto-apply when connection is not established', async () => {
      const userMessage = createMockMessage({
        id: 'user-msg',
        role: 'user',
        user_id: 'user-123',
      });
      const assistantMessage = createMockMessage({
        id: 'assistant-msg',
        code: 'name: Workflow',
      });

      // As above: the assistant message has to arrive after mount so that
      // auto-apply is genuinely reachable and the connection guard is what
      // stops it.
      const { rerender } = renderHook(
        ({ currentSession }: { currentSession: Session }) =>
          useAIWorkflowApplications({
            sessionId: 'session-1',
            page: 'workflow_template',
            currentSession,
            currentUserId: 'user-123',
            aiMode: createMockAIMode('workflow_template'),
            workflowActions: mockWorkflowActions,
            monacoRef: createMockMonacoRef(),
            jobs: [],
            canApplyChanges: true,
            connectionState: 'connecting' as ConnectionState, // Not connected
            setPreviewingMessageId: mockSetPreviewingMessageId,
            previewingMessageId: null,
            setApplyingMessageId: mockSetApplyingMessageId,
            isNewWorkflow: false,
            isSessionConnected: true,
            isSessionConnecting: false,
            appliedMessageIdsRef: { current: new Set() },
            streamingApply: null,
            streamingApplyActions: mockStreamingApplyActions,
          }),
        {
          initialProps: {
            currentSession: createMockSession(
              [userMessage],
              'workflow_template'
            ),
          },
        }
      );

      rerender({
        currentSession: createMockSession(
          [userMessage, assistantMessage],
          'workflow_template'
        ),
      });

      // See above: flush effects rather than waitFor for a negative assertion.
      await act(async () => {});

      expect(mockImportWorkflow).not.toHaveBeenCalled();
    });

    it('only applies latest message with code', async () => {
      const appliedMessageIdsRef = { current: new Set<string>() };

      const messages = [
        createMockMessage({
          id: 'user-1',
          role: 'user',
          user_id: 'user-123',
          inserted_at: new Date(Date.now() - 4000).toISOString(),
        }),
        createMockMessage({
          id: 'assistant-1',
          code: 'name: Old Workflow',
          inserted_at: new Date(Date.now() - 3000).toISOString(),
        }),
        createMockMessage({
          id: 'user-2',
          role: 'user',
          user_id: 'user-123',
          inserted_at: new Date(Date.now() - 2000).toISOString(),
        }),
        createMockMessage({
          id: 'assistant-2',
          code: 'name: Latest Workflow',
          inserted_at: new Date(Date.now() - 1000).toISOString(),
        }),
      ];

      const session = createMockSession(messages, 'workflow_template');

      const { rerender } = renderHook(
        ({ currentSession }) =>
          useAIWorkflowApplications({
            sessionId: 'session-1',
            page: 'workflow_template',
            currentSession,
            currentUserId: 'user-123',
            aiMode: createMockAIMode('workflow_template'),
            workflowActions: mockWorkflowActions,
            monacoRef: createMockMonacoRef(),
            jobs: [],
            canApplyChanges: true,
            connectionState: 'connected' as ConnectionState,
            setPreviewingMessageId: mockSetPreviewingMessageId,
            previewingMessageId: null,
            setApplyingMessageId: mockSetApplyingMessageId,
            isNewWorkflow: false,
            isSessionConnected: true,
            isSessionConnecting: false,
            appliedMessageIdsRef,
            streamingApply: null,
            streamingApplyActions: mockStreamingApplyActions,
          }),
        { initialProps: { currentSession: null } }
      );

      rerender({ currentSession: session });

      // Should mark both as applied on initial load
      await waitFor(() => {
        expect(appliedMessageIdsRef.current.has('assistant-1')).toBe(true);
        expect(appliedMessageIdsRef.current.has('assistant-2')).toBe(true);
        expect(mockImportWorkflow).not.toHaveBeenCalled();
      });
    });
  });
});
