/**
 * useConnect Hook Tests
 *
 * Tests for edge validation logic in the workflow diagram.
 * These tests verify the four validation rules:
 * 1. Self-connection prevention
 * 2. Cannot connect to triggers
 * 3. Circular workflow detection
 * 4. Duplicate edge prevention
 *
 * These validation functions are pure and shared between the old workflow
 * diagram and the collaborative editor.
 */

import { describe, expect, test } from 'vitest';
import * as Y from 'yjs';
import type { Flow } from '../../js/workflow-diagram/types';
import {
  isUpstream,
  isChild,
  getDropTargetError,
} from '../../js/workflow-diagram/useConnect';
import {
  createWorkflowYDoc,
  createLinearWorkflowYDoc,
  createDiamondWorkflowYDoc,
} from './__helpers__/workflowFactory';

describe('isUpstream', () => {
  test('returns false for empty graph', () => {
    const model: Flow.Model = { nodes: [], edges: [] };
    expect(isUpstream(model, 'node-a', 'node-b')).toBe(false);
  });

  test('detects upstream relationships in linear chains and prevents reverse connections', () => {
    // Create a linear chain A→B→C
    const model: Flow.Model = {
      nodes: [],
      edges: [
        { id: 'e1', source: 'node-a', target: 'node-b' },
        { id: 'e2', source: 'node-b', target: 'node-c' },
      ],
    };

    // C is a descendant of A (A flows to C)
    expect(isUpstream(model, 'node-a', 'node-c')).toBe(true);

    // A is not a descendant of C
    expect(isUpstream(model, 'node-c', 'node-a')).toBe(false);

    // B is a descendant of A (A flows to B)
    expect(isUpstream(model, 'node-a', 'node-b')).toBe(true);
  });

  test('detects potential two-node and three-node cycles', () => {
    // Two-node potential cycle: A→B exists, attempting B→A
    // isUpstream checks if target (A) is downstream of source (B)
    // Since B is downstream of A, connecting B→A would create cycle
    const twoNodeModel: Flow.Model = {
      nodes: [],
      edges: [{ id: 'e1', source: 'node-a', target: 'node-b' }],
    };
    // B is downstream of A, so B→A would create cycle
    expect(isUpstream(twoNodeModel, 'node-a', 'node-b')).toBe(true);

    // Three-node potential cycle: A→B→C exists, attempting C→A
    const threeNodeModel: Flow.Model = {
      nodes: [],
      edges: [
        { id: 'e1', source: 'node-a', target: 'node-b' },
        { id: 'e2', source: 'node-b', target: 'node-c' },
      ],
    };
    // C is downstream of A, so C→A would create cycle
    expect(isUpstream(threeNodeModel, 'node-a', 'node-c')).toBe(true);
    // C is downstream of B, so C→B would create cycle
    expect(isUpstream(threeNodeModel, 'node-b', 'node-c')).toBe(true);
  });

  test('correctly handles diamond pattern (valid DAG, no false positive)', () => {
    // Diamond: A→B, A→C, B→D, C→D
    const model: Flow.Model = {
      nodes: [],
      edges: [
        { id: 'e1', source: 'node-a', target: 'node-b' },
        { id: 'e2', source: 'node-a', target: 'node-c' },
        { id: 'e3', source: 'node-b', target: 'node-d' },
        { id: 'e4', source: 'node-c', target: 'node-d' },
      ],
    };

    // A is upstream of D (valid)
    expect(isUpstream(model, 'node-a', 'node-d')).toBe(true);

    // D is not upstream of A (D→A would create cycle)
    expect(isUpstream(model, 'node-d', 'node-a')).toBe(false);

    // Multiple paths to same node are allowed (no false positive)
    expect(isUpstream(model, 'node-b', 'node-d')).toBe(true);
    expect(isUpstream(model, 'node-c', 'node-d')).toBe(true);
  });

  test('handles complex branching graphs and deep nesting', () => {
    // Complex branching: A→B→D, A→C→E
    const branchingModel: Flow.Model = {
      nodes: [],
      edges: [
        { id: 'e1', source: 'node-a', target: 'node-b' },
        { id: 'e2', source: 'node-b', target: 'node-d' },
        { id: 'e3', source: 'node-a', target: 'node-c' },
        { id: 'e4', source: 'node-c', target: 'node-e' },
      ],
    };

    expect(isUpstream(branchingModel, 'node-a', 'node-d')).toBe(true);
    expect(isUpstream(branchingModel, 'node-a', 'node-e')).toBe(true);
    expect(isUpstream(branchingModel, 'node-d', 'node-e')).toBe(false);

    // Deep nesting (5+ levels): A→B→C→D→E→F
    const deepModel: Flow.Model = {
      nodes: [],
      edges: [
        { id: 'e1', source: 'node-a', target: 'node-b' },
        { id: 'e2', source: 'node-b', target: 'node-c' },
        { id: 'e3', source: 'node-c', target: 'node-d' },
        { id: 'e4', source: 'node-d', target: 'node-e' },
        { id: 'e5', source: 'node-e', target: 'node-f' },
      ],
    };

    expect(isUpstream(deepModel, 'node-a', 'node-f')).toBe(true);
    expect(isUpstream(deepModel, 'node-c', 'node-f')).toBe(true);
    expect(isUpstream(deepModel, 'node-f', 'node-a')).toBe(false);
  });
});

describe('isChild', () => {
  test('returns undefined when no edges exist or child not found', () => {
    const emptyModel: Flow.Model = { nodes: [], edges: [] };
    expect(isChild(emptyModel, 'node-a', 'node-b')).toBeUndefined();

    const modelWithEdges: Flow.Model = {
      nodes: [],
      edges: [
        { id: 'e1', source: 'node-a', target: 'node-b' },
        { id: 'e2', source: 'node-a', target: 'node-c' },
      ],
    };
    expect(isChild(modelWithEdges, 'node-a', 'node-d')).toBeUndefined();
  });

  test('finds existing child and handles multiple children correctly', () => {
    const edge = { id: 'e1', source: 'node-a', target: 'node-b' };
    const model: Flow.Model = {
      nodes: [],
      edges: [
        edge,
        { id: 'e2', source: 'node-a', target: 'node-c' },
        { id: 'e3', source: 'node-a', target: 'node-d' },
      ],
    };

    // Find existing child
    expect(isChild(model, 'node-a', 'node-b')).toEqual(edge);

    // Multiple children from same source
    expect(isChild(model, 'node-a', 'node-c')).toBeDefined();
    expect(isChild(model, 'node-a', 'node-d')).toBeDefined();

    // Non-existent child
    expect(isChild(model, 'node-a', 'node-e')).toBeUndefined();
  });

  test('distinguishes between different sources to same target', () => {
    const edgeAB = { id: 'e1', source: 'node-a', target: 'node-b' };
    const edgeCB = { id: 'e2', source: 'node-c', target: 'node-b' };
    const model: Flow.Model = {
      nodes: [],
      edges: [edgeAB, edgeCB],
    };

    // Same target, different sources
    expect(isChild(model, 'node-a', 'node-b')).toEqual(edgeAB);
    expect(isChild(model, 'node-c', 'node-b')).toEqual(edgeCB);

    // Verify they are different edges
    expect(isChild(model, 'node-a', 'node-b')).not.toEqual(
      isChild(model, 'node-c', 'node-b')
    );
  });
});

describe('getDropTargetError', () => {
  test('returns truthy for self-connection', () => {
    const model: Flow.Model = {
      nodes: [
        { id: 'node-a', type: 'job', data: {}, position: { x: 0, y: 0 } },
      ],
      edges: [],
    };

    const error = getDropTargetError(model, 'node-a', 'node-a');
    expect(error).toBeTruthy();
  });

  test('validates trigger connections correctly', () => {
    const model: Flow.Model = {
      nodes: [
        { id: 'node-a', type: 'job', data: {}, position: { x: 0, y: 0 } },
        {
          id: 'trigger-1',
          type: 'trigger',
          data: {},
          position: { x: 0, y: 0 },
        },
      ],
      edges: [],
    };

    // Cannot connect TO a trigger
    expect(getDropTargetError(model, 'node-a', 'trigger-1')).toBe(
      'Cannot connect to a trigger'
    );

    // CAN connect FROM a trigger (triggers are valid sources)
    expect(getDropTargetError(model, 'trigger-1', 'node-a')).toBeUndefined();
  });

  test('detects circular workflows', () => {
    const model: Flow.Model = {
      nodes: [],
      edges: [
        { id: 'e1', source: 'node-a', target: 'node-b' },
        { id: 'e2', source: 'node-b', target: 'node-c' },
      ],
    };

    // Would create cycle: A→B→C→A
    expect(getDropTargetError(model, 'node-c', 'node-a')).toBe(
      'Cannot create circular workflow'
    );

    // Would create cycle: B→C→B
    expect(getDropTargetError(model, 'node-c', 'node-b')).toBe(
      'Cannot create circular workflow'
    );
  });

  test('detects duplicate edges', () => {
    const model: Flow.Model = {
      nodes: [],
      edges: [{ id: 'e1', source: 'node-a', target: 'node-b' }],
    };

    expect(getDropTargetError(model, 'node-a', 'node-b')).toBe(
      'Already connected to this step'
    );
  });

  test('returns undefined for valid connections', () => {
    const model: Flow.Model = {
      nodes: [
        { id: 'node-a', type: 'job', data: {}, position: { x: 0, y: 0 } },
        { id: 'node-b', type: 'job', data: {}, position: { x: 0, y: 0 } },
        { id: 'node-c', type: 'job', data: {}, position: { x: 0, y: 0 } },
      ],
      edges: [{ id: 'e1', source: 'node-a', target: 'node-b' }],
    };

    // Valid new connection
    expect(getDropTargetError(model, 'node-b', 'node-c')).toBeUndefined();

    // Valid connection from different source to existing target
    expect(getDropTargetError(model, 'node-c', 'node-b')).toBeUndefined();
  });
});

// =============================================================================
// INTEGRATION TESTS - Y.js Collaborative State
// =============================================================================

/**
 * Helper function to convert Y.Doc to Flow.Model for validation tests.
 * Extracts jobs, triggers, and edges from Y.js arrays and converts them
 * to the Flow.Model format that validation functions expect.
 */
function yDocToFlowModel(ydoc: Y.Doc): Flow.Model {
  const edgesArray = ydoc.getArray('edges');
  const edges: Flow.Edge[] = edgesArray
    .toArray()
    .map((yEdge: any) => yEdge.toJSON())
    .map((edge: any) => ({
      id: edge.id,
      source: edge.source_job_id || edge.source_trigger_id,
      target: edge.target_job_id,
      data: {},
    }));

  const jobsArray = ydoc.getArray('jobs');
  const jobNodes: Flow.Node[] = jobsArray
    .toArray()
    .map((yJob: any) => yJob.toJSON())
    .map((job: any) => ({
      id: job.id,
      type: 'job',
      data: {},
      position: { x: 0, y: 0 },
    }));

  const triggersArray = ydoc.getArray('triggers');
  const triggerNodes: Flow.Node[] = triggersArray
    .toArray()
    .map((yTrigger: any) => yTrigger.toJSON())
    .map((trigger: any) => ({
      id: trigger.id,
      type: 'trigger', // Use "trigger" not the actual trigger.type
      data: {},
      position: { x: 0, y: 0 },
    }));

  const nodes: Flow.Node[] = [...jobNodes, ...triggerNodes];
  return { nodes, edges };
}

describe('useConnect - Integration Tests with Y.js', () => {
  test('validates against current Y.js workflow state', () => {
    const ydoc = createWorkflowYDoc({
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
      },
      edges: [{ id: 'edge-1', source: 'job-a', target: 'job-b' }],
    });

    const model = yDocToFlowModel(ydoc);

    // Test validation functions with Y.js state
    expect(getDropTargetError(model, 'job-a', 'job-b')).toBe(
      'Already connected to this step'
    );
  });

  test('validation updates after collaborative edge addition', () => {
    const ydoc = createWorkflowYDoc({
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
      },
      edges: [],
    });

    // Initially, A→B should be valid
    let model = yDocToFlowModel(ydoc);
    expect(getDropTargetError(model, 'job-a', 'job-b')).toBeUndefined();

    // Simulate remote user adding edge A→B
    const edgesArray = ydoc.getArray('edges');
    const edgeMap = new Y.Map();
    edgeMap.set('id', 'edge-1');
    edgeMap.set('source_job_id', 'job-a');
    edgeMap.set('target_job_id', 'job-b');
    edgeMap.set('condition_type', 'on_job_success');
    edgesArray.push([edgeMap]);

    // Now A→B should be invalid (duplicate)
    model = yDocToFlowModel(ydoc);
    expect(getDropTargetError(model, 'job-a', 'job-b')).toBe(
      'Already connected to this step'
    );
  });

  test('detects circular workflow after collaborative changes', () => {
    const ydoc = createWorkflowYDoc({
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
      edges: [],
    });

    const edgesArray = ydoc.getArray('edges');

    // User 1 creates A→B
    const edge1Map = new Y.Map();
    edge1Map.set('id', 'edge-1');
    edge1Map.set('source_job_id', 'job-a');
    edge1Map.set('target_job_id', 'job-b');
    edge1Map.set('condition_type', 'on_job_success');
    edgesArray.push([edge1Map]);

    // User 2 creates B→C
    const edge2Map = new Y.Map();
    edge2Map.set('id', 'edge-2');
    edge2Map.set('source_job_id', 'job-b');
    edge2Map.set('target_job_id', 'job-c');
    edge2Map.set('condition_type', 'on_job_success');
    edgesArray.push([edge2Map]);

    // Now C→A should be prevented (circular)
    const model = yDocToFlowModel(ydoc);
    expect(getDropTargetError(model, 'job-c', 'job-a')).toBe(
      'Cannot create circular workflow'
    );
  });

  test('validates linear workflow from Y.js helper', () => {
    const ydoc = createLinearWorkflowYDoc();
    const model = yDocToFlowModel(ydoc);

    // Prevent reverse connection (would create cycle)
    expect(getDropTargetError(model, 'job-c', 'job-a')).toBe(
      'Cannot create circular workflow'
    );

    // Cannot connect job to trigger
    expect(getDropTargetError(model, 'job-c', 'trigger-1')).toBe(
      'Cannot connect to a trigger'
    );
  });

  test('validates diamond workflow from Y.js helper', () => {
    const ydoc = createDiamondWorkflowYDoc();
    const model = yDocToFlowModel(ydoc);

    // D→A would create cycle
    expect(getDropTargetError(model, 'job-d', 'job-a')).toBe(
      'Cannot create circular workflow'
    );

    // B→C is allowed (no cycle - both branches feed into D independently)
    expect(getDropTargetError(model, 'job-b', 'job-c')).toBeUndefined();
  });
});
