/** Warns on leaving the page with uncommitted edits. */

import { useEffect } from 'react';

import { isUnloadWarningSuppressed } from '../lib/unloadGuard';

import { useHasSynced } from './useHasSynced';
import { useExperimentalFeatures } from './useSessionContext';
import { useUnsavedChanges } from './useUnsavedChanges';

export function useUnloadWarning() {
  const { hasChanges } = useUnsavedChanges();
  const hasSynced = useHasSynced();
  const experimentalFeatures = useExperimentalFeatures();

  useEffect(() => {
    if (!experimentalFeatures) return;

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
