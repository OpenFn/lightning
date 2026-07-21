/**
 * useAIWorkflowApplications - Auto-Save on New Workflow Tests
 *
 * Tests the auto-save behavior that follows a successful workflow
 * apply for brand-new (unsaved) workflows, and how validation errors
 * are routed differently depending on whether the workflow is new:
 * - Auto-save after importWorkflow when isNewWorkflow is true
 * - No auto-save for existing workflows
 * - Validation error routing (onValidationError vs toast)
 */

import { renderHook, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import flowEvents from '../../../js/collaborative-editor/components/diagram/react-flow-events';
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

vi.mock(
  '../../../js/collaborative-editor/components/diagram/react-flow-events',
  () => ({
    default: {
      dispatch: vi.fn(),
      register: vi.fn(() => () => {}),
    },
  })
);

describe('useAIWorkflowApplications - auto-save on new workflow', () => {
  const {
    mockImportWorkflow,
    mockSetPreviewingMessageId,
    mockSetApplyingMessageId,
    mockSaveWorkflow,
    mockStreamingApplyActions,
    mockWorkflowActions,
    createMockMonacoRef,
    createMockAIMode,
  } = createAIWorkflowApplicationsMocks();

  const mockOnValidationError = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
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
        isSessionConnected: true,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
      expect(mockSaveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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
        isSessionConnected: true,
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

  describe('fit-view dispatch', () => {
    // eslint-disable-next-line @typescript-eslint/unbound-method -- vi.fn(), no `this` binding to lose
    const mockDispatch = vi.mocked(flowEvents.dispatch);

    it('does not dispatch fit-view itself when isNewWorkflow is true (the shared save handler already does)', async () => {
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
          isSessionConnected: true,
          appliedMessageIdsRef: { current: new Set() },
          streamingApply: null,
          streamingApplyActions: mockStreamingApplyActions,
        })
      );

      await result.current.handleApplyWorkflow('name: Test', 'msg-1');

      await waitFor(() => {
        expect(mockSaveWorkflow).toHaveBeenCalled();
      });
      expect(mockDispatch).not.toHaveBeenCalled();
    });

    it('dispatches fit-view when isNewWorkflow is false (no shared save handler runs for this path)', async () => {
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
        expect(mockDispatch).toHaveBeenCalledWith('fit-view');
      });
      expect(mockDispatch).toHaveBeenCalledTimes(1);
    });
  });
});
