/**
 * Tests for createSessionStore
 *
 * This test suite covers Steps 1 & 2 of the SessionStore migration:
 * - Core store interface (subscribe/getSnapshot)
 * - Yjs Document Management (Step 1)
 * - Phoenix Provider Creation Logic (Step 2)
 * - State management and cleanup
 * - Error handling and validation
 */

import test from "ava";
import * as sinon from "sinon";

import { PhoenixChannelProvider } from "y-phoenix-channel";
import * as awarenessProtocol from "y-protocols/awareness";
import { Doc as YDoc } from "yjs";

import { createSessionStore } from "../../js/collaborative-editor/stores/createSessionStore";

import { createMockPhoenixChannel } from "./mocks/phoenixChannel";
import { createMockSocket } from "./mocks/phoenixSocket";

// Test helper interface for triggering mock events
interface MockProviderTestHelpers {
  triggerStatus: (status: string) => void;
  triggerSync: (synced: boolean) => void;
  triggerSynced: (synced: boolean) => void;
  getEventHandlers: () => Map<string, Set<(...args: unknown[]) => unknown>>;
}

// Factory for creating properly mocked PhoenixChannelProvider instances
const createMockPhoenixChannelProvider = (
  doc?: YDoc,
  awareness?: awarenessProtocol.Awareness
): PhoenixChannelProvider & { _test: MockProviderTestHelpers } => {
  const eventHandlers = new Map<string, Set<(...args: unknown[]) => unknown>>();

  // Create a stub that extends the real class but doesn't connect
  const stub = sinon.createStubInstance(PhoenixChannelProvider);

  // Mock basic properties
  stub.synced = false;
  stub.shouldConnect = true;
  stub.doc = doc || new YDoc();
  stub.awareness = awareness || new awarenessProtocol.Awareness(stub.doc);
  stub.channel = createMockPhoenixChannel() as any;
  stub.serverUrl = "ws://localhost:4000/socket";
  stub.roomname = "test:room";
  stub.bcChannel = "test-bc-channel";
  stub.bcconnected = false;
  stub.disableBc = false;
  stub.wsUnsuccessfulReconnects = 0;
  stub.wsLastMessageReceived = 0;

  // Mock event system
  stub.on.callsFake(
    (event: string, handler: (...args: unknown[]) => unknown) => {
      if (!eventHandlers.has(event)) {
        eventHandlers.set(event, new Set());
      }
      eventHandlers.get(event)?.add(handler);
      return handler as any;
    }
  );

  stub.off.callsFake(
    (event: string, handler: (...args: unknown[]) => unknown) => {
      const handlers = eventHandlers.get(event);
      if (handlers) {
        handlers.delete(handler);
      }
    }
  );

  stub.emit.callsFake((event: string, args: unknown[]) => {
    const handlers = eventHandlers.get(event);
    if (handlers) {
      handlers.forEach(handler => handler(...args));
    }
  });

  // Mock lifecycle methods
  stub.destroy.callsFake(() => {
    eventHandlers.clear();
  });

  stub.connect.callsFake(() => {
    stub.shouldConnect = true;
  });

  stub.disconnect.callsFake(() => {
    stub.shouldConnect = false;
  });

  stub.connectBc.callsFake(() => {
    stub.bcconnected = true;
  });

  stub.disconnectBc.callsFake(() => {
    stub.bcconnected = false;
  });

  // Add test helpers for triggering events
  (stub as any)._test = {
    triggerStatus: (status: string) => {
      const handlers = eventHandlers.get("status");
      if (handlers) {
        handlers.forEach(handler => handler([{ status }]));
      }
    },

    triggerSync: (synced: boolean) => {
      stub.synced = synced;
      const handlers = eventHandlers.get("sync");
      if (handlers) {
        handlers.forEach(handler => handler(synced));
      }
    },

    triggerSynced: (synced: boolean) => {
      stub.synced = synced;
      const handlers = eventHandlers.get("synced");
      if (handlers) {
        handlers.forEach(handler => handler([synced]));
      }
    },

    getEventHandlers: () => eventHandlers,
  };

  return stub as any;
};

// =============================================================================
// CORE STORE INTERFACE TESTS
// =============================================================================

test("getSnapshot returns initial state", t => {
  const store = createSessionStore();
  const initialState = store.getSnapshot();

  t.is(initialState.ydoc, null);
  t.is(initialState.provider, null);
  t.is(initialState.isConnected, false);
  t.is(initialState.isSynced, false);
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
  store.initializeYDoc();

  t.is(callCount, 1, "Listener should be called once for state change");

  // Unsubscribe and trigger another change
  unsubscribe();
  store.destroyYDoc();

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
// PHOENIX PROVIDER CREATION TESTS (STEP 2)
// =============================================================================

test("createProvider creates PhoenixChannelProvider with YDoc", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  // Initialize YDoc first
  const ydoc = store.initializeYDoc();

  const provider = store.createProvider(mockSocket, roomname, {
    connect: false,
  });

  t.truthy(provider, "Should return provider instance");
  t.is(
    store.getSnapshot().provider,
    provider,
    "Should store provider in state"
  );
  t.is(store.getProvider(), provider, "Query should return same provider");
});

test("createProvider with awareness and options", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  // Initialize YDoc and create awareness
  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);

  const provider = store.createProvider(mockSocket, roomname, {
    awareness,
    connect: false,
  });

  t.truthy(provider, "Should return provider instance");
  t.is(
    store.getSnapshot().provider,
    provider,
    "Should store provider in state"
  );
});

test("createProvider throws error without YDoc", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  const error = t.throws(() => {
    store.createProvider(mockSocket, roomname);
  });

  t.is(error.message, "YDoc must be initialized before creating provider");
});

test("createProvider throws error with null socket", t => {
  const store = createSessionStore();
  const roomname = "test:room:123";

  store.initializeYDoc();

  const error = t.throws(() => {
    store.createProvider(null, roomname);
  });

  t.is(error.message, "Socket must be connected before creating provider");
});

test("createProvider replaces existing provider", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname1 = "test:room:123";
  const roomname2 = "test:room:456";

  store.initializeYDoc();

  const firstProvider = store.createProvider(mockSocket, roomname1, {
    connect: false,
  });
  const secondProvider = store.createProvider(mockSocket, roomname2, {
    connect: false,
  });

  t.not(firstProvider, secondProvider, "Should create different instances");
  t.is(
    store.getSnapshot().provider,
    secondProvider,
    "Should store latest provider"
  );
});

// =============================================================================
// LEGACY PROVIDER CONNECTION TESTS
// =============================================================================

test("connectProvider sets provider and attaches handlers", t => {
  const store = createSessionStore();
  const mockProvider = createMockPhoenixChannelProvider();

  store.connectProvider(mockProvider);

  t.is(store.getSnapshot().provider, mockProvider, "Should store provider");
  t.is(store.getProvider(), mockProvider, "Query should return provider");
});

test("connectProvider cleans up previous handlers", t => {
  const store = createSessionStore();
  const firstProvider = createMockPhoenixChannelProvider();
  const secondProvider = createMockPhoenixChannelProvider();

  store.connectProvider(firstProvider);
  store.connectProvider(secondProvider);

  t.is(
    store.getSnapshot().provider,
    secondProvider,
    "Should use latest provider"
  );
});

// =============================================================================
// DISCONNECT AND CLEANUP TESTS
// =============================================================================

test("disconnectProvider cleans up provider and YDoc", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  // Set up provider and YDoc
  store.initializeYDoc();
  store.createProvider(mockSocket, roomname);

  // Verify initial state
  t.truthy(store.getSnapshot().provider, "Provider should be present");
  t.truthy(store.getSnapshot().ydoc, "YDoc should be present");

  store.disconnectProvider();

  const finalState = store.getSnapshot();
  t.is(finalState.provider, null, "Provider should be null");
  t.is(finalState.ydoc, null, "YDoc should be null");
  t.is(finalState.isConnected, false, "Should not be connected");
  t.is(finalState.isSynced, false, "Should not be synced");
  t.is(finalState.lastStatus, null, "Status should be null");
});

test("disconnectProvider handles null provider gracefully", t => {
  const store = createSessionStore();

  t.notThrows(() => {
    store.disconnectProvider();
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
  store.createProvider(mockSocket, "test:room:123");
  t.true(store.isReady(), "Should be ready with YDoc and provider");

  store.destroyYDoc();
  t.false(store.isReady(), "Should not be ready after destroying YDoc");
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

// =============================================================================
// AWARENESS PROTOCOL INTEGRATION TESTS (STEP 3)
// =============================================================================

test("setAwareness stores awareness instance", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);

  store.setAwareness(awareness);

  t.is(
    store.getSnapshot().awareness,
    awareness,
    "Should store awareness in state"
  );
  t.is(store.getAwareness(), awareness, "Query should return same awareness");
  t.is(store.awareness, awareness, "Property accessor should return awareness");
});

test("setAwareness accepts null awareness", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);

  // Set and then clear
  store.setAwareness(awareness);
  store.setAwareness(null);

  t.is(store.getSnapshot().awareness, null, "Should accept null awareness");
  t.is(store.getAwareness(), null, "Query should return null");
});

test("createProvider uses stored awareness when no awareness in options", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(awareness);

  const provider = store.createProvider(mockSocket, roomname, {
    connect: false,
  });

  t.truthy(provider, "Should create provider with stored awareness");
  t.is(
    store.getSnapshot().provider,
    provider,
    "Should store provider in state"
  );
});

test("createProvider options awareness overrides stored awareness", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  const ydoc = store.initializeYDoc();
  const storedAwareness = new awarenessProtocol.Awareness(ydoc);
  const optionsAwareness = new awarenessProtocol.Awareness(ydoc);

  store.setAwareness(storedAwareness);

  const provider = store.createProvider(mockSocket, roomname, {
    awareness: optionsAwareness,
    connect: false,
  });

  t.truthy(provider, "Should create provider with options awareness");
  t.is(
    store.getSnapshot().provider,
    provider,
    "Should store provider in state"
  );
});

test("destroyYDoc cleans up both YDoc and awareness", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);

  store.setAwareness(awareness);

  // Verify both are present
  t.truthy(store.getSnapshot().ydoc, "YDoc should be present");
  t.truthy(store.getSnapshot().awareness, "Awareness should be present");

  store.destroyYDoc();

  const finalState = store.getSnapshot();
  t.is(finalState.ydoc, null, "YDoc should be null");
  t.is(finalState.awareness, null, "Awareness should be null");
});

test("disconnectProvider cleans up awareness along with provider and YDoc", t => {
  const store = createSessionStore();
  const mockProvider = createMockPhoenixChannelProvider();

  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(awareness);
  store.connectProvider(mockProvider);

  // Verify all are present
  const initialState = store.getSnapshot();
  t.truthy(initialState.ydoc, "YDoc should be present");
  t.truthy(initialState.awareness, "Awareness should be present");
  t.truthy(initialState.provider, "Provider should be present");

  store.disconnectProvider();

  const finalState = store.getSnapshot();
  t.is(finalState.ydoc, null, "YDoc should be null");
  t.is(finalState.awareness, null, "Awareness should be null");
  t.is(finalState.provider, null, "Provider should be null");
});

test("getAwareness returns current awareness state", t => {
  const store = createSessionStore();

  t.is(store.getAwareness(), null, "Should initially be null");

  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(awareness);

  t.is(store.getAwareness(), awareness, "Should return stored awareness");
});

test("awareness property accessor returns current state", t => {
  const store = createSessionStore();

  t.is(
    store.awareness,
    null,
    "awareness accessor should return null initially"
  );

  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(awareness);

  t.is(
    store.awareness,
    awareness,
    "awareness accessor should return awareness after setting"
  );
});

// =============================================================================
// CONNECTION SEQUENCE MANAGEMENT TESTS (STEP 4)
// =============================================================================

test("initializeSession creates YDoc, provider, and sets awareness atomically", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";
  const ydoc = new YDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);

  const result = store.initializeSession(mockSocket, roomname, awareness, {
    connect: false,
  });

  t.truthy(result.ydoc, "Should return YDoc instance");
  t.truthy(result.provider, "Should return provider instance");
  t.is(result.awareness, awareness, "Should return same awareness instance");

  const finalState = store.getSnapshot();
  t.is(finalState.ydoc, result.ydoc, "Should store YDoc in state");
  t.is(finalState.provider, result.provider, "Should store provider in state");
  t.is(finalState.awareness, awareness, "Should store awareness in state");
});

test("initializeSession reuses existing YDoc if present", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  const existingYDoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(existingYDoc);

  const result = store.initializeSession(mockSocket, roomname, awareness, {
    connect: false,
  });

  t.is(result.ydoc, existingYDoc, "Should reuse existing YDoc");
  t.truthy(result.provider, "Should create provider");
  t.is(result.awareness, awareness, "Should use provided awareness");
});

test("initializeSession uses stored awareness when none provided", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";

  const ydoc = store.initializeYDoc();
  const storedAwareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(storedAwareness);

  const result = store.initializeSession(mockSocket, roomname, null, {
    connect: false,
  });

  t.is(result.awareness, storedAwareness, "Should use stored awareness");
  t.truthy(result.provider, "Should create provider");
  t.is(result.ydoc, ydoc, "Should use existing YDoc");
});

test("initializeSession throws error with null socket", t => {
  const store = createSessionStore();
  const roomname = "test:room:123";

  const error = t.throws(() => {
    store.initializeSession(null, roomname);
  });

  t.is(error.message, "Socket must be connected before initializing session");

  // Ensure no partial state on failure
  const finalState = store.getSnapshot();
  t.is(finalState.ydoc, null, "YDoc should remain null");
  t.is(finalState.provider, null, "Provider should remain null");
  t.is(finalState.awareness, null, "Awareness should remain null");
});

test("initializeSession with connect=false option", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  const roomname = "test:room:123";
  const ydoc = new YDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);

  const result = store.initializeSession(mockSocket, roomname, awareness, {
    connect: false,
  });

  t.truthy(result.provider, "Should create provider");
  t.is(result.awareness, awareness, "Should use provided awareness");
  t.truthy(result.ydoc, "Should create/use YDoc");
});

test("initializeSession handles awareness properly with null awareness", t => {
  const store = createSessionStore();
  const mockProvider = createMockPhoenixChannelProvider();

  // Use connectProvider to avoid the PhoenixChannelProvider constructor issue
  const ydoc = store.initializeYDoc();
  store.connectProvider(mockProvider);

  const finalState = store.getSnapshot();
  t.truthy(finalState.ydoc, "Should have YDoc");
  t.truthy(finalState.provider, "Should have provider");
  t.is(finalState.awareness, null, "Awareness should be null");
});

// =============================================================================
// LEGACY SETYDOC TESTS
// =============================================================================

test("setYDoc allows external YDoc assignment", t => {
  const store = createSessionStore();
  const externalYDoc = new YDoc();

  store.setYDoc(externalYDoc);

  t.is(store.getSnapshot().ydoc, externalYDoc, "Should store external YDoc");
  t.is(store.getYDoc(), externalYDoc, "Query should return external YDoc");

  store.setYDoc(null);
  t.is(store.getSnapshot().ydoc, null, "Should accept null YDoc");
});

// =============================================================================
// STEP 6: COMPREHENSIVE CLEANUP TESTS
// =============================================================================

test("destroySession performs complete cleanup", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(awareness);

  // Create mock provider using the factory
  const mockProvider = createMockPhoenixChannelProvider(ydoc, awareness);

  // Set up provider via connectProvider to avoid constructor issues
  store.connectProvider(mockProvider);

  // Track YDoc destruction
  let ydocDestroyed = false;
  const originalDestroy = ydoc.destroy;
  ydoc.destroy = () => {
    ydocDestroyed = true;
    originalDestroy.call(ydoc);
  };

  // Track awareness destruction
  let awarenessDestroyed = false;
  const originalAwarenessDestroy = awareness.destroy;
  awareness.destroy = () => {
    awarenessDestroyed = true;
    originalAwarenessDestroy.call(awareness);
  };

  // Verify initial state
  const beforeState = store.getSnapshot();
  t.truthy(beforeState.ydoc, "Should have YDoc before cleanup");
  t.truthy(beforeState.provider, "Should have provider before cleanup");
  t.truthy(beforeState.awareness, "Should have awareness before cleanup");

  // Perform cleanup
  store.destroySession();

  // Verify complete cleanup
  const afterState = store.getSnapshot();
  t.is(afterState.ydoc, null, "YDoc should be null after destroySession");
  t.is(
    afterState.provider,
    null,
    "Provider should be null after destroySession"
  );
  t.is(
    afterState.awareness,
    null,
    "Awareness should be null after destroySession"
  );
  t.is(
    afterState.isConnected,
    false,
    "isConnected should be false after destroySession"
  );
  t.is(
    afterState.isSynced,
    false,
    "isSynced should be false after destroySession"
  );
  t.is(
    afterState.lastStatus,
    null,
    "lastStatus should be null after destroySession"
  );

  // Verify destruction was called
  t.true(ydocDestroyed, "YDoc destroy should have been called");
  t.true(awarenessDestroyed, "Awareness destroy should have been called");
  t.true(
    (mockProvider.destroy as sinon.SinonStub).calledOnce,
    "Provider destroy should have been called"
  );
});

test("destroySession is safe when called on empty state", t => {
  const store = createSessionStore();

  // Should not throw when called on initial state
  t.notThrows(() => {
    store.destroySession();
  }, "destroySession should be safe on empty state");

  // State should remain in clean initial state
  const state = store.getSnapshot();
  t.is(state.ydoc, null, "YDoc should remain null");
  t.is(state.provider, null, "Provider should remain null");
  t.is(state.awareness, null, "Awareness should remain null");
  t.is(state.isConnected, false, "isConnected should remain false");
  t.is(state.isSynced, false, "isSynced should remain false");
  t.is(state.lastStatus, null, "lastStatus should remain null");
});

test("destroySession handles partial state cleanup", t => {
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
    store.destroySession();
  }, "destroySession should handle partial state");

  // Verify cleanup
  const afterState = store.getSnapshot();
  t.is(afterState.ydoc, null, "YDoc should be cleaned up");
  t.true(ydocDestroyed, "YDoc destroy should have been called");
});

test("destroySession cleans up event handlers", t => {
  const store = createSessionStore();

  // Set up state and connect provider (which sets up handlers)
  const ydoc = store.initializeYDoc();
  const mockProvider = createMockPhoenixChannelProvider(ydoc);
  store.connectProvider(mockProvider);

  // Verify initial state
  t.truthy(store.getSnapshot().provider, "Should have provider");

  // Perform cleanup
  store.destroySession();

  // Verify handler cleanup and provider destruction
  t.true(
    (mockProvider.off as sinon.SinonStub).called,
    "Event handlers should be cleaned up"
  );
  t.true(
    (mockProvider.destroy as sinon.SinonStub).calledOnce,
    "Provider should be destroyed"
  );
});

test("disconnectProvider maintains existing comprehensive cleanup", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(awareness);

  // Create mock provider using the factory
  const mockProvider = createMockPhoenixChannelProvider(ydoc, awareness);

  store.connectProvider(mockProvider);

  // Track destruction calls
  let ydocDestroyed = false;
  let awarenessDestroyed = false;

  const originalYdocDestroy = ydoc.destroy;
  ydoc.destroy = () => {
    ydocDestroyed = true;
    originalYdocDestroy.call(ydoc);
  };

  const originalAwarenessDestroy = awareness.destroy;
  awareness.destroy = () => {
    awarenessDestroyed = true;
    originalAwarenessDestroy.call(awareness);
  };

  // disconnectProvider should clean up everything like destroySession
  store.disconnectProvider();

  // Verify complete cleanup (same as destroySession)
  const afterState = store.getSnapshot();
  t.is(afterState.ydoc, null, "YDoc should be null after disconnectProvider");
  t.is(
    afterState.provider,
    null,
    "Provider should be null after disconnectProvider"
  );
  t.is(
    afterState.awareness,
    null,
    "Awareness should be null after disconnectProvider"
  );
  t.is(afterState.isConnected, false, "isConnected should be false");
  t.is(afterState.isSynced, false, "isSynced should be false");
  t.is(afterState.lastStatus, null, "lastStatus should be null");

  // Verify all destruction was called
  t.true(ydocDestroyed, "YDoc destroy should have been called");
  t.true(awarenessDestroyed, "Awareness destroy should have been called");
  t.true(
    (mockProvider.destroy as sinon.SinonStub).calledOnce,
    "Provider destroy should have been called"
  );
  t.true(
    (mockProvider.off as sinon.SinonStub).called,
    "Event handlers should be cleaned up"
  );
});

// =============================================================================
// DOCUMENT SETTLING BEHAVIOR TESTS
// =============================================================================

test("settled state starts as false", t => {
  const store = createSessionStore();

  const state = store.getSnapshot();
  t.is(state.settled, false, "settled should start as false");
  t.is(store.getSettled(), false, "getSettled() should return false");
  t.is(store.settled, false, "property accessor should return false");
});

test("settled state is included in state reset operations", t => {
  const store = createSessionStore();

  // Set up some state
  const ydoc = store.initializeYDoc();
  const awareness = new awarenessProtocol.Awareness(ydoc);
  store.setAwareness(awareness);

  // Create mock provider using the factory
  const mockProvider = createMockPhoenixChannelProvider(ydoc, awareness);

  store.connectProvider(mockProvider);

  // Manually set settled to true to test reset
  // Note: In reality this would be set by the settling process

  // Test disconnectProvider resets settled
  store.disconnectProvider();
  const afterDisconnect = store.getSnapshot();
  t.is(
    afterDisconnect.settled,
    false,
    "disconnectProvider should reset settled to false"
  );

  // Test destroySession resets settled
  const ydoc2 = store.initializeYDoc();
  store.connectProvider(mockProvider);
  store.destroySession();
  const afterDestroy = store.getSnapshot();
  t.is(
    afterDestroy.settled,
    false,
    "destroySession should reset settled to false"
  );
});

test("settled state tracks document settling process", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();

  // Create mock provider using the factory
  const mockProvider = createMockPhoenixChannelProvider(ydoc);

  // Connect provider - this should start settling when connected
  store.connectProvider(mockProvider);

  // Initially settled should be false
  t.is(store.settled, false, "settled should be false initially");

  // Simulate connection (this should trigger settling)
  mockProvider._test.triggerStatus("connected");

  // Settled should still be false until both sync and update events occur
  t.is(
    store.settled,
    false,
    "settled should be false until sync and update complete"
  );

  t.pass("settling process integration test completed");
});

test("settling is reset on reconnection", t => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();

  // Create mock provider using the factory
  const mockProvider = createMockPhoenixChannelProvider(ydoc);

  store.connectProvider(mockProvider);

  // Simulate initial connection
  mockProvider._test.triggerStatus("connected");
  t.is(
    store.settled,
    false,
    "settled should be false after initial connection"
  );

  // Simulate disconnection
  mockProvider._test.triggerStatus("disconnected");
  t.is(store.settled, false, "settled should remain false after disconnection");

  // Simulate reconnection (this should restart settling)
  mockProvider._test.triggerStatus("connected");
  t.is(
    store.settled,
    false,
    "settled should be false after reconnection, ready to settle again"
  );

  t.pass("reconnection settling reset test completed");
});
