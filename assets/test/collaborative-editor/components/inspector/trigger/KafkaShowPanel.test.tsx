/**
 * KafkaShowPanel Component Tests
 *
 * Covers the read-only kafka "show" panel (#4787): the "Kafka" badge, the
 * summary fields (Hosts, Topics, SSL, Authentication), and the Edit button
 * permission gating.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { KafkaShowPanel } from '../../../../../js/collaborative-editor/components/inspector/trigger/KafkaShowPanel';
import { SessionContext } from '../../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import type { SessionContextStoreInstance } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createMockSocket } from '../../../__helpers__/sessionStoreHelpers';
import { createWorkflowYDoc } from '../../../__helpers__/workflowFactory';

const TRIGGER_ID = '22222222-2222-4222-8222-222222222222';

interface SetupOptions {
  canEdit?: boolean;
}

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const channel = createMockPhoenixChannel();
  const provider = createMockPhoenixChannelProvider(channel);
  store.connect(ydoc, provider as never);
  return store;
}

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
        kafka_triggers_enabled: true,
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
    <KafkaShowPanel trigger={trigger} onClose={onClose} onEdit={onEdit} />,
    { wrapper }
  );

  return { onClose, onEdit };
}

function makeKafkaTrigger(
  overrides: Partial<Workflow.Trigger> = {}
): Workflow.Trigger {
  return {
    id: TRIGGER_ID,
    type: 'kafka',
    enabled: true,
    has_auth_method: false,
    cron_expression: null,
    cron_cursor_job_id: null,
    kafka_configuration: {
      hosts_string: 'localhost:9092',
      topics_string: 'events',
      ssl: true,
      sasl: 'scram_sha_256',
      username: 'u',
      password: 'p',
      initial_offset_reset_policy: 'latest',
      connect_timeout: 30000,
    },
    webhook_reply: null,
    webhook_response_config: null,
    ...overrides,
  } as Workflow.Trigger;
}

describe('KafkaShowPanel', () => {
  let ydoc: Y.Doc;

  beforeEach(() => {
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'kafka' } },
    });
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
  });

  test('renders badge and all summary fields from kafka_configuration', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc);
    await setup(makeKafkaTrigger(), workflowStore);

    // Both the panel title <h2> and the badge <span> render "Kafka";
    // assert the badge (span element) is present alongside the data fields.
    const kafkaLabels = screen.getAllByText('Kafka');
    const badge = kafkaLabels.find(el => el.tagName === 'SPAN');
    expect(badge).toBeTruthy();
    expect(screen.getByText('localhost:9092')).toBeInTheDocument();
    expect(screen.getByText('events')).toBeInTheDocument();
    expect(screen.getByText('Enabled')).toBeInTheDocument();
    expect(screen.getByText('SCRAM-SHA-256')).toBeInTheDocument();
  });

  test('shows "None" for authentication when sasl is null', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc);
    await setup(
      makeKafkaTrigger({
        kafka_configuration: {
          hosts_string: 'localhost:9092',
          topics_string: 'events',
          ssl: false,
          sasl: null,
          initial_offset_reset_policy: 'latest',
          connect_timeout: 30000,
        },
      } as Partial<Workflow.Trigger>),
      workflowStore
    );

    expect(screen.getByText('None')).toBeInTheDocument();
    expect(screen.getByText('Disabled')).toBeInTheDocument();
  });

  test('shows "—" for empty hosts and topics', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc);
    await setup(
      makeKafkaTrigger({
        kafka_configuration: {
          hosts_string: '',
          topics_string: '',
          ssl: false,
          sasl: null,
          initial_offset_reset_policy: 'latest',
          connect_timeout: 30000,
        },
      } as Partial<Workflow.Trigger>),
      workflowStore
    );

    // Two "—" entries: one for hosts and one for topics
    const dashes = screen.getAllByText('—');
    expect(dashes.length).toBeGreaterThanOrEqual(2);
  });

  describe('edit button gating', () => {
    test('is enabled and calls onEdit when the user can edit', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const { onEdit } = await setup(makeKafkaTrigger(), workflowStore, {
        canEdit: true,
      });

      const editButton = screen.getByRole('button', { name: 'Edit trigger' });
      expect(editButton).not.toBeDisabled();

      await userEvent.click(editButton);
      expect(onEdit).toHaveBeenCalledTimes(1);
    });

    test('is disabled with a tooltip for read-only / viewers', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const { onEdit } = await setup(makeKafkaTrigger(), workflowStore, {
        canEdit: false,
      });

      const editButton = screen.getByRole('button', { name: 'Edit trigger' });
      expect(editButton).toBeDisabled();
      await userEvent.click(editButton);
      expect(onEdit).not.toHaveBeenCalled();

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
