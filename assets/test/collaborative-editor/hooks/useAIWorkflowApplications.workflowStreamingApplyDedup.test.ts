/**
 * useAIWorkflowApplications - Streaming Apply Dedup Tests
 *
 * Tests how a completed AI response reconciles against a workflow
 * already applied during streaming, when the streamed YAML matches
 * the final message:
 * - Skip re-import when the final message matches the streaming record
 * - Retry an owed save (without re-importing) when the streamed apply
 *   had previously save-failed
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

describe('useAIWorkflowApplications - streaming apply dedup', () => {
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

  it('skips re-import when the final message matches the streaming apply record', async () => {
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
          isNewWorkflow: true,
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

    // Streaming already imported this exact YAML and saved successfully
    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      streamingApply: { yaml: 'name: Test', saveFailed: false },
    });

    await waitFor(() => {
      expect(appliedMessageIdsRef.current.has('msg-1')).toBe(true);
      expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(mockSaveWorkflow).not.toHaveBeenCalled();
  });

  it('retries the owed save without re-importing when the matching streaming apply is save-failed', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };
    const successfulSaveWorkflow = vi.fn(() => Promise.resolve(true));

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
          workflowActions: {
            ...mockWorkflowActions,
            saveWorkflow: successfulSaveWorkflow,
          },
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
          currentSession: { messages: [userMessage] },
          streamingApply: null,
        },
      }
    );

    // Streaming imported the YAML but its save failed — a save is still owed
    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      streamingApply: { yaml: 'name: Test', saveFailed: true },
    });

    await waitFor(() => {
      expect(successfulSaveWorkflow).toHaveBeenCalledWith({
        notify: 'error-only',
      });
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    // Successful retry clears the owed-save flag
    expect(mockStreamingApplyActions.setSaveFailed).toHaveBeenCalledWith(false);
  });
});
