/**
 * Session Store Test Helpers
 *
 * Utility functions for testing session store functionality, including helpers
 * for triggering provider events, applying updates, and waiting for state changes.
 *
 * These helpers were extracted from createSessionStore.test.ts to promote
 * reusability across test files.
 *
 * Usage:
 *   const socket = createMockSocket();
 *   await waitForState(store, state => state.isConnected);
 *   triggerProviderSync(store, true);
 */

import { Doc as YDoc, applyUpdate, encodeStateAsUpdate } from 'yjs';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import { expect } from 'vitest';

import type { SessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import type { SessionState } from '../../../js/collaborative-editor/stores/createSessionStore';

import { createMockSocket as baseCreateMockSocket } from '../mocks/phoenixSocket';
import {
  createMockPhoenixChannel as baseCreateMockPhoenixChannel,
  waitForAsync,
} from '../mocks/phoenixChannel';

// Re-export commonly used utilities
export { waitForAsync };

/**
 * Creates a mock Phoenix socket for session store tests
 *
 * @returns Mock socket instance
 *
 * @example
 * const socket = createMockSocket();
 * store.initializeSession(socket, "room:123", userData);
 */
export function createMockSocket() {
  return baseCreateMockSocket();
}

/**
 * Creates a mock Phoenix channel for session store tests
 *
 * @param topic - Channel topic (defaults to "test:channel")
 * @returns Mock channel instance
 *
 * @example
 * const channel = createMockPhoenixChannel("workflow:123");
 */
export function createMockPhoenixChannel(topic: string = 'test:channel') {
  return baseCreateMockPhoenixChannel(topic);
}

/**
 * Triggers a sync event on the session store's provider
 *
 * Simulates the provider emitting a sync event, which indicates whether
 * the local document is synchronized with the server.
 *
 * @param store - The session store instance
 * @param synced - Whether the provider is synced
 *
 * @example
 * triggerProviderSync(store, true);
 * expect(store.getSnapshot().isSynced).toBe(true);
 */
export function triggerProviderSync(
  store: SessionStore,
  synced: boolean
): void {
  if (!store.provider) {
    throw new Error('Cannot trigger sync: provider not initialized');
  }
  store.provider.emit('sync', [synced]);
}

/**
 * Triggers a status change event on the session store's provider
 *
 * Simulates the provider changing connection status.
 *
 * @param store - The session store instance
 * @param status - The new connection status
 *
 * @example
 * triggerProviderStatus(store, "connected");
 * expect(store.getSnapshot().isConnected).toBe(true);
 */
export function triggerProviderStatus(
  store: SessionStore,
  status: 'connected' | 'disconnected' | 'connecting'
): void {
  if (!store.provider) {
    throw new Error('Cannot trigger status: provider not initialized');
  }
  store.provider.emit('status', [{ status }]);
}

/**
 * Applies a test update to a YDoc through a provider
 *
 * Creates a temporary YDoc with test data and applies its state as an
 * update to the target document, simulating a remote update.
 *
 * @param ydoc - The YDoc to update
 * @param provider - The provider through which to apply the update
 *
 * @example
 * const ydoc = store.getYDoc();
 * const provider = store.getProvider();
 * applyProviderUpdate(ydoc, provider);
 */
export function applyProviderUpdate(
  ydoc: YDoc,
  provider: PhoenixChannelProvider
): void {
  // Create a temporary document with some test data
  const doc2 = new YDoc();
  doc2.getArray('test').insert(0, ['hello']);

  // Encode and apply the update
  const update = encodeStateAsUpdate(doc2);
  applyUpdate(ydoc, update, provider);
}

/**
 * Waits for a specific state condition to become true
 *
 * Subscribes to store changes and resolves when the callback returns true.
 * Rejects with a timeout error if the condition is not met within the timeout period.
 *
 * @param store - The session store instance
 * @param callback - Function that returns true when desired state is reached
 * @param timeout - Timeout in milliseconds (defaults to 200ms)
 * @returns Promise that resolves when condition is met
 *
 * @example
 * await waitForState(store, state => state.isConnected);
 *
 * @example
 * await waitForState(
 *   store,
 *   state => state.isSynced && state.settled,
 *   500
 * );
 */
export async function waitForState(
  store: SessionStore,
  callback: (state: SessionState) => boolean,
  timeout: number = 200
): Promise<boolean> {
  // Capture stack trace for better error messages
  const stack = new Error().stack;

  return new Promise((resolve, reject) => {
    // Check if condition is already met
    if (callback(store.getSnapshot())) {
      resolve(true);
      return;
    }

    const timeoutId = setTimeout(() => {
      unsubscribe();
      const error = new Error(
        `Timeout waiting for state after ${timeout}ms. Current state: ${JSON.stringify(store.getSnapshot())}`
      );
      error.stack = stack;
      reject(error);
    }, timeout);

    const unsubscribe = store.subscribe(() => {
      try {
        const result = callback(store.getSnapshot());
        if (result) {
          unsubscribe();
          clearTimeout(timeoutId);
          resolve(result);
        }
      } catch (error) {
        unsubscribe();
        clearTimeout(timeoutId);
        reject(error);
      }
    });
  });
}

/**
 * Waits for the store to be fully connected and synced
 *
 * Convenience wrapper around waitForState for the common case of waiting
 * for a session to be ready.
 *
 * @param store - The session store instance
 * @param timeout - Timeout in milliseconds (defaults to 200ms)
 * @returns Promise that resolves when session is ready
 *
 * @example
 * store.initializeSession(socket, topic, userData);
 * await waitForSessionReady(store);
 * // Store is now connected and synced
 */
export async function waitForSessionReady(
  store: SessionStore,
  timeout: number = 200
): Promise<boolean> {
  return waitForState(
    store,
    state => state.isConnected && state.isSynced && state.settled,
    timeout
  );
}

/**
 * Creates a test YDoc with sample data
 *
 * Useful for testing document operations without needing to set up
 * a full session.
 *
 * @param data - Optional initial data to populate
 * @returns Initialized YDoc instance
 *
 * @example
 * const ydoc = createTestYDoc({ name: "Test Workflow" });
 */
export function createTestYDoc(data?: Record<string, any>): YDoc {
  const ydoc = new YDoc();

  if (data) {
    const map = ydoc.getMap('test');
    Object.entries(data).forEach(([key, value]) => {
      map.set(key, value);
    });
  }

  return ydoc;
}

/**
 * Extracts the current state of a YDoc as a plain object
 *
 * Useful for assertions in tests.
 *
 * @param ydoc - The YDoc to extract data from
 * @param mapName - Name of the map to extract (defaults to "test")
 * @returns Plain object representation of the map
 *
 * @example
 * const data = extractYDocData(ydoc);
 * expect(data.name).toBe("Test Workflow");
 */
export function extractYDocData(
  ydoc: YDoc,
  mapName: string = 'test'
): Record<string, any> {
  const map = ydoc.getMap(mapName);
  const result: Record<string, any> = {};

  map.forEach((value, key) => {
    result[key] = value;
  });

  return result;
}

/**
 * Simulates a remote user joining the session
 *
 * Creates awareness state for a new user.
 *
 * @param store - The session store instance
 * @param clientId - Client ID for the new user
 * @param userData - User data (name, color, etc.)
 *
 * @example
 * simulateRemoteUserJoin(store, 123, {
 *   id: "user-2",
 *   name: "Remote User",
 *   color: "#00ff00"
 * });
 */
export function simulateRemoteUserJoin(
  store: SessionStore,
  clientId: number,
  userData: { id: string; name: string; color: string }
): void {
  const awareness = store.getAwareness();
  if (!awareness) {
    throw new Error('Cannot simulate remote user: awareness not initialized');
  }

  awareness.setLocalStateField('user', userData);
}

/**
 * Simulates a remote user leaving the session
 *
 * Removes awareness state for a user.
 *
 * @param store - The session store instance
 * @param clientId - Client ID of the user leaving
 *
 * @example
 * simulateRemoteUserLeave(store, 123);
 */
export function simulateRemoteUserLeave(
  store: SessionStore,
  clientId: number
): void {
  const awareness = store.getAwareness();
  if (!awareness) {
    throw new Error('Cannot simulate remote leave: awareness not initialized');
  }

  // In real Yjs, this would be handled by the awareness protocol
  // For testing, we can manipulate the states map directly
  awareness.meta.delete(clientId);
  awareness.states.delete(clientId);
  awareness.emit('change', [
    { added: [], updated: [], removed: [clientId] },
    'local',
  ]);
}

/**
 * Asserts that awareness is "clean" (userData in state, not in awareness)
 *
 * This helper verifies the key invariant: userData is stored in session state
 * instead of awareness local state. This prevents userData from being broadcast
 * to other clients.
 *
 * @param state - The session state to check
 * @param expectedUserData - Expected userData value (or null)
 *
 * @example
 * const state = store.getSnapshot();
 * assertCleanAwareness(state, { id: "user-1", name: "Test", color: "#ff0000" });
 */
export function assertCleanAwareness(
  state: SessionState,
  expectedUserData: { id: string; name: string; color: string } | null
): void {
  expect(state.userData).toEqual(expectedUserData);
  if (expectedUserData) {
    const awarenessUserData = state.awareness?.getLocalState()?.user;
    expect(awarenessUserData).toBe(undefined);
  }
}
