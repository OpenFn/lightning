/**
 * Saves before a run, where a save is possible. Running is not editing, so a
 * live workflow or a view of the past runs without one rather than failing.
 */

import { useCallback } from 'react';

import { usePinnedView } from '../lib/pinnedView';

import { useContentLocked } from './useSessionContext';
import type { SaveWorkflowOptions } from './useWorkflow';

type SaveWorkflow = (
  options?: SaveWorkflowOptions
) => Promise<{ saved_at?: string; lock_version?: number }>;

export function useSaveBeforeRun(saveWorkflow: SaveWorkflow) {
  const contentLocked = useContentLocked();
  const { isPinnedView } = usePinnedView();

  return useCallback(async (): Promise<boolean> => {
    if (contentLocked || isPinnedView) return false;
    await saveWorkflow({ notify: 'none' });
    return true;
  }, [contentLocked, isPinnedView, saveWorkflow]);
}
