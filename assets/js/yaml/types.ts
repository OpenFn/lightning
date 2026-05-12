// State
export type StateJob = {
  id: string;
  name: string;
  adaptor: string;
  body: string;
  keychain_credential_id: string | null;
  project_credential_id: string | null;
};

export type JobCredentials = Record<
  string,
  {
    project_credential_id: string | null;
    keychain_credential_id: string | null;
  }
>;

export type StateCronTrigger = {
  id: string;
  type: 'cron';
  enabled: boolean;
  cron_expression: string;
  cron_cursor_job_id: string | null;
};

export type StateWebhookTrigger = {
  id: string;
  enabled: boolean;
  type: 'webhook';
  webhook_reply: 'before_start' | 'after_completion' | 'custom' | null;
};

/**
 * Kafka configuration carried on a `StateKafkaTrigger`.
 *
 * Mirrors the shape the workflow store hydrates from Y.Doc (which the Elixir
 * `Lightning.Collaboration.WorkflowSerializer` populates from
 * `Triggers.KafkaConfiguration`): hosts and topics live as comma-separated
 * `_string` form on state, and become flat lists in the portability format.
 *
 * `connect_timeout` is in seconds (matches the Elixir schema default of 30).
 */
export type StateKafkaConfiguration = {
  hosts_string: string;
  topics_string: string;
  initial_offset_reset_policy: string;
  connect_timeout: number;
  group_id?: string | null;
  sasl?: string | null;
  ssl?: boolean;
  username?: string | null;
  password?: string | null;
};

export type StateKafkaTrigger = {
  id: string;
  enabled: boolean;
  type: 'kafka';
  kafka_configuration?: StateKafkaConfiguration | null;
};

export type StateTrigger =
  | StateCronTrigger
  | StateWebhookTrigger
  | StateKafkaTrigger;

export type StateEdge = {
  id: string;
  condition_type: string;
  condition_label?: string;
  condition_expression?: string | null;
  source_job_id?: string;
  source_trigger_id?: string;
  target_job_id: string;
  enabled: boolean;
};

export type Position = {
  x: number;
  y: number;
};

export type StatePositions = Record<string, Position>;

export type WorkflowState = {
  id: string;
  name: string;
  jobs: StateJob[];
  triggers: StateTrigger[];
  edges: StateEdge[];
  positions: StatePositions | null;
};

// Spec
export type SpecJob = {
  id?: string;
  name: string;
  adaptor: string;
  body: string;
  pos: Position | undefined;
};

export type SpecCronTrigger = {
  id?: string;
  type: 'cron';
  enabled: boolean;
  cron_expression: string;
  cron_cursor_job: string | null;
  pos: Position | undefined;
};

export type SpecWebhookTrigger = {
  id?: string;
  type: 'webhook';
  enabled: boolean;
  webhook_reply: string | null;
  pos: Position | undefined;
};

export type SpecKafkaTrigger = {
  id?: string;
  type: 'kafka';
  enabled: boolean;
  kafka_configuration?: StateKafkaConfiguration | null;
};

export type SpecTrigger =
  | SpecCronTrigger
  | SpecWebhookTrigger
  | SpecKafkaTrigger;

export type SpecEdge = {
  id?: string;
  source_trigger?: string;
  source_job?: string;
  target_job: string;
  condition_type: string;
  condition_label?: string;
  condition_expression?: string | null;
  enabled: boolean;
};

export type WorkflowSpec = {
  id?: string;
  name: string;
  jobs: Record<string, SpecJob>;
  triggers: Record<string, SpecTrigger>;
  edges: Record<string, SpecEdge>;
};
