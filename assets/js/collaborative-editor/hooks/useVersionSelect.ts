/**
 * useVersionSelect Hook
 *
 * Provides a consolidated handler for workflow version selection.
 * Switches between workflow versions by updating URL parameters.
 *
 *
 * Version switching works by:
 * 1. Updating the URL parameter (?release=1, a release version_number, or no
 *    param for latest)
 * 2. SessionProvider detects the change and creates a new Y.Doc/provider
 * 3. The new provider connects to the appropriate room:
 *    - Latest: workflow:collaborate:{id}
 *    - Release: workflow:collaborate:{id}:release{version_number}
 * 4. Y.Doc syncs fresh data from the server for the selected version
 *
 */

import { useCallback } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { CLEAR_PINNED_VIEW, RELEASE_PARAM } from '../lib/pinnedView';

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
          ...CLEAR_PINNED_VIEW,
          [RELEASE_PARAM]: version === 'latest' ? null : String(version),
          run: null,
          // The step belongs to the run being cleared, and a step id means
          // nothing in another version.
          step: null,
        });
      });
    },
    [guard, updateSearchParams]
  );

  return { handleVersionSelect, prompt };
}
