/**
 * useViewAsExecuted Hook
 *
 * Loads the workflow read-only exactly as a given run executed it.
 *
 * Unlike `?release=<version_number>` (which pins a published release and builds
 * the `:release<N>` room) and `?run=<id>` (which merely selects a run for step
 * highlighting on the current document), this sets a distinct `?as_run=<run_id>`
 * param. SessionProvider turns that into the run-scoped room
 * `workflow:collaborate:{id}:run:{run_id}`, which the backend loads read-only
 * from the exact snapshot that run executed against. This works for ANY run,
 * including runs against unreleased/draft snapshots.
 *
 * `run` is set alongside `as_run` so the executed steps still highlight on the
 * canvas; any prior version pin is cleared since the two are mutually exclusive
 * views.
 */

import { useCallback } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { AS_RUN_PARAM, CLEAR_PINNED_VIEW } from '../lib/pinnedView';

import { useDiscardGuard } from './useDiscardGuard';

export function useViewAsExecuted() {
  const { updateSearchParams } = useURLState();
  const { guard, ...prompt } = useDiscardGuard();

  const viewAsExecuted = useCallback(
    /**
     * @param onProceed runs just before the URL changes, for state that must
     *   only be set if the prompt does not block the switch.
     */
    (runId: string, onProceed?: () => void) => {
      // Pinning a run loads its snapshot, which destroys the document. Ask
      // before that takes uncommitted edits with it.
      guard(() => {
        onProceed?.();
        updateSearchParams({
          ...CLEAR_PINNED_VIEW,
          [AS_RUN_PARAM]: runId,
          run: runId,
        });
      });
    },
    [guard, updateSearchParams]
  );

  return { viewAsExecuted, prompt };
}
