import { useCallback, useEffect, useRef } from 'react';
import type { RefObject } from 'react';

import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import {
  parseWorkflowYAML,
  convertWorkflowSpecToState,
  applyJobCredsToWorkflowState,
  extractJobCredentials,
} from '../../yaml/util';
import type { MonacoHandle } from '../components/CollaborativeMonaco';
import { notifications } from '../lib/notifications';
import type { Job } from '../types';
import type {
  JobCodeContext,
  ConnectionState,
  Message,
  SessionType,
  WorkflowTemplateContext,
} from '../types/ai-assistant';

import flowEvents from '../components/diagram/react-flow-events';

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
  sessionType,
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
  sessionType: SessionType | null;
  currentSession: {
    messages: Message[];
    workflowTemplateContext?: WorkflowTemplateContext | null;
  } | null;
  currentUserId: string | undefined;
  aiMode: AIModeResult | null;
  workflowActions: {
    importWorkflow: (state: YAMLWorkflowState) => void;
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

  // Reset hasLoadedSessionRef when session changes
  useEffect(() => {
    hasLoadedSessionRef.current = false;
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

        importWorkflow(workflowStateWithCreds);
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
      if (!aiMode) return;

      const context = aiMode.context as WorkflowTemplateContext;
      const jobId = context.jobCtx?.job_id;

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
   * Apply job code to Y.Doc
   *
   * Updates the job body in Y.Doc, which syncs to all collaborators.
   * Clears any active diff preview and shows success notification.
   */
  const handleApplyJobCode = useCallback(
    async (code: string, messageId: string) => {
      if (!aiMode) return;
      const context = aiMode.context as WorkflowTemplateContext;
      const jobId = context.jobCtx?.job_id;

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

    if (sessionType !== 'workflow_template' || !messages.length) return;
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

    if (
      latestMessage?.code &&
      !appliedMessageIdsRef.current.has(latestMessage.id) &&
      !latestMessage.job_id
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
    sessionType,
    sessionId,
    connectionState,
    handleApplyWorkflow,
    canApplyChanges,
    currentUserId,
    appliedMessageIdsRef,
  ]);

  return {
    handleApplyWorkflow,
    handlePreviewJobCode,
    handleApplyJobCode,
  };
}
