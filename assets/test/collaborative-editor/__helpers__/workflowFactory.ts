/**
 * Workflow Test Factory
 *
 * Factory functions for creating Y.Doc instances with workflow data for testing.
 * These factories simplify the setup of workflow test scenarios with jobs, triggers,
 * and edges in Y.js collaborative documents.
 *
 * Usage:
 *   const ydoc = createWorkflowYDoc({
 *     jobs: { "job-a": { id: "job-a", name: "Job A", adaptor: "@openfn/language-common" } },
 *     edges: [{ id: "e1", source: "job-a", target: "job-b" }],
 *   });
 */

import * as Y from 'yjs';

/**
 * Input for creating a workflow Y.Doc with factory functions.
 * All fields are optional and can be partially specified.
 */
export interface CreateWorkflowInput {
  jobs?: Record<
    string,
    {
      id: string;
      name: string;
      adaptor: string;
      body?: string;
      project_credential_id?: string | null;
      keychain_credential_id?: string | null;
    }
  >;
  triggers?: Record<
    string,
    {
      id: string;
      type: string;
      enabled?: boolean;
    }
  >;
  edges?: Array<{
    id: string;
    source: string;
    target: string;
    condition_type?: string;
    condition_label?: string;
    condition_expression?: string;
    enabled?: boolean;
  }>;
}

/**
 * Creates a Y.Doc with a workflow containing specified jobs, triggers, and edges
 *
 * This helper creates a properly structured Y.Doc for testing workflow validation
 * and collaborative editing scenarios. The Y.Doc structure matches what the
 * WorkflowStore expects.
 *
 * @param config - Configuration object with jobs, triggers, and edges
 * @returns Y.Doc instance with workflow data
 *
 * @example
 * const ydoc = createWorkflowYDoc({
 *   jobs: {
 *     "job-a": { id: "job-a", name: "Job A", adaptor: "@openfn/language-common" },
 *     "job-b": { id: "job-b", name: "Job B", adaptor: "@openfn/language-common" },
 *   },
 *   edges: [
 *     { id: "edge-1", source: "job-a", target: "job-b", condition_type: "on_job_success" },
 *   ],
 * });
 */
export function createWorkflowYDoc(config: CreateWorkflowInput): Y.Doc {
  const ydoc = new Y.Doc();

  // Set up jobs
  const jobsArray = ydoc.getArray('jobs');
  if (config.jobs) {
    Object.entries(config.jobs).forEach(([_id, job]) => {
      const jobMap = new Y.Map();
      jobMap.set('id', job.id);
      jobMap.set('name', job.name);
      jobMap.set('adaptor', job.adaptor);
      if (job.body) {
        jobMap.set('body', new Y.Text(job.body));
      } else {
        jobMap.set('body', new Y.Text(''));
      }
      // Set credential fields explicitly - default to null if not provided
      jobMap.set('project_credential_id', job.project_credential_id ?? null);
      jobMap.set('keychain_credential_id', job.keychain_credential_id ?? null);
      jobsArray.push([jobMap]);
    });
  }

  // Set up triggers
  const triggersArray = ydoc.getArray('triggers');
  if (config.triggers) {
    Object.entries(config.triggers).forEach(([_id, trigger]) => {
      const triggerMap = new Y.Map();
      triggerMap.set('id', trigger.id);
      triggerMap.set('type', trigger.type);
      triggerMap.set('enabled', trigger.enabled ?? true);
      triggersArray.push([triggerMap]);
    });
  }

  // Set up edges
  const edgesArray = ydoc.getArray('edges');
  if (config.edges) {
    config.edges.forEach(edge => {
      const edgeMap = new Y.Map();
      edgeMap.set('id', edge.id);

      // Determine if source is a job or trigger by checking the config
      const isSourceTrigger = config.triggers?.[edge.source] !== undefined;
      if (isSourceTrigger) {
        edgeMap.set('source_trigger_id', edge.source);
      } else {
        edgeMap.set('source_job_id', edge.source);
      }

      // Target is always a job
      edgeMap.set('target_job_id', edge.target);

      edgeMap.set('condition_type', edge.condition_type || 'on_job_success');
      edgeMap.set('condition_label', edge.condition_label || null);
      edgeMap.set('condition_expression', edge.condition_expression || null);
      edgeMap.set('enabled', edge.enabled ?? true);
      edgesArray.push([edgeMap]);
    });
  }

  return ydoc;
}

/**
 * Creates a simple linear workflow: Trigger → Job A → Job B → Job C
 *
 * Useful for testing sequential workflow validation scenarios.
 *
 * @returns Y.Doc with linear workflow structure
 *
 * @example
 * const ydoc = createLinearWorkflowYDoc();
 * // Creates: trigger-1 → job-a → job-b → job-c
 */
export function createLinearWorkflowYDoc(): Y.Doc {
  return createWorkflowYDoc({
    triggers: {
      'trigger-1': { id: 'trigger-1', type: 'webhook' },
    },
    jobs: {
      'job-a': {
        id: 'job-a',
        name: 'Job A',
        adaptor: '@openfn/language-common',
      },
      'job-b': {
        id: 'job-b',
        name: 'Job B',
        adaptor: '@openfn/language-common',
      },
      'job-c': {
        id: 'job-c',
        name: 'Job C',
        adaptor: '@openfn/language-common',
      },
    },
    edges: [
      { id: 'e1', source: 'trigger-1', target: 'job-a' },
      { id: 'e2', source: 'job-a', target: 'job-b' },
      { id: 'e3', source: 'job-b', target: 'job-c' },
    ],
  });
}

/**
 * Creates a diamond workflow: A splits to B and C, both converge to D
 *
 * Useful for testing that diamond patterns (valid DAGs) are allowed while
 * preventing false-positive circular workflow detection.
 *
 * @returns Y.Doc with diamond workflow structure
 *
 * @example
 * const ydoc = createDiamondWorkflowYDoc();
 * // Creates: trigger-1 → job-a → job-b → job-d
 * //                           ↘ job-c ↗
 */
export function createDiamondWorkflowYDoc(): Y.Doc {
  return createWorkflowYDoc({
    triggers: {
      'trigger-1': { id: 'trigger-1', type: 'webhook' },
    },
    jobs: {
      'job-a': {
        id: 'job-a',
        name: 'Job A',
        adaptor: '@openfn/language-common',
      },
      'job-b': {
        id: 'job-b',
        name: 'Job B',
        adaptor: '@openfn/language-common',
      },
      'job-c': {
        id: 'job-c',
        name: 'Job C',
        adaptor: '@openfn/language-common',
      },
      'job-d': {
        id: 'job-d',
        name: 'Job D',
        adaptor: '@openfn/language-common',
      },
    },
    edges: [
      { id: 'e1', source: 'trigger-1', target: 'job-a' },
      { id: 'e2', source: 'job-a', target: 'job-b' },
      { id: 'e3', source: 'job-a', target: 'job-c' },
      { id: 'e4', source: 'job-b', target: 'job-d' },
      { id: 'e5', source: 'job-c', target: 'job-d' },
    ],
  });
}
