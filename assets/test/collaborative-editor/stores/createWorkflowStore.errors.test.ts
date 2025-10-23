import { describe, it, expect, beforeEach } from "vitest";
import * as Y from "yjs";

import type { Session } from "../../../js/collaborative-editor/types/session";

import { createWorkflowStore } from "../../../js/collaborative-editor/stores/createWorkflowStore";

describe("WorkflowStore - Errors Observer", () => {
  let ydoc: Y.Doc;
  let store: ReturnType<typeof createWorkflowStore>;

  beforeEach(() => {
    ydoc = new Y.Doc();

    // Initialize Y.Doc structure
    const workflowMap = ydoc.getMap("workflow");
    const jobsArray = ydoc.getArray("jobs");
    const triggersArray = ydoc.getArray("triggers");
    const edgesArray = ydoc.getArray("edges");
    const positionsMap = ydoc.getMap("positions");
    const errorsMap = ydoc.getMap("errors");

    ydoc.transact(() => {
      workflowMap.set("id", "workflow-1");
      workflowMap.set("name", "Test Workflow");
      workflowMap.set("lock_version", 1);
      workflowMap.set("deleted_at", null);
    });

    store = createWorkflowStore();

    // Create mock provider
    const mockProvider = {
      channel: {},
    } as any;

    store.connect(ydoc as Session.WorkflowDoc, mockProvider);
  });

  it("should sync errors from Y.Doc to state", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add error to Y.Doc
    ydoc.transact(() => {
      errorsMap.set("name", "Name is required");
    });

    // Observer should sync to state
    const state = store.getSnapshot();
    expect(state.errors).toEqual({ name: "Name is required" });
  });

  it("should sync multiple errors from Y.Doc to state", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add multiple errors to Y.Doc
    ydoc.transact(() => {
      errorsMap.set("name", "Name is required");
      errorsMap.set("concurrency", "Must be positive");
    });

    // Observer should sync to state
    const state = store.getSnapshot();
    expect(state.errors).toEqual({
      name: "Name is required",
      concurrency: "Must be positive",
    });
  });

  it("should clear error when removed from Y.Doc", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add error
    ydoc.transact(() => {
      errorsMap.set("name", "Name is required");
    });

    expect(store.getSnapshot().errors).toEqual({ name: "Name is required" });

    // Remove error
    ydoc.transact(() => {
      errorsMap.delete("name");
    });

    // Observer should sync to state
    expect(store.getSnapshot().errors).toEqual({});
  });

  it("should support clearError command", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add error manually
    ydoc.transact(() => {
      errorsMap.set("name", "Name is required");
    });

    expect(store.getSnapshot().errors).toEqual({ name: "Name is required" });

    // Clear via command
    store.clearError("name");

    // State should update
    expect(store.getSnapshot().errors).toEqual({});
  });

  it("should support clearAllErrors command", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add multiple errors manually
    ydoc.transact(() => {
      errorsMap.set("name", "Name is required");
      errorsMap.set("concurrency", "Must be positive");
    });

    expect(store.getSnapshot().errors).toEqual({
      name: "Name is required",
      concurrency: "Must be positive",
    });

    // Clear all via command
    store.clearAllErrors();

    // State should update
    expect(store.getSnapshot().errors).toEqual({});
  });

  it("should support nested error keys for jobs", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add job error with nested key
    ydoc.transact(() => {
      errorsMap.set("jobs.abc-123.name", "Job name is required");
    });

    // Observer should sync to state
    const state = store.getSnapshot();
    expect(state.errors).toEqual({
      "jobs.abc-123.name": "Job name is required",
    });
  });

  it("should support setError command", () => {
    // Set error via command
    store.setError("name", "Name is required");

    // State should update
    const state = store.getSnapshot();
    expect(state.errors).toEqual({ name: "Name is required" });
  });

  it("should handle errors getter", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add error to Y.Doc
    ydoc.transact(() => {
      errorsMap.set("name", "Name is required");
    });

    // Getter should return current errors
    expect(store.errors).toEqual({ name: "Name is required" });
  });

  it("should start with empty errors map", () => {
    const state = store.getSnapshot();
    expect(state.errors).toEqual({});
  });

  it("should update errors when multiple keys change", () => {
    const errorsMap = ydoc.getMap("errors");

    // Add first error
    ydoc.transact(() => {
      errorsMap.set("name", "Name is required");
    });

    expect(store.getSnapshot().errors).toEqual({ name: "Name is required" });

    // Add second error
    ydoc.transact(() => {
      errorsMap.set("concurrency", "Must be positive");
    });

    expect(store.getSnapshot().errors).toEqual({
      name: "Name is required",
      concurrency: "Must be positive",
    });

    // Remove first error
    ydoc.transact(() => {
      errorsMap.delete("name");
    });

    expect(store.getSnapshot().errors).toEqual({
      concurrency: "Must be positive",
    });
  });
});
