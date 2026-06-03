import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { TriggerSchema } from '#/collaborative-editor/types/trigger';

import { useWorkflowActions } from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';

/**
 * Options for {@link useTriggerDraft}.
 */
export interface UseTriggerDraftOptions {
  /** Auth-method ids currently associated with the trigger (the committed set). */
  initialAuthMethodIds: string[];
  /**
   * Persists a new auth-method id set. Called by `commit()` only when the draft
   * id set differs from `initialAuthMethodIds`.
   */
  commitAuthMethods: (ids: string[]) => Promise<void>;
}

/**
 * Return shape of the {@link useTriggerDraft} hook.
 */
export interface UseTriggerDraftResult {
  /** The local, uncommitted trigger draft. */
  draft: Workflow.Trigger;
  /** Shallow-merges `updates` into the draft. Never touches the Y.Doc. */
  mergeDraft: (updates: Partial<Workflow.Trigger>) => void;
  /** The local, uncommitted set of webhook auth-method ids. */
  draftAuthMethodIds: string[];
  /** Replaces the draft auth-method id set. Never touches the channel. */
  setDraftAuthMethodIds: (ids: string[]) => void;
  /**
   * True when the draft differs from the source trigger OR the draft auth-method
   * id set differs from `initialAuthMethodIds`.
   */
  isDirty: boolean;
  /** Re-seeds the draft and auth-method ids from the current source (Cancel). */
  reset: () => void;
  /** Validation error from the draft (null when valid). */
  validationError: string | null;
  /**
   * Validates the draft and, if valid, commits it in one shot:
   * `updateTrigger(trigger.id, draft)` plus `commitAuthMethods` (only when the
   * auth-method id set changed). Returns `{ ok: false }` without persisting when
   * the draft is invalid.
   */
  commit: () => Promise<{ ok: boolean }>;
}

/** Order-independent comparison of two id sets. */
function sameIdSet(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const setB = new Set(b);
  return a.every(id => setB.has(id));
}

/**
 * Draft/commit buffer for editing a trigger in the wizard flow.
 *
 * The wizard must hold edits in a local draft and only write them to the Y.Doc
 * on Finish (Cancel discards). This hook owns that draft:
 *
 * - `mergeDraft` / `setDraftAuthMethodIds` mutate ONLY local state.
 * - `commit()` is the SOLE place that calls `updateTrigger` / `commitAuthMethods`.
 *
 * @param trigger The source trigger (committed state).
 * @param options Initial auth-method ids and the channel commit function.
 */
export function useTriggerDraft(
  trigger: Workflow.Trigger,
  options: UseTriggerDraftOptions
): UseTriggerDraftResult {
  const { initialAuthMethodIds, commitAuthMethods } = options;
  const { updateTrigger } = useWorkflowActions();

  const [draft, setDraft] = useState<Workflow.Trigger>(() => trigger);
  const [draftAuthMethodIds, setDraftAuthMethodIdsState] = useState<string[]>(
    () => initialAuthMethodIds
  );

  // Auth methods load asynchronously, so `initialAuthMethodIds` is often `[]`
  // at mount and only later resolves to the real server set. Until the user
  // edits the selection we must keep tracking that loaded value; otherwise a
  // Finish would commit `[]` and wipe the trigger's real auth methods (data
  // loss). `authTouchedRef` records whether the user has taken ownership of the
  // selection — once they have, server updates no longer clobber their edit.
  const authTouchedRef = useRef(false);

  const setDraftAuthMethodIds = useCallback((ids: string[]) => {
    authTouchedRef.current = true;
    setDraftAuthMethodIdsState(ids);
  }, []);

  // Re-seed the draft auth ids from the loaded server value while the user has
  // not edited the selection. Guarded by `sameIdSet` so we only set state when
  // the value actually changed (avoids render loops).
  useEffect(() => {
    if (authTouchedRef.current) return;
    setDraftAuthMethodIdsState(current =>
      sameIdSet(current, initialAuthMethodIds) ? current : initialAuthMethodIds
    );
  }, [initialAuthMethodIds]);

  const mergeDraft = useCallback((updates: Partial<Workflow.Trigger>) => {
    setDraft(current => ({ ...current, ...updates }) as Workflow.Trigger);
  }, []);

  const reset = useCallback(() => {
    authTouchedRef.current = false;
    setDraft(trigger);
    setDraftAuthMethodIdsState(initialAuthMethodIds);
  }, [trigger, initialAuthMethodIds]);

  const authIdsChanged = useMemo(
    () => !sameIdSet(draftAuthMethodIds, initialAuthMethodIds),
    [draftAuthMethodIds, initialAuthMethodIds]
  );

  const isDirty = useMemo(() => {
    const triggerChanged = JSON.stringify(draft) !== JSON.stringify(trigger);
    return triggerChanged || authIdsChanged;
  }, [draft, trigger, authIdsChanged]);

  // Live validation of the draft against the trigger schema.
  const validationError = useMemo(() => {
    const result = TriggerSchema.safeParse(draft);
    if (result.success) return null;
    return result.error.issues[0]?.message ?? 'Invalid trigger configuration';
  }, [draft]);

  const commit = useCallback(async (): Promise<{ ok: boolean }> => {
    const result = TriggerSchema.safeParse(draft);

    // Invalid draft: do not persist. `validationError` (derived above) already
    // reflects the failure for the caller to surface.
    if (!result.success) {
      return { ok: false };
    }

    updateTrigger(trigger.id, draft);

    if (authIdsChanged) {
      await commitAuthMethods(draftAuthMethodIds);
    }

    return { ok: true };
  }, [
    draft,
    trigger.id,
    updateTrigger,
    authIdsChanged,
    draftAuthMethodIds,
    commitAuthMethods,
  ]);

  return {
    draft,
    mergeDraft,
    draftAuthMethodIds,
    setDraftAuthMethodIds,
    isDirty,
    reset,
    validationError,
    commit,
  };
}
