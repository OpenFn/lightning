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
  label: string;
  error_path: boolean;
  condition: string;
  source_job?: string;
  source_trigger?: string;
  target_job?: string;
}

export type Workflow = {
  id: string;
  changeId?: string;
  triggers: TriggerNode[];
  jobs: JobNode[];
  edges: Edge[];
};
