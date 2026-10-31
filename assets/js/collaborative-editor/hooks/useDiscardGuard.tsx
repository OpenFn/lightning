/**
 * Asks before an action destroys the collaborative document, which takes any
 * uncommitted edits with it. Offers to save first.
 */

import { useCallback, useState } from 'react';

import { useHasSynced } from './useHasSynced';
import { useUnsavedChanges } from './useUnsavedChanges';
import { useWorkflowActions } from './useWorkflow';

export function useDiscardGuard() {
  const { hasChanges } = useUnsavedChanges();
  const hasSynced = useHasSynced();
  const { saveWorkflow } = useWorkflowActions();
  const [pending, setPending] = useState<(() => void) | null>(null);

  const atRisk = hasChanges && hasSynced;

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
