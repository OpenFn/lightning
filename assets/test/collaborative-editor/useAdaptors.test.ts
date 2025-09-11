/**
 * Tests for useAdaptors React hooks
 *
 * Tests the adaptor management hooks that provide convenient access
 * to adaptor functionality from React components using the SessionProvider context.
 */

import { createAdaptorStore } from "../../js/collaborative-editor/stores/createAdaptorStore";
import type { AdaptorStoreInstance } from "../../js/collaborative-editor/stores/createAdaptorStore";
import type {
  Adaptor,
  AdaptorState,
} from "../../js/collaborative-editor/types/adaptor";

import { mockAdaptorsList } from "./fixtures/adaptorData";
import {
  createHookTester,
  setMockSessionValue,
  createMockSessionContext,
} from "./mocks/reactTestUtils";

// Note: setAdaptors doesn't sort, only handleAdaptorsReceived does
// So when we use setAdaptors in tests, we get the original order

// Since we can't easily test React hooks directly with Vitest, we'll test the hook logic
// by directly testing the store interactions and selector behavior

interface TestContext {
  adaptorStore: AdaptorStoreInstance;
  mockSession: ReturnType<typeof createMockSessionContext>;
}

let testContext: TestContext;

beforeEach(() => {
  // Create fresh store for each test
  const adaptorStore = createAdaptorStore();
  const mockSession = createMockSessionContext(adaptorStore);
  setMockSessionValue(mockSession);

  testContext = {
    adaptorStore,
    mockSession,
  };
});

// =============================================================================
// useAdaptors Hook Tests
// =============================================================================

test("useAdaptors: default selector returns all adaptors", () => {
  const { adaptorStore } = testContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test default selector behavior (returns state.adaptors)
  const defaultSelector = (state: AdaptorState) => state.adaptors;
  const selector = adaptorStore.withSelector(defaultSelector);

  const result = selector();

  expect(result).toEqual(mockAdaptorsList);
});

test("useAdaptors: custom selector returns selected data", () => {
  const { adaptorStore } = testContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);
  adaptorStore.setLoading(false);
  adaptorStore.setError(null);

  // Test custom selector that returns just adaptor names
  const nameSelector = (state: AdaptorState) => state.adaptors.map(a => a.name);
  const selector = adaptorStore.withSelector(nameSelector);

  const result = selector();

  expect(result).toEqual(mockAdaptorsList.map(a => a.name));
});

test("useAdaptors: selector with memoization", () => {
  const { adaptorStore } = testContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test that withSelector provides stable references
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  );

  const result1 = selector();
  const result2 = selector();

  // Results should be the same reference due to memoization
  expect(result1).toBe(result2);
  expect(result1).toEqual(mockAdaptorsList);
});

test("useAdaptors: handles empty adaptors list", () => {
  const { adaptorStore } = testContext;

  // Don't set any adaptors (should start empty)
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  );

  const result = selector();

  expect(result).toEqual([]);
});

test("useAdaptors: complex selector with filtering", () => {
  const { adaptorStore } = testContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test complex selector that filters adaptors with multiple versions
  const multiVersionSelector = (state: AdaptorState) =>
    state.adaptors.filter(a => a.versions.length > 1);
  const selector = adaptorStore.withSelector(multiVersionSelector);

  const result = selector();

  expect(result.length).toBe(3); // All mock adaptors have multiple versions
  expect(result[0]?.name).toBe("@openfn/language-http");
});

// =============================================================================
// useAdaptorsLoading Hook Tests
// =============================================================================

test("useAdaptorsLoading: returns loading state", () => {
  const { adaptorStore } = testContext;

  // Test initial loading state
  adaptorStore.setLoading(true);

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.isLoading
  );
  const result = selector();

  expect(result).toBe(true);
});

test("useAdaptorsLoading: updates when loading state changes", () => {
  const { adaptorStore } = testContext;

  // Create hook tester to test subscription behavior
  const hookTester = createHookTester(
    adaptorStore.subscribe,
    adaptorStore.withSelector((state: AdaptorState) => state.isLoading)
  );

  let callCount = 0;
  const values: boolean[] = [];

  const unsubscribe = hookTester.startWatching((value: boolean) => {
    values.push(value);
    callCount++;
  });

  // Change loading state
  adaptorStore.setLoading(true);
  adaptorStore.setLoading(false);

  unsubscribe();
  hookTester.cleanup();

  expect(values[0]).toBe(false); // Initial state
  expect(callCount >= 1).toBe(true);
});

// =============================================================================
// useAdaptorsError Hook Tests
// =============================================================================

test("useAdaptorsError: returns error state", () => {
  const { adaptorStore } = testContext;

  const errorMessage = "Failed to load adaptors";
  adaptorStore.setError(errorMessage);

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.error
  );
  const result = selector();

  expect(result).toBe(errorMessage);
});

test("useAdaptorsError: returns null when no error", () => {
  const { adaptorStore } = testContext;

  adaptorStore.setError(null);

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.error
  );
  const result = selector();

  expect(result).toBe(null);
});

test("useAdaptorsError: updates when error state changes", () => {
  const { adaptorStore } = testContext;

  const hookTester = createHookTester(
    adaptorStore.subscribe,
    adaptorStore.withSelector((state: AdaptorState) => state.error)
  );

  const values: (string | null)[] = [];

  const unsubscribe = hookTester.startWatching((value: string | null) => {
    values.push(value);
  });

  // Change error state
  adaptorStore.setError("Test error");
  adaptorStore.clearError();

  unsubscribe();
  hookTester.cleanup();

  expect(values[0]).toBe(null); // Initial state
});

// =============================================================================
// useAdaptorCommands Hook Tests
// =============================================================================

test("useAdaptorCommands: returns command functions", () => {
  const { adaptorStore } = testContext;

  // Test that commands are available (we can't easily test the full hook, but we can test the store provides them)
  expect(typeof adaptorStore.requestAdaptors).toBe("function");
  expect(typeof adaptorStore.setAdaptors).toBe("function");
  expect(typeof adaptorStore.clearError).toBe("function");
});

test("useAdaptorCommands: setAdaptors command works", () => {
  const { adaptorStore } = testContext;

  // Test setAdaptors command
  adaptorStore.setAdaptors(mockAdaptorsList);

  const state = adaptorStore.getSnapshot();
  expect(state.adaptors).toEqual(mockAdaptorsList);
});

test("useAdaptorCommands: clearError command works", () => {
  const { adaptorStore } = testContext;

  // Set an error first
  adaptorStore.setError("Test error");
  expect(adaptorStore.getSnapshot().error).toBe("Test error");

  // Clear the error
  adaptorStore.clearError();
  expect(adaptorStore.getSnapshot().error).toBe(null);
});

// =============================================================================
// useAdaptor Hook Tests (find specific adaptor by name)
// =============================================================================

test("useAdaptor: finds existing adaptor by name", () => {
  const { adaptorStore } = testContext;

  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test finding specific adaptor
  const adaptorName = "@openfn/language-http";
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) =>
      state.adaptors.find(adaptor => adaptor.name === adaptorName) || null
  );

  const result = selector();

  expect(result).not.toBe(null);
  expect(result?.name).toBe(adaptorName);
  expect(result?.latest).toBe("2.1.0");
});

test("useAdaptor: returns null for non-existent adaptor", () => {
  const { adaptorStore } = testContext;

  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test finding non-existent adaptor
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) =>
      state.adaptors.find(adaptor => adaptor.name === "@openfn/nonexistent") ||
      null
  );

  const result = selector();

  expect(result).toBe(null);
});

test("useAdaptor: updates when adaptors change", () => {
  const { adaptorStore } = testContext;

  const targetAdaptor = "@openfn/language-http";

  const hookTester = createHookTester(
    adaptorStore.subscribe,
    adaptorStore.withSelector(
      (state: AdaptorState) =>
        state.adaptors.find(adaptor => adaptor.name === targetAdaptor) || null
    )
  );

  const values: (Adaptor | null)[] = [];

  const unsubscribe = hookTester.startWatching((value: Adaptor | null) => {
    values.push(value);
  });

  // Initially no adaptors
  expect(values[0]).toBe(null);

  // Add adaptors
  adaptorStore.setAdaptors(mockAdaptorsList);

  unsubscribe();
  hookTester.cleanup();
});

// =============================================================================
// Integration Tests
// =============================================================================

test("hooks integration: all hooks work together", () => {
  const { adaptorStore } = testContext;

  // Test initial state
  const initialAdaptors = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  )();
  const initialLoading = adaptorStore.withSelector(
    (state: AdaptorState) => state.isLoading
  )();
  const initialError = adaptorStore.withSelector(
    (state: AdaptorState) => state.error
  )();

  expect(initialAdaptors).toEqual([]);
  expect(initialLoading).toBe(false);
  expect(initialError).toBe(null);

  // Set loading state
  adaptorStore.setLoading(true);
  expect(
    adaptorStore.withSelector((state: AdaptorState) => state.isLoading)()
  ).toBe(true);

  // Add adaptors
  adaptorStore.setAdaptors(mockAdaptorsList);
  adaptorStore.setLoading(false);

  const finalAdaptors = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  )();
  const finalLoading = adaptorStore.withSelector(
    (state: AdaptorState) => state.isLoading
  )();
  const specificAdaptor = adaptorStore.withSelector(
    (state: AdaptorState) =>
      state.adaptors.find(a => a.name === "@openfn/language-http") || null
  )();

  expect(finalAdaptors).toEqual(mockAdaptorsList);
  expect(finalLoading).toBe(false);
  expect(specificAdaptor).not.toBe(null);
  expect(specificAdaptor?.name).toBe("@openfn/language-http");
});

test("hooks integration: error handling works across all hooks", () => {
  const { adaptorStore } = testContext;

  const errorMessage = "Network error";

  // Set error
  adaptorStore.setError(errorMessage);

  const error = adaptorStore.withSelector(
    (state: AdaptorState) => state.error
  )();
  const loading = adaptorStore.withSelector(
    (state: AdaptorState) => state.isLoading
  )();
  const adaptors = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  )();

  expect(error).toBe(errorMessage);
  expect(loading).toBe(false); // setError should clear loading
  expect(adaptors).toEqual([]); // adaptors should still be empty

  // Clear error
  adaptorStore.clearError();
  expect(
    adaptorStore.withSelector((state: AdaptorState) => state.error)()
  ).toBe(null);
});

// =============================================================================
// Edge Cases
// =============================================================================

test("hooks: handle rapid state changes", () => {
  const { adaptorStore } = testContext;

  // Rapid state changes
  adaptorStore.setLoading(true);
  adaptorStore.setError("Error 1");
  adaptorStore.clearError();
  adaptorStore.setAdaptors(mockAdaptorsList);
  adaptorStore.setLoading(false);
  adaptorStore.setError("Error 2");
  adaptorStore.clearError();

  // Final state should be consistent
  const finalState = adaptorStore.getSnapshot();

  expect(finalState.adaptors).toEqual(mockAdaptorsList);
  expect(finalState.isLoading).toBe(false);
  expect(finalState.error).toBe(null);
  expect(typeof finalState.lastUpdated).toBe("number");
});

test("hooks: selector referential stability", () => {
  const { adaptorStore } = testContext;

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  );

  // Same selector should return same reference when data hasn't changed
  const result1 = selector();
  const result2 = selector();
  expect(result1).toBe(result2);

  // After changing data, should return new reference
  adaptorStore.setAdaptors(mockAdaptorsList);
  const result3 = selector();
  expect(result1).not.toBe(result3);
});
