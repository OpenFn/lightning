import type { RefObject } from 'react';
import { useCallback, useEffect, useRef } from 'react';

import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import {
  applyJobCredsToWorkflowState,
  convertWorkflowSpecToState,
  extractJobCredentials,
  parseWorkflowYAML,
} from '../../yaml/util';
import type { MonacoHandle } from '../components/CollaborativeMonaco';
import flowEvents from '../components/diagram/react-flow-events';
import { notifications } from '../lib/notifications';
import type { Job } from '../types';
import type {
  ConnectionState,
  JobCodeContext,
  Message,
  SessionType,
  StreamingApplyState,
  WorkflowTemplateContext,
} from '../types/ai-assistant';

import type { AIModeResult } from './useAIMode';
import { NOT_CONNECTED_ALERT, STILL_CONNECTING_ALERT } from './useWorkflow';
import type { SaveWorkflowOptions } from './useWorkflow';

/**
 * Helper function to validate workflow IDs before applying
 *
 * Ensures that all IDs in the workflow spec are strings or null,
 * not objects. This prevents YAML parsing issues where the AI
 * might incorrectly generate object IDs.
 */
function validateIds(spec: Record<string, unknown>): void {
  if (spec['jobs']) {
    for (const [jobKey, job] of Object.entries(spec['jobs'] as object)) {
      const jobItem = job as Record<string, unknown>;
      if (
        jobItem['id'] &&
        typeof jobItem['id'] === 'object' &&
        jobItem['id'] !== null
      ) {
        throw new Error(
          `Invalid ID format for job "${jobKey}". IDs must be strings or null, not objects. ` +
            `Please ask the AI to regenerate the workflow with proper ID format.`
        );
      }
    }
  }
  if (spec['triggers']) {
    for (const [triggerKey, trigger] of Object.entries(
      spec['triggers'] as object
    )) {
      const triggerItem = trigger as Record<string, unknown>;
      if (
        triggerItem['id'] &&
        typeof triggerItem['id'] === 'object' &&
        triggerItem['id'] !== null
      ) {
        throw new Error(
          `Invalid ID format for trigger "${triggerKey}". IDs must be strings or null, not objects. ` +
            `Please ask the AI to regenerate the workflow with proper ID format.`
        );
      }
    }
  }
  if (spec['edges']) {
    for (const [edgeKey, edge] of Object.entries(spec['edges'] as object)) {
      const edgeItem = edge as Record<string, unknown>;
      if (
        edgeItem['id'] &&
        typeof edgeItem['id'] === 'object' &&
        edgeItem['id'] !== null
      ) {
        throw new Error(
          `Invalid ID format for edge "${edgeKey}". IDs must be strings or null, not objects. ` +
            `Please ask the AI to regenerate the workflow with proper ID format.`
        );
      }
    }
  }
}

/**
 * Hook to manage workflow and job code application from AI Assistant
 *
 * Handles:
 * - Manual application of workflow YAML via handleApplyWorkflow
 * - Manual application of job code via handleApplyJobCode
 * - Preview of job code diffs in Monaco via handlePreviewJobCode
 * - Auto-application of workflow YAML for message authors
 * - Auto-preview of job code for message authors (via useAutoPreview)
 *
 * Auto-application behavior:
 * - Only applies for the user who authored the triggering message
 * - Prevents duplicate applies in collaborative sessions
 * - Tracks applied messages to avoid re-applying on session load
 * - Only applies the latest message with code (skips intermediates)
 * - Skips the final message's re-import when streaming already applied
 *   the same YAML (streamingApply record in AIAssistantStore)
 *
 * Accepts raw dependencies (not callbacks) and creates callbacks internally
 * for cleaner usage and better memoization control.
 */
export function useAIWorkflowApplications({
  sessionId,
  page,
  currentSession,
  currentUserId,
  aiMode,
  isNewWorkflow,
  isSessionConnected,
  isSessionConnecting = false,
  onValidationError,
  workflowActions,
  monacoRef,
  jobs,
  canApplyChanges,
  connectionState,
  setPreviewingMessageId,
  previewingMessageId,
  setApplyingMessageId,
  appliedMessageIdsRef,
  streamingApply,
  streamingApplyActions,
}: {
  sessionId: string | null;
  page: SessionType | null;
  currentSession: {
    messages: Message[];
    workflowTemplateContext?: WorkflowTemplateContext | null;
  } | null;
  currentUserId: string | undefined;
  aiMode: AIModeResult | null;
  isNewWorkflow: boolean;
  /**
   * Workflow-session socket connectivity (distinct from `connectionState`,
   * which tracks the separate assistant-conversation channel).
   */
  isSessionConnected: boolean;
  /**
   * True only during the initial workflow-session channel-join window —
   * distinct from a genuine disconnect. Lets the offline gate tell the user
   * "still connecting" instead of a misleading "not connected". Optional
   * (defaults to false) so existing test fakes that only set
   * `isSessionConnected` keep compiling.
   */
  isSessionConnecting?: boolean;
  onValidationError?: (message: string) => void;
  workflowActions: {
    importWorkflow: (state: YAMLWorkflowState) => Promise<void>;
    startApplyingWorkflow: (messageId: string) => Promise<boolean>;
    doneApplyingWorkflow: (messageId: string) => Promise<void>;
    startApplyingJobCode: (messageId: string) => Promise<boolean>;
    doneApplyingJobCode: (messageId: string) => Promise<void>;
    updateJob: (jobId: string, updates: { body: string }) => void;
    saveWorkflow: (options?: SaveWorkflowOptions) => Promise<unknown>;
  };
  monacoRef: RefObject<MonacoHandle> | null;
  jobs: Job[];
  canApplyChanges: boolean;
  connectionState: ConnectionState;
  setPreviewingMessageId: (id: string | null) => void;
  previewingMessageId: string | null;
  setApplyingMessageId: (id: string | null) => void;
  appliedMessageIdsRef: React.MutableRefObject<Set<string>>;
  /**
   * Pending streaming apply record from AIAssistantStore: the YAML already
   * imported to the canvas during streaming (see StreamingApplyState).
   * The auto-apply effect compares the final message's code against it to
   * skip the duplicate import that would dirty the Y.Doc.
   */
  streamingApply: StreamingApplyState | null;
  streamingApplyActions: {
    set: (yaml: string) => void;
    setSaveFailed: (saveFailed: boolean) => void;
    clear: () => void;
  };
}) {
  const {
    importWorkflow,
    startApplyingWorkflow,
    doneApplyingWorkflow,
    startApplyingJobCode,
    doneApplyingJobCode,
    updateJob,
    saveWorkflow,
  } = workflowActions;

  /**
   * hasLoadedSessionRef tracks whether we've loaded the current session
   * to prevent auto-applying existing messages when opening a session.
   *
   * This ensures we only auto-apply NEW messages, not historical ones.
   */
  const hasLoadedSessionRef = useRef(false);

  /**
   * Message ids whose auto-apply is currently running. Added SYNCHRONOUSLY
   * before the async apply starts and removed when it settles. This is the
   * re-entrancy guard: the auto-apply effect below re-runs on nearly every
   * render (handleApplyWorkflow's identity changes each render because
   * saveWorkflow from useWorkflowActions is rebuilt every render), so without
   * a synchronous marker a re-run during an in-flight apply would launch a
   * second concurrent apply of the same message.
   */
  const inFlightApplyRef = useRef<Set<string>>(new Set());

  /**
   * A single message that was blocked while offline (handleApplyWorkflow
   * returned 'gated') and should be retried once the session reconnects.
   * The auto-apply effect deliberately ignores this message on its normal
   * re-runs; only the reconnect effect below replays it. That keeps a blocked
   * apply from re-alerting on every render while still offline, yet still
   * recovers automatically on reconnect.
   */
  const pendingReconnectApplyRef = useRef<{ id: string; code: string } | null>(
    null
  );

  // Reset per-session bookkeeping when the session changes
  useEffect(() => {
    hasLoadedSessionRef.current = false;
    inFlightApplyRef.current.clear();
    pendingReconnectApplyRef.current = null;
  }, [sessionId]);

  /**
   * Save a new workflow after an AI apply. Failure feedback (persistent
   * Retry toast) is owned by the shared save handler in useWorkflow.tsx.
   * Records the outcome on the pending streaming apply so the final
   * new_message knows whether a save is still owed (no-op in the store
   * when the apply didn't come from streaming).
   */
  const saveNewWorkflow = useCallback(async (): Promise<boolean> => {
    try {
      await saveWorkflow({ notify: 'error-only' });
      streamingApplyActions.setSaveFailed(false);
      return true;
    } catch (saveError) {
      // Shared save handler (useWorkflow.tsx) has already shown a persistent
      // Retry toast — its Retry button calls the shared wrappedSaveWorkflow
      // directly, not this function, so no local retry plumbing is needed.
      streamingApplyActions.setSaveFailed(true);
      console.error('[AI Assistant] Failed to save workflow:', saveError);
      return false;
    }
  }, [saveWorkflow, streamingApplyActions]);

  /**
   * Apply workflow YAML to the canvas
   *
   * Parses YAML, validates IDs, preserves credentials, and imports
   * the workflow state into Y.Doc. Coordinates with collaborators
   * to show "APPLYING..." state.
   */
  const handleApplyWorkflow = useCallback(
    async (
      yaml: string,
      messageId: string
    ): Promise<'applied' | 'gated' | 'failed'> => {
      if (!aiMode) return 'failed';
      // Global messages carry a full workflow YAML and may be applied even
      // while a job is open (job_code mode). Non-global workflow chat keeps
      // the workflow_template-only guard so its Apply stays a no-op when a
      // job is open.
      const isGlobal = !!currentSession?.messages.find(m => m.id === messageId)
        ?.from_global;
      if (aiMode.page !== 'workflow_template' && !isGlobal) {
        console.error(
          '[AI Assistant] Cannot apply workflow - not in workflow mode',
          {
            aiMode,
          }
        );
        return 'failed';
      }

      // Creation flow: an import that can't be followed by a save would
      // orphan the canvas. Fail fast instead of waiting out a 10s push
      // timeout. (Existing workflows are fine: offline imports are normal
      // unsaved collaborative edits that sync on reconnect.) Callers that
      // track "have we handled this message" (the auto-apply effect below)
      // should treat 'gated' as not-yet-resolved and retry once connected.
      if (isNewWorkflow && !isSessionConnected) {
        notifications.alert(
          isSessionConnecting ? STILL_CONNECTING_ALERT : NOT_CONNECTED_ALERT
        );
        return 'gated';
      }

      // A global message applied while a step is open leaves an active diff in
      // the open step. Clear it so the editor returns to an editable state.
      const monaco = monacoRef?.current;
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
        setPreviewingMessageId(null);
      }

      setApplyingMessageId(messageId);

      // Any non-streaming apply supersedes a pending streaming apply — the
      // canvas will no longer hold the streamed YAML after this import.
      if (messageId !== '__streaming__') {
        streamingApplyActions.clear();
      }

      // Signal to all collaborators that we're starting to apply
      // Returns false if coordination failed (other users won't be notified)
      const coordinated = await startApplyingWorkflow(messageId);

      // Track outcomes independently: applySucceeded covers parse/validate/import;
      // saveSucceeded covers the subsequent save for new workflows.
      let applySucceeded = false;
      let saveSucceeded = true;
      try {
        const workflowSpec = parseWorkflowYAML(yaml);
        validateIds(workflowSpec);

        // IDs are already in the YAML from AI (sent with IDs, like legacy editor)
        const workflowState = convertWorkflowSpecToState(workflowSpec);

        const workflowStateWithCreds = applyJobCredsToWorkflowState(
          workflowState,
          extractJobCredentials(jobs)
        );

        await importWorkflow(workflowStateWithCreds);
        applySucceeded = true;

        if (messageId === '__streaming__') {
          // Record the applied YAML so the auto-apply effect can skip the
          // duplicate import when the final new_message carries the same YAML.
          // Set only after a successful import, so failed applies never
          // leave a stale record behind.
          streamingApplyActions.set(yaml);
        }

        if (isNewWorkflow) {
          saveSucceeded = await saveNewWorkflow();
        }
      } catch (error) {
        console.error('[AI Assistant] Failed to apply workflow:', error);

        const errorMessage =
          error instanceof Error ? error.message : 'Invalid workflow YAML';

        if (isNewWorkflow && onValidationError) {
          onValidationError(errorMessage);
        } else {
          notifications.alert({
            title: 'Failed to apply workflow',
            description: errorMessage,
          });
        }
      } finally {
        setApplyingMessageId(null);
        // Always signal completion when coordinated so collaborators aren't
        // left stuck in "APPLYING..." state, even if apply itself failed.
        if (coordinated) {
          await doneApplyingWorkflow(messageId);
          // Only fit-view when the canvas was actually updated and persisted.
          // Skip when importWorkflow failed (applySucceeded false) or when
          // save failed so we don't zoom in on an unpersisted workflow. Also
          // skip for new workflows: the shared save handler
          // (useWorkflow.tsx's handleSaveSuccess) already dispatches
          // fit-view when a brand-new workflow's first save succeeds, so
          // dispatching again here would just re-trigger the same
          // in-progress animation.
          if (applySucceeded && saveSucceeded && !isNewWorkflow) {
            flowEvents.dispatch('fit-view');
          }
        }
      }

      return applySucceeded && saveSucceeded ? 'applied' : 'failed';
    },
    [
      aiMode,
      currentSession,
      importWorkflow,
      startApplyingWorkflow,
      doneApplyingWorkflow,
      jobs,
      setApplyingMessageId,
      isNewWorkflow,
      isSessionConnected,
      isSessionConnecting,
      onValidationError,
      saveNewWorkflow,
      streamingApplyActions,
      monacoRef,
      previewingMessageId,
      setPreviewingMessageId,
    ]
  );

  /**
   * Launch an apply for a message with a synchronous re-entrancy guard.
   *
   * This is the single entry point for BOTH the auto-apply effect and the
   * manual "Apply" button (via the returned `launchApply`). Routing the manual
   * path through here — instead of calling `handleApplyWorkflow` raw — means a
   * manual apply also marks the message, so the auto-apply effect won't later
   * re-fire a duplicate import/save for a message the user already applied by
   * hand (e.g. applied manually while the assistant channel was briefly
   * disconnected, then reconnects).
   *
   * The guard (inFlightApplyRef) is set before the first `await`, so a re-run
   * of the auto-apply effect while this apply is still in flight is a no-op
   * instead of a second concurrent apply. On settle:
   * - 'gated' (blocked offline): park the message for a reconnect retry.
   * - otherwise ('applied' or 'failed'): record it as terminally handled. A
   *   'failed' import is intentionally not retried automatically (avoids a
   *   re-apply loop); the user can re-apply via the still-enabled manual button
   *   and save failures recover via the shared Retry toast.
   *
   * The '__streaming__' pseudo-message is deliberately NOT routed through here
   * (it calls handleApplyWorkflow directly) so it never lands in
   * appliedMessageIdsRef and can be superseded by the final new_message.
   */
  const launchApply = useCallback(
    (messageId: string, code: string) => {
      if (inFlightApplyRef.current.has(messageId)) return;
      inFlightApplyRef.current.add(messageId);
      void (async () => {
        try {
          const outcome = await handleApplyWorkflow(code, messageId);
          if (outcome === 'gated') {
            pendingReconnectApplyRef.current = { id: messageId, code };
          } else {
            appliedMessageIdsRef.current.add(messageId);
          }
        } finally {
          inFlightApplyRef.current.delete(messageId);
        }
      })();
    },
    [handleApplyWorkflow, appliedMessageIdsRef]
  );

  /**
   * Preview job code diff in Monaco editor
   *
   * Shows a side-by-side diff of current job code vs AI-generated code.
   * Only works in job_code mode with a valid job_id.
   */
  const handlePreviewJobCode = useCallback(
    (code: string, messageId: string) => {
      if (!aiMode || aiMode.page !== 'job_code') {
        console.error('[AI Assistant] Cannot preview - not in job mode', {
          aiMode,
        });
        return;
      }

      const context = aiMode.context as JobCodeContext;
      const jobId = context.job_id;

      if (!jobId) {
        console.error('[AI Assistant] Cannot preview - no job ID', { context });
        notifications.alert({
          title: 'Cannot preview code',
          description: 'No job selected',
        });
        return;
      }

      // If already previewing this message, do nothing
      if (previewingMessageId === messageId) {
        return;
      }

      // If we're previewing from streaming and the real message arrives,
      // just update the message ID without re-rendering the diff
      if (previewingMessageId === '__streaming__') {
        setPreviewingMessageId(messageId);
        return;
      }

      const monaco = monacoRef?.current;

      // Clear any existing diff first
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
      }

      // Get current job code from Y.Doc
      const currentJob = jobs.find(j => j.id === jobId);
      const currentCode = currentJob?.body ?? '';

      // Show diff in Monaco
      if (monaco) {
        monaco.showDiff(currentCode, code);
        setPreviewingMessageId(messageId);
      } else {
        console.error('[AI Assistant] ❌ Monaco ref not available', {
          hasMonacoRef: !!monacoRef,
          hasMonacoRefCurrent: !!monacoRef?.current,
        });
        notifications.alert({
          title: 'Preview unavailable',
          description: 'Editor not ready. Please try again in a moment.',
        });
      }
    },
    [aiMode, jobs, previewingMessageId, monacoRef, setPreviewingMessageId]
  );

  /**
   * Preview the open job's diff from a global full-workflow YAML message
   *
   * Mirrors handlePreviewJobCode, but extracts the open job's body from the
   * workflow YAML (global messages carry the whole workflow in `code`).
   * Shows a diff only when the open step's body actually changed; clears any
   * stale diff otherwise.
   */
  const handlePreviewGlobalStep = useCallback(
    (yaml: string, messageId: string) => {
      if (!aiMode || aiMode.page !== 'job_code') return; // only when a step is open
      const jobId = (aiMode.context as JobCodeContext).job_id;
      if (!jobId) return;

      // Same dedup guards as handlePreviewJobCode
      if (previewingMessageId === messageId) return;
      if (previewingMessageId === '__streaming__') {
        setPreviewingMessageId(messageId);
        return;
      }

      const currentJob = jobs.find(j => j.id === jobId);
      const currentBody = currentJob?.body ?? '';

      let newBody: string | undefined;
      try {
        const spec = parseWorkflowYAML(yaml);
        // ids from the YAML are preserved, so we match the open step by id
        const state = convertWorkflowSpecToState(spec);
        newBody = state.jobs.find(j => j.id === jobId)?.body;
      } catch (error) {
        console.error(
          '[AI Assistant] Failed to parse global workflow YAML:',
          error
        );
        notifications.alert({
          title: 'Could not preview step',
          description:
            error instanceof Error
              ? error.message
              : 'The AI server returned invalid workflow YAML.',
        });
        return;
      }

      if (newBody === undefined) {
        // Open step's id wasn't in the YAML, so the server likely didn't preserve it
        console.warn(
          '[AI Assistant] Open step not found in global workflow YAML',
          { jobId }
        );
        notifications.warning({
          title: 'Could not preview this step',
          description: `Step "${
            currentJob?.name ?? jobId
          }" was not found in the AI response (id: ${jobId}). Its ID may not have been preserved by the server.`,
        });
        if (previewingMessageId) monacoRef?.current?.clearDiff();
        return;
      }

      if (newBody === currentBody) {
        // open step genuinely unchanged -> ensure no stale diff is shown
        if (previewingMessageId) monacoRef?.current?.clearDiff();
        return;
      }

      const monaco = monacoRef?.current;
      if (previewingMessageId && monaco) monaco.clearDiff();
      if (monaco) {
        monaco.showDiff(currentBody, newBody);
        setPreviewingMessageId(messageId);
      }
    },
    [aiMode, jobs, previewingMessageId, monacoRef, setPreviewingMessageId]
  );

  /**
   * Apply job code to Y.Doc
   *
   * Updates the job body in Y.Doc, which syncs to all collaborators.
   * Clears any active diff preview and shows success notification.
   */
  const handleApplyJobCode = useCallback(
    async (code: string, messageId: string) => {
      if (!aiMode || aiMode.page !== 'job_code') {
        console.error('[AI Assistant] Cannot apply job code - not in job mode');
        return;
      }

      const context = aiMode.context as JobCodeContext;
      const jobId = context.job_id;

      if (!jobId) {
        notifications.alert({
          title: 'Cannot apply code',
          description: 'No job selected',
        });
        return;
      }

      const monaco = monacoRef?.current;
      // Clear diff if showing
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
        setPreviewingMessageId(null);
      }

      setApplyingMessageId(messageId);

      // Coordinate with collaborators (non-blocking)
      const coordinated = await startApplyingJobCode(messageId);

      try {
        // Update job body in Y.Doc (syncs to all collaborators)
        updateJob(jobId, { body: code });

        notifications.success({
          title: 'Code applied',
          description: 'Job code has been updated',
        });
      } catch (error) {
        console.error('[AI Assistant] Failed to apply job code:', error);

        notifications.alert({
          title: 'Failed to apply code',
          description:
            error instanceof Error ? error.message : 'Unknown error occurred',
        });
      } finally {
        setApplyingMessageId(null);
        // Only signal completion if we successfully coordinated
        if (coordinated) {
          await doneApplyingJobCode(messageId);
        }
      }
    },
    [
      aiMode,
      updateJob,
      startApplyingJobCode,
      doneApplyingJobCode,
      previewingMessageId,
      monacoRef,
      setPreviewingMessageId,
      setApplyingMessageId,
    ]
  );

  /**
   * Auto-apply workflow YAML when AI responds
   *
   * This effect watches for new messages in workflow_template mode and
   * automatically applies the latest workflow YAML to the canvas. This
   * creates a seamless experience where users see their workflow update
   * in real-time as the AI generates it.
   *
   * Conditions for auto-apply:
   * - Session type is 'workflow_template' (not job_code)
   * - There are messages in the conversation
   * - Connection is established (prevents applying during reconnection)
   * - The message has code and hasn't been applied yet (tracked in appliedMessageIdsRef)
   * - The current user is the one who sent the message that triggered the AI response
   *   (prevents duplicate applies in collaborative sessions where multiple users view the same chat)
   *
   * Note: We only apply the LATEST message with code to avoid applying intermediate
   * drafts if the AI sends multiple responses quickly.
   */
  useEffect(() => {
    if (!currentSession) return;
    const messages = currentSession.messages;

    if (page !== 'workflow_template' || !messages.length) return;
    if (connectionState !== 'connected') return;
    // Don't auto-apply when readonly (except for new workflow creation)
    if (!canApplyChanges) return;

    const messagesWithCode = messages.filter(
      msg => msg.role === 'assistant' && msg.code && msg.status === 'success'
    );

    // On initial session load, mark all existing messages as already applied
    // to prevent re-applying workflows when opening existing sessions
    if (!hasLoadedSessionRef.current) {
      hasLoadedSessionRef.current = true;
      messagesWithCode.forEach(msg => {
        appliedMessageIdsRef.current.add(msg.id);
      });
      // Streaming may have applied before the session finished loading; the
      // final message was seeded above, so the record will never be consumed.
      // Drop it.
      streamingApplyActions.clear();
      return;
    }

    const latestMessage = messagesWithCode.pop();

    if (
      latestMessage?.code &&
      !appliedMessageIdsRef.current.has(latestMessage.id) &&
      !inFlightApplyRef.current.has(latestMessage.id) &&
      pendingReconnectApplyRef.current?.id !== latestMessage.id
    ) {
      // Streaming already imported this exact YAML to the canvas — skip the
      // re-import, which would only dirty the Y.Doc (unsaved red dot). If
      // the streaming apply's save is still owed, settle it now. When the
      // YAML differs (streaming apply failed, or the final response changed),
      // fall through and apply normally.
      if (streamingApply && streamingApply.yaml === latestMessage.code) {
        appliedMessageIdsRef.current.add(latestMessage.id);
        streamingApplyActions.clear();
        if (streamingApply.saveFailed) {
          void saveNewWorkflow();
        }
        return;
      }

      // Find the user message that triggered this AI response
      // Look for the most recent user message before this assistant message
      const latestMessageIndex = messages.findIndex(
        m => m.id === latestMessage.id
      );
      const precedingUserMessage = messages
        .slice(0, latestMessageIndex)
        .reverse()
        .find(m => m.role === 'user');

      // Only auto-apply if the current user sent the triggering message
      // This prevents duplicate applies in collaborative sessions where
      // multiple users view the same chat and would otherwise all auto-apply
      const isCurrentUserAuthor =
        precedingUserMessage?.user_id === currentUserId ||
        // Fallback: if no user_id on message (legacy), allow apply
        !precedingUserMessage?.user_id;

      if (isCurrentUserAuthor) {
        // Guarded launch: the synchronous inFlightApplyRef marker prevents a
        // re-run of this effect from starting a second concurrent apply. A
        // 'gated' (offline) result parks the message for the reconnect effect
        // rather than dropping it.
        launchApply(latestMessage.id, latestMessage.code);
      } else {
        appliedMessageIdsRef.current.add(latestMessage.id);
      }
    }
  }, [
    currentSession,
    page,
    sessionId,
    connectionState,
    launchApply,
    canApplyChanges,
    currentUserId,
    appliedMessageIdsRef,
    streamingApply,
    streamingApplyActions,
    saveNewWorkflow,
  ]);

  // Retry a message that was blocked offline, once the session reconnects.
  // This is the ONLY retry path for a gated apply — the auto-apply effect
  // ignores the parked message so it doesn't re-attempt (and re-alert) on
  // every render while still offline.
  useEffect(() => {
    if (!isSessionConnected) return;
    const pending = pendingReconnectApplyRef.current;
    if (!pending) return;
    // Clear before launching so a concurrent effect run can't replay it twice.
    pendingReconnectApplyRef.current = null;
    launchApply(pending.id, pending.code);
  }, [isSessionConnected, launchApply]);

  return {
    handleApplyWorkflow,
    /**
     * Guarded workflow-apply launcher for the manual "Apply" button. Prefer
     * this over `handleApplyWorkflow` for user-message applies: it marks the
     * message (in-flight + applied/parked) so the auto-apply effect can't later
     * re-fire a duplicate apply for a manually-applied message. Signature is
     * (messageId, yaml) — note the argument order differs from
     * handleApplyWorkflow's (yaml, messageId).
     */
    launchApply,
    handlePreviewJobCode,
    handlePreviewGlobalStep,
    handleApplyJobCode,
  };
}
