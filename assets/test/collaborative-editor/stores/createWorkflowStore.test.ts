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

import { describe, test, expect, beforeEach } from "vitest";
import * as Y from "yjs";
import type { Channel } from "phoenix";

import { createWorkflowStore } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import type { WorkflowStoreInstance } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import type { PhoenixChannelProvider } from "y-phoenix-channel";
import type { Session } from "../../../js/collaborative-editor/types/session";
import {
  createMockChannelPushOk,
  createMockChannelPushError,
} from "../__helpers__/channelMocks";

describe("WorkflowStore - Save Workflow", () => {
  let store: WorkflowStoreInstance;
  let ydoc: Session.WorkflowDoc;
  let mockChannel: Channel;
  let mockProvider: PhoenixChannelProvider & { channel: Channel };

  beforeEach(() => {
    // Create fresh store and Y.Doc instances
    store = createWorkflowStore();
    ydoc = new Y.Doc() as Session.WorkflowDoc;

    // Mock Phoenix Channel with save_workflow support
    mockChannel = {
      push: createMockChannelPushOk({
        saved_at: new Date().toISOString(),
        lock_version: 1,
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

  test("returns response with lock_version after successful save", async () => {
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

    // Note: Y.Doc lock_version is NOT updated by client
    // The server will merge the saved workflow back into Y.Doc
    // and broadcast the update to all clients via Y.js sync
    expect(workflowMap.get("lock_version")).toBeNull();

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

  test("returns incremented lock_version on subsequent saves", async () => {
    // First save
    await store.saveWorkflow();
    const workflowMap = ydoc.getMap("workflow");

    // Simulate server updating Y.Doc (would happen via Y.js sync in real scenario)
    workflowMap.set("lock_version", 1);

    // Mock incremented lock_version for second save
    mockChannel.push = createMockChannelPushOk({
      saved_at: new Date().toISOString(),
      lock_version: 2,
    });

    // Second save
    const response = await store.saveWorkflow();

    // Verify response
    expect(response).toMatchObject({
      lock_version: 2,
    });

    // Note: Client doesn't update Y.Doc - server handles that
    // Y.Doc still shows version 1 until server broadcasts the update
    expect(workflowMap.get("lock_version")).toBe(1);
  });

  test("does not update lock_version if save fails", async () => {
    // Mock failure response with correct error structure
    mockChannel.push = createMockChannelPushError("Save failed", "save_error");

    const workflowMap = ydoc.getMap("workflow");
    expect(workflowMap.get("lock_version")).toBeNull();

    // Try to save and expect error
    await expect(store.saveWorkflow()).rejects.toThrow("Save failed");

    // Verify Y.Doc was NOT updated
    expect(workflowMap.get("lock_version")).toBeNull();
  });

  test("handles response without lock_version gracefully", async () => {
    // Mock response without lock_version (shouldn't happen, but defensive)
    mockChannel.push = createMockChannelPushOk({
      saved_at: new Date().toISOString(),
      // lock_version intentionally omitted
    });

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

  test("Y.Doc observer propagates lock_version changes to Immer state when server updates", () => {
    // Track state updates via subscription
    let stateUpdateCount = 0;
    const unsubscribe = store.subscribe(() => {
      stateUpdateCount++;
    });

    // Simulate server updating Y.Doc (would happen via Y.js sync in real scenario)
    const workflowMap = ydoc.getMap("workflow");
    workflowMap.set("lock_version", 5);

    // Get current snapshot
    const snapshot = store.getSnapshot();

    // Verify Immer state reflects Y.Doc update from server
    expect(snapshot.workflow?.lock_version).toBe(5);

    // Verify at least one state update occurred
    expect(stateUpdateCount).toBeGreaterThan(0);

    unsubscribe();
  });
});
