import { useCallback, useState } from 'react';

import { useSession } from './useSession';
import { useUnsavedChanges } from './useUnsavedChanges';
import { useWorkflowActions } from './useWorkflow';

/**
 * Asks before an action destroys unsaved edits.
 *
 * Switching version, opening a run that pins one, and leaving for a sandbox all
 * tear the collaborative document down, taking uncommitted changes with them.
 * Wrap the action in `guard` and it runs immediately when there is nothing to
 * lose, or waits for an answer when there is.
 */
export function useDiscardGuard() {
  const { hasChanges } = useUnsavedChanges();
  const { isSynced } = useSession();
  const { saveWorkflow } = useWorkflowActions();
  const [pending, setPending] = useState<(() => void) | null>(null);

  // Before the document has synced the store is still empty, so it differs from
  // the saved workflow and reads as changed. `isSynced` is what tells the two
  // apart, and the save button is gated the same way.
  const atRisk = hasChanges && isSynced;

  const guard = useCallback(
    (proceed: () => void) => {
      if (!atRisk) {
        proceed();
        return;
      }

      setPending(() => proceed);
    },
    [atRisk]
  );

  const cancel = useCallback(() => {
    setPending(null);
  }, []);

  const runPending = useCallback(() => {
    const proceed = pending;

    setPending(null);
    proceed?.();
  }, [pending]);

  // The dialog owns the messaging, so the save is asked to stay quiet, and a
  // failure keeps the dialog open rather than switching anyway.
  const saveAndRunPending = useCallback(async () => {
    try {
      await saveWorkflow({ notify: 'error-only' });
    } catch {
      return false;
    }

    runPending();
    return true;
  }, [saveWorkflow, runPending]);

  return {
    guard,
    isAsking: pending !== null,
    cancel,
    runPending,
    saveAndRunPending,
  };
}
