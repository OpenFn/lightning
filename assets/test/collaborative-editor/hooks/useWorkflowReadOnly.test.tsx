/**
 * useWorkflowReadOnly Hook Tests
 *
 * Tests for the read-only state hook that determines if a workflow
 * should be editable based on deletion state, permissions, and snapshot version.
 */

import { act, renderHook, waitFor } from "@testing-library/react";
import type React from "react";
import { describe, expect, test } from "vitest";
import * as Y from "yjs";

import type { StoreContextValue } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { StoreContext } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { useWorkflowReadOnly } from "../../../js/collaborative-editor/hooks/useWorkflow";
import type { SessionContextStoreInstance } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import { createSessionContextStore } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import type { WorkflowStoreInstance } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import { createWorkflowStore } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import type { Session } from "../../../js/collaborative-editor/types/session";
import {
  createSessionContext,
  mockPermissions,
} from "../__helpers__/sessionContextFactory";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from "../mocks/phoenixChannel";

// =============================================================================
// TEST HELPERS
// =============================================================================

interface WrapperOptions {
  permissions?: { can_edit_workflow: boolean; can_run_workflow: boolean };
  latestSnapshotLockVersion?: number;
  workflowLockVersion?: number | null;
  workflowDeletedAt?: string | null;
}

function createWrapper(options: WrapperOptions = {}): [
  React.ComponentType<{ children: React.ReactNode }>,
  {
    sessionContextStore: SessionContextStoreInstance;
    workflowStore: WorkflowStoreInstance;
    ydoc: Session.WorkflowDoc;
    mockChannel: any;
    emitSessionContext: () => void;
  },
] {
  const {
    permissions = { can_edit_workflow: true, can_run_workflow: true },
    latestSnapshotLockVersion = 1,
    workflowLockVersion = 1,
    workflowDeletedAt = null,
  } = options;

  // Create stores
  const sessionContextStore = createSessionContextStore();
  const workflowStore = createWorkflowStore();

  // Create Y.Doc and set up workflow data
  const ydoc = new Y.Doc() as Session.WorkflowDoc;
  const workflowMap = ydoc.getMap("workflow");
  workflowMap.set("id", "test-workflow-123");
  workflowMap.set("name", "Test Workflow");
  workflowMap.set("lock_version", workflowLockVersion);
  workflowMap.set("deleted_at", workflowDeletedAt);

  // Initialize empty arrays for jobs, triggers, edges
  ydoc.getArray("jobs");
  ydoc.getArray("triggers");
  ydoc.getArray("edges");
  ydoc.getMap("positions");

  // Connect workflow store to Y.Doc
  const mockChannel = createMockPhoenixChannel("test:room");
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  (mockProvider as any).doc = ydoc;
  workflowStore.connect(ydoc, mockProvider as any);

  // Connect session context store to channel
  sessionContextStore._connectChannel(mockProvider as any);

  // Helper function to emit session context
  const emitSessionContext = () => {
    (mockChannel as any)._test.emit(
      "session_context",
      createSessionContext({
        permissions,
        latest_snapshot_lock_version: latestSnapshotLockVersion,
      })
    );
  };

  const mockStoreValue: StoreContextValue = {
    sessionContextStore,
    workflowStore,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    uiStore: {} as any,
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );

  return [
    wrapper,
    {
      sessionContextStore,
      workflowStore,
      ydoc,
      mockChannel,
      emitSessionContext,
    },
  ];
}

// =============================================================================
// DELETED WORKFLOW TESTS
// =============================================================================

describe("useWorkflowReadOnly - Deleted Workflow", () => {
  test("returns read-only true with deletion message for deleted workflow", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      workflowDeletedAt: new Date().toISOString(),
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(true);
      expect(result.current.tooltipMessage).toBe(
        "This workflow has been deleted and cannot be edited"
      );
    });
  });

  test("deleted state takes priority over permission restrictions", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: false, can_run_workflow: false },
      workflowDeletedAt: new Date().toISOString(),
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(true);
      expect(result.current.tooltipMessage).toBe(
        "This workflow has been deleted and cannot be edited"
      );
    });
  });

  test("deleted state takes priority over old snapshot", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      latestSnapshotLockVersion: 2,
      workflowLockVersion: 1,
      workflowDeletedAt: new Date().toISOString(),
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(true);
      expect(result.current.tooltipMessage).toBe(
        "This workflow has been deleted and cannot be edited"
      );
    });
  });
});

// =============================================================================
// PERMISSION TESTS
// =============================================================================

describe("useWorkflowReadOnly - Permissions", () => {
  test("returns read-only true with permission message when user lacks edit permission", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: false, can_run_workflow: false },
      workflowDeletedAt: null,
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(true);
      expect(result.current.tooltipMessage).toBe(
        "You do not have permission to edit this workflow"
      );
    });
  });

  test("permission restriction takes priority over old snapshot", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: false, can_run_workflow: false },
      latestSnapshotLockVersion: 2,
      workflowLockVersion: 1,
      workflowDeletedAt: null,
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(true);
      expect(result.current.tooltipMessage).toBe(
        "You do not have permission to edit this workflow"
      );
    });
  });
});

// =============================================================================
// SNAPSHOT VERSION TESTS
// =============================================================================

describe("useWorkflowReadOnly - Snapshot Version", () => {
  test("returns read-only true with snapshot message for old snapshot", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      latestSnapshotLockVersion: 2,
      workflowLockVersion: 1,
      workflowDeletedAt: null,
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(true);
      expect(result.current.tooltipMessage).toBe(
        "You cannot edit or run an old snapshot of a workflow"
      );
    });
  });

  test("returns not read-only when viewing latest snapshot", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      latestSnapshotLockVersion: 1,
      workflowLockVersion: 1,
      workflowDeletedAt: null,
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(false);
      expect(result.current.tooltipMessage).toBe("");
    });
  });
});

// =============================================================================
// VALID EDITING SCENARIO TESTS
// =============================================================================

describe("useWorkflowReadOnly - Valid Editing", () => {
  test("returns not read-only for valid editing scenario", async () => {
    const [wrapper, { emitSessionContext }] = createWrapper({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      latestSnapshotLockVersion: 1,
      workflowLockVersion: 1,
      workflowDeletedAt: null,
    });

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(false);
      expect(result.current.tooltipMessage).toBe("");
    });
  });
});

// =============================================================================
// EDGE CASES AND NULL HANDLING
// =============================================================================

describe("useWorkflowReadOnly - Edge Cases", () => {
  test("handles null workflow gracefully", async () => {
    const sessionContextStore = createSessionContextStore();
    const workflowStore = createWorkflowStore();

    // Don't connect workflow store to Y.Doc (workflow will be null)
    const mockChannel = createMockPhoenixChannel("test:room");
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    sessionContextStore._connectChannel(mockProvider as any);

    const mockStoreValue: StoreContextValue = {
      sessionContextStore,
      workflowStore,
      adaptorStore: {} as any,
      credentialStore: {} as any,
      awarenessStore: {} as any,
      uiStore: {} as any,
    };

    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    );

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    act(() => {
      (mockChannel as any)._test.emit(
        "session_context",
        createSessionContext({
          user: null,
          project: null,
          permissions: mockPermissions,
        })
      );
    });

    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(false);
      expect(result.current.tooltipMessage).toBe("");
    });
  });

  test("handles null permissions gracefully (loading state - not read-only)", async () => {
    const sessionContextStore = createSessionContextStore();
    const workflowStore = createWorkflowStore();

    const ydoc = new Y.Doc() as Session.WorkflowDoc;
    const workflowMap = ydoc.getMap("workflow");
    workflowMap.set("id", "test-workflow-123");
    workflowMap.set("name", "Test Workflow");
    workflowMap.set("lock_version", 1);
    workflowMap.set("deleted_at", null);

    ydoc.getArray("jobs");
    ydoc.getArray("triggers");
    ydoc.getArray("edges");
    ydoc.getMap("positions");

    const mockChannel = createMockPhoenixChannel("test:room");
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    (mockProvider as any).doc = ydoc;
    workflowStore.connect(ydoc, mockProvider as any);
    sessionContextStore._connectChannel(mockProvider as any);

    const mockStoreValue: StoreContextValue = {
      sessionContextStore,
      workflowStore,
      adaptorStore: {} as any,
      credentialStore: {} as any,
      awarenessStore: {} as any,
      uiStore: {} as any,
    };

    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    );

    const { result } = renderHook(() => useWorkflowReadOnly(), { wrapper });

    // Emit session context with null permissions (loading state)
    act(() => {
      (mockChannel as any)._test.emit(
        "session_context",
        createSessionContext({
          user: null,
          project: null,
          permissions: null as any, // Testing loading state with null permissions
        })
      );
    });

    // During loading (null permissions), should not show as read-only
    // This prevents flickering on initial load
    await waitFor(() => {
      expect(result.current.isReadOnly).toBe(false);
      expect(result.current.tooltipMessage).toBe("");
    });
  });
});

// =============================================================================
// PRIORITY ORDER TESTS
// =============================================================================

describe("useWorkflowReadOnly - Priority Order", () => {
  test("verifies complete priority order: deleted > permissions > snapshot", async () => {
    // Test 1: All three conditions apply - deleted takes priority
    const [wrapper1, { emitSessionContext: emit1 }] = createWrapper({
      permissions: { can_edit_workflow: false, can_run_workflow: false },
      latestSnapshotLockVersion: 2,
      workflowLockVersion: 1,
      workflowDeletedAt: new Date().toISOString(),
    });

    const { result: result1 } = renderHook(() => useWorkflowReadOnly(), {
      wrapper: wrapper1,
    });

    act(() => {
      emit1();
    });

    await waitFor(() => {
      expect(result1.current.tooltipMessage).toBe(
        "This workflow has been deleted and cannot be edited"
      );
    });

    // Test 2: Permission and snapshot conditions apply - permission takes priority
    const [wrapper2, { emitSessionContext: emit2 }] = createWrapper({
      permissions: { can_edit_workflow: false, can_run_workflow: false },
      latestSnapshotLockVersion: 2,
      workflowLockVersion: 1,
      workflowDeletedAt: null,
    });

    const { result: result2 } = renderHook(() => useWorkflowReadOnly(), {
      wrapper: wrapper2,
    });

    act(() => {
      emit2();
    });

    await waitFor(() => {
      expect(result2.current.tooltipMessage).toBe(
        "You do not have permission to edit this workflow"
      );
    });

    // Test 3: Only snapshot condition applies
    const [wrapper3, { emitSessionContext: emit3 }] = createWrapper({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      latestSnapshotLockVersion: 2,
      workflowLockVersion: 1,
      workflowDeletedAt: null,
    });

    const { result: result3 } = renderHook(() => useWorkflowReadOnly(), {
      wrapper: wrapper3,
    });

    act(() => {
      emit3();
    });

    await waitFor(() => {
      expect(result3.current.tooltipMessage).toBe(
        "You cannot edit or run an old snapshot of a workflow"
      );
    });
  });
});
