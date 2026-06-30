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

  it('skips auto-apply and marks message applied when appliedViaStreamingRef is set', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };
    const appliedViaStreamingRef = { current: false };

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
    };

    const { rerender } = renderHook(
      ({ currentSession }: Props) =>
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
          appliedViaStreamingRef,
        }),
      { initialProps: { currentSession: { messages: [userMessage] } } }
    );

    // Simulate streaming having already applied the YAML
    appliedViaStreamingRef.current = true;

    rerender({
      currentSession: { messages: [userMessage, assistantMessage] },
    });

    await waitFor(() => {
      expect(mockImportWorkflow).not.toHaveBeenCalled();
      expect(mockSaveWorkflow).not.toHaveBeenCalled();
      expect(appliedMessageIdsRef.current.has('msg-1')).toBe(true);
      expect(appliedViaStreamingRef.current).toBe(false);
    });
  });

  it('resets appliedViaStreamingRef during session-load so subsequent responses are not skipped', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };
    const appliedViaStreamingRef = { current: false };

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
    };

    const { rerender } = renderHook(
      ({ currentSession }: Props) =>
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
          appliedViaStreamingRef,
        }),
      { initialProps: { currentSession: null } }
    );

    // Simulate streaming having fired before the first new_message arrives
    appliedViaStreamingRef.current = true;

    // First new_message: session loading for the first time (hasLoadedSessionRef = false)
    rerender({
      currentSession: { messages: [userMessage1, assistantMessage1] },
    });

    await waitFor(() => {
      // Session-load path marks messages applied but does not re-import
      expect(mockImportWorkflow).not.toHaveBeenCalled();
      // Fix: ref must be cleared so the next real response isn't skipped
      expect(appliedViaStreamingRef.current).toBe(false);
    });

    // Second response arrives — ref is now false, so auto-apply proceeds
    rerender({
      currentSession: {
        messages: [
          userMessage1,
          assistantMessage1,
          userMessage2,
          assistantMessage2,
        ],
      },
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

  it('resets appliedViaStreamingRef when save rejects after a successful streaming apply', async () => {
    const appliedViaStreamingRef = { current: true };
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
        appliedViaStreamingRef,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(appliedViaStreamingRef.current).toBe(false);
    });
  });

  it('resets appliedViaStreamingRef when save returns null (disconnected) after a successful streaming apply', async () => {
    const appliedViaStreamingRef = { current: true };
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
        appliedViaStreamingRef,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(appliedViaStreamingRef.current).toBe(false);
    });
  });
});
