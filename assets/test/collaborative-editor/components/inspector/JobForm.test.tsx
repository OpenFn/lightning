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

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { KeyboardProvider } from '#/collaborative-editor/keyboard';
import { JobForm } from '../../../../js/collaborative-editor/components/inspector/JobForm';
import { CredentialModalProvider } from '../../../../js/collaborative-editor/contexts/CredentialModalContext';
import { LiveViewActionsProvider } from '../../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { SessionContext } from '../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { AdaptorStoreInstance } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAdaptorStore } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import type { AwarenessStoreInstance } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import type { CredentialStoreInstance } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import { createCredentialStore } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import type { SessionContextStoreInstance } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionContextStore } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../js/collaborative-editor/stores/createSessionStore';
import type { WorkflowStoreInstance } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createWorkflowYDoc } from '../../__helpers__/workflowFactory';

// Mock useAdaptorIcons to avoid fetching icon manifest
vi.mock('#/workflow-diagram/useAdaptorIcons', () => ({
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
  const sessionStore = createSessionStore();

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

  const mockSessionValue = {
    sessionStore,
    isNewWorkflow: false,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <KeyboardProvider>
      <SessionContext.Provider value={mockSessionValue}>
        <LiveViewActionsProvider actions={mockLiveViewActions}>
          <CredentialModalProvider>
            <StoreContext.Provider value={mockStoreValue}>
              {children}
            </StoreContext.Provider>
          </CredentialModalProvider>
        </LiveViewActionsProvider>
      </SessionContext.Provider>
    </KeyboardProvider>
  );
}

describe('JobForm - Adaptor Display Section', () => {
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
        'job-1': {
          id: 'job-1',
          name: 'Test Job',
          adaptor: '@openfn/language-http@1.0.0',
          body: 'fn(state => state)',
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
      (mockChannel as any)._test.emit('adaptors', {
        adaptors: [
          {
            name: '@openfn/language-http',
            latest: '1.0.0',
            versions: [{ version: '1.0.0' }, { version: '0.9.0' }],
          },
          {
            name: '@openfn/language-salesforce',
            latest: '2.0.0',
            versions: [{ version: '2.0.0' }, { version: '1.0.0' }],
          },
          {
            name: '@openfn/language-common',
            latest: '2.0.0',
            versions: [{ version: '2.0.0' }],
          },
        ],
      });
    });

    // Emit credentials from channel
    act(() => {
      (mockChannel as any)._test.emit('credentials_list', {
        project_credentials: [],
        keychain_credentials: [],
      });
    });

    // Set permissions
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
      });
    });
  });

  test('displays adaptor information with icon (Phase 2R: simplified)', async () => {
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
    expect(screen.getByText('Adaptor')).toBeInTheDocument();

    // Check display name is shown (Http instead of @openfn/language-http)
    await waitFor(() => {
      expect(screen.getByText('Http')).toBeInTheDocument();
    });

    // Phase 2R: Version is NO LONGER displayed in inspector
    // Version selection moved to ConfigureAdaptorModal (Phase 3R)

    // Check "Connect" button exists (no credential set yet)
    const connectButton = screen.getByRole('button', {
      name: /connect credential/i,
    });
    expect(connectButton).toBeInTheDocument();
    expect(connectButton).toHaveTextContent('Connect');
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

    // Click "Connect" button to open ConfigureAdaptorModal
    const connectButton = screen.getByRole('button', {
      name: /connect credential/i,
    });
    await user.click(connectButton);

    // Phase 3R: ConfigureAdaptorModal should open (not AdaptorSelectionModal)
    await waitFor(
      () => {
        expect(screen.getByText('Configure connection')).toBeInTheDocument();
      },
      { timeout: 3000 }
    );
  });

  test('ConfigureAdaptorModal closes when Escape pressed (Phase 3R)', async () => {
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
    expect(screen.getByText('Http')).toBeInTheDocument();

    // Open modal with "Connect" button
    const connectButton = screen.getByRole('button', {
      name: /connect credential/i,
    });
    await user.click(connectButton);

    // ConfigureAdaptorModal should open
    await waitFor(
      () => {
        expect(screen.getByText('Configure connection')).toBeInTheDocument();
      },
      { timeout: 3000 }
    );

    // Close modal by pressing Escape
    await user.keyboard('{Escape}');

    // Modal should close
    await waitFor(
      () => {
        expect(
          screen.queryByText('Configure connection')
        ).not.toBeInTheDocument();
      },
      { timeout: 3000 }
    );
  });

  test('displays correct adaptor name for different adaptors', async () => {
    // Create job with salesforce adaptor
    const ydocWithSalesforce = createWorkflowYDoc({
      jobs: {
        'job-1': {
          id: 'job-1',
          name: 'Salesforce Job',
          adaptor: '@openfn/language-salesforce@latest',
          body: 'fn(state => state)',
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
      expect(screen.getByText('Salesforce')).toBeInTheDocument();
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
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
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

describe('JobForm - Complete Integration (Phase 2R: Simplified)', () => {
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
        'job-1': {
          id: 'job-1',
          name: 'Initial Name',
          adaptor: '@openfn/language-salesforce@latest',
          body: 'fn(state => state)',
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
      (mockChannel as any)._test.emit('adaptors', {
        adaptors: [
          {
            name: '@openfn/language-http',
            latest: '1.0.0',
            versions: [{ version: '1.0.0' }],
          },
          {
            name: '@openfn/language-salesforce',
            latest: '2.0.0',
            versions: [{ version: '2.0.0' }, { version: '1.0.0' }],
          },
        ],
      });
    });

    // Emit permissions
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
      });
    });
  });

  test('handles job name update and ConfigureAdaptorModal flow (Phase 3R)', async () => {
    const user = userEvent.setup();

    // Emit empty credentials (credential selection in ConfigureAdaptorModal)
    act(() => {
      (mockChannel as any)._test.emit('credentials_list', {
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
    expect(screen.getByDisplayValue('Initial Name')).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByText('Salesforce')).toBeInTheDocument();
    });

    // 2. Change job name
    const nameInput = screen.getByLabelText('Job Name');
    await user.clear(nameInput);
    await user.type(nameInput, 'Updated Name');

    await waitFor(() => {
      const updatedJob = workflowStore.getSnapshot().jobs[0];
      expect(updatedJob.name).toBe('Updated Name');
    });

    // 3. Verify "Connect" button opens ConfigureAdaptorModal (Phase 3R)
    const connectButton = screen.getByRole('button', {
      name: /connect credential/i,
    });
    await user.click(connectButton);

    // Wait for ConfigureAdaptorModal to open
    await waitFor(
      () => {
        expect(screen.getByText('Configure connection')).toBeInTheDocument();
      },
      { timeout: 3000 }
    );

    // Close modal with Escape key
    await user.keyboard('{Escape}');

    // Wait for modal to close
    await waitFor(
      () => {
        expect(
          screen.queryByText('Configure connection')
        ).not.toBeInTheDocument();
      },
      { timeout: 3000 }
    );

    // Phase 3R: Credential selection handled in ConfigureAdaptorModal

    // 4. Verify job name changed in store
    await waitFor(() => {
      const finalJob = workflowStore.getSnapshot().jobs[0];
      expect(finalJob.name).toBe('Updated Name');
    });

    // Verify adaptor didn't change (since we canceled modal)
    const finalJob = workflowStore.getSnapshot().jobs[0];
    expect(finalJob.adaptor).toContain('salesforce');
  });
});

describe('JobForm - Collaborative Validation (Phase 5)', () => {
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
        'job-1': {
          id: 'job-1',
          name: 'Test Job',
          adaptor: '@openfn/language-http@1.0.0',
          body: 'fn(state => state)',
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
      (mockChannel as any)._test.emit('adaptors', {
        adaptors: [
          {
            name: '@openfn/language-http',
            latest: '1.0.0',
            versions: [{ version: '1.0.0' }],
          },
        ],
      });
    });

    // Emit credentials
    act(() => {
      (mockChannel as any)._test.emit('credentials_list', {
        project_credentials: [],
        keychain_credentials: [],
      });
    });

    // Emit permissions
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
      });
    });
  });

  test('displays server validation errors from Y.Doc', async () => {
    // Add server validation errors to Y.Doc
    const errorsMap = ydoc.getMap('errors');
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-1': {
            name: ['Job name is too long (max 100 characters)'],
          },
        });
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

    // Verify error is displayed in form
    await waitFor(() => {
      expect(screen.getByText(/Job name is too long/)).toBeInTheDocument();
    });
  });

  test('displays multiple validation errors for different fields', async () => {
    // Add multiple errors to Y.Doc
    // Note: JobForm only renders the name field, not body
    const errorsMap = ydoc.getMap('errors');
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-1': {
            name: ['Job name is required'],
            adaptor: ['Adaptor is invalid'],
          },
        });
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

    // Both errors should be displayed (name visible, adaptor handled by form)
    await waitFor(() => {
      expect(screen.getByText(/Job name is required/)).toBeInTheDocument();
    });
    // Note: adaptor error won't be visible in current JobForm UI since
    // adaptor is selected via modal, not a direct form field
  });

  test('preserves errors when reopening inspector', async () => {
    // Add validation errors
    const errorsMap = ydoc.getMap('errors');
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-1': {
            name: ['Invalid job name'],
          },
        });
      });
    });

    const job = workflowStore.getSnapshot().jobs[0];

    // Render, unmount, and re-render
    const { unmount } = render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Verify error is shown initially
    await waitFor(() => {
      expect(screen.getByText(/Invalid job name/)).toBeInTheDocument();
    });

    // Unmount (simulate closing inspector)
    unmount();

    // Re-render (simulate reopening inspector)
    render(<JobForm job={job} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Error should still be visible after remount
    await waitFor(() => {
      expect(screen.getByText(/Invalid job name/)).toBeInTheDocument();
    });
  });

  test('clears errors when removed from Y.Doc', async () => {
    // Start with errors
    const errorsMap = ydoc.getMap('errors');
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-1': {
            name: ['Job name is invalid'],
          },
        });
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

    // Verify error is shown
    await waitFor(() => {
      expect(screen.getByText(/Job name is invalid/)).toBeInTheDocument();
    });

    // Clear errors from Y.Doc
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('jobs', {});
      });
    });

    // Error should disappear
    await waitFor(() => {
      expect(screen.queryByText(/Job name is invalid/)).not.toBeInTheDocument();
    });
  });

  test('handles errors for specific job only (not other jobs)', async () => {
    // Create a second Y.Doc with two jobs to test isolation
    const ydocWithTwoJobs = createWorkflowYDoc({
      jobs: {
        'job-1': {
          id: 'job-1',
          name: 'First Job',
          adaptor: '@openfn/language-http@1.0.0',
          body: 'fn(state => state)',
          project_credential_id: null,
          keychain_credential_id: null,
        },
        'job-2': {
          id: 'job-2',
          name: 'Second Job',
          adaptor: '@openfn/language-http@1.0.0',
          body: 'fn(state => state)',
          project_credential_id: null,
          keychain_credential_id: null,
        },
      },
    });

    const twoJobsStore = createConnectedWorkflowStore(ydocWithTwoJobs);

    // Add errors only for job-2
    const errorsMap = ydocWithTwoJobs.getMap('errors');
    act(() => {
      ydocWithTwoJobs.transact(() => {
        errorsMap.set('jobs', {
          'job-2': {
            name: ['Error on job 2'],
          },
        });
      });
    });

    // Render form for job-1
    const job1 = twoJobsStore.getSnapshot().jobs.find(j => j.id === 'job-1');

    render(<JobForm job={job1!} />, {
      wrapper: createWrapper(
        twoJobsStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // job-1 form should NOT show job-2's error
    await waitFor(() => {
      expect(screen.queryByText(/Error on job 2/)).not.toBeInTheDocument();
    });
  });

  test('displays first error when field has multiple errors', async () => {
    // Add multiple errors for same field
    const errorsMap = ydoc.getMap('errors');
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-1': {
            name: [
              'First error message',
              'Second error message',
              'Third error message',
            ],
          },
        });
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

    // Should display first error only
    await waitFor(() => {
      expect(screen.getByText(/First error message/)).toBeInTheDocument();
      expect(
        screen.queryByText(/Second error message/)
      ).not.toBeInTheDocument();
      expect(screen.queryByText(/Third error message/)).not.toBeInTheDocument();
    });
  });

  test('form values reset when switching between different jobs', async () => {
    // This test verifies that TanStack Form properly re-initializes when
    // the job prop changes, preventing form values from "sticking" between jobs.
    // This is critical for collaborative editing where users frequently switch
    // between inspecting different jobs.

    // Create Y.Doc with two jobs with distinctly different values
    const ydocWithTwoJobs = createWorkflowYDoc({
      jobs: {
        'job-1': {
          id: 'job-1',
          name: 'First Job Name',
          adaptor: '@openfn/language-http@1.0.0',
          body: 'fn(state => state)',
          project_credential_id: null,
          keychain_credential_id: null,
        },
        'job-2': {
          id: 'job-2',
          name: 'Second Job Name',
          adaptor: '@openfn/language-salesforce@2.0.0',
          body: 'fn(state => state)',
          project_credential_id: null,
          keychain_credential_id: null,
        },
      },
    });

    const twoJobsStore = createConnectedWorkflowStore(ydocWithTwoJobs);

    // Get both jobs
    const job1 = twoJobsStore.getSnapshot().jobs.find(j => j.id === 'job-1');
    const job2 = twoJobsStore.getSnapshot().jobs.find(j => j.id === 'job-2');

    // Render form for job-1
    const { rerender } = render(<JobForm job={job1!} />, {
      wrapper: createWrapper(
        twoJobsStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Verify job-1 values are displayed initially
    await waitFor(() => {
      expect(screen.getByDisplayValue('First Job Name')).toBeInTheDocument();
      expect(screen.getByText('Http')).toBeInTheDocument();
    });

    // Now switch to job-2 (this simulates user clicking on a different job in the canvas)
    rerender(<JobForm job={job2!} />);

    // CRITICAL: Verify job-2 values are displayed (not job-1's values)
    // This is what we're testing - that form values don't "stick" when switching jobs
    await waitFor(() => {
      expect(screen.getByDisplayValue('Second Job Name')).toBeInTheDocument();
      // Verify job-1's name is NOT shown
      expect(
        screen.queryByDisplayValue('First Job Name')
      ).not.toBeInTheDocument();
    });

    // Verify adaptor changed too
    await waitFor(() => {
      expect(screen.getByText('Salesforce')).toBeInTheDocument();
      // Verify job-1's adaptor is NOT shown
      expect(screen.queryByText('Http')).not.toBeInTheDocument();
    });

    // Switch back to job-1 to verify bidirectional switching works
    rerender(<JobForm job={job1!} />);

    // Verify job-1 values are correctly restored
    await waitFor(() => {
      expect(screen.getByDisplayValue('First Job Name')).toBeInTheDocument();
      expect(screen.getByText('Http')).toBeInTheDocument();
      // Verify job-2's values are NOT shown
      expect(
        screen.queryByDisplayValue('Second Job Name')
      ).not.toBeInTheDocument();
      expect(screen.queryByText('Salesforce')).not.toBeInTheDocument();
    });
  });
});
