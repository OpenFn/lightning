/**
 * static-layout Utility Tests
 *
 * `computeStaticPositions` is the whole of the auto-layout, extracted out of
 * `layout()` so a read-only rendering can use it without a ReactFlowInstance.
 * These are the first tests the Dagre pass has had, so they pin the properties
 * both callers actually depend on rather than exact coordinates, which are
 * Dagre's business and would make this a change-detector.
 */

import { describe, expect, test } from 'vitest';

import type { Flow } from '../../../js/workflow-diagram/types';
import computeStaticPositions from '../../../js/workflow-diagram/util/static-layout';

function node(id: string): Flow.Node {
  return { id, type: 'job', position: { x: 0, y: 0 }, data: {} } as Flow.Node;
}

function edge(source: string, target: string): Flow.Edge {
  return { id: `${source}->${target}`, source, target } as Flow.Edge;
}

/** trigger → a → b, the shape almost every workflow starts as. */
const CHAIN: Flow.Model = {
  nodes: [node('trigger'), node('a'), node('b')],
  edges: [edge('trigger', 'a'), edge('a', 'b')],
};

describe('computeStaticPositions', () => {
  test('returns a position for every node', () => {
    const positions = computeStaticPositions(CHAIN);

    expect(Object.keys(positions).sort()).toEqual(['a', 'b', 'trigger']);
    Object.values(positions).forEach(position => {
      expect(Number.isFinite(position.x)).toBe(true);
      expect(Number.isFinite(position.y)).toBe(true);
    });
  });

  test('lays a chain out top to bottom, in edge order', () => {
    // Both callers rely on this: the diagram is read downwards, and the
    // preview would be misleading if a template's steps came out shuffled.
    const positions = computeStaticPositions(CHAIN);

    expect(positions['trigger']!.y).toBeLessThan(positions['a']!.y);
    expect(positions['a']!.y).toBeLessThan(positions['b']!.y);
  });

  test('separates branches horizontally', () => {
    const branched: Flow.Model = {
      nodes: [node('trigger'), node('left'), node('right')],
      edges: [edge('trigger', 'left'), edge('trigger', 'right')],
    };

    const positions = computeStaticPositions(branched);

    expect(positions['left']!.x).not.toEqual(positions['right']!.x);
    // Siblings share a rank, so they belong on the same row.
    expect(positions['left']!.y).toEqual(positions['right']!.y);
  });

  test('is deterministic, so the same workflow always lays out the same way', () => {
    // The preview re-derives on every selection and the canvas re-lays out on
    // every structural change. Either would flicker if this drifted.
    expect(computeStaticPositions(CHAIN)).toEqual(
      computeStaticPositions(CHAIN)
    );
  });

  test('handles a single node with no edges', () => {
    const positions = computeStaticPositions({
      nodes: [node('only')],
      edges: [],
    });

    expect(Object.keys(positions)).toEqual(['only']);
  });

  test('returns nothing for an empty model', () => {
    expect(computeStaticPositions({ nodes: [], edges: [] })).toEqual({});
  });
});
