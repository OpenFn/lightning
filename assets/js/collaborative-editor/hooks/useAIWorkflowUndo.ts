import { useCallback, useState } from 'react';

import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import {
  applyJobCredsToWorkflowState,
  convertWorkflowSpecToState,
  extractJobCredentials,
  parseWorkflowYAML,
} from '../../yaml/util';
import { notifications } from '../lib/notifications';
import type { Job } from '../types';

import { useActionLock } from './useActionLock';
import type { AppliedCanvas } from './useAppliedCanvas';

interface UseAIWorkflowUndoOptions {
  jobs: Job[];
  appliedCanvas: AppliedCanvas;
  workflowActions: {
    importWorkflow: (state: YAMLWorkflowState) => Promise<void>;
    startApplyingWorkflow: (messageId: string) => Promise<boolean>;
    doneApplyingWorkflow: (messageId: string) => Promise<void>;
  };
}

interface UseAIWorkflowUndoReturn {
  /** Reply whose changes are currently undone, so its control offers Redo */
  undoneMessageId: string | null;
  /** Undo a reply's changes, or redo them, confirming first if needed */
  requestUndoChanges: (messageId: string, yaml: string) => void;
  isConfirmOpen: boolean;
  confirmUndoChanges: () => void;
  cancelUndoChanges: () => void;
}

/**
 * Undo and redo for a global assistant reply's auto-applied changes.
 *
 * Restores one of the two YAMLs a turn is bounded by: the baseline the user
 * message carries, or the reply's own result. Both are full workflows, and
 * `importWorkflow` replaces the whole document, so restoring the baseline
 * also removes the steps the reply added. Ids round-trip, so restored steps
 * keep their identity.
 *
 * Deliberately not routed through `handleApplyWorkflow`: that writes the
 * bookkeeping the mid-turn auto-apply pipeline reads to decide what to skip.
 */
export function useAIWorkflowUndo({
  jobs,
  appliedCanvas,
  workflowActions: {
    importWorkflow,
    startApplyingWorkflow,
    doneApplyingWorkflow,
  },
}: UseAIWorkflowUndoOptions): UseAIWorkflowUndoReturn {
  const [undoneMessageId, setUndoneMessageId] = useState<string | null>(null);
  const [pending, setPending] = useState<{
    messageId: string;
    yaml: string;
  } | null>(null);

  const { run: restore } = useActionLock(
    async (messageId: string, yaml: string) => {
      const coordinated = await startApplyingWorkflow(messageId);

      try {
        // No id validation: this YAML is our own serializer's output, not the
        // model's.
        const state = convertWorkflowSpecToState(parseWorkflowYAML(yaml));

        await importWorkflow(
          applyJobCredsToWorkflowState(state, extractJobCredentials(jobs))
        );

        appliedCanvas.record();
        setUndoneMessageId(previous =>
          previous === messageId ? null : messageId
        );
      } catch (error) {
        console.error('[AI Assistant] Failed to restore workflow:', error);
        notifications.alert({
          title: 'Failed to restore workflow',
          description:
            error instanceof Error ? error.message : 'Invalid workflow YAML',
        });
      } finally {
        if (coordinated) await doneApplyingWorkflow(messageId);
      }
    }
  );

  const requestUndoChanges = useCallback(
    (messageId: string, yaml: string) => {
      if (appliedCanvas.hasChangedSinceApply()) {
        setPending({ messageId, yaml });
        return;
      }
      void restore(messageId, yaml);
    },
    [appliedCanvas, restore]
  );

  const confirmUndoChanges = useCallback(() => {
    if (pending) void restore(pending.messageId, pending.yaml);
    setPending(null);
  }, [pending, restore]);

  const cancelUndoChanges = useCallback(() => {
    setPending(null);
  }, []);

  return {
    undoneMessageId,
    requestUndoChanges,
    isConfirmOpen: pending !== null,
    confirmUndoChanges,
    cancelUndoChanges,
  };
}
