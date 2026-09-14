import { useCallback } from 'react';

import { useContentLocked } from './useSessionContext';
import type { SaveWorkflowOptions } from './useWorkflow';

type SaveWorkflow = (
  options?: SaveWorkflowOptions
) => Promise<{ saved_at?: string; lock_version?: number }>;

/**
 * Saves the workflow on the way to starting a run, unless the server would
 * refuse the save.
 *
 * Every run control saves first, so a draft runs what is on screen rather than
 * what was last written. A live workflow outside a sandbox cannot be saved at
 * all: the channel rejects the write and the run never happens, which is why
 * running a live workflow used to fail with an editing error. Running is not
 * editing, so the run goes ahead and the save is skipped.
 *
 * Gated on the lifecycle lock alone, which is the same condition the server
 * gates on, so nothing else about when a run saves changes.
 *
 * Returns whether it saved, because the toast afterwards says so.
 */
export function useSaveBeforeRun(saveWorkflow: SaveWorkflow) {
  const contentLocked = useContentLocked();

  return useCallback(async (): Promise<boolean> => {
    if (contentLocked) return false;
    await saveWorkflow({ notify: 'none' });
    return true;
  }, [contentLocked, saveWorkflow]);
}
