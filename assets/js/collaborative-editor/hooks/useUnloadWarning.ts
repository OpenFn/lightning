import { useEffect } from 'react';

import { isUnloadWarningSuppressed } from '../lib/unloadGuard';

import { useHasSynced } from './useHasSynced';
import { useExperimentalFeatures } from './useSessionContext';
import { useUnsavedChanges } from './useUnsavedChanges';

/**
 * Warns before the browser leaves the page with unsaved edits.
 *
 * This one has to use the browser's own dialog, which cannot be styled and
 * cannot offer to save. Everything that stays inside the app, and the hard
 * navigation into a sandbox, ask through `useDiscardGuard` instead.
 *
 * Behind the experimental flag, like everything else this work added. It is a
 * good warning and it is still new: a user who did not opt in should get the
 * editor they have today, and today closing the tab asks them nothing.
 */
export function useUnloadWarning() {
  const { hasChanges } = useUnsavedChanges();
  const hasSynced = useHasSynced();
  const experimentalFeatures = useExperimentalFeatures();

  useEffect(() => {
    if (!experimentalFeatures) return;

    // Before the document syncs the store is empty and so differs from the
    // saved workflow, which is not a change anyone made. A later disconnect
    // must not disarm the warning, hence the first sync rather than the
    // current one.
    if (!hasChanges || !hasSynced) return;

    const warn = (event: BeforeUnloadEvent) => {
      if (isUnloadWarningSuppressed()) return;
      event.preventDefault();
    };

    window.addEventListener('beforeunload', warn);

    return () => {
      window.removeEventListener('beforeunload', warn);
    };
  }, [experimentalFeatures, hasChanges, hasSynced]);
}
