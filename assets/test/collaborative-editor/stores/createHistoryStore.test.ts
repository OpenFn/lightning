/**
 * Tests for createHistoryStore - Core Functionality
 *
 * This test suite covers:
 * - Core store interface (subscribe/getSnapshot/withSelector)
 * - State management commands (setLoading, setError, clearError)
 * - Channel integration and request/response flow
 * - Real-time history updates
 * - Error handling for channel operations
 */

import { describe, test, expect, beforeEach } from "vitest";
import { createHistoryStore } from "../../../js/collaborative-editor/stores/createHistoryStore";
import type { HistoryStoreInstance } from "../../../js/collaborative-editor/stores/createHistoryStore";

import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
} from "../mocks/phoenixChannel";
import type {
  MockPhoenixChannel,
  MockPhoenixChannelProvider,
} from "../mocks/phoenixChannel";

describe("createHistoryStore", () => {
  let store: HistoryStoreInstance;
  let mockChannel: MockPhoenixChannel;
  let mockChannelProvider: MockPhoenixChannelProvider;

  beforeEach(() => {
    store = createHistoryStore();
    mockChannel = createMockPhoenixChannel("workflow:collaborate:test");
    mockChannelProvider = createMockPhoenixChannelProvider(mockChannel);
  });

  describe("core store interface", () => {
    test("getSnapshot returns initial state", () => {
      const initialState = store.getSnapshot();

      expect(initialState.history).toEqual([]);
      expect(initialState.isLoading).toBe(false);
      expect(initialState.error).toBe(null);
      expect(initialState.lastUpdated).toBe(null);
    });

    test("subscribe/unsubscribe functionality works correctly", () => {
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

      expect(callCount).toBe(2); // Listener not called after unsubscribe
    });

    test("withSelector creates memoized selector with referential stability", () => {
      const selectHistory = store.withSelector(state => state.history);
      const selectIsLoading = store.withSelector(state => state.isLoading);

      // Initial calls
      const history1 = selectHistory();
      const loading1 = selectIsLoading();

      // Same calls should return same reference
      const history2 = selectHistory();
      const loading2 = selectIsLoading();

      expect(history1).toBe(history2);
      expect(loading1).toBe(loading2);

      // Change unrelated state - history selector should return same reference
      store.setLoading(true);
      const history3 = selectHistory();
      const loading3 = selectIsLoading();

      expect(history1).toBe(history3); // Unrelated state change
      expect(loading1).not.toBe(loading3); // Related state change
    });
  });

  describe("state management", () => {
    test("setLoading updates loading state and notifies subscribers", () => {
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
      // First set loading to true
      store.setLoading(true);
      expect(store.getSnapshot().isLoading).toBe(true);

      // Set error - should clear loading state
      const errorMessage = "Test error message";
      store.setError(errorMessage);

      const state = store.getSnapshot();
      expect(state.error).toBe(errorMessage);
      expect(state.isLoading).toBe(false); // Setting error clears loading
    });

    test("setError with null clears error", () => {
      // Set error first
      store.setError("Test error");
      expect(store.getSnapshot().error).toBe("Test error");

      // Set error to null
      store.setError(null);
      expect(store.getSnapshot().error).toBe(null);
    });

    test("clearError removes error state", () => {
      // Set error first
      store.setError("Test error");
      expect(store.getSnapshot().error).toBe("Test error");

      // Clear error
      store.clearError();
      expect(store.getSnapshot().error).toBe(null);
    });
  });

  describe("channel integration", () => {
    test("_connectChannel registers history_updated listener", () => {
      store._connectChannel(mockChannelProvider as any);

      const handlers = (mockChannel as any)._test.getHandlers(
        "history_updated"
      );
      expect(handlers?.size).toBe(1);
    });

    test("_connectChannel returns cleanup function that unregisters listeners", () => {
      const cleanup = store._connectChannel(mockChannelProvider as any);

      // Verify listener is registered
      let handlers = (mockChannel as any)._test.getHandlers("history_updated");
      expect(handlers?.size).toBe(1);

      // Call cleanup
      cleanup();

      // Verify listener is removed
      handlers = (mockChannel as any)._test.getHandlers("history_updated");
      expect(handlers?.size).toBe(0);
    });
  });

  describe("requestHistory", () => {
    test("sets loading state before request", async () => {
      store._connectChannel(mockChannelProvider as any);

      // Mock the channel push to respond with history
      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === "ok") {
              setTimeout(() => callback({ history: [] }), 10);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      // Start request (don't await yet)
      const promise = store.requestHistory();

      // Check loading state immediately
      expect(store.getSnapshot().isLoading).toBe(true);

      await promise;
    });

    test("handles successful response with valid history data", async () => {
      store._connectChannel(mockChannelProvider as any);

      const mockHistory = [
        {
          id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
          state: "success",
          last_activity: "2025-10-23T21:00:02.293382Z",
          version: 29,
          runs: [
            {
              id: "f3218e57-df40-4a41-b22c-dcdfdf94650e",
              state: "success",
              error_type: null,
              started_at: "2025-10-23T20:59:58.293382Z",
              finished_at: "2025-10-23T21:00:02.293382Z",
            },
          ],
        },
      ];

      // Mock the channel push to respond with history
      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === "ok") {
              setTimeout(() => callback({ history: mockHistory }), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      await store.requestHistory();

      await waitForCondition(() => !store.getSnapshot().isLoading);

      const state = store.getSnapshot();
      expect(state.history).toEqual(mockHistory);
      expect(state.isLoading).toBe(false);
      expect(state.error).toBe(null);
      expect(state.lastUpdated).toBeGreaterThan(0);
    });

    test("handles successful response with run_id parameter", async () => {
      store._connectChannel(mockChannelProvider as any);

      const runId = "f3218e57-df40-4a41-b22c-dcdfdf94650e";
      const mockHistory = [
        {
          id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
          state: "success",
          last_activity: "2025-10-23T21:00:02.293382Z",
          version: 29,
          runs: [
            {
              id: runId,
              state: "success",
              error_type: null,
              started_at: "2025-10-23T20:59:58.293382Z",
              finished_at: "2025-10-23T21:00:02.293382Z",
            },
          ],
        },
      ];

      let pushedPayload: any = null;

      mockChannel.push = (_event: string, payload: unknown) => {
        pushedPayload = payload;
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === "ok") {
              setTimeout(() => callback({ history: mockHistory }), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      await store.requestHistory(runId);

      await waitForCondition(() => !store.getSnapshot().isLoading);

      expect(pushedPayload).toEqual({ run_id: runId });
      expect(store.getSnapshot().history).toEqual(mockHistory);
    });

    test("handles invalid history data with Zod validation error", async () => {
      store._connectChannel(mockChannelProvider as any);

      const invalidHistory = [
        {
          id: "not-a-uuid", // Invalid UUID
          state: "success",
          // Missing required fields
        },
      ];

      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === "ok") {
              setTimeout(() => callback({ history: invalidHistory }), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      await store.requestHistory();

      await waitForCondition(() => !store.getSnapshot().isLoading);

      const state = store.getSnapshot();
      expect(state.error).toContain("Invalid history data");
      expect(state.isLoading).toBe(false);
      expect(state.history).toEqual([]); // Should remain empty
    });

    test("handles channel request failure", async () => {
      store._connectChannel(mockChannelProvider as any);

      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === "error") {
              setTimeout(
                () =>
                  callback({ errors: { base: ["timeout"] }, type: "error" }),
                0
              );
            } else if (status === "timeout") {
              setTimeout(() => callback(), 0);
            }
            return {
              receive: (s: string, cb: (r?: unknown) => void) => {
                if (s === "error") {
                  setTimeout(
                    () => cb({ errors: { base: ["timeout"] }, type: "error" }),
                    0
                  );
                } else if (s === "timeout") {
                  setTimeout(() => cb(), 0);
                }
                return { receive: () => ({}) };
              },
            };
          },
        } as any;
      };

      await store.requestHistory();

      // Wait for error state
      await waitForCondition(() => store.getSnapshot().error !== null, {
        timeout: 2000,
      });

      const state = store.getSnapshot();
      expect(state.error).toBe("Failed to request history");
      expect(state.isLoading).toBe(false);
    });

    test("handles request when no channel is connected", async () => {
      // Don't connect channel
      await store.requestHistory();

      const state = store.getSnapshot();
      expect(state.error).toBe("No connection available");
      expect(state.isLoading).toBe(false);
    });
  });

  describe("real-time updates", () => {
    test("handles work order created event", () => {
      store._connectChannel(mockChannelProvider as any);

      const newWorkOrder = {
        id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
        state: "pending",
        last_activity: "2025-10-23T21:00:02.293382Z",
        version: 30,
        runs: [],
      };

      (mockChannel as any)._test.emit("history_updated", {
        action: "created",
        work_order: newWorkOrder,
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(1);
      expect(state.history[0]).toEqual(newWorkOrder);
    });

    test("limits history to 20 work orders when adding new one", () => {
      store._connectChannel(mockChannelProvider as any);

      // Add 20 work orders
      for (let i = 0; i < 20; i++) {
        (mockChannel as any)._test.emit("history_updated", {
          action: "created",
          work_order: {
            id: `e2107d46-cf29-4930-b11b-cbcfcf8354${i.toString().padStart(2, "0")}`,
            state: "success",
            last_activity: "2025-10-23T21:00:02.293382Z",
            version: i,
            runs: [],
          },
        });
      }

      expect(store.getSnapshot().history).toHaveLength(20);

      // Add 21st work order
      (mockChannel as any)._test.emit("history_updated", {
        action: "created",
        work_order: {
          id: "f3218e57-df40-4a41-b22c-dcdfdf946521",
          state: "success",
          last_activity: "2025-10-23T21:00:02.293382Z",
          version: 21,
          runs: [],
        },
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(20);
      expect(state.history[0].id).toBe("f3218e57-df40-4a41-b22c-dcdfdf946521");
    });

    test("handles work order updated event", () => {
      store._connectChannel(mockChannelProvider as any);

      const workOrder = {
        id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
        state: "running",
        last_activity: "2025-10-23T21:00:02.293382Z",
        version: 30,
        runs: [],
      };

      // Add initial work order
      (mockChannel as any)._test.emit("history_updated", {
        action: "created",
        work_order: workOrder,
      });

      // Update it
      const updatedWorkOrder = {
        ...workOrder,
        state: "success",
        last_activity: "2025-10-23T21:05:00.000000Z",
      };

      (mockChannel as any)._test.emit("history_updated", {
        action: "updated",
        work_order: updatedWorkOrder,
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(1);
      expect(state.history[0].state).toBe("success");
      expect(state.history[0].last_activity).toBe(
        "2025-10-23T21:05:00.000000Z"
      );
    });

    test("handles run created event", () => {
      store._connectChannel(mockChannelProvider as any);

      const workOrder = {
        id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
        state: "running",
        last_activity: "2025-10-23T21:00:02.293382Z",
        version: 30,
        runs: [],
      };

      // Add initial work order
      (mockChannel as any)._test.emit("history_updated", {
        action: "created",
        work_order: workOrder,
      });

      // Add run
      const newRun = {
        id: "f3218e57-df40-4a41-b22c-dcdfdf94650e",
        state: "started",
        error_type: null,
        started_at: "2025-10-23T21:00:00.000000Z",
        finished_at: null,
      };

      (mockChannel as any)._test.emit("history_updated", {
        action: "run_created",
        work_order_id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
        run: newRun,
      });

      const state = store.getSnapshot();
      expect(state.history[0].runs).toHaveLength(1);
      expect(state.history[0].runs[0]).toEqual(newRun);
    });

    test("handles run updated event", () => {
      store._connectChannel(mockChannelProvider as any);

      const run = {
        id: "f3218e57-df40-4a41-b22c-dcdfdf94650e",
        state: "started",
        error_type: null,
        started_at: "2025-10-23T21:00:00.000000Z",
        finished_at: null,
      };

      const workOrder = {
        id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
        state: "running",
        last_activity: "2025-10-23T21:00:02.293382Z",
        version: 30,
        runs: [run],
      };

      // Add initial work order with run
      (mockChannel as any)._test.emit("history_updated", {
        action: "created",
        work_order: workOrder,
      });

      // Update run
      const updatedRun = {
        ...run,
        state: "success",
        finished_at: "2025-10-23T21:00:05.000000Z",
      };

      (mockChannel as any)._test.emit("history_updated", {
        action: "run_updated",
        work_order_id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
        run: updatedRun,
      });

      const state = store.getSnapshot();
      expect(state.history[0].runs[0].state).toBe("success");
      expect(state.history[0].runs[0].finished_at).toBe(
        "2025-10-23T21:00:05.000000Z"
      );
    });

    test("ignores run events for non-existent work orders", () => {
      store._connectChannel(mockChannelProvider as any);

      const newRun = {
        id: "f3218e57-df40-4a41-b22c-dcdfdf94650e",
        state: "started",
        error_type: null,
        started_at: "2025-10-23T21:00:00.000000Z",
        finished_at: null,
      };

      // Try to add run to non-existent work order
      (mockChannel as any)._test.emit("history_updated", {
        action: "run_created",
        work_order_id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
        run: newRun,
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(0); // No work orders added
    });
  });
});
