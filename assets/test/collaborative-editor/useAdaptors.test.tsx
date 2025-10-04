/**
 * Tests for useAdaptors React hooks
 *
 * Tests the adaptor management hooks that provide convenient access
 * to adaptor functionality from React components using the StoreProvider context.
 *
 * This file uses real React hook testing with renderHook from @testing-library/react
 * to verify actual React lifecycle behavior including:
 * - Hook mounting and unmounting
 * - Subscription management
 * - Re-render behavior
 * - Context validation
 * - Referential stability
 */

import { act, renderHook, waitFor } from "@testing-library/react";
import type React from "react";
import { describe, expect, test } from "vitest";

import {
  useAdaptor,
  useAdaptorCommands,
  useAdaptors,
  useAdaptorsError,
  useAdaptorsLoading,
} from "../../js/collaborative-editor/hooks/useAdaptors";
import { createSessionStore } from "../../js/collaborative-editor/stores/createSessionStore";

import { SessionContext } from "../../js/collaborative-editor/contexts/SessionProvider";
import { StoreContext } from "../../js/collaborative-editor/contexts/StoreProvider";
import { createAdaptorStore } from "../../js/collaborative-editor/stores/createAdaptorStore";
import { createAwarenessStore } from "../../js/collaborative-editor/stores/createAwarenessStore";
import { createCredentialStore } from "../../js/collaborative-editor/stores/createCredentialStore";
import { createSessionContextStore } from "../../js/collaborative-editor/stores/createSessionContextStore";
import { createWorkflowStore } from "../../js/collaborative-editor/stores/createWorkflowStore";
import { mockAdaptorsList } from "./fixtures/adaptorData";
import { createMockSocket } from "./mocks/phoenixSocket";

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Creates a wrapper component with SessionProvider and StoreProvider contexts
 * Returns the wrapper and store instances for test manipulation
 */
function createWrapper() {
  const sessionStore = createSessionStore();
  const adaptorStore = createAdaptorStore();
  const credentialStore = createCredentialStore();
  const awarenessStore = createAwarenessStore();
  const workflowStore = createWorkflowStore();
  const sessionContextStore = createSessionContextStore();

  const mockSocket = createMockSocket();

  // Initialize the session store
  sessionStore.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  const stores = {
    adaptorStore,
    credentialStore,
    awarenessStore,
    workflowStore,
    sessionContextStore,
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={sessionStore}>
      <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
    </SessionContext.Provider>
  );

  return { wrapper, stores, sessionStore };
}

// =============================================================================
// useAdaptors Hook Tests
// =============================================================================

describe("useAdaptors hooks", () => {
  describe("useAdaptors", () => {
    test("returns all adaptors from store", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      expect(result.current).toEqual([]);
    });

    test("updates when adaptors change", async () => {
      const { wrapper, stores } = createWrapper();

      const { result } = renderHook(() => useAdaptors(), { wrapper });

      expect(result.current).toEqual([]);

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(result.current).toHaveLength(3);
      });
    });

    test("returns referentially stable array when data unchanged", () => {
      const { wrapper, stores } = createWrapper();

      stores.adaptorStore.setAdaptors(mockAdaptorsList);

      const { result, rerender } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      const firstResult = result.current;
      rerender();
      const secondResult = result.current;

      // Should be same reference when data hasn't changed
      expect(firstResult).toBe(secondResult);
    });

    test("returns new reference when adaptors actually change", async () => {
      const { wrapper, stores } = createWrapper();

      const { result } = renderHook(() => useAdaptors(), { wrapper });

      const firstResult = result.current;

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(result.current).not.toBe(firstResult);
        expect(result.current).toHaveLength(3);
      });
    });

    test("subscription cleanup on unmount", () => {
      const { wrapper, stores } = createWrapper();

      const { unmount } = renderHook(() => useAdaptors(), { wrapper });

      // Store should have subscribers
      const stateBefore = stores.adaptorStore.getSnapshot();
      expect(stateBefore).toBeDefined();

      // Unmount should clean up subscription
      unmount();

      // Store should still work after unmount
      const stateAfter = stores.adaptorStore.getSnapshot();
      expect(stateAfter).toBeDefined();
    });

    test("multiple hooks share same store data", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      const { result: result1 } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      const { result: result2 } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      await waitFor(() => {
        expect(result1.current).toHaveLength(3);
        expect(result2.current).toHaveLength(3);
      });

      // Should be same reference due to memoization
      expect(result1.current).toBe(result2.current);
    });

    test("handles empty adaptors list", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(() => useAdaptors(), { wrapper });

      expect(result.current).toEqual([]);
      expect(Array.isArray(result.current)).toBe(true);
    });

    test("hook re-renders only when adaptors change", async () => {
      const { wrapper, stores } = createWrapper();
      let renderCount = 0;

      const { result } = renderHook(
        () => {
          renderCount++;
          return useAdaptors();
        },
        { wrapper }
      );

      const initialRenderCount = renderCount;
      expect(result.current).toEqual([]);

      // Change unrelated state (loading)
      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      // Should not re-render since adaptors didn't change
      expect(renderCount).toBe(initialRenderCount);

      // Now change adaptors
      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(renderCount).toBeGreaterThan(initialRenderCount);
        expect(result.current).toHaveLength(3);
      });
    });

    test("throws error when used outside StoreProvider", () => {
      expect(() => {
        renderHook(() => useAdaptors());
      }).toThrow("useAdaptorStore must be used within a StoreProvider");
    });
  });

  // =============================================================================
  // useAdaptorsLoading Hook Tests
  // =============================================================================

  describe("useAdaptorsLoading", () => {
    test("returns loading state", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(() => useAdaptorsLoading(), {
        wrapper,
      });

      expect(result.current).toBe(false);
      expect(typeof result.current).toBe("boolean");
    });

    test("updates when loading state changes", async () => {
      const { wrapper, stores } = createWrapper();

      const { result } = renderHook(() => useAdaptorsLoading(), { wrapper });

      expect(result.current).toBe(false);

      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      await waitFor(() => {
        expect(result.current).toBe(true);
      });

      act(() => {
        stores.adaptorStore.setLoading(false);
      });

      await waitFor(() => {
        expect(result.current).toBe(false);
      });
    });

    test("subscription cleanup on unmount", () => {
      const { wrapper } = createWrapper();

      const { unmount } = renderHook(() => useAdaptorsLoading(), { wrapper });

      unmount();
      // Should not throw or cause issues
    });

    test("hook re-renders only when loading changes", async () => {
      const { wrapper, stores } = createWrapper();
      let renderCount = 0;

      const { result } = renderHook(
        () => {
          renderCount++;
          return useAdaptorsLoading();
        },
        { wrapper }
      );

      const initialRenderCount = renderCount;

      // Change unrelated state (adaptors)
      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      // Should not re-render since loading didn't change
      expect(renderCount).toBe(initialRenderCount);

      // Now change loading
      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      await waitFor(() => {
        expect(renderCount).toBeGreaterThan(initialRenderCount);
        expect(result.current).toBe(true);
      });
    });

    test("multiple hooks get same loading state", async () => {
      const { wrapper, stores } = createWrapper();

      const { result: result1 } = renderHook(() => useAdaptorsLoading(), {
        wrapper,
      });

      const { result: result2 } = renderHook(() => useAdaptorsLoading(), {
        wrapper,
      });

      expect(result1.current).toBe(result2.current);

      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      await waitFor(() => {
        expect(result1.current).toBe(true);
        expect(result2.current).toBe(true);
      });
    });

    test("throws error when used outside StoreProvider", () => {
      expect(() => {
        renderHook(() => useAdaptorsLoading());
      }).toThrow("useAdaptorStore must be used within a StoreProvider");
    });
  });

  // =============================================================================
  // useAdaptorsError Hook Tests
  // =============================================================================

  describe("useAdaptorsError", () => {
    test("returns error state", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(() => useAdaptorsError(), {
        wrapper,
      });

      expect(result.current).toBe(null);
    });

    test("returns null when no error", () => {
      const { wrapper, stores } = createWrapper();

      stores.adaptorStore.setError(null);

      const { result } = renderHook(() => useAdaptorsError(), { wrapper });

      expect(result.current).toBe(null);
    });

    test("updates when error state changes", async () => {
      const { wrapper, stores } = createWrapper();

      const { result } = renderHook(() => useAdaptorsError(), { wrapper });

      expect(result.current).toBe(null);

      const errorMessage = "Failed to load adaptors";
      act(() => {
        stores.adaptorStore.setError(errorMessage);
      });

      await waitFor(() => {
        expect(result.current).toBe(errorMessage);
      });
    });

    test("updates when error is cleared", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setError("Test error");
      });

      const { result } = renderHook(() => useAdaptorsError(), { wrapper });

      await waitFor(() => {
        expect(result.current).toBe("Test error");
      });

      act(() => {
        stores.adaptorStore.clearError();
      });

      await waitFor(() => {
        expect(result.current).toBe(null);
      });
    });

    test("subscription cleanup on unmount", () => {
      const { wrapper } = createWrapper();

      const { unmount } = renderHook(() => useAdaptorsError(), { wrapper });

      unmount();
      // Should not throw or cause issues
    });

    test("hook re-renders only when error changes", async () => {
      const { wrapper, stores } = createWrapper();
      let renderCount = 0;

      const { result } = renderHook(
        () => {
          renderCount++;
          return useAdaptorsError();
        },
        { wrapper }
      );

      const initialRenderCount = renderCount;

      // Change unrelated state (loading)
      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      // Should not re-render since error didn't change
      expect(renderCount).toBe(initialRenderCount);

      // Now change error
      act(() => {
        stores.adaptorStore.setError("Test error");
      });

      await waitFor(() => {
        expect(renderCount).toBeGreaterThan(initialRenderCount);
        expect(result.current).toBe("Test error");
      });
    });

    test("handles multiple error updates", async () => {
      const { wrapper, stores } = createWrapper();

      const { result } = renderHook(() => useAdaptorsError(), { wrapper });

      act(() => {
        stores.adaptorStore.setError("Error 1");
      });

      await waitFor(() => {
        expect(result.current).toBe("Error 1");
      });

      act(() => {
        stores.adaptorStore.setError("Error 2");
      });

      await waitFor(() => {
        expect(result.current).toBe("Error 2");
      });

      act(() => {
        stores.adaptorStore.clearError();
      });

      await waitFor(() => {
        expect(result.current).toBe(null);
      });
    });

    test("throws error when used outside StoreProvider", () => {
      expect(() => {
        renderHook(() => useAdaptorsError());
      }).toThrow("useAdaptorStore must be used within a StoreProvider");
    });
  });

  // =============================================================================
  // useAdaptorCommands Hook Tests
  // =============================================================================

  describe("useAdaptorCommands", () => {
    test("returns stable command functions", () => {
      const { wrapper } = createWrapper();

      const { result, rerender } = renderHook(() => useAdaptorCommands(), {
        wrapper,
      });

      expect(result.current).toHaveProperty("requestAdaptors");
      expect(result.current).toHaveProperty("setAdaptors");
      expect(result.current).toHaveProperty("clearError");

      const commands1 = result.current;
      rerender();
      const commands2 = result.current;

      // Functions should be referentially stable
      expect(commands1.requestAdaptors).toBe(commands2.requestAdaptors);
      expect(commands1.setAdaptors).toBe(commands2.setAdaptors);
      expect(commands1.clearError).toBe(commands2.clearError);
    });

    test("setAdaptors command works", async () => {
      const { wrapper } = createWrapper();

      const { result: commandsResult } = renderHook(
        () => useAdaptorCommands(),
        { wrapper }
      );

      const { result: adaptorsResult } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      expect(adaptorsResult.current).toEqual([]);

      act(() => {
        commandsResult.current.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(adaptorsResult.current).toHaveLength(3);
      });
    });

    test("clearError command works", async () => {
      const { wrapper } = createWrapper();

      const { result: commandsResult } = renderHook(
        () => useAdaptorCommands(),
        { wrapper }
      );

      const { result: errorResult } = renderHook(() => useAdaptorsError(), {
        wrapper,
      });

      act(() => {
        commandsResult.current.setAdaptors(mockAdaptorsList);
      });

      // Trigger an error by setting error state
      act(() => {
        const { stores } = createWrapper();
        stores.adaptorStore.setError("Test error");
      });

      // Note: We need to use the store directly since commands might not trigger error
      const { wrapper: wrapper2, stores } = createWrapper();

      const { result: commands2 } = renderHook(() => useAdaptorCommands(), {
        wrapper: wrapper2,
      });

      const { result: error2 } = renderHook(() => useAdaptorsError(), {
        wrapper: wrapper2,
      });

      act(() => {
        stores.adaptorStore.setError("Test error");
      });

      await waitFor(() => {
        expect(error2.current).toBe("Test error");
      });

      act(() => {
        commands2.current.clearError();
      });

      await waitFor(() => {
        expect(error2.current).toBe(null);
      });

      expect(errorResult.current).toBe(null);
    });

    test("commands don't re-render on unrelated state changes", () => {
      const { wrapper, stores } = createWrapper();
      let renderCount = 0;

      const { result } = renderHook(
        () => {
          renderCount++;
          return useAdaptorCommands();
        },
        { wrapper }
      );

      const initialRenderCount = renderCount;
      expect(result.current).toBeDefined();

      // Change store state
      act(() => {
        stores.adaptorStore.setLoading(true);
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
        stores.adaptorStore.setError("Test error");
      });

      // Commands hook should not re-render
      expect(renderCount).toBe(initialRenderCount);
    });

    test("commands object has correct structure", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(() => useAdaptorCommands(), { wrapper });

      expect(typeof result.current.requestAdaptors).toBe("function");
      expect(typeof result.current.setAdaptors).toBe("function");
      expect(typeof result.current.clearError).toBe("function");
      expect(Object.keys(result.current)).toEqual([
        "requestAdaptors",
        "setAdaptors",
        "clearError",
      ]);
    });

    test("throws error when used outside StoreProvider", () => {
      expect(() => {
        renderHook(() => useAdaptorCommands());
      }).toThrow("useAdaptorStore must be used within a StoreProvider");
    });
  });

  // =============================================================================
  // useAdaptor Hook Tests (find specific adaptor by name)
  // =============================================================================

  describe("useAdaptor", () => {
    test("finds existing adaptor by name", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      const { result } = renderHook(() => useAdaptor("@openfn/language-http"), {
        wrapper,
      });

      await waitFor(() => {
        expect(result.current).not.toBe(null);
        expect(result.current?.name).toBe("@openfn/language-http");
        expect(result.current?.latest).toBe("2.1.0");
      });
    });

    test("returns null for non-existent adaptor", () => {
      const { wrapper, stores } = createWrapper();

      stores.adaptorStore.setAdaptors(mockAdaptorsList);

      const { result } = renderHook(() => useAdaptor("@openfn/nonexistent"), {
        wrapper,
      });

      expect(result.current).toBe(null);
    });

    test("updates when adaptors change", async () => {
      const { wrapper, stores } = createWrapper();

      const { result } = renderHook(() => useAdaptor("@openfn/language-http"), {
        wrapper,
      });

      expect(result.current).toBe(null);

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(result.current).not.toBe(null);
        expect(result.current?.name).toBe("@openfn/language-http");
      });
    });

    test("updates when searching for different adaptor", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      const { result, rerender } = renderHook(({ name }) => useAdaptor(name), {
        wrapper,
        initialProps: { name: "@openfn/language-http" },
      });

      await waitFor(() => {
        expect(result.current?.name).toBe("@openfn/language-http");
      });

      rerender({ name: "@openfn/language-dhis2" });

      await waitFor(() => {
        expect(result.current?.name).toBe("@openfn/language-dhis2");
      });
    });

    test("subscription cleanup on unmount", () => {
      const { wrapper } = createWrapper();

      const { unmount } = renderHook(
        () => useAdaptor("@openfn/language-http"),
        {
          wrapper,
        }
      );

      unmount();
      // Should not throw or cause issues
    });

    test("hook re-renders only when specific adaptor changes", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      let renderCount = 0;

      const { result } = renderHook(
        () => {
          renderCount++;
          return useAdaptor("@openfn/language-http");
        },
        { wrapper }
      );

      await waitFor(() => {
        expect(result.current).not.toBe(null);
      });

      const initialRenderCount = renderCount;

      // Change unrelated state (loading)
      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      // Should not re-render since the specific adaptor didn't change
      expect(renderCount).toBe(initialRenderCount);
    });

    test("handles multiple hooks searching for different adaptors", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      const { result: result1 } = renderHook(
        () => useAdaptor("@openfn/language-http"),
        { wrapper }
      );

      const { result: result2 } = renderHook(
        () => useAdaptor("@openfn/language-dhis2"),
        { wrapper }
      );

      await waitFor(() => {
        expect(result1.current?.name).toBe("@openfn/language-http");
        expect(result2.current?.name).toBe("@openfn/language-dhis2");
      });

      expect(result1.current).not.toBe(result2.current);
    });

    test("returns stable reference when adaptor unchanged", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      const { result, rerender } = renderHook(
        () => useAdaptor("@openfn/language-http"),
        { wrapper }
      );

      await waitFor(() => {
        expect(result.current).not.toBe(null);
      });

      const firstResult = result.current;
      rerender();
      const secondResult = result.current;

      // Should be same reference when adaptor hasn't changed
      expect(firstResult).toBe(secondResult);
    });

    test("throws error when used outside StoreProvider", () => {
      expect(() => {
        renderHook(() => useAdaptor("@openfn/language-http"));
      }).toThrow("useAdaptorStore must be used within a StoreProvider");
    });
  });

  // =============================================================================
  // Integration Tests - Multiple Hooks Working Together
  // =============================================================================

  describe("integration tests", () => {
    test("all hooks work together", async () => {
      const { wrapper, stores } = createWrapper();

      const { result: adaptors } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      const { result: loading } = renderHook(() => useAdaptorsLoading(), {
        wrapper,
      });

      const { result: error } = renderHook(() => useAdaptorsError(), {
        wrapper,
      });

      const { result: commands } = renderHook(() => useAdaptorCommands(), {
        wrapper,
      });

      // Initial state
      expect(adaptors.current).toEqual([]);
      expect(loading.current).toBe(false);
      expect(error.current).toBe(null);

      // Set loading state
      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      await waitFor(() => {
        expect(loading.current).toBe(true);
      });

      // Add adaptors
      act(() => {
        commands.current.setAdaptors(mockAdaptorsList);
        stores.adaptorStore.setLoading(false);
      });

      await waitFor(() => {
        expect(adaptors.current).toHaveLength(3);
        expect(loading.current).toBe(false);
      });
    });

    test("error handling works across all hooks", async () => {
      const { wrapper, stores } = createWrapper();

      const { result: error } = renderHook(() => useAdaptorsError(), {
        wrapper,
      });

      const { result: loading } = renderHook(() => useAdaptorsLoading(), {
        wrapper,
      });

      const { result: commands } = renderHook(() => useAdaptorCommands(), {
        wrapper,
      });

      const errorMessage = "Network error";

      act(() => {
        stores.adaptorStore.setError(errorMessage);
      });

      await waitFor(() => {
        expect(error.current).toBe(errorMessage);
        expect(loading.current).toBe(false); // setError should clear loading
      });

      act(() => {
        commands.current.clearError();
      });

      await waitFor(() => {
        expect(error.current).toBe(null);
      });
    });

    test("useAdaptor integrates with useAdaptors", async () => {
      const { wrapper, stores } = createWrapper();

      const { result: adaptors } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      const { result: specificAdaptor } = renderHook(
        () => useAdaptor("@openfn/language-http"),
        { wrapper }
      );

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(adaptors.current).toHaveLength(3);
        expect(specificAdaptor.current).not.toBe(null);
        expect(specificAdaptor.current?.name).toBe("@openfn/language-http");
      });

      // The specific adaptor should be in the full list
      const foundInList = adaptors.current.find(
        a => a.name === "@openfn/language-http"
      );
      expect(foundInList).toBeDefined();
      expect(foundInList).toEqual(specificAdaptor.current);
    });

    test("commands affect hook state immediately", async () => {
      const { wrapper } = createWrapper();

      const { result: commands } = renderHook(() => useAdaptorCommands(), {
        wrapper,
      });

      const { result: adaptors } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      expect(adaptors.current).toEqual([]);

      act(() => {
        commands.current.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(adaptors.current).toHaveLength(3);
      });
    });
  });

  // =============================================================================
  // Edge Cases
  // =============================================================================

  describe("edge cases", () => {
    test("handles rapid state changes", async () => {
      const { wrapper, stores } = createWrapper();

      const { result } = renderHook(() => useAdaptors(), { wrapper });

      // Rapid state changes
      act(() => {
        stores.adaptorStore.setLoading(true);
        stores.adaptorStore.setError("Error 1");
        stores.adaptorStore.clearError();
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
        stores.adaptorStore.setLoading(false);
        stores.adaptorStore.setError("Error 2");
        stores.adaptorStore.clearError();
      });

      await waitFor(() => {
        expect(result.current).toHaveLength(3);
      });

      // Final state should be consistent
      expect(result.current).toEqual(mockAdaptorsList);
    });

    test("hook survives rapid mount/unmount cycles", async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      for (let i = 0; i < 10; i++) {
        const { result, unmount } = renderHook(() => useAdaptors(), {
          wrapper,
        });

        await waitFor(() => {
          expect(result.current).toHaveLength(3);
        });

        unmount();
      }
    });

    test("multiple hooks with different selectors update independently", async () => {
      const { wrapper, stores } = createWrapper();

      let adaptorsRenderCount = 0;
      let loadingRenderCount = 0;

      renderHook(
        () => {
          adaptorsRenderCount++;
          return useAdaptors();
        },
        { wrapper }
      );

      renderHook(
        () => {
          loadingRenderCount++;
          return useAdaptorsLoading();
        },
        { wrapper }
      );

      const initialAdaptorsCount = adaptorsRenderCount;
      const initialLoadingCount = loadingRenderCount;

      // Change only loading state
      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      await waitFor(() => {
        expect(loadingRenderCount).toBeGreaterThan(initialLoadingCount);
      });

      // Adaptors hook should not have re-rendered
      expect(adaptorsRenderCount).toBe(initialAdaptorsCount);
    });
  });
});
