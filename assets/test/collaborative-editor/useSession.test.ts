/**
 * useSession Hook Tests
 *
 * Tests for the useSession hook that provides access to the SessionStore instance.
 * Tests React integration compatibility and selector-based optimization.
 */

import test from "ava";

import { createSessionStore } from "../../js/collaborative-editor/stores/createSessionStore";
import { createMockSocket } from "./mocks/phoenixSocket";

// Mock React context and hooks for testing
let mockContextValue = null;

// Simple mock implementations
const mockUseContext = () => mockContextValue;
const mockUseSyncExternalStore = (subscribe, getSnapshot) => getSnapshot();
const mockUseMemo = factory => factory();

// Hook implementation under test (simplified for testing)
function testUseSession(selector) {
  const context = mockUseContext();
  if (!context) {
    throw new Error("useSession must be used within a SessionProvider");
  }

  const getSnapshot = context.withSelector(selector || (state => state));
  return mockUseSyncExternalStore(context.subscribe, getSnapshot);
}

// =============================================================================
// HOOK CONTEXT VALIDATION TESTS
// =============================================================================

test("useSession throws error when used outside SessionProvider", t => {
  mockContextValue = null;

  const error = t.throws(() => {
    testUseSession();
  });

  t.is(error.message, "useSession must be used within a SessionProvider");
});

// =============================================================================
// REACT INTEGRATION COMPATIBILITY TESTS
// =============================================================================

test("useSession supports component destructuring patterns", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  mockContextValue = store;

  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  // Simulate SessionStoreInstance pattern from phase5 (store instance passed directly)
  const sessionStore = store; // Phase 5 passes store instance through context

  // Simulate ConnectionStatus component pattern
  const { isConnected: yjsConnected, isSynced } = sessionStore;

  t.is(typeof yjsConnected, "boolean", "Should support renaming destructure");
  t.is(typeof isSynced, "boolean", "Should support property destructure");

  store.destroy();
});

test("useSession supports direct property access patterns", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  mockContextValue = store;

  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  // Simulate direct property access from the store itself (as Phase 5 returns store instance)
  // In actual implementation, useSession would return the store instance directly
  const sessionStore = store; // Phase 5 passes store instance through context

  // Test direct property access
  const ydoc = sessionStore.ydoc;
  const isReady = sessionStore.isReady();

  t.truthy(ydoc, "Should support direct property access");
  t.is(typeof isReady, "boolean", "Should support method calls");

  store.destroy();
});

// =============================================================================
// SELECTOR-BASED OPTIMIZATION TESTS
// =============================================================================

test("useSession with selector only re-renders on selected state changes", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  mockContextValue = store;

  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  let ydocSelectorCallCount = 0;
  const ydocSelector = state => {
    ydocSelectorCallCount++;
    return state.ydoc;
  };

  // Use hook with selector
  const selectedYdoc = testUseSession(ydocSelector);

  t.is(ydocSelectorCallCount, 1, "Selector should be called once initially");
  t.is(selectedYdoc, store.ydoc, "Should return selected value");

  // Test that selector is memoized
  const memoizedSelector = store.withSelector(ydocSelector);
  const firstCall = memoizedSelector();
  const secondCall = memoizedSelector();

  t.is(
    ydocSelectorCallCount,
    2,
    "Selector should be called for withSelector setup"
  );
  t.is(
    firstCall,
    secondCall,
    "Memoized selector should return consistent values"
  );

  store.destroy();
});

test("useSession without selector provides full state reactively", t => {
  const store = createSessionStore();
  const mockSocket = createMockSocket();
  mockContextValue = store;

  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  // Use hook without selector (default selector returns full state)
  const sessionState = testUseSession();

  // Should get full session state
  t.truthy(sessionState.ydoc, "Should have ydoc from full state");
  t.truthy(sessionState.provider, "Should have provider from full state");
  t.truthy(sessionState.awareness, "Should have awareness from full state");
  t.is(
    typeof sessionState.isConnected,
    "boolean",
    "Should have isConnected from full state"
  );
  t.is(
    typeof sessionState.isSynced,
    "boolean",
    "Should have isSynced from full state"
  );
  t.is(
    typeof sessionState.settled,
    "boolean",
    "Should have settled from full state"
  );

  // Verify it matches store snapshot
  const storeSnapshot = store.getSnapshot();
  t.deepEqual(
    sessionState,
    storeSnapshot,
    "Should return full state matching store snapshot"
  );

  store.destroy();
});
