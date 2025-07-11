import type {
  WorkflowState,
  SpecJob,
  SpecTrigger,
  SpecEdge,
  StateJob,
  StateTrigger,
  StateEdge,
  WorkflowSpec,
} from './types';
import { randomUUID } from '../common';
import workflowV1Schema from './schema/workflow-spec.json';
import YAML from 'yaml';
import Ajv, { type ErrorObject } from 'ajv';

const hyphenate = (str: string) => {
  return str.replace(/\s+/g, '-');
};

export const convertWorkflowStateToSpec = (
  workflowState: WorkflowState
): WorkflowSpec => {
  const jobs: { [key: string]: SpecJob } = {};
  workflowState.jobs.forEach(job => {
    const jobDetails: SpecJob = {
      id: job.id,
      name: job.name,
      adaptor: job.adaptor,
      body: job.body
    };
    jobs[hyphenate(job.name)] = jobDetails;
  });

  const triggers: { [key: string]: SpecTrigger } = {};
  workflowState.triggers.forEach(trigger => {
    const triggerDetails: SpecTrigger = {
      id: trigger.id,
      type: trigger.type,
      enabled: trigger.enabled
    } as SpecTrigger;
    
    if (trigger.type === 'cron' && 'cron_expression' in trigger) {
      (triggerDetails as any).cron_expression = trigger.cron_expression;
    }
    // TODO: handle kafka config
    triggers[trigger.type] = triggerDetails;
  });

  const edges: { [key: string]: SpecEdge } = {};
  workflowState.edges.forEach(edge => {
    const edgeDetails: SpecEdge = {
      id: edge.id,
      condition_type: edge.condition_type,
      enabled: edge.enabled,
      target_job: ''
    };

    if (edge.source_trigger_id) {
      const trigger = workflowState.triggers.find(
        trigger => trigger.id === edge.source_trigger_id
      );
      if (trigger) {
        edgeDetails.source_trigger = trigger.type;
      }
    }
    if (edge.source_job_id) {
      const job = workflowState.jobs.find(job => job.id === edge.source_job_id);
      if (job) {
        edgeDetails.source_job = hyphenate(job.name);
      }
    }
    const targetJob = workflowState.jobs.find(
      job => job.id === edge.target_job_id
    );
    if (targetJob) {
      edgeDetails.target_job = hyphenate(targetJob.name);
    }

    if (edge.condition_label) {
      edgeDetails.condition_label = edge.condition_label;
    }
    if (edge.condition_expression) {
      edgeDetails.condition_expression = edge.condition_expression;
    }

    const source_name = edgeDetails.source_trigger || edgeDetails.source_job;
    const target_name = edgeDetails.target_job;

    edges[`${source_name}->${target_name}`] = edgeDetails;
  });

  const workflowSpec: WorkflowSpec = {
    id: workflowState.id,
    name: workflowState.name,
    jobs: jobs,
    triggers: triggers,
    edges: edges
  };

  return workflowSpec;
};

export const convertWorkflowSpecToState = (
  workflowSpec: WorkflowSpec
): WorkflowState => {
  const stateJobs: Record<string, StateJob> = {};
  Object.entries(workflowSpec.jobs).forEach(([key, specJob]) => {
    stateJobs[key] = {
      id: specJob.id || randomUUID(),
      name: specJob.name,
      adaptor: specJob.adaptor,
      body: specJob.body,
    };
  });

  const stateTriggers: Record<string, StateTrigger> = {};
  Object.entries(workflowSpec.triggers).forEach(([key, specTrigger]) => {
    const trigger = {
      id: specTrigger.id || randomUUID(),
      type: specTrigger.type,
      enabled: specTrigger.enabled !== undefined ? specTrigger.enabled : true,
    };

    if (specTrigger.type === 'cron') {
      trigger.cron_expression = specTrigger.cron_expression;
    }

    // TODO: handle kafka config

    stateTriggers[key] = trigger;
  });

  const stateEdges: Record<string, StateEdge> = {};
  Object.entries(workflowSpec.edges).forEach(([key, specEdge]) => {
    const targetJob = stateJobs[specEdge.target_job];
    if (!targetJob) {
      throw new Error(
        `TargetJob: '${specEdge.target_job}' specified by edge '${key}' not found in spec`
      );
    }

    const edge: StateEdge = {
      id: specEdge.id || randomUUID(),
      condition_type: specEdge.condition_type,
      enabled: specEdge.enabled,
      target_job_id: targetJob.id,
    };

    if (specEdge.source_trigger) {
      const trigger = stateTriggers[specEdge.source_trigger];
      if (!trigger) {
        throw new Error(
          `SourceTrigger: '${specEdge.source_trigger}' specified by edge '${key}' not found in spec`
        );
      }
      edge.source_trigger_id = trigger.id;
    }

    if (specEdge.source_job) {
      const job = stateJobs[specEdge.source_job];
      if (!job) {
        throw new Error(
          `SourceJob: '${specEdge.source_job}' specified by edge '${key}' not found in spec`
        );
      }
      edge.source_job_id = job.id;
    }

    if (specEdge.condition_label) {
      edge.condition_label = specEdge.condition_label;
    }

    if (specEdge.condition_expression) {
      edge.condition_expression = specEdge.condition_expression;
    }

    stateEdges[key] = edge;
  });

  const workflowState: WorkflowState = {
    id: workflowSpec.id || randomUUID(),
    name: workflowSpec.name,
    jobs: Object.values(stateJobs),
    edges: Object.values(stateEdges),
    triggers: Object.values(stateTriggers),
  };

  return workflowState;
};

export const parseWorkflowYAML = (yamlString: string): WorkflowSpec => {
  const ajv = new Ajv({ allErrors: true });
  const validate = ajv.compile(workflowV1Schema);

  // throw error one at a time
  const parsedYAML = YAML.parse(yamlString);

  const isSchemaValid = validate(parsedYAML);

  if (!isSchemaValid) {
    const error = findActionableAjvError(validate.errors);

    throw new Error(humanizeAjvError(error));
  }

  // Validate job names
  Object.entries(parsedYAML['jobs']).reduce(
    (acc, [key, specJob]: [string, object]) => {
      if (acc[specJob.name]) {
        throw new Error(
          `Duplicate job name '${specJob.name}' found at 'jobs/${key}'`
        );
      }
      acc[specJob.name] = true;
      return acc;
    },
    {}
  );

  return parsedYAML as WorkflowSpec;
};

export const parseWorkflowTemplate = (code: string): WorkflowSpec => {
  const parsedYAML = YAML.parse(code);

  return parsedYAML as WorkflowSpec;
};

const humanizeAjvError = (error: ErrorObject): string => {
  switch (error.keyword) {
    case 'required':
      return `Missing required property '${error.params.missingProperty}' at ${error.instancePath}`;
    case 'additionalProperties':
      return `Unknown property '${error.params.additionalProperty}' at ${error.instancePath}`;
    case 'enum':
      return `Invalid value at ${error.instancePath}. Allowed values are: '${error.params.allowedValues}'`;
    default:
      return `${error.message} at ${error.instancePath}`;
  }
};

const findActionableAjvError = (
  errors: ErrorObject[]
): ErrorObject | undefined => {
  const requiredError = errors.find(error => error.keyword === 'required');
  const additionalPropertiesError = errors.find(
    error => error.keyword === 'additionalProperties'
  );
  const typeError = errors.find(error => error.keyword === 'type');
  const enumError = errors.find(error => error.keyword === 'enum');

  return (
    enumError ||
    additionalPropertiesError ||
    requiredError ||
    typeError ||
    errors[0]
  );
};