// Synthetic `WorkflowState` factories for v2 round-trip tests.
//
// These build state instances in the shape `v2.serializeWorkflow` consumes,
// pairing 1:1 with the on-disk fixtures under
// `test/fixtures/portability/v2/scenarios/`. They let round-trip tests
// (state → serialize → parse → state) run without depending on the YAML
// fixtures so the two layers can fail independently.

import type {
  StateEdge,
  StateJob,
  StateTrigger,
  WorkflowState,
} from '../../../js/yaml/types';

export const makeJob = (
  overrides: Partial<StateJob> & { name: string }
): StateJob => ({
  id: `job-${overrides.name}`,
  adaptor: '@openfn/language-common@latest',
  body: 'fn(state => state)\n',
  keychain_credential_id: null,
  project_credential_id: null,
  ...overrides,
});

export const baseEdge = (overrides: Partial<StateEdge>): StateEdge => ({
  id: `edge-${Math.random().toString(36).slice(2, 9)}`,
  condition_type: 'always',
  enabled: true,
  target_job_id: 'job-x',
  ...overrides,
});

export const simpleWebhookState = (): WorkflowState => {
  const greet = makeJob({ name: 'greet' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: 'after_completion',
  };
  return {
    id: 'wf-1',
    name: 'simple webhook',
    jobs: [greet],
    triggers: [webhook],
    edges: [
      baseEdge({
        source_trigger_id: webhook.id,
        target_job_id: greet.id,
      }),
    ],
    positions: null,
  };
};

export const cronWithCursorState = (): WorkflowState => {
  const cursor = makeJob({ name: 'cursor step' });
  const cron: StateTrigger = {
    id: 'trigger-cron',
    type: 'cron',
    enabled: true,
    cron_expression: '0 6 * * *',
    cron_cursor_job_id: cursor.id,
  };
  return {
    id: 'wf-2',
    name: 'cron with cursor',
    jobs: [cursor],
    triggers: [cron],
    edges: [
      baseEdge({
        source_trigger_id: cron.id,
        target_job_id: cursor.id,
      }),
    ],
    positions: null,
  };
};

export const jsExpressionEdgeState = (): WorkflowState => {
  const source = makeJob({ name: 'source step' });
  const target = makeJob({ name: 'target step' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: null,
  };
  return {
    id: 'wf-3',
    name: 'js expression edge',
    jobs: [source, target],
    triggers: [webhook],
    edges: [
      baseEdge({
        source_trigger_id: webhook.id,
        target_job_id: source.id,
      }),
      baseEdge({
        source_job_id: source.id,
        target_job_id: target.id,
        condition_type: 'js_expression',
        condition_label: 'Only when payload present',
        condition_expression: '!!state.data && state.data.length > 0\n',
      }),
    ],
    positions: null,
  };
};

export const multiTriggerState = (): WorkflowState => {
  const shared = makeJob({ name: 'shared step' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: null,
  };
  const cron: StateTrigger = {
    id: 'trigger-cron',
    type: 'cron',
    enabled: true,
    cron_expression: '*/5 * * * *',
    cron_cursor_job_id: null,
  };
  return {
    id: 'wf-4',
    name: 'multi trigger',
    jobs: [shared],
    triggers: [webhook, cron],
    edges: [
      baseEdge({ source_trigger_id: webhook.id, target_job_id: shared.id }),
      baseEdge({ source_trigger_id: cron.id, target_job_id: shared.id }),
    ],
    positions: null,
  };
};

export const kafkaTriggerState = (): WorkflowState => {
  const consume = makeJob({ name: 'consume' });
  const kafka: StateTrigger = {
    id: 'trigger-kafka',
    type: 'kafka',
    enabled: true,
    kafka_configuration: {
      hosts_string: 'broker-a:9092, broker-b:9092',
      topics_string: 'orders, shipments',
      ssl: true,
      sasl: 'scram_sha_256',
      username: 'svc-orders',
      password: 'pw-shh',
      initial_offset_reset_policy: 'earliest',
      connect_timeout: 30,
      group_id: 'lightning-orders',
    },
  };
  return {
    id: 'wf-5',
    name: 'kafka trigger',
    jobs: [consume],
    triggers: [kafka],
    edges: [
      baseEdge({
        source_trigger_id: kafka.id,
        target_job_id: consume.id,
      }),
    ],
    positions: null,
  };
};

export const branchingJobsState = (): WorkflowState => {
  const fanOut = makeJob({ name: 'fan out' });
  const branchA = makeJob({ name: 'branch a' });
  const branchB = makeJob({ name: 'branch b' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: null,
  };
  return {
    id: 'wf-6',
    name: 'branching jobs',
    jobs: [fanOut, branchA, branchB],
    triggers: [webhook],
    edges: [
      baseEdge({ source_trigger_id: webhook.id, target_job_id: fanOut.id }),
      baseEdge({
        source_job_id: fanOut.id,
        target_job_id: branchA.id,
        condition_type: 'on_job_success',
      }),
      baseEdge({
        source_job_id: fanOut.id,
        target_job_id: branchB.id,
        condition_type: 'on_job_failure',
      }),
    ],
    positions: null,
  };
};

export const SYNTHETIC_STATES: Array<{
  name: string;
  state: () => WorkflowState;
}> = [
  { name: 'simple-webhook', state: simpleWebhookState },
  { name: 'cron-with-cursor', state: cronWithCursorState },
  { name: 'js-expression-edge', state: jsExpressionEdgeState },
  { name: 'multi-trigger', state: multiTriggerState },
  { name: 'kafka-trigger', state: kafkaTriggerState },
  { name: 'branching-jobs', state: branchingJobsState },
];
