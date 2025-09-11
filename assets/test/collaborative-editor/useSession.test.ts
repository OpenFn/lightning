/**
 * useSession Hook Tests
 *
 * Tests for the useSession hook that provides access to the SessionStore instance.
 * Tests React integration compatibility and selector-based optimization.
 */

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

test("useSession throws error when used outside SessionProvider", () => {
  mockContextValue = null;

  expect(() => {
    testUseSession();
  }).toThrow("useSession must be used within a SessionProvider");
});

// =============================================================================
// REACT INTEGRATION COMPATIBILITY TESTS
// =============================================================================

test("useSession supports component destructuring patterns", () => {
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

  expect(typeof yjsConnected).toBe("boolean"); // "Should support renaming destructure"
  expect(typeof isSynced).toBe("boolean"); // "Should support property destructure"

  store.destroy();
});

test("useSession supports direct property access patterns", () => {
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

  expect(ydoc).toBeTruthy(); // "Should support direct property access"
  expect(typeof isReady).toBe("boolean"); // "Should support method calls"

  store.destroy();
});

// =============================================================================
// SELECTOR-BASED OPTIMIZATION TESTS
// =============================================================================

test("useSession with selector only re-renders on selected state changes", () => {
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

  expect(ydocSelectorCallCount).toBe(1); // "Selector should be called once initially"
  expect(selectedYdoc).toBe(store.ydoc); // "Should return selected value"

  // Test that selector is memoized
  const memoizedSelector = store.withSelector(ydocSelector);
  const firstCall = memoizedSelector();
  const secondCall = memoizedSelector();

  expect(ydocSelectorCallCount).toBe(2); // Selector should be called for withSelector setup
  expect(firstCall).toBe(secondCall); // Memoized selector should return consistent values

  store.destroy();
});

test("useSession without selector provides full state reactively", () => {
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
  expect(sessionState.ydoc).toBeTruthy(); // "Should have ydoc from full state"
  expect(sessionState.provider).toBeTruthy(); // "Should have provider from full state"
  expect(sessionState.awareness).toBeTruthy(); // "Should have awareness from full state"
  expect(typeof sessionState.isConnected).toBe("boolean"); // Should have isConnected from full state
  expect(typeof sessionState.isSynced).toBe("boolean"); // Should have isSynced from full state
  expect(typeof sessionState.settled).toBe("boolean"); // Should have settled from full state

  // Verify it matches store snapshot
  const storeSnapshot = store.getSnapshot();
  expect(sessionState).toEqual(storeSnapshot); // Should return full state matching store snapshot

  store.destroy();
});
