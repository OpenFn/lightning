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

import { useAIWorkflowApplications } from '../../../js/collaborative-editor/hooks/useAIWorkflowApplications';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';
import type { ConnectionState } from '../../../js/collaborative-editor/types/ai-assistant';

import { createAIWorkflowApplicationsMocks } from './__helpers__/aiWorkflowApplicationsTestSetup';

// Mock modules. The mock implementations are dynamically imported from
// the shared helper (rather than statically imported at the top of this
// file) because vi.mock() factories are hoisted above imports; a static
// import here would be referenced before it's initialized.
vi.mock('../../../js/yaml/util', async () => {
  const { aiWorkflowApplicationsYamlUtilMock } = await import(
    './__helpers__/aiWorkflowApplicationsTestSetup'
  );
  return aiWorkflowApplicationsYamlUtilMock();
});

vi.mock('../../../js/collaborative-editor/lib/notifications', async () => {
  const { aiWorkflowApplicationsNotificationsMock } = await import(
    './__helpers__/aiWorkflowApplicationsTestSetup'
  );
  return aiWorkflowApplicationsNotificationsMock();
});

describe('useAIWorkflowApplications - handleApplyWorkflow', () => {
  const {
    mockImportWorkflow,
    mockStartApplyingWorkflow,
    mockDoneApplyingWorkflow,
    mockSetPreviewingMessageId,
    mockSetApplyingMessageId,
    mockStreamingApplyActions,
    mockWorkflowActions,
    createMockMonacoRef,
    createMockAIMode,
    createMockJob,
  } = createAIWorkflowApplicationsMocks();

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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
});
