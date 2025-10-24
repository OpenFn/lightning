/**
 * Test Fixtures
 *
 * This file uses Vitest 3.x fixtures for cleaner test setup and automatic cleanup.
 *
 * Available fixtures:
 * - store: SessionStore instance (auto cleanup with destroy())
 * - mockSocket: Mock Phoenix socket
 * - initializedSession: Store with session initialized (depends on store and mockSocket)
 * - ydoc: YDoc instance initialized in the store
 *
 * Usage:
 * sessionTest("test name", async ({ initializedSession }) => {
 *   const { store, socket, userData } = initializedSession;
 *   // test logic - cleanup automatic
 * });
 */

import { describe, test, expect } from "vitest";
import { Doc as YDoc } from "yjs";

import {
  createSessionStore,
  type SessionState,
  type SessionStore,
} from "../../js/collaborative-editor/stores/createSessionStore";

import { createMockSocket } from "./mocks/phoenixSocket";
import type { PhoenixChannelProvider } from "y-phoenix-channel";
import {
  triggerProviderSync,
  triggerProviderStatus,
  applyProviderUpdate,
  waitForState,
  assertCleanAwareness,
} from "./__helpers__/sessionStoreHelpers";

// Vitest 3.x fixtures for cleaner test setup and automatic cleanup
const sessionTest = test.extend({
  store: async ({}, use) => {
    const store = createSessionStore();
    await use(store);
    store.destroy(); // Automatic cleanup
  },

  mockSocket: async ({}, use) => {
    const socket = createMockSocket();
    await use(socket);
  },

  initializedSession: async ({ store, mockSocket }, use) => {
    const userData = { id: "user-1", name: "Test User", color: "#ff0000" };
    store.initializeSession(mockSocket, "test:room", userData, {
      connect: false,
    });

    await use({ store, socket: mockSocket, userData });

    // Cleanup happens via store fixture
  },

  ydoc: async ({ store }, use) => {
    const ydoc = store.initializeYDoc();
    await use(ydoc);
    // Cleanup happens via store.destroy()
  },
});

describe("createSessionStore", () => {
  describe("core store interface", () => {
    test("getSnapshot returns initial state", () => {
      const store = createSessionStore();
      const initialState = store.getSnapshot();

      expect(initialState.ydoc).toBe(null);
      expect(initialState.provider).toBe(null);
      expect(initialState.awareness).toBe(null);
      expect(initialState.userData).toBe(null);
      expect(initialState.isConnected).toBe(false);
      expect(initialState.isSynced).toBe(false);
      expect(initialState.settled).toBe(false);
      expect(initialState.lastStatus).toBe(null);
    });

    test("subscribe/unsubscribe and selector work correctly", () => {
      const store = createSessionStore();
      let callCount = 0;
      const unsubscribe = store.subscribe(() => callCount++);

      // Trigger state changes and verify subscription
      store.initializeSession(createMockSocket(), "test:room", {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      });
      expect(callCount).toBe(1);

      unsubscribe();
      store.destroy();
      expect(callCount).toBe(1); // No call after unsubscribe

      // Verify selector referential stability
      const store2 = createSessionStore();
      const selectYdoc = store2.withSelector(state => state.ydoc);
      const newYDoc = store2.initializeYDoc();
      expect(selectYdoc()).toBe(newYDoc);
      expect(selectYdoc()).toBe(selectYdoc()); // Same reference
    });
  });

  describe("YDoc initialization", () => {
    test("creates new YDoc instance", () => {
      const store = createSessionStore();

      const ydoc = store.initializeYDoc();

      expect(ydoc).toBeInstanceOf(YDoc);
      expect(store.getSnapshot().ydoc).toBe(ydoc);
      expect(store.getYDoc()).toBe(ydoc);
    });

    test("cleans up YDoc instance on destroy", () => {
      const store = createSessionStore();

      store.initializeYDoc();

      store.destroyYDoc();

      expect(store.getSnapshot().ydoc).toBeNull();
      expect(store.getYDoc()).toBeNull();
    });

    test("handles null YDoc gracefully", () => {
      const store = createSessionStore();

      expect(() => {
        store.destroyYDoc();
      }).not.toThrow();
    });

    test("replaces previous YDoc on multiple initialization calls", () => {
      const store = createSessionStore();

      const firstYDoc = store.initializeYDoc();
      const secondYDoc = store.initializeYDoc();

      expect(firstYDoc).not.toBe(secondYDoc);
      expect(store.getSnapshot().ydoc).toBe(secondYDoc);
    });

    test("cleans up both YDoc and awareness", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

      store.initializeSession(mockSocket, "test:room", userData, {
        connect: false,
      });

      store.destroyYDoc();

      const finalState = store.getSnapshot();
      expect(finalState.ydoc).toBeNull();
      expect(finalState.awareness).toBeNull();
    });
  });

  describe("provider initialization", () => {
    sessionTest(
      "creates provider with correct state",
      ({ initializedSession, store, mockSocket }) => {
        const result = store.getSnapshot();
        expect(result.provider).toBeTruthy();
        expect(store.getProvider()).toBe(result.provider);
        expect(result.isSynced).toBe(result.provider.synced);

        // Verify provider replacement works
        const userData = { id: "user-2", name: "User 2", color: "#00ff00" };
        const secondResult = store.initializeSession(
          mockSocket,
          "test:room:456",
          userData,
          { connect: false }
        );
        expect(secondResult.provider).not.toBe(result.provider);
        expect(store.getSnapshot().provider).toBe(secondResult.provider);
      }
    );
  });

  describe("lifecycle", () => {
    sessionTest("performs complete cleanup", ({ initializedSession }) => {
      const { store } = initializedSession;
      const state = store.getSnapshot();
      let ydocDestroyed = false;
      let awarenessDestroyed = false;

      const originalDestroy = state.ydoc!.destroy;
      state.ydoc!.destroy = () => {
        ydocDestroyed = true;
        originalDestroy.call(state.ydoc);
      };

      const originalAwarenessDestroy = state.awareness!.destroy;
      state.awareness!.destroy = () => {
        awarenessDestroyed = true;
        originalAwarenessDestroy.call(state.awareness);
      };

      store.destroy();

      const afterState = store.getSnapshot();
      expect(afterState).toMatchObject({
        ydoc: null,
        provider: null,
        awareness: null,
        userData: null,
        isConnected: false,
        isSynced: false,
        lastStatus: null,
      });
      expect(ydocDestroyed).toBe(true);
      expect(awarenessDestroyed).toBe(true);
    });

    test("is safe with empty or partial state", () => {
      const store = createSessionStore();
      expect(() => store.destroy()).not.toThrow();

      const store2 = createSessionStore();
      store2.initializeYDoc();
      expect(() => store2.destroy()).not.toThrow();
      expect(store2.getSnapshot().ydoc).toBeNull();
    });
  });

  describe("query methods", () => {
    test("isReady returns correct state", () => {
      const store = createSessionStore();

      expect(store.isReady()).toBe(false); // "Should not be ready initially"

      store.initializeYDoc();
      expect(store.isReady()).toBe(false); // "Should not be ready with only YDoc"

      const mockSocket = createMockSocket();
      store.initializeSession(mockSocket, "test:room:123", null, {
        connect: false,
      });
      expect(store.isReady()).toBe(true); // "Should be ready with YDoc and provider"

      store.destroyYDoc();
      expect(store.isReady()).toBe(false); // "Should not be ready after destroying YDoc"

      store.destroy();
    });

    test("getConnectionState and getSyncState return current values", () => {
      const store = createSessionStore();

      expect(store.getConnectionState()).toBe(false); // "Should not be connected initially"
      expect(store.getSyncState()).toBe(false); // "Should not be synced initially"
    });
  });

  describe("awareness state", () => {
    sessionTest(
      "creates new awareness when re-initializing",
      ({ store, mockSocket }) => {
        const userData1 = { id: "user-1", name: "Test User", color: "#ff0000" };
        const firstResult = store.initializeSession(
          mockSocket,
          "test:room:123",
          userData1,
          { connect: false }
        );
        const firstAwareness = firstResult.awareness;

        const userData2 = { id: "user-2", name: "New User", color: "#00ff00" };
        const secondResult = store.initializeSession(
          mockSocket,
          "test:room:456",
          userData2,
          { connect: false }
        );

        expect(secondResult.awareness).not.toBe(firstAwareness);
        assertCleanAwareness(store.getSnapshot(), userData2);
      }
    );
  });

  describe("session initialization", () => {
    sessionTest(
      "creates YDoc, provider, and awareness atomically",
      ({ initializedSession }) => {
        const { store, userData } = initializedSession;
        const state = store.getSnapshot();
        expect(state.ydoc).toBeTruthy();
        expect(state.provider).toBeTruthy();
        expect(state.awareness).toBeTruthy();
        assertCleanAwareness(state, userData);
      }
    );

    sessionTest("reuses existing YDoc if present", ({ store, mockSocket }) => {
      const userData = { id: "user-2", name: "Another User", color: "#00ff00" };
      const existingYDoc = store.initializeYDoc();
      const result = store.initializeSession(
        mockSocket,
        "test:room:123",
        userData,
        { connect: false }
      );

      expect(result.ydoc).toBe(existingYDoc);
      expect(result.provider).toBeTruthy();
      assertCleanAwareness(store.getSnapshot(), userData);
    });

    test("creates awareness via provider even without userData", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();

      // Without userData - PhoenixChannelProvider still creates awareness
      store.initializeSession(mockSocket, "test:room:123", null, {
        connect: false,
      });
      const state1 = store.getSnapshot();
      expect(state1.ydoc).toBeTruthy();
      expect(state1.provider).toBeTruthy();
      // PhoenixChannelProvider creates awareness even when not explicitly provided
      expect(state1.awareness).toBeTruthy();
      expect(state1.userData).toBe(null);

      // With userData - creates new awareness and sets userData
      const userData = { id: "user-4", name: "Test User 4", color: "#ff00ff" };
      store.initializeSession(mockSocket, "test:room:456", userData, {
        connect: false,
      });
      const state2 = store.getSnapshot();
      expect(state2.awareness).toBeTruthy();
      expect(state2.userData).toEqual(userData);
      assertCleanAwareness(state2, userData);

      store.destroy();
    });

    test("throws error with null socket", () => {
      const store = createSessionStore();
      expect(() => store.initializeSession(null, "test:room", null)).toThrow(
        "Socket must be connected before initializing session"
      );
      expect(store.getSnapshot()).toMatchObject({
        ydoc: null,
        provider: null,
        awareness: null,
        userData: null,
      });
    });
  });

  describe("event handler integration", () => {
    test("provider event handlers work correctly", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

      const result = store.initializeSession(
        mockSocket,
        "test:room",
        userData,
        { connect: false }
      );
      expect(result.provider).toBeTruthy();
      expect(store.getSnapshot().isSynced).toBe(result.provider.synced);

      // Verify provider replacement
      const result2 = store.initializeSession(mockSocket, "room2", userData, {
        connect: false,
      });
      expect(result2.provider).not.toBe(result.provider);
      expect(store.getSnapshot().provider).toBe(result2.provider);

      // Verify cleanup
      store.destroy();
      const finalState = store.getSnapshot();
      expect(finalState).toMatchObject({
        provider: null,
        isConnected: false,
        isSynced: false,
        lastStatus: null,
      });
    });
  });

  describe("settling mechanism", () => {
    test("tracks document settling process", async () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const userData = {
        id: "user-settling",
        name: "Settling User",
        color: "#00ffff",
      };

      // Initialize session (without connecting initially)
      const result = store.initializeSession(
        mockSocket,
        "test:room",
        userData,
        {
          connect: true,
        }
      );

      // Initially settled should be false
      expect(store.settled).toBe(false); // "settled should be false initially"
      const settled = waitForState(store, state => state.settled);

      triggerProviderStatus(store, "connected");
      const { ydoc, provider } = result;
      provider.synced = true;

      applyProviderUpdate(ydoc, provider);

      expect(await settled).toBe(true);

      store.destroy();
    });

    test("resets on reconnection", async () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const userData = {
        id: "user-reconnect",
        name: "Reconnect User",
        color: "#ffff00",
      };

      // Initialize session
      const result = store.initializeSession(
        mockSocket,
        "test:room",
        userData,
        {
          connect: true,
        }
      );

      expect(result.provider).toEqual(store.getSnapshot().provider);

      triggerProviderStatus(store, "connected");
      expect(store.isConnected).toBe(true);

      // Initially settled should be false
      expect(store.settled).toBe(false); // "settled should be false initially"

      let settled = waitForState(store, state => state.settled);

      triggerProviderSync(store, true);
      applyProviderUpdate(store.ydoc!, store.provider!);

      expect(await settled).toBe(true);
      expect(store.settled).toBe(true);

      triggerProviderStatus(store, "disconnected");
      expect(store.isConnected).toBe(false);

      expect(store.settled).toBe(false);

      settled = waitForState(store, state => state.settled);

      triggerProviderStatus(store, "connected");
      triggerProviderSync(store, true);
      applyProviderUpdate(store.ydoc!, store.provider!);

      expect(await settled).toBe(true);

      store.destroy();
      expect(store.settled).toBe(false); // destroy should reset settled to false
    });
  });
});
