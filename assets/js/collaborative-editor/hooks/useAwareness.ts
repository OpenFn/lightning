/**
 * # Awareness Hooks
 *
 * Provides React hooks for consuming awareness data with maximum referential stability.
 * These hooks use useSyncExternalStore with memoized selectors to minimize re-renders.
 *
 * ## Core Hooks:
 * - `useAwareness()`: Access to awareness store methods
 * - `useAwarenessUsers()`: All connected users
 * - `useRemoteUsers()`: Remote users (excluding local user)
 * - `useLocalUser()`: Current user data
 * - `useUserCursors()`: Cursor data for rendering
 * - `useRawAwareness()`: Raw awareness instance (for Monaco bindings)
 *
 * ## Usage Examples:
 *
 * ```typescript
 * // Get all users
 * const users = useAwarenessUsers();
 *
 * // Get only remote users for cursor rendering
 * const remoteUsers = useRemoteUsers();
 *
 * // Get local user info
 * const localUser = useLocalUser();
 *
 * // Access store commands
 * const awareness = useAwareness();
 * awareness.updateLocalCursor({ x: 100, y: 200 });
 *
 * // Raw awareness for Monaco (referentially stable)
 * const rawAwareness = useRawAwareness();
 * ```
 */

import { useSyncExternalStore } from "react";

import { useSession } from "../contexts/SessionProvider";
import type { AwarenessUser, LocalUserData } from "../types/awareness";

/**
 * Hook to access the awareness store instance and all its methods
 */
export const useAwareness = () => {
  const { awarenessStore } = useSession();
  return awarenessStore;
};

/**
 * Hook to get all connected users (including local user)
 * Returns referentially stable array that only changes when users actually change
 */
export const useAwarenessUsers = (): AwarenessUser[] => {
  const { awarenessStore } = useSession();

  const selectUsers = awarenessStore.withSelector(state => state.users);

  return useSyncExternalStore(awarenessStore.subscribe, selectUsers);
};

/**
 * Hook to get only remote users (excluding the local user)
 * Useful for cursor rendering where you don't want to show your own cursor
 */
export const useRemoteUsers = (): AwarenessUser[] => {
  const { awarenessStore } = useSession();

  const selectRemoteUsers = awarenessStore.withSelector(state => {
    if (!state.localUser) return state.users;
    return state.users.filter(user => user.user.id !== state.localUser?.id);
  });

  return useSyncExternalStore(awarenessStore.subscribe, selectRemoteUsers);
};

/**
 * Hook to get the local user data
 * Returns null if user is not initialized
 */
export const useLocalUser = (): LocalUserData | null => {
  const { awarenessStore } = useSession();

  const selectLocalUser = awarenessStore.withSelector(state => state.localUser);

  return useSyncExternalStore(awarenessStore.subscribe, selectLocalUser);
};

/**
 * Hook to get awareness connection state
 */
export const useAwarenessConnectionState = (): {
  isInitialized: boolean;
  isConnected: boolean;
} => {
  const { awarenessStore } = useSession();

  const selectConnectionState = awarenessStore.withSelector(state => ({
    isInitialized: state.isInitialized,
    isConnected: state.isConnected,
  }));

  return useSyncExternalStore(awarenessStore.subscribe, selectConnectionState);
};

/**
 * Hook to get a specific user by ID
 */
export const useUserById = (userId: string | null): AwarenessUser | null => {
  const { awarenessStore } = useSession();

  const selectUser = awarenessStore.withSelector(state => {
    if (!userId) return null;
    return state.users.find(user => user.user.id === userId) || null;
  });

  return useSyncExternalStore(awarenessStore.subscribe, selectUser);
};

/**
 * Hook to get cursor data optimized for rendering
 * Returns a Map for efficient lookups by clientId
 */
export const useUserCursors = (): Map<number, AwarenessUser> => {
  const { awarenessStore } = useSession();

  const selectCursors = awarenessStore.withSelector(state => {
    const cursorsMap = new Map<number, AwarenessUser>();

    state.users.forEach(user => {
      if (user.cursor || user.selection) {
        cursorsMap.set(user.clientId, user);
      }
    });

    return cursorsMap;
  });

  return useSyncExternalStore(awarenessStore.subscribe, selectCursors);
};

/**
 * Hook to get the raw awareness instance (for Monaco editor bindings)
 * This is referentially stable - only changes when awareness is initialized/destroyed
 */
export const useRawAwareness = () => {
  const { awarenessStore } = useSession();

  const selectRawAwareness = awarenessStore.withSelector(
    state => state.rawAwareness
  );

  return useSyncExternalStore(awarenessStore.subscribe, selectRawAwareness);
};

/**
 * Hook to get awareness readiness state
 * Useful for conditional rendering of awareness-dependent components
 */
export const useAwarenessReady = (): boolean => {
  const { awarenessStore } = useSession();

  const selectReady = awarenessStore.withSelector(
    state => state.isInitialized && state.rawAwareness !== null
  );

  return useSyncExternalStore(awarenessStore.subscribe, selectReady);
};
