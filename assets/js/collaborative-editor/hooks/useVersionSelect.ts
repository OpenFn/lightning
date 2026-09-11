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
  CLEAR_PINNED_VIEW,
  RELEASE_PARAM,
  SNAPSHOT_PARAM,
} from '../lib/pinnedView';

import { useDiscardGuard } from './useDiscardGuard';
import { useExperimentalFeatures } from './useSessionContext';

/**
 * Hook that provides a version selection handler.
 *
 * @returns The handler, plus the state a `DiscardChangesDialog` needs when the
 * switch would discard unsaved edits.
 */
export function useVersionSelect() {
  const { updateSearchParams } = useURLState();
  const { guard, ...prompt } = useDiscardGuard();

  // Which numbering the picker on screen is using. A release version_number and
  // a snapshot lock_version are different numbers for different content, so
  // writing one into the other's parameter would open the wrong document.
  const experimentalFeatures = useExperimentalFeatures();

  const handleVersionSelect = useCallback(
    (version: number | 'latest') => {
      const value = version === 'latest' ? null : String(version);

      // Without the flag this touches the one parameter it has always touched.
      // A run stays open across the switch, which is how the mismatch banner's
      // offer works today: it takes you to the version the open run ran
      // against, and the run has to survive the trip.
      const switchTo = experimentalFeatures
        ? () => {
            updateSearchParams({
              ...CLEAR_PINNED_VIEW,
              [RELEASE_PARAM]: value,
              run: null,
              // The step belongs to the run being cleared, and a step id means
              // nothing in another version.
              step: null,
            });
          }
        : () => {
            updateSearchParams({ [SNAPSHOT_PARAM]: value });
          };

      // Switching destroys the document, so with experimental features on we
      // ask first when that would take uncommitted edits with it.
      //
      // Without them, it switches straight away and the edits go, which is what
      // the editor does today. The prompt is a good addition and it is still an
      // addition; a user who did not opt in should not meet a dialog they have
      // never seen.
      if (!experimentalFeatures) {
        switchTo();
        return;
      }

      guard(switchTo);
    },
    [experimentalFeatures, guard, updateSearchParams]
  );

  return { handleVersionSelect, prompt };
}
