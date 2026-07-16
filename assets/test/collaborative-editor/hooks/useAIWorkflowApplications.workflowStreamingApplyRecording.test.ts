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

describe('useAIWorkflowApplications - streaming apply recording', () => {
  const {
    mockImportWorkflow,
    mockSetPreviewingMessageId,
    mockSetApplyingMessageId,
    mockStreamingApplyActions,
    mockWorkflowActions,
    createMockMonacoRef,
    createMockAIMode,
  } = createAIWorkflowApplicationsMocks();

  const mockOnValidationError = vi.fn();

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
