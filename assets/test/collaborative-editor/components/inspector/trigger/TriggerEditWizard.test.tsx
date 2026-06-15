/**
 * TriggerEditWizard Component Tests
 *
 * Consolidates coverage from the former WebhookEditWizard and CronEditWizard
 * tests (#4787). Exercises the unified type-agnostic wizard for all three
 * trigger types (webhook, cron, kafka): Choose ↔ Picker ↔ Configure navigation,
 * the draft/commit lifecycle (Finish commits once via updateTrigger then calls
 * onDone; Cancel discards without writing), and type-specific field behaviour.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { TriggerEditWizard } from '../../../../../js/collaborative-editor/components/inspector/trigger/TriggerEditWizard';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WebhookAuthMethod } from '../../../../../js/collaborative-editor/types/sessionContext';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockChannelPushOk,
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createTriggerTestHarness } from '../../../__helpers__/triggerInspectorHelpers';
import { createWorkflowYDoc } from '../../../__helpers__/workflowFactory';

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';
const JOB_ID = '44444444-4444-4444-8444-444444444444';
const AUTH_METHOD_1 = '22222222-2222-4222-8222-222222222222';
const AUTH_METHOD_2 = '33333333-3333-4333-8333-333333333333';

const PROJECT_AUTH_METHODS: WebhookAuthMethod[] = [
  { id: AUTH_METHOD_1, name: 'Primary API Key', auth_type: 'api' },
  { id: AUTH_METHOD_2, name: 'Basic Login', auth_type: 'basic' },
];

const mockLiveViewActions = {
  pushEvent: vi.fn(),
  pushEventTo: vi.fn(),
  handleEvent: vi.fn(() => () => {}),
  navigate: vi.fn(),
};

// ---------------------------------------------------------------------------
// Trigger factories
// ---------------------------------------------------------------------------

function makeWebhookTrigger(
  overrides: Partial<Workflow.Trigger> = {}
): Workflow.Trigger {
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
    ...overrides,
  } as Workflow.Trigger;
}

function makeCronTrigger(
  overrides: Partial<Workflow.Trigger> = {}
): Workflow.Trigger {
  return {
    id: TRIGGER_ID,
    type: 'cron',
    enabled: true,
    has_auth_method: false,
    cron_expression: '0 0 * * *',
    cron_cursor_job_id: null,
    kafka_configuration: null,
    webhook_reply: null,
    webhook_response_config: null,
    ...overrides,
  } as Workflow.Trigger;
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

// ---------------------------------------------------------------------------
// Store helpers
// ---------------------------------------------------------------------------

/**
 * Builds a connected workflow store whose channel resolves
 * `request_trigger_auth_methods` with the supplied associated methods.
 */
function createConnectedWorkflowStore(
  ydoc: Y.Doc,
  associatedMethods: WebhookAuthMethod[] = []
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

// ---------------------------------------------------------------------------
// Render helper
// ---------------------------------------------------------------------------

interface SetupOptions {
  initialFocus?: 'authentication' | 'response';
}

async function setup(
  trigger: Workflow.Trigger,
  workflowStore: WorkflowStoreInstance,
  { initialFocus }: SetupOptions = {}
) {
  const { wrapper, sessionChannel } = await createTriggerTestHarness({
    canEdit: true,
    kafkaEnabled: true,
    webhookAuthMethods: PROJECT_AUTH_METHODS,
    workflowStore,
    liveViewActions: mockLiveViewActions,
  });

  const onClose = vi.fn();
  const onDone = vi.fn();

  render(
    <TriggerEditWizard
      trigger={trigger}
      initialFocus={initialFocus}
      onClose={onClose}
      onDone={onDone}
    />,
    { wrapper }
  );

  return { onClose, onDone, sessionChannel };
}

// ===========================================================================
// WEBHOOK PATH
// ===========================================================================

describe('TriggerEditWizard — webhook', () => {
  let ydoc: Y.Doc;

  beforeEach(() => {
    mockLiveViewActions.pushEvent.mockClear();
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'webhook' } },
    });
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
  });

  describe('navigation', () => {
    test('starts on Choose, Next navigates to Configure, breadcrumb Choose returns', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeWebhookTrigger(), workflowStore);

      expect(
        screen.getByRole('heading', { name: 'On webhook call' })
      ).toBeInTheDocument();

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      // Configure-only control confirms we're on Configure.
      expect(screen.getByLabelText(/Response Type/i)).toBeInTheDocument();

      // Breadcrumb "Choose" crumb returns to Choose.
      await userEvent.click(screen.getByRole('button', { name: 'Choose' }));
      expect(screen.queryByLabelText(/Response Type/i)).not.toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: 'Change' })
      ).toBeInTheDocument();
    });

    test('Change opens the picker; picking Webhook returns to Choose', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeWebhookTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Change' }));
      expect(
        screen.getByRole('heading', { name: 'What triggers this workflow?' })
      ).toBeInTheDocument();

      await userEvent.click(
        screen.getByRole('button', { name: /on webhook call/i })
      );
      expect(
        screen.getByRole('heading', { name: 'On webhook call' })
      ).toBeInTheDocument();
    });

    test('initialFocus="authentication" opens directly on Configure', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeWebhookTrigger(), workflowStore, {
        initialFocus: 'authentication',
      });

      // Should be on Configure step immediately (Response Type control present).
      expect(screen.getByLabelText(/Response Type/i)).toBeInTheDocument();
    });
  });

  describe('commit lifecycle', () => {
    test('Cancel discards the draft and never calls updateTrigger', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(makeWebhookTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

      expect(onDone).toHaveBeenCalledTimes(1);
      expect(updateSpy).not.toHaveBeenCalled();
    });

    test('Finish with no changes skips updateTrigger but still calls onDone', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(makeWebhookTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      // The draft equals the source trigger, so commit() writes nothing — this
      // is what stops an unchanged Finish from clobbering concurrent edits.
      await waitFor(() => {
        expect(onDone).toHaveBeenCalledTimes(1);
      });
      expect(updateSpy).not.toHaveBeenCalled();
    });

    test('switching Response Type to Immediately clears response config in the committed payload', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const withConfig = makeWebhookTrigger({
        webhook_reply: 'after_completion',
        webhook_response_config: { success_code: 201, error_code: 500 },
      });
      const { onDone } = await setup(withConfig, workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      await userEvent.click(screen.getByLabelText(/Response Type/i));
      await userEvent.click(
        screen.getByRole('option', { name: /Immediately/i })
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
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const withConfig = makeWebhookTrigger({
        webhook_reply: 'after_completion',
        webhook_response_config: { success_code: 201, error_code: 500 },
      });
      const { onDone } = await setup(withConfig, workflowStore);

      // Change → picker → re-pick the same type → back on Choose.
      // Must NOT reset the draft to type defaults.
      await userEvent.click(screen.getByRole('button', { name: 'Change' }));
      await userEvent.click(
        screen.getByRole('button', { name: /on webhook call/i })
      );
      await userEvent.click(screen.getByRole('button', { name: 'Next' }));

      // The draft still reflects after_completion — its Response Options section
      // (only rendered in that mode) is present, proving config was preserved
      // rather than reset to the before_start default.
      expect(
        screen.getByRole('button', { name: 'Response Options' })
      ).toBeInTheDocument();

      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      // Nothing changed, so commit() writes nothing; a reset would instead have
      // committed the type defaults.
      await waitFor(() => {
        expect(onDone).toHaveBeenCalledTimes(1);
      });
      expect(updateSpy).not.toHaveBeenCalled();
    });
  });

  describe('auth buffering', () => {
    test('selecting a credential buffers it; channel commit fires only on Finish', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const { sessionChannel } = await setup(
        makeWebhookTrigger(),
        workflowStore
      );

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      await userEvent.click(
        screen.getByRole('button', { name: 'Authentication' })
      );
      await userEvent.click(
        screen.getByRole('button', { name: 'Authentication credential 1' })
      );
      await userEvent.click(
        screen.getByRole('option', { name: /Basic Login/i })
      );

      // No auth push before Finish.
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
          auth_method_ids: [AUTH_METHOD_2],
        });
      });
    });

    test('the Add button appends another credential row', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeWebhookTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      await userEvent.click(
        screen.getByRole('button', { name: 'Authentication' })
      );
      await userEvent.click(
        screen.getByRole('button', { name: 'Authentication credential 1' })
      );
      await userEvent.click(
        screen.getByRole('option', { name: /Basic Login/i })
      );
      await userEvent.click(screen.getByRole('button', { name: /add/i }));
      expect(
        screen.getByRole('button', { name: 'Authentication credential 2' })
      ).toBeInTheDocument();
    });

    test('the "Create a new authentication method" link opens the create flow', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeWebhookTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      await userEvent.click(
        screen.getByRole('button', { name: 'Authentication' })
      );
      await userEvent.click(
        screen.getByRole('button', {
          name: /create a new authentication method/i,
        })
      );

      expect(mockLiveViewActions.pushEvent).toHaveBeenCalledWith(
        'open_webhook_auth_modal',
        {}
      );
    });
  });
});

// ===========================================================================
// CRON PATH
// ===========================================================================

describe('TriggerEditWizard — cron', () => {
  let ydoc: Y.Doc;

  beforeEach(() => {
    mockLiveViewActions.pushEvent.mockClear();
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'cron' } },
      jobs: {
        [JOB_ID]: { id: JOB_ID, name: 'Transform data' },
      },
    });
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
  });

  describe('navigation', () => {
    test('Choose -> Next -> Configure; breadcrumb Choose returns; back-arrow from Choose exits', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const { onDone } = await setup(makeCronTrigger(), workflowStore);

      // Choose step is the landing screen.
      expect(
        screen.getByRole('heading', { name: 'On a Schedule' })
      ).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: 'Change' })
      ).toBeInTheDocument();

      // Next → Configure (Configure-only control present).
      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      expect(screen.getByLabelText('Cron Input Source')).toBeInTheDocument();

      // Breadcrumb "Choose" crumb returns to Choose.
      await userEvent.click(screen.getByRole('button', { name: 'Choose' }));
      expect(
        screen.queryByLabelText('Cron Input Source')
      ).not.toBeInTheDocument();

      // Back-arrow from Choose exits the wizard.
      await userEvent.click(screen.getByRole('button', { name: 'Back' }));
      expect(onDone).toHaveBeenCalledTimes(1);
    });
  });

  describe('commit lifecycle', () => {
    test('Finish commits cron_expression + cron_cursor_job_id via updateTrigger then onDone', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(makeCronTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));

      // Pick a frequency from the CronFieldBuilder dropdown.
      await userEvent.selectOptions(
        screen.getByLabelText('Frequency'),
        'every_n_minutes'
      );

      // Pick a Cron Input Source.
      await userEvent.selectOptions(
        screen.getByLabelText('Cron Input Source'),
        JOB_ID
      );

      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      await waitFor(() => {
        expect(updateSpy).toHaveBeenCalledTimes(1);
      });
      expect(updateSpy).toHaveBeenCalledWith(
        TRIGGER_ID,
        expect.objectContaining({
          cron_expression: '*/15 * * * *',
          cron_cursor_job_id: JOB_ID,
        })
      );
      expect(onDone).toHaveBeenCalledTimes(1);
    });

    test('an existing schedule seeds the frequency dropdown', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(
        makeCronTrigger({ cron_expression: '*/15 * * * *' }),
        workflowStore
      );

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      // "*/15 * * * *" is recognised as the "every N minutes" frequency.
      expect(screen.getByLabelText('Frequency')).toHaveValue('every_n_minutes');
    });
  });
});

// ===========================================================================
// KAFKA PATH
// ===========================================================================

describe('TriggerEditWizard — kafka', () => {
  let ydoc: Y.Doc;

  beforeEach(() => {
    mockLiveViewActions.pushEvent.mockClear();
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'kafka' } },
    });
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
  });

  describe('navigation', () => {
    test('starts on Choose showing "Kafka" badge, Next navigates to Configure', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeKafkaTrigger(), workflowStore);

      // TriggerChooseStep renders with the Kafka badge.
      expect(
        screen.getByRole('heading', { name: /kafka/i })
      ).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: 'Change' })
      ).toBeInTheDocument();

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      // Configure-only controls confirm we're on KafkaConfigureStep.
      expect(screen.getByLabelText('Kafka Hosts')).toBeInTheDocument();
      expect(screen.getByLabelText('Topics')).toBeInTheDocument();
    });

    test('breadcrumb Choose returns from Configure to Choose', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeKafkaTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      expect(screen.getByLabelText('Kafka Hosts')).toBeInTheDocument();

      await userEvent.click(screen.getByRole('button', { name: 'Choose' }));
      expect(screen.queryByLabelText('Kafka Hosts')).not.toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: 'Change' })
      ).toBeInTheDocument();
    });
  });

  describe('commit lifecycle', () => {
    test('Finish commits updated kafka_configuration via updateTrigger then onDone', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(makeKafkaTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));

      // Edit the hosts field.
      const hostsInput = screen.getByLabelText('Kafka Hosts');
      await userEvent.clear(hostsInput);
      await userEvent.type(hostsInput, 'broker1:9092');

      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      await waitFor(() => {
        expect(updateSpy).toHaveBeenCalledTimes(1);
      });
      const committed = updateSpy.mock.calls[0][1] as Workflow.Trigger;
      expect(committed.kafka_configuration?.hosts_string).toBe('broker1:9092');
      expect(onDone).toHaveBeenCalledTimes(1);
    });

    test('Cancel discards the draft and never calls updateTrigger', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(makeKafkaTrigger(), workflowStore);

      // Back-arrow from Choose exits without committing.
      await userEvent.click(screen.getByRole('button', { name: 'Back' }));

      expect(onDone).toHaveBeenCalledTimes(1);
      expect(updateSpy).not.toHaveBeenCalled();
    });
  });

  describe('SASL fields', () => {
    test('selecting a SASL mechanism on Configure shows username and password fields', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeKafkaTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));

      // No credentials visible with sasl: null.
      expect(screen.queryByLabelText('Username')).not.toBeInTheDocument();

      await userEvent.selectOptions(
        screen.getByLabelText('SASL Authentication'),
        'plain'
      );

      expect(screen.getByLabelText('Username')).toBeInTheDocument();
      expect(screen.getByLabelText('Password')).toBeInTheDocument();
    });
  });
});

// ===========================================================================
// TYPE SWITCHING VIA PICKER
// ===========================================================================

describe('TriggerEditWizard — type switching via picker', () => {
  let ydoc: Y.Doc;

  beforeEach(() => {
    mockLiveViewActions.pushEvent.mockClear();
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'webhook' } },
    });
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
  });

  test('picking a different type from the picker moves the draft to that type', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc);
    await setup(makeWebhookTrigger(), workflowStore);

    // Start at webhook Choose, open picker.
    await userEvent.click(screen.getByRole('button', { name: 'Change' }));
    expect(
      screen.getByRole('heading', { name: 'What triggers this workflow?' })
    ).toBeInTheDocument();

    // Pick cron instead.
    await userEvent.click(
      screen.getByRole('button', { name: /on a schedule/i })
    );

    // Should be on Choose step for cron now.
    expect(
      screen.getByRole('heading', { name: 'On a Schedule' })
    ).toBeInTheDocument();
  });
});
