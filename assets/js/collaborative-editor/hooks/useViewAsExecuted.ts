/**
 * useViewAsExecuted Hook
 *
 * Loads the workflow read-only exactly as a given run executed it.
 *
 * Unlike `?v=<version_number>` (which pins a published *release* and builds the
 * `:v<N>` snapshot room) and `?run=<id>` (which merely selects a run for step
 * highlighting on the current document), this sets a distinct `?as_run=<run_id>`
 * param. SessionProvider turns that into the run-scoped room
 * `workflow:collaborate:{id}:run:{run_id}`, which the backend loads read-only
 * from the exact snapshot that run executed against. This works for ANY run,
 * including runs against unreleased/draft snapshots.
 *
 * `run` is set alongside `as_run` so the executed steps still highlight on the
 * canvas; any prior `?v=` release pin is cleared since the two are mutually
 * exclusive views.
 */

import { useCallback } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

export function useViewAsExecuted() {
  const { updateSearchParams } = useURLState();

  return useCallback(
    (runId: string) => {
      updateSearchParams({ v: null, as_run: runId, run: runId });
    },
    [updateSearchParams]
  );
}
