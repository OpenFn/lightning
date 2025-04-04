// State
export type StateJob = {
  id: string;
  name: string;
  adaptor: string;
  body: string;
};

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
  target_job_id?: string;
  enabled: boolean;
};

export type WorkflowState = {
  id: string;
  name: string;
  jobs: StateJob[];
  triggers: StateTrigger[];
  edges: StateEdge[];
};

// Spec
export type SpecJob = {
  name: string;
  adaptor: string;
  body: string;
};

export type SpecCronTrigger = {
  type: 'cron';
  enabled: boolean;
  cron_expression: string;
};

export type SpecWebhookTrigger = {
  type: 'webhook';
  enabled: boolean;
};

export type SpecKafkaTrigger = {
  type: 'kafka';
  enabled: boolean;
};

export type SpecTrigger =
  | SpecCronTrigger
  | SpecWebhookTrigger
  | SpecKafkaTrigger;

export type SpecEdge = {
  source_trigger?: string;
  source_job?: string;
  target_job: string;
  condition_type: string;
  condition_label?: string;
  condition_expression?: string | null;
  enabled: boolean;
};

export type WorkflowSpec = {
  name: string;
  jobs: Map<string, SpecJob>;
  triggers: Map<string, SpecTrigger>;
  edges: Map<string, SpecEdge>;
};
