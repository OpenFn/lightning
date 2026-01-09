import Ajv, { type ErrorObject } from 'ajv';
import YAML from 'yaml';

import type { Workflow } from '../collaborative-editor/types/workflow';
import { randomUUID } from '../common';

import workflowV1Schema from './schema/workflow-spec.json';
import type {
  JobCredentials,
  Position,
  SpecEdge,
  SpecJob,
  SpecTrigger,
  StateEdge,
  StateJob,
  StateTrigger,
  WorkflowSpec,
  WorkflowState,
} from './types';
import {
  WorkflowError,
  YamlSyntaxError,
  JobNotFoundError,
  TriggerNotFoundError,
  DuplicateJobNameError,
  SchemaValidationError,
  createWorkflowError,
} from './workflow-errors';

const hyphenate = (str: string) => {
  return str.replace(/\s+/g, '-');
};

const roundPosition = (pos: Position): Position => {
  return {
    x: Math.round(pos.x),
    y: Math.round(pos.y),
  };
};

export const convertWorkflowStateToSpec = (
  workflowState: WorkflowState,
  includeIds: boolean = true
): WorkflowSpec => {
  const jobs: { [key: string]: SpecJob } = {};
  workflowState.jobs.forEach(job => {
    const pos = workflowState.positions?.[job.id];
    const jobDetails: SpecJob = {
      ...(includeIds && { id: job.id }),
      name: job.name,
      adaptor: job.adaptor,
      body: job.body,
      pos: pos ? roundPosition(pos) : undefined,
    };
    jobs[hyphenate(job.name)] = jobDetails;
  });

  const triggers: { [key: string]: SpecTrigger } = {};
  workflowState.triggers.forEach(trigger => {
    const pos = workflowState.positions?.[trigger.id];
    const triggerDetails: SpecTrigger = {
      ...(includeIds && { id: trigger.id }),
      type: trigger.type,
      enabled: trigger.enabled,
      pos: trigger.type !== 'kafka' && pos ? roundPosition(pos) : undefined,
      cron_expression:
        trigger.type === 'cron' && 'cron_expression' in trigger
          ? trigger.cron_expression
          : undefined,
    } as SpecTrigger;

    // TODO: handle kafka config
    triggers[trigger.type] = triggerDetails;
  });

  const edges: { [key: string]: SpecEdge } = {};
  workflowState.edges.forEach(edge => {
    const edgeDetails: SpecEdge = {
      ...(includeIds && { id: edge.id }),
      condition_type: edge.condition_type,
      enabled: edge.enabled,
      target_job: '',
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
    ...(includeIds && { id: workflowState.id }),
    name: workflowState.name,
    jobs: jobs,
    triggers: triggers,
    edges: edges,
  };

  return workflowSpec;
};

export const convertWorkflowSpecToState = (
  workflowSpec: WorkflowSpec
): WorkflowState => {
  const positions: Record<string, Position> = {};
  const stateJobs: Record<string, StateJob> = {};
  Object.entries(workflowSpec.jobs).forEach(([key, specJob]) => {
    const uId = specJob.id || randomUUID();
    stateJobs[key] = {
      id: uId,
      name: specJob.name,
      adaptor: specJob.adaptor,
      body: specJob.body,
    };
    if (specJob.pos) positions[uId] = specJob.pos;
  });

  const stateTriggers: Record<string, StateTrigger> = {};
  Object.entries(workflowSpec.triggers).forEach(([key, specTrigger]) => {
    const uId = specTrigger.id || randomUUID();
    const enabled =
      specTrigger.enabled !== undefined ? specTrigger.enabled : true;

    if (specTrigger.type !== 'kafka' && specTrigger.pos) {
      positions[uId] = specTrigger.pos;
    }

    let trigger: StateTrigger;
    if (specTrigger.type === 'cron') {
      trigger = {
        id: uId,
        type: 'cron',
        enabled,
        cron_expression: specTrigger.cron_expression,
      };
    } else if (specTrigger.type === 'webhook') {
      trigger = {
        id: uId,
        type: 'webhook',
        enabled,
      };
    } else {
      trigger = {
        id: uId,
        type: 'kafka',
        enabled,
      };
    }

    stateTriggers[key] = trigger;
  });

  const stateEdges: Record<string, StateEdge> = {};
  Object.entries(workflowSpec.edges).forEach(([key, specEdge]) => {
    const targetJob = stateJobs[specEdge.target_job];
    if (!targetJob) {
      throw new JobNotFoundError(specEdge.target_job, key, false);
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
        throw new TriggerNotFoundError(specEdge.source_trigger, key);
      }
      edge.source_trigger_id = trigger.id;
    }

    if (specEdge.source_job) {
      const job = stateJobs[specEdge.source_job];
      if (!job) {
        throw new JobNotFoundError(specEdge.source_job, key, true);
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
    positions: Object.keys(positions).length ? positions : null, // null here is super important - don't mess with it
  };

  return workflowState;
};

export const extractJobCredentials = (jobs: Workflow.Job[]): JobCredentials => {
  const credentials: JobCredentials = {};
  for (const job of jobs) {
    credentials[job.id] = {
      keychain_credential_id: job.keychain_credential_id,
      project_credential_id: job.project_credential_id,
    };
  }
  return credentials;
};

export const applyJobCredsToWorkflowState = (
  state: WorkflowState,
  credentials: JobCredentials
) => {
  for (const job of state.jobs) {
    job.keychain_credential_id = credentials[job.id]?.keychain_credential_id;
    job.project_credential_id = credentials[job.id]?.project_credential_id;
  }
  return state;
};

export const parseWorkflowYAML = (yamlString: string): WorkflowSpec => {
  try {
    const parsedYAML = YAML.parse(yamlString);

    const ajv = new Ajv({ allErrors: true });
    const validate = ajv.compile(workflowV1Schema);
    const isSchemaValid = validate(parsedYAML);

    if (!isSchemaValid && validate.errors) {
      const error = findActionableAjvError(validate.errors);
      if (error) {
        throw new SchemaValidationError(error);
      }
    }

    // Validate job names
    const seenNames: Record<string, boolean> = {};
    Object.entries(parsedYAML['jobs']).forEach(
      ([key, specJob]: [string, any]) => {
        if (seenNames[specJob.name]) {
          throw new DuplicateJobNameError(specJob.name, key);
        }
        seenNames[specJob.name] = true;
      }
    );

    return parsedYAML as WorkflowSpec;
  } catch (error) {
    // If it's already one of our errors, re-throw it
    if (error instanceof WorkflowError) {
      throw error;
    }

    // If it's a YAML parsing error
    if (error instanceof Error && error.name === 'YAMLParseError') {
      throw new YamlSyntaxError(error.message, error);
    }

    // For any other error, create a workflow error
    throw createWorkflowError(error);
  }
};

export const parseWorkflowTemplate = (code: string): WorkflowSpec => {
  try {
    const parsedYAML = YAML.parse(code);
    return parsedYAML as WorkflowSpec;
  } catch (error) {
    if (error instanceof Error && error.name === 'YAMLParseError') {
      throw new YamlSyntaxError(error.message, error);
    }
    throw createWorkflowError(error);
  }
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
