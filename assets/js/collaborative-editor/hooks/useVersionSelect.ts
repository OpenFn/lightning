/**
 * useVersionSelect Hook
 *
 * Provides a consolidated handler for workflow version selection.
 * Switches between workflow versions by updating URL parameters.
 *
 *
 * Version switching works by:
 * 1. Updating the URL parameter (?v=1, a release version_number, or no param
 *    for latest)
 * 2. SessionProvider detects the change and creates a new Y.Doc/provider
 * 3. The new provider connects to the appropriate room:
 *    - Latest: workflow:collaborate:{id}
 *    - Snapshot: workflow:collaborate:{id}:v{version_number}
 * 4. Y.Doc syncs fresh data from the server for the selected version
 *
 */

import { useCallback } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { useDiscardGuard } from './useDiscardGuard';

/**
 * Hook that provides a version selection handler.
 *
 * @returns The handler, plus the state a `DiscardChangesDialog` needs when the
 * switch would discard unsaved edits.
 */
export function useVersionSelect() {
  const { updateSearchParams } = useURLState();
  const { guard, ...prompt } = useDiscardGuard();

  const handleVersionSelect = useCallback(
    (version: number | 'latest') => {
      // Switching destroys the document, so ask first when that would take
      // uncommitted edits with it. A run belongs to one version, so it must not
      // leak across a switch either.
      guard(() => {
        updateSearchParams({
          v: version === 'latest' ? null : String(version),
          run: null,
          as_run: null,
        });
      });
    },
    [guard, updateSearchParams]
  );

  return { handleVersionSelect, prompt };
}
