/**
 * Header Component Integration Tests
 *
 * Tests for the Header component focusing on ReadOnlyWarning integration.
 * Since hook and component tests are comprehensive, these tests verify
 * proper integration within the Header component.
 */

import { act, render, screen, waitFor } from "@testing-library/react";
import type React from "react";
import { describe, expect, test } from "vitest";
import * as Y from "yjs";

import { Header } from "../../../js/collaborative-editor/components/Header";
import { SessionContext } from "../../../js/collaborative-editor/contexts/SessionProvider";
import type { StoreContextValue } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { StoreContext } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { createAdaptorStore } from "../../../js/collaborative-editor/stores/createAdaptorStore";
import { createAwarenessStore } from "../../../js/collaborative-editor/stores/createAwarenessStore";
import { createCredentialStore } from "../../../js/collaborative-editor/stores/createCredentialStore";
import { createSessionContextStore } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import { createSessionStore } from "../../../js/collaborative-editor/stores/createSessionStore";
import { createUIStore } from "../../../js/collaborative-editor/stores/createUIStore";
import { createWorkflowStore } from "../../../js/collaborative-editor/stores/createWorkflowStore";
import type { Session } from "../../../js/collaborative-editor/types/session";
import { createSessionContext } from "../__helpers__/sessionContextFactory";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from "../mocks/phoenixChannel";
import { createMockSocket } from "../mocks/phoenixSocket";

// =============================================================================
// TEST HELPERS
// =============================================================================

interface WrapperOptions {
  permissions?: { can_edit_workflow: boolean };
  latestSnapshotLockVersion?: number;
  workflowLockVersion?: number | null;
  workflowDeletedAt?: string | null;
  isNewWorkflow?: boolean;
}

function createTestSetup(options: WrapperOptions = {}) {
  const {
    permissions = { can_edit_workflow: true },
    latestSnapshotLockVersion = 1,
    workflowLockVersion = 1,
    workflowDeletedAt = null,
    isNewWorkflow = false,
  } = options;

  // Create all stores
  const sessionStore = createSessionStore();
  const sessionContextStore = createSessionContextStore(isNewWorkflow);
  const workflowStore = createWorkflowStore();
  const adaptorStore = createAdaptorStore();
  const awarenessStore = createAwarenessStore();
  const credentialStore = createCredentialStore();
  const uiStore = createUIStore();

  // Initialize session store
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(mockSocket, "test:room", {
    id: "user-1",
    name: "Test User",
    color: "#ff0000",
  });

  // Set up Y.Doc and workflow
  const ydoc = new Y.Doc() as Session.WorkflowDoc;
  const workflowMap = ydoc.getMap("workflow");

  if (!isNewWorkflow) {
    workflowMap.set("id", "test-workflow-123");
  }
  workflowMap.set("name", "Test Workflow");
  workflowMap.set("lock_version", workflowLockVersion);
  workflowMap.set("deleted_at", workflowDeletedAt);

  ydoc.getArray("jobs");
  ydoc.getArray("triggers");
  ydoc.getArray("edges");
  ydoc.getMap("positions");

  // Connect stores
  const mockChannel = createMockPhoenixChannel("test:room");
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  (mockProvider as any).doc = ydoc;

  workflowStore.connect(ydoc, mockProvider as any);
  sessionContextStore._connectChannel(mockProvider as any);

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
    adaptorStore,
    credentialStore,
    awarenessStore,
    uiStore,
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow }}>
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );

  return { wrapper, emitSessionContext, ydoc };
}

// =============================================================================
// HEADER INTEGRATION TESTS
// =============================================================================

describe("Header - ReadOnlyWarning Integration", () => {
  test("renders ReadOnlyWarning in correct position (after Breadcrumbs, inside header)", async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText("Read-only")).toBeInTheDocument();
    });

    // Verify ReadOnlyWarning appears inside the main header div
    const readOnlyElement = screen.getByText("Read-only").parentElement;
    const headerDiv = container.querySelector(".flex-none.bg-white");

    // Both should exist
    expect(readOnlyElement).toBeInTheDocument();
    expect(headerDiv).toBeInTheDocument();

    // ReadOnlyWarning should be inside the header div
    expect(headerDiv).toContainElement(readOnlyElement);

    // ReadOnlyWarning should come after the breadcrumbs
    const breadcrumb = screen.getByText("Breadcrumb");
    const allElements = Array.from(container.querySelectorAll("*"));
    const breadcrumbIndex = allElements.indexOf(breadcrumb);
    const readOnlyIndex = allElements.indexOf(readOnlyElement!);

    expect(readOnlyIndex).toBeGreaterThan(breadcrumbIndex);
  });

  test("shows ReadOnlyWarning when workflow is read-only", async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText("Read-only")).toBeInTheDocument();
    });
  });

  test("does not show ReadOnlyWarning when workflow is editable", async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: true },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.queryByText("Read-only")).not.toBeInTheDocument();
  });

  test("hides ReadOnlyWarning during new workflow creation", async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
      isNewWorkflow: true,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Should not show warning even with no permission when creating new workflow
    expect(screen.queryByText("Read-only")).not.toBeInTheDocument();
  });
});

// =============================================================================
// HEADER COMPONENT BASELINE TESTS
// =============================================================================

describe("Header - Basic Rendering", () => {
  test("renders breadcrumbs", async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Test Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.getByText("Test Breadcrumb")).toBeInTheDocument();
  });

  test("renders save button", async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.getByRole("button", { name: /save/i })).toBeInTheDocument();
  });

  test("renders run button when projectId and workflowId and triggers provided", async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    // Add a trigger so the Run button appears (must be a Y.Map, not plain object)
    const triggersArray = ydoc.getArray("triggers");
    const triggerMap = new Y.Map();
    triggerMap.set("id", "trigger-123");
    triggerMap.set("type", "webhook");
    triggerMap.set("enabled", true);
    triggerMap.set("cron_expression", null);
    triggerMap.set("kafka_configuration", null);
    triggersArray.push([triggerMap]);

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /run/i })).toBeInTheDocument();
    });
  });

  test("renders user menu button", async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(
      screen.getByRole("button", { name: /open user menu/i })
    ).toBeInTheDocument();
  });
});

// =============================================================================
// HEADER STATE INTERACTION TESTS
// =============================================================================

describe("Header - Read-Only State Changes", () => {
  test("ReadOnlyWarning appears when workflow becomes read-only", async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup({
      permissions: { can_edit_workflow: true },
    });

    const { rerender } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.queryByText("Read-only")).not.toBeInTheDocument();

    // Make workflow deleted
    act(() => {
      const workflowMap = ydoc.getMap("workflow");
      workflowMap.set("deleted_at", new Date().toISOString());
    });

    rerender(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>
    );

    await waitFor(() => {
      expect(screen.getByText("Read-only")).toBeInTheDocument();
    });
  });

  test("ReadOnlyWarning disappears when workflow becomes editable", async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup({
      permissions: { can_edit_workflow: true },
      workflowDeletedAt: new Date().toISOString(),
    });

    const { rerender } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText("Read-only")).toBeInTheDocument();
    });

    // Make workflow not deleted
    act(() => {
      const workflowMap = ydoc.getMap("workflow");
      workflowMap.set("deleted_at", null);
    });

    rerender(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>
    );

    await waitFor(() => {
      expect(screen.queryByText("Read-only")).not.toBeInTheDocument();
    });
  });
});
