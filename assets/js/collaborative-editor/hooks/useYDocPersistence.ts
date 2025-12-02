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

import _logger from '#/utils/logger';

import type { SessionStoreInstance } from '../stores/createSessionStore';

const logger = _logger.ns('useYDocPersistence').seal();

export interface YDocPersistenceOptions {
  /** The session store that manages Y.Doc */
  sessionStore: SessionStoreInstance;

  /** Whether to initialize Y.Doc (usually once per session) */
  shouldInitialize: boolean;

  /** Version identifier - when this changes, Y.Doc is reset */
  version: string | null;

  /** Callback when Y.Doc is initialized */
  onInitialized?: (ydoc: Y.Doc) => void;

  /** Callback when Y.Doc is destroyed */
  onDestroyed?: () => void;
}

/**
 * Hook that manages Y.Doc lifecycle with proper persistence
 *
 * @example
 * const { ydoc, hasInitialized } = useYDocPersistence({
 *   sessionStore,
 *   shouldInitialize: socket && isConnected,
 *   version: versionParam,
 *   onInitialized: (ydoc) => console.log('Y.Doc ready'),
 * });
 */
export function useYDocPersistence({
  sessionStore,
  shouldInitialize,
  version,
  onInitialized,
  onDestroyed,
}: YDocPersistenceOptions): {
  ydoc: Y.Doc | null;
  hasInitialized: boolean;
} {
  const hasInitialized = useRef(false);
  const prevVersionRef = useRef(version);

  // Handle version changes
  useEffect(() => {
    if (prevVersionRef.current !== version && hasInitialized.current) {
      // Version changed during migration - Y.Doc will be handled by migration
      // Just update the version ref so we don't trigger this again
      if (sessionStore.isTransitioning()) {
        logger.debug(
          'Version changed during migration - Y.Doc handled by registry'
        );
        prevVersionRef.current = version;
        return;
      }

      // Version changed outside of migration (edge case) - reset Y.Doc
      logger.debug('Version changed outside migration - resetting Y.Doc');
      onDestroyed?.();
      hasInitialized.current = false;
      prevVersionRef.current = version;
    }
  }, [version, onDestroyed, sessionStore]);

  // Track Y.Doc initialization
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

  return {
    ydoc: sessionStore.ydoc,
    hasInitialized: hasInitialized.current,
  };
}
