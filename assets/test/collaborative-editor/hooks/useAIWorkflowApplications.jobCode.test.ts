/**
 * useAIWorkflowApplications - Job Code Tests
 *
 * Tests the job code functionality:
 * - Preview code diffs in Monaco
 * - Apply job code to Y.Doc
 * - Error handling
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
vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: vi.fn(),
    success: vi.fn(),
  },
}));

describe('useAIWorkflowApplications - Job Code', () => {
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
  describe('handlePreviewJobCode', () => {
    it('shows diff in Monaco when in job mode', () => {
      const monacoRef = createMockMonacoRef();
      const job = createMockJob({ id: 'job-1', body: 'old code' });

      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          workflowActions: mockWorkflowActions,
          monacoRef,
          jobs: [job],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: null,
          setApplyingMessageId: mockSetApplyingMessageId,
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      result.current.handlePreviewJobCode('new code', 'msg-1');

      expect(mockShowDiff).toHaveBeenCalledWith('old code', 'new code');
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith('msg-1');
    });

    it('does not preview when not in job mode', () => {
      const monacoRef = createMockMonacoRef();

      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'workflow_template',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('workflow_template'),
          workflowActions: mockWorkflowActions,
          monacoRef,
          jobs: [],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: null,
          setApplyingMessageId: mockSetApplyingMessageId,
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      result.current.handlePreviewJobCode('new code', 'msg-1');

      expect(mockShowDiff).not.toHaveBeenCalled();
    });

    it('does nothing if already previewing same message', () => {
      const monacoRef = createMockMonacoRef();
      const job = createMockJob({ id: 'job-1' });

      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          workflowActions: mockWorkflowActions,
          monacoRef,
          jobs: [job],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: 'msg-1', // Already previewing
          setApplyingMessageId: mockSetApplyingMessageId,
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      result.current.handlePreviewJobCode('new code', 'msg-1');

      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).not.toHaveBeenCalled();
    });

    it('clears existing diff before showing new one', () => {
      const monacoRef = createMockMonacoRef();
      const job = createMockJob({ id: 'job-1' });

      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          workflowActions: mockWorkflowActions,
          monacoRef,
          jobs: [job],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: 'msg-1', // Existing preview
          setApplyingMessageId: mockSetApplyingMessageId,
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      result.current.handlePreviewJobCode('new code', 'msg-2');

      expect(mockClearDiff).toHaveBeenCalledOnce();
      expect(mockShowDiff).toHaveBeenCalledOnce();
    });

    it('shows error when Monaco ref unavailable', () => {
      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          workflowActions: mockWorkflowActions,
          monacoRef: null,
          jobs: [createMockJob()],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: null,
          setApplyingMessageId: mockSetApplyingMessageId,
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      result.current.handlePreviewJobCode('new code', 'msg-1');

      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Preview unavailable',
        description: expect.stringContaining('Editor not ready') as string,
      });
    });

    it('shows error when job ID missing', () => {
      const monacoRef = createMockMonacoRef();

      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', {}), // No job_id
          workflowActions: mockWorkflowActions,
          monacoRef,
          jobs: [],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: null,
          setApplyingMessageId: mockSetApplyingMessageId,
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      result.current.handlePreviewJobCode('new code', 'msg-1');

      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Cannot preview code',
        description: 'No job selected',
      });
    });
  });

  describe('handleApplyJobCode', () => {
    it('updates job body and shows success notification', async () => {
      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
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

      await result.current.handleApplyJobCode('new code', 'msg-1');

      await waitFor(() => {
        expect(mockUpdateJob).toHaveBeenCalledWith('job-1', {
          body: 'new code',
        });
        expect(notifications.success).toHaveBeenCalledWith({
          title: 'Code applied',
          description: 'Job code has been updated',
        });
      });
    });

    it('does not apply when not in job mode', async () => {
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
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      await result.current.handleApplyJobCode('new code', 'msg-1');

      expect(mockUpdateJob).not.toHaveBeenCalled();
    });

    it('clears diff preview when applying', async () => {
      const monacoRef = createMockMonacoRef();

      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          workflowActions: mockWorkflowActions,
          monacoRef,
          jobs: [createMockJob()],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: 'msg-1',
          setApplyingMessageId: mockSetApplyingMessageId,
          appliedMessageIdsRef: { current: new Set() },
        })
      );

      await result.current.handleApplyJobCode('new code', 'msg-1');

      await waitFor(() => {
        expect(mockClearDiff).toHaveBeenCalledOnce();
        expect(mockSetPreviewingMessageId).toHaveBeenCalledWith(null);
      });
    });

    it('coordinates with collaborators', async () => {
      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
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

      await result.current.handleApplyJobCode('new code', 'msg-1');

      await waitFor(() => {
        expect(mockStartApplyingJobCode).toHaveBeenCalledWith('msg-1');
        expect(mockDoneApplyingJobCode).toHaveBeenCalledWith('msg-1');
      });
    });

    it('shows error when job ID missing', async () => {
      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', {}),
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

      await result.current.handleApplyJobCode('new code', 'msg-1');

      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Cannot apply code',
        description: 'No job selected',
      });
    });

    it('handles Y.Doc update errors gracefully', async () => {
      mockUpdateJob.mockImplementationOnce(() => {
        throw new Error('Update failed');
      });

      const { result } = renderHook(() =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession: null,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
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

      await result.current.handleApplyJobCode('new code', 'msg-1');

      await waitFor(() => {
        expect(notifications.alert).toHaveBeenCalledWith({
          title: 'Failed to apply code',
          description: 'Update failed',
        });
      });
    });
  });
});
