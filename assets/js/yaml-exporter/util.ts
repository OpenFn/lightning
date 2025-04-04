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
  const jobs = new Map<string, SpecJob>();
  workflowState.jobs.forEach(job => {
    const jobDetails = new Map();
    jobDetails.set('name', job.name);
    jobDetails.set('adaptor', job.adaptor);
    jobDetails.set('body', job.body);
    jobs.set(hyphenate(job.name), jobDetails);
  });

  const triggers = new Map<string, SpecTrigger>();
  workflowState.triggers.forEach(trigger => {
    const triggerDetails = new Map();
    triggerDetails.set('type', trigger.type);
    if (trigger.cron_expression) {
      triggerDetails.set('cron_expression', trigger.cron_expression);
    }
    triggerDetails.set('enabled', trigger.enabled);
    // handle kafka config
    triggers.set(trigger.type, triggerDetails);
  });

  const edges = new Map<string, SpecEdge>();
  workflowState.edges.forEach(edge => {
    const edgeDetails = new Map();

    if (edge.source_trigger_id) {
      const trigger = workflowState.triggers.find(
        trigger => trigger.id === edge.source_trigger_id
      );
      edgeDetails.set('source_trigger', trigger.type);
    }
    if (edge.source_job_id) {
      const job = workflowState.jobs.find(job => job.id === edge.source_job_id);
      edgeDetails.set('source_job', hyphenate(job.name));
    }
    const targetJob = workflowState.jobs.find(
      job => job.id === edge.target_job_id
    );
    edgeDetails.set('target_job', hyphenate(targetJob.name));
    edgeDetails.set('condition_type', edge.condition_type);

    if (edge.condition_label) {
      edgeDetails.set('condition_label', edge.condition_label);
    }
    if (edge.condition_expression) {
      edgeDetails.set('condition_expression', edge.condition_expression);
    }

    edgeDetails.set('enabled', edge.enabled);

    const source_name =
      edgeDetails.get('source_trigger') || edgeDetails.get('source_job');
    const target_name = edgeDetails.get('target_job');

    edges.set(`${source_name}->${target_name}`, edgeDetails);
  });

  const workflowSpec = new Map();
  workflowSpec.set('name', workflowState.name);
  workflowSpec.set('jobs', jobs);
  workflowSpec.set('triggers', triggers);
  workflowSpec.set('edges', edges);

  return workflowSpec as WorkflowSpec;
};
