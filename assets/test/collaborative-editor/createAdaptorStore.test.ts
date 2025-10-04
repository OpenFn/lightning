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

/**
 * Test Fixtures
 *
 * This file uses Vitest 3.x fixtures for cleaner test setup and automatic cleanup.
 *
 * Available fixtures:
 * - store: AdaptorStore instance (auto cleanup)
 * - mockChannel: Mock Phoenix channel
 * - mockProvider: Mock Phoenix channel provider (depends on mockChannel)
 * - connectedStore: Store with channel connected (auto cleanup)
 *
 * Usage:
 * adaptorTest("test name", async ({ connectedStore }) => {
 *   const { store, provider } = connectedStore;
 *   // test logic - cleanup automatic
 * });
 */

import { describe, test, expect } from "vitest";

import { createAdaptorStore } from "../../js/collaborative-editor/stores/createAdaptorStore";
import type { AdaptorStoreInstance } from "../../js/collaborative-editor/stores/createAdaptorStore";

import {
  mockAdaptorsList,
  mockAdaptor,
  invalidAdaptorData,
  createMockAdaptor,
} from "./fixtures/adaptorData.js";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
} from "./mocks/phoenixChannel.js";
import type {
  MockPhoenixChannel,
  MockPhoenixChannelProvider,
} from "./mocks/phoenixChannel.js";

// Define fixture types
interface AdaptorTestFixtures {
  store: AdaptorStoreInstance;
  mockChannel: MockPhoenixChannel;
  mockProvider: MockPhoenixChannelProvider;
  connectedStore: {
    store: AdaptorStoreInstance;
    provider: MockPhoenixChannelProvider;
    cleanup: () => void;
  };
}

// Vitest 3.x fixtures for cleaner test setup and automatic cleanup
const adaptorTest = test.extend<AdaptorTestFixtures>({
  store: async ({}, use) => {
    const store = createAdaptorStore();
    await use(store);
    // Automatic cleanup - store doesn't need explicit cleanup
  },

  mockChannel: async ({}, use) => {
    const channel = createMockPhoenixChannel();
    await use(channel);
    // Channel cleanup happens automatically
  },

  mockProvider: async ({ mockChannel }, use) => {
    const provider = createMockPhoenixChannelProvider(mockChannel);
    await use(provider);
  },

  connectedStore: async ({ store, mockProvider }, use) => {
    // Setup: connect channel to store
    const cleanup = store._connectChannel(mockProvider as any);

    await use({ store, provider: mockProvider, cleanup });

    // Automatic cleanup
    cleanup();
  },
});

describe("createAdaptorStore", () => {
  describe("initialization", () => {
    test("getSnapshot returns initial state", () => {
      const store = createAdaptorStore();
      const initialState = store.getSnapshot();

      expect(initialState.adaptors).toEqual([]);
      expect(initialState.isLoading).toBe(false);
      expect(initialState.error).toBe(null);
      expect(initialState.lastUpdated).toBe(null);
    });
  });

  describe("subscriptions", () => {
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

      expect(callCount).toBe(1);

      // Unsubscribe and trigger change
      unsubscribe();
      store.clearError();

      // Listener should not be called after unsubscribe
      expect(callCount).toBe(1);
    });

    test("withSelector creates memoized selector with referential stability", () => {
      const store = createAdaptorStore();

      const selectAdaptors = store.withSelector(state => state.adaptors);
      const selectIsLoading = store.withSelector(state => state.isLoading);

      // Initial calls
      const adaptors1 = selectAdaptors();
      const loading1 = selectIsLoading();

      // Change unrelated state - adaptors selector should return same reference
      store.setLoading(true);
      const adaptors3 = selectAdaptors();
      const loading3 = selectIsLoading();

      // Unrelated state change should not affect memoized selector
      expect(adaptors1).toBe(adaptors3);
      // Related state change should return new value
      expect(loading1).not.toBe(loading3);
    });

    test("handles multiple subscribers correctly", () => {
      const store = createAdaptorStore();

      let listener1Count = 0;
      let listener2Count = 0;

      const unsubscribe1 = store.subscribe(() => {
        listener1Count++;
      });
      const unsubscribe2 = store.subscribe(() => {
        listener2Count++;
      });

      // Trigger change
      store.setLoading(true);

      expect(listener1Count).toBe(1);
      expect(listener2Count).toBe(1);

      // Unsubscribe middle listener
      unsubscribe2();

      // Trigger another change
      store.setError("test");

      // Unsubscribed listener should not be called
      expect(listener2Count).toBe(1);

      // Cleanup
      unsubscribe1();
    });
  });

  describe("state management", () => {
    describe("loading state", () => {
      test("setLoading updates loading state and notifies subscribers", () => {
        const store = createAdaptorStore();
        let notificationCount = 0;

        store.subscribe(() => {
          notificationCount++;
        });

        store.setLoading(true);
        expect(store.getSnapshot().isLoading).toBe(true);

        store.setLoading(false);
        expect(store.getSnapshot().isLoading).toBe(false);
        // Should notify subscribers on each state change
        expect(notificationCount).toBe(2);
      });
    });

    describe("error state", () => {
      test("setError updates error state and sets loading to false", () => {
        const store = createAdaptorStore();
        store.setLoading(true);

        const errorMessage = "Test error message";
        store.setError(errorMessage);

        const state = store.getSnapshot();
        expect(state.error).toBe(errorMessage);
        // Setting error should clear loading state
        expect(state.isLoading).toBe(false);
      });

      test("clearError removes error state", () => {
        const store = createAdaptorStore();
        store.setError("Test error");

        store.clearError();
        expect(store.getSnapshot().error).toBeNull();
      });
    });

    describe("adaptors state", () => {
      test("setAdaptors updates adaptors list and metadata", () => {
        const store = createAdaptorStore();
        const timestamp = Date.now();

        store.setAdaptors(mockAdaptorsList);

        const state = store.getSnapshot();
        expect(state.adaptors).toEqual(mockAdaptorsList);
        expect(state.error).toBeNull();
        expect(state.lastUpdated).toBeGreaterThanOrEqual(timestamp);
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
        expect(finalState.error).toBeNull();
        expect(finalState.lastUpdated).toBeGreaterThan(0);
      });
    });
  });

  describe("Phoenix channel integration", () => {
    describe("requestAdaptors", () => {
      adaptorTest(
        "processes valid data correctly via channel",
        async ({ store, mockChannel, mockProvider }) => {
          let _notificationCount = 0;

          store.subscribe(() => {
            _notificationCount++;
          });

          // Set up the channel with successful response containing mockAdaptorsList
          mockChannel.push = (event: string, _payload: unknown) => {
            const mockPush = {
              receive: (
                status: string,
                callback: (response?: unknown) => void
              ) => {
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
          store._connectChannel(mockProvider as any);
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

          // Adaptors should be sorted alphabetically with versions descending
          expect(state.adaptors).toEqual(expectedSortedAdaptors);
          expect(state.isLoading).toBe(false);
          expect(state.error).toBeNull();
          expect(state.lastUpdated).toBeGreaterThan(0);
        }
      );

      adaptorTest(
        "handles invalid data gracefully via channel",
        async ({ store, mockChannel, mockProvider }) => {
          // Set up the channel with response containing invalid data
          mockChannel.push = (event: string, _payload: unknown) => {
            const mockPush = {
              receive: (
                status: string,
                callback: (response?: unknown) => void
              ) => {
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
          store._connectChannel(mockProvider as any);
          await store.requestAdaptors();

          const state = store.getSnapshot();
          expect(state.adaptors).toHaveLength(0);
          expect(state.isLoading).toBe(false);
          expect(state.error).toContain("Invalid adaptors data");
        }
      );

      adaptorTest(
        "handles successful response",
        async ({ store, mockChannel, mockProvider }) => {
          // Set up the channel with successful response
          mockChannel.push = (event: string, _payload: unknown) => {
            const mockPush = {
              receive: (
                status: string,
                callback: (response?: unknown) => void
              ) => {
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
          store._connectChannel(mockProvider as any);

          // Request adaptors
          await store.requestAdaptors();

          const state = store.getSnapshot();
          expect(state.adaptors).toHaveLength(mockAdaptorsList.length);
          expect(state.error).toBeNull();
          expect(state.isLoading).toBe(false);
        }
      );

      adaptorTest(
        "handles error response",
        async ({ store, mockChannel, mockProvider }) => {
          // Set up the channel with error response
          mockChannel.push = (event: string, _payload: unknown) => {
            const mockPush = {
              receive: (
                status: string,
                callback: (response?: unknown) => void
              ) => {
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
          store._connectChannel(mockProvider as any);

          // Request adaptors (should fail)
          await store.requestAdaptors();

          const state = store.getSnapshot();
          expect(state.adaptors).toHaveLength(0);
          expect(state.error).toContain("Failed to request adaptors");
          expect(state.isLoading).toBe(false);
        }
      );

      test("handles no channel connection", async () => {
        const store = createAdaptorStore();

        await store.requestAdaptors();

        const state = store.getSnapshot();
        expect(state.error).toContain("No connection available");
        expect(state.isLoading).toBe(false);
      });
    });

    describe("channel events", () => {
      adaptorTest(
        "processes adaptors_updated events correctly",
        async ({ store, mockChannel, mockProvider }) => {
          // Set up the initial channel response for request_adaptors
          mockChannel.push = (event: string, _payload: unknown) => {
            const mockPush = {
              receive: (
                status: string,
                callback: (response?: unknown) => void
              ) => {
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
          const cleanup = store._connectChannel(mockProvider as any);

          // Simulate adaptors_updated event from server
          const mockChannelWithTest = mockChannel as typeof mockChannel & {
            _test: { emit: (event: string, message: unknown) => void };
          };
          mockChannelWithTest._test.emit("adaptors_updated", mockAdaptorsList);

          // Wait for the store to process the update
          await waitForCondition(() => store.getSnapshot().adaptors.length > 0);

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
        }
      );
    });

    describe("connectChannel", () => {
      adaptorTest(
        "sets up event listeners and requests adaptors",
        async ({ store, mockChannel, mockProvider }) => {
          // Mock the channel push method to simulate successful response
          mockChannel.push = (event: string, _payload: unknown) => {
            const mockPush = {
              receive: (
                status: string,
                callback: (response?: unknown) => void
              ) => {
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
          const cleanup = store._connectChannel(mockProvider as any);

          // Wait for adaptors to be loaded
          await waitForCondition(() => store.getSnapshot().adaptors.length > 0);

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

          // Wait for the update to be processed
          await waitForCondition(
            () => store.getSnapshot().adaptors.length === 1
          );

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
        }
      );
    });

    describe("error handling", () => {
      test("handles null and undefined channel provider gracefully", async () => {
        const store = createAdaptorStore();

        // Test with null provider - this should handle the null case gracefully
        try {
          store._connectChannel(null as any);
          throw new Error("Should have thrown error for null provider");
        } catch (error) {
          expect(error instanceof TypeError).toBe(true);
          expect(
            (error as Error).message.includes("Cannot read properties of null")
          ).toBe(true);
        }

        // Test with undefined provider
        try {
          store._connectChannel(undefined as any);
          throw new Error("Should have thrown error for undefined provider");
        } catch (error) {
          expect(error instanceof TypeError).toBe(true);
        }

        // Test requestAdaptors without any channel connection
        await store.requestAdaptors();

        const state = store.getSnapshot();
        expect(state.error).toContain("No connection available");
      });

      adaptorTest(
        "handles complex adaptor data transformations",
        async ({ store, mockChannel, mockProvider }) => {
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
              receive: (
                status: string,
                callback: (response?: unknown) => void
              ) => {
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
          store._connectChannel(mockProvider as any);
          await store.requestAdaptors();

          const state = store.getSnapshot();

          // Check alphabetical sorting of adaptors
          expect(state.adaptors[0].name).toBe("a-first-adaptor");
          expect(state.adaptors[1].name).toBe("z-last-adaptor");

          // Check version sorting (descending)
          expect(
            state.adaptors[0].versions.map(
              (v: { version: string }) => v.version
            )
          ).toEqual(["3.1.0", "3.0.0", "2.9.0"]);
          expect(
            state.adaptors[1].versions.map(
              (v: { version: string }) => v.version
            )
          ).toEqual(["2.0.0", "1.5.0", "1.0.0"]);
        }
      );
    });
  });

  describe("query helpers", () => {
    test("findAdaptorByName returns correct adaptor", () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      const foundAdaptor = store.findAdaptorByName("@openfn/language-http");
      expect(foundAdaptor).toEqual(mockAdaptor);

      const notFound = store.findAdaptorByName("@openfn/language-nonexistent");
      expect(notFound).toBeNull();
    });

    test("getLatestVersion returns correct version", () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      const latestVersion = store.getLatestVersion("@openfn/language-http");
      expect(latestVersion).toBe("2.1.0");

      const notFound = store.getLatestVersion("@openfn/language-nonexistent");
      expect(notFound).toBeNull();
    });

    test("getVersions returns correct versions array", () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      const versions = store.getVersions("@openfn/language-http");
      expect(versions).toEqual(mockAdaptor.versions);

      const notFound = store.getVersions("@openfn/language-nonexistent");
      expect(notFound).toHaveLength(0);
    });
  });
});
