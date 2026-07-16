/**
 * useAIWorkflowApplications - Offline Gate Tests
 *
 * Tests the connection gate that blocks applying a brand-new workflow
 * while the collaboration session is disconnected, and the bookkeeping
 * that lets a blocked auto-apply retry automatically once reconnected:
 * - Gate blocks creation offline (new workflow, session disconnected)
 * - Gate does not block existing workflows when disconnected
 * - Blocked auto-apply retries automatically after reconnect
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

describe('useAIWorkflowApplications - offline gate', () => {
  const {
    mockImportWorkflow,
    mockStartApplyingWorkflow,
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

  it('gate blocks creation offline: new workflow, session disconnected', async () => {
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
        isSessionConnected: false,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Not connected',
        description: 'Connect to the server before creating a workflow.',
      });
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(mockStartApplyingWorkflow).not.toHaveBeenCalled();
  });

  it('gate shows "still connecting" instead of "not connected" during the initial join window', async () => {
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
        isSessionConnected: false,
        isSessionConnecting: true,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Still connecting',
        description: 'Connecting to the server — try again in a moment.',
      });
    });
    expect(notifications.alert).not.toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Not connected' })
    );
    expect(mockImportWorkflow).not.toHaveBeenCalled();
  });

  it('gate does not block existing workflows when session disconnected', async () => {
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
        isSessionConnected: false,
        appliedMessageIdsRef: { current: new Set() },
        streamingApply: null,
        streamingApplyActions: mockStreamingApplyActions,
      })
    );

    await result.current.handleApplyWorkflow('name: Test', 'msg-1');

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
    });
    expect(notifications.alert).not.toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Not connected' })
    );
  });

  it('blocked auto-apply retries automatically after reconnect', async () => {
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
      isSessionConnected: boolean;
    };

    const { rerender } = renderHook(
      ({ currentSession, isSessionConnected }: Props) =>
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
          isSessionConnected,
          appliedMessageIdsRef,
          streamingApply: null,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      {
        initialProps: {
          currentSession: { messages: [userMessage] },
          isSessionConnected: false,
        },
      }
    );

    // Auto-apply effect fires for the new assistant message while offline:
    // the gate blocks the apply and the message is left unmarked so a later
    // run of this effect can retry it.
    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      isSessionConnected: false,
    });

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith({
        title: 'Not connected',
        description: 'Connect to the server before creating a workflow.',
      });
    });
    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(appliedMessageIdsRef.current.has('msg-1')).toBe(false);

    // Reconnect with the same messages: the effect re-runs (isSessionConnected
    // changes handleApplyWorkflow's identity) and retries automatically,
    // with no manual "Apply" click required.
    rerender({
      currentSession: {
        messages: [userMessage, assistantMessage] as (typeof userMessage)[],
      },
      isSessionConnected: true,
    });

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalled();
    });
    expect(appliedMessageIdsRef.current.has('msg-1')).toBe(true);
  });
});
