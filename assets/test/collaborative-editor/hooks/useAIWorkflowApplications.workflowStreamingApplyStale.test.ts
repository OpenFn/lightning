/**
 * useAIWorkflowApplications - Streaming Apply Stale Record Tests
 *
 * Tests how a completed AI response supersedes a stale streaming
 * record whose YAML no longer matches the final message, including
 * the record seeded transiently while a session is still loading:
 * - Apply normally when the final YAML differs from the streamed record
 * - Clear a stale record seeded during session-load so later responses
 *   are not skipped
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

describe('useAIWorkflowApplications - streaming apply stale record', () => {
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

  it('applies normally when the final message YAML differs from the streaming apply record', async () => {
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
          isNewWorkflow: false,
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

    // Stale record: streaming applied different YAML than the final message
    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      streamingApply: { yaml: 'name: Something else', saveFailed: false },
    });

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
    });
    // The non-streaming apply supersedes (and clears) the stale record
    expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
  });

  it('clears the streaming apply record during session-load seeding so later responses are not skipped', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };

    const userMessage1 = {
      id: 'user-msg-1',
      role: 'user' as const,
      content: 'Build me a workflow',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:00Z',
      user_id: 'user-123',
    };
    const assistantMessage1 = {
      id: 'msg-1',
      role: 'assistant' as const,
      content: 'Here is workflow 1',
      code: 'name: Test 1',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:01Z',
    };
    const userMessage2 = {
      id: 'user-msg-2',
      role: 'user' as const,
      content: 'Refine the workflow',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:02Z',
      user_id: 'user-123',
    };
    const assistantMessage2 = {
      id: 'msg-2',
      role: 'assistant' as const,
      content: 'Here is workflow 2',
      code: 'name: Test 2',
      status: 'success' as const,
      inserted_at: '2024-01-01T00:00:03Z',
    };

    type Props = {
      currentSession: { messages: (typeof userMessage1)[] } | null;
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
          currentSession: null,
          // Streaming fired before the session finished loading
          streamingApply: { yaml: 'name: Test 1', saveFailed: false },
        },
      }
    );

    // First new_message: session loading for the first time (hasLoadedSessionRef = false)
    rerender({
      currentSession: { messages: [userMessage1, assistantMessage1] },
      streamingApply: { yaml: 'name: Test 1', saveFailed: false },
    });

    await waitFor(() => {
      // Session-load path marks messages applied but does not re-import;
      // the streaming record is dropped, never consumed
      expect(mockStreamingApplyActions.clear).toHaveBeenCalled();
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();

    // Second response arrives — record cleared, so auto-apply proceeds
    rerender({
      currentSession: {
        messages: [
          userMessage1,
          assistantMessage1,
          userMessage2,
          assistantMessage2,
        ],
      },
      streamingApply: null,
    });

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
    });
  });
});
