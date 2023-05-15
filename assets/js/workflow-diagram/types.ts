// This all describes the lightning view of a workflow

export interface Node {
  id: string;
  name: string;
  workflowId: string;
}

type CronTrigger = {
  type: 'cron';
  cronExpression: string;
};

type WebhookTrigger = {
  type: 'webhook';
  webhookUrl: string;
};

export interface TriggerNode extends Node {
  trigger: CronTrigger | WebhookTrigger;
}

export interface JobNode extends Node {}

export interface Edge {
  id: string;
  source_job_id?: string;
  source_trigger_id?: string;
  target_job_id?: string;
  name: string;
  condition?: string;
  error_path?: boolean;
  errors: any;
}

export type Workflow = {
  id: string;
  changeId?: string;
  triggers: TriggerNode[];
  jobs: JobNode[];
  edges: Edge[];
};
