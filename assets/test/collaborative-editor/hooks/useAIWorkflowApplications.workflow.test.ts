/**
 * useAIWorkflowApplications - Workflow Application Tests
 *
 * Tests the workflow YAML application functionality:
 * - Parsing and applying workflow YAML
 * - ID validation
 * - Error handling
 * - Credential preservation
 * - Collaborative coordination
 */

import { renderHook, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import type { MonacoHandle } from '../../../js/collaborative-editor/components/CollaborativeMonaco';
import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import { useAIWorkflowApplications } from '../../../js/collaborative-editor/hooks/useAIWorkflowApplications';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';
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

describe('useAIWorkflowApplications - handleApplyWorkflow', () => {
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
  const mockOnValidationError = vi.fn();

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

  const createMockJob = (overrides: Partial<Job> = {}): Job => ({
    id: 'job-1',
    name: 'Test Job',
    body: 'console.log("old code");',
    adaptor: '@openfn/language-http@latest',
    enabled: true,
    ...overrides,
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('successfully parses and applies valid YAML', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: mockWorkflowActions,
        monacoRef: createMockMonacoRef(),
        jobs: [createMockJob()],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: false,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    const validYAML = 'name: Test Workflow\njobs:\n  job-1:\n    name: Job 1';

    await result.current.handleApplyWorkflow(validYAML, 'msg-1');

    await waitFor(() => {
      expect(mockStartApplyingWorkflow).toHaveBeenCalledWith('msg-1');
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(mockDoneApplyingWorkflow).toHaveBeenCalledWith('msg-1');
      expect(mockSetApplyingMessageId).toHaveBeenCalledWith(null);
    });
  });

  it('validates ID formats and rejects object IDs', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: mockWorkflowActions,
        monacoRef: createMockMonacoRef(),
        jobs: [createMockJob()],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: false,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    const invalidYAML = 'object-id: true\njobs:\n  job-1:\n    name: Job 1';

    await result.current.handleApplyWorkflow(invalidYAML, 'msg-1');

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Failed to apply workflow',
        description: expect.stringContaining('Invalid ID format') as string,
      });
      expect(mockImportWorkflow).not.toHaveBeenCalled();
    });
  });

  it('handles YAML parsing errors gracefully', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: mockWorkflowActions,
        monacoRef: createMockMonacoRef(),
        jobs: [createMockJob()],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: false,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    const invalidYAML = 'invalid: yaml: syntax:';

    await result.current.handleApplyWorkflow(invalidYAML, 'msg-1');

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Failed to apply workflow',
        description: expect.any(String) as string,
      });
      expect(mockImportWorkflow).not.toHaveBeenCalled();
    });
  });

  it('extracts and applies job credentials', async () => {
    const jobWithCred = createMockJob({
      id: 'job-1',
      credential: 'cred-123',
    });

    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: mockWorkflowActions,
        monacoRef: createMockMonacoRef(),
        jobs: [jobWithCred],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: false,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    const validYAML = 'name: Test Workflow';

    await result.current.handleApplyWorkflow(validYAML, 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalledWith(
        expect.objectContaining({
          _credentialsApplied: true,
        })
      );
    });
  });

  it('coordinates with collaborators', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
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
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockStartApplyingWorkflow).toHaveBeenCalledWith('msg-1');
      expect(mockDoneApplyingWorkflow).toHaveBeenCalledWith('msg-1');
    });
  });

  it('shows error notification on failure', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
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
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('invalid', 'msg-1');

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Failed to apply workflow',
        description: expect.any(String) as string,
      });
    });
  });

  it('does not signal completion if coordination failed', async () => {
    mockStartApplyingWorkflow.mockResolvedValueOnce(false);

    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
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
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockDoneApplyingWorkflow).not.toHaveBeenCalled();
    });
  });

  it('auto-saves after importWorkflow when isNewWorkflow is true', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: {
          ...mockWorkflowActions,
          saveWorkflow: mockSaveWorkflow,
        },
        monacoRef: createMockMonacoRef(),
        jobs: [],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: true,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(mockSaveWorkflow).toHaveBeenCalledWith({ silent: true });
    });

    const importOrder = mockImportWorkflow.mock.invocationCallOrder[0];
    const saveOrder = mockSaveWorkflow.mock.invocationCallOrder[0];
    expect(importOrder).toBeLessThan(saveOrder);
  });

  it('does not auto-save when isNewWorkflow is false', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: {
          ...mockWorkflowActions,
          saveWorkflow: mockSaveWorkflow,
        },
        monacoRef: createMockMonacoRef(),
        jobs: [],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: false,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
    });

    expect(mockSaveWorkflow).not.toHaveBeenCalled();
  });

  it('routes validation error to onValidationError callback when isNewWorkflow is true', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
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
        onValidationError: mockOnValidationError,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('invalid yaml', 'msg-1');

    await waitFor(() => {
      expect(mockOnValidationError).toHaveBeenCalledWith(expect.any(String));
      expect(notifications.alert).not.toHaveBeenCalled();
    });
  });

  it('falls back to toast for validation errors when isNewWorkflow is false', async () => {
    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
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
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('invalid yaml', 'msg-1');

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Failed to apply workflow',
        description: expect.any(String) as string,
      });
    });
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
      currentSession: { messages: [userMessage, assistantMessage] },
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
      currentSession: { messages: [userMessage, assistantMessage] },
      streamingApply: { yaml: 'name: Test', saveFailed: true },
    });

    await waitFor(() => {
      expect(successfulSaveWorkflow).toHaveBeenCalledWith({ silent: true });
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    // Successful retry clears the owed-save flag
    expect(mockStreamingApplyActions.setSaveFailed).toHaveBeenCalledWith(false);
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
      currentSession: { messages: [userMessage, assistantMessage] },
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

  it('shows save-failure toast and does not call onValidationError when save rejects', async () => {
    const failingSaveWorkflow = vi.fn(() =>
      Promise.reject(new Error('Network error'))
    );

    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: {
          ...mockWorkflowActions,
          saveWorkflow: failingSaveWorkflow,
        },
        monacoRef: createMockMonacoRef(),
        jobs: [],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: true,
        onValidationError: mockOnValidationError,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(notifications.alert).toHaveBeenCalledWith(
        expect.objectContaining({
          title: 'Failed to save workflow',
          description: 'Network error',
          action: expect.objectContaining({ label: 'Retry' }) as object,
        })
      );
      expect(mockOnValidationError).not.toHaveBeenCalled();
    });
  });

  it('records the streaming apply only after a successful import', async () => {
    const successfulSaveWorkflow = vi.fn(() => Promise.resolve(true));

    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
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
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    // Failed apply (parse error): the record is never set, so the final
    // message applies normally with no reset needed anywhere
    await result.current.handleApplyWorkflow('invalid yaml', '__streaming__');
    expect(mockStreamingApplyActions.set).not.toHaveBeenCalled();

    // Successful apply: recorded, and the save success marks no save owed
    await result.current.handleApplyWorkflow('name: Test', '__streaming__');

    await waitFor(() => {
      expect(mockStreamingApplyActions.set).toHaveBeenCalledWith('name: Test');
      expect(mockStreamingApplyActions.setSaveFailed).toHaveBeenCalledWith(
        false
      );
    });
  });

  it('marks the streaming apply save-failed when save rejects', async () => {
    const failingSaveWorkflow = vi.fn(() =>
      Promise.reject(new Error('Network error'))
    );

    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: {
          ...mockWorkflowActions,
          saveWorkflow: failingSaveWorkflow,
        },
        monacoRef: createMockMonacoRef(),
        jobs: [],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: true,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', '__streaming__');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      // Recorded after the successful import, then flagged so the final
      // message settles the owed save
      expect(mockStreamingApplyActions.set).toHaveBeenCalledWith('name: Test');
      expect(mockStreamingApplyActions.setSaveFailed).toHaveBeenCalledWith(
        true
      );
    });
  });

  it('marks the streaming apply save-failed when save returns null (disconnected)', async () => {
    const disconnectedSaveWorkflow = vi.fn(() => Promise.resolve(null));

    const { result } = renderHook(() =>
      useAIWorkflowApplications({
        sessionId: 'session-1',
        page: 'workflow_template',
        currentSession: null,
        currentUserId: 'user-123',
        aiMode: createMockAIMode('workflow_template'),
        workflowActions: {
          ...mockWorkflowActions,
          saveWorkflow: disconnectedSaveWorkflow,
        },
        monacoRef: createMockMonacoRef(),
        jobs: [],
        canApplyChanges: true,
        connectionState: 'connected' as ConnectionState,
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        isNewWorkflow: true,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', '__streaming__');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(mockStreamingApplyActions.set).toHaveBeenCalledWith('name: Test');
      expect(mockStreamingApplyActions.setSaveFailed).toHaveBeenCalledWith(
        true
      );
    });
  });
});
