import type { Flow, Positions } from './types';

export const ensureNodePosition = (
  model: Flow.Model,
  positions: Positions,
  node: Flow.Node,
  positionOffsetMap: Record<string, number> = {}
) => {
  if (!node.position) {
    // Try and find the first parent node in the tree, and append to that
    let bestParent;
    let currentNodeId = node.id;
    while (currentNodeId && !bestParent) {
      const edge = model.edges.find(e => e.target === currentNodeId);
      if (edge) {
        currentNodeId = edge.source;

        const parent = positions[edge.source];
        if (parent) {
          bestParent = {
            id: edge.source,
            ...parent,
          };
        }
      } else {
        break;
      }
    }
    if (bestParent) {
      if (bestParent.id in positionOffsetMap) {
        positionOffsetMap[bestParent.id] += 30;
      } else {
        positionOffsetMap[bestParent.id] = 0;
      }

      const offset = positionOffsetMap[bestParent.id];
      node.position = {
        x: bestParent.x + offset,
        y: bestParent.y + 227 /* magic number */ + offset,
      };
      return true;
    } else {
      // Only warn if positions map has data but we still couldn't find a parent
      // Empty positions on initial render is expected before layout runs
      const hasPositions = Object.keys(positions).length > 0;
      if (hasPositions) {
        console.warn(
          'WARNING: could not auto-calculate position for ',
          node.id
        );
      }
      node.position = { x: 0, y: 0 };
    }
  }
};
