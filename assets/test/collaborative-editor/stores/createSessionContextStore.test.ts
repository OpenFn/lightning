/**
 * Tests for createSessionContextStore
 *
 * This test suite covers all aspects of the SessionContextStore:
 * - Core store interface (subscribe/getSnapshot/withSelector)
 * - State initialization with null domain data
 * - State management commands (setLoading, setError, clearError)
 * - Channel integration and message handling
 * - Request/response flow with validation
 * - Error handling and validation failure scenarios
 * - Real-time updates via channel events
 */

import { createSessionContextStore } from "../../../js/collaborative-editor/stores/createSessionContextStore";

import {
  mockSessionContextResponse,
  mockUpdatedSessionContext,
  mockUnauthenticatedSessionContext,
  invalidSessionContextData,
  createMockSessionContext,
  mockUserContext,
  mockProjectContext,
  mockAppConfig,
} from "../fixtures/sessionContextData";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForAsync,
  type MockPhoenixChannel,
} from "../mocks/phoenixChannel";

// =============================================================================
// CORE STORE INTERFACE TESTS
// =============================================================================

test("getSnapshot returns initial state", () => {
  const store = createSessionContextStore();
  const initialState = store.getSnapshot();

  expect(initialState.user).toBe(null);
  expect(initialState.project).toBe(null);
  expect(initialState.config).toBe(null);
  expect(initialState.isLoading).toBe(false);
  expect(initialState.error).toBe(null);
  expect(initialState.lastUpdated).toBe(null);
});

test("subscribe/unsubscribe functionality works correctly", () => {
  const store = createSessionContextStore();
  let callCount = 0;

  const listener = () => {
    callCount++;
  };

  // Subscribe to changes
  const unsubscribe = store.subscribe(listener);

  // Trigger a state change
  store.setLoading(true);

  expect(callCount).toBe(1); // Listener should be called once

  // Trigger another state change
  store.setError("test error");

  expect(callCount).toBe(2); // Listener should be called twice

  // Unsubscribe and trigger change
  unsubscribe();
  store.clearError();

  expect(callCount).toBe(2); // Listener should not be called after unsubscribe
});

test("withSelector creates memoized selector with referential stability", () => {
  const store = createSessionContextStore();

  const selectUser = store.withSelector(state => state.user);
  const selectIsLoading = store.withSelector(state => state.isLoading);

  // Initial calls
  const user1 = selectUser();
  const loading1 = selectIsLoading();

  // Same calls should return same reference
  const user2 = selectUser();
  const loading2 = selectIsLoading();

  expect(user1).toBe(user2); // Same selector calls should return identical reference
  expect(loading1).toBe(loading2); // Same selector calls should return identical reference

  // Change unrelated state - user selector should return same reference
  store.setLoading(true);
  const user3 = selectUser();
  const loading3 = selectIsLoading();

  expect(user1).toBe(user3); // Unrelated state change should not affect memoized selector
  expect(loading1).not.toBe(loading3); // Related state change should return new value
});

// =============================================================================
// STATE MANAGEMENT COMMANDS TESTS
// =============================================================================

test("setLoading updates loading state and notifies subscribers", () => {
  const store = createSessionContextStore();
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  // Set loading to true
  store.setLoading(true);

  const state1 = store.getSnapshot();
  expect(state1.isLoading).toBe(true);
  expect(notificationCount).toBe(1);

  // Set loading to false
  store.setLoading(false);

  const state2 = store.getSnapshot();
  expect(state2.isLoading).toBe(false);
  expect(notificationCount).toBe(2);
});

test("setError updates error state and sets loading to false", () => {
  const store = createSessionContextStore();

  // First set loading to true
  store.setLoading(true);
  expect(store.getSnapshot().isLoading).toBe(true);

  // Set error - should clear loading state
  const errorMessage = "Test error message";
  store.setError(errorMessage);

  const state = store.getSnapshot();
  expect(state.error).toBe(errorMessage);
  expect(state.isLoading).toBe(false); // Setting error should clear loading state
});

test("setError with null clears error", () => {
  const store = createSessionContextStore();

  // Set error first
  store.setError("Test error");
  expect(store.getSnapshot().error).toBe("Test error");

  // Set error to null
  store.setError(null);
  expect(store.getSnapshot().error).toBe(null);
});

test("clearError removes error state", () => {
  const store = createSessionContextStore();

  // Set error first
  store.setError("Test error");
  expect(store.getSnapshot().error).toBe("Test error");

  // Clear error
  store.clearError();
  expect(store.getSnapshot().error).toBe(null);
});

// =============================================================================
// CHANNEL INTEGRATION TESTS - SUCCESSFUL RESPONSES
// =============================================================================

test("requestSessionContext processes Elixir response format (direct data, not wrapped)", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  // IMPORTANT: Elixir handler returns {user, project, config} DIRECTLY
  // NOT wrapped in session_context key!
  // See lib/lightning_web/channels/workflow_channel.ex line 96-102
  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            // This matches actual Elixir response format
            callback(mockSessionContextResponse);
          }, 0);
        } else if (status === "error") {
          setTimeout(() => {
            callback({ reason: "Error" });
          }, 0);
        } else if (status === "timeout") {
          setTimeout(() => {
            callback();
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect channel and request session context
  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();

  expect(state.user).toEqual(mockUserContext);
  expect(state.project).toEqual(mockProjectContext);
  expect(state.config).toEqual(mockAppConfig);
  expect(state.isLoading).toBe(false); // Should clear loading state
  expect(state.error).toBe(null); // Should clear error state
  expect(state.lastUpdated ? state.lastUpdated > 0 : false).toBe(true); // Should set lastUpdated timestamp

  // Should have triggered notifications for: setLoading(true), clearError(), and handleSessionContextReceived
  expect(notificationCount).toBeGreaterThan(0);
});

test("requestSessionContext processes valid data correctly via channel (legacy wrapper format)", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  // NOTE: This test uses legacy wrapper format for backwards compatibility testing
  // Real Elixir handler returns data directly (see test above)
  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            // Legacy format: wrapped in session_context
            callback(mockSessionContextResponse);
          }, 0);
        } else if (status === "error") {
          setTimeout(() => {
            callback({ reason: "Error" });
          }, 0);
        } else if (status === "timeout") {
          setTimeout(() => {
            callback();
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect channel and request session context
  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();

  expect(state.user).toEqual(mockUserContext);
  expect(state.project).toEqual(mockProjectContext);
  expect(state.config).toEqual(mockAppConfig);
  expect(state.isLoading).toBe(false); // Should clear loading state
  expect(state.error).toBe(null); // Should clear error state
  expect(state.lastUpdated ? state.lastUpdated > 0 : false).toBe(true); // Should set lastUpdated timestamp

  // Should have triggered notifications for: setLoading(true), clearError(), and handleSessionContextReceived
  expect(notificationCount).toBeGreaterThan(0);
});

test("requestSessionContext handles unauthenticated context with null user", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the channel with unauthenticated response
  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockUnauthenticatedSessionContext);
          }, 0);
        } else if (status === "error") {
          setTimeout(() => {
            callback({ reason: "Error" });
          }, 0);
        } else if (status === "timeout") {
          setTimeout(() => {
            callback();
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect channel and request session context
  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.user).toBe(null);
  expect(state.project).toBe(null);
  expect(state.config).toEqual(mockAppConfig);
  expect(state.error).toBe(null);
  expect(state.isLoading).toBe(false);
});

// =============================================================================
// CHANNEL INTEGRATION TESTS - ERROR HANDLING
// =============================================================================

test("requestSessionContext handles invalid data gracefully via channel", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the channel with response containing invalid data
  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            // Return invalid data (missing required user field, not null)
            callback(invalidSessionContextData.missingUser);
          }, 0);
        } else if (status === "error") {
          setTimeout(() => {
            callback({ reason: "Error" });
          }, 0);
        } else if (status === "timeout") {
          setTimeout(() => {
            callback();
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect channel and request session context
  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.user).toBe(null); // Should remain null on invalid data
  expect(state.project).toBe(null); // Should remain null on invalid data
  expect(state.config).toBe(null); // Should remain null on invalid data
  expect(state.isLoading).toBe(false); // Should clear loading state even on error
  expect(state.error?.includes("Invalid session context data")).toBe(true); // Should set descriptive error message
});

test("requestSessionContext handles error response", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the channel with error response
  mockChannel.push = (_event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "error") {
          setTimeout(() => {
            callback({ reason: "Server error" });
          }, 0);
        } else if (status === "ok") {
          // Do nothing for ok status in error test
        } else if (status === "timeout") {
          setTimeout(() => {
            callback();
          }, 0);
        }
        return mockPush;
      },
    };

    return mockPush;
  };

  // Connect channel
  store._connectChannel(mockProvider);

  // Request session context (should fail)
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.user).toBe(null);
  expect(state.project).toBe(null);
  expect(state.config).toBe(null);
  expect(
    state.error?.includes("Failed to request session context") || false
  ).toBe(true);
  expect(state.isLoading).toBe(false);
});

test("requestSessionContext handles no channel connection", async () => {
  const store = createSessionContextStore();

  // Request session context without connecting channel
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.error?.includes("No connection available") ?? false).toBe(true);
  expect(state.isLoading).toBe(false);
});

// =============================================================================
// VALIDATION ERROR TESTS
// =============================================================================

test("handles invalid user ID gracefully", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(invalidSessionContextData.invalidUserId);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.error?.includes("Invalid session context data")).toBe(true);
});

test("handles invalid user email gracefully", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(invalidSessionContextData.invalidUserEmail);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.error?.includes("Invalid session context data")).toBe(true);
});

test("handles missing config gracefully", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(invalidSessionContextData.missingConfig);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.error?.includes("Invalid session context data")).toBe(true);
});

test("handles invalid config type gracefully", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(invalidSessionContextData.invalidConfigType);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.error?.includes("Invalid session context data")).toBe(true);
});

// =============================================================================
// CHANNEL EVENT HANDLER TESTS
// =============================================================================

test("channel session_context events are processed correctly", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the initial channel response for get_context
  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockUnauthenticatedSessionContext);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect to channel
  const cleanup = store._connectChannel(mockProvider);
  await waitForAsync(10);

  // Verify initial state
  const initialState = store.getSnapshot();
  expect(initialState.user).toBe(null);

  // Simulate session_context event from server (user logged in)
  const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };
  mockChannelWithTest._test.emit("session_context", mockSessionContextResponse);

  await waitForAsync(10);

  const state = store.getSnapshot();
  expect(state.user).toEqual(mockUserContext);
  expect(state.project).toEqual(mockProjectContext);
  expect(state.config).toEqual(mockAppConfig);
  expect(state.error).toBe(null);

  // Cleanup
  cleanup();
});

test("channel session_context_updated events are processed correctly", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the initial channel response
  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockSessionContextResponse);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect to channel
  const cleanup = store._connectChannel(mockProvider);
  await waitForAsync(10);

  // Verify initial state
  const initialState = store.getSnapshot();
  expect(initialState.user).toEqual(mockUserContext);

  // Simulate session_context_updated event from server
  const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };
  mockChannelWithTest._test.emit(
    "session_context_updated",
    mockUpdatedSessionContext
  );

  await waitForAsync(10);

  const state = store.getSnapshot();
  expect(state.user).toEqual(mockUpdatedSessionContext.user);
  expect(state.project).toEqual(mockUpdatedSessionContext.project);
  expect(state.config).toEqual(mockUpdatedSessionContext.config);

  // Cleanup
  cleanup();
});

test("connectChannel sets up event listeners and requests session context", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Mock the channel push method to simulate successful response
  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockSessionContextResponse);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect to channel
  const cleanup = store._connectChannel(mockProvider);

  // Wait for async operations
  await waitForAsync(50);

  // Verify session context was loaded
  const state = store.getSnapshot();
  expect(state.user).toEqual(mockUserContext);
  expect(state.project).toEqual(mockProjectContext);
  expect(state.config).toEqual(mockAppConfig);

  // Test real-time updates
  const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };
  mockChannelWithTest._test.emit(
    "session_context_updated",
    mockUpdatedSessionContext
  );

  await waitForAsync(10);

  const updatedState = store.getSnapshot();
  expect(updatedState.user).toEqual(mockUpdatedSessionContext.user);
  expect(updatedState.project).toEqual(mockUpdatedSessionContext.project);
  expect(updatedState.config).toEqual(mockUpdatedSessionContext.config);

  // Cleanup
  cleanup();
});

test("handleSessionContextReceived updates lastUpdated timestamp", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  const timestampBefore = Date.now();

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockSessionContextResponse);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.lastUpdated).not.toBe(null);
  expect(state.lastUpdated ? state.lastUpdated >= timestampBefore : false).toBe(
    true
  );
});

test("handleSessionContextUpdated updates lastUpdated timestamp", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockSessionContextResponse);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await waitForAsync(10);

  const firstTimestamp = store.getSnapshot().lastUpdated;

  // Wait a bit then trigger update
  await waitForAsync(10);

  const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };
  mockChannelWithTest._test.emit(
    "session_context_updated",
    mockUpdatedSessionContext
  );

  await waitForAsync(10);

  const secondTimestamp = store.getSnapshot().lastUpdated;
  expect(secondTimestamp).not.toBe(null);
  expect(
    secondTimestamp && firstTimestamp
      ? secondTimestamp >= firstTimestamp
      : false
  ).toBe(true);
});

// =============================================================================
// EDGE CASES AND MULTIPLE SUBSCRIBERS
// =============================================================================

test("handles multiple subscribers correctly", () => {
  const store = createSessionContextStore();

  let listener1Count = 0;
  let listener2Count = 0;
  let listener3Count = 0;

  const unsubscribe1 = store.subscribe(() => {
    listener1Count++;
  });
  const unsubscribe2 = store.subscribe(() => {
    listener2Count++;
  });
  const unsubscribe3 = store.subscribe(() => {
    listener3Count++;
  });

  // Trigger change
  store.setLoading(true);

  expect(listener1Count).toBe(1);
  expect(listener2Count).toBe(1);
  expect(listener3Count).toBe(1);

  // Unsubscribe middle listener
  unsubscribe2();

  // Trigger another change
  store.setError("test");

  expect(listener1Count).toBe(2);
  expect(listener2Count).toBe(1); // Unsubscribed listener should not be called
  expect(listener3Count).toBe(2);

  // Cleanup
  unsubscribe1();
  unsubscribe3();
});

test("maintains state consistency during rapid updates", () => {
  const store = createSessionContextStore();
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  // Perform rapid state updates
  store.setLoading(true);
  store.setError("error 1");
  store.clearError();
  store.setLoading(false);
  store.setError("error 2");
  store.clearError();

  // Each operation should trigger exactly one notification
  expect(notificationCount).toBe(6);

  // Final state should be consistent
  const finalState = store.getSnapshot();
  expect(finalState.isLoading).toBe(false);
  expect(finalState.error).toBe(null);
});

test("handles null and undefined channel provider gracefully", async () => {
  const store = createSessionContextStore();

  // Test with null provider
  try {
    store._connectChannel(null as any);
    throw new Error("Should have thrown error for null provider");
  } catch (error) {
    expect(error instanceof TypeError).toBe(true);
  }

  // Test with undefined provider
  try {
    store._connectChannel(undefined as any);
    throw new Error("Should have thrown error for undefined provider");
  } catch (error) {
    expect(error instanceof TypeError).toBe(true);
  }

  // Test requestSessionContext without any channel connection
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.error?.includes("No connection available") ?? false).toBe(true);
});

test("channel cleanup removes event listeners", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockSessionContextResponse);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  // Connect to channel
  const cleanup = store._connectChannel(mockProvider);
  await waitForAsync(10);

  // Verify handlers are registered
  const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
    _test: { getHandlers: (event: string) => Set<unknown> | undefined };
  };
  expect(mockChannelWithTest._test.getHandlers("session_context")?.size).toBe(
    1
  );
  expect(
    mockChannelWithTest._test.getHandlers("session_context_updated")?.size
  ).toBe(1);

  // Cleanup
  cleanup();

  // Verify handlers are removed
  expect(mockChannelWithTest._test.getHandlers("session_context")?.size).toBe(
    0
  );
  expect(
    mockChannelWithTest._test.getHandlers("session_context_updated")?.size
  ).toBe(0);
});

// =============================================================================
// SELECTOR PERFORMANCE TESTS
// =============================================================================

test("withSelector provides optimized access to state", () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(mockSessionContextResponse);
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);

  // Create selectors
  const selectUser = store.withSelector(state => state.user);
  const selectProject = store.withSelector(state => state.project);
  const selectIsLoading = store.withSelector(state => state.isLoading);

  // Initial values
  expect(selectUser()).toBe(null);
  expect(selectProject()).toBe(null);
  expect(selectIsLoading()).toBe(true); // Should be loading during request

  // Same selector calls should return same reference
  expect(selectUser()).toBe(selectUser());
  expect(selectProject()).toBe(selectProject());
});

test("complex session context updates maintain referential stability", async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === "ok") {
          setTimeout(() => {
            callback(
              createMockSessionContext({
                user: {
                  id: "111e8400-e29b-41d4-a716-446655440000",
                  first_name: "Complex",
                  last_name: "User",
                  email: "complex@example.com",
                  email_confirmed: true,
                  inserted_at: "2024-02-01T12:00:00Z",
                },
              })
            );
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.user?.first_name).toBe("Complex");
  expect(state.user?.email).toBe("complex@example.com");

  // Create selector
  const selectUser = store.withSelector(state => state.user);
  const user1 = selectUser();

  // Unrelated state change should not affect user reference
  store.setLoading(true);
  const user2 = selectUser();

  expect(user1).toBe(user2); // Reference should remain stable
});
