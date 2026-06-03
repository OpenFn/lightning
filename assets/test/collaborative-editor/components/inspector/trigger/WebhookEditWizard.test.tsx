/**
 * WebhookEditWizard Component Tests
 *
 * Covers the webhook edit wizard (#4798): the draft/commit lifecycle
 * (Cancel discards, Finish commits once), the Response Type → clear-config
 * behaviour, auth-method buffering (channel commit only on Finish), and the
 * Choose ↔ Picker ↔ Configure navigation.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { WebhookEditWizard } from '../../../../../js/collaborative-editor/components/inspector/trigger/WebhookEditWizard';
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

// Mock the auth modal so we can exercise its onSave boundary without rendering
// the full Headless UI dialog. The mock surfaces a button that buffers an id.
vi.mock(
  '../../../../../js/collaborative-editor/components/inspector/WebhookAuthMethodModal',
  () => ({
    WebhookAuthMethodModal: ({
      onSave,
    }: {
      onSave: (ids: string[]) => Promise<void>;
    }) => (
      <button type="button" onClick={() => void onSave(['auth-2'])}>
        mock-save-auth
      </button>
    ),
  })
);

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';
const AUTH_METHOD_1 = '22222222-2222-4222-8222-222222222222';
const AUTH_METHOD_2 = '33333333-3333-4333-8333-333333333333';

const PROJECT_AUTH_METHODS: WebhookAuthMethod[] = [
  { id: AUTH_METHOD_1, name: 'Primary API Key', auth_type: 'api' },
  { id: AUTH_METHOD_2, name: 'Basic Login', auth_type: 'basic' },
];

/**
 * Builds a connected workflow store whose channel resolves
 * `request_trigger_auth_methods` with the supplied associated methods.
 */
function createConnectedWorkflowStore(
  ydoc: Y.Doc,
  associatedMethods: WebhookAuthMethod[]
): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const channel = createMockPhoenixChannel();
  channel.push = createMockChannelPushOk({
    trigger_id: TRIGGER_ID,
    webhook_auth_methods: associatedMethods,
  });
  const provider = createMockPhoenixChannelProvider(channel);
  store.connect(ydoc, provider as never);
  return store;
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

async function setup(
  trigger: Workflow.Trigger,
  workflowStore: WorkflowStoreInstance
) {
  const sessionStore = createSessionStore();
  sessionStore.initializeSession(
    createMockSocket(),
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
  // The session provider channel is where commitAuthMethods pushes.
  const sessionChannel = provider?.channel as unknown as {
    push: ReturnType<typeof createMockChannelPushOk>;
  };
  sessionChannel.push = createMockChannelPushOk({ ok: true });

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
        kafka_triggers_enabled: true,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: PROJECT_AUTH_METHODS,
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
  const onDone = vi.fn();

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <StoreContext.Provider value={storeValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );

  render(
    <WebhookEditWizard trigger={trigger} onClose={onClose} onDone={onDone} />,
    { wrapper }
  );

  return { onClose, onDone, sessionChannel };
}

describe('WebhookEditWizard', () => {
  let ydoc: Y.Doc;
  let trigger: Workflow.Trigger;

  beforeEach(() => {
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'webhook' } },
    });
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
    trigger = makeWebhookTrigger();
  });

  describe('commit lifecycle', () => {
    test('Cancel discards the draft and never calls updateTrigger', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(trigger, workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

      expect(onDone).toHaveBeenCalledTimes(1);
      expect(updateSpy).not.toHaveBeenCalled();
    });

    test('Finish on a valid draft calls updateTrigger once then onDone', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(trigger, workflowStore);

      // Choose -> Configure
      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      await waitFor(() => {
        expect(updateSpy).toHaveBeenCalledTimes(1);
      });
      expect(updateSpy).toHaveBeenCalledWith(TRIGGER_ID, expect.any(Object));
      expect(onDone).toHaveBeenCalledTimes(1);
    });

    test('switching Response Type to Immediately clears response config in the committed payload', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      // Start with an after_completion trigger carrying a response config.
      const withConfig = {
        ...makeWebhookTrigger(),
        webhook_reply: 'after_completion',
        webhook_response_config: { success_code: 201, error_code: 500 },
      } as Workflow.Trigger;
      const { onDone } = await setup(withConfig, workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));

      // Switch back to Immediately (before_start) -> config must clear.
      await userEvent.selectOptions(
        screen.getByLabelText('Response Type'),
        'before_start'
      );
      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      await waitFor(() => {
        expect(updateSpy).toHaveBeenCalledTimes(1);
      });
      expect(updateSpy).toHaveBeenCalledWith(
        TRIGGER_ID,
        expect.objectContaining({
          webhook_reply: 'before_start',
          webhook_response_config: null,
        })
      );
      expect(onDone).toHaveBeenCalledTimes(1);
    });

    test('re-picking the current type (Webhook) preserves the existing config', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const withConfig = {
        ...makeWebhookTrigger(),
        webhook_reply: 'after_completion',
        webhook_response_config: { success_code: 201, error_code: 500 },
      } as Workflow.Trigger;
      const { onDone } = await setup(withConfig, workflowStore);

      // Change -> picker -> re-pick the same type (Webhook) -> back on Choose.
      // This must NOT reset the draft to the type's defaults.
      await userEvent.click(screen.getByRole('button', { name: 'Change' }));
      await userEvent.click(
        screen.getByRole('button', { name: /on webhook call/i })
      );
      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      await waitFor(() => {
        expect(updateSpy).toHaveBeenCalledTimes(1);
      });
      expect(updateSpy).toHaveBeenCalledWith(
        TRIGGER_ID,
        expect.objectContaining({
          webhook_reply: 'after_completion',
          webhook_response_config: { success_code: 201, error_code: 500 },
        })
      );
      expect(onDone).toHaveBeenCalledTimes(1);
    });
  });

  describe('auth buffering', () => {
    test('auth modal onSave buffers ids; the channel commit fires only on Finish', async () => {
      // Trigger starts associated with method 1; saving in the modal selects
      // method 2 instead, so the set changed and a commit must fire on Finish.
      const workflowStore = createConnectedWorkflowStore(ydoc, [
        PROJECT_AUTH_METHODS[0],
      ]);
      const { sessionChannel } = await setup(trigger, workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));

      // Open the (mocked) auth modal and save a new selection.
      await userEvent.click(
        screen.getByRole('button', { name: /manage authentication/i })
      );
      await userEvent.click(
        screen.getByRole('button', { name: 'mock-save-auth' })
      );

      // No channel push for auth before Finish.
      const authPushBefore = (
        sessionChannel.push as ReturnType<typeof vi.fn>
      ).mock.calls.filter(([event]) => event === 'update_trigger_auth_methods');
      expect(authPushBefore).toHaveLength(0);

      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      await waitFor(() => {
        const authPushAfter = (
          sessionChannel.push as ReturnType<typeof vi.fn>
        ).mock.calls.filter(
          ([event]) => event === 'update_trigger_auth_methods'
        );
        expect(authPushAfter).toHaveLength(1);
        expect(authPushAfter[0][1]).toEqual({
          trigger_id: TRIGGER_ID,
          auth_method_ids: ['auth-2'],
        });
      });
    });
  });

  describe('navigation', () => {
    test('Choose -> Configure -> Back -> Choose', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      await setup(trigger, workflowStore);

      expect(
        screen.getByRole('heading', { name: 'Select trigger' })
      ).toBeInTheDocument();

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      expect(
        screen.getByRole('heading', { name: 'Setup Trigger' })
      ).toBeInTheDocument();

      await userEvent.click(screen.getByRole('button', { name: 'Back' }));
      expect(
        screen.getByRole('heading', { name: 'Select trigger' })
      ).toBeInTheDocument();
    });

    test('Change opens the picker; picking Webhook returns to Choose', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc, []);
      await setup(trigger, workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Change' }));
      expect(
        screen.getByRole('heading', { name: 'What triggers this workflow?' })
      ).toBeInTheDocument();

      await userEvent.click(
        screen.getByRole('button', { name: /on webhook call/i })
      );
      expect(
        screen.getByRole('heading', { name: 'Select trigger' })
      ).toBeInTheDocument();
    });
  });
});
