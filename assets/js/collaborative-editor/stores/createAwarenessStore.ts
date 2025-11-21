/**
 * # AwarenessStore
 *
 * This store implements the same pattern as WorkflowStore and AdaptorStore:
 * useSyncExternalStore + Immer for optimal performance and referential stability.
 *
 * ## Core Principles:
 * - Awareness as reactive data source (similar to Y.Doc)
 * - Immer for referentially stable state updates
 * - Command Query Separation (CQS) for predictable state mutations
 * - Maximum referential stability to minimize React re-renders
 * - Clean separation between collaborative awareness data and local UI state
 *
 * ## Update Patterns:
 *
 * ### Pattern 1: Awareness → Observer → Immer → Notify (Collaborative Data)
 * **When to use**: All collaborative awareness data (users, cursors, selections)
 * **Flow**: Awareness change → observer fires → validate → Immer update → React notification
 * **Benefits**: Real-time collaboration, automatic conflict resolution, referential stability
 *
 * ```typescript
 * // Example: Awareness state changes trigger observer
 * awareness.on('change', () => {
 *   const users = extractUsersFromAwareness(awareness);
 *   state = produce(state, (draft) => {
 *     draft.users = users;  // Referentially stable update
 *     draft.lastUpdated = Date.now();
 *   });
 *   notify();
 * });
 * ```
 *
 * ### Pattern 2: Direct Immer → Notify + Awareness Update (Local Commands)
 * **When to use**: Local user actions that need to update awareness
 * **Flow**: Command → update awareness → immediate local state update → notify
 * **Benefits**: Immediate UI feedback, maintains consistency
 *
 * ```typescript
 * // Example: Update local cursor position
 * const updateLocalCursor = (cursor: { x: number; y: number } | null) => {
 *   if (awareness) {
 *     awareness.setLocalStateField('cursor', cursor);
 *   }
 *
 *   state = produce(state, (draft) => {
 *     if (draft.localUser) {
 *       // Update local state immediately for responsiveness
 *       const localUserIndex = draft.users.findIndex(u => u.user.id === draft.localUser?.id);
 *       if (localUserIndex !== -1 && cursor) {
 *         draft.users[localUserIndex].cursor = cursor;
 *       }
 *     }
 *   });
 *   notify();
 * };
 * ```
 *
 * ### Pattern 3: Direct Immer → Notify (Local UI State)
 * **When to use**: Local state that doesn't affect awareness
 * **Flow**: Direct Immer update → React notification
 * **Benefits**: Simple, immediate response
 *
 * ## Architecture Benefits:
 * - Removes awareness dependency from SessionProvider context
 * - Provides memoized selectors for referential stability
 * - Separates awareness management from session lifecycle
 * - Enables fine-grained subscriptions to specific awareness data
 */

/**
 * ## Redux DevTools Integration
 *
 * This store integrates with Redux DevTools for debugging in
 * development and test environments.
 *
 * **Features:**
 * - Real-time state inspection
 * - Action history with timestamps
 * - Time-travel debugging (jump to previous states)
 * - State export/import for reproducing bugs
 *
 * **Usage:**
 * 1. Install Redux DevTools browser extension
 * 2. Open DevTools and select the "AwarenessStore" instance
 * 3. Perform actions in the app and watch them appear in DevTools
 *
 * **Note:** DevTools is automatically disabled in production builds.
 *
 * **Excluded from DevTools:**
 * rawAwareness (too large/circular)
 */

import { produce } from 'immer';
import type { Awareness } from 'y-protocols/awareness';

import _logger from '#/utils/logger';

import type {
  AwarenessState,
  AwarenessStore,
  AwarenessUser,
  LocalUserData,
} from '../types/awareness';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('AwarenessStore').seal();

/**
 * Creates an awareness store instance with useSyncExternalStore + Immer pattern
 */
export const createAwarenessStore = (): AwarenessStore => {
  // Single Immer-managed state object (referentially stable)
  let state: AwarenessState = produce(
    {
      users: [],
      localUser: null,
      isInitialized: false,
      cursorsMap: new Map(),
      rawAwareness: null,
      isConnected: false,
      lastUpdated: null,
    } as AwarenessState,
    // No initial transformations needed
    draft => draft
  );

  const listeners = new Set<() => void>();
  let awarenessInstance: Awareness | null = null;
  let lastSeenTimer: NodeJS.Timeout | null = null;

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'AwarenessStore',
    excludeKeys: ['rawAwareness'], // Exclude Y.js Awareness object
    maxAge: 200, // Higher limit since awareness changes are frequent
  });

  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
    listeners.forEach(listener => {
      listener();
    });
  };

  // =============================================================================
  // CORE STORE INTERFACE
  // =============================================================================

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): AwarenessState => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  // =============================================================================
  // PATTERN 1: Awareness → Observer → Immer → Notify (Collaborative Data)
  // =============================================================================

  /**
   * Helper: Compare cursor positions for referential stability
   */
  const arePositionsEqual = (
    a: { x: number; y: number } | undefined,
    b: { x: number; y: number } | undefined
  ): boolean => {
    if (a === undefined && b === undefined) return true;
    if (a === undefined || b === undefined) return false;
    return a.x === b.x && a.y === b.y;
  };

  /**
   * Helper: Compare selections (RelativePosition) for referential stability
   */
  const areSelectionsEqual = (
    a: AwarenessUser['selection'] | undefined,
    b: AwarenessUser['selection'] | undefined
  ): boolean => {
    if (a === undefined && b === undefined) return true;
    if (a === undefined || b === undefined) return false;

    // RelativePosition objects from Yjs need proper comparison
    // Using JSON.stringify for deep equality check
    return (
      JSON.stringify(a.anchor) === JSON.stringify(b.anchor) &&
      JSON.stringify(a.head) === JSON.stringify(b.head)
    );
  };

  /**
   * Handle awareness state changes - core collaborative data update pattern
   */
  const handleAwarenessChange = () => {
    if (!awarenessInstance) {
      logger.warn('handleAwarenessChange called without awareness instance');
      return;
    }

    // Capture awareness instance for closure
    const awareness = awarenessInstance;

    state = produce(state, draft => {
      const awarenessStates = awareness.getStates();

      // Track which clientIds we've seen in this update
      const seenClientIds = new Set<number>();

      // Update or add users using Immer's Map support
      awarenessStates.forEach((awarenessState, clientId) => {
        seenClientIds.add(clientId);

        // Validate user data exists
        if (!awarenessState['user']) {
          return;
        }

        try {
          // Get existing user from Map (if any)
          const existingUser = draft.cursorsMap.get(clientId);

          // Extract new data
          const userData = awarenessState['user'] as AwarenessUser['user'];
          const cursor = awarenessState['cursor'] as AwarenessUser['cursor'];
          const selection = awarenessState[
            'selection'
          ] as AwarenessUser['selection'];
          const lastSeen = awarenessState['lastSeen'] as number | undefined;

          // Check if user data actually changed
          if (existingUser) {
            let hasChanged = false;

            // Compare user fields
            if (
              existingUser.user.id !== userData.id ||
              existingUser.user.name !== userData.name ||
              existingUser.user.email !== userData.email ||
              existingUser.user.color !== userData.color
            ) {
              hasChanged = true;
            }

            // Compare cursor
            if (!arePositionsEqual(existingUser.cursor, cursor)) {
              hasChanged = true;
            }

            // Compare selection
            if (!areSelectionsEqual(existingUser.selection, selection)) {
              hasChanged = true;
            }

            // Compare lastSeen
            if (existingUser.lastSeen !== lastSeen) {
              hasChanged = true;
            }

            // Only update if something changed
            // If not changed, Immer preserves the existing reference
            if (hasChanged) {
              draft.cursorsMap.set(clientId, {
                clientId,
                user: userData,
                cursor,
                selection,
                lastSeen,
              });
            }
          } else {
            // New user - add to map
            draft.cursorsMap.set(clientId, {
              clientId,
              user: userData,
              cursor,
              selection,
              lastSeen,
            });
          }
        } catch (error) {
          logger.warn('Invalid user data for client', clientId, error);
        }
      });

      // Remove users that are no longer in awareness
      const entriesToDelete: number[] = [];
      draft.cursorsMap.forEach((_, clientId) => {
        if (!seenClientIds.has(clientId)) {
          entriesToDelete.push(clientId);
        }
      });
      entriesToDelete.forEach(clientId => {
        draft.cursorsMap.delete(clientId);
      });

      // Rebuild users array from cursorsMap for compatibility
      // Sort by name for consistent ordering
      draft.users = Array.from(draft.cursorsMap.values()).sort((a, b) =>
        a.user.name.localeCompare(b.user.name)
      );

      draft.lastUpdated = Date.now();
    });
    notify('awarenessChange');
  };

  // =============================================================================
  // PATTERN 2: Direct Immer → Notify + Awareness Update (Local Commands)
  // =============================================================================

  /**
   * Initialize awareness instance and set up observers
   */
  const initializeAwareness = (
    awareness: Awareness,
    userData: LocalUserData
  ) => {
    logger.debug('Initializing awareness', { userData });

    awarenessInstance = awareness;

    // Set up awareness with user data
    awareness.setLocalStateField('user', userData);
    awareness.setLocalStateField('lastSeen', Date.now());

    // Set up awareness observer for Pattern 1 updates
    awareness.on('change', handleAwarenessChange);

    // Update local state
    state = produce(state, draft => {
      draft.localUser = userData;
      draft.rawAwareness = awareness;
      draft.isInitialized = true;
      draft.isConnected = true;
      draft.lastUpdated = Date.now();
    });

    // Initial sync of users
    handleAwarenessChange();

    devtools.connect();
    notify('initializeAwareness');
  };

  /**
   * Clean up awareness instance
   */
  const destroyAwareness = () => {
    logger.debug('Destroying awareness');

    if (awarenessInstance) {
      awarenessInstance.off('change', handleAwarenessChange);
      awarenessInstance = null;
    }

    if (lastSeenTimer) {
      clearInterval(lastSeenTimer);
      lastSeenTimer = null;
    }

    devtools.disconnect();

    state = produce(state, draft => {
      draft.users = [];
      draft.cursorsMap.clear();
      draft.localUser = null;
      draft.rawAwareness = null;
      draft.isInitialized = false;
      draft.isConnected = false;
      draft.lastUpdated = Date.now();
    });
    notify('destroyAwareness');
  };

  /**
   * Update local user data in awareness
   */
  const updateLocalUserData = (userData: Partial<LocalUserData>) => {
    if (!awarenessInstance || !state.localUser) {
      logger.warn('Cannot update user data - awareness not initialized');
      return;
    }

    const updatedUserData = { ...state.localUser, ...userData };

    // Update awareness first
    awarenessInstance.setLocalStateField('user', updatedUserData);

    // Update local state for immediate UI response
    state = produce(state, draft => {
      draft.localUser = updatedUserData;
    });
    notify('updateLocalUserData');

    // Note: awareness observer will also fire and update the users array
  };

  /**
   * Update local cursor position
   */
  const updateLocalCursor = (cursor: { x: number; y: number } | null) => {
    if (!awarenessInstance) {
      logger.warn('Cannot update cursor - awareness not initialized');
      return;
    }

    // Update awareness
    awarenessInstance.setLocalStateField('cursor', cursor);

    // Immediate local state update for responsiveness
    state = produce(state, draft => {
      if (draft.localUser) {
        const localUserIndex = draft.users.findIndex(
          u => u.user.id === draft.localUser?.id
        );
        if (localUserIndex !== -1 && draft.users[localUserIndex]) {
          if (cursor) {
            draft.users[localUserIndex].cursor = cursor;
          } else {
            delete draft.users[localUserIndex].cursor;
          }
        }
      }
    });
    notify('updateLocalCursor');
  };

  /**
   * Update local text selection
   */
  const updateLocalSelection = (
    selection: AwarenessUser['selection'] | null
  ) => {
    if (!awarenessInstance) {
      logger.warn('Cannot update selection - awareness not initialized');
      return;
    }

    // Update awareness
    awarenessInstance.setLocalStateField('selection', selection);

    // Immediate local state update for responsiveness
    state = produce(state, draft => {
      if (draft.localUser) {
        const localUserIndex = draft.users.findIndex(
          u => u.user.id === draft.localUser?.id
        );
        if (localUserIndex !== -1 && draft.users[localUserIndex]) {
          if (selection) {
            draft.users[localUserIndex].selection = selection;
          } else {
            delete draft.users[localUserIndex].selection;
          }
        }
      }
    });
    notify('updateLocalSelection');
  };

  /**
   * Update last seen timestamp
   */
  const updateLastSeen = () => {
    if (!awarenessInstance) {
      return;
    }

    const timestamp = Date.now();
    awarenessInstance.setLocalStateField('lastSeen', timestamp);

    // Note: We don't update local state here as awareness observer will handle it
  };

  /**
   * Set up automatic last seen updates
   */
  const setupLastSeenTimer = () => {
    if (lastSeenTimer) {
      clearInterval(lastSeenTimer);
    }

    lastSeenTimer = setInterval(() => {
      updateLastSeen();
    }, 10000); // Update every 10 seconds

    return () => {
      if (lastSeenTimer) {
        clearInterval(lastSeenTimer);
        lastSeenTimer = null;
      }
    };
  };

  // =============================================================================
  // PATTERN 3: Direct Immer → Notify (Local UI State)
  // =============================================================================

  /**
   * Set connection state
   */
  const setConnected = (isConnected: boolean) => {
    state = produce(state, draft => {
      draft.isConnected = isConnected;
    });
    notify('setConnected');
  };

  // =============================================================================
  // QUERY HELPERS (CQS Pattern)
  // =============================================================================

  const getAllUsers = (): AwarenessUser[] => state.users;

  const getRemoteUsers = (): AwarenessUser[] => {
    if (!state.localUser) return state.users;

    return state.users.filter(user => user.user.id !== state.localUser?.id);
  };

  const getLocalUser = (): LocalUserData | null => state.localUser;

  const getUserById = (userId: string): AwarenessUser | null => {
    return state.users.find(user => user.user.id === userId) || null;
  };

  const getUserByClientId = (clientId: number): AwarenessUser | null => {
    return state.users.find(user => user.clientId === clientId) || null;
  };

  const isAwarenessReady = (): boolean => {
    return state.isInitialized && state.rawAwareness !== null;
  };

  const getConnectionState = (): boolean => state.isConnected;

  const getRawAwareness = (): Awareness | null => state.rawAwareness;

  // =============================================================================
  // PUBLIC INTERFACE
  // =============================================================================

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Commands (CQS pattern)
    initializeAwareness,
    destroyAwareness,
    updateLocalUserData,
    updateLocalCursor,
    updateLocalSelection,
    updateLastSeen,
    setConnected,

    // Queries (CQS pattern)
    getAllUsers,
    getRemoteUsers,
    getLocalUser,
    getUserById,
    getUserByClientId,
    isAwarenessReady,
    getConnectionState,
    getRawAwareness,

    // Internal methods (for SessionProvider integration)
    _internal: {
      handleAwarenessChange,
      setupLastSeenTimer,
    },
  };
};

export type AwarenessStoreInstance = ReturnType<typeof createAwarenessStore>;
