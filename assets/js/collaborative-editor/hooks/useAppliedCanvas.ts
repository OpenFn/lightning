import { useCallback } from 'react';

import { serializeCanvasForComparison } from '../utils/workflowSerialization';

import { useAIStore } from './useAIAssistant';
import { useWorkflowStoreContext } from './useWorkflow';

export interface AppliedCanvas {
  /** Record the canvas as it stands, after an assistant import */
  record: () => void;
  /**
   * Whether the workflow has been edited since the last recorded import.
   * True when nothing was recorded, so a session that has lost its record
   * (a reload) errs towards confirming.
   */
  hasChangedSinceApply: () => boolean;
}

/**
 * Tracks the canvas as the assistant last left it, so undo can tell whether
 * anything has been edited since and only confirm when it has.
 *
 * Reads the workflow store directly rather than taking state as an argument:
 * callers record in the tick after `await importWorkflow`, when a render
 * closure still holds the pre-import jobs.
 */
export function useAppliedCanvas(): AppliedCanvas {
  const aiStore = useAIStore();
  const workflowStore = useWorkflowStoreContext();

  // An empty workflow serializes to nothing, which is a real state to
  // record, not an absent record. Keeping them distinct matters because
  // `null` is what says "never recorded": conflating them made Redo always
  // confirm after undoing a reply that created a workflow's first steps.
  const serialize = useCallback(
    () => serializeCanvasForComparison(workflowStore.getSnapshot()) ?? '',
    [workflowStore]
  );

  const record = useCallback(() => {
    aiStore._setAppliedCanvasYaml(serialize());
  }, [aiStore, serialize]);

  const hasChangedSinceApply = useCallback(() => {
    const applied = aiStore.getSnapshot().appliedCanvasYaml;
    return applied === null || applied !== serialize();
  }, [aiStore, serialize]);

  return { record, hasChangedSinceApply };
}
