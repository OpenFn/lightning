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

import { useSyncExternalStore, useContext } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { AwarenessStoreInstance } from '../stores/createAwarenessStore';
import type { AwarenessUser, LocalUserData } from '../types/awareness';

/**
 * Main hook for accessing the AwarenessStore instance
 * Handles context access and error handling once
 */
const useAwarenessStore = (): AwarenessStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useAwarenessStore must be used within a StoreProvider');
  }
  return context.awarenessStore;
};

/**
 * Hook to get all connected users (including local user)
 * Returns referentially stable array that only changes when users actually change
 */
export const useAwarenessUsers = (): AwarenessUser[] => {
  const awarenessStore = useAwarenessStore();

  const selectUsers = awarenessStore.withSelector(state => state.users);

  return useSyncExternalStore(awarenessStore.subscribe, selectUsers);
};

/**
 * Hook to get only remote users (excluding the local user)
 * Useful for cursor rendering where you don't want to show your own cursor
 * Deduplicates users by keeping the one with the latest lastSeen timestamp
 * and adds connectionCount to show how many connections they have
 */
export const useRemoteUsers = (): AwarenessUser[] => {
  const awarenessStore = useAwarenessStore();

  const selectRemoteUsers = awarenessStore.withSelector(state => {
    if (!state.localUser) return state.users;

    // Filter out local user
    const remoteUsers = state.users.filter(
      user => user.user.id !== state.localUser?.id
    );

    // Group users by user ID and deduplicate
    const userMap = new Map<string, AwarenessUser>();
    const connectionCounts = new Map<string, number>();

    remoteUsers.forEach(user => {
      const userId = user.user.id;
      const count = connectionCounts.get(userId) || 0;
      connectionCounts.set(userId, count + 1);

      const existingUser = userMap.get(userId);
      if (!existingUser) {
        userMap.set(userId, user);
      } else {
        // Keep the user with the latest lastSeen timestamp
        const existingLastSeen = existingUser.lastSeen || 0;
        const currentLastSeen = user.lastSeen || 0;
        if (currentLastSeen > existingLastSeen) {
          userMap.set(userId, user);
        }
      }
    });

    // Add connection counts to users
    return Array.from(userMap.values()).map(user => ({
      ...user,
      connectionCount: connectionCounts.get(user.user.id) || 1,
    }));
  });

  return useSyncExternalStore(awarenessStore.subscribe, selectRemoteUsers);
};

/**
 * Hook to get the local user data
 * Returns null if user is not initialized
 */
export const useLocalUser = (): LocalUserData | null => {
  const awarenessStore = useAwarenessStore();

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
  const awarenessStore = useAwarenessStore();

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
  const awarenessStore = useAwarenessStore();

  const selectUser = awarenessStore.withSelector(state => {
    if (!userId) return null;
    return state.users.find(user => user.user.id === userId) || null;
  });

  return useSyncExternalStore(awarenessStore.subscribe, selectUser);
};

/**
 * Hook to get the map of user cursors
 */
export const useUserCursors = (): Map<number, AwarenessUser> => {
  const awarenessStore = useAwarenessStore();

  const selectCursors = awarenessStore.withSelector(state => state.cursorsMap);

  return useSyncExternalStore(awarenessStore.subscribe, selectCursors);
};

/**
 * Hook to get the raw awareness instance (for Monaco editor bindings)
 * This is referentially stable - only changes when awareness is initialized/destroyed
 */
export const useRawAwareness = () => {
  const awarenessStore = useAwarenessStore();

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
  const awarenessStore = useAwarenessStore();

  const selectReady = awarenessStore.withSelector(
    state => state.isInitialized && state.rawAwareness !== null
  );

  return useSyncExternalStore(awarenessStore.subscribe, selectReady);
};

/**
 * Hook to get awareness command functions
 * Returns stable function references that don't change across renders
 * Use this for actions like updating cursor position, user data, etc.
 */
export const useAwarenessCommands = () => {
  const awarenessStore = useAwarenessStore();

  // These are already stable function references from the store
  return {
    updateLocalUserData: awarenessStore.updateLocalUserData,
    updateLocalCursor: awarenessStore.updateLocalCursor,
    updateLocalSelection: awarenessStore.updateLocalSelection,
    updateLastSeen: awarenessStore.updateLastSeen,
    setConnected: awarenessStore.setConnected,
  };
};
