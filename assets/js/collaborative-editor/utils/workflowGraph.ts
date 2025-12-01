/**
 * @fileoverview Workflow graph traversal utilities for Lightning workflows.
 *
 * This module provides helper functions for traversing and analyzing
 * workflow DAGs (directed acyclic graphs). It supports both plain Edge
 * objects and Y.Doc Y.Map structures for collaborative editing scenarios.
 *
 * Provides a single source of truth for DAG operations on workflow edges
 * and jobs. Consolidates duplicated logic across the collaborative editor
 * for querying and analyzing workflow structure.
 *
 * @module workflowGraph
 */

import * as Y from 'yjs';

import type { Workflow } from '../types/workflow';

// ============================================================================
// Edge Queries (Plain Objects)
// ============================================================================

/**
 * Gets all edges where the specified job is the source.
 *
 * This function filters the edges array to find all edges that originate
 * from the given job ID. Edges with source_trigger_id are excluded as
 * they originate from triggers, not jobs.
 *
 * @param edges - Array of workflow edges to search
 * @param jobId - The ID of the job to find outgoing edges for
 * @returns Array of edges where source_job_id matches the jobId
 *
 * @example
 * ```typescript
 * const edges = [
 *   { id: 'e1', source_job_id: 'job-1', target_job_id: 'job-2' },
 *   { id: 'e2', source_job_id: 'job-1', target_job_id: 'job-3' },
 *   { id: 'e3', source_job_id: 'job-2', target_job_id: 'job-3' }
 * ];
 * const outgoing = getOutgoingJobEdges(edges, 'job-1');
 * // Returns: [e1, e2]
 * ```
 *
 * @remarks
 * Returns an empty array if no edges match or if edges array is empty.
 * Edges with null or undefined source_job_id are excluded.
 */
export function getOutgoingJobEdges(
  edges: Workflow.Edge[],
  jobId: string
): Workflow.Edge[] {
  return edges.filter(edge => edge.source_job_id === jobId);
}

/**
 * Gets all edges where the specified job is the target.
 *
 * This function filters the edges array to find all edges that point to
 * the given job ID. This includes edges from both jobs (source_job_id)
 * and triggers (source_trigger_id), allowing you to identify all parent
 * nodes in the workflow DAG.
 *
 * @param edges - Array of workflow edges to search
 * @param jobId - The ID of the job to find incoming edges for
 * @returns Array of edges where target_job_id matches the jobId
 *
 * @example
 * ```typescript
 * const edges = [
 *   { id: 'e1', source_job_id: 'job-1', target_job_id: 'job-2' },
 *   { id: 'e2', source_trigger_id: 'trigger-1', target_job_id: 'job-2' },
 *   { id: 'e3', source_job_id: 'job-2', target_job_id: 'job-3' }
 * ];
 * const incoming = getIncomingJobEdges(edges, 'job-2');
 * // Returns: [e1, e2] (both job and trigger sources)
 * ```
 *
 * @remarks
 * Returns an empty array if no edges match or if edges array is empty.
 * Use this to detect parent nodes in the workflow graph.
 */
export function getIncomingJobEdges(
  edges: Workflow.Edge[],
  jobId: string
): Workflow.Edge[] {
  return edges.filter(edge => edge.target_job_id === jobId);
}

/**
 * Gets all edges where the specified trigger is the source.
 *
 * This function filters the edges array to find all edges that originate
 * from the given trigger ID. Edges with source_job_id are excluded as
 * they originate from jobs, not triggers.
 *
 * @param edges - Array of workflow edges to search
 * @param triggerId - The ID of the trigger to find outgoing edges for
 * @returns Array of edges where source_trigger_id matches the triggerId
 *
 * @example
 * ```typescript
 * const edges = [
 *   { id: 'e1', source_trigger_id: 'trigger-1', target_job_id: 'job-1' },
 *   { id: 'e2', source_trigger_id: 'trigger-1', target_job_id: 'job-2' },
 *   { id: 'e3', source_job_id: 'job-1', target_job_id: 'job-3' }
 * ];
 * const outgoing = getOutgoingTriggerEdges(edges, 'trigger-1');
 * // Returns: [e1, e2]
 * ```
 *
 * @remarks
 * Returns an empty array if no edges match or if edges array is empty.
 * Edges with null or undefined source_trigger_id are excluded.
 */
export function getOutgoingTriggerEdges(
  edges: Workflow.Edge[],
  triggerId: string
): Workflow.Edge[] {
  return edges.filter(edge => edge.source_trigger_id === triggerId);
}

// ============================================================================
// Edge Queries (Y.Doc Arrays)
// ============================================================================

/**
 * Gets indices of edges where the specified job is the target.
 *
 * This function is specifically designed for Y.Doc Y.Array operations.
 * It finds all edges targeting a job and returns their array indices in
 * descending order (highest to lowest). This ordering is critical for
 * safe deletion from Y.Array structures.
 *
 * @param edges - Array of Y.Map objects from Y.Doc containing edge data
 * @param jobId - The ID of the job to find incoming edge indices for
 * @returns Array of indices in descending order (highest to lowest)
 *
 * @example
 * ```typescript
 * // Y.Doc array of edges
 * const yEdges = doc.getArray('edges');
 * const edges = yEdges.toArray(); // Y.Map<unknown>[]
 *
 * // Find indices of edges targeting 'job-2'
 * const indices = getIncomingEdgeIndices(edges, 'job-2');
 * // Returns: [4, 2, 0] (descending order)
 *
 * // Safe deletion from Y.Array (highest to lowest)
 * doc.transact(() => {
 *   indices.forEach(index => {
 *     yEdges.delete(index, 1);
 *   });
 * });
 * ```
 *
 * @remarks
 * **Critical**: Indices are returned in descending order to enable safe
 * deletion from Y.Array. When deleting multiple items from an array by
 * index, you must delete from highest to lowest to avoid index shifting
 * issues. Deleting from lowest to highest will cause indices to shift
 * after each deletion, resulting in incorrect deletions.
 *
 * Returns an empty array if no edges match or if edges array is empty.
 */
export function getIncomingEdgeIndices(
  edges: Y.Map<unknown>[],
  jobId: string
): number[] {
  return edges
    .map((edge, index) => ({ edge, index }))
    .filter(({ edge }) => edge.get('target_job_id') === jobId)
    .map(({ index }) => index)
    .sort((a, b) => b - a); // Sort descending for safe deletion
}

// ============================================================================
// Ghost Edge Handling
// ============================================================================

/**
 * Removes edges that point to non-existent jobs (ghost edges).
 *
 * A "ghost edge" is an edge with a target_job_id that doesn't exist in
 * the jobs array. This can occur due to:
 * - Asynchronous operations (job deleted before edge cleanup)
 * - Collaborative editing sync issues
 * - Race conditions during multi-user editing
 *
 * This function filters out ghost edges, returning only valid edges
 * where the target job exists.
 *
 * @param edges - Array of workflow edges to filter
 * @param jobs - Array of workflow jobs for validation
 * @returns Array of edges with only valid target jobs
 *
 * @example
 * ```typescript
 * const jobs = [
 *   { id: 'job-1', name: 'Job 1' },
 *   { id: 'job-2', name: 'Job 2' }
 * ];
 * const edges = [
 *   { id: 'e1', source_job_id: 'job-1', target_job_id: 'job-2' }, // Valid
 *   { id: 'e2', source_job_id: 'job-2', target_job_id: 'job-999' } // Ghost
 * ];
 * const validEdges = removeGhostEdges(edges, jobs);
 * // Returns: [e1] (only the valid edge)
 * ```
 *
 * @remarks
 * Edges without a target_job_id (null or undefined) are considered
 * valid and are NOT removed, though they would be invalid edges in
 * practice. Use this function to clean up edges after job deletion.
 *
 * See also {@link findGhostEdges} for the inverse operation.
 */
export function removeGhostEdges(
  edges: Workflow.Edge[],
  jobs: Workflow.Job[]
): Workflow.Edge[] {
  return edges.filter(edge => {
    // If target is a job, verify it exists
    if (edge.target_job_id) {
      return jobs.some(job => job.id === edge.target_job_id);
    }
    // If no target_job_id, it's not a ghost edge
    // (though this would be an invalid edge)
    return true;
  });
}

/**
 * Finds edges that point to non-existent jobs (ghost edges).
 *
 * This function returns only the invalid edges (where target job does
 * not exist). It's the inverse of {@link removeGhostEdges} and is
 * useful for debugging, validation, or cleanup operations.
 *
 * @param edges - Array of workflow edges to check
 * @param jobs - Array of workflow jobs for validation
 * @returns Array of ghost edges (edges with invalid target jobs)
 *
 * @example
 * ```typescript
 * const jobs = [
 *   { id: 'job-1', name: 'Job 1' }
 * ];
 * const edges = [
 *   { id: 'e1', source_job_id: 'job-1', target_job_id: 'job-2' }, // Valid
 *   { id: 'e2', source_job_id: 'job-1', target_job_id: 'job-999' }, // Ghost
 *   { id: 'e3', source_job_id: 'job-1', target_job_id: 'job-888' }  // Ghost
 * ];
 * const ghosts = findGhostEdges(edges, jobs);
 * // Returns: [e2, e3] (only the ghost edges)
 *
 * // Use for validation before saving
 * if (ghosts.length > 0) {
 *   console.warn(`Found ${ghosts.length} ghost edges`);
 * }
 * ```
 *
 * @remarks
 * Edges without a target_job_id (null or undefined) are NOT considered
 * ghost edges and will not be returned. The relationship between this
 * function and removeGhostEdges is:
 * `findGhostEdges(edges, jobs) + removeGhostEdges(edges, jobs) = edges`
 *
 * See also {@link removeGhostEdges} for filtering out ghost edges.
 */
export function findGhostEdges(
  edges: Workflow.Edge[],
  jobs: Workflow.Job[]
): Workflow.Edge[] {
  return edges.filter(edge => {
    // If target is a job, check if it exists
    if (edge.target_job_id) {
      return !jobs.some(job => job.id === edge.target_job_id);
    }
    // If no target_job_id, it's not a ghost edge
    return false;
  });
}

// ============================================================================
// Source Type Detection
// ============================================================================

/**
 * Checks if a node ID exists in the jobs array.
 *
 * Used to determine if a source node is a job (versus a trigger).
 * This is necessary because both jobs and triggers use the same ID
 * space in the workflow diagram visualization, and edge creation logic
 * needs to distinguish between them.
 *
 * @param nodeId - The node ID to check against the jobs array
 * @param jobs - Array of workflow jobs to search
 * @returns True if the node ID matches a job, false otherwise
 *
 * @example
 * ```typescript
 * const jobs = [
 *   { id: 'job-1', name: 'First Job' },
 *   { id: 'job-2', name: 'Second Job' }
 * ];
 *
 * // Check before creating an edge
 * const sourceId = 'job-1';
 * if (isSourceNodeJob(sourceId, jobs)) {
 *   // Create job-to-job edge
 *   edge.source_job_id = sourceId;
 * } else {
 *   // Create trigger-to-job edge
 *   edge.source_trigger_id = sourceId;
 * }
 * ```
 *
 * @remarks
 * Returns false for empty jobs array or non-existent IDs.
 * Use this function during edge creation to set the correct source
 * field (source_job_id vs source_trigger_id).
 */
export function isSourceNodeJob(nodeId: string, jobs: Workflow.Job[]): boolean {
  return jobs.some(job => job.id === nodeId);
}

/**
 * Checks if an edge originates from a trigger.
 *
 * This function validates that the edge has a non-null, non-undefined
 * source_trigger_id field, indicating the edge starts from a trigger
 * node rather than a job node.
 *
 * @param edge - The edge to check for trigger source
 * @returns True if edge has a valid source_trigger_id, false otherwise
 *
 * @example
 * ```typescript
 * const edge1 = {
 *   id: 'e1',
 *   source_trigger_id: 'trigger-1',
 *   target_job_id: 'job-1'
 * };
 * const edge2 = {
 *   id: 'e2',
 *   source_job_id: 'job-1',
 *   target_job_id: 'job-2'
 * };
 *
 * isEdgeFromTrigger(edge1); // true
 * isEdgeFromTrigger(edge2); // false
 *
 * // Use in condition validation
 * if (isEdgeFromTrigger(edge)) {
 *   // Trigger edges support different condition types
 *   validateTriggerEdgeCondition(edge);
 * }
 * ```
 *
 * @remarks
 * Returns false for null or undefined source_trigger_id values.
 * Use this with {@link isEdgeFromJob} to determine edge source type.
 */
export function isEdgeFromTrigger(edge: Workflow.Edge): boolean {
  return (
    edge.source_trigger_id !== undefined && edge.source_trigger_id !== null
  );
}

/**
 * Checks if an edge originates from a job.
 *
 * This function validates that the edge has a non-null, non-undefined
 * source_job_id field, indicating the edge starts from a job node
 * rather than a trigger node.
 *
 * @param edge - The edge to check for job source
 * @returns True if edge has a valid source_job_id, false otherwise
 *
 * @example
 * ```typescript
 * const edge1 = {
 *   id: 'e1',
 *   source_job_id: 'job-1',
 *   target_job_id: 'job-2'
 * };
 * const edge2 = {
 *   id: 'e2',
 *   source_trigger_id: 'trigger-1',
 *   target_job_id: 'job-1'
 * };
 *
 * isEdgeFromJob(edge1); // true
 * isEdgeFromJob(edge2); // false
 *
 * // Check parent type when analyzing dependencies
 * const parentEdges = getIncomingJobEdges(edges, 'job-2');
 * const hasJobParent = parentEdges.some(isEdgeFromJob);
 * const hasTriggerParent = parentEdges.some(isEdgeFromTrigger);
 * ```
 *
 * @remarks
 * Returns false for null or undefined source_job_id values.
 * Use this with {@link isEdgeFromTrigger} to determine edge source type.
 * Useful for distinguishing between first jobs (trigger parents) and
 * downstream jobs (job parents).
 */
export function isEdgeFromJob(edge: Workflow.Edge): boolean {
  return edge.source_job_id !== undefined && edge.source_job_id !== null;
}

// ============================================================================
// Workflow Structure Analysis
// ============================================================================

/**
 * Checks if a job is the "first job" in a workflow.
 *
 * A job is considered the "first job" if it has at least one parent
 * edge from a trigger AND no parent edges from other jobs. First jobs
 * are special in Lightning workflows because they:
 * - Are directly connected to workflow triggers
 * - Serve as entry points for workflow execution
 * - May have special validation rules (e.g., cannot be deleted)
 *
 * @param edges - Array of workflow edges to analyze
 * @param jobId - The ID of the job to check
 * @returns True if job is first in workflow, false otherwise
 *
 * @example
 * ```typescript
 * const edges = [
 *   { id: 'e1', source_trigger_id: 'trigger-1', target_job_id: 'job-1' },
 *   { id: 'e2', source_job_id: 'job-1', target_job_id: 'job-2' },
 *   { id: 'e3', source_job_id: 'job-2', target_job_id: 'job-3' }
 * ];
 *
 * isFirstJobInWorkflow(edges, 'job-1'); // true (trigger parent only)
 * isFirstJobInWorkflow(edges, 'job-2'); // false (has job parent)
 * isFirstJobInWorkflow(edges, 'job-3'); // false (has job parent)
 *
 * // Use to enforce workflow rules
 * const canDelete = !isFirstJobInWorkflow(edges, jobId);
 * if (!canDelete) {
 *   showError('Cannot delete first job in workflow');
 * }
 * ```
 *
 * @remarks
 * Returns false if:
 * - Job has no parent edges (orphaned job)
 * - Job has only job parents (downstream job)
 * - Job has both trigger and job parents (multiple paths)
 * - Edges array is empty
 *
 * A workflow can have multiple first jobs if different triggers
 * connect to different jobs.
 */
export function isFirstJobInWorkflow(
  edges: Workflow.Edge[],
  jobId: string
): boolean {
  const parentEdges = getIncomingJobEdges(edges, jobId);

  const hasTriggerParent = parentEdges.some(isEdgeFromTrigger);
  const hasJobParent = parentEdges.some(isEdgeFromJob);

  return hasTriggerParent && !hasJobParent;
}

/**
 * Finds the first job ID connected to a trigger.
 *
 * Returns the target_job_id of the first edge found that originates
 * from the given trigger. This is used to determine which job to run
 * when a trigger is activated (e.g., manual runs, retry operations, or
 * webhook/cron trigger activation).
 *
 * @param edges - Array of workflow edges to search
 * @param triggerId - The ID of the trigger to find the connected job for
 * @returns The job ID if found, undefined if no edge or invalid target
 *
 * @example
 * ```typescript
 * const edges = [
 *   { id: 'e1', source_trigger_id: 'trigger-1', target_job_id: 'job-1' },
 *   { id: 'e2', source_trigger_id: 'trigger-1', target_job_id: 'job-2' },
 *   { id: 'e3', source_trigger_id: 'trigger-2', target_job_id: 'job-3' }
 * ];
 *
 * const firstJob = findFirstJobFromTrigger(edges, 'trigger-1');
 * // Returns: 'job-1' (first edge found)
 *
 * // Use for manual workflow execution
 * const jobId = findFirstJobFromTrigger(edges, selectedTriggerId);
 * if (jobId) {
 *   executeWorkflow(jobId);
 * } else {
 *   showError('No job connected to this trigger');
 * }
 * ```
 *
 * @remarks
 * Returns undefined if:
 * - No edge exists with the specified trigger ID
 * - The edge has a null or undefined target_job_id
 * - Edges array is empty
 *
 * If multiple edges exist from the same trigger (branching workflow),
 * this returns the first edge's target job based on array order.
 * In practice, triggers typically connect to a single first job.
 */
export function findFirstJobFromTrigger(
  edges: Workflow.Edge[],
  triggerId: string
): string | undefined {
  const edge = edges.find(e => e.source_trigger_id === triggerId);
  return edge?.target_job_id || undefined;
}

// gets job ordinals relative to start(trigger-node)
export function getJobOrdinals(adj: Record<string, string[]>, start: string) {
  const ordinals: Record<string, number> = { [start]: 1 };
  const visited = new Set();
  const queue = [start];

  visited.add(start);

  while (queue.length > 0) {
    const node = queue.shift(); // pop from front
    if (!node) continue;

    const neighbors = adj[node] || [];
    for (const next of neighbors) {
      if (!visited.has(next)) {
        ordinals[next] = ordinals[node] + 1;
        visited.add(next);
        queue.push(next);
      }
    }
  }
  return ordinals;
}

interface EdgesToAdjListResult {
  list: Record<string, string[]>;
  trigger_id: string;
}

// create an adjacency list from edges
export function edgesToAdjList(edges: Workflow.Edge[]): EdgesToAdjListResult {
  const list: Record<string, string[]> = {};
  let triggerId: string = '';
  for (let i = 0; i < edges.length; i++) {
    const edge = edges[i];
    const from_id = edge.source_job_id || edge.source_trigger_id;
    if (edge.source_trigger_id) triggerId = edge.source_trigger_id;
    if (!from_id || !edge.target_job_id) continue;
    if (Array.isArray(list[from_id])) {
      list[from_id].push(edge.target_job_id);
    } else list[from_id] = [edge.target_job_id];
  }
  return { list, trigger_id: triggerId };
}
