import YAML from 'yaml';

import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { convertWorkflowStateToSpec } from '../../yaml/util';

interface WorkflowMetadata {
  id: string;
  name: string;
}

export interface SerializableWorkflow {
  id: string;
  name: string;
  jobs: Array<{
    id: string;
    name: string;
    adaptor: string;
    body: string;
  }>;
  triggers: YAMLWorkflowState['triggers'];
  edges: Array<{
    id: string;
    condition_type: string;
    enabled: boolean;
    target_job_id: string;
    source_job_id?: string;
    source_trigger_id?: string;
    condition_label?: string;
    condition_expression?: string;
  }>;
  positions: YAMLWorkflowState['positions'];
}

/**
 * Prepares workflow data from store state for serialization.
 *
 * This function transforms the loosely-typed workflow store state into the
 * strongly-typed format expected by serializeWorkflowToYAML. It handles the
 * conversion of jobs and edges from unknown[] to their proper types.
 *
 * @param workflow - Basic workflow metadata (id, name)
 * @param jobs - Array of job objects from workflow store
 * @param triggers - Array of trigger objects from workflow store
 * @param edges - Array of edge objects from workflow store
 * @param positions - Position data for workflow nodes
 * @returns SerializableWorkflow or null if workflow has no jobs
 */
export function prepareWorkflowForSerialization(
  workflow: WorkflowMetadata | null,
  jobs: unknown[],
  triggers: unknown[],
  edges: unknown[],
  positions: unknown
): SerializableWorkflow | null {
  if (!workflow || jobs.length === 0) {
    return null;
  }

  return {
    id: workflow.id,
    name: workflow.name,
    jobs: jobs.map((job: unknown) => {
      const j = job as Record<string, unknown>;
      return {
        id: String(j['id']),
        name: String(j['name']),
        adaptor: String(j['adaptor']),
        body: String(j['body']),
      };
    }),
    triggers: triggers as YAMLWorkflowState['triggers'],
    edges: edges.map((edge: unknown) => {
      const e = edge as Record<string, unknown>;
      const conditionType = e['condition_type'];
      const result: SerializableWorkflow['edges'][number] = {
        id: String(e['id']),
        condition_type:
          conditionType && typeof conditionType === 'string'
            ? conditionType
            : 'always',
        enabled: e['enabled'] !== false,
        target_job_id: String(e['target_job_id']),
      };

      const sourceJobId = e['source_job_id'];
      if (sourceJobId && typeof sourceJobId === 'string') {
        result.source_job_id = sourceJobId;
      }
      const sourceTriggerId = e['source_trigger_id'];
      if (sourceTriggerId && typeof sourceTriggerId === 'string') {
        result.source_trigger_id = sourceTriggerId;
      }
      const conditionLabel = e['condition_label'];
      if (conditionLabel && typeof conditionLabel === 'string') {
        result.condition_label = conditionLabel;
      }
      const conditionExpression = e['condition_expression'];
      if (conditionExpression && typeof conditionExpression === 'string') {
        result.condition_expression = conditionExpression;
      }

      return result;
    }),
    positions: positions as YAMLWorkflowState['positions'],
  };
}

/**
 * Serializes a workflow to YAML format for AI Assistant context.
 *
 * This utility converts the workflow state from the Zustand store into YAML format
 * that can be sent to the AI Assistant as context. It's used in multiple places:
 * - Initial session connection with workflow context
 * - Sending messages with updated workflow state
 * - Creating new conversations
 * - Switching between sessions
 *
 * @param workflow - The workflow data including jobs, triggers, edges, and positions
 * @returns YAML string representation of the workflow, or undefined if serialization fails
 *
 * @example
 * ```ts
 * const yaml = serializeWorkflowToYAML({
 *   id: workflow.id,
 *   name: workflow.name,
 *   jobs: jobs.map(job => ({ id: job.id, name: job.name, adaptor: job.adaptor, body: job.body })),
 *   triggers: triggers,
 *   edges: edges,
 *   positions: positions
 * });
 * ```
 */
export function serializeWorkflowToYAML(
  workflow: SerializableWorkflow
): string | undefined {
  try {
    const workflowSpec = convertWorkflowStateToSpec(
      {
        id: workflow.id,
        name: workflow.name,
        jobs: workflow.jobs,
        triggers: workflow.triggers,
        edges: workflow.edges.map(edge => ({
          id: edge.id,
          condition_type: edge.condition_type || 'always',
          enabled: edge.enabled !== false,
          target_job_id: edge.target_job_id,
          ...(edge.source_job_id && {
            source_job_id: edge.source_job_id,
          }),
          ...(edge.source_trigger_id && {
            source_trigger_id: edge.source_trigger_id,
          }),
          ...(edge.condition_label && {
            condition_label: edge.condition_label,
          }),
          ...(edge.condition_expression && {
            condition_expression: edge.condition_expression,
          }),
        })),
        positions: workflow.positions,
      },
      true // Include IDs so AI responses preserve them (matches legacy behavior)
    );

    return YAML.stringify(workflowSpec);
  } catch (error) {
    console.error('Failed to serialize workflow to YAML:', error);
    return undefined;
  }
}
