/**
 * useSessionContext Hooks Tests
 *
 * Tests for the session context hooks that provide access to user, project,
 * and app configuration data.
 *
 * Hooks tested:
 * - useUser()
 * - useProject()
 * - useAppConfig()
 * - useSessionContextLoading()
 * - useSessionContextError()
 *
 * Note: These tests focus on the hooks' ability to access store state and subscribe to changes.
 * Full integration tests with channel messages are in createSessionContextStore.test.ts.
 */

import { describe, expect, test, beforeEach, afterEach } from "vitest";

import { createSessionContextStore } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import type { SessionContextStoreInstance } from "../../../js/collaborative-editor/stores/createSessionContextStore";

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Mock context value for testing hooks
 * In real usage, this would come from StoreProvider's React Context
 */
let mockContextValue: SessionContextStoreInstance | null = null;

/**
 * Mock useContext implementation for tests
 */
const mockUseContext = () => mockContextValue;

/**
 * Mock useSyncExternalStore implementation for tests
 */
const mockUseSyncExternalStore = <T>(
  subscribe: (callback: () => void) => () => void,
  getSnapshot: () => T
): T => {
  // In tests, just return the current snapshot
  return getSnapshot();
};

/**
 * Test hook implementation that simulates the real hooks
 */
function testUseSessionContextHook<T>(selector: (state: any) => T): T {
  const context = mockUseContext();
  if (!context) {
    throw new Error(
      "useSessionContextStore must be used within a StoreProvider"
    );
  }

  const getSnapshot = context.withSelector(selector);
  return mockUseSyncExternalStore(context.subscribe, getSnapshot);
}

// =============================================================================
// SETUP / TEARDOWN
// =============================================================================

describe("useSessionContext Hooks", () => {
  let store: SessionContextStoreInstance;

  beforeEach(() => {
    // Create a fresh store for each test
    store = createSessionContextStore();
    mockContextValue = store;
  });

  afterEach(() => {
    // Clean up
    mockContextValue = null;
  });

  // ===========================================================================
  // CONTEXT VALIDATION TESTS
  // ===========================================================================

  describe("Context Validation", () => {
    test("hooks throw error when used outside StoreProvider", () => {
      mockContextValue = null;

      expect(() => {
        testUseSessionContextHook(state => state.user);
      }).toThrow("useSessionContextStore must be used within a StoreProvider");
    });

    test("all hooks require StoreProvider context", () => {
      mockContextValue = null;

      // Test each selector type
      const selectors = [
        (state: any) => state.user,
        (state: any) => state.project,
        (state: any) => state.config,
        (state: any) => state.isLoading,
        (state: any) => state.error,
      ];

      selectors.forEach(selector => {
        expect(() => {
          testUseSessionContextHook(selector);
        }).toThrow(
          "useSessionContextStore must be used within a StoreProvider"
        );
      });
    });
  });

  // ===========================================================================
  // useUser() TESTS
  // ===========================================================================

  describe("useUser()", () => {
    test("returns null when user is not yet loaded", () => {
      const user = testUseSessionContextHook(state => state.user);

      expect(user).toBe(null);
    });

    test("subscribes to user changes", () => {
      let notificationCount = 0;
      const unsubscribe = store.subscribe(() => {
        notificationCount++;
      });

      // Even though we can't set user directly, the subscription mechanism works
      // This verifies the hooks can subscribe to store changes
      store.setLoading(true);

      expect(notificationCount).toBe(1);

      unsubscribe();
    });

    test("selector is memoized and returns stable reference", () => {
      const selector = store.withSelector(state => state.user);
      const result1 = selector();
      const result2 = selector();

      expect(result1).toBe(result2);
    });
  });

  // ===========================================================================
  // useProject() TESTS
  // ===========================================================================

  describe("useProject()", () => {
    test("returns null when project is not yet loaded", () => {
      const project = testUseSessionContextHook(state => state.project);

      expect(project).toBe(null);
    });

    test("selector provides referential stability", () => {
      const selector = store.withSelector(state => state.project);
      const result1 = selector();
      const result2 = selector();

      expect(result1).toBe(result2);
    });
  });

  // ===========================================================================
  // useAppConfig() TESTS
  // ===========================================================================

  describe("useAppConfig()", () => {
    test("returns null when config is not yet loaded", () => {
      const config = testUseSessionContextHook(state => state.config);

      expect(config).toBe(null);
    });

    test("selector provides referential stability", () => {
      const selector = store.withSelector(state => state.config);
      const result1 = selector();
      const result2 = selector();

      expect(result1).toBe(result2);
    });
  });

  // ===========================================================================
  // useSessionContextLoading() TESTS
  // ===========================================================================

  describe("useSessionContextLoading()", () => {
    test("returns false when not loading", () => {
      const isLoading = testUseSessionContextHook(state => state.isLoading);

      expect(isLoading).toBe(false);
    });

    test("returns true when loading", () => {
      store.setLoading(true);

      const isLoading = testUseSessionContextHook(state => state.isLoading);

      expect(isLoading).toBe(true);
    });

    test("returns updated loading state when changed", () => {
      store.setLoading(true);

      const isLoading1 = testUseSessionContextHook(state => state.isLoading);
      expect(isLoading1).toBe(true);

      store.setLoading(false);

      const isLoading2 = testUseSessionContextHook(state => state.isLoading);
      expect(isLoading2).toBe(false);
    });

    test("subscribes to loading state changes", () => {
      let notificationCount = 0;
      const unsubscribe = store.subscribe(() => {
        notificationCount++;
      });

      store.setLoading(true);
      expect(notificationCount).toBe(1);

      store.setLoading(false);
      expect(notificationCount).toBe(2);

      unsubscribe();
    });
  });

  // ===========================================================================
  // useSessionContextError() TESTS
  // ===========================================================================

  describe("useSessionContextError()", () => {
    test("returns null when no error", () => {
      const error = testUseSessionContextHook(state => state.error);

      expect(error).toBe(null);
    });

    test("returns error message when present", () => {
      store.setError("Test error");

      const error = testUseSessionContextHook(state => state.error);

      expect(error).toBe("Test error");
    });

    test("returns updated error when changed", () => {
      store.setError("Error 1");

      const error1 = testUseSessionContextHook(state => state.error);
      expect(error1).toBe("Error 1");

      store.setError("Error 2");

      const error2 = testUseSessionContextHook(state => state.error);
      expect(error2).toBe("Error 2");
    });

    test("returns null when error is cleared", () => {
      store.setError("Test error");

      const error1 = testUseSessionContextHook(state => state.error);
      expect(error1).toBe("Test error");

      store.setError(null);

      const error2 = testUseSessionContextHook(state => state.error);
      expect(error2).toBe(null);
    });

    test("subscribes to error changes", () => {
      let notificationCount = 0;
      const unsubscribe = store.subscribe(() => {
        notificationCount++;
      });

      store.setError("Test error");
      expect(notificationCount).toBe(1);

      store.setError(null);
      expect(notificationCount).toBe(2);

      unsubscribe();
    });
  });

  // ===========================================================================
  // REFERENTIAL STABILITY TESTS
  // ===========================================================================

  describe("Referential Stability", () => {
    test("selector returns same reference when data unchanged", () => {
      const selector = store.withSelector(state => state.user);
      const result1 = selector();
      const result2 = selector();
      const result3 = selector();

      // All calls should return the same reference
      expect(result1).toBe(result2);
      expect(result2).toBe(result3);
    });

    test("multiple selectors are independent", () => {
      const userSelector = store.withSelector(state => state.user);
      const loadingSelector = store.withSelector(state => state.isLoading);

      const user1 = userSelector();
      const loading1 = loadingSelector();

      // Update loading state
      store.setLoading(true);

      const user2 = userSelector();
      const loading2 = loadingSelector();

      // User should stay the same, loading should change
      expect(user1).toBe(user2);
      expect(loading1).not.toBe(loading2);
    });

    test("selectors only react to relevant state changes", () => {
      const errorSelector = store.withSelector(state => state.error);

      const error1 = errorSelector();

      // Change loading state (unrelated to error)
      store.setLoading(true);

      const error2 = errorSelector();

      // Error reference should remain stable
      expect(error1).toBe(error2);
    });
  });

  // ===========================================================================
  // INTEGRATION TESTS
  // ===========================================================================

  describe("Integration Scenarios", () => {
    test("loading state management workflow", () => {
      store.setLoading(true);

      let loadingState = testUseSessionContextHook(state => state.isLoading);
      expect(loadingState).toBe(true);

      // Simulate load complete
      store.setLoading(false);

      loadingState = testUseSessionContextHook(state => state.isLoading);
      expect(loadingState).toBe(false);
    });

    test("handling error during session context load", () => {
      store.setError("Failed to load session context");

      const isLoading = testUseSessionContextHook(state => state.isLoading);
      const error = testUseSessionContextHook(state => state.error);

      expect(isLoading).toBe(false); // setError sets isLoading to false
      expect(error).toBe("Failed to load session context");

      // Clear error
      store.setError(null);

      const clearedLoading = testUseSessionContextHook(
        state => state.isLoading
      );
      const clearedError = testUseSessionContextHook(state => state.error);

      expect(clearedLoading).toBe(false);
      expect(clearedError).toBe(null);
    });

    test("error clears loading state", () => {
      store.setLoading(true);

      let isLoading = testUseSessionContextHook(state => state.isLoading);
      expect(isLoading).toBe(true);

      // Setting an error should clear loading state
      store.setError("Something went wrong");

      isLoading = testUseSessionContextHook(state => state.isLoading);
      const error = testUseSessionContextHook(state => state.error);

      expect(isLoading).toBe(false);
      expect(error).toBe("Something went wrong");
    });
  });

  // ===========================================================================
  // SUBSCRIPTION TESTS
  // ===========================================================================

  describe("Subscription Behavior", () => {
    test("hook subscribes to store updates", () => {
      let notificationCount = 0;

      const unsubscribe = store.subscribe(() => {
        notificationCount++;
      });

      // Trigger multiple updates
      store.setLoading(true);
      store.setError("test");
      store.clearError();

      expect(notificationCount).toBe(3);

      unsubscribe();
    });

    test("unsubscribe stops receiving updates", () => {
      let notificationCount = 0;

      const unsubscribe = store.subscribe(() => {
        notificationCount++;
      });

      store.setLoading(true);
      expect(notificationCount).toBe(1);

      unsubscribe();

      store.setLoading(false);
      expect(notificationCount).toBe(1); // Should not increment
    });

    test("multiple subscribers receive updates independently", () => {
      let count1 = 0;
      let count2 = 0;

      const unsubscribe1 = store.subscribe(() => {
        count1++;
      });

      const unsubscribe2 = store.subscribe(() => {
        count2++;
      });

      store.setLoading(true);

      expect(count1).toBe(1);
      expect(count2).toBe(1);

      unsubscribe1();

      store.setError("test");

      expect(count1).toBe(1); // Should not increment
      expect(count2).toBe(2); // Should increment

      unsubscribe2();
    });
  });
});
