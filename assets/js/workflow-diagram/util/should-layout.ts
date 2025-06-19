// This function will determine whether we should run a layout on a model
// This generates a simple hash from the edges and compares it to the last hash
import type { Flow } from '../types';

// this function should consider node types too.
// with just edges. it misses the case where a node goes from placeholder to node.
// we need that to be tracked so that new position data for the placeholder component stored in the store will be used for rendering.
// without it. an actual new render wouldn't happen. and [0, 0] would be used for this new node in the model
export default (edges: Flow.Edge[], nodes: Flow.Node[], lastHash?: string) => {
  const nodesId = nodes
    .map(n => n.type || '')
    .sort()
    .join('-');
  const edgesId = edges
    .map(e => `${e.source}-${e.target}`)
    .sort()
    .join('--');

  const id = nodesId + edgesId;

  if (id !== lastHash) {
    return id;
  }
};
