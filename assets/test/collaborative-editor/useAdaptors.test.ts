/**
 * Tests for useAdaptors React hooks
 *
 * Tests the adaptor management hooks that provide convenient access
 * to adaptor functionality from React components using the SessionProvider context.
 */

import test from "ava";

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

// Since we can't easily test React hooks directly with Ava, we'll test the hook logic
// by directly testing the store interactions and selector behavior

interface TestContext {
  adaptorStore: AdaptorStoreInstance;
  mockSession: ReturnType<typeof createMockSessionContext>;
}

test.beforeEach(t => {
  // Create fresh store for each test
  const adaptorStore = createAdaptorStore();
  const mockSession = createMockSessionContext(adaptorStore);
  setMockSessionValue(mockSession);

  t.context = {
    adaptorStore,
    mockSession,
  };
});

// =============================================================================
// useAdaptors Hook Tests
// =============================================================================

test("useAdaptors: default selector returns all adaptors", t => {
  const { adaptorStore } = t.context as TestContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test default selector behavior (returns state.adaptors)
  const defaultSelector = (state: AdaptorState) => state.adaptors;
  const selector = adaptorStore.withSelector(defaultSelector);

  const result = selector();

  t.deepEqual(result, mockAdaptorsList);
});

test("useAdaptors: custom selector returns selected data", t => {
  const { adaptorStore } = t.context as TestContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);
  adaptorStore.setLoading(false);
  adaptorStore.setError(null);

  // Test custom selector that returns just adaptor names
  const nameSelector = (state: AdaptorState) => state.adaptors.map(a => a.name);
  const selector = adaptorStore.withSelector(nameSelector);

  const result = selector();

  t.deepEqual(
    result,
    mockAdaptorsList.map(a => a.name)
  );
});

test("useAdaptors: selector with memoization", t => {
  const { adaptorStore } = t.context as TestContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test that withSelector provides stable references
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  );

  const result1 = selector();
  const result2 = selector();

  // Results should be the same reference due to memoization
  t.is(result1, result2);
  t.deepEqual(result1, mockAdaptorsList);
});

test("useAdaptors: handles empty adaptors list", t => {
  const { adaptorStore } = t.context as TestContext;

  // Don't set any adaptors (should start empty)
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  );

  const result = selector();

  t.deepEqual(result, []);
});

test("useAdaptors: complex selector with filtering", t => {
  const { adaptorStore } = t.context as TestContext;

  // Set up test data
  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test complex selector that filters adaptors with multiple versions
  const multiVersionSelector = (state: AdaptorState) =>
    state.adaptors.filter(a => a.versions.length > 1);
  const selector = adaptorStore.withSelector(multiVersionSelector);

  const result = selector();

  t.is(result.length, 3); // All mock adaptors have multiple versions
  t.is(result[0]?.name, "@openfn/language-http");
});

// =============================================================================
// useAdaptorsLoading Hook Tests
// =============================================================================

test("useAdaptorsLoading: returns loading state", t => {
  const { adaptorStore } = t.context as TestContext;

  // Test initial loading state
  adaptorStore.setLoading(true);

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.isLoading
  );
  const result = selector();

  t.is(result, true);
});

test("useAdaptorsLoading: updates when loading state changes", t => {
  const { adaptorStore } = t.context as TestContext;

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

  t.is(values[0], false); // Initial state
  t.true(callCount >= 1);
});

// =============================================================================
// useAdaptorsError Hook Tests
// =============================================================================

test("useAdaptorsError: returns error state", t => {
  const { adaptorStore } = t.context as TestContext;

  const errorMessage = "Failed to load adaptors";
  adaptorStore.setError(errorMessage);

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.error
  );
  const result = selector();

  t.is(result, errorMessage);
});

test("useAdaptorsError: returns null when no error", t => {
  const { adaptorStore } = t.context as TestContext;

  adaptorStore.setError(null);

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.error
  );
  const result = selector();

  t.is(result, null);
});

test("useAdaptorsError: updates when error state changes", t => {
  const { adaptorStore } = t.context as TestContext;

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

  t.is(values[0], null); // Initial state
});

// =============================================================================
// useAdaptorCommands Hook Tests
// =============================================================================

test("useAdaptorCommands: returns command functions", t => {
  const { adaptorStore } = t.context as TestContext;

  // Test that commands are available (we can't easily test the full hook, but we can test the store provides them)
  t.is(typeof adaptorStore.requestAdaptors, "function");
  t.is(typeof adaptorStore.setAdaptors, "function");
  t.is(typeof adaptorStore.clearError, "function");
});

test("useAdaptorCommands: setAdaptors command works", t => {
  const { adaptorStore } = t.context as TestContext;

  // Test setAdaptors command
  adaptorStore.setAdaptors(mockAdaptorsList);

  const state = adaptorStore.getSnapshot();
  t.deepEqual(state.adaptors, mockAdaptorsList);
});

test("useAdaptorCommands: clearError command works", t => {
  const { adaptorStore } = t.context as TestContext;

  // Set an error first
  adaptorStore.setError("Test error");
  t.is(adaptorStore.getSnapshot().error, "Test error");

  // Clear the error
  adaptorStore.clearError();
  t.is(adaptorStore.getSnapshot().error, null);
});

// =============================================================================
// useAdaptor Hook Tests (find specific adaptor by name)
// =============================================================================

test("useAdaptor: finds existing adaptor by name", t => {
  const { adaptorStore } = t.context as TestContext;

  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test finding specific adaptor
  const adaptorName = "@openfn/language-http";
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) =>
      state.adaptors.find(adaptor => adaptor.name === adaptorName) || null
  );

  const result = selector();

  t.not(result, null);
  t.is(result?.name, adaptorName);
  t.is(result?.latest, "2.1.0");
});

test("useAdaptor: returns null for non-existent adaptor", t => {
  const { adaptorStore } = t.context as TestContext;

  adaptorStore.setAdaptors(mockAdaptorsList);

  // Test finding non-existent adaptor
  const selector = adaptorStore.withSelector(
    (state: AdaptorState) =>
      state.adaptors.find(adaptor => adaptor.name === "@openfn/nonexistent") ||
      null
  );

  const result = selector();

  t.is(result, null);
});

test("useAdaptor: updates when adaptors change", t => {
  const { adaptorStore } = t.context as TestContext;

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
  t.is(values[0], null);

  // Add adaptors
  adaptorStore.setAdaptors(mockAdaptorsList);

  unsubscribe();
  hookTester.cleanup();
});

// =============================================================================
// Integration Tests
// =============================================================================

test("hooks integration: all hooks work together", t => {
  const { adaptorStore } = t.context as TestContext;

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

  t.deepEqual(initialAdaptors, []);
  t.is(initialLoading, false);
  t.is(initialError, null);

  // Set loading state
  adaptorStore.setLoading(true);
  t.is(
    adaptorStore.withSelector((state: AdaptorState) => state.isLoading)(),
    true
  );

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

  t.deepEqual(finalAdaptors, mockAdaptorsList);
  t.is(finalLoading, false);
  t.not(specificAdaptor, null);
  t.is(specificAdaptor?.name, "@openfn/language-http");
});

test("hooks integration: error handling works across all hooks", t => {
  const { adaptorStore } = t.context as TestContext;

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

  t.is(error, errorMessage);
  t.is(loading, false); // setError should clear loading
  t.deepEqual(adaptors, []); // adaptors should still be empty

  // Clear error
  adaptorStore.clearError();
  t.is(adaptorStore.withSelector((state: AdaptorState) => state.error)(), null);
});

// =============================================================================
// Edge Cases
// =============================================================================

test("hooks: handle rapid state changes", t => {
  const { adaptorStore } = t.context as TestContext;

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

  t.deepEqual(finalState.adaptors, mockAdaptorsList);
  t.is(finalState.isLoading, false);
  t.is(finalState.error, null);
  t.is(typeof finalState.lastUpdated, "number");
});

test("hooks: selector referential stability", t => {
  const { adaptorStore } = t.context as TestContext;

  const selector = adaptorStore.withSelector(
    (state: AdaptorState) => state.adaptors
  );

  // Same selector should return same reference when data hasn't changed
  const result1 = selector();
  const result2 = selector();
  t.is(result1, result2);

  // After changing data, should return new reference
  adaptorStore.setAdaptors(mockAdaptorsList);
  const result3 = selector();
  t.not(result1, result3);
});
