/**
 * Tests for createAdaptorStore
 *
 * This test suite covers all aspects of the AdaptorStore:
 * - Core store interface (subscribe/getSnapshot)
 * - State management commands (setLoading, setError, etc.)
 * - Channel integration and message handling
 * - Query helpers (findAdaptorByName, getLatestVersion, etc.)
 * - Error handling and validation
 */

import { createAdaptorStore } from "../../js/collaborative-editor/stores/createAdaptorStore";

import {
  mockAdaptorsList,
  mockAdaptor,
  invalidAdaptorData,
  createMockAdaptor,
} from "./fixtures/adaptorData.js";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForAsync,
} from "./mocks/phoenixChannel.js";

// =============================================================================
// CORE STORE INTERFACE TESTS
// =============================================================================

test("getSnapshot returns initial state", () => {
  const store = createAdaptorStore();
  const initialState = store.getSnapshot();

  expect(initialState.adaptors).toEqual([]);
  expect(initialState.isLoading).toBe(false);
  expect(initialState.error).toBe(null);
  expect(initialState.lastUpdated).toBe(null);
});

test("subscribe/unsubscribe functionality works correctly", () => {
  const store = createAdaptorStore();
  let callCount = 0;

  const listener = () => {
    callCount++;
  };

  // Subscribe to changes
  const unsubscribe = store.subscribe(listener);

  // Trigger a state change
  store.setLoading(true);

  expect(callCount).toBe(1); // "Listener should be called once"

  // Trigger another state change
  store.setError("test error");

  expect(callCount).toBe(2); // "Listener should be called twice"

  // Unsubscribe and trigger change
  unsubscribe();
  store.clearError();

  expect(callCount).toBe(2); // "Listener should not be called after unsubscribe"
});

test("withSelector creates memoized selector with referential stability", () => {
  const store = createAdaptorStore();

  const selectAdaptors = store.withSelector(state => state.adaptors);
  const selectIsLoading = store.withSelector(state => state.isLoading);

  // Initial calls
  const adaptors1 = selectAdaptors();
  const loading1 = selectIsLoading();

  // Same calls should return same reference
  const adaptors2 = selectAdaptors();
  const loading2 = selectIsLoading();

  expect(adaptors1).toBe(adaptors2); // Same selector calls should return identical reference
  expect(loading1).toBe(loading2); // Same selector calls should return identical reference

  // Change unrelated state - adaptors selector should return same reference
  store.setLoading(true);
  const adaptors3 = selectAdaptors();
  const loading3 = selectIsLoading();

  expect(adaptors1).toBe(adaptors3); // Unrelated state change should not affect memoized selector
  expect(loading1).not.toBe(loading3); // "Related state change should return new value"
});

// =============================================================================
// STATE MANAGEMENT COMMANDS TESTS
// =============================================================================

test("setLoading updates loading state and notifies subscribers", () => {
  const store = createAdaptorStore();
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
  const store = createAdaptorStore();

  // First set loading to true
  store.setLoading(true);
  expect(store.getSnapshot().isLoading).toBe(true);

  // Set error - should clear loading state
  const errorMessage = "Test error message";
  store.setError(errorMessage);

  const state = store.getSnapshot();
  expect(state.error).toBe(errorMessage);
  expect(state.isLoading).toBe(false); // "Setting error should clear loading state"
});

test("clearError removes error state", () => {
  const store = createAdaptorStore();

  // Set error first
  store.setError("Test error");
  expect(store.getSnapshot().error).toBe("Test error");

  // Clear error
  store.clearError();
  expect(store.getSnapshot().error).toBe(null);
});

test("setAdaptors updates adaptors list and metadata", () => {
  const store = createAdaptorStore();
  const timestamp = Date.now();

  store.setAdaptors(mockAdaptorsList);

  const state = store.getSnapshot();
  expect(state.adaptors).toEqual(mockAdaptorsList);
  expect(state.error).toBe(null); // "Setting adaptors should clear error"
  expect(state.lastUpdated ? state.lastUpdated >= timestamp : false).toBe(true); // Should update lastUpdated timestamp
});

// =============================================================================
// CHANNEL INTEGRATION TESTS
// =============================================================================

test("requestAdaptors processes valid data correctly via channel", async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  let _notificationCount = 0;

  store.subscribe(() => {
    _notificationCount++;
  });

  // Set up the channel with successful response containing mockAdaptorsList
  mockChannel.push = (event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (event === "request_adaptors" && status === "ok") {
          setTimeout(() => {
            callback({ adaptors: mockAdaptorsList });
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
        return mockPush;
      },
    };

    return mockPush;
  };

  // Connect channel and request adaptors
  store._connectChannel(mockProvider);
  await store.requestAdaptors();

  const state = store.getSnapshot();

  // The adaptors should be sorted alphabetically by name
  const expectedSortedAdaptors = [...mockAdaptorsList]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(adaptor => ({
      ...adaptor,
      versions: [...adaptor.versions].sort((a, b) =>
        b.version.localeCompare(a.version)
      ),
    }));

  expect(state.adaptors).toEqual(expectedSortedAdaptors);
  expect(state.isLoading).toBe(false); // "Should clear loading state"
  expect(state.error).toBe(null); // "Should clear error state"
  expect(state.lastUpdated ? state.lastUpdated > 0 : false).toBe(true); // "Should set lastUpdated timestamp"

  // Check that adaptors are sorted alphabetically
  const adaptorNames = state.adaptors.map(a => a.name);
  const sortedNames = [...adaptorNames].sort();
  expect(adaptorNames).toEqual(sortedNames); // "Adaptors should be sorted alphabetically"

  // Check that versions are sorted (descending)
  state.adaptors.forEach(adaptor => {
    const versions = adaptor.versions.map(v => v.version);
    const sortedVersions = [...versions].sort((a, b) => b.localeCompare(a));
    expect(versions).toEqual(sortedVersions); // `Versions for ${adaptor.name} should be sorted descending`
  });
});

test("requestAdaptors handles invalid data gracefully via channel", async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the channel with response containing invalid data
  mockChannel.push = (event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (event === "request_adaptors" && status === "ok") {
          setTimeout(() => {
            // Return invalid adaptors data (missing required name field)
            callback({ adaptors: [invalidAdaptorData.missingName] });
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
        return mockPush;
      },
    };

    return mockPush;
  };

  // Connect channel and request adaptors
  store._connectChannel(mockProvider);
  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.adaptors).toEqual([]); // "Adaptors should remain empty on invalid data"
  expect(state.isLoading).toBe(false); // "Should clear loading state even on error"
  expect(state.error?.includes("Invalid adaptors data")).toBe(true); // "Should set descriptive error message"
});

test("channel adaptors_updated events are processed correctly", async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the initial channel response for request_adaptors
  mockChannel.push = (event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (event === "request_adaptors" && status === "ok") {
          setTimeout(() => {
            callback({ adaptors: [] }); // Start with empty adaptors
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
        return mockPush;
      },
    };

    return mockPush;
  };

  // Connect to channel
  const cleanup = store._connectChannel(mockProvider);
  await waitForAsync(10);

  // Simulate adaptors_updated event from server
  const mockChannelWithTest = mockChannel as typeof mockChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };
  mockChannelWithTest._test.emit("adaptors_updated", mockAdaptorsList);

  await waitForAsync(10);

  const state = store.getSnapshot();

  // Should be sorted same as requestAdaptors
  const expectedSortedAdaptors = [...mockAdaptorsList]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(adaptor => ({
      ...adaptor,
      versions: [...adaptor.versions].sort((a, b) =>
        b.version.localeCompare(a.version)
      ),
    }));

  expect(state.adaptors).toEqual(expectedSortedAdaptors); // "Should process update same as received"

  // Cleanup
  cleanup();
});

test("connectChannel sets up event listeners and requests adaptors", async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Mock the channel push method to simulate successful response
  mockChannel.push = (event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (event === "request_adaptors" && status === "ok") {
          setTimeout(() => {
            callback({ adaptors: mockAdaptorsList });
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
        return mockPush;
      },
    };

    return mockPush;
  };

  // Connect to channel
  const cleanup = store._connectChannel(mockProvider);

  // Wait for async operations
  await waitForAsync(50);

  // Verify adaptors were loaded (they should be sorted)
  const state = store.getSnapshot();
  const expectedSortedAdaptors = [...mockAdaptorsList]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(adaptor => ({
      ...adaptor,
      versions: [...adaptor.versions].sort((a, b) =>
        b.version.localeCompare(a.version)
      ),
    }));

  expect(state.adaptors).toEqual(expectedSortedAdaptors);

  // Test real-time updates
  const updatedAdaptors = [mockAdaptor];
  // Emit adaptors_updated event to test real-time updates
  const mockChannelWithTest = mockChannel as typeof mockChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };
  mockChannelWithTest._test.emit("adaptors_updated", updatedAdaptors);

  await waitForAsync(10);

  const updatedState = store.getSnapshot();
  const expectedUpdatedAdaptors = [...updatedAdaptors]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(adaptor => ({
      ...adaptor,
      versions: [...adaptor.versions].sort((a, b) =>
        b.version.localeCompare(a.version)
      ),
    }));

  expect(updatedState.adaptors).toEqual(expectedUpdatedAdaptors);

  // Cleanup
  cleanup();
  // "Channel cleanup completed without errors");
});

test("requestAdaptors handles successful response", async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the channel with successful response
  mockChannel.push = (event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (event === "request_adaptors" && status === "ok") {
          setTimeout(() => {
            callback({ adaptors: mockAdaptorsList });
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
        return mockPush;
      },
    };

    return mockPush;
  };

  // Connect channel
  store._connectChannel(mockProvider);

  // Request adaptors
  await store.requestAdaptors();

  const state = store.getSnapshot();
  const expectedSortedAdaptors = [...mockAdaptorsList]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(adaptor => ({
      ...adaptor,
      versions: [...adaptor.versions].sort((a, b) =>
        b.version.localeCompare(a.version)
      ),
    }));

  expect(state.adaptors).toEqual(expectedSortedAdaptors);
  expect(state.error).toBe(null);
  expect(state.isLoading).toBe(false);
});

test("requestAdaptors handles error response", async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Set up the channel with error response
  mockChannel.push = (event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (event === "request_adaptors" && status === "error") {
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

  // Request adaptors (should fail)
  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.adaptors).toEqual([]);
  expect(state.error?.includes("Failed to request adaptors") || false).toBe(
    true
  );
  expect(state.isLoading).toBe(false);
});

test("requestAdaptors handles no channel connection", async () => {
  const store = createAdaptorStore();

  // Request adaptors without connecting channel
  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.error?.includes("No connection available") ?? false).toBe(true);
  expect(state.isLoading).toBe(false);
});

// =============================================================================
// QUERY HELPERS TESTS
// =============================================================================

test("findAdaptorByName returns correct adaptor", () => {
  const store = createAdaptorStore();
  store.setAdaptors(mockAdaptorsList);

  const foundAdaptor = store.findAdaptorByName("@openfn/language-http");
  expect(foundAdaptor).toEqual(mockAdaptor);

  const notFound = store.findAdaptorByName("@openfn/language-nonexistent");
  expect(notFound).toBe(null);
});

test("getLatestVersion returns correct version", () => {
  const store = createAdaptorStore();
  store.setAdaptors(mockAdaptorsList);

  const latestVersion = store.getLatestVersion("@openfn/language-http");
  expect(latestVersion).toBe("2.1.0");

  const notFound = store.getLatestVersion("@openfn/language-nonexistent");
  expect(notFound).toBe(null);
});

test("getVersions returns correct versions array", () => {
  const store = createAdaptorStore();
  store.setAdaptors(mockAdaptorsList);

  const versions = store.getVersions("@openfn/language-http");
  expect(versions).toEqual(mockAdaptor.versions);

  const notFound = store.getVersions("@openfn/language-nonexistent");
  expect(notFound).toEqual([]);
});

// =============================================================================
// EDGE CASES AND ERROR HANDLING
// =============================================================================

test("handles multiple subscribers correctly", () => {
  const store = createAdaptorStore();

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
  expect(listener2Count).toBe(1); // "Unsubscribed listener should not be called"
  expect(listener3Count).toBe(2);

  // Cleanup
  unsubscribe1();
  unsubscribe3();
});

test("handles complex adaptor data transformations via channel", async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Create adaptors with unsorted versions
  const unsortedAdaptors = [
    createMockAdaptor({
      name: "z-last-adaptor",
      versions: [
        { version: "1.0.0" },
        { version: "2.0.0" },
        { version: "1.5.0" },
      ],
    }),
    createMockAdaptor({
      name: "a-first-adaptor",
      versions: [
        { version: "3.0.0" },
        { version: "3.1.0" },
        { version: "2.9.0" },
      ],
    }),
  ];

  // Set up the channel with unsorted adaptors data
  mockChannel.push = (event: string, _payload: unknown) => {
    const mockPush = {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (event === "request_adaptors" && status === "ok") {
          setTimeout(() => {
            callback({ adaptors: unsortedAdaptors });
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
        return mockPush;
      },
    };

    return mockPush;
  };

  // Connect channel and request adaptors
  store._connectChannel(mockProvider);
  await store.requestAdaptors();

  const state = store.getSnapshot();

  // Check alphabetical sorting of adaptors
  expect(state.adaptors[0].name).toBe("a-first-adaptor");
  expect(state.adaptors[1].name).toBe("z-last-adaptor");

  // Check version sorting (descending)
  expect(state.adaptors[0].versions.map(v => v.version)).toEqual([
    "3.1.0",
    "3.0.0",
    "2.9.0",
  ]);
  expect(state.adaptors[1].versions.map(v => v.version)).toEqual([
    "2.0.0",
    "1.5.0",
    "1.0.0",
  ]);
});

test("handles null and undefined channel provider gracefully", async () => {
  const store = createAdaptorStore();

  // Test with null provider - this should handle the null case gracefully
  try {
    store._connectChannel(null);
    throw new Error("Should have thrown error for null provider");
  } catch (error) {
    expect(error instanceof TypeError).toBe(true);
    expect(
      (error as Error).message.includes("Cannot read properties of null")
    ).toBe(true);
  }

  // Test with undefined provider
  try {
    store._connectChannel(undefined);
    throw new Error("Should have thrown error for undefined provider");
  } catch (error) {
    expect(error instanceof TypeError).toBe(true);
  }

  // Test requestAdaptors without any channel connection
  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.error?.includes("No connection available") ?? false).toBe(true);
});

test("maintains state consistency during rapid updates", () => {
  const store = createAdaptorStore();
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  // Perform rapid state updates
  store.setLoading(true);
  store.setError("error 1");
  store.clearError();
  store.setAdaptors(mockAdaptorsList);
  store.setLoading(false);
  store.setError("error 2");
  store.clearError();

  // Each operation should trigger exactly one notification
  expect(notificationCount).toBe(7);

  // Final state should be consistent
  const finalState = store.getSnapshot();
  expect(finalState.adaptors).toEqual(mockAdaptorsList);
  expect(finalState.isLoading).toBe(false);
  expect(finalState.error).toBe(null);
  expect(finalState.lastUpdated ? finalState.lastUpdated > 0 : false).toBe(
    true
  );
});
