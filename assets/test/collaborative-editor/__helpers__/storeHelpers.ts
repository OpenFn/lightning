/**
 * Store Setup Helpers
 *
 * Factory functions for setting up store instances with common configurations
 * in tests. These helpers consolidate repetitive store initialization and
 * cleanup logic.
 *
 * Usage:
 *   const { store, mockChannel, cleanup } = setupAdaptorStoreTest();
 *   // ... run test
 *   cleanup();
 */

import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';
import { createSessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';

import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  type MockPhoenixChannel,
  type MockPhoenixChannelProvider,
} from './channelMocks';

/**
 * Result of setting up an adaptor store test
 */
export interface AdaptorStoreTestSetup {
  /** The adaptor store instance */
  store: ReturnType<typeof createAdaptorStore>;
  /** Mock Phoenix channel */
  mockChannel: MockPhoenixChannel;
  /** Mock channel provider */
  mockProvider: MockPhoenixChannelProvider;
  /** Cleanup function to call after test */
  cleanup: () => void;
}

/**
 * Sets up an adaptor store test with a connected mock channel
 *
 * This helper creates all the necessary mocks and connects them together,
 * providing a consistent starting point for adaptor store tests.
 *
 * @param topic - Optional channel topic (defaults to "test:channel")
 * @returns Test setup with store, mocks, and cleanup function
 *
 * @example
 * test("adaptor store functionality", async () => {
 *   const { store, mockChannel, cleanup } = setupAdaptorStoreTest();
 *
 *   // Configure channel responses
 *   mockChannel.push = () => createMockPushWithResponse("ok", { adaptors: [] });
 *
 *   // Test store behavior
 *   await store.requestAdaptors();
 *
 *   // Cleanup
 *   cleanup();
 * });
 */
export function setupAdaptorStoreTest(
  topic: string = 'test:channel'
): AdaptorStoreTestSetup {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel(topic);
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Connect the channel to the store
  const channelCleanup = store._connectChannel(mockProvider);

  return {
    store,
    mockChannel,
    mockProvider,
    cleanup: () => {
      channelCleanup();
    },
  };
}

/**
 * Result of setting up a session context store test
 */
export interface SessionContextStoreTestSetup {
  /** The session context store instance */
  store: ReturnType<typeof createSessionContextStore>;
  /** Mock Phoenix channel */
  mockChannel: MockPhoenixChannel;
  /** Mock channel provider */
  mockProvider: MockPhoenixChannelProvider;
  /** Cleanup function to call after test */
  cleanup: () => void;
}

/**
 * Sets up a session context store test with a connected mock channel
 *
 * @param topic - Optional channel topic (defaults to "test:channel")
 * @returns Test setup with store, mocks, and cleanup function
 *
 * @example
 * test("session context store functionality", async () => {
 *   const { store, mockChannel, cleanup } = setupSessionContextStoreTest();
 *
 *   // Configure responses
 *   mockChannel.push = () => createMockPushWithResponse("ok", {
 *     user: mockUser,
 *     project: mockProject,
 *     config: mockConfig
 *   });
 *
 *   await store.requestSessionContext();
 *
 *   cleanup();
 * });
 */
export function setupSessionContextStoreTest(
  topic: string = 'test:channel'
): SessionContextStoreTestSetup {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel(topic);
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Connect the channel to the store
  const channelCleanup = store._connectChannel(mockProvider);

  return {
    store,
    mockChannel,
    mockProvider,
    cleanup: () => {
      channelCleanup();
    },
  };
}

/**
 * Result of setting up a session store test
 */
export interface SessionStoreTestSetup {
  /** The session store instance */
  store: ReturnType<typeof createSessionStore>;
  /** Mock Phoenix socket */
  mockSocket: ReturnType<any>;
  /** Cleanup function to call after test */
  cleanup: () => void;
}

/**
 * Sets up a session store test with initialized YDoc and provider
 *
 * This is more complex than other store setups because it involves
 * YDoc initialization and socket connection.
 *
 * @param roomTopic - Room topic for the session (defaults to "test:room")
 * @param userData - Optional user data for awareness
 * @returns Test setup with store, socket, and cleanup function
 *
 * @example
 * test("session store functionality", () => {
 *   const { store, mockSocket, cleanup } = setupSessionStoreTest("room:123", {
 *     id: "user-1",
 *     name: "Test User",
 *     color: "#ff0000"
 *   });
 *
 *   const state = store.getSnapshot();
 *   expect(state.isConnected).toBe(true);
 *
 *   cleanup();
 * });
 */
export function setupSessionStoreTest(
  roomTopic: string = 'test:room',
  userData?: { id: string; name: string; color: string }
): SessionStoreTestSetup {
  const store = createSessionStore();

  // Import createMockSocket dynamically to avoid circular dependencies
  const { createMockSocket } = require('../mocks/phoenixSocket');
  const mockSocket = createMockSocket();

  // Initialize session if userData provided
  if (userData) {
    store.initializeSession(mockSocket, roomTopic, userData);
  }

  return {
    store,
    mockSocket,
    cleanup: () => {
      store.destroy();
    },
  };
}

/**
 * Creates multiple stores and optionally connects them to a session
 *
 * This is useful for integration tests that need multiple stores working together.
 *
 * @param connectToSession - Whether to connect stores to a session
 * @returns Object containing all stores and cleanup function
 *
 * @example
 * test("multiple stores integration", () => {
 *   const { stores, cleanup } = setupMultipleStores(true);
 *
 *   // Test interactions between stores
 *   expect(stores.adaptorStore).toBeDefined();
 *   expect(stores.sessionContextStore).toBeDefined();
 *
 *   cleanup();
 * });
 */
export function setupMultipleStores(connectToSession: boolean = false): {
  stores: {
    adaptorStore: ReturnType<typeof createAdaptorStore>;
    sessionContextStore: ReturnType<typeof createSessionContextStore>;
    sessionStore: ReturnType<typeof createSessionStore>;
  };
  cleanup: () => void;
} {
  const adaptorStore = createAdaptorStore();
  const sessionContextStore = createSessionContextStore();
  const sessionStore = createSessionStore();

  const cleanupFunctions: Array<() => void> = [];

  if (connectToSession) {
    const { createMockSocket } = require('../mocks/phoenixSocket');
    const mockSocket = createMockSocket();

    sessionStore.initializeSession(mockSocket, 'test:room', {
      id: 'user-1',
      name: 'Test User',
      color: '#ff0000',
    });

    const session = sessionStore.getSnapshot();
    if (session.provider && session.isConnected) {
      cleanupFunctions.push(adaptorStore._connectChannel(session.provider));
      cleanupFunctions.push(
        sessionContextStore._connectChannel(session.provider)
      );
    }
  }

  return {
    stores: {
      adaptorStore,
      sessionContextStore,
      sessionStore,
    },
    cleanup: () => {
      cleanupFunctions.forEach(fn => fn());
      sessionStore.destroy();
    },
  };
}
