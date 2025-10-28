/**
 * useVersionSelect Hook
 *
 * Provides a consolidated handler for workflow version selection.
 * Switches between workflow versions by updating URL parameters.
 *
 * This hook replaces duplicated handleVersionSelect functions across:
 * - CollaborativeEditor.tsx
 * - components/ide/IDEHeader.tsx
 *
 * Version switching works by:
 * 1. Updating the URL parameter (?v=22 or no param for latest)
 * 2. SessionProvider detects the change and creates a new Y.Doc/provider
 * 3. The new provider connects to the appropriate room:
 *    - Latest: workflow:collaborate:{id}
 *    - Snapshot: workflow:collaborate:{id}:v{version}
 * 4. Y.Doc syncs fresh data from the server for the selected version
 */

import { useURLState } from '#/react/lib/use-url-state';

/**
 * Hook that provides a version selection handler.
 *
 * @returns Handler function for version selection
 */
export function useVersionSelect() {
  const { updateSearchParams } = useURLState();

  const handleVersionSelect = (version: number | 'latest') => {
    // Update URL parameter to trigger version switch
    // SessionProvider will detect the change and recreate the Y.Doc/provider
    if (version === 'latest') {
      updateSearchParams({ v: null }); // Remove version param
    } else {
      updateSearchParams({ v: String(version) }); // Set version param
    }
  };

  return handleVersionSelect;
}
