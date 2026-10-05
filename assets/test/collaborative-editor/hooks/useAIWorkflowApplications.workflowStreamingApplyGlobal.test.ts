/**
 * useAIWorkflowApplications - Streaming Apply Reconciliation for Global Sessions
 *
 * Global sessions apply streamed YAML page-independently, so their
 * reconciliation (clearing the streamingApply record, retrying an owed
 * save) must also run when the reply finishes while the user is on a
 * job page — not only on the workflow_template page.
 */

import { renderHook, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import { useAIWorkflowApplications } from '../../../js/collaborative-editor/hooks/useAIWorkflowApplications';
import type { ConnectionState } from '../../../js/collaborative-editor/types/ai-assistant';

import { createAIWorkflowApplicationsMocks } from './__helpers__/aiWorkflowApplicationsTestSetup';

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

describe('useAIWorkflowApplications - global session reconciliation off the canvas page', () => {
  const {
    mockImportWorkflow,
    mockSetPreviewingMessageId,
    mockSetApplyingMessageId,
    mockStreamingApplyActions,
    mockWorkflowActions,
    createMockMonacoRef,
    createMockAIMode,
  } = createAIWorkflowApplicationsMocks();

  beforeEach(() => {
    vi.clearAllMocks();
  });

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

  const renderOnJobPage = (
    saveWorkflow?: () => Promise<boolean>,
    appliedMessageIdsRef = { current: new Set<string>() }
  ) =>
    renderHook(
      ({ currentSession, streamingApply }: Props) =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'job_code',
          currentSession,
          currentUserId: 'user-123',
          aiMode: createMockAIMode('job_code'),
          isGlobalSession: true,
          workflowActions: saveWorkflow
            ? { ...mockWorkflowActions, saveWorkflow }
            : mockWorkflowActions,
          monacoRef: createMockMonacoRef(),
          jobs: [],
          canApplyChanges: true,
          connectionState: 'connected' as ConnectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: null,
          setApplyingMessageId: mockSetApplyingMessageId,
          isNewWorkflow: true,
          isSessionConnected: true,
          isSessionConnecting: false,
          appliedMessageIdsRef,
          streamingApply,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      {
        initialProps: {
          currentSession: { messages: [userMessage] },
          streamingApply: null,
        } as Props,
      }
    );

  it('clears a matching streaming apply record while on the job page', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };
    const { rerender } = renderOnJobPage(undefined, appliedMessageIdsRef);

    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      streamingApply: { yaml: 'name: Test', saveFailed: false },
    });

    await waitFor(() => {
      expect(appliedMessageIdsRef.current.has('msg-1')).toBe(true);
      expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
  });

  it('retries an owed save while on the job page', async () => {
    const successfulSaveWorkflow = vi.fn(() => Promise.resolve(true));
    const { rerender } = renderOnJobPage(successfulSaveWorkflow);

    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      streamingApply: { yaml: 'name: Test', saveFailed: true },
    });

    await waitFor(() => {
      expect(successfulSaveWorkflow).toHaveBeenCalled();
      expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
  });
});
