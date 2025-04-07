import type {
  WorkflowState,
  SpecJob,
  SpecTrigger,
  SpecEdge,
  WorkflowSpec,
} from './types';

const hyphenate = (str: string) => {
  return str.replace(/\s+/g, '-');
};

export const convertWorkflowStateToSpec = (
  workflowState: WorkflowState
): WorkflowSpec => {
  const jobs: { [key: string]: SpecJob } = {};
  workflowState.jobs.forEach(job => {
    const jobDetails: SpecJob = {} as SpecJob;
    jobDetails.name = job.name;
    jobDetails.adaptor = job.adaptor;
    jobDetails.body = job.body;
    jobs[hyphenate(job.name)] = jobDetails;
  });

  const triggers: { [key: string]: SpecTrigger } = {};
  workflowState.triggers.forEach(trigger => {
    const triggerDetails: SpecTrigger = {} as SpecTrigger;
    triggerDetails.type = trigger.type;
    if (trigger.cron_expression) {
      triggerDetails.cron_expression = trigger.cron_expression;
    }
    triggerDetails.enabled = trigger.enabled;
    // TODO: handle kafka config
    triggers[trigger.type] = triggerDetails;
  });

  const edges: { [key: string]: SpecEdge } = {};
  workflowState.edges.forEach(edge => {
    const edgeDetails: SpecEdge = {} as SpecEdge;

    if (edge.source_trigger_id) {
      const trigger = workflowState.triggers.find(
        trigger => trigger.id === edge.source_trigger_id
      );
      edgeDetails.source_trigger = trigger.type;
    }
    if (edge.source_job_id) {
      const job = workflowState.jobs.find(job => job.id === edge.source_job_id);
      edgeDetails.source_job = hyphenate(job.name);
    }
    const targetJob = workflowState.jobs.find(
      job => job.id === edge.target_job_id
    );
    edgeDetails.target_job = hyphenate(targetJob.name);
    edgeDetails.condition_type = edge.condition_type;

    if (edge.condition_label) {
      edgeDetails.condition_label = edge.condition_label;
    }
    if (edge.condition_expression) {
      edgeDetails.condition_expression = edge.condition_expression;
    }

    edgeDetails.enabled = edge.enabled;

    const source_name = edgeDetails.source_trigger || edgeDetails.source_job;
    const target_name = edgeDetails.target_job;

    edges[`${source_name}->${target_name}`] = edgeDetails;
  });

  const workflowSpec: WorkflowSpec = {} as WorkflowSpec;
  workflowSpec.name = workflowState.name;
  workflowSpec.jobs = jobs;
  workflowSpec.triggers = triggers;
  workflowSpec.edges = edges;

  return workflowSpec;
};
