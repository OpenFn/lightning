import DagreUntyped from '../../../vendor/dagre.cjs';
import { NODE_HEIGHT, NODE_WIDTH } from '../constants';
import type { Flow, Positions } from '../types';

// TypeScript won't match vendor/dagre.d.ts to a `.cjs` import specifier — it
// looks for a .d.cts — so the declarations are bound explicitly. Type-only,
// erased at build. `layout.ts` carried the resulting `any` for years; moving
// the code was the chance to stop.
const Dagre = DagreUntyped as unknown as typeof import('../../../vendor/dagre');

/**
 * A plain Dagre pass over a flow model: model in, a position per node out.
 *
 * This is the whole of the auto-layout. `layout()` wraps it with the things
 * the live canvas needs — animating between two layouts, and refitting the
 * viewport around what the user can currently see — but neither of those has
 * anything to do with deciding where nodes go.
 *
 * Separating them means a static, read-only rendering can lay itself out
 * without a ReactFlowInstance, a viewport, or an effect to hang the async
 * result on. It also keeps the Dagre configuration in one place: a second
 * copy would drift from this one the first time anyone tuned the spacing.
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

  return model.nodes.reduce((positions, node) => {
    const { x, y } = g.node(node.id);
    positions[node.id] = { x, y };
    return positions;
  }, {} as Positions);
};

export default computeStaticPositions;
