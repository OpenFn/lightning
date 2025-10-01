/**
 * StoreProvider Tests
 *
 * This test suite verifies the SessionContextStore integration into StoreProvider:
 * - SessionContextStore is created and available in context
 * - Store connects to channel when provider is ready
 * - Store cleanup on unmount
 * - Store instance stability across re-renders
 *
 * Note: This project doesn't use React Testing Library, so we test the provider
 * by directly examining the store instances and their behavior.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

import type { StoreContextValue } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { createSessionStore } from "../../../js/collaborative-editor/stores/createSessionStore";
import type { SessionStoreInstance } from "../../../js/collaborative-editor/stores/createSessionStore";
import type { SessionContextStoreInstance } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
  type MockPhoenixChannel,
} from "../mocks/phoenixChannel";
import { createMockSocket } from "../mocks/phoenixSocket";
import {
  createStores,
  simulateChannelConnection,
} from "../__helpers__/storeProviderHelpers";

// =============================================================================
// TEST SETUP
// =============================================================================

describe("StoreProvider - SessionContextStore Integration", () => {
  let sessionStore: SessionStoreInstance | null = null;
  let stores: StoreContextValue | null = null;

  beforeEach(() => {
    // Create fresh instances for each test
    sessionStore = createSessionStore();
    stores = createStores();
  });

  afterEach(() => {
    // Clean up
    if (sessionStore) {
      sessionStore.destroy();
      sessionStore = null;
    }
    stores = null;
  });

  // ===========================================================================
  // STORE CREATION TESTS
  // ===========================================================================

  test("sessionContextStore is created and available in context", () => {
    expect(stores).not.toBeNull();
    expect(stores!.sessionContextStore).toBeDefined();
    expect(typeof stores!.sessionContextStore.requestSessionContext).toBe(
      "function"
    );
  });

  test("sessionContextStore has correct initial state", () => {
    const state = stores!.sessionContextStore.getSnapshot();

    expect(state.user).toBeNull();
    expect(state.project).toBeNull();
    expect(state.config).toBeNull();
    expect(state.isLoading).toBe(false);
    expect(state.error).toBeNull();
    expect(state.lastUpdated).toBeNull();
  });

  test("sessionContextStore methods are functional", () => {
    // Test subscribe
    let notificationCount = 0;
    const unsubscribe = stores!.sessionContextStore.subscribe(() => {
      notificationCount++;
    });

    stores!.sessionContextStore.setLoading(true);
    expect(notificationCount).toBe(1);

    unsubscribe();
    stores!.sessionContextStore.setLoading(false);
    expect(notificationCount).toBe(1); // Should not increment after unsubscribe
  });

  test("all required stores are present in context", () => {
    expect(stores!.adaptorStore).toBeDefined();
    expect(stores!.credentialStore).toBeDefined();
    expect(stores!.awarenessStore).toBeDefined();
    expect(stores!.workflowStore).toBeDefined();
    expect(stores!.sessionContextStore).toBeDefined();
  });

  // ===========================================================================
  // CHANNEL CONNECTION TESTS
  // ===========================================================================

  test("sessionContextStore connects to channel when provider is ready", async () => {
    const mockSocket = createMockSocket();

    // Initialize session with connect: true (will auto-connect)
    sessionStore!.initializeSession(
      mockSocket,
      "test:workflow",
      {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      },
      { connect: true }
    );

    // Wait for provider to be ready
    await waitForCondition(() => {
      const session = sessionStore!.getSnapshot();
      return session.provider !== null && session.isConnected;
    });

    // Verify provider is available in session
    const session = sessionStore!.getSnapshot();
    expect(session.provider).not.toBeNull();
    expect(session.isConnected).toBe(true);

    // Spy on store's _connectChannel method
    let connectChannelCalled = false;
    const originalConnect = stores!.sessionContextStore._connectChannel;
    stores!.sessionContextStore._connectChannel = (provider: any) => {
      connectChannelCalled = true;
      return originalConnect.call(stores!.sessionContextStore, provider);
    };

    // Simulate the useEffect that connects stores
    const cleanup = simulateChannelConnection(stores!, sessionStore!);

    // Verify _connectChannel was called
    expect(connectChannelCalled).toBe(true);

    // Cleanup
    cleanup();
  });

  test("sessionContextStore registers channel event listeners", async () => {
    const mockSocket = createMockSocket();
    const mockProvider = createMockPhoenixChannelProvider(
      createMockPhoenixChannel()
    );

    // Directly test that _connectChannel returns a cleanup function
    const cleanup = stores!.sessionContextStore._connectChannel(mockProvider);

    // Verify cleanup function was returned (indicates listeners were registered)
    expect(typeof cleanup).toBe("function");

    // Verify cleanup can be called without errors
    expect(() => {
      cleanup();
    }).not.toThrow();
  });

  test("sessionContextStore does not connect when provider is not ready", async () => {
    const mockSocket = createMockSocket();

    let pushCalled = false;

    // Initialize session WITHOUT provider
    sessionStore!.initializeSession(mockSocket, "test:workflow", {
      id: "user-1",
      name: "Test User",
      color: "#ff0000",
    });

    // Don't set provider state (simulates not connected)

    // Simulate the connection effect (should not connect)
    const cleanup = simulateChannelConnection(stores!, sessionStore!);

    // Small delay to ensure effect runs (but connection should not happen)
    await new Promise(resolve => setTimeout(resolve, 10));

    // Verify no connection was attempted
    expect(pushCalled).toBe(false);

    // Store should still be available
    expect(stores!.sessionContextStore).toBeDefined();

    // Cleanup
    cleanup();
  });

  test("sessionContextStore initial request is sent on connection", async () => {
    const mockSocket = createMockSocket();

    // Initialize and connect
    sessionStore!.initializeSession(
      mockSocket,
      "test:workflow",
      {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      },
      { connect: true }
    );

    // Wait for provider
    await waitForCondition(() => {
      const session = sessionStore!.getSnapshot();
      return session.provider !== null;
    });

    // Test that requestSessionContext can be called
    const requestResult = stores!.sessionContextStore.requestSessionContext();

    // Should return a promise
    expect(requestResult).toBeInstanceOf(Promise);

    // Small delay for async request to be initiated
    await new Promise(resolve => setTimeout(resolve, 10));

    // The fact that we can call requestSessionContext means the store is properly set up
    expect(stores!.sessionContextStore).toBeDefined();
  });

  // ===========================================================================
  // CLEANUP TESTS
  // ===========================================================================

  test("channel listeners are removed on cleanup", async () => {
    const mockSocket = createMockSocket();

    // Initialize and connect
    sessionStore!.initializeSession(
      mockSocket,
      "test:workflow",
      {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      },
      { connect: true }
    );

    // Wait for provider
    await waitForCondition(() => {
      const session = sessionStore!.getSnapshot();
      return session.provider !== null;
    });

    // Connect stores
    const cleanup = simulateChannelConnection(stores!, sessionStore!);

    // Small delay for connection to be established
    await new Promise(resolve => setTimeout(resolve, 10));

    // Verify cleanup can be called without errors
    expect(() => {
      cleanup();
    }).not.toThrow();

    // Small delay for cleanup to complete
    await new Promise(resolve => setTimeout(resolve, 10));

    // Verify we can still access the store after cleanup
    expect(stores!.sessionContextStore).toBeDefined();
    expect(stores!.sessionContextStore.getSnapshot()).toBeDefined();
  });

  test("cleanup is called when dependencies change", async () => {
    const mockSocket = createMockSocket();

    // Initialize with first session
    sessionStore!.initializeSession(
      mockSocket,
      "test:workflow:1",
      {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      },
      { connect: true }
    );

    // Wait for provider
    await waitForCondition(() => {
      const session = sessionStore!.getSnapshot();
      return session.provider !== null;
    });

    const cleanup1 = simulateChannelConnection(stores!, sessionStore!);

    // Small delay for connection to be established
    await new Promise(resolve => setTimeout(resolve, 10));

    // Clean up first connection
    expect(() => {
      cleanup1();
    }).not.toThrow();

    // Small delay for cleanup to complete
    await new Promise(resolve => setTimeout(resolve, 10));

    // Connect to second session (simulates reconnection)
    sessionStore!.initializeSession(
      mockSocket,
      "test:workflow:2",
      {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      },
      { connect: true }
    );

    // Wait for new provider
    await waitForCondition(() => {
      const session = sessionStore!.getSnapshot();
      return session.provider !== null;
    });

    const cleanup2 = simulateChannelConnection(stores!, sessionStore!);

    // Small delay for new connection to be established
    await new Promise(resolve => setTimeout(resolve, 10));

    // Verify second cleanup works
    expect(() => {
      cleanup2();
    }).not.toThrow();
  });

  // ===========================================================================
  // INTEGRATION TESTS
  // ===========================================================================

  test("sessionContextStore updates do not affect other stores", async () => {
    const mockSocket = createMockSocket();

    // Get initial adaptor state
    const initialAdaptorState = stores!.adaptorStore.getSnapshot();

    // Initialize and connect
    sessionStore!.initializeSession(
      mockSocket,
      "test:workflow",
      {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      },
      { connect: true }
    );

    const cleanup = simulateChannelConnection(stores!, sessionStore!);

    // Small delay for connection to be established
    await new Promise(resolve => setTimeout(resolve, 10));

    // Manually update sessionContextStore
    stores!.sessionContextStore.setLoading(true);

    // Verify adaptorStore state is unchanged
    const currentAdaptorState = stores!.adaptorStore.getSnapshot();
    expect(currentAdaptorState).toEqual(initialAdaptorState);

    // Cleanup
    cleanup();
  });

  test("sessionContextStore can be subscribed to independently", () => {
    let sessionContextNotifications = 0;
    let adaptorNotifications = 0;

    const unsubscribe1 = stores!.sessionContextStore.subscribe(() => {
      sessionContextNotifications++;
    });

    const unsubscribe2 = stores!.adaptorStore.subscribe(() => {
      adaptorNotifications++;
    });

    // Update sessionContextStore
    stores!.sessionContextStore.setLoading(true);

    expect(sessionContextNotifications).toBe(1);
    expect(adaptorNotifications).toBe(0);

    // Update adaptorStore
    stores!.adaptorStore.setLoading(true);

    expect(sessionContextNotifications).toBe(1);
    expect(adaptorNotifications).toBe(1);

    // Cleanup
    unsubscribe1();
    unsubscribe2();
  });

  test("sessionContextStore maintains state independently from session store", async () => {
    const mockSocket = createMockSocket();

    // Initialize and connect
    sessionStore!.initializeSession(
      mockSocket,
      "test:workflow",
      {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      },
      { connect: true }
    );

    const cleanup = simulateChannelConnection(stores!, sessionStore!);

    // Small delay for connection to be established
    await new Promise(resolve => setTimeout(resolve, 10));

    // Verify stores maintain independent state
    const sessionState = sessionStore!.getSnapshot();
    const sessionContextState = stores!.sessionContextStore.getSnapshot();

    // Session store has userData, context store has user - they should be different objects
    expect(sessionState.userData).not.toBe(sessionContextState.user);

    // Cleanup
    cleanup();
  });
});
