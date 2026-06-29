// v1 (Lightning legacy) YAML format — PARSE-ONLY.
//
// This module owns the v1 parse path so existing v1 YAML files (canvas Code
// panel exports, customer YAML files, legacy WorkflowTemplate rows) continue
// to import. **There is no v1 serializer in this codebase**: per Phase 4 of
// #4718, all outbound YAML emits v2 via `./v2.ts` (use `./format.ts` for the
// public API).
//
// See plan #4718.

import Ajv, { type ErrorObject } from 'ajv';
import YAML from 'yaml';

import type { Workflow } from '../collaborative-editor/types/workflow';
import { randomUUID } from '../common';

import workflowV1Schema from './schema/workflow-spec.json';
import type {
  JobCredentials,
  Position,
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
      const cursorJob = specTrigger.cron_cursor_job
        ? (stateJobs[specTrigger.cron_cursor_job] ?? null)
        : null;
      trigger = {
        id: uId,
        type: 'cron',
        enabled,
        cron_expression: specTrigger.cron_expression,
        cron_cursor_job_id: cursorJob ? cursorJob.id : null,
      };
    } else if (specTrigger.type === 'webhook') {
      trigger = {
        id: uId,
        type: 'webhook',
        enabled,
        webhook_reply: specTrigger.webhook_reply,
        ...(specTrigger.webhook_response_config
          ? { webhook_response_config: specTrigger.webhook_response_config }
          : {}),
      };
    } else {
      trigger = {
        id: uId,
        type: 'kafka',
        enabled,
        ...(specTrigger.kafka_configuration
          ? { kafka_configuration: specTrigger.kafka_configuration }
          : {}),
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
    job.keychain_credential_id =
      credentials[job.id]?.keychain_credential_id ?? null;
    job.project_credential_id =
      credentials[job.id]?.project_credential_id ?? null;
  }
  return state;
};

/**
 * Parse a v1 workflow YAML string. Validates against the v1 AJV schema.
 *
 * Use the format-aware `parseWorkflow` from `./format` for new code that
 * should accept either v1 or v2.
 */
export const parseWorkflowYAML = (yamlString: string): WorkflowSpec => {
  try {
    const parsedYAML = YAML.parse(yamlString);
    return parseWorkflow(parsedYAML);
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

/**
 * Validate an already-parsed v1 document and return its `WorkflowSpec`.
 *
 * This is the v1 entry point used by the format façade in `./format` after
 * format detection. Callers that already have a `YAML.parse(...)`'d map should
 * prefer this over `parseWorkflowYAML`.
 */
export const parseWorkflow = (parsedMap: unknown): WorkflowSpec => {
  const ajv = new Ajv({ allErrors: true });
  const validate = ajv.compile(workflowV1Schema);
  const isSchemaValid = validate(parsedMap);

  if (!isSchemaValid && validate.errors) {
    const error = findActionableAjvError(validate.errors);
    if (error) {
      throw new SchemaValidationError(error);
    }
  }

  // Validate job names — at this point the schema has confirmed `jobs` is an
  // object keyed by string, so this cast is safe.
  const parsed = parsedMap as { jobs: Record<string, { name: string }> };
  const seenNames: Record<string, boolean> = {};
  Object.entries(parsed['jobs']).forEach(([key, specJob]) => {
    if (seenNames[specJob.name]) {
      throw new DuplicateJobNameError(specJob.name, key);
    }
    seenNames[specJob.name] = true;
  });

  return parsedMap as WorkflowSpec;
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
