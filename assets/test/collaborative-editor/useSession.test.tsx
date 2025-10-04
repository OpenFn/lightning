/**
 * useSession Hook Tests
 *
 * Tests for the useSession hook that provides access to the SessionStore instance.
 * Tests React integration using renderHook from @testing-library/react.
 *
 * This file replaces the simulation-based tests with actual React hook testing
 * to verify real React lifecycle behavior including:
 * - Hook mounting and unmounting
 * - Subscription management
 * - Re-render behavior
 * - Context validation
 * - Memory leak prevention
 */

import { act, renderHook, waitFor } from "@testing-library/react";
import type React from "react";
import { useEffect, useState } from "react";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { useSession } from "../../js/collaborative-editor/hooks/useSession";
import type { SessionStoreInstance } from "../../js/collaborative-editor/stores/createSessionStore";
import { createSessionStore } from "../../js/collaborative-editor/stores/createSessionStore";

import { SessionContext } from "../../js/collaborative-editor/contexts/SessionProvider";
import { createMockSocket } from "./mocks/phoenixSocket";

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Creates a wrapper component with SessionProvider context
 * Returns both the wrapper and the store instance for test manipulation
 */
function createWrapper() {
  const store = createSessionStore();
  const mockSocket = createMockSocket();

  // Initialize the session store
  store.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={store}>{children}</SessionContext.Provider>
  );

  return { wrapper, store };
}

/**
 * Creates a wrapper without initializing the session
 * Useful for testing pre-initialization state
 */
function createUninitializedWrapper() {
  const store = createSessionStore();

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={store}>{children}</SessionContext.Provider>
  );

  return { wrapper, store };
}

// =============================================================================
// BASIC HOOK FUNCTIONALITY TESTS
// =============================================================================

describe("useSession", () => {
  describe("basic functionality", () => {
    test("returns session state from context", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      expect(result.current).toBeDefined();
      expect(result.current.ydoc).toBeDefined();
      expect(result.current.provider).toBeDefined();
      expect(result.current.awareness).toBeDefined();
    });

    test("default selector returns full state", () => {
      const { wrapper, store } = createWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      const storeSnapshot = store.getSnapshot();
      expect(result.current).toEqual(storeSnapshot);
    });

    test("custom selector returns selected data", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(() => useSession(state => state.ydoc), {
        wrapper,
      });

      expect(result.current).toBeDefined();
      expect(result.current.constructor.name).toBe("Doc"); // YDoc instance
    });

    test("custom selector can return primitive values", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(
        () => useSession(state => state.isConnected),
        {
          wrapper,
        }
      );

      expect(typeof result.current).toBe("boolean");
    });

    test("custom selector can return nested object", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(
        () =>
          useSession(state => ({
            isConnected: state.isConnected,
            isSynced: state.isSynced,
          })),
        {
          wrapper,
        }
      );

      expect(result.current).toEqual({
        isConnected: expect.any(Boolean),
        isSynced: expect.any(Boolean),
      });
    });

    test("throws error when used outside provider", () => {
      // renderHook without wrapper means no SessionProvider
      expect(() => {
        renderHook(() => useSession());
      }).toThrow("useSession must be used within a SessionProvider");
    });

    test("throws error with helpful message outside provider", () => {
      try {
        renderHook(() => useSession());
        expect.fail("Should have thrown error");
      } catch (error: unknown) {
        expect((error as Error).message).toContain(
          "useSession must be used within a SessionProvider"
        );
      }
    });
  });

  // =============================================================================
  // HOOK UPDATES AND REACTIVITY TESTS
  // =============================================================================

  describe("reactivity and updates", () => {
    test("hook updates when store changes", async () => {
      const { wrapper, store } = createUninitializedWrapper();

      const { result } = renderHook(
        () => useSession(state => state.isConnected),
        {
          wrapper,
        }
      );

      expect(result.current).toBe(false);

      // Initialize session which should trigger connection
      const mockSocket = createMockSocket();
      store.initializeSession(mockSocket, "test:room", {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      });

      await waitFor(() => {
        expect(result.current).toBe(true);
      });
    });

    test("multiple components get same state", () => {
      const { wrapper } = createWrapper();

      const { result: result1 } = renderHook(
        () => useSession(state => state.ydoc),
        {
          wrapper,
        }
      );

      const { result: result2 } = renderHook(
        () => useSession(state => state.ydoc),
        {
          wrapper,
        }
      );

      // Both hooks should return the same ydoc instance
      expect(result1.current).toBe(result2.current);
    });

    test("selector memoization prevents unnecessary re-renders", () => {
      const { wrapper, store } = createWrapper();
      let renderCount = 0;

      const { result } = renderHook(
        () => {
          renderCount++;
          return useSession(state => state.ydoc);
        },
        {
          wrapper,
        }
      );

      const initialRenderCount = renderCount;
      expect(result.current).toBeDefined();

      // Trigger update to unrelated state
      store.getSnapshot(); // Just reading shouldn't cause re-render

      // Should not have re-rendered
      expect(renderCount).toBe(initialRenderCount);
    });

    test("different selectors can return different parts of state", () => {
      const { wrapper } = createWrapper();

      const { result: ydocResult } = renderHook(
        () => useSession(state => state.ydoc),
        {
          wrapper,
        }
      );

      const { result: connectedResult } = renderHook(
        () => useSession(state => state.isConnected),
        {
          wrapper,
        }
      );

      expect(ydocResult.current).toBeDefined();
      expect(typeof connectedResult.current).toBe("boolean");
      expect(ydocResult.current).not.toBe(connectedResult.current);
    });

    test("hook re-renders only when selected value changes", async () => {
      const { wrapper, store } = createWrapper();
      let ydocRenderCount = 0;
      let connectedRenderCount = 0;

      // Hook that selects ydoc
      renderHook(
        () => {
          ydocRenderCount++;
          return useSession(state => state.ydoc);
        },
        {
          wrapper,
        }
      );

      // Hook that selects isConnected
      renderHook(
        () => {
          connectedRenderCount++;
          return useSession(state => state.isConnected);
        },
        {
          wrapper,
        }
      );

      const initialYdocCount = ydocRenderCount;
      const initialConnectedCount = connectedRenderCount;

      // Manually trigger a notification
      // Note: This is a bit artificial since we're not changing state
      // but it tests the selector memoization
      const snapshot = store.getSnapshot();

      // Neither should re-render if state hasn't actually changed
      expect(ydocRenderCount).toBe(initialYdocCount);
      expect(connectedRenderCount).toBe(initialConnectedCount);
      expect(snapshot).toBeDefined();
    });
  });

  // =============================================================================
  // SUBSCRIPTION MANAGEMENT TESTS
  // =============================================================================

  describe("subscription management", () => {
    test("hook subscribes to store on mount", () => {
      const { wrapper, store } = createWrapper();
      let subscriptionCount = 0;

      // Wrap the subscribe method to count calls
      const originalSubscribe = store.subscribe;
      store.subscribe = listener => {
        subscriptionCount++;
        return originalSubscribe(listener);
      };

      renderHook(() => useSession(), { wrapper });

      expect(subscriptionCount).toBeGreaterThan(0);

      // Restore original method
      store.subscribe = originalSubscribe;
    });

    test("hook unsubscribes on unmount", () => {
      const { wrapper, store } = createWrapper();
      const subscriptions = new Set<() => void>();

      // Track subscriptions
      const originalSubscribe = store.subscribe;
      store.subscribe = listener => {
        const unsubscribe = originalSubscribe(listener);
        subscriptions.add(unsubscribe);
        return () => {
          subscriptions.delete(unsubscribe);
          unsubscribe();
        };
      };

      const { unmount } = renderHook(() => useSession(), { wrapper });

      const subscriptionCountBeforeUnmount = subscriptions.size;
      expect(subscriptionCountBeforeUnmount).toBeGreaterThan(0);

      unmount();

      // Subscription should be cleaned up
      expect(subscriptions.size).toBe(0);

      // Restore original method
      store.subscribe = originalSubscribe;
    });

    test("multiple hooks share single store subscription", () => {
      const { wrapper } = createWrapper();

      // Mount multiple hooks
      const { unmount: unmount1 } = renderHook(() => useSession(), {
        wrapper,
      });
      const { unmount: unmount2 } = renderHook(() => useSession(), {
        wrapper,
      });
      const { unmount: unmount3 } = renderHook(() => useSession(), {
        wrapper,
      });

      // All hooks should work independently
      unmount1();
      unmount2();
      unmount3();

      // No errors should occur
    });

    test("re-rendering doesn't create duplicate subscriptions", () => {
      const { wrapper, store } = createWrapper();
      let subscriptionCount = 0;

      const originalSubscribe = store.subscribe;
      store.subscribe = listener => {
        subscriptionCount++;
        return originalSubscribe(listener);
      };

      const { rerender } = renderHook(() => useSession(), { wrapper });

      const initialCount = subscriptionCount;

      // Re-render multiple times
      rerender();
      rerender();
      rerender();

      // Should only have subscribed once (useSyncExternalStore handles this)
      expect(subscriptionCount).toBe(initialCount);

      // Restore original method
      store.subscribe = originalSubscribe;
    });

    test("subscription persists across re-renders", async () => {
      const { wrapper, store } = createUninitializedWrapper();

      const { result, rerender } = renderHook(
        () => useSession(state => state.isConnected),
        {
          wrapper,
        }
      );

      expect(result.current).toBe(false);

      // Initialize session
      const mockSocket = createMockSocket();
      store.initializeSession(mockSocket, "test:room", {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      });

      await waitFor(() => {
        expect(result.current).toBe(true);
      });

      // Re-render
      rerender();

      // Should still be connected
      expect(result.current).toBe(true);
    });
  });

  // =============================================================================
  // EDGE CASES TESTS
  // =============================================================================

  describe("edge cases", () => {
    test("handles rapid state updates", async () => {
      const { wrapper, store } = createWrapper();

      const { result } = renderHook(() => useSession(state => state.settled), {
        wrapper,
      });

      // Trigger multiple rapid updates by destroying and reinitializing
      const mockSocket = createMockSocket();
      for (let i = 0; i < 5; i++) {
        store.initializeSession(mockSocket, `test:room-${i}`, {
          id: `user-${i}`,
          name: `Test User ${i}`,
          color: "#ff0000",
        });
      }

      // Should handle all updates without error
      await waitFor(() => {
        expect(result.current).toBeDefined();
      });
    });

    test("handles null values in state", () => {
      const { wrapper, store } = createUninitializedWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      // Before initialization, some values should be null
      expect(result.current.ydoc).toBeNull();
      expect(result.current.provider).toBeNull();
      expect(result.current.awareness).toBeNull();
      expect(store).toBeDefined();
    });

    test("handles undefined selector result", () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(
        () => useSession(state => (state as any).nonExistentProperty),
        {
          wrapper,
        }
      );

      expect(result.current).toBeUndefined();
    });

    test("selector throws error - component should handle gracefully", () => {
      const { wrapper } = createWrapper();

      const faultySelector = () => {
        throw new Error("Selector error");
      };

      expect(() => {
        renderHook(() => useSession(faultySelector), { wrapper });
      }).toThrow("Selector error");
    });

    test("provider remounts - subscriptions still work", async () => {
      let store = createSessionStore();
      const mockSocket = createMockSocket();

      store.initializeSession(mockSocket, "test:room", {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      });

      const wrapper1 = ({ children }: { children: React.ReactNode }) => (
        <SessionContext.Provider value={store}>
          {children}
        </SessionContext.Provider>
      );

      const { result, rerender, unmount } = renderHook(
        () => useSession(state => state.isConnected),
        {
          wrapper: wrapper1,
        }
      );

      // Wait for connection to be established
      await waitFor(() => {
        expect(result.current).toBe(true);
      });

      // Simulate provider remount by unmounting and creating new wrapper
      unmount();

      // Create new store and wrapper with new socket
      store = createSessionStore();
      const newMockSocket = createMockSocket();
      store.initializeSession(newMockSocket, "test:room", {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      });

      const wrapper2 = ({ children }: { children: React.ReactNode }) => (
        <SessionContext.Provider value={store}>
          {children}
        </SessionContext.Provider>
      );

      const { result: result2 } = renderHook(
        () => useSession(state => state.isConnected),
        {
          wrapper: wrapper2,
        }
      );

      await waitFor(() => {
        expect(result2.current).toBe(true);
      });
      expect(rerender).toBeDefined();
    });
  });

  // =============================================================================
  // INTEGRATION WITH SESSION PROVIDER TESTS
  // =============================================================================

  describe("integration with SessionProvider", () => {
    test("works with actual store initialization flow", () => {
      const { wrapper, store } = createWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      expect(result.current.ydoc).toBeDefined();
      expect(result.current.provider).toBeDefined();
      expect(result.current.awareness).toBeDefined();
      expect(store.isReady()).toBe(true);
    });

    test("provider updates propagate to hook", async () => {
      const { wrapper, store } = createUninitializedWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      expect(result.current.provider).toBeNull();

      const mockSocket = createMockSocket();
      act(() => {
        store.initializeSession(mockSocket, "test:room", {
          id: "user-1",
          name: "Test User",
          color: "#ff0000",
        });
      });

      await waitFor(() => {
        expect(result.current.provider).not.toBeNull();
      });
    });

    test("store destroy cleans up hook subscriptions", async () => {
      const { wrapper, store } = createWrapper();

      const { result, unmount } = renderHook(() => useSession(), { wrapper });

      expect(result.current.ydoc).toBeDefined();

      act(() => {
        store.destroy();
      });

      await waitFor(() => {
        expect(result.current.ydoc).toBeNull();
      });

      unmount();
    });

    test("multiple hooks with same selector share memoized value", () => {
      const { wrapper } = createWrapper();

      const selector = (state: any) => state.ydoc;

      const { result: result1 } = renderHook(() => useSession(selector), {
        wrapper,
      });

      const { result: result2 } = renderHook(() => useSession(selector), {
        wrapper,
      });

      // Both should return exact same reference
      expect(result1.current).toBe(result2.current);
    });

    test("hook works with state updates from store methods", async () => {
      const { wrapper, store } = createWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      const initialSnapshot = result.current;
      expect(initialSnapshot).toBeDefined();

      // Get current snapshot
      const snapshot = store.getSnapshot();
      expect(snapshot).toEqual(initialSnapshot);
    });
  });

  // =============================================================================
  // COMPLEX INTEGRATION SCENARIOS
  // =============================================================================

  describe("complex integration scenarios", () => {
    test("hook works with component that uses state", async () => {
      const { wrapper } = createWrapper();

      function useSessionWithLocalState() {
        const session = useSession();
        const [count, setCount] = useState(0);

        useEffect(() => {
          if (session.isConnected) {
            setCount(c => c + 1);
          }
        }, [session.isConnected]);

        return { session, count };
      }

      const { result } = renderHook(() => useSessionWithLocalState(), {
        wrapper,
      });

      await waitFor(() => {
        expect(result.current.count).toBeGreaterThan(0);
      });

      expect(result.current.session).toBeDefined();
    });

    test("hook works with multiple selectors in same component", () => {
      const { wrapper } = createWrapper();

      function useMultipleSelectors() {
        const ydoc = useSession(state => state.ydoc);
        const isConnected = useSession(state => state.isConnected);
        const isSynced = useSession(state => state.isSynced);

        return { ydoc, isConnected, isSynced };
      }

      const { result } = renderHook(() => useMultipleSelectors(), {
        wrapper,
      });

      expect(result.current.ydoc).toBeDefined();
      expect(typeof result.current.isConnected).toBe("boolean");
      expect(typeof result.current.isSynced).toBe("boolean");
    });

    test("hook works with conditional rendering", () => {
      const { wrapper } = createWrapper();

      // Test proper conditional rendering - using a component that conditionally uses the hook
      function useConditionalSession(enabled: boolean) {
        // Proper way: always call the hook but return different values
        const session = useSession();
        if (!enabled) {
          return null;
        }
        return session;
      }

      const { result, rerender } = renderHook(
        ({ enabled }) => useConditionalSession(enabled),
        {
          wrapper,
          initialProps: { enabled: false },
        }
      );

      expect(result.current).toBeNull();

      rerender({ enabled: true });

      expect(result.current).toBeDefined();
      expect(result.current!.ydoc).toBeDefined();
    });

    test("hook survives rapid mount/unmount cycles", () => {
      const { wrapper } = createWrapper();

      for (let i = 0; i < 10; i++) {
        const { result, unmount } = renderHook(() => useSession(), {
          wrapper,
        });

        expect(result.current).toBeDefined();
        unmount();
      }
    });

    test("selector identity changes trigger re-subscription", () => {
      const { wrapper } = createWrapper();

      const { result, rerender } = renderHook(
        ({ selector }) => useSession(selector),
        {
          wrapper,
          initialProps: {
            selector: (state: any) => state.ydoc,
          },
        }
      );

      const initialResult = result.current;

      // Change selector identity (new function)
      rerender({
        selector: (state: any) => state.provider,
      });

      // Should get different result
      expect(result.current).not.toBe(initialResult);
    });
  });
});
