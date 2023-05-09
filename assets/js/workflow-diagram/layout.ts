import { getRectOfNodes, Node, Edge } from 'reactflow';
import { stratify, tree } from 'd3-hierarchy';
import { timer } from 'd3-timer';
import {
  FIT_DURATION,
  FIT_PADDING,
  NODE_HEIGHT,
  NODE_WIDTH,
} from './constants';

const layout = tree<Node>()
  // the node size configures the spacing between the nodes ([width, height])
  .nodeSize([200, 150])
  // this is needed for creating equal space between all nodes
  .separation(() => 1);

type Model = { nodes: Node[]; edges: Edge[] };

const calculateLayout = (
  model: Model,
  update,
  flow,
  duration: number | false = 500,
  onComplete
) => {
  const { nodes, edges } = model;
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
    width: d.width || NODE_WIDTH,
    height: d.height || NODE_HEIGHT,
  }));

  const newModel = { nodes: newNodes, edges };

  const hasOldPositions = nodes.find(n => n.position);

  // If the old model had no positions, this is a first load and we should not animate
  if (hasOldPositions && duration) {
    animate(model, newModel, update, flow, duration, onComplete);
  } else {
    update(newModel);

    // TODO deal with this
    if (onComplete) {
      const positions = newNodes.reduce((obj, next) => {
        obj[next.id] = next.position;
        return obj;
      }, {});
      onComplete(positions);
    }
  }

  // TODO deal with this
  return newNodes.reduce((obj, next) => {
    obj[next.id] = next.position;
    return obj;
  }, {});
};

export default calculateLayout;

export const animate = (
  from,
  to,
  setModel,
  flowInstance,
  duration = 500,
  onComplete
) => {
  const transitions = to.nodes.map(node => {
    // We usually animate a node from its previous position
    let animateFrom = from.nodes.find(({ id }) => id === node.id);
    if (!animateFrom || !animateFrom.position) {
      // But if this a node node, animate from its parent (source)
      const edge = from.edges.find(({ target }) => target === node.id);
      animateFrom = from.nodes.find(({ id }) => id === edge.source);
    }
    return {
      id: node.id,
      from: animateFrom.position || { x: 0, y: 0 },
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
      // Synchronise a fit to the final position with the same duration
      const bounds = getRectOfNodes(to.nodes);
      flowInstance.fitBounds(bounds, { duration, padding: FIT_PADDING });
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

      // TODO deal with this
      if (onComplete) {
        const positions = to.nodes.reduce((obj, next) => {
          obj[next.id] = next.position;
          return obj;
        }, {});
        onComplete(positions);
      }
    }
  });
};
