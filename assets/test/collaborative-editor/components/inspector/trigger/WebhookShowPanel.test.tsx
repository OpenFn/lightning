/**
 * WebhookShowPanel Component Tests
 *
 * Covers the read-only webhook "show" panel (#4797): the webhook URL, the
 * auth-methods list vs the "No auth configured" placeholder, the
 * "Add Authentication" affordance gating, and the Edit button permission
 * gating.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { WebhookShowPanel } from '../../../../../js/collaborative-editor/components/inspector/trigger/WebhookShowPanel';
import { SessionContext } from '../../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import type { SessionContextStoreInstance } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WebhookAuthMethod } from '../../../../../js/collaborative-editor/types/sessionContext';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockChannelPushOk,
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createMockSocket } from '../../../__helpers__/sessionStoreHelpers';
import { createWorkflowYDoc } from '../../../__helpers__/workflowFactory';

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';

interface SetupOptions {
  canEdit?: boolean;
  authMethods?: WebhookAuthMethod[];
}

/**
 * Builds a connected workflow store whose channel resolves
 * `request_trigger_auth_methods` with the supplied auth methods.
 */
function createConnectedWorkflowStore(
  ydoc: Y.Doc,
  authMethods: WebhookAuthMethod[]
): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const channel = createMockPhoenixChannel();
  channel.push = createMockChannelPushOk({
    trigger_id: TRIGGER_ID,
    webhook_auth_methods: authMethods,
  });
  const provider = createMockPhoenixChannelProvider(channel);
  store.connect(ydoc, provider as never);
  return store;
}

/**
 * Renders the panel inside a session + store context with permissions emitted
 * via the session context channel.
 */
async function setup(
  trigger: Workflow.Trigger,
  workflowStore: WorkflowStoreInstance,
  { canEdit = true }: SetupOptions = {}
) {
  const sessionStore = createSessionStore();
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(
    mockSocket,
    'test:room',
    { id: 'user-1', name: 'Test', email: 'test@example.com', color: '#000' },
    { connect: true }
  );

  await new Promise(resolve => setTimeout(resolve, 50));

  const provider = sessionStore.getSnapshot().provider;
  if (provider) {
    provider.emit('sync', [true]);
    provider.emit('status', [{ status: 'connected' }]);
  }

  const sessionContextStore: SessionContextStoreInstance =
    createSessionContextStore();
  const ctxChannel = createMockPhoenixChannel();
  const ctxProvider = createMockPhoenixChannelProvider(ctxChannel);
  sessionContextStore._connectChannel(ctxProvider as never);

  act(() => {
    (
      ctxChannel as never as {
        _test: { emit: (e: string, m: unknown) => void };
      }
    )._test.emit('session_context', {
      user: null,
      project: null,
      config: {
        require_email_verification: false,
        kafka_triggers_enabled: false,
      },
      permissions: {
        can_edit_workflow: canEdit,
        can_run_workflow: canEdit,
        can_write_webhook_auth_method: canEdit,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: false,
    });
  });

  const storeValue = {
    workflowStore,
    sessionContextStore,
    uiStore: createUIStore(),
  } as unknown as StoreContextValue;

  const onClose = vi.fn();
  const onEdit = vi.fn();

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <StoreContext.Provider value={storeValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );

  render(
    <WebhookShowPanel trigger={trigger} onClose={onClose} onEdit={onEdit} />,
    { wrapper }
  );

  return { onClose, onEdit };
}

function makeWebhookTrigger(): Workflow.Trigger {
  return {
    id: TRIGGER_ID,
    type: 'webhook',
    enabled: true,
    has_auth_method: false,
    cron_expression: null,
    cron_cursor_job_id: null,
    kafka_configuration: null,
    webhook_reply: 'before_start',
    webhook_response_config: null,
  } as Workflow.Trigger;
}

const AUTH_METHODS: WebhookAuthMethod[] = [
  {
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Primary API Key',
    auth_type: 'api',
  },
];

describe('WebhookShowPanel', () => {
  let ydoc: Y.Doc;
  let trigger: Workflow.Trigger;

  beforeEach(() => {
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'webhook' } },
    });
    // Populate the workflow map so the store derives a saved (non-deleted)
    // workflow; otherwise useWorkflowReadOnly treats an empty map's
    // `deleted_at === undefined` as deleted.
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
    trigger = makeWebhookTrigger();
  });

  test('renders the webhook URL', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc, []);
    await setup(trigger, workflowStore);

    expect(
      screen.getByText(`${window.location.origin}/i/${TRIGGER_ID}`)
    ).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Copy URL' })
    ).toBeInTheDocument();
  });

  describe('authentication section', () => {
    // The section is collapsible and collapsed by default; the disclosure
    // button's accessible name is "Authentication (<count>)".
    const expandAuth = () =>
      userEvent.click(screen.getByRole('button', { name: /^authentication/i }));

    test('shows a count in the header and the configured methods when expanded', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, AUTH_METHODS);
      await setup(trigger, workflowStore);

      await expandAuth();
      await waitFor(() => {
        expect(screen.getByText('Primary API Key')).toBeInTheDocument();
      });
      expect(screen.getByText('(API Key)')).toBeInTheDocument();
      expect(screen.getByText(/1 configured/i)).toBeInTheDocument();
      expect(
        screen.queryByText(/no authentication configured/i)
      ).not.toBeInTheDocument();
    });

    test('shows "none configured" and an Add authentication link when none and editable', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      const { onEdit } = await setup(trigger, workflowStore, { canEdit: true });

      await waitFor(() => {
        expect(screen.getByText(/none configured/i)).toBeInTheDocument();
      });

      await expandAuth();
      await waitFor(() => {
        expect(
          screen.getByText(/no authentication configured/i)
        ).toBeInTheDocument();
      });

      const addLink = screen.getByRole('button', {
        name: /add authentication/i,
      });
      await userEvent.click(addLink);
      expect(onEdit).toHaveBeenCalledTimes(1);
    });

    test('hides the Add authentication link for viewers even when no auth configured', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      await setup(trigger, workflowStore, { canEdit: false });

      await expandAuth();
      await waitFor(() => {
        expect(
          screen.getByText(/no authentication configured/i)
        ).toBeInTheDocument();
      });
      expect(
        screen.queryByRole('button', { name: /add authentication/i })
      ).not.toBeInTheDocument();
    });
  });

  describe('edit button gating', () => {
    test('is enabled and calls onEdit when the user can edit', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      const { onEdit } = await setup(trigger, workflowStore, { canEdit: true });

      const editButton = screen.getByRole('button', { name: 'Edit trigger' });
      expect(editButton).not.toBeDisabled();

      await userEvent.click(editButton);
      expect(onEdit).toHaveBeenCalledTimes(1);
    });

    test('is disabled with a tooltip for read-only / viewers', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      const { onEdit } = await setup(trigger, workflowStore, {
        canEdit: false,
      });

      const editButton = screen.getByRole('button', { name: 'Edit trigger' });
      expect(editButton).toBeDisabled();
      await userEvent.click(editButton);
      expect(onEdit).not.toHaveBeenCalled();

      // The disabled tooltip message from useWorkflowReadOnly surfaces on hover
      // of the wrapping span (the button itself is disabled).
      const wrapper = editButton.parentElement;
      if (wrapper) {
        await userEvent.hover(wrapper);
      }
      await waitFor(() => {
        expect(
          screen.getAllByText(
            'You do not have permission to edit this workflow'
          ).length
        ).toBeGreaterThan(0);
      });
    });
  });
});
