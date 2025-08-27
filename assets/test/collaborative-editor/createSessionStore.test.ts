import test from "ava";
import { Doc as YDoc, applyUpdate, encodeStateAsUpdate } from "yjs";

import {
  createSessionStore,
  type SessionState,
  type SessionStore,
} from "../../js/collaborative-editor/stores/createSessionStore";

import { createMockSocket } from "./mocks/phoenixSocket";
import type { PhoenixChannelProvider } from "y-phoenix-channel";

// =============================================================================
// CORE STORE INTERFACE TESTS
// =============================================================================

test("getSnapshot returns initial state", t => {
  const store = createSessionStore();
  const initialState = store.getSnapshot();

  t.is(initialState.ydoc, null);
  t.is(initialState.provider, null);
  t.is(initialState.awareness, null);
  t.is(initialState.userData, null);
  t.is(initialState.isConnected, false);
  t.is(initialState.isSynced, false);
  t.is(initialState.settled, false);
  t.is(initialState.lastStatus, null);
});

test("subscribe/unsubscribe functionality works correctly", t => {
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

  t.is(callCount, 1, "Listener should be called once for state change");

  // Unsubscribe and trigger another change
  unsubscribe();
  store.destroy();

  t.is(callCount, 1, "Listener should not be called after unsubscribe");
});

test("withSelector creates memoized selector with referential stability", t => {
  const store = createSessionStore();

  const selectYdoc = store.withSelector(state => state.ydoc);
  const selectProvider = store.withSelector(state => state.provider);

  // Initial calls
  const ydoc1 = selectYdoc();
  const provider1 = selectProvider();

  t.is(ydoc1, null, "Should initially be null");
  t.is(provider1, null, "Should initially be null");

  // Change YDoc
  const newYDoc = store.initializeYDoc();
  const ydoc2 = selectYdoc();
  const provider2 = selectProvider();

  t.is(ydoc2, newYDoc, "Should return new YDoc");
  t.is(provider2, null, "Provider should still be null");

  // Same selector calls should return same references
  t.is(selectYdoc(), ydoc2, "Selector should return same reference");
  t.is(selectProvider(), provider2, "Selector should return same reference");
});

// =============================================================================
// YJS DOCUMENT MANAGEMENT TESTS (STEP 1)
// =============================================================================

test("initializeYDoc creates new YDoc instance", t => {
  const store = createSessionStore();

  const ydoc = store.initializeYDoc();

  t.truthy(ydoc, "Should return YDoc instance");
  t.true(ydoc instanceof YDoc, "Should be instance of YDoc");
  t.is(store.getSnapshot().ydoc, ydoc, "Should store YDoc in state");
  t.is(store.getYDoc(), ydoc, "Query should return same YDoc");
});

test("destroyYDoc cleans up YDoc instance", t => {
  const store = createSessionStore();

  const ydoc = store.initializeYDoc();
  t.truthy(store.getSnapshot().ydoc, "YDoc should be present");

  store.destroyYDoc();

  t.is(store.getSnapshot().ydoc, null, "YDoc should be null after destroy");
  t.is(store.getYDoc(), null, "Query should return null");
});

test("destroyYDoc handles null YDoc gracefully", t => {
  const store = createSessionStore();

  // Should not throw when no YDoc exists
  t.notThrows(() => {
    store.destroyYDoc();
  });

  t.is(store.getSnapshot().ydoc, null, "State should remain null");
});

test("multiple initializeYDoc calls replace previous YDoc", t => {
  const store = createSessionStore();

  const firstYDoc = store.initializeYDoc();
  const secondYDoc = store.initializeYDoc();

  t.not(firstYDoc, secondYDoc, "Should create different instances");
  t.is(store.getSnapshot().ydoc, secondYDoc, "Should store latest YDoc");
});

// =============================================================================
// PROVIDER ATTACHMENT BEHAVIOR TESTS
// =============================================================================

test("initializeSession creates provider and attaches event handlers", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";
  const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

  const result = store.initializeSession(mockSocket, roomname, userData, {
    connect: false,
  });

  t.truthy(result.provider, "Should return provider instance");
  t.is(
    store.getSnapshot().provider,
    result.provider,
    "Should store provider in state"
  );
  t.is(
    store.getProvider(),
    result.provider,
    "Query should return same provider"
  );

  // Verify initial sync state is reflected
  t.is(
    store.getSnapshot().isSynced,
    result.provider.synced,
    "Store should reflect provider sync state"
  );

  store.destroy();
});

test("initializeSession replaces existing provider", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname1 = "test:room:123";
  const roomname2 = "test:room:456";
  const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

  const firstResult = store.initializeSession(mockSocket, roomname1, userData, {
    connect: false,
  });
  const secondResult = store.initializeSession(
    mockSocket,
    roomname2,
    userData,
    {
      connect: false,
    }
  );

  t.not(
    firstResult.provider,
    secondResult.provider,
    "Should create different instances"
  );
  t.is(
    store.getSnapshot().provider,
    secondResult.provider,
    "Should store latest provider"
  );

  store.destroy();
});

// =============================================================================
// DISCONNECT AND CLEANUP TESTS
// =============================================================================

test("destroy cleans up provider and YDoc", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  // Set up provider and YDoc via initializeSession
  store.initializeSession(mockSocket, roomname, null, { connect: false });

  // Verify initial state
  t.truthy(store.getSnapshot().provider, "Provider should be present");
  t.truthy(store.getSnapshot().ydoc, "YDoc should be present");

  store.destroy();

  const finalState = store.getSnapshot();
  t.is(finalState.provider, null, "Provider should be null");
  t.is(finalState.ydoc, null, "YDoc should be null");
  t.is(finalState.isConnected, false, "Should not be connected");
  t.is(finalState.isSynced, false, "Should not be synced");
  t.is(finalState.lastStatus, null, "Status should be null");
});

test("destroy handles null provider gracefully", t => {
  const store = createSessionStore();

  t.notThrows(() => {
    store.destroy();
  });

  const state = store.getSnapshot();
  t.is(state.provider, null);
  t.is(state.isConnected, false);
  t.is(state.isSynced, false);
});

// =============================================================================
// QUERY METHODS TESTS
// =============================================================================

test("isReady returns correct state", t => {
  const store = createSessionStore();

  t.false(store.isReady(), "Should not be ready initially");

  store.initializeYDoc();
  t.false(store.isReady(), "Should not be ready with only YDoc");

  const mockSocket = createMockSocket();
  store.initializeSession(mockSocket, "test:room:123", null, {
    connect: false,
  });
  t.true(store.isReady(), "Should be ready with YDoc and provider");

  store.destroyYDoc();
  t.false(store.isReady(), "Should not be ready after destroying YDoc");

  store.destroy();
});

test("getConnectionState and getSyncState return current values", t => {
  const store = createSessionStore();

  t.false(store.getConnectionState(), "Should not be connected initially");
  t.false(store.getSyncState(), "Should not be synced initially");
});

test("property accessors return current state", t => {
  const store = createSessionStore();

  t.is(store.ydoc, null, "ydoc accessor should return null");
  t.is(store.provider, null, "provider accessor should return null");
  t.false(store.isConnected, "isConnected accessor should return false");
  t.false(store.isSynced, "isSynced accessor should return false");

  const ydoc = store.initializeYDoc();
  t.is(
    store.ydoc,
    ydoc,
    "ydoc accessor should return YDoc after initialization"
  );
});

test("property getters provide convenient access to state values", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();

  // Initialize session
  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  // Test property getters provide convenient access to state
  t.is(typeof store.ydoc, "object", "Should have ydoc getter");
  t.is(typeof store.provider, "object", "Should have provider getter");
  t.is(typeof store.awareness, "object", "Should have awareness getter");
  t.is(typeof store.isConnected, "boolean", "Should have isConnected getter");
  t.is(typeof store.isSynced, "boolean", "Should have isSynced getter");
  t.is(typeof store.settled, "boolean", "Should have settled getter");

  store.destroy();
});

test("withSelector creates memoized selectors for performance", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();

  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  // Test selector access (optimized)
  const ydocSelector = store.withSelector(state => state.ydoc);
  const isConnectedSelector = store.withSelector(state => state.isConnected);

  t.is(
    ydocSelector(),
    store.ydoc,
    "Selector should return same value as getter"
  );
  t.is(
    isConnectedSelector(),
    store.isConnected,
    "Selector should return same value as getter"
  );

  store.destroy();
});

test("store instance maintains stable reference across state changes", t => {
  const store = createSessionStore();

  // Store instance reference should never change
  const reference1 = store;
  const reference2 = store;

  t.is(reference1, reference2, "Store instance should have stable reference");

  // Even after state changes, reference stays the same
  const mockSocket = createMockSocket();
  store.initializeSession(mockSocket, "test:room", null);

  const reference3 = store;
  t.is(
    reference1,
    reference3,
    "Store reference should remain stable after state changes"
  );

  store.destroy();
});

test("store supports destructuring assignment for backward compatibility", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();

  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  // This pattern should work for backward compatibility
  const { ydoc, provider, awareness, isConnected, isSynced, settled } = store;

  t.truthy(ydoc, "Should be able to destructure ydoc");
  t.truthy(provider, "Should be able to destructure provider");
  t.truthy(awareness, "Should be able to destructure awareness");
  t.is(
    typeof isConnected,
    "boolean",
    "Should be able to destructure isConnected"
  );
  t.is(typeof isSynced, "boolean", "Should be able to destructure isSynced");
  t.is(typeof settled, "boolean", "Should be able to destructure settled");

  store.destroy();
});

test("withSelector creates optimized subscription callbacks", t => {
  const store = createSessionStore();
  let callCount = 0;

  // Create selector that only listens to ydoc changes
  const selectYdoc = store.withSelector(state => state.ydoc);

  // Subscribe to selector
  const unsubscribe = store.subscribe(() => {
    callCount++;
  });

  // Initialize session - should trigger notification
  const mockSocket = createMockSocket();
  store.initializeSession(mockSocket, "test:room", null);

  t.is(callCount, 1, "Should notify on state change");

  // Selector should return current value
  t.is(selectYdoc(), store.ydoc, "Selector should return current ydoc");

  unsubscribe();
  store.destroy();
});

test("store provides complete interface for React integration", t => {
  const store = createSessionStore();

  // Verify store instance provides all necessary interface
  t.is(typeof store.subscribe, "function", "Should have store interface");
  t.is(typeof store.getSnapshot, "function", "Should have store interface");
  t.is(typeof store.withSelector, "function", "Should have store interface");

  // Verify convenience getters
  t.true("ydoc" in store, "Should have ydoc getter");
  t.true("provider" in store, "Should have provider getter");
  t.true("awareness" in store, "Should have awareness getter");
  t.true("isConnected" in store, "Should have isConnected getter");
  t.true("isSynced" in store, "Should have isSynced getter");
  t.true("settled" in store, "Should have settled getter");

  // Verify methods
  t.is(typeof store.initializeSession, "function", "Should have commands");
  t.is(typeof store.destroy, "function", "Should have commands");
  t.is(typeof store.isReady, "function", "Should have queries");
});

// =============================================================================
// AWARENESS INTERNAL MANAGEMENT TESTS
// =============================================================================

test("initializeSession reuses existing awareness when re-initializing", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  // First initialize with userData to create internal awareness
  const userData = { id: "user-1", name: "Test User", color: "#ff0000" };
  const firstResult = store.initializeSession(mockSocket, roomname, userData, {
    connect: false,
  });
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

  t.truthy(secondResult.provider, "Should create provider with awareness");
  t.not(
    secondResult.awareness,
    firstAwareness,
    "Should create new awareness with new userData"
  );
  t.is(
    store.getSnapshot().provider,
    secondResult.provider,
    "Should store new provider in state"
  );

  // Verify userData is stored in session state instead of awareness
  const sessionUserData = store.getSnapshot().userData;
  t.deepEqual(
    sessionUserData,
    newUserData,
    "Session state should contain user data"
  );

  // Verify awareness does not have user data set (clean awareness)
  const awarenessUserData = secondResult.awareness?.getLocalState()?.user;
  t.is(
    awarenessUserData,
    undefined,
    "Awareness should not contain user data (clean awareness)"
  );

  store.destroy();
});

test("destroyYDoc cleans up both YDoc and awareness", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const mockSocket = createMockSocket();
  const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

  // Create awareness internally through initializeSession
  store.initializeSession(mockSocket, "test:room", userData, {
    connect: false,
  });

  // Verify both are present
  t.truthy(store.getSnapshot().ydoc, "YDoc should be present");
  t.truthy(store.getSnapshot().awareness, "Awareness should be present");

  store.destroyYDoc();

  const finalState = store.getSnapshot();
  t.is(finalState.ydoc, null, "YDoc should be null");
  t.is(finalState.awareness, null, "Awareness should be null");
});

// =============================================================================
// CONNECTION SEQUENCE MANAGEMENT TESTS (STEP 4)
// =============================================================================

test("initializeSession creates YDoc, provider, and sets awareness atomically", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";
  const userData = { id: "user-1", name: "Test User", color: "#ff0000" };

  const result = store.initializeSession(mockSocket, roomname, userData, {
    connect: false,
  });

  t.truthy(result.ydoc, "Should return YDoc instance");
  t.truthy(result.provider, "Should return provider instance");
  t.truthy(result.awareness, "Should create and return awareness instance");

  const finalState = store.getSnapshot();
  t.is(finalState.ydoc, result.ydoc, "Should store YDoc in state");
  t.is(finalState.provider, result.provider, "Should store provider in state");
  t.is(
    finalState.awareness,
    result.awareness,
    "Should store awareness in state"
  );

  // Verify userData is stored in session state instead of awareness
  t.deepEqual(
    finalState.userData,
    userData,
    "Session state should contain provided user data"
  );

  // Verify awareness does not have user data set (clean awareness)
  const awarenessUserData = result.awareness?.getLocalState()?.user;
  t.is(
    awarenessUserData,
    undefined,
    "Awareness should not contain user data (clean awareness)"
  );

  store.destroy();
});

test("initializeSession reuses existing YDoc if present", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";
  const userData = { id: "user-2", name: "Another User", color: "#00ff00" };

  const existingYDoc = store.initializeYDoc();

  const result = store.initializeSession(mockSocket, roomname, userData, {
    connect: false,
  });

  t.is(result.ydoc, existingYDoc, "Should reuse existing YDoc");
  t.truthy(result.provider, "Should create provider");
  t.truthy(result.awareness, "Should create awareness");

  // Verify userData is stored in session state instead of awareness
  const sessionUserData = store.getSnapshot().userData;
  t.deepEqual(
    sessionUserData,
    userData,
    "Session state should contain provided user data"
  );

  // Verify awareness does not have user data set (clean awareness)
  const awarenessUserData = result.awareness?.getLocalState()?.user;
  t.is(
    awarenessUserData,
    undefined,
    "Awareness should not contain user data (clean awareness)"
  );

  store.destroy();
});

test("initializeSession handles null userData gracefully", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  const ydoc = store.initializeYDoc();

  const result = store.initializeSession(mockSocket, roomname, null, {
    connect: false,
  });

  t.is(
    result.awareness,
    null,
    "Should not create awareness when userData is null"
  );
  t.truthy(result.provider, "Should create provider");
  t.is(result.ydoc, ydoc, "Should use existing YDoc");

  store.destroy();
});

test("initializeSession throws error with null socket", t => {
  const store = createSessionStore();
  const roomname = "test:room:123";

  const error = t.throws(() => {
    store.initializeSession(null, roomname, null);
  });

  t.is(error.message, "Socket must be connected before initializing session");

  // Ensure no partial state on failure
  const finalState = store.getSnapshot();
  t.is(finalState.ydoc, null, "YDoc should remain null");
  t.is(finalState.provider, null, "Provider should remain null");
  t.is(finalState.awareness, null, "Awareness should remain null");
  t.is(finalState.userData, null, "userData should remain null");
});

test("initializeSession with connect=false option", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";
  const userData = { id: "user-3", name: "Test User 3", color: "#0000ff" };

  const result = store.initializeSession(mockSocket, roomname, userData, {
    connect: false,
  });

  t.truthy(result.provider, "Should create provider");
  t.truthy(result.awareness, "Should create awareness");
  t.truthy(result.ydoc, "Should create/use YDoc");

  // Verify userData is stored in session state instead of awareness
  const sessionUserData = store.getSnapshot().userData;
  t.deepEqual(
    sessionUserData,
    userData,
    "Session state should contain provided user data"
  );

  // Verify awareness does not have user data set (clean awareness)
  const awarenessUserData = result.awareness?.getLocalState()?.user;
  t.is(
    awarenessUserData,
    undefined,
    "Awareness should not contain user data (clean awareness)"
  );

  store.destroy();
});

test("initializeSession creates awareness only when userData is provided", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  // Test without userData
  store.initializeSession(mockSocket, roomname, null, {
    connect: false,
  });
  const result1 = store.getSnapshot();
  t.truthy(result1.ydoc, "Should have YDoc");
  t.truthy(result1.provider, "Should have provider");
  t.is(result1.awareness, null, "Awareness should be null when no userData");
  t.is(
    result1.userData,
    null,
    "userData should be null when no userData provided"
  );

  // Test with userData
  const userData = { id: "user-4", name: "Test User 4", color: "#ff00ff" };
  store.initializeSession(mockSocket, roomname + "2", userData, {
    connect: false,
  });
  const result2 = store.getSnapshot();
  t.truthy(result2.awareness, "Should create awareness when userData provided");

  // Verify userData is stored in session state instead of awareness
  t.deepEqual(
    result2.userData,
    userData,
    "Session state should contain provided user data"
  );

  // Verify awareness does not have user data set (clean awareness)
  const awarenessUserData = result2.awareness?.getLocalState()?.user;
  t.is(
    awarenessUserData,
    undefined,
    "Awareness should not contain user data (clean awareness)"
  );

  store.destroy();
});

// =============================================================================
// EVENT HANDLER INTEGRATION TESTS
// =============================================================================

test("attachProvider integration works with initializeSession", t => {
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
  t.truthy(result1.provider, "initializeSession should create provider");

  // Re-initialize with new session - should call attachProvider internally and replace provider
  const result2 = store.initializeSession(
    mockSocket,
    "room2",
    { id: "user-2", name: "Test User 2", color: "#00ff00" },
    { connect: false }
  );
  t.truthy(result2.provider, "second initializeSession should create provider");
  t.not(
    result1.provider,
    result2.provider,
    "Should create different provider instances"
  );
  t.is(
    store.getSnapshot().provider,
    result2.provider,
    "Should store latest provider"
  );

  store.destroy();
});

test("provider event handler integration via public interface", t => {
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
  t.is(
    store.getSnapshot().isSynced,
    result.provider.synced,
    "Store should reflect provider sync state"
  );

  // Test that provider status changes are reflected in store state
  // (This verifies attachProvider event handlers are working)
  t.is(store.getSnapshot().isConnected, false, "Should start disconnected");
  t.is(store.getSnapshot().lastStatus, null, "Should have no initial status");

  // Verify event handlers are working by checking that destroy cleans up properly
  t.notThrows(
    () => store.destroy(),
    "Destroy should handle event cleanup properly"
  );

  // After destroy, all state should be reset
  const finalState = store.getSnapshot();
  t.is(finalState.provider, null, "Provider should be null after destroy");
  t.is(finalState.isConnected, false, "Should not be connected after destroy");
  t.is(finalState.isSynced, false, "Should not be synced after destroy");
  t.is(finalState.lastStatus, null, "Status should be null after destroy");
});

// =============================================================================
// STEP 6: COMPREHENSIVE CLEANUP TESTS
// =============================================================================

test("destroy performs complete cleanup", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const userData = {
    id: "user-cleanup",
    name: "Cleanup User",
    color: "#ff0000",
  };

  // Initialize with userData to create awareness internally
  const result = store.initializeSession(mockSocket, "test:room", userData, {
    connect: false,
  });

  // Track YDoc destruction
  let ydocDestroyed = false;
  const originalDestroy = result.ydoc.destroy;
  result.ydoc.destroy = () => {
    ydocDestroyed = true;
    originalDestroy.call(result.ydoc);
  };

  // Track awareness destruction
  let awarenessDestroyed = false;
  if (result.awareness) {
    const originalAwarenessDestroy = result.awareness.destroy;
    result.awareness.destroy = () => {
      awarenessDestroyed = true;
      originalAwarenessDestroy.call(result.awareness);
    };
  }

  // Verify initial state
  const beforeState = store.getSnapshot();
  t.truthy(beforeState.ydoc, "Should have YDoc before cleanup");
  t.truthy(beforeState.provider, "Should have provider before cleanup");
  t.truthy(beforeState.awareness, "Should have awareness before cleanup");

  // Perform cleanup
  store.destroy();

  // Verify complete cleanup
  const afterState = store.getSnapshot();
  t.is(afterState.ydoc, null, "YDoc should be null after destroy");
  t.is(afterState.provider, null, "Provider should be null after destroy");
  t.is(afterState.awareness, null, "Awareness should be null after destroy");
  t.is(
    afterState.isConnected,
    false,
    "isConnected should be false after destroy"
  );
  t.is(afterState.isSynced, false, "isSynced should be false after destroy");
  t.is(afterState.userData, null, "userData should be null after destroy");
  t.is(afterState.lastStatus, null, "lastStatus should be null after destroy");

  // Verify destruction was called
  t.true(ydocDestroyed, "YDoc destroy should have been called");
  t.true(awarenessDestroyed, "Awareness destroy should have been called");
});

test("destroy is safe when called on empty state", t => {
  const store = createSessionStore();

  // Should not throw when called on initial state
  t.notThrows(() => {
    store.destroy();
  }, "destroy should be safe on empty state");

  // State should remain in clean initial state
  const state = store.getSnapshot();
  t.is(state.ydoc, null, "YDoc should remain null");
  t.is(state.provider, null, "Provider should remain null");
  t.is(state.awareness, null, "Awareness should remain null");
  t.is(state.userData, null, "userData should remain null");
  t.is(state.isConnected, false, "isConnected should remain false");
  t.is(state.isSynced, false, "isSynced should remain false");
  t.is(state.lastStatus, null, "lastStatus should remain null");
});

test("destroy handles partial state cleanup", t => {
  const store = createSessionStore();

  // Set up partial state (only YDoc, no provider or awareness)
  const ydoc = store.initializeYDoc();

  // Track YDoc destruction
  let ydocDestroyed = false;
  const originalDestroy = ydoc.destroy;
  ydoc.destroy = () => {
    ydocDestroyed = true;
    originalDestroy.call(ydoc);
  };

  // Verify partial state
  const beforeState = store.getSnapshot();
  t.truthy(beforeState.ydoc, "Should have YDoc");
  t.is(beforeState.provider, null, "Should not have provider");
  t.is(beforeState.awareness, null, "Should not have awareness");

  // Should handle partial cleanup gracefully
  t.notThrows(() => {
    store.destroy();
  }, "destroy should handle partial state");

  // Verify cleanup
  const afterState = store.getSnapshot();
  t.is(afterState.ydoc, null, "YDoc should be cleaned up");
  t.true(ydocDestroyed, "YDoc destroy should have been called");
});

test("destroy cleans up event handlers", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const userData = {
    id: "user-handler",
    name: "Handler User",
    color: "#00ff00",
  };

  // Set up state by initializing session
  const result = store.initializeSession(mockSocket, "test:room", userData, {
    connect: false,
  });

  // Verify initial state
  t.truthy(store.getSnapshot().provider, "Should have provider");

  // Perform cleanup
  store.destroy();

  // Verify provider destruction
  const finalState = store.getSnapshot();
  t.is(finalState.provider, null, "Provider should be destroyed");
});

test("destroy maintains existing comprehensive cleanup", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const userData = {
    id: "user-comprehensive",
    name: "Comprehensive User",
    color: "#0000ff",
  };

  // Initialize session to create all components internally
  const result = store.initializeSession(mockSocket, "test:room", userData, {
    connect: false,
  });

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
  t.is(afterState.ydoc, null, "YDoc should be null after destroy");
  t.is(afterState.provider, null, "Provider should be null after destroy");
  t.is(afterState.awareness, null, "Awareness should be null after destroy");
  t.is(afterState.userData, null, "userData should be null after destroy");
  t.is(afterState.isConnected, false, "isConnected should be false");
  t.is(afterState.isSynced, false, "isSynced should be false");
  t.is(afterState.lastStatus, null, "lastStatus should be null");

  // Verify all destruction was called
  t.true(ydocDestroyed, "YDoc destroy should have been called");
  t.true(awarenessDestroyed, "Awareness destroy should have been called");
});

// =============================================================================
// DOCUMENT SETTLING BEHAVIOR TESTS
// =============================================================================

test("settled state tracks document settling process", async t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const userData = {
    id: "user-settling",
    name: "Settling User",
    color: "#00ffff",
  };

  // Initialize session (without connecting initially)
  const result = store.initializeSession(mockSocket, "test:room", userData, {
    connect: true,
  });

  // Initially settled should be false
  t.is(store.settled, false, "settled should be false initially");
  const settled = waitForState(store, state => state.settled);

  triggerProviderStatus(store, "connected");
  const { ydoc, provider } = result;
  provider.synced = true;

  applyProviderUpdate(ydoc, provider);

  t.is(await settled, true);

  store.destroy();
});

test("settling is reset on reconnection", async t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const userData = {
    id: "user-reconnect",
    name: "Reconnect User",
    color: "#ffff00",
  };

  // Initialize session
  const result = store.initializeSession(mockSocket, "test:room", userData, {
    connect: true,
  });

  t.deepEqual(result.provider, store.getSnapshot().provider);

  triggerProviderStatus(store, "connected");
  t.is(store.isConnected, true);

  // Initially settled should be false
  t.is(store.settled, false, "settled should be false initially");

  let settled = waitForState(store, state => state.settled);

  triggerProviderSync(store, true);
  applyProviderUpdate(store.ydoc!, store.provider!);

  t.is(await settled, true);
  t.is(store.settled, true);

  triggerProviderStatus(store, "disconnected");
  t.is(store.isConnected, false);

  t.is(store.settled, false);

  settled = waitForState(store, state => state.settled);

  triggerProviderStatus(store, "connected");
  triggerProviderSync(store, true);
  applyProviderUpdate(store.ydoc!, store.provider!);

  t.is(await settled, true);

  store.destroy();
  t.is(store.settled, false, "destroy should reset settled to false");
});

function triggerProviderSync(store: SessionStore, synced: boolean) {
  store.provider!.emit("sync", [synced]);
}

function triggerProviderStatus(
  store: SessionStore,
  status: "connected" | "disconnected" | "connecting"
) {
  store.provider!.emit("status", [{ status }]);
}

function applyProviderUpdate(ydoc: YDoc, provider: PhoenixChannelProvider) {
  const doc2 = new YDoc();
  doc2.getArray("test").insert(0, ["hello"]);

  const update = encodeStateAsUpdate(doc2);
  applyUpdate(ydoc, update, provider);
}

async function waitForState(
  store: SessionStore,
  callback: (state: SessionState) => boolean,
  timeout = 200
) {
  const stack = new Error().stack;
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      const error = new Error("Timeout waiting for state");
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
        reject(error);
      }
    });
  });
}
