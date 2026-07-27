/**
 * KafkaConfigureStep Component Tests
 *
 * Covers the kafka wizard's "Configure" step (#4787): field bindings via
 * mergeDraft, conditional SASL credential fields, the Advanced section toggle,
 * and the validationError display.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { KafkaConfigureStep } from '../../../../../js/collaborative-editor/components/inspector/trigger/KafkaConfigureStep';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createTriggerTestHarness } from '../../../__helpers__/triggerInspectorHelpers';
import { createWorkflowYDoc } from '../../../__helpers__/workflowFactory';

const TRIGGER_ID = '33333333-3333-4333-8333-333333333333';

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const channel = createMockPhoenixChannel();
  const provider = createMockPhoenixChannelProvider(channel);
  store.connect(ydoc, provider as never);
  return store;
}

interface SetupOptions {
  draft?: Workflow.Trigger;
  mergeDraft?: (updates: Partial<Workflow.Trigger>) => void;
  validationError?: string | null;
}

async function setup(
  workflowStore: WorkflowStoreInstance,
  { draft, mergeDraft = vi.fn(), validationError = null }: SetupOptions = {}
) {
  const resolvedDraft: Workflow.Trigger = draft ?? makeKafkaDraft();

  const { wrapper } = await createTriggerTestHarness({
    kafkaEnabled: true,
    workflowStore,
  });

  const onClose = vi.fn();
  const onBack = vi.fn();
  const onFinish = vi.fn();

  render(
    <KafkaConfigureStep
      draft={resolvedDraft}
      mergeDraft={mergeDraft}
      validationError={validationError}
      onClose={onClose}
      onBack={onBack}
      onFinish={onFinish}
    />,
    { wrapper }
  );

  return { onClose, onBack, onFinish, mergeDraft };
}

/** Kafka draft with sasl: null (no auth). */
function makeKafkaDraft(
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
      ssl: false,
      sasl: null,
      username: '',
      password: '',
      initial_offset_reset_policy: 'latest',
      connect_timeout: 30000,
    },
    webhook_reply: null,
    webhook_response_config: null,
    ...overrides,
  } as Workflow.Trigger;
}

/** Kafka draft with a SASL mechanism set (shows credential fields). */
function makeKafkaDraftWithSasl(
  sasl: 'plain' | 'scram_sha_256' | 'scram_sha_512'
): Workflow.Trigger {
  return makeKafkaDraft({
    kafka_configuration: {
      hosts_string: 'localhost:9092',
      topics_string: 'events',
      ssl: false,
      sasl,
      username: 'user',
      password: 'pass',
      initial_offset_reset_policy: 'latest',
      connect_timeout: 30000,
    },
  } as Partial<Workflow.Trigger>);
}

describe('KafkaConfigureStep', () => {
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

  test('typing in Kafka Hosts calls mergeDraft with updated hosts_string', async () => {
    const mergeDraft = vi.fn();
    const workflowStore = createConnectedWorkflowStore(ydoc);
    // Start from an empty hosts draft so the appended character is unambiguous
    await setup(workflowStore, {
      draft: makeKafkaDraft({
        kafka_configuration: {
          hosts_string: '',
          topics_string: 'events',
          ssl: false,
          sasl: null,
          username: '',
          password: '',
          initial_offset_reset_policy: 'latest',
          connect_timeout: 30000,
        },
      } as Partial<Workflow.Trigger>),
      mergeDraft,
    });

    await userEvent.type(screen.getByLabelText('Kafka Hosts'), 'b');

    // mergeDraft is called with kafka_configuration containing updated hosts_string
    const hostsCall = mergeDraft.mock.calls[0][0] as {
      kafka_configuration: { hosts_string: string };
    };
    expect(hostsCall.kafka_configuration.hosts_string).toBe('b');
  });

  test('typing in Topics calls mergeDraft with updated topics_string', async () => {
    const mergeDraft = vi.fn();
    const workflowStore = createConnectedWorkflowStore(ydoc);
    // Start from an empty topics draft so the appended character is unambiguous
    await setup(workflowStore, {
      draft: makeKafkaDraft({
        kafka_configuration: {
          hosts_string: 'localhost:9092',
          topics_string: '',
          ssl: false,
          sasl: null,
          username: '',
          password: '',
          initial_offset_reset_policy: 'latest',
          connect_timeout: 30000,
        },
      } as Partial<Workflow.Trigger>),
      mergeDraft,
    });

    await userEvent.type(screen.getByLabelText('Topics'), 't');

    const topicsCall = mergeDraft.mock.calls[0][0] as {
      kafka_configuration: { topics_string: string };
    };
    expect(topicsCall.kafka_configuration.topics_string).toBe('t');
  });

  describe('SASL authentication', () => {
    test('selecting a SASL mechanism calls mergeDraft with that sasl value', async () => {
      const mergeDraft = vi.fn();
      const workflowStore = createConnectedWorkflowStore(ydoc);
      // Start from a no-auth draft; selecting PLAIN triggers the spy
      await setup(workflowStore, { draft: makeKafkaDraft(), mergeDraft });

      await userEvent.selectOptions(
        screen.getByLabelText('SASL Authentication'),
        'plain'
      );

      const saslCall = mergeDraft.mock.calls[0][0] as {
        kafka_configuration: { sasl: string | null };
      };
      expect(saslCall.kafka_configuration.sasl).toBe('plain');
    });

    test('username and password fields are visible when sasl is already set', async () => {
      // Render with a pre-set sasl so the conditional fields are present
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(workflowStore, {
        draft: makeKafkaDraftWithSasl('scram_sha_256'),
      });

      expect(screen.getByLabelText('Username')).toBeInTheDocument();
      expect(screen.getByLabelText('Password')).toBeInTheDocument();
    });

    test('username and password fields are hidden when sasl is null', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(workflowStore, { draft: makeKafkaDraft() });

      expect(screen.queryByLabelText('Username')).not.toBeInTheDocument();
      expect(screen.queryByLabelText('Password')).not.toBeInTheDocument();
    });
  });

  describe('Advanced section', () => {
    test('Advanced toggle reveals offset-policy and connect-timeout controls', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(workflowStore);

      // Advanced controls are hidden initially
      expect(
        screen.queryByLabelText('Initial Offset Reset Policy')
      ).not.toBeInTheDocument();
      expect(
        screen.queryByLabelText('Connect Timeout (ms)')
      ).not.toBeInTheDocument();

      await userEvent.click(screen.getByRole('button', { name: /Advanced/i }));

      expect(
        screen.getByLabelText('Initial Offset Reset Policy')
      ).toBeInTheDocument();
      expect(screen.getByLabelText('Connect Timeout (ms)')).toBeInTheDocument();
    });
  });

  test('displays validationError text near the Finish footer', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc);
    await setup(workflowStore, {
      validationError: 'Kafka hosts are required',
    });

    expect(screen.getByText('Kafka hosts are required')).toBeInTheDocument();
  });

  test('Finish button calls onFinish', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc);
    const { onFinish } = await setup(workflowStore);

    await userEvent.click(screen.getByRole('button', { name: 'Finish' }));
    expect(onFinish).toHaveBeenCalledTimes(1);
  });
});
