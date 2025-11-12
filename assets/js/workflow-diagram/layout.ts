import type { ReactFlowInstance } from '@xyflow/react';
import { timer } from 'd3-timer';

import Dagre from '../../vendor/dagre.cjs';

import { FIT_PADDING, NODE_HEIGHT, NODE_WIDTH } from './constants';
import type { Flow, Positions } from './types';
import { getVisibleRect, isPointInRect } from './util/viewport';

export type LayoutOpts = {
  duration?: number | false;
  autofit?: boolean | Flow.Node[];
  forceFit?: boolean;
};

const calculateLayout = async (
  model: Flow.Model,
  update: (newModel: Flow.Model) => any,
  flow: ReactFlowInstance,
  viewBounds: { width: number; height: number },
  options: Omit<LayoutOpts, 'autofit'> = {}
): Promise<Positions> => {
  const { nodes, edges } = model;
  const { duration } = options;

  // Before we layout, work out whether there are any new unpositioned placeholders
  // @ts-ignore _default is a temporary flag added by us
  const newPlaceholders = model.nodes.filter(n => n.position?._default);

  const g = new Dagre.graphlib.Graph().setDefaultEdgeLabel(() => ({}));
  g.setGraph({
    rankdir: 'TB',
    nodesep: 250,
    edgesep: 200,
    ranksep: 150,
  });

  edges.forEach(edge => g.setEdge(edge.source, edge.target));
  nodes.forEach(node =>
    g.setNode(node.id, { ...node, width: NODE_WIDTH, height: NODE_HEIGHT })
  );

  Dagre.layout(g, { disableOptimalOrderHeuristic: true });

  const newModel = {
    nodes: nodes.map(node => {
      const { x, y, width, height } = g.node(node.id);

      return {
        ...node,
        position: { x, y, width, height },
      };
    }),
    edges,
  };

  const finalPositions = newModel.nodes.reduce((obj, next) => {
    obj[next.id] = next.position;
    return obj;
  }, {} as Positions);

  const hasOldPositions = nodes.find(n => n.position);

  let autofit: LayoutOpts['autofit'] = false;
  let doFit: boolean = false;
  const fitTargets: Flow.Node[] = [];

  if (hasOldPositions) {
    const oldPositions = nodes.reduce((obj, next) => {
      obj[next.id] = next.position;
      return obj;
    }, {} as Positions);

    // When updating the layout, we should try and fit to the currently visible nodes
    // This usually just occurs when adding or removing placeholder nodes

    // First work out the size of the current viewpoint in canvas coordinates
    if (newPlaceholders.length) {
      const rect = getVisibleRect(flow.getViewport(), viewBounds, 0.9);
      // Now work out the visible nodes, paying special attention to the placeholder
      //
      for (const id in finalPositions) {
        // Check the node's old position to see if it was visible before the layout
        // if it's a new node, take the new position
        const pos = oldPositions[id] || finalPositions[id];
        const isInside = isPointInRect(pos, rect);
        const node = newModel.nodes.find(n => n.id === id)!;

        if (isInside) {
          // if the node was previously visible, add it to the fit list
          fitTargets.push(node);
          // but also, if the NEW position is NOT visible, we need to force a layout
          if (!doFit && !isPointInRect(finalPositions[id], rect)) {
            doFit = true;
          }
        } else if (node?.type === 'placeholder') {
          // If the placeholder is NOT visible within the bounds,
          // include it in the set of visible nodes and force a fit
          doFit = true;
          fitTargets.push({
            ...node,
            // cheat on the size so we get a better fit
            height: 100,
            width: 100,
          });
        }
      }
    } else {
      // otherwise, if running a layout, fit to the currently visible nodes
      // this usually means we've removed a placeholder and lets us tidy up
      doFit = true;
      const rect = getVisibleRect(flow.getViewport(), viewBounds, 1.1);
      for (const id in finalPositions) {
        // again, use the OLD position to work out visibility
        const pos = oldPositions[id] || finalPositions[id];
        const isInside = isPointInRect(pos, rect);
        if (isInside) {
          const node = newModel.nodes.find(n => n.id === id)!;
          fitTargets.push(node);
        }
      }
    }

    // Useful debugging
    //console.log(fitTargets.map(n => n.data?.name ?? n.type));
  }

  // If we need to run a fit, save the set of visible nodes as the fit target
  if (doFit) {
    autofit = fitTargets;
  }

  // If the old model had no positions, this is a first load and we should not animate
  if (hasOldPositions && duration) {
    await animate(model, newModel, update, flow, { duration, autofit });
  } else {
    update(newModel);

    // Force a fit with animation
    if (options.forceFit) {
      setTimeout(() => {
        flow.fitView({
          duration: typeof duration === 'number' ? duration : 500,
          padding: FIT_PADDING,
        });
      }, 20);
    }
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
        if (edge) {
          animateFrom = from.nodes.find(({ id }) => id === edge.source);
        }
      }

      // If we still don't have a valid position to animate from,
      // use the node's current position (instant placement, no animation)
      const fromPosition = animateFrom?.position ?? node.position;

      return {
        id: node.id,
        from: fromPosition,
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
        let fitTarget = to.nodes;
        if (typeof autofit !== 'boolean') {
          fitTarget = autofit;
        }
        const bounds = flowInstance.getNodesBounds(fitTarget);
        if (autofit) {
          flowInstance.fitBounds(bounds, {
            duration: typeof duration === 'number' ? duration : 0,
            padding: FIT_PADDING,
          });
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
