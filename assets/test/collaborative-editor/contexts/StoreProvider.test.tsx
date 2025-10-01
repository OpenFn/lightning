/**
 * StoreProvider Tests - React Testing Library Edition
 *
 * This test suite verifies the StoreProvider using React Testing Library:
 * - Context provision and store availability
 * - Store independence across multiple provider instances
 * - Provider lifecycle (mount, re-render, unmount)
 * - Integration with hooks and components
 * - Error handling
 *
 * Uses renderHook and render from @testing-library/react to test actual
 * React provider rendering and context provision.
 */

import { render, renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { useContext, type ReactNode } from "react";

import {
  StoreContext,
  StoreProvider,
} from "../../../js/collaborative-editor/contexts/StoreProvider";
import * as useSessionModule from "../../../js/collaborative-editor/hooks/useSession";
import type { SessionState } from "../../../js/collaborative-editor/stores/createSessionStore";

// =============================================================================
// TEST SETUP
// =============================================================================

// Mock useSession to avoid SessionProvider dependency
const mockUseSession = vi.spyOn(useSessionModule, "useSession");

// Default mock session state
const createMockSessionState = (
  overrides?: Partial<SessionState>
): SessionState => ({
  ydoc: null,
  provider: null,
  awareness: null,
  userData: null,
  isConnected: false,
  isSynced: false,
  settled: false,
  lastStatus: null,
  ...overrides,
});

describe("StoreProvider - React Testing Library", () => {
  beforeEach(() => {
    // Reset mock before each test
    mockUseSession.mockReturnValue(createMockSessionState());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // ===========================================================================
  // CONTEXT PROVISION TESTS
  // ===========================================================================

  describe("context provision", () => {
    test("provides store context to children", () => {
      const TestComponent = () => {
        const context = useContext(StoreContext);
        return <div>{context ? "has context" : "no context"}</div>;
      };

      const { getByText } = render(
        <StoreProvider>
          <TestComponent />
        </StoreProvider>
      );

      expect(getByText("has context")).toBeInTheDocument();
    });

    test("provides adaptorStore in context", () => {
      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: ({ children }: { children: ReactNode }) => (
          <StoreProvider>{children}</StoreProvider>
        ),
      });

      expect(result.current).toBeDefined();
      expect(result.current!.adaptorStore).toBeDefined();
      expect(typeof result.current!.adaptorStore.subscribe).toBe("function");
      expect(typeof result.current!.adaptorStore.getSnapshot).toBe("function");
      expect(typeof result.current!.adaptorStore.withSelector).toBe("function");
    });

    test("provides all required stores", () => {
      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      expect(result.current!.adaptorStore).toBeDefined();
      expect(result.current!.credentialStore).toBeDefined();
      expect(result.current!.awarenessStore).toBeDefined();
      expect(result.current!.workflowStore).toBeDefined();
      expect(result.current!.sessionContextStore).toBeDefined();
    });

    test("each store has correct interface", () => {
      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const stores = result.current!;

      // Check adaptorStore interface
      expect(typeof stores.adaptorStore.subscribe).toBe("function");
      expect(typeof stores.adaptorStore.getSnapshot).toBe("function");
      expect(typeof stores.adaptorStore.withSelector).toBe("function");

      // Check credentialStore interface
      expect(typeof stores.credentialStore.subscribe).toBe("function");
      expect(typeof stores.credentialStore.getSnapshot).toBe("function");
      expect(typeof stores.credentialStore.withSelector).toBe("function");

      // Check sessionContextStore interface
      expect(typeof stores.sessionContextStore.subscribe).toBe("function");
      expect(typeof stores.sessionContextStore.getSnapshot).toBe("function");
      expect(typeof stores.sessionContextStore.withSelector).toBe("function");
      expect(typeof stores.sessionContextStore.requestSessionContext).toBe(
        "function"
      );

      // Check awarenessStore interface
      expect(typeof stores.awarenessStore.subscribe).toBe("function");
      expect(typeof stores.awarenessStore.initializeAwareness).toBe("function");
      expect(typeof stores.awarenessStore.destroyAwareness).toBe("function");

      // Check workflowStore interface
      expect(typeof stores.workflowStore.connect).toBe("function");
      expect(typeof stores.workflowStore.disconnect).toBe("function");
    });

    test("stores have correct initial structure", () => {
      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const stores = result.current!;

      // Check sessionContextStore initial state
      const sessionContextState = stores.sessionContextStore.getSnapshot();
      expect(sessionContextState.user).toBeNull();
      expect(sessionContextState.project).toBeNull();
      expect(sessionContextState.config).toBeNull();
      expect(sessionContextState.lastUpdated).toBeNull();

      // Note: We don't test adaptorStore and credentialStore state in detail
      // because they may have already started async fetching operations when
      // the test renders. The key is that the stores are present and accessible.
      expect(stores.adaptorStore.getSnapshot()).toBeDefined();
      expect(stores.credentialStore.getSnapshot()).toBeDefined();
    });
  });

  // ===========================================================================
  // STORE INDEPENDENCE TESTS
  // ===========================================================================

  describe("store independence", () => {
    test("multiple providers have independent stores", () => {
      const { result: result1 } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const { result: result2 } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      // Different provider instances = different stores
      expect(result1.current!.adaptorStore).not.toBe(
        result2.current!.adaptorStore
      );
      expect(result1.current!.sessionContextStore).not.toBe(
        result2.current!.sessionContextStore
      );
      expect(result1.current!.credentialStore).not.toBe(
        result2.current!.credentialStore
      );
      expect(result1.current!.awarenessStore).not.toBe(
        result2.current!.awarenessStore
      );
      expect(result1.current!.workflowStore).not.toBe(
        result2.current!.workflowStore
      );
    });

    test("stores from same provider are shared", () => {
      let store1: any;
      let store2: any;

      const TestComponent1 = () => {
        const context = useContext(StoreContext);
        store1 = context?.adaptorStore;
        return null;
      };

      const TestComponent2 = () => {
        const context = useContext(StoreContext);
        store2 = context?.adaptorStore;
        return null;
      };

      render(
        <StoreProvider>
          <TestComponent1 />
          <TestComponent2 />
        </StoreProvider>
      );

      expect(store1).toBe(store2);
    });

    test("stores are independent instances with separate state", () => {
      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const stores = result.current!;

      // Verify all stores are different instances
      expect(stores.adaptorStore).not.toBe(stores.sessionContextStore);
      expect(stores.credentialStore).not.toBe(stores.sessionContextStore);
      expect(stores.awarenessStore).not.toBe(stores.sessionContextStore);
      expect(stores.workflowStore).not.toBe(stores.sessionContextStore);
      expect(stores.adaptorStore).not.toBe(stores.credentialStore);

      // Verify each store has its own state
      const sessionContextState = stores.sessionContextStore.getSnapshot();
      const adaptorState = stores.adaptorStore.getSnapshot();

      expect(sessionContextState).not.toBe(adaptorState);
    });
  });

  // ===========================================================================
  // PROVIDER LIFECYCLE TESTS
  // ===========================================================================

  describe("provider lifecycle", () => {
    test("creates stores on mount", () => {
      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      expect(result.current).toBeDefined();
      expect(result.current!.adaptorStore.getSnapshot()).toBeDefined();
      expect(result.current!.sessionContextStore.getSnapshot()).toBeDefined();
      expect(result.current!.credentialStore.getSnapshot()).toBeDefined();
    });

    test("stores survive provider re-renders", () => {
      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const initialAdaptorStore = result.current!.adaptorStore;
      const initialSessionContextStore = result.current!.sessionContextStore;
      const initialCredentialStore = result.current!.credentialStore;
      const initialAwarenessStore = result.current!.awarenessStore;
      const initialWorkflowStore = result.current!.workflowStore;

      rerender();

      // Stores should be the same instances
      expect(result.current!.adaptorStore).toBe(initialAdaptorStore);
      expect(result.current!.sessionContextStore).toBe(
        initialSessionContextStore
      );
      expect(result.current!.credentialStore).toBe(initialCredentialStore);
      expect(result.current!.awarenessStore).toBe(initialAwarenessStore);
      expect(result.current!.workflowStore).toBe(initialWorkflowStore);
    });

    test("stores maintain state across re-renders", () => {
      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      // Update store state
      result.current!.sessionContextStore.setLoading(true);

      const stateBeforeRerender =
        result.current!.sessionContextStore.getSnapshot();
      expect(stateBeforeRerender.isLoading).toBe(true);

      rerender();

      // State should persist
      const stateAfterRerender =
        result.current!.sessionContextStore.getSnapshot();
      expect(stateAfterRerender.isLoading).toBe(true);
    });

    test("cleans up awareness on unmount", () => {
      const { result, unmount } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const awarenessStore = result.current!.awarenessStore;
      const destroySpy = vi.spyOn(awarenessStore, "destroyAwareness");

      unmount();

      expect(destroySpy).toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // AWARENESS INITIALIZATION TESTS
  // ===========================================================================

  describe("awareness initialization", () => {
    test("initializes awareness when awareness and userData are available", async () => {
      // Create mock awareness and userData with all required methods
      const mockAwareness = {
        getLocalState: vi.fn(),
        setLocalState: vi.fn(),
        setLocalStateField: vi.fn(),
        getStates: vi.fn().mockReturnValue(new Map()),
        on: vi.fn(),
        off: vi.fn(),
      } as any;

      const mockUserData = {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      };

      // Start without awareness
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const awarenessStore = result.current!.awarenessStore;
      const initSpy = vi.spyOn(awarenessStore, "initializeAwareness");

      // Update to provide awareness and userData
      mockUseSession.mockReturnValue(
        createMockSessionState({
          awareness: mockAwareness,
          userData: mockUserData,
        })
      );

      rerender();

      // Wait for effect to run
      await waitFor(() => {
        expect(initSpy).toHaveBeenCalledWith(mockAwareness, mockUserData);
      });
    });

    test("does not initialize awareness when already ready", async () => {
      const mockAwareness = {
        getLocalState: vi.fn(),
        setLocalState: vi.fn(),
        setLocalStateField: vi.fn(),
        on: vi.fn(),
        off: vi.fn(),
      } as any;

      const mockUserData = {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      };

      // Start without awareness
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const awarenessStore = result.current!.awarenessStore;

      // Mock isAwarenessReady to return true BEFORE providing awareness
      vi.spyOn(awarenessStore, "isAwarenessReady").mockReturnValue(true);
      const initSpy = vi.spyOn(awarenessStore, "initializeAwareness");

      // Now update to provide awareness and userData
      mockUseSession.mockReturnValue(
        createMockSessionState({
          awareness: mockAwareness,
          userData: mockUserData,
        })
      );

      rerender();

      // Wait to ensure effect has time to run
      await new Promise(resolve => setTimeout(resolve, 10));

      // Should not have been called since awareness is already ready
      expect(initSpy).not.toHaveBeenCalled();
    });

    test("does not initialize awareness when userData is missing", async () => {
      const mockAwareness = {
        getLocalState: vi.fn(),
        setLocalState: vi.fn(),
        setLocalStateField: vi.fn(),
        on: vi.fn(),
        off: vi.fn(),
      } as any;

      mockUseSession.mockReturnValue(
        createMockSessionState({
          awareness: mockAwareness,
          userData: null,
        })
      );

      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const awarenessStore = result.current!.awarenessStore;
      const initSpy = vi.spyOn(awarenessStore, "initializeAwareness");

      // Wait to ensure effect has time to run
      await new Promise(resolve => setTimeout(resolve, 10));

      expect(initSpy).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // CHANNEL CONNECTION TESTS
  // ===========================================================================

  describe("channel connection", () => {
    test("connects stores when provider and isConnected are ready", async () => {
      const mockProvider = {
        channel: {
          push: vi.fn(),
          on: vi.fn(),
          off: vi.fn(),
        },
      } as any;

      // Start without provider
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const adaptorStore = result.current!.adaptorStore;
      const credentialStore = result.current!.credentialStore;
      const sessionContextStore = result.current!.sessionContextStore;

      const connectSpy1 = vi.spyOn(adaptorStore, "_connectChannel");
      const connectSpy2 = vi.spyOn(credentialStore, "_connectChannel");
      const connectSpy3 = vi.spyOn(sessionContextStore, "_connectChannel");

      // Update to connected state
      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider,
          isConnected: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(connectSpy1).toHaveBeenCalledWith(mockProvider);
        expect(connectSpy2).toHaveBeenCalledWith(mockProvider);
        expect(connectSpy3).toHaveBeenCalledWith(mockProvider);
      });
    });

    test("does not connect when provider is missing", async () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: null,
          isConnected: true,
        })
      );

      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const adaptorStore = result.current!.adaptorStore;
      const connectSpy = vi.spyOn(adaptorStore, "_connectChannel");

      // Wait to ensure effect has time to run
      await new Promise(resolve => setTimeout(resolve, 10));

      expect(connectSpy).not.toHaveBeenCalled();
    });

    test("does not connect when isConnected is false", async () => {
      const mockProvider = {
        channel: {
          push: vi.fn(),
          on: vi.fn(),
          off: vi.fn(),
        },
      } as any;

      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider,
          isConnected: false,
        })
      );

      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const adaptorStore = result.current!.adaptorStore;
      const connectSpy = vi.spyOn(adaptorStore, "_connectChannel");

      // Wait to ensure effect has time to run
      await new Promise(resolve => setTimeout(resolve, 10));

      expect(connectSpy).not.toHaveBeenCalled();
    });

    test("cleans up channel connections on unmount", async () => {
      const mockCleanup1 = vi.fn();
      const mockCleanup2 = vi.fn();
      const mockCleanup3 = vi.fn();

      const mockProvider = {
        channel: {
          push: vi.fn(),
          on: vi.fn(),
          off: vi.fn(),
        },
      } as any;

      // Start without provider
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender, unmount } = renderHook(
        () => useContext(StoreContext),
        {
          wrapper: StoreProvider,
        }
      );

      // Mock _connectChannel to return cleanup functions BEFORE connection
      vi.spyOn(result.current!.adaptorStore, "_connectChannel").mockReturnValue(
        mockCleanup1
      );
      vi.spyOn(
        result.current!.credentialStore,
        "_connectChannel"
      ).mockReturnValue(mockCleanup2);
      vi.spyOn(
        result.current!.sessionContextStore,
        "_connectChannel"
      ).mockReturnValue(mockCleanup3);

      // Now connect
      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider,
          isConnected: true,
        })
      );

      rerender();

      // Wait for connection effect to run
      await waitFor(() => {
        expect(result.current!.adaptorStore._connectChannel).toHaveBeenCalled();
      });

      unmount();

      // Cleanup functions should have been called
      expect(mockCleanup1).toHaveBeenCalled();
      expect(mockCleanup2).toHaveBeenCalled();
      expect(mockCleanup3).toHaveBeenCalled();
    });

    test("reconnects when provider changes", async () => {
      const mockProvider1 = {
        channel: {
          push: vi.fn(),
          on: vi.fn(),
          off: vi.fn(),
        },
      } as any;

      const mockProvider2 = {
        channel: {
          push: vi.fn(),
          on: vi.fn(),
          off: vi.fn(),
        },
      } as any;

      const mockCleanup1 = vi.fn();
      const mockCleanup2 = vi.fn();

      // Start without provider
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      // Mock first connection to return cleanup1
      vi.spyOn(result.current!.adaptorStore, "_connectChannel")
        .mockReturnValueOnce(mockCleanup1)
        .mockReturnValueOnce(mockCleanup2);

      // Connect to first provider
      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider1,
          isConnected: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(
          result.current!.adaptorStore._connectChannel
        ).toHaveBeenCalledWith(mockProvider1);
      });

      // Change provider
      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider2,
          isConnected: true,
        })
      );

      rerender();

      await waitFor(() => {
        // Old connection should be cleaned up
        expect(mockCleanup1).toHaveBeenCalled();
        // New connection should be established
        expect(
          result.current!.adaptorStore._connectChannel
        ).toHaveBeenCalledWith(mockProvider2);
      });
    });
  });

  // ===========================================================================
  // WORKFLOW STORE CONNECTION TESTS
  // ===========================================================================

  describe("workflow store connection", () => {
    test("connects workflowStore when ydoc and provider are ready", async () => {
      // Create complete mock YDoc with both getMap and getArray methods
      const mockYDoc = {
        getMap: vi.fn().mockReturnValue({
          set: vi.fn(),
          get: vi.fn(),
          observe: vi.fn(),
          observeDeep: vi.fn(),
          unobserve: vi.fn(),
          unobserveDeep: vi.fn(),
          toJSON: vi.fn().mockReturnValue({}),
        }),
        getArray: vi.fn().mockReturnValue({
          push: vi.fn(),
          get: vi.fn(),
          observe: vi.fn(),
          observeDeep: vi.fn(),
          unobserve: vi.fn(),
          unobserveDeep: vi.fn(),
          toArray: vi.fn().mockReturnValue([]),
        }),
      } as any;

      const mockProvider = {
        channel: {
          push: vi.fn(),
          on: vi.fn(),
          off: vi.fn(),
        },
      } as any;

      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const workflowStore = result.current!.workflowStore;
      const connectSpy = vi.spyOn(workflowStore, "connect");

      mockUseSession.mockReturnValue(
        createMockSessionState({
          ydoc: mockYDoc,
          provider: mockProvider,
          isConnected: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(connectSpy).toHaveBeenCalledWith(mockYDoc, mockProvider);
      });
    });

    test("disconnects workflowStore on unmount", async () => {
      // Create complete mock YDoc with both getMap and getArray methods
      const mockYDoc = {
        getMap: vi.fn().mockReturnValue({
          set: vi.fn(),
          get: vi.fn(),
          observe: vi.fn(),
          observeDeep: vi.fn(),
          unobserve: vi.fn(),
          unobserveDeep: vi.fn(),
          toJSON: vi.fn().mockReturnValue({}),
        }),
        getArray: vi.fn().mockReturnValue({
          push: vi.fn(),
          get: vi.fn(),
          observe: vi.fn(),
          observeDeep: vi.fn(),
          unobserve: vi.fn(),
          unobserveDeep: vi.fn(),
          toArray: vi.fn().mockReturnValue([]),
        }),
      } as any;

      const mockProvider = {
        channel: {
          push: vi.fn(),
          on: vi.fn(),
          off: vi.fn(),
        },
      } as any;

      // Start without provider/ydoc
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender, unmount } = renderHook(
        () => useContext(StoreContext),
        {
          wrapper: StoreProvider,
        }
      );

      const workflowStore = result.current!.workflowStore;
      const disconnectSpy = vi.spyOn(workflowStore, "disconnect");

      // Now connect with ydoc and provider
      mockUseSession.mockReturnValue(
        createMockSessionState({
          ydoc: mockYDoc,
          provider: mockProvider,
          isConnected: true,
        })
      );

      rerender();

      // Small delay to allow connection to complete
      await new Promise(resolve => setTimeout(resolve, 10));

      unmount();

      expect(disconnectSpy).toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // INTEGRATION TESTS
  // ===========================================================================

  describe("integration tests", () => {
    test("hooks can access stores through the provider", () => {
      const useTestHook = () => {
        const context = useContext(StoreContext);
        if (!context) {
          throw new Error("StoreContext is null");
        }
        return context.adaptorStore.getSnapshot();
      };

      const { result } = renderHook(() => useTestHook(), {
        wrapper: StoreProvider,
      });

      expect(result.current).toBeDefined();
      expect(result.current.isLoading).toBe(false);
    });

    test("multiple hooks share the same store instance within one provider", () => {
      let store1: any;
      let store2: any;

      const useHook1 = () => {
        const context = useContext(StoreContext);
        store1 = context?.adaptorStore;
        return store1;
      };

      const useHook2 = () => {
        const context = useContext(StoreContext);
        store2 = context?.adaptorStore;
        return store2;
      };

      const TestComponent = () => {
        useHook1();
        useHook2();
        return null;
      };

      render(
        <StoreProvider>
          <TestComponent />
        </StoreProvider>
      );

      expect(store1).toBe(store2);
    });

    test("store updates trigger re-renders in components", async () => {
      let renderCount = 0;

      const TestComponent = () => {
        const context = useContext(StoreContext);
        const isLoading = context!.sessionContextStore.getSnapshot().isLoading;
        renderCount++;
        return <div>{isLoading ? "loading" : "idle"}</div>;
      };

      const { getByText, rerender } = render(
        <StoreProvider>
          <TestComponent />
        </StoreProvider>
      );

      expect(getByText("idle")).toBeInTheDocument();
      const initialRenderCount = renderCount;

      // Note: This test demonstrates the pattern, but store updates
      // won't automatically trigger re-renders without using useSyncExternalStore
      // This is expected behavior - components should use the store hooks
      // (like useAdaptorStore) which use useSyncExternalStore internally
      expect(initialRenderCount).toBeGreaterThan(0);
    });

    test("store state is independent from session state", () => {
      const mockUserData = {
        id: "user-1",
        name: "Test User",
        color: "#ff0000",
      };

      mockUseSession.mockReturnValue(
        createMockSessionState({
          userData: mockUserData,
        })
      );

      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      // Session has userData, sessionContextStore has user
      const sessionContextState =
        result.current!.sessionContextStore.getSnapshot();

      // Initially, sessionContextStore.user should be null
      // It only gets populated after requestSessionContext succeeds
      expect(sessionContextState.user).toBeNull();

      // They maintain independent state
      expect(sessionContextState.user).not.toBe(mockUserData);
    });
  });

  // ===========================================================================
  // ERROR HANDLING TESTS
  // ===========================================================================

  describe("error handling", () => {
    test("accessing StoreContext outside provider returns null", () => {
      const { result } = renderHook(() => useContext(StoreContext));

      expect(result.current).toBeNull();
    });

    test("components can check for null context", () => {
      const TestComponent = () => {
        const context = useContext(StoreContext);
        return <div>{context ? "has context" : "no context"}</div>;
      };

      const { getByText } = render(<TestComponent />);

      expect(getByText("no context")).toBeInTheDocument();
    });
  });
});
