import type { RefObject } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

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
  WorkflowTemplateContext,
} from '../types/ai-assistant';

import type { AIModeResult } from './useAIMode';

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
  workflowActions,
  monacoRef,
  jobs,
  canApplyChanges,
  connectionState,
  setPreviewingMessageId,
  previewingMessageId,
  setApplyingMessageId,
  appliedMessageIdsRef,
}: {
  sessionId: string | null;
  page: SessionType | null;
  currentSession: {
    messages: Message[];
    workflowTemplateContext?: WorkflowTemplateContext | null;
  } | null;
  currentUserId: string | undefined;
  aiMode: AIModeResult | null;
  workflowActions: {
    importWorkflow: (state: YAMLWorkflowState) => Promise<void>;
    startApplyingWorkflow: (messageId: string) => Promise<boolean>;
    doneApplyingWorkflow: (messageId: string) => Promise<void>;
    startApplyingJobCode: (messageId: string) => Promise<boolean>;
    doneApplyingJobCode: (messageId: string) => Promise<void>;
    updateJob: (jobId: string, updates: { body: string }) => void;
  };
  monacoRef: RefObject<MonacoHandle> | null;
  jobs: Job[];
  canApplyChanges: boolean;
  connectionState: ConnectionState;
  setPreviewingMessageId: (id: string | null) => void;
  previewingMessageId: string | null;
  setApplyingMessageId: (id: string | null) => void;
  appliedMessageIdsRef: React.MutableRefObject<Set<string>>;
}) {
  const {
    importWorkflow,
    startApplyingWorkflow,
    doneApplyingWorkflow,
    startApplyingJobCode,
    doneApplyingJobCode,
    updateJob,
  } = workflowActions;

  /**
   * hasLoadedSessionRef tracks whether we've loaded the current session
   * to prevent auto-applying existing messages when opening a session.
   *
   * This ensures we only auto-apply NEW messages, not historical ones.
   */
  const hasLoadedSessionRef = useRef(false);

  /**
   * Tracks the last `${messageId}:${jobId}` previewed via handlePreviewGlobalStep
   * so re-entering a step re-shows its diff while re-rendering on the same step
   * does not. Kept separate from previewingMessageId, which the rest of the UI
   * reads as a plain message id.
   */
  const lastPreviewedGlobalStepRef = useRef<string | null>(null);

  /**
   * Global messages never auto-apply; they require an explicit Apply click.
   * This tracks which global messages the user has applied, so a message stays
   * "pending" (and keeps showing per-step diffs as you browse) until applied.
   * State (not a ref) so pendingGlobalMessage recomputes when it changes. Kept
   * separate from appliedMessageIdsRef, which dedups workflow-chat auto-apply.
   */
  const [appliedGlobalMessageIds, setAppliedGlobalMessageIds] = useState<
    Set<string>
  >(() => new Set());

  // Reset session-scoped tracking when the session changes. Only clear the
  // applied-set on an actual session change (not initial mount) so we don't
  // trigger a spurious re-render that would re-run the auto-apply effect.
  const prevSessionIdRef = useRef(sessionId);
  useEffect(() => {
    hasLoadedSessionRef.current = false;
    lastPreviewedGlobalStepRef.current = null;
    if (prevSessionIdRef.current !== sessionId) {
      prevSessionIdRef.current = sessionId;
      setAppliedGlobalMessageIds(new Set());
    }
  }, [sessionId]);

  /**
   * Apply workflow YAML to the canvas
   *
   * Parses YAML, validates IDs, preserves credentials, and imports
   * the workflow state into Y.Doc. Coordinates with collaborators
   * to show "APPLYING..." state.
   */
  const handleApplyWorkflow = useCallback(
    async (yaml: string, messageId: string) => {
      if (!aiMode) return;
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
        return;
      }
      setApplyingMessageId(messageId);

      // Signal to all collaborators that we're starting to apply
      // Returns false if coordination failed (other users won't be notified)
      const coordinated = await startApplyingWorkflow(messageId);

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

        // Mark a global message applied so it stops being "pending" and no
        // longer re-shows per-step diffs as the user navigates.
        if (isGlobal && messageId !== '__streaming__') {
          setAppliedGlobalMessageIds(prev => new Set(prev).add(messageId));
        }
      } catch (error) {
        console.error('[AI Assistant] Failed to apply workflow:', error);

        notifications.alert({
          title: 'Failed to apply workflow',
          description:
            error instanceof Error ? error.message : 'Invalid workflow YAML',
        });
      } finally {
        setApplyingMessageId(null);
        // Only signal completion if we successfully coordinated
        // (otherwise other users weren't notified of the start)
        if (coordinated) {
          await doneApplyingWorkflow(messageId);
          flowEvents.dispatch('fit-view');
        }
      }
    },
    [
      aiMode,
      currentSession,
      importWorkflow,
      startApplyingWorkflow,
      doneApplyingWorkflow,
      jobs,
      setApplyingMessageId,
    ]
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

      // Dedup is keyed on message + open step so navigating to a different
      // step re-fires the diff while re-rendering on the same step does not.
      // (previewingMessageId stays the plain message id for the rest of the UI.)
      const stepKey = `${messageId}:${jobId}`;
      if (lastPreviewedGlobalStepRef.current === stepKey) return;
      if (previewingMessageId === '__streaming__') {
        setPreviewingMessageId(messageId);
        lastPreviewedGlobalStepRef.current = stepKey;
        return;
      }

      const currentBody = jobs.find(j => j.id === jobId)?.body ?? '';

      let newBody: string | undefined;
      try {
        const spec = parseWorkflowYAML(yaml);
        // state.jobs is an array; ids from the YAML are preserved
        const state = convertWorkflowSpecToState(spec);
        newBody = state.jobs.find(j => j.id === jobId)?.body;
      } catch {
        return; // invalid YAML -> no diff
      }

      if (newBody === undefined || newBody === currentBody) {
        // open step unchanged -> ensure no stale diff is shown
        if (previewingMessageId) monacoRef?.current?.clearDiff();
        lastPreviewedGlobalStepRef.current = stepKey;
        return;
      }

      const monaco = monacoRef?.current;
      if (previewingMessageId && monaco) monaco.clearDiff();
      if (monaco) {
        monaco.showDiff(currentBody, newBody);
        setPreviewingMessageId(messageId);
        lastPreviewedGlobalStepRef.current = stepKey;
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
      return;
    }

    const latestMessage = messagesWithCode.pop();

    // Global messages never auto-apply — they require an explicit Apply click
    // so the user can review each step's diff first.
    if (latestMessage?.from_global) return;

    if (
      latestMessage?.code &&
      !appliedMessageIdsRef.current.has(latestMessage.id)
    ) {
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

      appliedMessageIdsRef.current.add(latestMessage.id);

      if (isCurrentUserAuthor) {
        void handleApplyWorkflow(latestMessage.code, latestMessage.id);
      }
    }
  }, [
    currentSession,
    page,
    sessionId,
    connectionState,
    handleApplyWorkflow,
    canApplyChanges,
    currentUserId,
    appliedMessageIdsRef,
  ]);

  /**
   * Clears the per-step preview dedup so the next handlePreviewGlobalStep call
   * re-shows even for the same step. The editor remount on step (re)entry
   * disposes the prior diff, so re-entry must be allowed to re-show it.
   */
  const resetGlobalStepPreviewDedup = useCallback(() => {
    lastPreviewedGlobalStepRef.current = null;
  }, []);

  /**
   * The latest "pending" global message: a successful assistant message from
   * the global assistant that carries a full workflow YAML and has not been
   * explicitly applied yet. While one exists, opening a step re-shows that
   * step's diff. Returns null otherwise.
   */
  const pendingGlobalMessage = useMemo(() => {
    const messages = currentSession?.messages;
    if (!messages) return null;
    for (let i = messages.length - 1; i >= 0; i--) {
      const m = messages[i];
      if (
        m &&
        m.role === 'assistant' &&
        m.from_global &&
        m.code &&
        m.status === 'success' &&
        !appliedGlobalMessageIds.has(m.id)
      ) {
        return m;
      }
    }
    return null;
  }, [currentSession, appliedGlobalMessageIds]);

  return {
    handleApplyWorkflow,
    handlePreviewJobCode,
    handlePreviewGlobalStep,
    handleApplyJobCode,
    pendingGlobalMessage,
    resetGlobalStepPreviewDedup,
  };
}
