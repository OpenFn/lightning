/**
 * # Awareness Hooks
 *
 * Provides React hooks for consuming awareness data with maximum referential stability.
 * These hooks use useSyncExternalStore with memoized selectors to minimize re-renders.
 *
 * ## Unified API (Recommended):
 * - `useAwareness(options?)`: Flexible hook with options for all use cases
 *
 * ## Legacy Hooks (Deprecated - use useAwareness instead):
 * - `useAwarenessUsers()`: All connected users
 * - `useRemoteUsers()`: Remote users with deduplication
 * - `useLiveRemoteUsers()`: Live remote users only
 * - `useUserCursors()`: Cursor map for rendering
 *
 * ## Other Hooks:
 * - `useLocalUser()`: Current user data
 * - `useRawAwareness()`: Raw awareness instance (for Monaco bindings)
 * - `useAwarenessCommands()`: Command functions
 *
 * ## Usage Examples:
 *
 * ```typescript
 * // Live remote users only (default) - for cursor rendering
 * const users = useAwareness();
 *
 * // Include cached users (recently disconnected) - for avatar lists
 * const users = useAwareness({ cached: true });
 *
 * // Return as Map keyed by clientId - for Monaco CSS generation
 * const usersMap = useAwareness({ format: 'map' });
 *
 * // Combination: cached + map format
 * const usersMap = useAwareness({
 *   cached: true,
 *   format: 'map'
 * });
 *
 * // Get local user info
 * const localUser = useLocalUser();
 *
 * // Access store commands
 * const { updateLocalCursor } = useAwarenessCommands();
 * updateLocalCursor({ x: 100, y: 200 });
 *
 * // Raw awareness for Monaco (referentially stable)
 * const rawAwareness = useRawAwareness();
 * ```
 *
 * ## Migration Guide:
 * ```typescript
 * // Old: useLiveRemoteUsers()
 * // New: useAwareness()
 * const users = useAwareness();
 *
 * // Old: useRemoteUsers()
 * // New: useAwareness({ cached: true })
 * const users = useAwareness({ cached: true });
 *
 * // Old: useUserCursors()
 * // New: useAwareness({ format: 'map' })
 * const usersMap = useAwareness({ format: 'map' });
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
 * Deduplicates users by keeping the one with the highest priority state
 * (active > away > idle), then by latest lastSeen timestamp
 * Adds connectionCount to show how many connections they have
 */
export const useRemoteUsers = (): AwarenessUser[] => {
  const awarenessStore = useAwarenessStore();

  const selectRemoteUsers = awarenessStore.withSelector(state => {
    if (!state.localUser) return state.users;

    const remoteUsers = state.users.filter(
      user => user.user.id !== state.localUser?.id
    );

    const statePriority = { active: 3, away: 2, idle: 1 };
    const userMap = new Map<string, AwarenessUser[]>();
    const connectionCounts = new Map<string, number>();

    remoteUsers.forEach(user => {
      const userId = user.user.id;
      connectionCounts.set(userId, (connectionCounts.get(userId) || 0) + 1);
      (userMap.get(userId) || userMap.set(userId, []).get(userId)!).push(user);
    });

    return Array.from(userMap.values()).map(users => {
      const selected = users.sort((a, b) => {
        const stateDiff =
          (statePriority[b.lastState || 'idle'] || 0) -
          (statePriority[a.lastState || 'idle'] || 0);
        return stateDiff || (b.lastSeen || 0) - (a.lastSeen || 0);
      })[0];

      return {
        ...selected,
        connectionCount: connectionCounts.get(selected.user.id) || 1,
      };
    });
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
 * Hook to get only live/active remote users (excluding cached/inactive users)
 * Use this for cursor rendering where you only want to show active users
 * Use useRemoteUsers() for avatar lists where you want to show cached users too
 */
export const useLiveRemoteUsers = (): AwarenessUser[] => {
  const awarenessStore = useAwarenessStore();

  const selectLiveRemoteUsers = awarenessStore.withSelector(state => {
    if (!state.localUser) {
      return Array.from(state.cursorsMap.values());
    }

    // Filter out local user from cursorsMap
    return Array.from(state.cursorsMap.values()).filter(
      user => user.user.id !== state.localUser?.id
    );
  });

  return useSyncExternalStore(awarenessStore.subscribe, selectLiveRemoteUsers);
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

/**
 * Options for the unified useAwareness hook
 */
export interface UseAwarenessOptions {
  /**
   * Use cached users (live + recently disconnected within 60s TTL)
   * Default: false (live only from cursorsMap)
   */
  cached?: boolean;
  /**
   * Return format
   * Default: 'array'
   */
  format?: 'array' | 'map';
}

// TypeScript overloads for type-safe return types
export function useAwareness(
  options: { format: 'map' } & Omit<UseAwarenessOptions, 'format'>
): Map<number, AwarenessUser>;
export function useAwareness(options?: UseAwarenessOptions): AwarenessUser[];

/**
 * Unified hook for accessing awareness data with flexible options
 *
 * This hook consolidates the functionality of useRemoteUsers(),
 * useLiveRemoteUsers(), and useUserCursors() into a single,
 * flexible API.
 *
 * The hook always excludes the local user from results, as no
 * component needs to render the current user's cursor or avatar.
 *
 * @example
 * // Live remote users only (default) - for cursor rendering
 * const users = useAwareness();
 *
 * @example
 * // Include cached users (recently disconnected) - for avatar lists
 * const users = useAwareness({ cached: true });
 *
 * @example
 * // Return as Map keyed by clientId - for Monaco CSS generation
 * const usersMap = useAwareness({ format: 'map' });
 *
 * @example
 * // Combination: cached + map format
 * const usersMap = useAwareness({
 *   cached: true,
 *   format: 'map'
 * });
 */
export function useAwareness(
  options?: UseAwarenessOptions
): AwarenessUser[] | Map<number, AwarenessUser> {
  const awarenessStore = useAwarenessStore();

  // Normalize options with defaults
  const opts = {
    cached: options?.cached ?? false,
    format: options?.format ?? 'array',
  } as const;

  const selectUsers = awarenessStore.withSelector(state => {
    // 1. Choose data source
    let users: AwarenessUser[];

    if (opts.cached) {
      // Use state.users (live + cached users within 60s TTL)
      users = state.users;

      // Apply deduplication (same logic as useRemoteUsers)
      const userMap = new Map<string, AwarenessUser>();
      const connectionCounts = new Map<string, number>();

      users.forEach(user => {
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

      // Add connection counts
      users = Array.from(userMap.values()).map(user => ({
        ...user,
        connectionCount: connectionCounts.get(user.user.id) || 1,
      }));
    } else {
      // Use cursorsMap (live users only, no deduplication needed)
      users = Array.from(state.cursorsMap.values());
    }

    // 2. Always filter out local user
    if (state.localUser) {
      users = users.filter(u => u.user.id !== state.localUser?.id);
    }

    // 3. Return in requested format
    if (opts.format === 'map') {
      // Convert array to Map keyed by clientId
      return new Map(users.map(user => [user.clientId, user]));
    }

    return users;
  });

  return useSyncExternalStore(awarenessStore.subscribe, selectUsers);
}
