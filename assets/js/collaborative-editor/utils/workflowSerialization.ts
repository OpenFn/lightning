import YAML from 'yaml';

import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { convertWorkflowStateToSpec } from '../../yaml/util';

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
      false
    );

    return YAML.stringify(workflowSpec);
  } catch (error) {
    console.error('Failed to serialize workflow to YAML:', error);
    return undefined;
  }
}
