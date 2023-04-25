import { useEffect, useRef } from 'react';
import type { Node, Edge } from 'reactflow';
import { stratify, tree } from 'd3-hierarchy';
// import { timer } from 'd3-timer';

const layout = tree<Node>()
  // the node size configures the spacing between the nodes ([width, height])
  .nodeSize([200, 150])
  // this is needed for creating equal space between all nodes
  .separation(() => 1);

export default ({ nodes, edges }: { nodes: Node[]; edges: Edge[] }) => {
  const hierarchy = stratify<Node>()
    .id(d => d.id)
    // get the id of each node by searching through the edges
    // this only works if every node has one connection
    .parentId(d => edges.find(e => e.target === d.id)?.source)(nodes);

  // run the layout algorithm with the hierarchy data structure
  const root = layout(hierarchy);

  const newNodes = root
    .descendants()
    .map(d => ({ ...d.data, position: { x: d.x, y: d.y } }));

  return { nodes: newNodes, edges };
};
