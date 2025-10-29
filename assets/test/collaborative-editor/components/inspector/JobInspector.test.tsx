/**
 * JobInspector Component Tests - Credential Handling
 *
 * Tests for JobInspector credential selection functionality using React Testing Library.
 * Verifies that credential fields are properly initialized, updated, and persisted to Y.Doc.
 *
 * Focus: Test credential selection behavior through user interactions and Y.Doc synchronization
 */

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type React from "react";
import { act } from "react";
import { beforeEach, describe, expect, test } from "vitest";
import type * as Y from "yjs";

import { JobInspector } from "../../../../js/collaborative-editor/components/inspector/JobInspector";
import { SessionContext } from "../../../../js/collaborative-editor/contexts/SessionProvider";
import { LiveViewActionsProvider } from "../../../../js/collaborative-editor/contexts/LiveViewActionsContext";
import type { StoreContextValue } from "../../../../js/collaborative-editor/contexts/StoreProvider";
import { StoreContext } from "../../../../js/collaborative-editor/contexts/StoreProvider";
import { createSessionStore } from "../../../../js/collaborative-editor/stores/createSessionStore";
import type { AdaptorStoreInstance } from "../../../../js/collaborative-editor/stores/createAdaptorStore";
import { createAdaptorStore } from "../../../../js/collaborative-editor/stores/createAdaptorStore";
import type { AwarenessStoreInstance } from "../../../../js/collaborative-editor/stores/createAwarenessStore";
import { createAwarenessStore } from "../../../../js/collaborative-editor/stores/createAwarenessStore";
import type { CredentialStoreInstance } from "../../../../js/collaborative-editor/stores/createCredentialStore";
import { createCredentialStore } from "../../../../js/collaborative-editor/stores/createCredentialStore";
import type { SessionContextStoreInstance } from "../../../../js/collaborative-editor/stores/createSessionContextStore";
import { createSessionContextStore } from "../../../../js/collaborative-editor/stores/createSessionContextStore";
import type { WorkflowStoreInstance } from "../../../../js/collaborative-editor/stores/createWorkflowStore";
import { createWorkflowStore } from "../../../../js/collaborative-editor/stores/createWorkflowStore";
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from "../../__helpers__/channelMocks";
import { createWorkflowYDoc } from "../../__helpers__/workflowFactory";

// Mock the useCanRun hook from useWorkflow
vi.mock("../../../../js/collaborative-editor/hooks/useWorkflow", async () => {
  const actual = await vi.importActual(
    "../../../../js/collaborative-editor/hooks/useWorkflow"
  );
  return {
    ...actual,
    useCanRun: () => ({
      canRun: true,
      tooltipMessage: "Run workflow",
    }),
  };
});

/**
 * Helper to create and connect a workflow store with Y.Doc
 */
function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const mockProvider = createMockPhoenixChannelProvider(
    createMockPhoenixChannel()
  );
  store.connect(ydoc, mockProvider as any);
  return store;
}

/**
 * Creates a React wrapper with store providers for component testing
 */
function createWrapper(
  workflowStore: WorkflowStoreInstance,
  credentialStore: CredentialStoreInstance,
  sessionContextStore: SessionContextStoreInstance,
  adaptorStore: AdaptorStoreInstance,
  awarenessStore: AwarenessStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    workflowStore,
    credentialStore,
    sessionContextStore,
    adaptorStore,
    awarenessStore,
  };

  const mockLiveViewActions = {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };

  const sessionStore = createSessionStore();

  return ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <LiveViewActionsProvider actions={mockLiveViewActions}>
        <StoreContext.Provider value={mockStoreValue}>
          {children}
        </StoreContext.Provider>
      </LiveViewActionsProvider>
    </SessionContext.Provider>
  );
}

describe("JobInspector - Credential Selection", () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with a job (credentials explicitly null)
    ydoc = createWorkflowYDoc({
      jobs: {
        "job-1": {
          id: "job-1",
          name: "Test Job",
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)",
          project_credential_id: null,
          keychain_credential_id: null,
        },
      },
    });

    // Create connected stores
    workflowStore = createConnectedWorkflowStore(ydoc);
    credentialStore = createCredentialStore();
    sessionContextStore = createSessionContextStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();

    // Mock available credentials and adaptors
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);

    // Emit adaptors from channel
    act(() => {
      (mockChannel as any)._test.emit("adaptors", {
        adaptors: [
          {
            name: "@openfn/language-common",
            latest: "2.0.0",
            versions: [{ version: "2.0.0" }, { version: "1.0.0" }],
          },
        ],
      });
    });

    // Emit credentials from channel
    act(() => {
      (mockChannel as any)._test.emit("credentials_list", {
        project_credentials: [
          {
            id: "a50e8400-e29b-41d4-a716-446655440001",
            project_credential_id: "b50e8400-e29b-41d4-a716-446655440001",
            name: "Project Cred 1",
            external_id: "ext-1",
            schema: "raw",
            owner: null,
            oauth_client_name: null,
            inserted_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
          },
          {
            id: "a50e8400-e29b-41d4-a716-446655440002",
            project_credential_id: "b50e8400-e29b-41d4-a716-446655440002",
            name: "Project Cred 2",
            external_id: "ext-2",
            schema: "oauth",
            owner: null,
            oauth_client_name: null,
            inserted_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
          },
        ],
        keychain_credentials: [
          {
            id: "c50e8400-e29b-41d4-a716-446655440001",
            name: "Keychain Cred 1",
            path: "/keychain/cred-1",
            default_credential_id: null,
            inserted_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
          },
        ],
      });
    });

    // Set permissions
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test("saves job without credential when none is selected", async () => {
    const user = userEvent.setup();
    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobInspector job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Change job name to trigger form update
    const nameInput = screen.getByLabelText(/name/i);
    await user.clear(nameInput);
    await user.type(nameInput, "Updated Job Name");

    // Verify Y.Doc has null credentials
    const jobsArray = ydoc.getArray("jobs");
    const jobMap = jobsArray.get(0) as Y.Map<unknown>;

    await waitFor(() => {
      expect(jobMap.get("name")).toBe("Updated Job Name");
      expect(jobMap.get("project_credential_id")).toBe(null);
      expect(jobMap.get("keychain_credential_id")).toBe(null);
    });
  });

  test("initializes job with null credentials in Y.Doc", () => {
    // Verify that job created by workflowFactory has null credentials in Y.Doc
    const jobsArray = ydoc.getArray("jobs");
    const jobMap = jobsArray.get(0) as Y.Map<unknown>;

    // Both credentials should be explicitly set to null (not undefined)
    expect(jobMap.get("project_credential_id")).toBe(null);
    expect(jobMap.get("keychain_credential_id")).toBe(null);
  });

  test("maintains null credentials when job name is updated", async () => {
    const user = userEvent.setup();
    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobInspector job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Update the job name
    const nameInput = screen.getByLabelText(/name/i);
    await user.clear(nameInput);
    await user.type(nameInput, "Updated Name");

    // Verify credentials remain null after update
    const jobsArray = ydoc.getArray("jobs");
    const jobMap = jobsArray.get(0) as Y.Map<unknown>;

    await waitFor(() => {
      expect(jobMap.get("name")).toBe("Updated Name");
      expect(jobMap.get("project_credential_id")).toBe(null);
      expect(jobMap.get("keychain_credential_id")).toBe(null);
    });
  });

  test("handles job with pre-existing project credential in Y.Doc", () => {
    // Create a new Y.Doc with a job that has a project credential
    const ydocWithCred = createWorkflowYDoc({
      jobs: {
        "job-1": {
          id: "job-1",
          name: "Job With Credential",
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)",
          project_credential_id: "pc-123",
          keychain_credential_id: null,
        },
      },
    });

    const jobsArray = ydocWithCred.getArray("jobs");
    const jobMap = jobsArray.get(0) as Y.Map<unknown>;

    // Verify the credential is properly set in Y.Doc
    expect(jobMap.get("project_credential_id")).toBe("pc-123");
    expect(jobMap.get("keychain_credential_id")).toBe(null);
  });

  test("handles job with pre-existing keychain credential in Y.Doc", () => {
    // Create a new Y.Doc with a job that has a keychain credential
    const ydocWithCred = createWorkflowYDoc({
      jobs: {
        "job-1": {
          id: "job-1",
          name: "Job With Keychain Credential",
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)",
          project_credential_id: null,
          keychain_credential_id: "kc-456",
        },
      },
    });

    const jobsArray = ydocWithCred.getArray("jobs");
    const jobMap = jobsArray.get(0) as Y.Map<unknown>;

    // Verify the credential is properly set in Y.Doc
    expect(jobMap.get("project_credential_id")).toBe(null);
    expect(jobMap.get("keychain_credential_id")).toBe("kc-456");
  });

  test("job initialized via createWorkflowYDoc has both credential fields as null", () => {
    // This is the core test for the bug fix: verifying that workflowFactory
    // properly initializes credential fields to null (not undefined)
    const testYdoc = createWorkflowYDoc({
      jobs: {
        "test-job": {
          id: "test-job",
          name: "Test Job",
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)",
          // Explicitly not providing credentials - they should default to null
        },
      },
    });

    const jobsArray = testYdoc.getArray("jobs");
    const jobMap = jobsArray.get(0) as Y.Map<unknown>;

    // Both fields must be null, not undefined
    expect(jobMap.has("project_credential_id")).toBe(true);
    expect(jobMap.has("keychain_credential_id")).toBe(true);
    expect(jobMap.get("project_credential_id")).toBe(null);
    expect(jobMap.get("keychain_credential_id")).toBe(null);
  });
});
