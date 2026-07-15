/**
 * useAIWorkflowApplications - Streaming Apply Recording Tests
 *
 * Tests how handleApplyWorkflow itself records outcomes into the
 * streaming-apply bookkeeping (set / setSaveFailed / clear), and how
 * save failures are surfaced without duplicating toasts already shown
 * elsewhere:
 * - No duplicate toast/onValidationError call when save rejects
 * - Streaming apply is recorded only after a successful import
 * - Streaming apply is marked save-failed when save rejects
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

describe('useAIWorkflowApplications - streaming apply recording', () => {
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

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('does not show its own toast and does not call onValidationError when save rejects', async () => {
    // A rejected saveWorkflow is the real-save-failure path — in production
    // this is the wrapped saveWorkflow from useWorkflow.tsx, which already
    // shows its own "Failed to save workflow" toast and re-throws. Showing
    // another one here would double up on a single failure.
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
        isSessionConnected: true,
        onValidationError: mockOnValidationError,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(mockStreamingApplyActions.setSaveFailed).toHaveBeenCalledWith(
        true
      );
    });
    expect(notifications.alert).not.toHaveBeenCalled();
    expect(mockOnValidationError).not.toHaveBeenCalled();
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
});
