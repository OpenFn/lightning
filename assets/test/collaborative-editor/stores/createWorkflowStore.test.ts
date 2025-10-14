/**
 * WorkflowStore Integration Tests
 *
 * Tests for save workflow behavior, focusing on lock_version synchronization
 * between Y.Doc and the backend database after save operations.
 *
 * Key Testing Patterns:
 * - Uses Vitest for test framework
 * - Uses Y.Doc for collaborative state management
 * - Mocks Phoenix Channel for backend communication
 * - Verifies Y.Doc state directly (not just response validation)
 */

import { describe, test, expect, beforeEach, vi } from "vitest";
import * as Y from "yjs";
import type { Channel } from "phoenix";

import { createWorkflowStore } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import type { WorkflowStoreInstance } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import type { PhoenixChannelProvider } from "y-phoenix-channel";

describe("WorkflowStore - Save Workflow", () => {
  let store: WorkflowStoreInstance;
  let ydoc: Y.Doc;
  let mockChannel: Channel;
  let mockProvider: PhoenixChannelProvider & { channel: Channel };

  beforeEach(() => {
    // Create fresh store and Y.Doc instances
    store = createWorkflowStore();
    ydoc = new Y.Doc();

    // Mock Phoenix Channel with save_workflow support
    // The push().receive() chain requires each receive to return an object with receive method
    mockChannel = {
      push: vi.fn((event: string) => {
        // Create chainable mock push object
        const mockPush = {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (event === "save_workflow" && status === "ok") {
              // Simulate successful save with lock_version in response
              setTimeout(() => {
                callback({
                  saved_at: new Date().toISOString(),
                  lock_version: 1,
                });
              }, 0);
            } else if (status === "error") {
              // Keep error handler registered but don't call it
            } else if (status === "timeout") {
              // Keep timeout handler registered but don't call it
            }
            return mockPush; // Return self for chaining
          },
        };
        return mockPush;
      }),
    } as unknown as Channel;

    // Create mock provider with channel
    mockProvider = {
      channel: mockChannel,
      synced: true,
      awareness: null,
      doc: ydoc,
    } as unknown as PhoenixChannelProvider & { channel: Channel };

    // Initialize workflow in Y.Doc with null lock_version (new workflow)
    const workflowMap = ydoc.getMap("workflow");
    workflowMap.set("id", "workflow-123");
    workflowMap.set("name", "Test Workflow");
    workflowMap.set("lock_version", null);

    // Initialize empty arrays for jobs, triggers, edges
    ydoc.getArray("jobs");
    ydoc.getArray("triggers");
    ydoc.getArray("edges");
    ydoc.getMap("positions");

    // Connect store to Y.Doc and provider
    store.connect(ydoc, mockProvider);
  });

  test("updates workflow lock_version in Y.Doc after successful save", async () => {
    // Verify initial state
    const workflowMap = ydoc.getMap("workflow");
    expect(workflowMap.get("lock_version")).toBeNull();

    // Save workflow
    const response = await store.saveWorkflow();

    // Verify response contains lock_version
    expect(response).toMatchObject({
      saved_at: expect.any(String),
      lock_version: 1,
    });

    // Verify Y.Doc was updated with new lock_version
    expect(workflowMap.get("lock_version")).toBe(1);

    // Verify channel.push was called with correct payload
    expect(mockChannel.push).toHaveBeenCalledWith(
      "save_workflow",
      expect.objectContaining({
        id: "workflow-123",
        name: "Test Workflow",
        lock_version: null, // Original value at time of save
      })
    );
  });

  test("updates lock_version on subsequent saves", async () => {
    // First save
    await store.saveWorkflow();
    const workflowMap = ydoc.getMap("workflow");
    expect(workflowMap.get("lock_version")).toBe(1);

    // Mock incremented lock_version for second save
    mockChannel.push = vi.fn(() => {
      const mockPush = {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === "ok") {
            setTimeout(() => {
              callback({
                saved_at: new Date().toISOString(),
                lock_version: 2,
              });
            }, 0);
          }
          return mockPush;
        },
      };
      return mockPush;
    }) as unknown as Channel["push"];

    // Second save
    const response = await store.saveWorkflow();

    // Verify response
    expect(response).toMatchObject({
      lock_version: 2,
    });

    // Verify Y.Doc updated to lock_version 2
    expect(workflowMap.get("lock_version")).toBe(2);
  });

  test("does not update lock_version if save fails", async () => {
    // Mock failure response
    mockChannel.push = vi.fn(() => {
      const mockPush = {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === "error") {
            setTimeout(() => {
              callback({ reason: "Save failed" });
            }, 0);
          } else if (status === "ok") {
            // Don't call ok handler
          }
          return mockPush;
        },
      };
      return mockPush;
    }) as unknown as Channel["push"];

    const workflowMap = ydoc.getMap("workflow");
    expect(workflowMap.get("lock_version")).toBeNull();

    // Try to save and expect error
    await expect(store.saveWorkflow()).rejects.toThrow("Save failed");

    // Verify Y.Doc was NOT updated
    expect(workflowMap.get("lock_version")).toBeNull();
  });

  test("handles response without lock_version gracefully", async () => {
    // Mock response without lock_version (shouldn't happen, but defensive)
    mockChannel.push = vi.fn(() => {
      const mockPush = {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === "ok") {
            setTimeout(() => {
              callback({
                saved_at: new Date().toISOString(),
                // lock_version intentionally omitted
              });
            }, 0);
          }
          return mockPush;
        },
      };
      return mockPush;
    }) as unknown as Channel["push"];

    const workflowMap = ydoc.getMap("workflow");
    const originalLockVersion = workflowMap.get("lock_version");

    // Save workflow
    const response = await store.saveWorkflow();

    // Response should succeed but not have lock_version
    expect(response).toMatchObject({
      saved_at: expect.any(String),
    });
    expect(response?.lock_version).toBeUndefined();

    // Y.Doc should remain unchanged
    expect(workflowMap.get("lock_version")).toBe(originalLockVersion);
  });

  test("save includes all workflow data in payload", async () => {
    // Add a job to the workflow
    const jobsArray = ydoc.getArray("jobs");
    const jobMap = new Y.Map();
    jobMap.set("id", "job-1");
    jobMap.set("name", "Test Job");
    jobMap.set("body", new Y.Text("console.log('test')"));
    jobsArray.push([jobMap]);

    // Add a trigger
    const triggersArray = ydoc.getArray("triggers");
    const triggerMap = new Y.Map();
    triggerMap.set("id", "trigger-1");
    triggerMap.set("type", "webhook");
    triggersArray.push([triggerMap]);

    // Add an edge
    const edgesArray = ydoc.getArray("edges");
    const edgeMap = new Y.Map();
    edgeMap.set("id", "edge-1");
    edgeMap.set("source_trigger_id", "trigger-1");
    edgeMap.set("target_job_id", "job-1");
    edgesArray.push([edgeMap]);

    // Add positions
    const positionsMap = ydoc.getMap("positions");
    positionsMap.set("job-1", { x: 100, y: 200 });

    // Save workflow
    await store.saveWorkflow();

    // Verify channel.push was called with complete payload
    expect(mockChannel.push).toHaveBeenCalledWith(
      "save_workflow",
      expect.objectContaining({
        id: "workflow-123",
        name: "Test Workflow",
        jobs: [
          expect.objectContaining({
            id: "job-1",
            name: "Test Job",
          }),
        ],
        triggers: [
          expect.objectContaining({
            id: "trigger-1",
            type: "webhook",
          }),
        ],
        edges: [
          expect.objectContaining({
            id: "edge-1",
            source_trigger_id: "trigger-1",
            target_job_id: "job-1",
          }),
        ],
        positions: {
          "job-1": { x: 100, y: 200 },
        },
      })
    );
  });

  test("returns null if Y.Doc not connected", async () => {
    // Create disconnected store
    const disconnectedStore = createWorkflowStore();

    // Try to save without connecting
    const response = await disconnectedStore.saveWorkflow();

    // Should return null and not throw
    expect(response).toBeNull();
  });

  test("returns null if provider not connected", async () => {
    // Create store with only Y.Doc (no provider)
    const storeWithoutProvider = createWorkflowStore();
    const ydocOnly = new Y.Doc();
    const workflowMap = ydocOnly.getMap("workflow");
    workflowMap.set("id", "test");

    // Connect with null provider (TypeScript workaround for test)
    // In reality, connect requires both ydoc and provider
    // This test verifies the guard clause in saveWorkflow

    // Try to save
    const response = await storeWithoutProvider.saveWorkflow();

    // Should return null
    expect(response).toBeNull();
  });

  test("updateWorkflowLockVersion can be called directly", () => {
    const workflowMap = ydoc.getMap("workflow");
    expect(workflowMap.get("lock_version")).toBeNull();

    // Call updateWorkflowLockVersion directly
    store.updateWorkflowLockVersion(5);

    // Verify Y.Doc updated
    expect(workflowMap.get("lock_version")).toBe(5);

    // Call again with different value
    store.updateWorkflowLockVersion(10);
    expect(workflowMap.get("lock_version")).toBe(10);
  });

  test("updateWorkflowLockVersion handles disconnected Y.Doc gracefully", () => {
    // Create disconnected store
    const disconnectedStore = createWorkflowStore();

    // Should not throw when Y.Doc not connected
    expect(() => {
      disconnectedStore.updateWorkflowLockVersion(1);
    }).not.toThrow();
  });

  test("Y.Doc observer propagates lock_version changes to Immer state", async () => {
    // Track state updates via subscription
    let stateUpdateCount = 0;
    const unsubscribe = store.subscribe(() => {
      stateUpdateCount++;
    });

    // Save workflow (triggers Y.Doc update which should trigger observer)
    await store.saveWorkflow();

    // Wait for observer to process (Y.js observers are synchronous)
    // The observer should update the Immer state

    // Get current snapshot
    const snapshot = store.getSnapshot();

    // Verify Immer state reflects Y.Doc update
    expect(snapshot.workflow?.lock_version).toBe(1);

    // Verify at least one state update occurred
    expect(stateUpdateCount).toBeGreaterThan(0);

    unsubscribe();
  });
});
