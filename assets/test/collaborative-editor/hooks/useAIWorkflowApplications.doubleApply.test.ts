/**
 * Regression — double-apply of a single assistant message must not happen.
 *
 * A brand-new-workflow AI apply must import and save exactly once per message,
 * even though the auto-apply effect re-runs on nearly every render (real
 * useWorkflowActions returns a new saveWorkflow closure each render). Two paths
 * can launch an apply and each must mark the message so the other is a no-op:
 *   1. the auto-apply effect (message authored by the current user), and
 *   2. the manual "Apply" button, which the wrapper routes through the hook's
 *      `launchApply` for exactly this reason.
 *
 * Faithful modelling of production:
 *  - `saveWorkflow` is rebuilt fresh on every render (real useWorkflowActions
 *    returns a new IIFE-built function each render → the auto-apply effect
 *    re-runs every render).
 *  - The save blocks on a controllable promise (models the channel round-trip).
 *  - A re-render happens while the save is pending (in production the first
 *    import mutates `jobs`, which forces exactly this re-render).
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

describe('useAIWorkflowApplications - double-apply guard', () => {
  const {
    mockImportWorkflow,
    mockStartApplyingWorkflow,
    mockDoneApplyingWorkflow,
    mockStartApplyingJobCode,
    mockDoneApplyingJobCode,
    mockUpdateJob,
    mockSetPreviewingMessageId,
    mockSetApplyingMessageId,
    mockStreamingApplyActions,
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

  it('auto-applies the same message only once even when the effect re-runs mid-save', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };

    // Save blocks until released — models the channel round-trip window.
    let releaseSave: () => void = () => {};
    const savePending = new Promise<void>(resolve => {
      releaseSave = resolve;
    });
    const mockSaveWorkflow = vi.fn(() => savePending);

    // Fresh workflowActions object every render, with a fresh saveWorkflow
    // closure — mirrors useWorkflowActions()'s per-render rebuild, which is
    // what makes the auto-apply effect re-run on every render.
    const makeActions = () => ({
      importWorkflow: mockImportWorkflow,
      startApplyingWorkflow: mockStartApplyingWorkflow,
      doneApplyingWorkflow: mockDoneApplyingWorkflow,
      startApplyingJobCode: mockStartApplyingJobCode,
      doneApplyingJobCode: mockDoneApplyingJobCode,
      updateJob: mockUpdateJob,
      saveWorkflow: () => mockSaveWorkflow(),
    });

    type Props = { messages: (typeof userMessage)[] };

    const { rerender } = renderHook(
      ({ messages }: Props) =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'workflow_template',
          currentSession: { messages },
          currentUserId: 'user-123',
          aiMode: createMockAIMode('workflow_template'),
          workflowActions: makeActions(),
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
          streamingApply: null,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      { initialProps: { messages: [userMessage] } }
    );

    // New assistant message arrives → auto-apply fires and reaches the
    // (blocked) save.
    rerender({ messages: [userMessage, assistantMessage] });
    await waitFor(() => expect(mockImportWorkflow).toHaveBeenCalledTimes(1));

    // Re-render while the save is still pending. In production the first
    // import's `jobs` mutation guarantees this render.
    rerender({ messages: [userMessage, assistantMessage] });
    rerender({ messages: [userMessage, assistantMessage] });

    // Let any re-run effects and their microtasks settle.
    await new Promise(r => setTimeout(r, 20));

    // Correct behaviour: the message is applied exactly once.
    expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
    expect(mockSaveWorkflow).toHaveBeenCalledTimes(1);

    // Once the save resolves, the message is recorded as terminally applied so
    // no later effect run re-launches it.
    releaseSave();
    await waitFor(() =>
      expect(appliedMessageIdsRef.current.has('msg-1')).toBe(true)
    );
    rerender({ messages: [userMessage, assistantMessage] });
    await new Promise(r => setTimeout(r, 20));
    expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
  });

  it('does not re-apply a manually-applied message when the auto-apply effect later runs', async () => {
    const appliedMessageIdsRef = { current: new Set<string>() };

    // Save blocks until released — models the channel round-trip window.
    let releaseSave: () => void = () => {};
    const savePending = new Promise<void>(resolve => {
      releaseSave = resolve;
    });
    const mockSaveWorkflow = vi.fn(() => savePending);

    const makeActions = () => ({
      importWorkflow: mockImportWorkflow,
      startApplyingWorkflow: mockStartApplyingWorkflow,
      doneApplyingWorkflow: mockDoneApplyingWorkflow,
      startApplyingJobCode: mockStartApplyingJobCode,
      doneApplyingJobCode: mockDoneApplyingJobCode,
      updateJob: mockUpdateJob,
      saveWorkflow: () => mockSaveWorkflow(),
    });

    type Props = { connectionState: ConnectionState };

    // The assistant channel starts disconnected: the auto-apply effect
    // early-returns (connectionState !== 'connected'), but the manual "Apply"
    // button is NOT gated on connectionState, so a user can still apply. This
    // is the gap finding #1 called out — a manually-applied message that
    // nothing marks, which the effect then re-applies once the channel
    // reconnects.
    const { result, rerender } = renderHook(
      ({ connectionState }: Props) =>
        useAIWorkflowApplications({
          sessionId: 'session-1',
          page: 'workflow_template',
          currentSession: { messages: [userMessage, assistantMessage] },
          currentUserId: 'user-123',
          aiMode: createMockAIMode('workflow_template'),
          workflowActions: makeActions(),
          monacoRef: createMockMonacoRef(),
          jobs: [],
          canApplyChanges: true,
          connectionState,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          previewingMessageId: null,
          setApplyingMessageId: mockSetApplyingMessageId,
          isNewWorkflow: true,
          isSessionConnected: true,
          appliedMessageIdsRef,
          streamingApply: null,
          streamingApplyActions: mockStreamingApplyActions,
        }),
      { initialProps: { connectionState: 'connecting' as ConnectionState } }
    );

    // Manual "Apply" click while the assistant channel is still connecting.
    // The wrapper routes this through launchApply (not handleApplyWorkflow
    // raw), which marks the message synchronously via the in-flight guard.
    result.current.launchApply('msg-1', 'name: Test');
    await waitFor(() => expect(mockImportWorkflow).toHaveBeenCalledTimes(1));

    // Assistant channel reconnects while the manual apply's save is still
    // pending → auto-apply effect runs, but the message is already in-flight,
    // so it must NOT launch a second concurrent apply.
    rerender({ connectionState: 'connected' as ConnectionState });
    await new Promise(r => setTimeout(r, 20));
    expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
    expect(mockSaveWorkflow).toHaveBeenCalledTimes(1);

    // After the save settles the message is terminally marked, so further
    // effect re-runs stay no-ops.
    releaseSave();
    await waitFor(() =>
      expect(appliedMessageIdsRef.current.has('msg-1')).toBe(true)
    );
    rerender({ connectionState: 'connected' as ConnectionState });
    await new Promise(r => setTimeout(r, 20));
    expect(mockImportWorkflow).toHaveBeenCalledTimes(1);
    expect(mockSaveWorkflow).toHaveBeenCalledTimes(1);
  });
});
