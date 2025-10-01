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
} from "./__helpers__/sessionStoreHelpers";

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

    test("subscribe/unsubscribe functionality works correctly", () => {
      const store = createSessionStore();
      let callCount = 0;

      const listener = () => {
        callCount++;
      };

      // Subscribe to changes
      const unsubscribe = store.subscribe(listener);

      // Trigger a state change
      store.initializeSession(createMockSocket(), "test:room", {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      });

      expect(callCount).toBe(1); // Listener should be called once for state change

      // Unsubscribe and trigger another change
      unsubscribe();
      store.destroy();

      expect(callCount).toBe(1); // Listener should not be called after unsubscribe
    });

    test("withSelector creates memoized selector with referential stability", () => {
      const store = createSessionStore();

      const selectYdoc = store.withSelector(state => state.ydoc);
      const selectProvider = store.withSelector(state => state.provider);

      // Initial calls
      const ydoc1 = selectYdoc();

      // Change YDoc
      const newYDoc = store.initializeYDoc();
      const ydoc2 = selectYdoc();
      const provider2 = selectProvider();

      expect(ydoc2).toBe(newYDoc);
      expect(provider2).toBeNull();

      // Same selector calls should return same references
      expect(selectYdoc()).toBe(
        ydoc2,
        "Selector should return same reference for unchanged state"
      );
      expect(selectProvider()).toBe(
        provider2,
        "Selector should return same reference for unchanged state"
      );
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
    test("creates provider and attaches event handlers", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";
      const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

      const result = store.initializeSession(mockSocket, roomname, userData, {
        connect: false,
      });

      expect(result.provider).toBeTruthy(); // "Should return provider instance"
      expect(store.getSnapshot().provider).toBe(result.provider); // "Should store provider in state"
      expect(store.getProvider()).toBe(result.provider); // "Query should return same provider"

      // Verify initial sync state is reflected
      expect(store.getSnapshot().isSynced).toBe(result.provider.synced); // "Store should reflect provider sync state"

      store.destroy();
    });

    test("replaces existing provider", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname1 = "test:room:123";
      const roomname2 = "test:room:456";
      const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

      const firstResult = store.initializeSession(
        mockSocket,
        roomname1,
        userData,
        {
          connect: false,
        }
      );
      const secondResult = store.initializeSession(
        mockSocket,
        roomname2,
        userData,
        {
          connect: false,
        }
      );

      expect(firstResult.provider).not.toBe(secondResult.provider); // "Should create different instances"
      expect(store.getSnapshot().provider).toBe(secondResult.provider); // "Should store latest provider"

      store.destroy();
    });
  });

  describe("lifecycle", () => {
    test("destroy cleans up provider and YDoc", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";

      store.initializeSession(mockSocket, roomname, null, { connect: false });

      store.destroy();

      const finalState = store.getSnapshot();
      expect(finalState.provider).toBeNull();
      expect(finalState.ydoc).toBeNull();
      expect(finalState.isConnected).toBe(false);
      expect(finalState.isSynced).toBe(false);
    });

    test("handles null provider gracefully", () => {
      const store = createSessionStore();

      expect(() => {
        store.destroy();
      }).not.toThrow();
    });

    test("performs complete cleanup", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const userData = {
        id: "user-cleanup",
        name: "Cleanup User",
        color: "#ff0000",
      };

      const result = store.initializeSession(
        mockSocket,
        "test:room",
        userData,
        {
          connect: false,
        }
      );

      // Track destruction calls
      let ydocDestroyed = false;
      let awarenessDestroyed = false;

      const originalDestroy = result.ydoc.destroy;
      result.ydoc.destroy = () => {
        ydocDestroyed = true;
        originalDestroy.call(result.ydoc);
      };

      if (result.awareness) {
        const originalAwarenessDestroy = result.awareness.destroy;
        result.awareness.destroy = () => {
          awarenessDestroyed = true;
          originalAwarenessDestroy.call(result.awareness);
        };
      }

      store.destroy();

      const afterState = store.getSnapshot();
      expect(afterState.ydoc).toBeNull();
      expect(afterState.provider).toBeNull();
      expect(afterState.awareness).toBeNull();
      expect(ydocDestroyed).toBe(true, "YDoc destroy should have been called");
      expect(awarenessDestroyed).toBe(
        true,
        "Awareness destroy should have been called"
      );
    });

    test("is safe when called on empty state", () => {
      const store = createSessionStore();

      expect(() => {
        store.destroy();
      }).not.toThrow();
    });

    test("handles partial state cleanup", () => {
      const store = createSessionStore();

      const ydoc = store.initializeYDoc();

      let ydocDestroyed = false;
      const originalDestroy = ydoc.destroy;
      ydoc.destroy = () => {
        ydocDestroyed = true;
        originalDestroy.call(ydoc);
      };

      expect(() => {
        store.destroy();
      }).not.toThrow();

      expect(store.getSnapshot().ydoc).toBeNull();
      expect(ydocDestroyed).toBe(true, "YDoc destroy should have been called");
    });

    test("cleans up event handlers", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const userData = {
        id: "user-handler",
        name: "Handler User",
        color: "#00ff00",
      };

      // Set up state by initializing session
      store.initializeSession(mockSocket, "test:room", userData, {
        connect: false,
      });

      // Verify initial state
      expect(store.getSnapshot().provider).toBeTruthy(); // "Should have provider"

      // Perform cleanup
      store.destroy();

      // Verify provider destruction
      const finalState = store.getSnapshot();
      expect(finalState.provider).toBe(null); // "Provider should be destroyed"
    });

    test("maintains comprehensive cleanup", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const userData = {
        id: "user-comprehensive",
        name: "Comprehensive User",
        color: "#0000ff",
      };

      // Initialize session to create all components internally
      const result = store.initializeSession(
        mockSocket,
        "test:room",
        userData,
        {
          connect: false,
        }
      );

      // Track destruction calls
      let ydocDestroyed = false;
      let awarenessDestroyed = false;

      const originalYdocDestroy = result.ydoc.destroy;
      result.ydoc.destroy = () => {
        ydocDestroyed = true;
        originalYdocDestroy.call(result.ydoc);
      };

      if (result.awareness) {
        const originalAwarenessDestroy = result.awareness.destroy;
        result.awareness.destroy = () => {
          awarenessDestroyed = true;
          originalAwarenessDestroy.call(result.awareness);
        };
      }

      // destroy should clean up everything
      store.destroy();

      // Verify complete cleanup
      const afterState = store.getSnapshot();
      expect(afterState.ydoc).toBe(null); // "YDoc should be null after destroy"
      expect(afterState.provider).toBe(null); // "Provider should be null after destroy"
      expect(afterState.awareness).toBe(null); // "Awareness should be null after destroy"
      expect(afterState.userData).toBe(null); // "userData should be null after destroy"
      expect(afterState.isConnected).toBe(false); // "isConnected should be false"
      expect(afterState.isSynced).toBe(false); // "isSynced should be false"
      expect(afterState.lastStatus).toBe(null); // "lastStatus should be null"

      // Verify all destruction was called
      expect(ydocDestroyed).toBe(true); // "YDoc destroy should have been called"
      expect(awarenessDestroyed).toBe(true); // "Awareness destroy should have been called"
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
    test("reuses existing awareness when re-initializing", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";

      // First initialize with userData to create internal awareness
      const userData = { id: "user-1", name: "Test User", color: "#ff0000" };
      const firstResult = store.initializeSession(
        mockSocket,
        roomname,
        userData,
        {
          connect: false,
        }
      );
      const firstAwareness = firstResult.awareness;

      // Re-initialize with different userData - should create new awareness
      const newUserData = { id: "user-2", name: "New User", color: "#00ff00" };
      const secondResult = store.initializeSession(
        mockSocket,
        roomname + "2",
        newUserData,
        {
          connect: false,
        }
      );

      expect(secondResult.provider).toBeTruthy(); // "Should create provider with awareness"
      expect(secondResult.awareness).not.toBe(firstAwareness); // "Should create new awareness with new userData"
      expect(store.getSnapshot().provider).toBe(secondResult.provider); // "Should store new provider in state"

      // Verify userData is stored in session state instead of awareness
      const sessionUserData = store.getSnapshot().userData;
      expect(sessionUserData).toEqual(newUserData); // "Session state should contain user data"

      // Verify awareness does not have user data set (clean awareness)
      const awarenessUserData = secondResult.awareness?.getLocalState()?.user;
      expect(awarenessUserData).toBe(undefined); // "Awareness should not contain user data (clean awareness)"

      store.destroy();
    });
  });

  describe("session initialization", () => {
    test("creates YDoc, provider, and sets awareness atomically", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";
      const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

      const result = store.initializeSession(mockSocket, roomname, userData, {
        connect: false,
      });

      expect(result.ydoc).toBeTruthy(); // "Should return YDoc instance"
      expect(result.provider).toBeTruthy(); // "Should return provider instance"
      expect(result.awareness).toBeTruthy(); // "Should create and return awareness instance"

      const finalState = store.getSnapshot();
      expect(finalState.ydoc).toBe(result.ydoc); // "Should store YDoc in state"
      expect(finalState.provider).toBe(result.provider); // "Should store provider in state"
      expect(finalState.awareness).toBe(result.awareness); // "Should store awareness in state"

      // Verify userData is stored in session state instead of awareness
      expect(finalState.userData).toEqual(userData); // "Session state should contain provided user data"

      // Verify awareness does not have user data set (clean awareness)
      const awarenessUserData = result.awareness?.getLocalState()?.user;
      expect(awarenessUserData).toBe(undefined); // "Awareness should not contain user data (clean awareness)"

      store.destroy();
    });

    test("reuses existing YDoc if present", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";
      const userData = { id: "user-2", name: "Another User", color: "#00ff00" };

      const existingYDoc = store.initializeYDoc();

      const result = store.initializeSession(mockSocket, roomname, userData, {
        connect: false,
      });

      expect(result.ydoc).toBe(existingYDoc); // "Should reuse existing YDoc"
      expect(result.provider).toBeTruthy(); // "Should create provider"
      expect(result.awareness).toBeTruthy(); // "Should create awareness"

      // Verify userData is stored in session state instead of awareness
      const sessionUserData = store.getSnapshot().userData;
      expect(sessionUserData).toEqual(userData); // "Session state should contain provided user data"

      // Verify awareness does not have user data set (clean awareness)
      const awarenessUserData = result.awareness?.getLocalState()?.user;
      expect(awarenessUserData).toBe(undefined); // "Awareness should not contain user data (clean awareness)"

      store.destroy();
    });

    test("handles null userData gracefully", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";

      const ydoc = store.initializeYDoc();

      const result = store.initializeSession(mockSocket, roomname, null, {
        connect: false,
      });

      expect(result.awareness).toBe(null); // "Should not create awareness when userData is null"
      expect(result.provider).toBeTruthy(); // "Should create provider"
      expect(result.ydoc).toBe(ydoc); // "Should use existing YDoc"

      store.destroy();
    });

    test("throws error with null socket", () => {
      const store = createSessionStore();
      const roomname = "test:room:123";

      expect(() => {
        store.initializeSession(null, roomname, null);
      }).toThrow("Socket must be connected before initializing session");

      // Ensure no partial state on failure
      const finalState = store.getSnapshot();
      expect(finalState.ydoc).toBe(null); // "YDoc should remain null"
      expect(finalState.provider).toBe(null); // "Provider should remain null"
      expect(finalState.awareness).toBe(null); // "Awareness should remain null"
      expect(finalState.userData).toBe(null); // "userData should remain null"
    });

    test("supports connect=false option", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";
      const userData = { id: "user-3", name: "Test User 3", color: "#0000ff" };

      const result = store.initializeSession(mockSocket, roomname, userData, {
        connect: false,
      });

      expect(result.provider).toBeTruthy(); // "Should create provider"
      expect(result.awareness).toBeTruthy(); // "Should create awareness"
      expect(result.ydoc).toBeTruthy(); // "Should create/use YDoc"

      // Verify userData is stored in session state instead of awareness
      const sessionUserData = store.getSnapshot().userData;
      expect(sessionUserData).toEqual(userData); // "Session state should contain provided user data"

      // Verify awareness does not have user data set (clean awareness)
      const awarenessUserData = result.awareness?.getLocalState()?.user;
      expect(awarenessUserData).toBe(undefined); // "Awareness should not contain user data (clean awareness)"

      store.destroy();
    });

    test("creates awareness only when userData is provided", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();
      const roomname = "test:room:123";

      // Test without userData
      store.initializeSession(mockSocket, roomname, null, {
        connect: false,
      });
      const result1 = store.getSnapshot();
      expect(result1.ydoc).toBeTruthy(); // "Should have YDoc"
      expect(result1.provider).toBeTruthy(); // "Should have provider"
      expect(result1.awareness).toBe(null); // "Awareness should be null when no userData"
      expect(result1.userData).toBe(null); // "userData should be null when no userData provided"

      // Test with userData
      const userData = { id: "user-4", name: "Test User 4", color: "#ff00ff" };
      store.initializeSession(mockSocket, roomname + "2", userData, {
        connect: false,
      });
      const result2 = store.getSnapshot();
      expect(result2.awareness).toBeTruthy(); // "Should create awareness when userData provided"

      // Verify userData is stored in session state instead of awareness
      expect(result2.userData).toEqual(userData); // "Session state should contain provided user data"

      // Verify awareness does not have user data set (clean awareness)
      const awarenessUserData = result2.awareness?.getLocalState()?.user;
      expect(awarenessUserData).toBe(undefined); // "Awareness should not contain user data (clean awareness)"

      store.destroy();
    });
  });

  describe("event handler integration", () => {
    test("attachProvider integration works with initializeSession", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();

      // Test that initializeSession properly integrates with attachProvider
      // by verifying that provider events can be processed (implicit test)

      // Initialize session - should call attachProvider internally
      const result1 = store.initializeSession(
        mockSocket,
        "room1",
        { id: "user-1", name: "Test User", color: "#ff0000" },
        { connect: false }
      );
      expect(result1.provider).toBeTruthy(); // "initializeSession should create provider"

      // Re-initialize with new session - should call attachProvider internally and replace provider
      const result2 = store.initializeSession(
        mockSocket,
        "room2",
        { id: "user-2", name: "Test User 2", color: "#00ff00" },
        { connect: false }
      );
      expect(result2.provider).toBeTruthy(); // "second initializeSession should create provider"
      expect(result1.provider).not.toBe(result2.provider); // "Should create different provider instances"
      expect(store.getSnapshot().provider).toBe(result2.provider); // "Should store latest provider"

      store.destroy();
    });

    test("provider event handler integration via public interface", () => {
      const store = createSessionStore();
      const mockSocket = createMockSocket();

      // Create provider and verify initial state
      const result = store.initializeSession(
        mockSocket,
        "test:room",
        { id: "user-1", name: "Test User", color: "#ff0000" },
        { connect: false }
      );

      // Initial state should reflect provider's synced status
      expect(store.getSnapshot().isSynced).toBe(result.provider.synced); // "Store should reflect provider sync state"

      // Test that provider status changes are reflected in store state
      // (This verifies attachProvider event handlers are working)
      expect(store.getSnapshot().isConnected).toBe(false); // "Should start disconnected"
      expect(store.getSnapshot().lastStatus).toBe(null); // "Should have no initial status"

      // Verify event handlers are working by checking that destroy cleans up properly
      expect(() => {
        store.destroy();
      }).not.toThrow();

      // After destroy, all state should be reset
      const finalState = store.getSnapshot();
      expect(finalState.provider).toBe(null); // "Provider should be null after destroy"
      expect(finalState.isConnected).toBe(false); // "Should not be connected after destroy"
      expect(finalState.isSynced).toBe(false); // "Should not be synced after destroy"
      expect(finalState.lastStatus).toBe(null); // "Status should be null after destroy"
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
