import { type BaseTemplate } from '../types/template';

/**
 * The workflow seeded by the "Build from scratch" landing-screen card:
 * a single webhook trigger, one "Untitled step" job on
 * `@openfn/language-common@latest`, and an always-on edge between them.
 *
 * `name` is intentionally left blank so `validateWorkflowName` (via
 * `importWorkflow`) applies the server's "Untitled workflow" default and
 * dedup suffixing, the same way `create_webhook_workflow` used to.
 */
export const BLANK_WORKFLOW_YAML = `name: ""
jobs:
  Untitled-step:
    name: Untitled step
    adaptor: "@openfn/language-common@latest"
    body: |
      // Check out the Job Writing Guide for help getting started:
      // https://docs.openfn.org/documentation/jobs/job-writing-guide
triggers:
  webhook:
    type: webhook
    enabled: true
edges:
  webhook->Untitled-step:
    source_trigger: webhook
    target_job: Untitled-step
    condition_type: always
    enabled: true`;

export const BASE_TEMPLATES: BaseTemplate[] = [
  {
    id: 'base-webhook-template',
    name: 'Event-based workflow',
    description:
      'A basic template for a workflow that does something on-demand, when a webhook notification is received.',
    tags: ['webhook', 'api', 'event', 'real-time'],
    isBase: true,
    code: `name: "Event-based workflow"
jobs:
  Transform-data:
    name: Transform data
    adaptor: "@openfn/language-common@latest"
    body: |
      // Validate and transform the data you've received...
      fn(state => {
        console.log("Do some data transformation here");
        return state;
      })
triggers:
  webhook:
    type: webhook
    enabled: true
edges:
  webhook->Transform-data:
    source_trigger: webhook
    target_job: Transform-data
    condition_type: always
    enabled: true`,
  },
  {
    id: 'base-cron-template',
    name: 'Scheduled workflow',
    description:
      'A basic template for a workflow that does something periodically, using a "cron" schedule.',
    tags: ['cron', 'scheduled', 'timer', 'periodic'],
    isBase: true,
    code: `name: "Scheduled workflow"
jobs:
  Get-data:
    name: Get data
    adaptor: "@openfn/language-http@latest"
    body: |
      // Get some data from an API...
      get('https://www.example.com');
triggers:
  cron:
    type: cron
    cron_expression: "0 0 * * *"
    enabled: true
edges:
  cron->Get-data:
    source_trigger: cron
    target_job: Get-data
    condition_type: always
    enabled: true`,
  },
];
