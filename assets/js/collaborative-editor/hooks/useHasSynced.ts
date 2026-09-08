import { useRef } from 'react';

import { useSession } from './useSession';

/**
 * Whether the current document has finished syncing at least once.
 *
 * `isSynced` is not latched: a dropped websocket, a sleeping laptop or a server
 * restart flips it back to false while the Y.Doc still holds the person's
 * unsaved edits. Anything that asks "is there work to lose" needs to survive
 * that, so this remembers the first sync and forgets it only when the document
 * itself is replaced, which the provider's identity tells us.
 */
export function useHasSynced() {
  const { provider, isSynced } = useSession();
  const hasSynced = useRef(false);
  const seenProvider = useRef(provider);

  if (seenProvider.current !== provider) {
    seenProvider.current = provider;
    hasSynced.current = false;
  }

  if (isSynced) hasSynced.current = true;

  return hasSynced.current;
}
