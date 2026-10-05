/**
 * useVersionSelect Hook
 *
 * Provides a consolidated handler for workflow version selection.
 * Switches between workflow versions by updating URL parameters.
 *
 *
 * Version switching works by:
 * 1. Updating the URL parameter: `?release=1` for a release version_number with
 *    experimental features on, `?v=1` for a snapshot lock_version without, or
 *    no param for latest
 * 2. SessionProvider detects the change and creates a new Y.Doc/provider
 * 3. The new provider connects to the appropriate room:
 *    - Latest: workflow:collaborate:{id}
 *    - Release: workflow:collaborate:{id}:release{version_number}
 *    - Snapshot: workflow:collaborate:{id}:v{lock_version}
 * 4. Y.Doc syncs fresh data from the server for the selected version
 *
 */

import { useCallback } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import {
  AS_RUN_PARAM,
  CLEAR_PINNED_VIEW,
  RELEASE_PARAM,
  SNAPSHOT_PARAM,
} from '../lib/pinnedView';

import { useDiscardGuard } from './useDiscardGuard';
import { useExperimentalFeatures } from './useSessionContext';
import { useVersionPicker } from './useVersionPicker';

/**
 * Hook that provides a version selection handler.
 *
 * @returns The handler, plus the state a `DiscardChangesDialog` needs when the
 * switch would discard unsaved edits.
 */
export function useVersionSelect() {
  const { updateSearchParams } = useURLState();
  const { guard, ...prompt } = useDiscardGuard();
  const experimentalFeatures = useExperimentalFeatures();

  const picker = useVersionPicker();

  const handleVersionSelect = useCallback(
    (version: number | 'latest') => {
      const value = version === 'latest' ? null : String(version);

      const switchTo =
        picker === 'releases'
          ? () => {
              updateSearchParams({
                ...CLEAR_PINNED_VIEW,
                [RELEASE_PARAM]: value,
                run: null,
                step: null,
              });
            }
          : () => {
              updateSearchParams({
                [RELEASE_PARAM]: null,
                [AS_RUN_PARAM]: null,
                [SNAPSHOT_PARAM]: value,
              });
            };

      if (!experimentalFeatures) {
        switchTo();
        return;
      }

      guard(switchTo);
    },
    [experimentalFeatures, picker, guard, updateSearchParams]
  );

  return { handleVersionSelect, prompt };
}
