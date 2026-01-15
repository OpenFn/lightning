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
};

export type StateWebhookTrigger = {
  id: string;
  enabled: boolean;
  type: 'webhook';
};

export type StateKafkaTrigger = {
  id: string;
  enabled: boolean;
  type: 'kafka';
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
  pos: Position | undefined;
};

export type SpecWebhookTrigger = {
  id?: string;
  type: 'webhook';
  enabled: boolean;
  pos: Position | undefined;
};

export type SpecKafkaTrigger = {
  id?: string;
  type: 'kafka';
  enabled: boolean;
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
