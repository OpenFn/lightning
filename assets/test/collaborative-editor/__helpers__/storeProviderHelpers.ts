/**
 * Store Provider Test Helpers
 *
 * Utilities for testing the StoreProvider context and store integration patterns.
 * These helpers simulate the behavior of StoreProvider in tests, allowing for
 * isolated testing of store interactions without requiring full React component rendering.
 *
 * Usage:
 *   const { stores, cleanup } = simulateStoreProvider();
 *   // ... test store interactions
 *   cleanup();
 */

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { SessionStoreInstance } from '../../../js/collaborative-editor/stores/createSessionStore';
import { createSessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';
import { createCredentialStore } from '../../../js/collaborative-editor/stores/createCredentialStore';
import { createAwarenessStore } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';

import { createMockSocket } from '../mocks/phoenixSocket';
import { waitForAsync } from '../mocks/phoenixChannel';

/**
 * Result of simulating StoreProvider setup
 */
export interface StoreProviderSimulation {
  /** All stores in the context */
  stores: StoreContextValue;
  /** Session store instance */
  sessionStore: SessionStoreInstance;
  /** Cleanup function to call after test */
  cleanup: () => void;
}

/**
 * Result of simulating StoreProvider with channel connection
 */
export interface ConnectedStoreProviderSimulation
  extends StoreProviderSimulation {
  /** Additional cleanup for channel connections */
  channelCleanup: () => void;
}

/**
 * Creates a stores object matching StoreProvider's structure
 *
 * This factory creates all the stores that would normally be provided
 * by the StoreProvider context.
 *
 * @returns Object containing all store instances
 *
 * @example
 * const stores = createStores();
 * expect(stores.sessionContextStore).toBeDefined();
 * expect(stores.adaptorStore).toBeDefined();
 */
export function createStores(): StoreContextValue {
  return {
    adaptorStore: createAdaptorStore(),
    credentialStore: createCredentialStore(),
    awarenessStore: createAwarenessStore(),
    workflowStore: createWorkflowStore(),
    sessionContextStore: createSessionContextStore(),
  };
}

/**
 * Simulates the channel connection effect from StoreProvider
 *
 * This function replicates the useEffect logic in StoreProvider that connects
 * stores to the Phoenix channel when the session provider becomes available.
 *
 * @param stores - The stores to connect
 * @param sessionStore - The session store with provider
 * @returns Cleanup function to remove channel connections
 *
 * @example
 * const stores = createStores();
 * const sessionStore = createSessionStore();
 * sessionStore.initializeSession(socket, topic, userData);
 *
 * const cleanup = simulateChannelConnection(stores, sessionStore);
 * // ... test channel interactions
 * cleanup();
 */
export function simulateChannelConnection(
  stores: StoreContextValue,
  sessionStore: SessionStoreInstance
): () => void {
  const session = sessionStore.getSnapshot();

  if (session.provider && session.isConnected) {
    const cleanup1 = stores.adaptorStore._connectChannel(session.provider);
    const cleanup2 = stores.credentialStore._connectChannel(session.provider);
    const cleanup3 = stores.sessionContextStore._connectChannel(
      session.provider
    );

    return () => {
      cleanup1();
      cleanup2();
      cleanup3();
    };
  }

  return () => {};
}

/**
 * Simulates a complete StoreProvider setup without channel connection
 *
 * Creates all stores and session store, but does not initialize the session
 * or connect channels. Useful for testing store creation and initial state.
 *
 * @returns Simulation with stores and cleanup
 *
 * @example
 * test("store initialization", () => {
 *   const { stores, cleanup } = simulateStoreProvider();
 *
 *   expect(stores.sessionContextStore.getSnapshot().user).toBe(null);
 *
 *   cleanup();
 * });
 */
export function simulateStoreProvider(): StoreProviderSimulation {
  const stores = createStores();
  const sessionStore = createSessionStore();

  return {
    stores,
    sessionStore,
    cleanup: () => {
      sessionStore.destroy();
    },
  };
}

/**
 * Simulates a complete StoreProvider setup with connected session
 *
 * Creates all stores, initializes the session, and connects channels.
 * This provides a fully-configured environment for testing store interactions.
 *
 * @param roomTopic - Room topic for the session (defaults to "test:workflow")
 * @param userData - User data for awareness (defaults to test user)
 * @param options - Session initialization options
 * @returns Simulation with stores, connected channels, and cleanup
 *
 * @example
 * test("store channel integration", async () => {
 *   const { stores, channelCleanup, cleanup } =
 *     await simulateStoreProviderWithConnection();
 *
 *   // Test store behavior with active channels
 *   await stores.sessionContextStore.requestSessionContext();
 *
 *   channelCleanup();
 *   cleanup();
 * });
 */
export async function simulateStoreProviderWithConnection(
  roomTopic: string = 'test:workflow',
  userData?: { id: string; name: string; color: string },
  options?: { connect?: boolean }
): Promise<ConnectedStoreProviderSimulation> {
  const stores = createStores();
  const sessionStore = createSessionStore();
  const mockSocket = createMockSocket();

  const defaultUserData = userData || {
    id: 'user-1',
    name: 'Test User',
    color: '#ff0000',
  };

  // Initialize session with connect: true by default
  sessionStore.initializeSession(mockSocket, roomTopic, defaultUserData, {
    connect: true,
    ...options,
  });

  // Wait for provider to be ready
  await waitForAsync(100);

  // Connect stores to channel
  const channelCleanup = simulateChannelConnection(stores, sessionStore);

  return {
    stores,
    sessionStore,
    channelCleanup,
    cleanup: () => {
      sessionStore.destroy();
    },
  };
}

/**
 * Verifies that all expected stores are present and properly initialized
 *
 * Helper for testing that StoreProvider creates all required stores.
 *
 * @param stores - The stores object to verify
 *
 * @example
 * const { stores } = simulateStoreProvider();
 * verifyAllStoresPresent(stores);
 */
export function verifyAllStoresPresent(stores: StoreContextValue): void {
  expect(stores.adaptorStore).toBeDefined();
  expect(stores.credentialStore).toBeDefined();
  expect(stores.awarenessStore).toBeDefined();
  expect(stores.workflowStore).toBeDefined();
  expect(stores.sessionContextStore).toBeDefined();

  // Verify each store has the expected interface
  [
    stores.adaptorStore,
    stores.credentialStore,
    stores.sessionContextStore,
  ].forEach(store => {
    expect(typeof store.subscribe).toBe('function');
    expect(typeof store.getSnapshot).toBe('function');
    expect(typeof store.withSelector).toBe('function');
  });
}

/**
 * Verifies that store instances are independent
 *
 * Ensures that each store is a separate instance with its own state.
 *
 * @param stores - The stores object to verify
 *
 * @example
 * const { stores } = simulateStoreProvider();
 * verifyStoresAreIndependent(stores);
 */
export function verifyStoresAreIndependent(stores: StoreContextValue): void {
  // Verify all stores are different instances
  expect(stores.adaptorStore).not.toBe(stores.sessionContextStore);
  expect(stores.credentialStore).not.toBe(stores.sessionContextStore);
  expect(stores.awarenessStore).not.toBe(stores.sessionContextStore);
  expect(stores.workflowStore).not.toBe(stores.sessionContextStore);
  expect(stores.adaptorStore).not.toBe(stores.credentialStore);

  // Verify each store has its own state
  const sessionContextState = stores.sessionContextStore.getSnapshot();
  const adaptorState = stores.adaptorStore.getSnapshot();

  expect(sessionContextState).not.toBe(adaptorState);
}

/**
 * Tests that store updates do not affect other stores
 *
 * Helper for verifying store isolation.
 *
 * @param stores - The stores object to test
 *
 * @example
 * const { stores, cleanup } = simulateStoreProvider();
 * testStoreIsolation(stores);
 * cleanup();
 */
export function testStoreIsolation(stores: StoreContextValue): void {
  // Get initial states
  const initialAdaptorState = stores.adaptorStore.getSnapshot();
  const initialCredentialState = stores.credentialStore.getSnapshot();

  // Update one store
  stores.sessionContextStore.setLoading(true);

  // Verify other stores are unchanged
  const currentAdaptorState = stores.adaptorStore.getSnapshot();
  const currentCredentialState = stores.credentialStore.getSnapshot();

  expect(currentAdaptorState).toEqual(initialAdaptorState);
  expect(currentCredentialState).toEqual(initialCredentialState);
}

/**
 * Tests that stores can be subscribed to independently
 *
 * Helper for verifying that each store has its own subscription mechanism.
 *
 * @param stores - The stores object to test
 * @returns Cleanup function to unsubscribe all listeners
 *
 * @example
 * const { stores, cleanup: providerCleanup } = simulateStoreProvider();
 * const subscriptionCleanup = testIndependentSubscriptions(stores);
 *
 * // ... run tests
 *
 * subscriptionCleanup();
 * providerCleanup();
 */
export function testIndependentSubscriptions(
  stores: StoreContextValue
): () => void {
  let sessionContextNotifications = 0;
  let adaptorNotifications = 0;

  const unsubscribe1 = stores.sessionContextStore.subscribe(() => {
    sessionContextNotifications++;
  });

  const unsubscribe2 = stores.adaptorStore.subscribe(() => {
    adaptorNotifications++;
  });

  // Update sessionContextStore
  stores.sessionContextStore.setLoading(true);

  expect(sessionContextNotifications).toBe(1);
  expect(adaptorNotifications).toBe(0);

  // Update adaptorStore
  stores.adaptorStore.setLoading(true);

  expect(sessionContextNotifications).toBe(1);
  expect(adaptorNotifications).toBe(1);

  // Return cleanup function
  return () => {
    unsubscribe1();
    unsubscribe2();
  };
}

/**
 * Simulates multiple store provider lifecycle events
 *
 * Useful for testing reconnection, unmount/remount scenarios.
 *
 * @returns Object with helper functions for lifecycle simulation
 *
 * @example
 * const lifecycle = simulateProviderLifecycle();
 *
 * const setup1 = await lifecycle.mount();
 * // ... test with first mount
 * lifecycle.unmount(setup1);
 *
 * const setup2 = await lifecycle.mount();
 * // ... test with second mount
 * lifecycle.unmount(setup2);
 */
export function simulateProviderLifecycle() {
  const activeMounts: ConnectedStoreProviderSimulation[] = [];

  return {
    /**
     * Simulates mounting the StoreProvider
     */
    async mount(
      roomTopic: string = 'test:workflow',
      userData?: { id: string; name: string; color: string }
    ): Promise<ConnectedStoreProviderSimulation> {
      const simulation = await simulateStoreProviderWithConnection(
        roomTopic,
        userData
      );
      activeMounts.push(simulation);
      return simulation;
    },

    /**
     * Simulates unmounting the StoreProvider
     */
    unmount(simulation: ConnectedStoreProviderSimulation): void {
      simulation.channelCleanup();
      simulation.cleanup();

      const index = activeMounts.indexOf(simulation);
      if (index > -1) {
        activeMounts.splice(index, 1);
      }
    },

    /**
     * Cleans up all active mounts
     */
    unmountAll(): void {
      activeMounts.forEach(simulation => {
        simulation.channelCleanup();
        simulation.cleanup();
      });
      activeMounts.length = 0;
    },
  };
}
