/**
 * Workflow Graph Traversal Utilities Tests
 *
 * Comprehensive tests for DAG operations on workflow edges and jobs.
 * Tests cover edge queries, ghost edge handling, source type detection,
 * and workflow structure analysis.
 */

import { describe, expect, test } from 'vitest';
import * as Y from 'yjs';

import type { Workflow } from '../../../js/collaborative-editor/types/workflow';
import {
  findFirstJobFromTrigger,
  findGhostEdges,
  getIncomingEdgeIndices,
  getIncomingJobEdges,
  getOutgoingJobEdges,
  getOutgoingTriggerEdges,
  isEdgeFromJob,
  isEdgeFromTrigger,
  isFirstJobInWorkflow,
  isSourceNodeJob,
  removeGhostEdges,
} from '../../../js/collaborative-editor/utils/workflowGraph';

// =============================================================================
// TEST FIXTURES
// =============================================================================

/**
 * Create a mock job with minimal required fields
 */
function createMockJob(overrides: Partial<Workflow.Job> = {}): Workflow.Job {
  return {
    id: 'job-1',
    name: 'Test Job',
    body: 'fn(state => state);',
    adaptor: '@openfn/language-common@latest',
    enabled: true,
    ...overrides,
  } as Workflow.Job;
}

/**
 * Create a mock edge with minimal required fields
 */
function createMockEdge(overrides: Partial<Workflow.Edge> = {}): Workflow.Edge {
  return {
    id: 'edge-1',
    target_job_id: 'job-2',
    condition_type: 'on_job_success',
    enabled: true,
    ...overrides,
  };
}

/**
 * Create a Y.Map edge for Y.Doc tests
 * Y.Map must be added to a Y.Doc before it can be read
 */
function createYMapEdge(data: Record<string, unknown>): Y.Map<unknown> {
  const doc = new Y.Doc();
  const ymap = doc.getMap('edge');
  Object.entries(data).forEach(([key, value]) => {
    ymap.set(key, value);
  });
  return ymap;
}

// =============================================================================
// GET OUTGOING JOB EDGES
// =============================================================================

describe.concurrent('getOutgoingJobEdges', () => {
  test('returns empty array when edges array is empty', () => {
    const result = getOutgoingJobEdges([], 'job-1');
    expect(result).toEqual([]);
  });

  test('returns empty array when no edges match job ID', () => {
    const edges = [
      createMockEdge({ source_job_id: 'job-2', target_job_id: 'job-3' }),
      createMockEdge({ source_job_id: 'job-3', target_job_id: 'job-4' }),
    ];

    const result = getOutgoingJobEdges(edges, 'job-1');
    expect(result).toEqual([]);
  });

  test('returns single edge when one edge matches', () => {
    const matchingEdge = createMockEdge({
      id: 'edge-1',
      source_job_id: 'job-1',
      target_job_id: 'job-2',
    });
    const edges = [
      matchingEdge,
      createMockEdge({ source_job_id: 'job-2', target_job_id: 'job-3' }),
    ];

    const result = getOutgoingJobEdges(edges, 'job-1');
    expect(result).toEqual([matchingEdge]);
  });

  test('returns multiple edges when multiple edges match', () => {
    const edge1 = createMockEdge({
      id: 'edge-1',
      source_job_id: 'job-1',
      target_job_id: 'job-2',
    });
    const edge2 = createMockEdge({
      id: 'edge-2',
      source_job_id: 'job-1',
      target_job_id: 'job-3',
    });
    const edges = [
      edge1,
      edge2,
      createMockEdge({ source_job_id: 'job-2', target_job_id: 'job-4' }),
    ];

    const result = getOutgoingJobEdges(edges, 'job-1');
    expect(result).toEqual([edge1, edge2]);
  });

  test('ignores edges with null source_job_id', () => {
    const edges = [
      createMockEdge({ source_job_id: null, target_job_id: 'job-2' }),
      createMockEdge({ source_job_id: 'job-1', target_job_id: 'job-3' }),
    ];

    const result = getOutgoingJobEdges(edges, 'job-1');
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe(edges[1].id);
  });

  test('ignores edges with undefined source_job_id', () => {
    const edges = [
      createMockEdge({ source_job_id: undefined, target_job_id: 'job-2' }),
      createMockEdge({ source_job_id: 'job-1', target_job_id: 'job-3' }),
    ];

    const result = getOutgoingJobEdges(edges, 'job-1');
    expect(result).toHaveLength(1);
  });

  test('ignores edges with source_trigger_id instead of source_job_id', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
      createMockEdge({ source_job_id: 'job-1', target_job_id: 'job-2' }),
    ];

    const result = getOutgoingJobEdges(edges, 'job-1');
    expect(result).toHaveLength(1);
    expect(result[0].source_job_id).toBe('job-1');
  });
});

// =============================================================================
// GET INCOMING JOB EDGES
// =============================================================================

describe.concurrent('getIncomingJobEdges', () => {
  test('returns empty array when edges array is empty', () => {
    const result = getIncomingJobEdges([], 'job-1');
    expect(result).toEqual([]);
  });

  test('returns empty array when no edges match job ID', () => {
    const edges = [
      createMockEdge({ source_job_id: 'job-2', target_job_id: 'job-3' }),
      createMockEdge({ source_job_id: 'job-3', target_job_id: 'job-4' }),
    ];

    const result = getIncomingJobEdges(edges, 'job-1');
    expect(result).toEqual([]);
  });

  test('returns single edge when one edge targets job', () => {
    const matchingEdge = createMockEdge({
      id: 'edge-1',
      source_job_id: 'job-2',
      target_job_id: 'job-1',
    });
    const edges = [
      matchingEdge,
      createMockEdge({ source_job_id: 'job-3', target_job_id: 'job-4' }),
    ];

    const result = getIncomingJobEdges(edges, 'job-1');
    expect(result).toEqual([matchingEdge]);
  });

  test('returns multiple edges when multiple edges target job', () => {
    const edge1 = createMockEdge({
      id: 'edge-1',
      source_job_id: 'job-2',
      target_job_id: 'job-1',
    });
    const edge2 = createMockEdge({
      id: 'edge-2',
      source_job_id: 'job-3',
      target_job_id: 'job-1',
    });
    const edges = [
      edge1,
      edge2,
      createMockEdge({ source_job_id: 'job-4', target_job_id: 'job-5' }),
    ];

    const result = getIncomingJobEdges(edges, 'job-1');
    expect(result).toEqual([edge1, edge2]);
  });

  test('includes edges from both jobs and triggers', () => {
    const edgeFromJob = createMockEdge({
      id: 'edge-1',
      source_job_id: 'job-2',
      target_job_id: 'job-1',
    });
    const edgeFromTrigger = createMockEdge({
      id: 'edge-2',
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-1',
    });
    const edges = [edgeFromJob, edgeFromTrigger];

    const result = getIncomingJobEdges(edges, 'job-1');
    expect(result).toEqual([edgeFromJob, edgeFromTrigger]);
  });
});

// =============================================================================
// GET OUTGOING TRIGGER EDGES
// =============================================================================

describe.concurrent('getOutgoingTriggerEdges', () => {
  test('returns empty array when edges array is empty', () => {
    const result = getOutgoingTriggerEdges([], 'trigger-1');
    expect(result).toEqual([]);
  });

  test('returns empty array when no edges match trigger ID', () => {
    const edges = [
      createMockEdge({ source_job_id: 'job-1', target_job_id: 'job-2' }),
      createMockEdge({
        source_trigger_id: 'trigger-2',
        target_job_id: 'job-1',
      }),
    ];

    const result = getOutgoingTriggerEdges(edges, 'trigger-1');
    expect(result).toEqual([]);
  });

  test('returns single edge when one edge matches', () => {
    const matchingEdge = createMockEdge({
      id: 'edge-1',
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-1',
    });
    const edges = [
      matchingEdge,
      createMockEdge({
        source_trigger_id: 'trigger-2',
        target_job_id: 'job-2',
      }),
    ];

    const result = getOutgoingTriggerEdges(edges, 'trigger-1');
    expect(result).toEqual([matchingEdge]);
  });

  test('returns multiple edges when multiple edges match', () => {
    const edge1 = createMockEdge({
      id: 'edge-1',
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-1',
    });
    const edge2 = createMockEdge({
      id: 'edge-2',
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-2',
    });
    const edges = [
      edge1,
      edge2,
      createMockEdge({
        source_trigger_id: 'trigger-2',
        target_job_id: 'job-3',
      }),
    ];

    const result = getOutgoingTriggerEdges(edges, 'trigger-1');
    expect(result).toEqual([edge1, edge2]);
  });

  test('ignores edges with null source_trigger_id', () => {
    const edges = [
      createMockEdge({ source_trigger_id: null, target_job_id: 'job-1' }),
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-2',
      }),
    ];

    const result = getOutgoingTriggerEdges(edges, 'trigger-1');
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe(edges[1].id);
  });

  test('ignores edges with source_job_id instead of source_trigger_id', () => {
    const edges = [
      createMockEdge({ source_job_id: 'job-1', target_job_id: 'job-2' }),
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
    ];

    const result = getOutgoingTriggerEdges(edges, 'trigger-1');
    expect(result).toHaveLength(1);
    expect(result[0].source_trigger_id).toBe('trigger-1');
  });
});

// =============================================================================
// GET INCOMING EDGE INDICES (Y.Doc)
// =============================================================================

describe.concurrent('getIncomingEdgeIndices', () => {
  test('returns empty array when edges array is empty', () => {
    const result = getIncomingEdgeIndices([], 'job-1');
    expect(result).toEqual([]);
  });

  test('returns empty array when no edges match job ID', () => {
    const edges = [
      createYMapEdge({ id: 'edge-1', target_job_id: 'job-2' }),
      createYMapEdge({ id: 'edge-2', target_job_id: 'job-3' }),
    ];

    const result = getIncomingEdgeIndices(edges, 'job-1');
    expect(result).toEqual([]);
  });

  test('returns single index when one edge matches', () => {
    const edges = [
      createYMapEdge({ id: 'edge-1', target_job_id: 'job-2' }),
      createYMapEdge({ id: 'edge-2', target_job_id: 'job-1' }),
      createYMapEdge({ id: 'edge-3', target_job_id: 'job-3' }),
    ];

    const result = getIncomingEdgeIndices(edges, 'job-1');
    expect(result).toEqual([1]);
  });

  test('returns multiple indices when multiple edges match', () => {
    const edges = [
      createYMapEdge({ id: 'edge-1', target_job_id: 'job-1' }), // index 0
      createYMapEdge({ id: 'edge-2', target_job_id: 'job-2' }), // index 1
      createYMapEdge({ id: 'edge-3', target_job_id: 'job-1' }), // index 2
      createYMapEdge({ id: 'edge-4', target_job_id: 'job-1' }), // index 3
    ];

    const result = getIncomingEdgeIndices(edges, 'job-1');
    expect(result).toEqual([3, 2, 0]); // Descending order
  });

  test('returns indices in descending order for safe deletion', () => {
    const edges = [
      createYMapEdge({ id: 'edge-1', target_job_id: 'job-1' }), // index 0
      createYMapEdge({ id: 'edge-2', target_job_id: 'job-1' }), // index 1
      createYMapEdge({ id: 'edge-3', target_job_id: 'job-2' }), // index 2
      createYMapEdge({ id: 'edge-4', target_job_id: 'job-1' }), // index 3
      createYMapEdge({ id: 'edge-5', target_job_id: 'job-1' }), // index 4
    ];

    const result = getIncomingEdgeIndices(edges, 'job-1');

    // Verify descending order (highest to lowest)
    expect(result).toEqual([4, 3, 1, 0]);

    // Verify each subsequent element is smaller
    for (let i = 0; i < result.length - 1; i++) {
      expect(result[i]).toBeGreaterThan(result[i + 1]);
    }
  });

  test('handles edges with null target_job_id', () => {
    const edges = [
      createYMapEdge({ id: 'edge-1', target_job_id: null }),
      createYMapEdge({ id: 'edge-2', target_job_id: 'job-1' }),
    ];

    const result = getIncomingEdgeIndices(edges, 'job-1');
    expect(result).toEqual([1]);
  });

  test('handles edges with undefined target_job_id', () => {
    const edges = [
      createYMapEdge({ id: 'edge-1' }), // No target_job_id
      createYMapEdge({ id: 'edge-2', target_job_id: 'job-1' }),
    ];

    const result = getIncomingEdgeIndices(edges, 'job-1');
    expect(result).toEqual([1]);
  });
});

// =============================================================================
// REMOVE GHOST EDGES
// =============================================================================

describe.concurrent('removeGhostEdges', () => {
  test('returns empty array when both edges and jobs are empty', () => {
    const result = removeGhostEdges([], []);
    expect(result).toEqual([]);
  });

  test('returns all edges when all target jobs exist', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
      createMockJob({ id: 'job-3' }),
    ];
    const edges = [
      createMockEdge({ id: 'edge-1', target_job_id: 'job-1' }),
      createMockEdge({ id: 'edge-2', target_job_id: 'job-2' }),
      createMockEdge({ id: 'edge-3', target_job_id: 'job-3' }),
    ];

    const result = removeGhostEdges(edges, jobs);
    expect(result).toEqual(edges);
  });

  test('filters out edges with non-existent target jobs', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
    ];
    const validEdge = createMockEdge({ id: 'edge-1', target_job_id: 'job-1' });
    const ghostEdge = createMockEdge({
      id: 'edge-2',
      target_job_id: 'job-999',
    });
    const edges = [validEdge, ghostEdge];

    const result = removeGhostEdges(edges, jobs);
    expect(result).toEqual([validEdge]);
  });

  test('returns empty array when all edges are ghost edges', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const edges = [
      createMockEdge({ id: 'edge-1', target_job_id: 'job-999' }),
      createMockEdge({ id: 'edge-2', target_job_id: 'job-888' }),
    ];

    const result = removeGhostEdges(edges, jobs);
    expect(result).toEqual([]);
  });

  test('keeps edges without target_job_id (considered valid)', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const edgeWithoutTarget = createMockEdge({
      id: 'edge-1',
      target_job_id: undefined,
    });
    const edges = [edgeWithoutTarget];

    const result = removeGhostEdges(edges, jobs);
    expect(result).toEqual([edgeWithoutTarget]);
  });

  test('keeps edges with null target_job_id', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const edgeWithNullTarget = createMockEdge({
      id: 'edge-1',
      target_job_id: null as unknown as string,
    });
    const edges = [edgeWithNullTarget];

    const result = removeGhostEdges(edges, jobs);
    expect(result).toEqual([edgeWithNullTarget]);
  });

  test('handles mixed valid and ghost edges', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
    ];
    const valid1 = createMockEdge({ id: 'edge-1', target_job_id: 'job-1' });
    const ghost1 = createMockEdge({ id: 'edge-2', target_job_id: 'job-999' });
    const valid2 = createMockEdge({ id: 'edge-3', target_job_id: 'job-2' });
    const ghost2 = createMockEdge({ id: 'edge-4', target_job_id: 'job-888' });
    const edges = [valid1, ghost1, valid2, ghost2];

    const result = removeGhostEdges(edges, jobs);
    expect(result).toEqual([valid1, valid2]);
  });
});

// =============================================================================
// FIND GHOST EDGES
// =============================================================================

describe.concurrent('findGhostEdges', () => {
  test('returns empty array when both edges and jobs are empty', () => {
    const result = findGhostEdges([], []);
    expect(result).toEqual([]);
  });

  test('returns empty array when all target jobs exist', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
    ];
    const edges = [
      createMockEdge({ id: 'edge-1', target_job_id: 'job-1' }),
      createMockEdge({ id: 'edge-2', target_job_id: 'job-2' }),
    ];

    const result = findGhostEdges(edges, jobs);
    expect(result).toEqual([]);
  });

  test('returns edges with non-existent target jobs', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const ghostEdge = createMockEdge({
      id: 'edge-1',
      target_job_id: 'job-999',
    });
    const edges = [ghostEdge];

    const result = findGhostEdges(edges, jobs);
    expect(result).toEqual([ghostEdge]);
  });

  test('returns all edges when all are ghost edges', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const ghost1 = createMockEdge({ id: 'edge-1', target_job_id: 'job-999' });
    const ghost2 = createMockEdge({ id: 'edge-2', target_job_id: 'job-888' });
    const edges = [ghost1, ghost2];

    const result = findGhostEdges(edges, jobs);
    expect(result).toEqual([ghost1, ghost2]);
  });

  test('excludes edges without target_job_id (not ghost edges)', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const edgeWithoutTarget = createMockEdge({
      id: 'edge-1',
      target_job_id: undefined,
    });
    const edges = [edgeWithoutTarget];

    const result = findGhostEdges(edges, jobs);
    expect(result).toEqual([]);
  });

  test('excludes edges with null target_job_id', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const edgeWithNullTarget = createMockEdge({
      id: 'edge-1',
      target_job_id: null as unknown as string,
    });
    const edges = [edgeWithNullTarget];

    const result = findGhostEdges(edges, jobs);
    expect(result).toEqual([]);
  });

  test('returns only ghost edges from mixed array', () => {
    const jobs = [createMockJob({ id: 'job-1' })];
    const valid = createMockEdge({ id: 'edge-1', target_job_id: 'job-1' });
    const ghost1 = createMockEdge({ id: 'edge-2', target_job_id: 'job-999' });
    const ghost2 = createMockEdge({ id: 'edge-3', target_job_id: 'job-888' });
    const edges = [valid, ghost1, ghost2];

    const result = findGhostEdges(edges, jobs);
    expect(result).toEqual([ghost1, ghost2]);
  });

  test('findGhostEdges and removeGhostEdges are inverse operations', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
    ];
    const edges = [
      createMockEdge({ id: 'edge-1', target_job_id: 'job-1' }),
      createMockEdge({ id: 'edge-2', target_job_id: 'job-999' }),
      createMockEdge({ id: 'edge-3', target_job_id: 'job-2' }),
      createMockEdge({ id: 'edge-4', target_job_id: 'job-888' }),
    ];

    const validEdges = removeGhostEdges(edges, jobs);
    const ghostEdges = findGhostEdges(edges, jobs);

    // Valid + ghost should equal original length
    expect(validEdges.length + ghostEdges.length).toBe(edges.length);

    // No overlap between valid and ghost
    const validIds = new Set(validEdges.map(e => e.id));
    const ghostIds = new Set(ghostEdges.map(e => e.id));
    const intersection = [...validIds].filter(id => ghostIds.has(id));
    expect(intersection).toEqual([]);
  });
});

// =============================================================================
// IS SOURCE NODE JOB
// =============================================================================

describe.concurrent('isSourceNodeJob', () => {
  test('returns false when jobs array is empty', () => {
    const result = isSourceNodeJob('job-1', []);
    expect(result).toBe(false);
  });

  test('returns true when node ID matches a job', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
    ];

    const result = isSourceNodeJob('job-1', jobs);
    expect(result).toBe(true);
  });

  test('returns false when node ID does not match any job', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
    ];

    const result = isSourceNodeJob('trigger-1', jobs);
    expect(result).toBe(false);
  });

  test('returns true for last job in array', () => {
    const jobs = [
      createMockJob({ id: 'job-1' }),
      createMockJob({ id: 'job-2' }),
      createMockJob({ id: 'job-3' }),
    ];

    const result = isSourceNodeJob('job-3', jobs);
    expect(result).toBe(true);
  });

  test('returns false for non-existent ID', () => {
    const jobs = [createMockJob({ id: 'job-1' })];

    const result = isSourceNodeJob('non-existent', jobs);
    expect(result).toBe(false);
  });
});

// =============================================================================
// IS EDGE FROM TRIGGER
// =============================================================================

describe.concurrent('isEdgeFromTrigger', () => {
  test('returns true when edge has source_trigger_id', () => {
    const edge = createMockEdge({
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-1',
    });

    const result = isEdgeFromTrigger(edge);
    expect(result).toBe(true);
  });

  test('returns false when edge has null source_trigger_id', () => {
    const edge = createMockEdge({
      source_trigger_id: null,
      target_job_id: 'job-1',
    });

    const result = isEdgeFromTrigger(edge);
    expect(result).toBe(false);
  });

  test('returns false when edge has undefined source_trigger_id', () => {
    const edge = createMockEdge({
      source_trigger_id: undefined,
      target_job_id: 'job-1',
    });

    const result = isEdgeFromTrigger(edge);
    expect(result).toBe(false);
  });

  test('returns false when edge has only source_job_id', () => {
    const edge = createMockEdge({
      source_job_id: 'job-1',
      target_job_id: 'job-2',
    });

    const result = isEdgeFromTrigger(edge);
    expect(result).toBe(false);
  });

  test('returns true when edge has both source_trigger_id and source_job_id', () => {
    // This would be invalid in practice, but tests the function logic
    const edge = createMockEdge({
      source_trigger_id: 'trigger-1',
      source_job_id: 'job-1',
      target_job_id: 'job-2',
    });

    const result = isEdgeFromTrigger(edge);
    expect(result).toBe(true);
  });
});

// =============================================================================
// IS EDGE FROM JOB
// =============================================================================

describe.concurrent('isEdgeFromJob', () => {
  test('returns true when edge has source_job_id', () => {
    const edge = createMockEdge({
      source_job_id: 'job-1',
      target_job_id: 'job-2',
    });

    const result = isEdgeFromJob(edge);
    expect(result).toBe(true);
  });

  test('returns false when edge has null source_job_id', () => {
    const edge = createMockEdge({
      source_job_id: null,
      target_job_id: 'job-1',
    });

    const result = isEdgeFromJob(edge);
    expect(result).toBe(false);
  });

  test('returns false when edge has undefined source_job_id', () => {
    const edge = createMockEdge({
      source_job_id: undefined,
      target_job_id: 'job-1',
    });

    const result = isEdgeFromJob(edge);
    expect(result).toBe(false);
  });

  test('returns false when edge has only source_trigger_id', () => {
    const edge = createMockEdge({
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-1',
    });

    const result = isEdgeFromJob(edge);
    expect(result).toBe(false);
  });

  test('returns true when edge has both source_job_id and source_trigger_id', () => {
    // This would be invalid in practice, but tests the function logic
    const edge = createMockEdge({
      source_job_id: 'job-1',
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-2',
    });

    const result = isEdgeFromJob(edge);
    expect(result).toBe(true);
  });
});

// =============================================================================
// IS FIRST JOB IN WORKFLOW
// =============================================================================

describe.concurrent('isFirstJobInWorkflow', () => {
  test('returns false when edges array is empty', () => {
    const result = isFirstJobInWorkflow([], 'job-1');
    expect(result).toBe(false);
  });

  test('returns true when job has only trigger parent', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
    ];

    const result = isFirstJobInWorkflow(edges, 'job-1');
    expect(result).toBe(true);
  });

  test('returns false when job has only job parent', () => {
    const edges = [
      createMockEdge({
        source_job_id: 'job-0',
        target_job_id: 'job-1',
      }),
    ];

    const result = isFirstJobInWorkflow(edges, 'job-1');
    expect(result).toBe(false);
  });

  test('returns false when job has both trigger and job parents', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        source_job_id: 'job-0',
        target_job_id: 'job-1',
      }),
    ];

    const result = isFirstJobInWorkflow(edges, 'job-1');
    expect(result).toBe(false);
  });

  test('returns false when job has no parents', () => {
    const edges = [
      createMockEdge({
        source_job_id: 'job-2',
        target_job_id: 'job-3',
      }),
    ];

    const result = isFirstJobInWorkflow(edges, 'job-1');
    expect(result).toBe(false);
  });

  test('returns true when job has multiple trigger parents but no job parents', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        source_trigger_id: 'trigger-2',
        target_job_id: 'job-1',
      }),
    ];

    const result = isFirstJobInWorkflow(edges, 'job-1');
    expect(result).toBe(true);
  });

  test('returns false when job has multiple job parents', () => {
    const edges = [
      createMockEdge({
        source_job_id: 'job-0',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        source_job_id: 'job-2',
        target_job_id: 'job-1',
      }),
    ];

    const result = isFirstJobInWorkflow(edges, 'job-1');
    expect(result).toBe(false);
  });

  test('returns false when job has trigger parent and at least one job parent', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        source_trigger_id: 'trigger-2',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        source_job_id: 'job-0',
        target_job_id: 'job-1',
      }),
    ];

    const result = isFirstJobInWorkflow(edges, 'job-1');
    expect(result).toBe(false);
  });
});

// =============================================================================
// FIND FIRST JOB FROM TRIGGER
// =============================================================================

describe.concurrent('findFirstJobFromTrigger', () => {
  test('returns undefined when edges array is empty', () => {
    const result = findFirstJobFromTrigger([], 'trigger-1');
    expect(result).toBeUndefined();
  });

  test('returns undefined when no edges match trigger ID', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-2',
        target_job_id: 'job-1',
      }),
    ];

    const result = findFirstJobFromTrigger(edges, 'trigger-1');
    expect(result).toBeUndefined();
  });

  test('returns job ID when trigger has one connected job', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
    ];

    const result = findFirstJobFromTrigger(edges, 'trigger-1');
    expect(result).toBe('job-1');
  });

  test('returns first matching job ID when trigger has multiple connected jobs', () => {
    const edges = [
      createMockEdge({
        id: 'edge-1',
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        id: 'edge-2',
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-2',
      }),
    ];

    const result = findFirstJobFromTrigger(edges, 'trigger-1');
    expect(result).toBe('job-1'); // First in array
  });

  test('returns undefined when edge has null target_job_id', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: null as unknown as string,
      }),
    ];

    const result = findFirstJobFromTrigger(edges, 'trigger-1');
    expect(result).toBeUndefined();
  });

  test('returns undefined when edge has undefined target_job_id', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: undefined as unknown as string,
      }),
    ];

    const result = findFirstJobFromTrigger(edges, 'trigger-1');
    expect(result).toBeUndefined();
  });

  test('ignores edges from other triggers', () => {
    const edges = [
      createMockEdge({
        source_trigger_id: 'trigger-2',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-2',
      }),
      createMockEdge({
        source_trigger_id: 'trigger-3',
        target_job_id: 'job-3',
      }),
    ];

    const result = findFirstJobFromTrigger(edges, 'trigger-1');
    expect(result).toBe('job-2');
  });

  test('ignores edges from jobs', () => {
    const edges = [
      createMockEdge({
        source_job_id: 'job-0',
        target_job_id: 'job-1',
      }),
      createMockEdge({
        source_trigger_id: 'trigger-1',
        target_job_id: 'job-2',
      }),
    ];

    const result = findFirstJobFromTrigger(edges, 'trigger-1');
    expect(result).toBe('job-2');
  });
});
