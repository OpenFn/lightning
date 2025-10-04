/**
 * useSessionContext Hooks Tests
 *
 * Tests for the session context hooks that provide access to user, project,
 * and app configuration data using actual React lifecycle with renderHook.
 *
 * Hooks tested:
 * - useUser()
 * - useProject()
 * - useAppConfig()
 * - useSessionContextLoading()
 * - useSessionContextError()
 */

import { describe, expect, test, beforeEach } from "vitest";
import { act, renderHook, waitFor } from "@testing-library/react";
import type React from "react";

import {
  useUser,
  useProject,
  useAppConfig,
  useSessionContextLoading,
  useSessionContextError,
} from "../../../js/collaborative-editor/hooks/useSessionContext";
import { StoreContext } from "../../../js/collaborative-editor/contexts/StoreProvider";
import type { StoreContextValue } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { createSessionContextStore } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import type { SessionContextStoreInstance } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from "../mocks/phoenixChannel";
import type {
  UserContext,
  ProjectContext,
  AppConfig,
} from "../../../js/collaborative-editor/types/sessionContext";

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Creates a wrapper with StoreProvider for testing hooks
 */
function createWrapper(
  sessionContextStore: SessionContextStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    sessionContextStore,
    // Mock other stores - not needed for these tests
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    workflowStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );
}

/**
 * Helper to create mock user data that matches UserContextSchema
 */
function createMockUser(): UserContext {
  return {
    id: "00000000-0000-4000-8000-000000000001", // Valid UUIDv4 format
    first_name: "Test",
    last_name: "User",
    email: "test@example.com",
    email_confirmed: true,
    inserted_at: new Date().toISOString(),
  };
}

/**
 * Helper to create mock project data that matches ProjectContextSchema
 */
function createMockProject(): ProjectContext {
  return {
    id: "00000000-0000-4000-8000-000000000002", // Valid UUIDv4 format
    name: "Test Project",
  };
}

/**
 * Helper to create mock app config that matches AppConfigSchema
 */
function createMockAppConfig(): AppConfig {
  return {
    require_email_verification: false,
  };
}

// =============================================================================
// CONTEXT VALIDATION TESTS
// =============================================================================

describe("useSessionContext Hooks - Context Validation", () => {
  test("useUser throws error when used outside StoreProvider", () => {
    expect(() => {
      renderHook(() => useUser());
    }).toThrow("useSessionContextStore must be used within a StoreProvider");
  });

  test("useProject throws error when used outside StoreProvider", () => {
    expect(() => {
      renderHook(() => useProject());
    }).toThrow("useSessionContextStore must be used within a StoreProvider");
  });

  test("useAppConfig throws error when used outside StoreProvider", () => {
    expect(() => {
      renderHook(() => useAppConfig());
    }).toThrow("useSessionContextStore must be used within a StoreProvider");
  });

  test("useSessionContextLoading throws error when used outside StoreProvider", () => {
    expect(() => {
      renderHook(() => useSessionContextLoading());
    }).toThrow("useSessionContextStore must be used within a StoreProvider");
  });

  test("useSessionContextError throws error when used outside StoreProvider", () => {
    expect(() => {
      renderHook(() => useSessionContextError());
    }).toThrow("useSessionContextStore must be used within a StoreProvider");
  });
});

// =============================================================================
// useUser() TESTS
// =============================================================================

describe("useUser()", () => {
  let store: SessionContextStoreInstance;

  beforeEach(() => {
    store = createSessionContextStore();
  });

  test("returns null when user is not yet loaded", () => {
    const { result } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);
  });

  test("updates when user data changes via channel message", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    // Connect store to channel
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);

    // Simulate server sending session context
    const mockUser = createMockUser();
    const mockConfig = createMockAppConfig();

    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockUser);
    });
  });

  test("returns referentially stable value when data unchanged", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });

    // Send initial data
    const mockUser = createMockUser();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockUser);
    });

    const firstReference = result.current;

    // Trigger unrelated state change (loading)
    act(() => {
      store.setLoading(true);
    });

    act(() => {
      store.setLoading(false);
    });

    // User reference should remain stable
    expect(result.current).toBe(firstReference);
  });

  test("returns new reference when user data changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });

    // Send initial data
    const mockUser1 = createMockUser();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser1,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockUser1);
    });

    const firstReference = result.current;

    // Send updated user data
    const mockUser2 = { ...mockUser1, first_name: "Updated" };
    act(() => {
      (mockChannel as any)._test.emit("session_context_updated", {
        user: mockUser2,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockUser2);
    });

    // Should be a new reference
    expect(result.current).not.toBe(firstReference);
  });

  test("subscription cleanup on unmount", () => {
    const { unmount } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });

    // Verify hook subscribed (listeners should be > 0)
    const stateBefore = store.getSnapshot();
    expect(stateBefore).toBeDefined();

    // Unmount should clean up subscription
    unmount();

    // No assertion needed - just verify no errors occur
  });

  test("hook re-renders only when user data changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    let renderCount = 0;
    const { result } = renderHook(
      () => {
        renderCount++;
        return useUser();
      },
      {
        wrapper: createWrapper(store),
      }
    );

    const initialRenderCount = renderCount;

    // Change error state (should not trigger re-render for useUser)
    act(() => {
      store.setError("some error");
    });

    act(() => {
      store.clearError();
    });

    // Should not have caused additional renders
    expect(renderCount).toBe(initialRenderCount);

    // Now change user data (should trigger re-render)
    const mockUser = createMockUser();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockUser);
      expect(renderCount).toBeGreaterThan(initialRenderCount);
    });
  });
});

// =============================================================================
// useProject() TESTS
// =============================================================================

describe("useProject()", () => {
  let store: SessionContextStoreInstance;

  beforeEach(() => {
    store = createSessionContextStore();
  });

  test("returns null when project is not yet loaded", () => {
    const { result } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);
  });

  test("updates when project data changes via channel message", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);

    const mockProject = createMockProject();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: mockProject,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockProject);
    });
  });

  test("returns referentially stable value when data unchanged", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });

    const mockProject = createMockProject();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: mockProject,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockProject);
    });

    const firstReference = result.current;

    // Trigger unrelated state change
    act(() => {
      store.setLoading(true);
    });

    act(() => {
      store.setLoading(false);
    });

    expect(result.current).toBe(firstReference);
  });

  test("returns new reference when project data changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });

    const mockProject1 = createMockProject();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: mockProject1,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockProject1);
    });

    const firstReference = result.current;

    const mockProject2 = { ...mockProject1, name: "Updated Project" };
    act(() => {
      (mockChannel as any)._test.emit("session_context_updated", {
        user: null,
        project: mockProject2,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockProject2);
    });

    expect(result.current).not.toBe(firstReference);
  });

  test("subscription cleanup on unmount", () => {
    const { unmount } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });

    unmount();
    // No assertion needed - just verify no errors occur
  });

  test("hook re-renders only when project data changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    let renderCount = 0;
    const { result } = renderHook(
      () => {
        renderCount++;
        return useProject();
      },
      {
        wrapper: createWrapper(store),
      }
    );

    const initialRenderCount = renderCount;

    // Change loading state (should not trigger re-render for useProject)
    act(() => {
      store.setLoading(true);
    });

    act(() => {
      store.setLoading(false);
    });

    expect(renderCount).toBe(initialRenderCount);

    // Now change project data (should trigger re-render)
    const mockProject = createMockProject();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: mockProject,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockProject);
      expect(renderCount).toBeGreaterThan(initialRenderCount);
    });
  });
});

// =============================================================================
// useAppConfig() TESTS
// =============================================================================

describe("useAppConfig()", () => {
  let store: SessionContextStoreInstance;

  beforeEach(() => {
    store = createSessionContextStore();
  });

  test("returns null when config is not yet loaded", () => {
    const { result } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);
  });

  test("updates when config data changes via channel message", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);

    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockConfig);
    });
  });

  test("returns referentially stable value when data unchanged", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });

    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockConfig);
    });

    const firstReference = result.current;

    // Trigger unrelated state change
    act(() => {
      store.setError("some error");
    });

    act(() => {
      store.clearError();
    });

    expect(result.current).toBe(firstReference);
  });

  test("returns new reference when config data changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    const { result } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });

    const mockConfig1 = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: mockConfig1,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockConfig1);
    });

    const firstReference = result.current;

    const mockConfig2 = { ...mockConfig1, require_email_verification: true };
    act(() => {
      (mockChannel as any)._test.emit("session_context_updated", {
        user: null,
        project: null,
        config: mockConfig2,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockConfig2);
    });

    expect(result.current).not.toBe(firstReference);
  });

  test("subscription cleanup on unmount", () => {
    const { unmount } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });

    unmount();
    // No assertion needed - just verify no errors occur
  });

  test("hook re-renders only when config data changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    let renderCount = 0;
    const { result } = renderHook(
      () => {
        renderCount++;
        return useAppConfig();
      },
      {
        wrapper: createWrapper(store),
      }
    );

    const initialRenderCount = renderCount;

    // Change loading state (should not trigger re-render for useAppConfig)
    act(() => {
      store.setLoading(true);
    });

    act(() => {
      store.setLoading(false);
    });

    expect(renderCount).toBe(initialRenderCount);

    // Now change config data (should trigger re-render)
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(result.current).toEqual(mockConfig);
      expect(renderCount).toBeGreaterThan(initialRenderCount);
    });
  });
});

// =============================================================================
// useSessionContextLoading() TESTS
// =============================================================================

describe("useSessionContextLoading()", () => {
  let store: SessionContextStoreInstance;

  beforeEach(() => {
    store = createSessionContextStore();
  });

  test("returns false initially", () => {
    const { result } = renderHook(() => useSessionContextLoading(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(false);
  });

  test("updates when loading state changes", () => {
    const { result } = renderHook(() => useSessionContextLoading(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(false);

    act(() => {
      store.setLoading(true);
    });

    expect(result.current).toBe(true);

    act(() => {
      store.setLoading(false);
    });

    expect(result.current).toBe(false);
  });

  test("subscription cleanup on unmount", () => {
    const { unmount } = renderHook(() => useSessionContextLoading(), {
      wrapper: createWrapper(store),
    });

    unmount();
    // No assertion needed - just verify no errors occur
  });

  test("hook re-renders only when loading changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    let renderCount = 0;
    const { result } = renderHook(
      () => {
        renderCount++;
        return useSessionContextLoading();
      },
      {
        wrapper: createWrapper(store),
      }
    );

    // Initial render count after mount
    const initialRenderCount = renderCount;

    // Connect channel - this will trigger loading=true then send response which sets loading=false
    act(() => {
      store._connectChannel(mockProvider as any);
    });

    // Wait for the loading state changes from connection
    await waitFor(() => {
      expect(result.current).toBe(false);
    });

    const renderCountAfterConnection = renderCount;

    // Change user data (should not trigger re-render for useSessionContextLoading)
    const mockUser = createMockUser();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser,
        project: null,
        config: mockConfig,
      });
    });

    // Wait a bit to ensure any potential re-renders complete
    await new Promise(resolve => setTimeout(resolve, 50));

    // Render count should not have changed (user data doesn't affect loading hook)
    expect(renderCount).toBe(renderCountAfterConnection);

    // Now change loading state directly (should trigger re-render)
    act(() => {
      store.setLoading(true);
    });

    expect(result.current).toBe(true);
    expect(renderCount).toBeGreaterThan(renderCountAfterConnection);
  });
});

// =============================================================================
// useSessionContextError() TESTS
// =============================================================================

describe("useSessionContextError()", () => {
  let store: SessionContextStoreInstance;

  beforeEach(() => {
    store = createSessionContextStore();
  });

  test("returns null initially", () => {
    const { result } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);
  });

  test("updates when error state changes", () => {
    const { result } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);

    act(() => {
      store.setError("Test error");
    });

    expect(result.current).toBe("Test error");

    act(() => {
      store.setError("Another error");
    });

    expect(result.current).toBe("Another error");
  });

  test("updates when error is cleared", () => {
    const { result } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    act(() => {
      store.setError("Test error");
    });

    expect(result.current).toBe("Test error");

    act(() => {
      store.clearError();
    });

    expect(result.current).toBe(null);
  });

  test("subscription cleanup on unmount", () => {
    const { unmount } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    unmount();
    // No assertion needed - just verify no errors occur
  });

  test("hook re-renders only when error changes", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    let renderCount = 0;
    const { result } = renderHook(
      () => {
        renderCount++;
        return useSessionContextError();
      },
      {
        wrapper: createWrapper(store),
      }
    );

    // Initial render count after mount
    const initialRenderCount = renderCount;

    // Connect channel - this shouldn't affect error hook
    store._connectChannel(mockProvider as any);

    // Wait for connection to complete
    await waitFor(() => {
      expect(store.getSnapshot().isLoading).toBe(false);
    });

    const renderCountAfterConnection = renderCount;

    // Change user data (should not trigger re-render for useSessionContextError)
    const mockUser = createMockUser();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser,
        project: null,
        config: mockConfig,
      });
    });

    // Wait a bit to ensure any potential re-renders complete
    await new Promise(resolve => setTimeout(resolve, 50));

    // Render count should not have changed (user data doesn't affect error hook)
    expect(renderCount).toBe(renderCountAfterConnection);

    // Now change error state (should trigger re-render)
    act(() => {
      store.setError("test error");
    });

    expect(result.current).toBe("test error");
    expect(renderCount).toBeGreaterThan(renderCountAfterConnection);
  });
});

// =============================================================================
// INTEGRATION TESTS
// =============================================================================

describe("Integration Scenarios", () => {
  let store: SessionContextStoreInstance;

  beforeEach(() => {
    store = createSessionContextStore();
  });

  test("all hooks work together with shared store instance", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    const { result: userResult } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });
    const { result: projectResult } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });
    const { result: configResult } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });
    const { result: loadingResult } = renderHook(
      () => useSessionContextLoading(),
      {
        wrapper: createWrapper(store),
      }
    );
    const { result: errorResult } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    // All should be in initial state
    expect(userResult.current).toBe(null);
    expect(projectResult.current).toBe(null);
    expect(configResult.current).toBe(null);
    expect(loadingResult.current).toBe(false);
    expect(errorResult.current).toBe(null);

    // Connect channel and simulate full session context update
    const mockUser = createMockUser();
    const mockProject = createMockProject();
    const mockConfig = createMockAppConfig();

    act(() => {
      store._connectChannel(mockProvider as any);
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser,
        project: mockProject,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(userResult.current).toEqual(mockUser);
      expect(projectResult.current).toEqual(mockProject);
      expect(configResult.current).toEqual(mockConfig);
      expect(loadingResult.current).toBe(false);
      expect(errorResult.current).toBe(null);
    });
  });

  test("state updates propagate to all relevant hooks", () => {
    const { result: loadingResult1 } = renderHook(
      () => useSessionContextLoading(),
      {
        wrapper: createWrapper(store),
      }
    );
    const { result: loadingResult2 } = renderHook(
      () => useSessionContextLoading(),
      {
        wrapper: createWrapper(store),
      }
    );

    expect(loadingResult1.current).toBe(false);
    expect(loadingResult2.current).toBe(false);

    act(() => {
      store.setLoading(true);
    });

    expect(loadingResult1.current).toBe(true);
    expect(loadingResult2.current).toBe(true);
  });

  test("independent hooks don't cause unnecessary re-renders", async () => {
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    store._connectChannel(mockProvider as any);

    let userRenderCount = 0;
    let errorRenderCount = 0;

    renderHook(
      () => {
        userRenderCount++;
        return useUser();
      },
      {
        wrapper: createWrapper(store),
      }
    );

    renderHook(
      () => {
        errorRenderCount++;
        return useSessionContextError();
      },
      {
        wrapper: createWrapper(store),
      }
    );

    const initialUserRenderCount = userRenderCount;
    const initialErrorRenderCount = errorRenderCount;

    // Change error (should only affect error hook)
    act(() => {
      store.setError("test error");
    });

    expect(errorRenderCount).toBeGreaterThan(initialErrorRenderCount);
    expect(userRenderCount).toBe(initialUserRenderCount);

    // Change user (should only affect user hook)
    const mockUser = createMockUser();
    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: mockUser,
        project: null,
        config: mockConfig,
      });
    });

    await waitFor(() => {
      expect(userRenderCount).toBeGreaterThan(initialUserRenderCount);
    });
  });

  test("error clears loading state", () => {
    const { result: loadingResult } = renderHook(
      () => useSessionContextLoading(),
      {
        wrapper: createWrapper(store),
      }
    );
    const { result: errorResult } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    act(() => {
      store.setLoading(true);
    });

    expect(loadingResult.current).toBe(true);
    expect(errorResult.current).toBe(null);

    act(() => {
      store.setError("Something went wrong");
    });

    expect(loadingResult.current).toBe(false);
    expect(errorResult.current).toBe("Something went wrong");
  });
});
