import { useEffect } from 'react';

import { isUnloadWarningSuppressed } from '../lib/unloadGuard';

import { useHasSynced } from './useHasSynced';
import { useUnsavedChanges } from './useUnsavedChanges';

/**
 * Warns before the browser leaves the page with unsaved edits.
 *
 * This one has to use the browser's own dialog, which cannot be styled and
 * cannot offer to save. Everything that stays inside the app, and the hard
 * navigation into a sandbox, ask through `useDiscardGuard` instead.
 */
export function useUnloadWarning() {
  const { hasChanges } = useUnsavedChanges();
  const hasSynced = useHasSynced();

  useEffect(() => {
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
  }, [hasChanges, hasSynced]);
}
