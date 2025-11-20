/**
 * # Session Hook
 *
 * Provides React hook for accessing the SessionStore instance.
 * After Phase 5 migration, this hook returns the SessionStoreInstance directly
 * instead of a memoized object, enabling zero context re-renders.
 *
 * ## Usage:
 *
 * ```typescript
 * const sessionStore = useSession();
 * // Access properties directly (convenience getters)
 * const { ydoc, provider, awareness, isConnected, isSynced, settled } = sessionStore;
 *
 * // Or use optimized selectors
 * const ydoc = sessionStore.withSelector(state => state.ydoc);
 * ```
 *
 * This hook is used by StoreProvider and components that need direct access
 * to session state. The store instance provides both convenience property
 * accessors and optimized selector-based subscriptions.
 */

import { useContext, useMemo, useSyncExternalStore } from 'react';

import { SessionContext } from '../contexts/SessionProvider';
import type { SessionState } from '../stores/createSessionStore';

function defaultSelector(state: SessionState): SessionState {
  return state;
}

export function useSession(): SessionState;
export function useSession<T>(
  selector: (state: SessionState) => T,
  deps?: React.DependencyList
): T;

/**
 * Hook to access SessionStore instance
 * Must be used within a SessionProvider
 *
 * @returns SessionStoreInstance - The session store with direct property access and selectors
 */
export function useSession<T = SessionState>(
  selector: (state: SessionState) => T = defaultSelector as (
    state: SessionState
  ) => T
): T {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error('useSession must be used within a SessionProvider');
  }

  const sessionStore = context.sessionStore;

  const getSnapshot = useMemo(() => {
    return sessionStore.withSelector(selector);
  }, [sessionStore, selector]);

  return useSyncExternalStore(sessionStore.subscribe, getSnapshot);
}
