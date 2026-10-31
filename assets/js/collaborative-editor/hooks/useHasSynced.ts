/** Whether this provider has synced at least once. Resets when it changes. */

import { useRef } from 'react';

import { useSession } from './useSession';

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
