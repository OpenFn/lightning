/**
 * EdgeInspector Component Tests - Footer Button States
 *
 * Tests for EdgeInspector footer visibility and button states in read-only mode.
 */

import { render, screen } from '@testing-library/react';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import type * as Y from 'yjs';

import { EdgeInspector } from '../../../../js/collaborative-editor/components/inspector/EdgeInspector';
import { SessionContext } from '../../../../js/collaborative-editor/contexts/SessionProvider';
import { LiveViewActionsProvider } from '../../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionStore } from '../../../../js/collaborative-editor/stores/createSessionStore';
import type { AdaptorStoreInstance } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAdaptorStore } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import type { AwarenessStoreInstance } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import type { CredentialStoreInstance } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import { createCredentialStore } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import type { SessionContextStoreInstance } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionContextStore } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import type { WorkflowStoreInstance } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createWorkflowYDoc } from '../../__helpers__/workflowFactory';
import { createMockSocket } from '../../__helpers__/sessionStoreHelpers';

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
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(
    mockSocket,
    'test:room',
    { id: 'test-user', name: 'Test', email: 'test@example.com', color: '#000' },
    { connect: false }
  );
  const provider = sessionStore.getSnapshot().provider;
  if (provider) {
    provider.emit('sync', [true]);
    provider.emit('status', [{ status: 'connected' }]);
  }

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

describe('EdgeInspector - Footer Button States', () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with jobs and an edge
    ydoc = createWorkflowYDoc({
      jobs: {
        'job-1': {
          id: 'job-1',
          name: 'First Job',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-2': {
          id: 'job-2',
          name: 'Second Job',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-1',
          target: 'job-2',
          condition_type: 'on_job_success',
          enabled: true,
        },
      ],
    });

    // Set workflow lock_version to match session context
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('lock_version', 1);

    workflowStore = createConnectedWorkflowStore(ydoc);
    credentialStore = createCredentialStore();
    sessionContextStore = createSessionContextStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();

    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    sessionContextStore._connectChannel(mockProvider as any);

    // Set default read-only permissions in beforeEach
    // Individual tests can override by emitting a new session_context event
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: {
          can_edit_workflow: false,
          can_run_workflow: false,
          can_write_webhook_auth_method: false,
        },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
      });
    });
  });

  test('footer is rendered in read-only mode', () => {
    // beforeEach already sets read-only permissions
    const edge = workflowStore.getSnapshot().edges[0];
    const mockOnClose = vi.fn();

    render(<EdgeInspector edge={edge} onClose={mockOnClose} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Footer should be rendered with toggle and delete button
    expect(screen.getByLabelText(/enabled/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /delete/i })).toBeInTheDocument();
  });

  test('toggle and delete button are disabled in read-only mode', () => {
    // beforeEach already sets read-only permissions
    const edge = workflowStore.getSnapshot().edges[0];
    const mockOnClose = vi.fn();

    render(<EdgeInspector edge={edge} onClose={mockOnClose} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    const toggle = screen.getByLabelText(/enabled/i);
    const deleteButton = screen.getByRole('button', { name: /delete/i });

    expect(toggle).toBeDisabled();
    expect(deleteButton).toBeDisabled();
  });

  test('footer is not rendered for trigger edges', () => {
    // Create edge from trigger - source references trigger ID
    const ydocWithTriggerEdge = createWorkflowYDoc({
      triggers: {
        'trigger-1': {
          id: 'trigger-1',
          type: 'webhook',
          enabled: true,
        },
      },
      jobs: {
        'job-1': {
          id: 'job-1',
          name: 'First Job',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'trigger-1', // Reference trigger by ID - factory will set source_trigger_id
          target: 'job-1',
          condition_type: 'always',
        },
      ],
    });

    // Set lock_version
    const workflowMap = ydocWithTriggerEdge.getMap('workflow');
    workflowMap.set('lock_version', 1);

    const workflowStoreWithTriggerEdge =
      createConnectedWorkflowStore(ydocWithTriggerEdge);

    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: {
          can_edit_workflow: true,
          can_run_workflow: true,
          can_write_webhook_auth_method: true,
        },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
      });
    });

    const edge = workflowStoreWithTriggerEdge.getSnapshot().edges[0];
    const mockOnClose = vi.fn();

    render(<EdgeInspector edge={edge} onClose={mockOnClose} />, {
      wrapper: createWrapper(
        workflowStoreWithTriggerEdge,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Footer should not be rendered for trigger edges
    expect(screen.queryByLabelText(/enabled/i)).not.toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: /delete/i })
    ).not.toBeInTheDocument();
  });
});
