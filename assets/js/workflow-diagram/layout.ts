import Dagre from '../../vendor/dagre';
import { timer } from 'd3-timer';
import { getRectOfNodes, ReactFlowInstance } from 'reactflow';

import { FIT_PADDING } from './constants';
import { Flow, Positions } from './types';
import getViewportBounds, { intersect } from './util/get-viewport-bounds';

export type LayoutOpts = {
  duration: number | false;
  autofit: boolean | Flow.Node[];
};

const calculateLayout = async (
  model: Flow.Model,
  update: (newModel: Flow.Model) => any,
  flow: ReactFlowInstance,
  options: LayoutOuts = {}
): Promise<Positions> => {
  const { nodes, edges } = model;
  const { duration } = options;

  // Before we layout, work out whether there are any new unpositioned placeholders
  const newPlaceholders = model.nodes.filter(n => n.position?._default);

  const g = new Dagre.graphlib.Graph().setDefaultEdgeLabel(() => ({}));
  g.setGraph({
    rankdir: 'TB',
    // nodesep: 400,
    // edgesep: 200,
    // ranksep: 400,
  });

  edges.forEach(edge => g.setEdge(edge.source, edge.target));
  nodes.forEach(node =>
    g.setNode(node.id, { ...node, width: 350, height: 200 })
  );

  Dagre.layout(g, { disableOptimalOrderHeuristic: true });

  const newModel = {
    nodes: nodes.map(node => {
      const { x, y, width, height } = g.node(node.id);

      return { ...node, position: { x, y }, width, height };
    }),
    edges,
  };

  const finalPositions = newModel.nodes.reduce((obj, next) => {
    obj[next.id] = next.position;
    return obj;
  }, {} as Positions);

  const hasOldPositions = nodes.find(n => n.position);

  // Work out whether to zoom the view, and to what bounds
  let autofit = false;
  if (newPlaceholders.length) {
    console.log(flow.getViewport());
    console.log({ finalPositions });

    const visible = [];
    let doFit = false;
    // TODO where do I get the canvas size from?
    const rect = getViewportBounds(flow.getViewport(), 1498, 780, 1);
    console.log({ rect });
    for (const id in finalPositions) {
      const pos = finalPositions[id];
      const isInside = intersect(pos, rect);
      const node = newModel.nodes.find(n => n.id === id);
      if (isInside) {
        visible.push(node);
      } else if (node.type === 'placeholder') {
        // If the placerholder is NOT visible within the bounds,
        // we'll need to run a fit
        doFit = true;
      }
    }

    // const visibleNodes = flow.getIntersectingNodes(rect, false);
    console.log(visible.map(n => n.data?.name ?? n.type));

    if (doFit) {
      autofit = visible;
    }
  }

  // If the old model had no positions, this is a first load and we should not animate
  if (hasOldPositions && duration) {
    await animate(model, newModel, update, flow, { duration, autofit });
  } else {
    update(newModel);
  }

  return finalPositions;
};

export default calculateLayout;

export const animate = (
  from: Flow.Model,
  to: Flow.Model,
  setModel: (newModel: Flow.Model) => void,
  flowInstance: ReactFlowInstance,
  options: LayoutOpts
) => {
  const { duration = 500, autofit = true } = options;
  return new Promise<void>(resolve => {
    const transitions = to.nodes.map(node => {
      // We usually animate a node from its previous position
      let animateFrom = from.nodes.find(({ id }) => id === node.id);
      if (!animateFrom || !animateFrom.position) {
        // But if this a new node, animate from its parent (source)
        const edge = from.edges.find(({ target }) => target === node.id);
        animateFrom = from.nodes.find(({ id }) => id === edge!.source);
      }
      return {
        id: node.id,
        from: animateFrom!.position || { x: 0, y: 0 },
        to: node.position,
        node,
      };
    });

    let isFirst = true;

    // create a timer to animate the nodes to their new positions
    const t = timer((elapsed: number) => {
      const s = elapsed / (duration || 0);

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

        // TODO do we fit to ALL nodes or VISIBLE nodes, and who decides?
        let fitTarget = to.nodes;
        if (typeof autofit !== 'boolean') {
          console.log('FIT');
          fitTarget = autofit;
        }
        const bounds = getRectOfNodes(fitTarget);
        if (autofit) {
          flowInstance.fitBounds(bounds, { duration, padding: FIT_PADDING });
        }
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

        resolve();
      }
    });
  });
};
