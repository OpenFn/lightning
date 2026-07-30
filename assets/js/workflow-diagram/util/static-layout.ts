import DagreUntyped from '../../../vendor/dagre.cjs';
import { NODE_HEIGHT, NODE_WIDTH } from '../constants';
import type { Flow, Positions } from '../types';

// TypeScript won't associate vendor/dagre.d.ts with a `.cjs` import specifier
// (it looks for a .d.cts), so bind the declarations explicitly. Type-only —
// erased at build time.
const Dagre = DagreUntyped as unknown as typeof import('../../../vendor/dagre');

/**
 * Pure Dagre pass over a flow model: returns auto-layout positions for every
 * node without touching the viewport. Shared by the editor's animated
 * `layout()` and by static, read-only renderings (e.g. template previews)
 * that have no ReactFlowInstance.
 */
const computeStaticPositions = (model: Flow.Model): Positions => {
  const g = new Dagre.graphlib.Graph().setDefaultEdgeLabel(() => ({}));
  g.setGraph({
    rankdir: 'TB',
    nodesep: 250,
    edgesep: 200,
    ranksep: 150,
  });

  model.edges.forEach(edge => g.setEdge(edge.source, edge.target));
  model.nodes.forEach(node =>
    g.setNode(node.id, { ...node, width: NODE_WIDTH, height: NODE_HEIGHT })
  );

  Dagre.layout(g, { disableOptimalOrderHeuristic: true });

  return model.nodes.reduce((obj, node) => {
    const { x, y } = g.node(node.id);
    obj[node.id] = { x, y };
    return obj;
  }, {} as Positions);
};

export default computeStaticPositions;
