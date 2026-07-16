/**
 * useAIWorkflowApplications - Streaming Apply Dedup Tests
 *
 * Tests how a completed AI response reconciles against a workflow
 * already applied during streaming, when the streamed YAML matches
 * the final message:
 * - Skip re-import when the final message matches the streaming record
 * - Retry an owed save (without re-importing) when the streamed apply
 *   had previously save-failed
 */

import { renderHook, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import { useAIWorkflowApplications } from '../../../js/collaborative-editor/hooks/useAIWorkflowApplications';
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

describe('useAIWorkflowApplications - streaming apply dedup', () => {
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

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('skips re-import when the final message matches the streaming apply record', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };

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

    const { rerender } = renderHook(
      ({ currentSession, streamingApply }: Props) =>
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
          isSessionConnected: true,
          appliedMessageIdsRef,
          streamingApply,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      {
        initialProps: {
          currentSession: { messages: [userMessage] },
          streamingApply: null,
        },
      }
    );

    // Streaming already imported this exact YAML and saved successfully
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
    expect(mockSaveWorkflow).not.toHaveBeenCalled();
  });

  it('retries the owed save without re-importing when the matching streaming apply is save-failed', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };
    const successfulSaveWorkflow = vi.fn(() => Promise.resolve(true));

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

    const { rerender } = renderHook(
      ({ currentSession, streamingApply }: Props) =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'workflow_template',
          currentSession,
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
          appliedMessageIdsRef,
          streamingApply,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      {
        initialProps: {
          currentSession: { messages: [userMessage] },
          streamingApply: null,
        },
      }
    );

    // Streaming imported the YAML but its save failed — a save is still owed
    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      streamingApply: { yaml: 'name: Test', saveFailed: true },
    });

    await waitFor(() => {
      expect(successfulSaveWorkflow).toHaveBeenCalledWith({
        notify: 'error-only',
      });
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    // Successful retry clears the owed-save flag
    expect(mockStreamingApplyActions.setSaveFailed).toHaveBeenCalledWith(false);
  });
});
