import { BaseTemplate } from '../types/template';

export const BASE_TEMPLATES: BaseTemplate[] = [
  {
    id: 'base-webhook-template',
    name: 'Event-based workflow',
    description: 'Trigger a workflow with a webhook or API call',
    tags: ['webhook', 'api', 'event'],
    isBase: true,
    code: `name: "Event-based workflow"
jobs:
  My-job:
    name: Validate & transform data
    adaptor: "@openfn/language-common@latest"
    body: |
      // Start writing your job code here
      fn(state => {
        console.log("Do some data transformation here");
        return state;
      })
triggers:
  webhook:
    type: webhook
    enabled: true
edges:
  webhook->My-job:
    source_trigger: webhook
    target_job: My-job
    condition_type: always
    enabled: true`,
  },
  {
    id: 'base-cron-template',
    name: 'Scheduled workflow',
    description: 'Run a workflow on a schedule using cron',
    tags: ['cron', 'scheduled', 'timer'],
    isBase: true,
    code: `name: "Scheduled workflow"
jobs:
  My-job:
    name: Get data
    adaptor: "@openfn/language-http@latest"
    body: |
      // Start writing your job code here
      get('www.example.com');
triggers:
  cron:
    type: cron
    cron_expression: "0 0 * * *"
    enabled: true
edges:
  cron->My-job:
    source_trigger: cron
    target_job: My-job
    condition_type: always
    enabled: true`,
  },
];
