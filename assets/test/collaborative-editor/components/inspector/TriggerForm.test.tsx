/**
 * TriggerForm Component Tests - Response Mode Field
 *
 * Tests for the webhook_reply (Response Mode) field in TriggerForm.
 */

import { render, screen, waitFor } from '@testing-library/react';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import * as Y from 'yjs';

import { TriggerForm } from '../../../../js/collaborative-editor/components/inspector/TriggerForm';
import { SessionContext } from '../../../../js/collaborative-editor/contexts/SessionProvider';
import { LiveViewActionsProvider } from '../../../../js/collaborative-editor/contexts/LiveViewActionsContext';
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
import type { Session } from '../../../../js/collaborative-editor/types/session';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createMockSocket } from '../../__helpers__/sessionStoreHelpers';

/**
 * Creates a Y.Doc with a webhook trigger including webhook_reply field
 */
function createWebhookTriggerYDoc(
  webhookReply: 'before_start' | 'after_completion' = 'before_start'
): Y.Doc {
  const ydoc = new Y.Doc();

  const triggersArray = ydoc.getArray('triggers');
  const triggerMap = new Y.Map();
  triggerMap.set('id', 'trigger-1');
  triggerMap.set('type', 'webhook');
  triggerMap.set('enabled', true);
  triggerMap.set('webhook_reply', webhookReply);
  triggersArray.push([triggerMap]);

  return ydoc;
}

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

describe('TriggerForm - Response Mode Field', () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    ydoc = createWebhookTriggerYDoc('before_start');

    workflowStore = createConnectedWorkflowStore(ydoc);
    credentialStore = createCredentialStore();
    sessionContextStore = createSessionContextStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();

    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);
    sessionContextStore._connectChannel(mockProvider as any);

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
        has_read_ai_disclaimer: true,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
      });
    });
  });

  test('renders Response Mode field for webhook triggers', async () => {
    const trigger = workflowStore.getSnapshot().triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await waitFor(() => {
      expect(screen.getByLabelText('Response Mode')).toBeInTheDocument();
    });
  });

  test('displays Async and Sync options', async () => {
    const trigger = workflowStore.getSnapshot().triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await screen.findByLabelText('Response Mode');

    // Check both options exist (use exact text to avoid "Async" matching "sync")
    expect(
      screen.getByRole('option', { name: 'Async (default)' })
    ).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Sync' })).toBeInTheDocument();
  });

  test('shows Async as default selected value', async () => {
    const trigger = workflowStore.getSnapshot().triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await waitFor(() => {
      const select = screen.getByLabelText(
        'Response Mode'
      ) as HTMLSelectElement;
      expect(select.value).toBe('before_start');
    });
  });

  test('shows async help text when Async is selected', async () => {
    const trigger = workflowStore.getSnapshot().triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await waitFor(() => {
      expect(
        screen.getByText(
          /responds immediately with the enqueued work order id/i
        )
      ).toBeInTheDocument();
    });
  });

  test('shows sync help text when Sync is selected', async () => {
    // Create Y.Doc with after_completion value
    const syncYdoc = createWebhookTriggerYDoc('after_completion');
    const syncWorkflowStore = createConnectedWorkflowStore(syncYdoc);

    const trigger = syncWorkflowStore.getSnapshot()
      .triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(
        syncWorkflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await waitFor(() => {
      expect(
        screen.getByText(
          /responds with the final output state after the run completes/i
        )
      ).toBeInTheDocument();
    });
  });

  test('does not render Response Mode for cron triggers', async () => {
    // Create a cron trigger Y.Doc
    const cronYdoc = new Y.Doc();
    const triggersArray = cronYdoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-1');
    triggerMap.set('type', 'cron');
    triggerMap.set('enabled', true);
    triggerMap.set('cron_expression', '0 0 * * *');
    triggersArray.push([triggerMap]);

    const cronWorkflowStore = createConnectedWorkflowStore(cronYdoc);
    const trigger = cronWorkflowStore.getSnapshot()
      .triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(
        cronWorkflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Wait for form to render
    await waitFor(() => {
      expect(screen.getByLabelText('Trigger Type')).toBeInTheDocument();
    });

    // Response Mode should NOT be present for cron triggers
    expect(screen.queryByLabelText('Response Mode')).not.toBeInTheDocument();
  });
});
