/**
 * JobForm Component Tests - Simplified Inspector (Phase 2R)
 *
 * Tests for JobForm with simplified adaptor display:
 * - Job name field
 * - Adaptor icon + name + "Connect" button
 * - Modal integration
 *
 * Phase 3R will add ConfigureAdaptorModal tests for version/credential selection.
 */

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type React from "react";
import { act } from "react";
import { beforeEach, describe, expect, test, vi } from "vitest";
import type * as Y from "yjs";

import { JobForm } from "../../../../js/collaborative-editor/components/inspector/JobForm";
import type { StoreContextValue } from "../../../../js/collaborative-editor/contexts/StoreProvider";
import { StoreContext } from "../../../../js/collaborative-editor/contexts/StoreProvider";
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
import { HotkeysProvider } from "react-hotkeys-hook";

// Mock useAdaptorIcons to avoid fetching icon manifest
vi.mock("#/workflow-diagram/useAdaptorIcons", () => ({
  default: () => null,
}));

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

  return ({ children }: { children: React.ReactNode }) => (
    <HotkeysProvider>
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    </HotkeysProvider>
  );
}

describe("JobForm - Adaptor Display Section", () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with a job using HTTP adaptor
    ydoc = createWorkflowYDoc({
      jobs: {
        "job-1": {
          id: "job-1",
          name: "Test Job",
          adaptor: "@openfn/language-http@1.0.0",
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
            name: "@openfn/language-http",
            latest: "1.0.0",
            versions: [{ version: "1.0.0" }, { version: "0.9.0" }],
          },
          {
            name: "@openfn/language-salesforce",
            latest: "2.0.0",
            versions: [{ version: "2.0.0" }, { version: "1.0.0" }],
          },
          {
            name: "@openfn/language-common",
            latest: "2.0.0",
            versions: [{ version: "2.0.0" }],
          },
        ],
      });
    });

    // Emit credentials from channel
    act(() => {
      (mockChannel as any)._test.emit("credentials_list", {
        project_credentials: [],
        keychain_credentials: [],
      });
    });

    // Set permissions
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test("displays adaptor information with icon (Phase 2R: simplified)", async () => {
    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Check adaptor display section exists
    expect(screen.getByText("Adaptor")).toBeInTheDocument();

    // Check display name is shown (Http instead of @openfn/language-http)
    await waitFor(() => {
      expect(screen.getByText("Http")).toBeInTheDocument();
    });

    // Phase 2R: Version is NO LONGER displayed in inspector
    // Version selection moved to ConfigureAdaptorModal (Phase 3R)

    // Check "Connect" button exists (changed from "Change" in Phase 2R)
    // Note: aria-label is "Configure adaptor" but button text is "Connect"
    const connectButton = screen.getByRole("button", { name: /configure/i });
    expect(connectButton).toBeInTheDocument();
    expect(connectButton).toHaveTextContent("Connect");
  });

  test("opens ConfigureAdaptorModal when 'Connect' clicked (Phase 3R)", async () => {
    const user = userEvent.setup();
    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Click "Connect" button (changed from "Change" in Phase 2R)
    const connectButton = screen.getByRole("button", { name: /configure/i });
    await user.click(connectButton);

    // Phase 3R: ConfigureAdaptorModal should open (not AdaptorSelectionModal)
    await waitFor(
      () => {
        expect(screen.getByText("Configure Your Adaptor")).toBeInTheDocument();
      },
      { timeout: 3000 }
    );
  });

  test("ConfigureAdaptorModal closes when Escape pressed (Phase 3R)", async () => {
    const user = userEvent.setup();
    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Verify initial adaptor
    expect(screen.getByText("Http")).toBeInTheDocument();

    // Open modal with "Connect" button
    const connectButton = screen.getByRole("button", { name: /configure/i });
    await user.click(connectButton);

    // ConfigureAdaptorModal should open
    await waitFor(
      () => {
        expect(screen.getByText("Configure Your Adaptor")).toBeInTheDocument();
      },
      { timeout: 3000 }
    );

    // Close modal by pressing Escape
    await user.keyboard("{Escape}");

    // Modal should close
    await waitFor(
      () => {
        expect(
          screen.queryByText("Configure Your Adaptor")
        ).not.toBeInTheDocument();
      },
      { timeout: 3000 }
    );
  });

  test("displays correct adaptor name for different adaptors", async () => {
    // Create job with salesforce adaptor
    const ydocWithSalesforce = createWorkflowYDoc({
      jobs: {
        "job-1": {
          id: "job-1",
          name: "Salesforce Job",
          adaptor: "@openfn/language-salesforce@latest",
          body: "fn(state => state)",
        },
      },
    });

    const sfStore = createConnectedWorkflowStore(ydocWithSalesforce);

    const job = sfStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        sfStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Should display "Salesforce" not "@openfn/language-salesforce"
    await waitFor(() => {
      expect(screen.getByText("Salesforce")).toBeInTheDocument();
    });
  });

  // REMOVED (Phase 2R): Version dropdown no longer in inspector
  // Version selection moved to ConfigureAdaptorModal (Phase 3R)
  // test("version dropdown is rendered", async () => { ... });
});

// COMMENTED OUT (Phase 2R): Credential display removed from inspector
// Credential selection moved to ConfigureAdaptorModal (Phase 3R)
/*

describe("JobForm - Credential Display", () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with a job
    ydoc = createWorkflowYDoc({
      jobs: {
        "job-1": {
          id: "job-1",
          name: "Test Job",
          adaptor: "@openfn/language-http@1.0.0",
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

    // Mock channels
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);

    // Emit adaptors
    act(() => {
      (mockChannel as any)._test.emit("adaptors", {
        adaptors: [
          {
            name: "@openfn/language-http",
            latest: "1.0.0",
            versions: [{ version: "1.0.0" }],
          },
        ],
      });
    });

    // Emit permissions
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test("shows connected state when credential is selected", async () => {
    const credId = "a1b2c3d4-e5f6-4000-8000-000000000001";
    const projectCredId = "b2c3d4e5-f6a7-4000-8000-000000000002";

    // Emit credentials with matching ID
    act(() => {
      (mockChannel as any)._test.emit("credentials_list", {
        project_credentials: [
          {
            id: credId,
            project_credential_id: projectCredId,
            name: "My Salesforce Cred",
            schema: "salesforce",
            external_id: "ext-1",
            inserted_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
          },
        ],
        keychain_credentials: [],
      });
    });

    // Update job with a credential using the store action
    act(() => {
      workflowStore.updateJob("job-1", {
        project_credential_id: projectCredId,
      });
    });

    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Check connected state is shown
    await waitFor(() => {
      expect(screen.getByText(/Connected:/)).toBeInTheDocument();
    });

    expect(screen.getByText("My Salesforce Cred")).toBeInTheDocument();
    expect(screen.getByText(/Project credential/)).toBeInTheDocument();
    expect(screen.getByText(/salesforce/)).toBeInTheDocument();
  });

  test("shows no connected state when no credential selected", () => {
    // Emit empty credentials list
    act(() => {
      (mockChannel as any)._test.emit("credentials_list", {
        project_credentials: [],
        keychain_credentials: [],
      });
    });

    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // No connected state
    expect(screen.queryByText(/Connected:/)).not.toBeInTheDocument();

    // Dropdown shows "Select credential" label
    expect(screen.getByText("Select credential")).toBeInTheDocument();
  });

  test("changes label to 'Change credential' when credential is selected", async () => {
    const credId = "c1d2e3f4-a5b6-4000-8000-000000000003";
    const projectCredId = "d2e3f4a5-b6c7-4000-8000-000000000004";

    // Emit credentials with matching ID
    act(() => {
      (mockChannel as any)._test.emit("credentials_list", {
        project_credentials: [
          {
            id: credId,
            project_credential_id: projectCredId,
            name: "My Cred",
            schema: "raw",
            external_id: "ext-1",
            inserted_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
          },
        ],
        keychain_credentials: [],
      });
    });

    // Update job with a credential using the store action
    act(() => {
      workflowStore.updateJob("job-1", {
        project_credential_id: projectCredId,
      });
    });

    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Wait for connected state to render
    await waitFor(() => {
      expect(screen.getByText(/Connected:/)).toBeInTheDocument();
    });

    // Check label is "Change credential"
    expect(screen.getByText("Change credential")).toBeInTheDocument();
  });
});

*/

describe("JobForm - Complete Integration (Phase 2R: Simplified)", () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with a job
    ydoc = createWorkflowYDoc({
      jobs: {
        "job-1": {
          id: "job-1",
          name: "Initial Name",
          adaptor: "@openfn/language-salesforce@latest",
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

    // Mock channels
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);

    // Emit adaptors
    act(() => {
      (mockChannel as any)._test.emit("adaptors", {
        adaptors: [
          {
            name: "@openfn/language-http",
            latest: "1.0.0",
            versions: [{ version: "1.0.0" }],
          },
          {
            name: "@openfn/language-salesforce",
            latest: "2.0.0",
            versions: [{ version: "2.0.0" }, { version: "1.0.0" }],
          },
        ],
      });
    });

    // Emit permissions
    act(() => {
      (mockChannel as any)._test.emit("session_context", {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test("handles job name update and ConfigureAdaptorModal flow (Phase 3R)", async () => {
    const user = userEvent.setup();

    // Emit empty credentials (credential selection in ConfigureAdaptorModal)
    act(() => {
      (mockChannel as any)._test.emit("credentials_list", {
        project_credentials: [],
        keychain_credentials: [],
      });
    });

    const job = workflowStore.getSnapshot().jobs[0];

    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // 1. Verify initial state - Job Name field label updated in Phase 2R
    expect(screen.getByDisplayValue("Initial Name")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByText("Salesforce")).toBeInTheDocument();
    });

    // 2. Change job name
    const nameInput = screen.getByLabelText("Job Name");
    await user.clear(nameInput);
    await user.type(nameInput, "Updated Name");

    await waitFor(() => {
      const updatedJob = workflowStore.getSnapshot().jobs[0];
      expect(updatedJob.name).toBe("Updated Name");
    });

    // 3. Verify "Connect" button opens ConfigureAdaptorModal (Phase 3R)
    const connectButton = screen.getByRole("button", { name: /configure/i });
    await user.click(connectButton);

    // Wait for ConfigureAdaptorModal to open
    await waitFor(
      () => {
        expect(screen.getByText("Configure Your Adaptor")).toBeInTheDocument();
      },
      { timeout: 3000 }
    );

    // Close modal with Escape key
    await user.keyboard("{Escape}");

    // Wait for modal to close
    await waitFor(
      () => {
        expect(
          screen.queryByText("Configure Your Adaptor")
        ).not.toBeInTheDocument();
      },
      { timeout: 3000 }
    );

    // Phase 3R: Credential selection handled in ConfigureAdaptorModal

    // 4. Verify job name changed in store
    await waitFor(() => {
      const finalJob = workflowStore.getSnapshot().jobs[0];
      expect(finalJob.name).toBe("Updated Name");
    });

    // Verify adaptor didn't change (since we canceled modal)
    const finalJob = workflowStore.getSnapshot().jobs[0];
    expect(finalJob.adaptor).toContain("salesforce");
  });
});
