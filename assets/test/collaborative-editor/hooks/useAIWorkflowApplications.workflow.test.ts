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
  const mockImportWorkflow = vi.fn();
  const mockStartApplyingWorkflow = vi.fn(() => Promise.resolve(true));
  const mockDoneApplyingWorkflow = vi.fn(() => Promise.resolve());
  const mockStartApplyingJobCode = vi.fn(() => Promise.resolve(true));
  const mockDoneApplyingJobCode = vi.fn(() => Promise.resolve());
  const mockUpdateJob = vi.fn();
  const mockSetPreviewingMessageId = vi.fn();
  const mockSetApplyingMessageId = vi.fn();
  const mockClearDiff = vi.fn();
  const mockShowDiff = vi.fn();

  const mockWorkflowActions = {
    importWorkflow: mockImportWorkflow,
    startApplyingWorkflow: mockStartApplyingWorkflow,
    doneApplyingWorkflow: mockDoneApplyingWorkflow,
    startApplyingJobCode: mockStartApplyingJobCode,
    doneApplyingJobCode: mockDoneApplyingJobCode,
    updateJob: mockUpdateJob,
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
    mode,
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
        sessionType: 'workflow_template',
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
        sessionType: 'workflow_template',
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
        sessionType: 'workflow_template',
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
        sessionType: 'workflow_template',
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
        sessionType: 'workflow_template',
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
        sessionType: 'workflow_template',
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
        sessionType: 'workflow_template',
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
        appliedMessageIdsRef: { current: new Set() },
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockDoneApplyingWorkflow).not.toHaveBeenCalled();
    });
  });
});
