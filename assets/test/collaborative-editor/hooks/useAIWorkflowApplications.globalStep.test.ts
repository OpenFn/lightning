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

    it('shows no diff when the open step is missing from the YAML', () => {
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
    });

    it('does nothing for invalid YAML', () => {
      const { result } = renderApplications();

      result.current.handlePreviewGlobalStep('invalid yaml', 'msg-1');

      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockClearDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).not.toHaveBeenCalled();
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

    it('does not re-show for the same open step but re-fires for a different one', () => {
      // job_b has a changed body too, so a diff would show if not deduped
      vi.mocked(convertWorkflowSpecToState).mockReturnValue({
        id: 'wf-1',
        name: 'Test Workflow',
        jobs: [
          {
            id: 'job-1',
            name: 'Test Job',
            adaptor: '@openfn/language-http@latest',
            body: 'new body',
            keychain_credential_id: null,
            project_credential_id: null,
          },
          {
            id: 'job-2',
            name: 'Other Job',
            adaptor: '@openfn/language-http@latest',
            body: 'new body 2',
            keychain_credential_id: null,
            project_credential_id: null,
          },
        ],
        triggers: [],
        edges: [],
        positions: null,
      });

      // First call on job-1 shows the diff
      const { result } = renderApplications({
        jobs: [
          createMockJob({ id: 'job-1', body: 'old body' }),
          createMockJob({ id: 'job-2', body: 'old body 2' }),
        ],
        aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
      });
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).toHaveBeenCalledTimes(1);

      // Same message + same open step -> no re-show
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).toHaveBeenCalledTimes(1);

      // Same message but a different open step -> re-fires
      const { result: onJob2 } = renderApplications({
        jobs: [
          createMockJob({ id: 'job-1', body: 'old body' }),
          createMockJob({ id: 'job-2', body: 'old body 2' }),
        ],
        aiMode: createMockAIMode('job_code', { job_id: 'job-2' }),
      });
      onJob2.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).toHaveBeenCalledTimes(2);
      expect(mockShowDiff).toHaveBeenLastCalledWith('old body 2', 'new body 2');
    });

    it('re-shows the same step after resetGlobalStepPreviewDedup (re-entry)', () => {
      const { result } = renderApplications();
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).toHaveBeenCalledTimes(1);

      // Without a reset the same step would be deduped
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).toHaveBeenCalledTimes(1);

      // A fresh editor mount resets the dedup, so re-entry re-shows
      result.current.resetGlobalStepPreviewDedup();
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).toHaveBeenCalledTimes(2);
    });

    it('streaming preview swaps to the plain message id and dedups the step', () => {
      const { result } = renderApplications({
        previewingMessageId: '__streaming__',
      });
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith('msg-1');

      // The step is now deduped (same message + same open step) -> no re-show
      result.current.handlePreviewGlobalStep('name: Test Workflow', 'msg-1');
      expect(mockShowDiff).not.toHaveBeenCalled();
    });
  });

  describe('pendingGlobalMessage selector', () => {
    const userMessage: Message = {
      id: 'user-1',
      role: 'user',
      content: 'Update my workflow',
      status: 'success',
      inserted_at: new Date().toISOString(),
      user_id: 'user-123',
    };

    it('picks the latest unapplied successful global message', () => {
      const older = createGlobalMessage({ id: 'global-old' });
      const newer = createGlobalMessage({ id: 'global-new' });

      const { result } = renderApplications({
        currentSession: { messages: [userMessage, older, newer] },
      });

      expect(result.current.pendingGlobalMessage?.id).toBe('global-new');
    });

    it('stops being pending once explicitly applied', async () => {
      const message = createGlobalMessage({ id: 'global-applied' });

      const { result } = renderApplications({
        currentSession: { messages: [userMessage, message] },
      });

      expect(result.current.pendingGlobalMessage?.id).toBe('global-applied');

      await result.current.handleApplyWorkflow(message.code!, message.id);

      await waitFor(() => {
        expect(result.current.pendingGlobalMessage).toBeNull();
      });
    });

    it('is unaffected by appliedMessageIdsRef (auto-apply dedup only)', () => {
      const message = createGlobalMessage({ id: 'global-1' });

      const { result } = renderApplications({
        currentSession: { messages: [userMessage, message] },
        appliedMessageIdsRef: { current: new Set(['global-1']) },
      });

      // Seeding the auto-apply dedup ref must NOT clear pending — only an
      // explicit apply does (global messages never auto-apply).
      expect(result.current.pendingGlobalMessage?.id).toBe('global-1');
    });

    it('ignores non-global, non-success, code-less, and user messages', () => {
      const nonGlobal = createGlobalMessage({
        id: 'workflow-msg',
        from_global: false,
      });
      const errored = createGlobalMessage({
        id: 'errored',
        status: 'error',
      });
      const noCode = createGlobalMessage({ id: 'no-code', code: undefined });

      const { result } = renderApplications({
        currentSession: {
          messages: [userMessage, nonGlobal, errored, noCode],
        },
      });

      expect(result.current.pendingGlobalMessage).toBeNull();
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

  describe('auto-apply suppression for global messages', () => {
    const userMessage: Message = {
      id: 'user-1',
      role: 'user',
      content: 'Update my workflow',
      status: 'success',
      inserted_at: new Date().toISOString(),
      user_id: 'user-123',
    };

    const baseProps = () => ({
      sessionId: 'session-1',
      page: 'workflow_template' as const,
      currentSession: { messages: [userMessage] },
      currentUserId: 'user-123',
      aiMode: createMockAIMode('workflow_template'),
      workflowActions: mockWorkflowActions,
      monacoRef: createMockMonacoRef(),
      jobs: [createMockJob()],
      canApplyChanges: true,
      connectionState: 'connected' as const,
      setPreviewingMessageId: mockSetPreviewingMessageId,
      previewingMessageId: null,
      setApplyingMessageId: mockSetApplyingMessageId,
      appliedMessageIdsRef: { current: new Set<string>() },
    });

    it('does not auto-apply a global message that arrives on the canvas', () => {
      const initialProps = baseProps();
      const { rerender } = renderHook(p => useAIWorkflowApplications(p), {
        initialProps,
      });

      // A global reply arrives after the session has loaded.
      rerender({
        ...initialProps,
        currentSession: {
          messages: [userMessage, createGlobalMessage({ id: 'g1' })],
        },
      });

      expect(mockImportWorkflow).not.toHaveBeenCalled();
    });

    it('still auto-applies a non-global workflow message', async () => {
      const initialProps = baseProps();
      const { rerender } = renderHook(p => useAIWorkflowApplications(p), {
        initialProps,
      });

      rerender({
        ...initialProps,
        currentSession: {
          messages: [
            userMessage,
            createGlobalMessage({ id: 'w1', from_global: false }),
          ],
        },
      });

      await waitFor(() => {
        expect(mockImportWorkflow).toHaveBeenCalled();
      });
    });
  });
});
