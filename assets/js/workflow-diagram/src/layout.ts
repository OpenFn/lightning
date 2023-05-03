import { useEffect, useRef } from 'react';
import { getRectOfNodes } from 'react-flow-renderer';
import type { Node, Edge } from 'reactflow';
import { stratify, tree } from 'd3-hierarchy';
import { timer } from 'd3-timer';

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

  const newNodes = root.descendants().map(d => ({
    ...d.data,
    position: { x: d.x, y: d.y },
    // Ensure nodes have a width/height so that we can later do a fit to bounds
    width: d.width || 150,
    height: d.height || 40,
  }));

  return { nodes: newNodes, edges };
};

export const animate = (from, to, setModel, flowInstance, duration = 500) => {
  const transitions = to.nodes.map(node => {
    const oldNode = from.nodes.find(({ id }) => id === node.id);
    return {
      id: node.id,
      from: oldNode.position,
      to: node.position,
      node,
    };
  });

  let isFirst = true;

  // create a timer to animate the nodes to their new positions
  const t = timer((elapsed: number) => {
    const s = elapsed / duration;

    const currNodes = transitions.map(({ node, from, to }) => ({
      ...node,
      position: {
        // simple linear interpolation
        x: from.x + (to.x - from.x) * s,
        y: from.y + (to.y - from.y) * s,
      },
    }));

    setModel({ edges: to.edges, nodes: currNodes });

    if (isFirst) {
      const bounds = getRectOfNodes(to.nodes);
      flowInstance.fitBounds(bounds, { duration });
      isFirst = false;
    }

    // this is the final step of the animation
    if (elapsed > duration) {
      // we are moving the nodes to their destination
      // this needs to happen to avoid glitches
      const finalNodes = transitions.map(({ node, to }) => ({
        ...node,
        position: {
          x: to.x,
          y: to.y,
        },
      }));

      setModel({ edges: to.edges, nodes: finalNodes });

      // stop the animation
      t.stop();
    }
  });
};
