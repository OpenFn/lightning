/**
 * useYDocPersistence - Manages Y.Doc lifecycle and persistence
 *
 * This hook is responsible for:
 * - Creating Y.Doc on mount
 * - Preserving Y.Doc during disconnections (offline editing support)
 * - Destroying Y.Doc only on unmount
 *
 * Key principle: Y.Doc is never destroyed during connection changes,
 * only when the component unmounts.
 */

import { useEffect, useRef } from 'react';
import type * as Y from 'yjs';

import type { SessionStoreInstance } from '../stores/createSessionStore';

export interface YDocPersistenceOptions {
  /** The session store that manages Y.Doc */
  sessionStore: SessionStoreInstance;

  /** Whether to initialize Y.Doc (usually once per session) */
  shouldInitialize: boolean;

  /** Callback when Y.Doc is initialized */
  onInitialized?: (ydoc: Y.Doc) => void;

  /** Callback when Y.Doc is destroyed */
  onDestroyed?: () => void;
}

/**
 * Hook that manages Y.Doc lifecycle with proper persistence
 *
 * @example
 * const ydoc = useYDocPersistence({
 *   sessionStore,
 *   shouldInitialize: socket && isConnected,
 *   onInitialized: (ydoc) => console.log('Y.Doc ready'),
 * });
 */
export function useYDocPersistence({
  sessionStore,
  shouldInitialize,
  onInitialized,
  onDestroyed,
}: YDocPersistenceOptions): Y.Doc | null {
  const hasInitialized = useRef(false);

  // Initialize Y.Doc when conditions are met
  useEffect(() => {
    if (!shouldInitialize || hasInitialized.current) {
      return;
    }

    // Y.Doc is created by sessionStore.initializeSession
    // This effect just tracks initialization state
    if (sessionStore.ydoc) {
      hasInitialized.current = true;
      onInitialized?.(sessionStore.ydoc);
    }
  }, [shouldInitialize, sessionStore, onInitialized]);

  // Cleanup: Only destroy Y.Doc on unmount
  useEffect(() => {
    return () => {
      if (hasInitialized.current) {
        onDestroyed?.();
        hasInitialized.current = false;
      }
    };
  }, [onDestroyed]);

  return sessionStore.ydoc;
}
