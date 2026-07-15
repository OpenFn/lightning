/**
 * useAIWorkflowApplications - Streaming Apply Stale Record Tests
 *
 * Tests how a completed AI response supersedes a stale streaming
 * record whose YAML no longer matches the final message, including
 * the record seeded transiently while a session is still loading:
 * - Apply normally when the final YAML differs from the streamed record
 * - Clear a stale record seeded during session-load so later responses
 *   are not skipped
 */

import { renderHook, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import type { MonacoHandle } from '../../../js/collaborative-editor/components/CollaborativeMonaco';
import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import { useAIWorkflowApplications } from '../../../js/collaborative-editor/hooks/useAIWorkflowApplications';
import type { Job } from '../../../js/collaborative-editor/types';
import type { ConnectionState } from '../../../js/collaborative-editor/types/ai-assistant';

// Mock modules
vi.mock('../../../js/yaml/util', () => ({
  parseWorkflowYAML: vi.fn((yaml: string) => {
    if (yaml.includes('invalid')) {
      throw new Error('Invalid YAML syntax');
    }
    if (yaml.includes('object-id')) {
      return {
        jobs: {
          'job-1': {
            id: { invalid: 'object' }, // Object ID (invalid)
            name: 'Job 1',
          },
        },
      };
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

vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: vi.fn(),
    success: vi.fn(),
    dismiss: vi.fn(),
  },
}));

describe('useAIWorkflowApplications - streaming apply stale record', () => {
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

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('applies normally when the final message YAML differs from the streaming apply record', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };

    const userMessage = {
      id: 'user-msg-1',
      role: 'user' as const,
      content: 'Build me a workflow',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:00Z',
      user_id: 'user-123',
    };

    const assistantMessage = {
      id: 'msg-1',
      role: 'assistant' as const,
      content: 'Here is your workflow',
      code: 'name: Test',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:01Z',
    };

    type Props = {
      currentSession: { messages: (typeof userMessage)[] } | null;
      streamingApply: { yaml: string; saveFailed: boolean } | null;
    };

    const { rerender } = renderHook(
      ({ currentSession, streamingApply }: Props) =>
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
          appliedMessageIdsRef,
          streamingApply,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      {
        initialProps: {
          currentSession: { messages: [userMessage] },
          streamingApply: null,
        },
      }
    );

    // Stale record: streaming applied different YAML than the final message
    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      streamingApply: { yaml: 'name: Something else', saveFailed: false },
    });

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
    });
    // The non-streaming apply supersedes (and clears) the stale record
    expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
  });

  it('clears the streaming apply record during session-load seeding so later responses are not skipped', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };

    const userMessage1 = {
      id: 'user-msg-1',
      role: 'user' as const,
      content: 'Build me a workflow',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:00Z',
      user_id: 'user-123',
    };
    const assistantMessage1 = {
      id: 'msg-1',
      role: 'assistant' as const,
      content: 'Here is workflow 1',
      code: 'name: Test 1',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:01Z',
    };
    const userMessage2 = {
      id: 'user-msg-2',
      role: 'user' as const,
      content: 'Refine the workflow',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:02Z',
      user_id: 'user-123',
    };
    const assistantMessage2 = {
      id: 'msg-2',
      role: 'assistant' as const,
      content: 'Here is workflow 2',
      code: 'name: Test 2',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:03Z',
    };

    type Props = {
      currentSession: { messages: (typeof userMessage1)[] } | null;
      streamingApply: { yaml: string; saveFailed: boolean } | null;
    };

    const { rerender } = renderHook(
      ({ currentSession, streamingApply }: Props) =>
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
          isNewWorkflow: true,
          isSessionConnected: true,
          appliedMessageIdsRef,
          streamingApply,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      {
        initialProps: {
          currentSession: null,
          // Streaming fired before the session finished loading
          streamingApply: { yaml: 'name: Test 1', saveFailed: false },
        },
      }
    );

    // First new_message: session loading for the first time (hasLoadedSessionRef = false)
    rerender({
      currentSession: { messages: [userMessage1, assistantMessage1] },
      streamingApply: { yaml: 'name: Test 1', saveFailed: false },
    });

    await waitFor(() => {
      // Session-load path marks messages applied but does not re-import;
      // the streaming record is dropped, never consumed
      expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();

    // Second response arrives — record cleared, so auto-apply proceeds
    rerender({
      currentSession: {
        messages: [
          userMessage1,
          assistantMessage1,
          userMessage2,
          assistantMessage2,
        ],
      },
      streamingApply: null,
    });

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
    });
  });
});
