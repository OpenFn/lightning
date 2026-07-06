/**
 * useAIWorkflowApplications - Global Message Tests
 *
 * Tests behavior specific to global AI assistant messages (full workflow
 * YAML, `from_global: true`, no job_id):
 * - handlePreviewGlobalStep: per-step diff extracted from the workflow YAML
 * - handleApplyWorkflow: relaxed mode guard for global messages only
 */

import { renderHook, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import type { MonacoHandle } from '../../../js/collaborative-editor/components/CollaborativeMonaco';
import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import { useAIWorkflowApplications } from '../../../js/collaborative-editor/hooks/useAIWorkflowApplications';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';
import type { Job } from '../../../js/collaborative-editor/types';
import type { Message } from '../../../js/collaborative-editor/types/ai-assistant';
import {
  convertWorkflowSpecToState,
  parseWorkflowYAML,
} from '../../../js/yaml/util';

vi.mock('../../../js/yaml/util', () => ({
  parseWorkflowYAML: vi.fn(),
  convertWorkflowSpecToState: vi.fn(),
  applyJobCredsToWorkflowState: vi.fn((state: unknown) => state),
  extractJobCredentials: vi.fn(() => ({})),
}));

vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: vi.fn(),
    warning: vi.fn(),
    success: vi.fn(),
  },
}));

describe('useAIWorkflowApplications - global messages', () => {
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
  };

  const createMockMonacoRef = () => ({
    current: {
      clearDiff: mockClearDiff,
      showDiff: mockShowDiff,
    } as MonacoHandle,
  });

  const createMockAIMode = (
    page: 'workflow_template' | 'job_code',
    context: Record<string, unknown> = {}
  ): AIModeResult => ({
    mode: 'workflow_template',
    page,
    context,
    storageKey: `ai-${page}`,
  });

  const createMockJob = (overrides: Partial<Job> = {}): Job =>
    ({
      id: 'job-1',
      name: 'Test Job',
      body: 'old body',
      adaptor: '@openfn/language-http@latest',
      enabled: true,
      ...overrides,
    }) as Job;

  const createGlobalMessage = (overrides: Partial<Message> = {}): Message => ({
    id: 'msg-global',
    role: 'assistant',
    content: 'Updated your workflow',
    code: 'name: Test Workflow',
    status: 'success',
    inserted_at: new Date().toISOString(),
    user_id: 'user-123',
    from_global: true,
    ...overrides,
  });

  /** Sets the body that the parsed YAML reports for job-1 */
  const mockYamlJobBody = (body: string) => {
    vi.mocked(convertWorkflowSpecToState).mockReturnValue({
      id: 'wf-1',
      name: 'Test Workflow',
      jobs: [
        {
          id: 'job-1',
          name: 'Test Job',
          adaptor: '@openfn/language-http@latest',
          body,
          keychain_credential_id: null,
          project_credential_id: null,
        },
      ],
      triggers: [],
      edges: [],
      positions: null,
    });
  };

  const renderApplications = (
    overrides: Partial<Parameters<typeof useAIWorkflowApplications>[0]> = {}
  ) =>
    renderHook(() =>
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
        connectionState: 'connected',
        setPreviewingMessageId: mockSetPreviewingMessageId,
        previewingMessageId: null,
        setApplyingMessageId: mockSetApplyingMessageId,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
        ...overrides,
      })
    );

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(parseWorkflowYAML).mockImplementation((yaml: string) => {
      if (yaml.includes('invalid')) {
        throw new Error('Invalid YAML syntax');
      }
      return { name: 'Test Workflow', jobs: {}, triggers: {}, edges: {} };
    });
    mockYamlJobBody('new body');
  });

  describe('handlePreviewGlobalStep', () => {
    it('shows a diff when the open step body changed in the YAML', () => {
      const { result } = renderApplications();

      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');

      expect(mockShowDiff).toHaveBeenCalledWith('old body', 'new body');
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith('msg-1');
    });

    it('shows no diff and clears a stale one when the open step is unchanged', () => {
      mockYamlJobBody('old body'); // same as current job body

      const { result } = renderApplications({
        previewingMessageId: 'previous-msg',
      });

      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');

      expect(mockClearDiff).toHaveBeenCalled();
      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).not.toHaveBeenCalled();
    });

    it('warns when the open step is missing from the YAML (id not preserved)', () => {
      vi.mocked(convertWorkflowSpecToState).mockReturnValue({
        id: 'wf-1',
        name: 'Test Workflow',
        jobs: [],
        triggers: [],
        edges: [],
        positions: null,
      });

      const { result } = renderApplications();

      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');

      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).not.toHaveBeenCalled();
      expect(notifications.warning).toHaveBeenCalled();
    });

    it('alerts for invalid YAML', () => {
      const { result } = renderApplications();

      result.current.handlePreviewGlobalStep('invalid yaml', 'msg-1');

      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockClearDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).not.toHaveBeenCalled();
      expect(notifications.alert).toHaveBeenCalled();
    });

    it('does nothing when no job is open (workflow_template mode)', () => {
      const { result } = renderApplications({
        aiMode: createMockAIMode('workflow_template'),
        page: 'workflow_template',
      });

      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');

      expect(parseWorkflowYAML).not.toHaveBeenCalled();
      expect(mockShowDiff).not.toHaveBeenCalled();
    });

    it('deduplicates previews like handlePreviewJobCode', () => {
      // Already previewing this message -> no-op
      const { result } = renderApplications({
        previewingMessageId: 'msg-1',
      });
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).not.toHaveBeenCalled();

      // Streaming preview already shown -> only swap the message id
      const { result: streaming } = renderApplications({
        previewingMessageId: '__streaming__',
      });
      streaming.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith('msg-1');
    });
  });

  describe('handleApplyWorkflow with global messages', () => {
    it('applies a global message while a job is open (job_code mode)', async () => {
      const globalMessage = createGlobalMessage();
      const { result } = renderApplications({
        currentSession: { messages: [globalMessage] },
      });

      await result.current.handleApplyWorkflow(
        globalMessage.code!,
        globalMessage.id
      );

      await waitFor(() => {
        expect(mockStartApplyingWorkflow).toHaveBeenCalledWith('msg-global');
        expect(mockImportWorkflow).toHaveBeenCalled();
        expect(mockDoneApplyingWorkflow).toHaveBeenCalledWith('msg-global');
      });
    });

    it('clears an active step diff when applying a global message', async () => {
      const globalMessage = createGlobalMessage();
      const { result } = renderApplications({
        currentSession: { messages: [globalMessage] },
        previewingMessageId: globalMessage.id,
      });

      await result.current.handleApplyWorkflow(
        globalMessage.code!,
        globalMessage.id
      );

      await waitFor(() => {
        expect(mockClearDiff).toHaveBeenCalled();
        expect(mockSetPreviewingMessageId).toHaveBeenCalledWith(null);
        expect(mockImportWorkflow).toHaveBeenCalled();
      });
    });

    it('still no-ops for a non-global message in job_code mode', async () => {
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});
      const workflowMessage = createGlobalMessage({
        id: 'msg-workflow',
        from_global: false,
      });

      const { result } = renderApplications({
        currentSession: { messages: [workflowMessage] },
      });

      await result.current.handleApplyWorkflow(
        workflowMessage.code!,
        workflowMessage.id
      );

      expect(mockStartApplyingWorkflow).not.toHaveBeenCalled();
      expect(mockImportWorkflow).not.toHaveBeenCalled();
      expect(mockSetApplyingMessageId).not.toHaveBeenCalled();
      consoleError.mockRestore();
    });

    it('still applies non-global messages in workflow_template mode', async () => {
      const workflowMessage = createGlobalMessage({
        id: 'msg-workflow',
        from_global: false,
      });

      const { result } = renderApplications({
        aiMode: createMockAIMode('workflow_template'),
        page: 'workflow_template',
        currentSession: { messages: [workflowMessage] },
      });

      await result.current.handleApplyWorkflow(
        workflowMessage.code!,
        workflowMessage.id
      );

      await waitFor(() => {
        expect(mockImportWorkflow).toHaveBeenCalled();
        expect(mockDoneApplyingWorkflow).toHaveBeenCalledWith('msg-workflow');
      });
    });
  });
});
