import type * as F from '@xyflow/react';
import React, { useCallback, useState } from 'react';

import { randomUUID } from '../common';
import { useWorkflowStore } from '../workflow-store/store';

import Connection from './edges/Connection';
import { styleEdge } from './styles';
import type { Flow } from './types';
import toWorkflow from './util/to-workflow';

const generateEdgeDiff = (source: string, target: string) => {
  const newEdge = styleEdge({
    id: randomUUID(),
    type: 'step',
    source,
    target,
    data: {
      enabled: true,
      condition_type: 'on_job_success',
    },
  });

  // this is just a diff
  const updatedModel = {
    nodes: [],
    edges: [newEdge],
  };

  return updatedModel;
};

// Returns true if nodeInQuestion is a descendant of the root
// TODO memoise this
const isUpstream = (
  model: Flow.Model,
  parent: string,
  nodeInQuestion: string
) => {
  // walk down the graph from parent, return true if we ever hit the node in question
  const edges = model.edges.filter(e => e.source === parent);
  for (const edge of edges) {
    if (
      edge.target === nodeInQuestion ||
      isUpstream(model, edge.target, nodeInQuestion)
    ) {
      return true;
    }
  }
  return false;
};
const isChild = (model: Flow.Model, sourceNode: string, targetNode: string) => {
  const edges = model.edges.filter(e => e.source === sourceNode);

  return edges.find(e => e.target === targetNode);
};

const getDropTargetError = (
  model: Flow.Model,
  source: string,
  target: string
) => {
  if (target === source) {
    return true;
  }
  const targetNode = model.nodes.find(n => n.id === target);

  if (targetNode?.type === 'trigger') {
    return 'Cannot connect to a trigger';
  }

  if (isUpstream(model, target, source)) {
    // Don't allow linking to direct ancestors, as it'll cause a loop
    return 'Cannot create circular workflow';
  }

  if (isChild(model, source, target)) {
    // Don't allow an edge to be created if it exists
    return 'Already connected to this step';
  }
};

const setValidDropTargets = (model: Flow.Model, source: string) => {
  const newModel = {
    nodes: model.nodes.map(n => {
      const err = getDropTargetError(model, source, n.id);
      return {
        ...n,
        data: {
          ...n.data,
          isValidDropTarget: !err,
          dropTargetError: err,
        },
      };
    }),
    edges: model.edges,
  };
  return newModel;
};

const setActiveDropTarget = (model: Flow.Model, target: string) => {
  const newModel = {
    nodes: model.nodes.map(n => ({
      ...n,
      data: {
        ...n.data,
        isActiveDropTarget: n.id === target,
      },
    })),
    edges: model.edges,
  };

  return newModel;
};

const resetModel = (model: Flow.Model) => ({
  nodes: model.nodes.map(n => ({
    ...n,
    data: {
      ...n.data,
      isValidDropTarget: false,
      isActiveDropTarget: false,
    },
  })),
  edges: model.edges,
});

// Export validation functions for testing
export { isUpstream, isChild, getDropTargetError };

export default (
  model: Flow.Model,
  setModel: React.Dispatch<React.SetStateAction<Flow.Model>>,
  addPlaceholder: (node: Flow.Node, where?: F.XYPosition) => void,
  bgClick: () => void,
  flow: F.ReactFlowInstance
) => {
  const [dragActive, setDragActive] = useState<string | false>(false);
  const { add: addTo } = useWorkflowStore();

  const onConnect: F.OnConnect = useCallback(args => {
    const newModel = generateEdgeDiff(args.source, args.target);
    const wf = toWorkflow(newModel);

    setDragActive(false);
    addTo(wf);
  }, []);

  const onConnectStart: F.OnConnectStart = useCallback(
    (_evt, args) => {
      setDragActive(args.nodeId);
      setModel(setValidDropTargets(model, args.nodeId));
    },
    [model]
  );

  const onClick = useCallback(
    (event: React.MouseEvent) => {
      if (
        event.target instanceof HTMLElement &&
        event.target.classList?.contains('react-flow__pane') &&
        !dragActive
      ) {
        bgClick();
      }
    },
    [dragActive]
  );

  const onConnectEnd: F.OnConnectEnd = useCallback(
    (evt, connectionState) => {
      if (!connectionState.isValid) {
        evt.stopPropagation();
        evt.preventDefault();
        const { clientX, clientY } =
          'changedTouches' in evt ? evt.changedTouches[0] : evt;

        // Use screenToFlowPosition to calculate flow coordinates
        const position = flow.screenToFlowPosition({
          x: clientX,
          y: clientY,
        });

        // Give time for any deselection to take place
        // when in auto-layout mode
        const node = connectionState.fromNode;
        if (!node) return;

        // reset model to reverse setValidDropTarget
        setModel(resetModel(model));

        // wait for any deselection to be done!
        setTimeout(() => {
          const isOnNode = (evt.target as HTMLElement).closest('[data-a-node]');
          if (isOnNode) {
            // dropped connect line on an existing node -> do nothing
            setDragActive(false);
            return;
          } else {
            // dropped connect line on an empty space -> create placeholder & deactivate drag.
            addPlaceholder(node, position);
            setDragActive(false);
          }
        }, 0);
      }
    },
    [model, addPlaceholder]
  );

  const onNodeMouseEnter: F.NodeMouseHandler = useCallback(
    (evt, args) => {
      if (dragActive) {
        setModel(setActiveDropTarget(model, args.id));
      }
    },
    [model]
  );

  const onNodeMouseLeave: F.NodeMouseHandler = useCallback(
    (evt, args) => {
      if (dragActive) {
        setModel(setActiveDropTarget(model, ''));
      }
    },
    [model]
  );

  const isValidConnection = useCallback(
    ({ source, target }: F.Connection): boolean => {
      // this is accessing a stale model :( why?
      // const targetNode = model.nodes.find(e => e.id === target);
      // return targetNode?.data.isValidDropTarget;

      // it'll work suboptimally if we duplicate the validation test
      // This fires a lot so its super annoying
      const err = getDropTargetError(model, source, target);
      return !err;
    },
    [model]
  );

  return {
    connectionLineComponent: Connection,
    onConnect,
    onConnectStart,
    onConnectEnd,
    onNodeMouseEnter,
    onNodeMouseLeave,
    isValidConnection,
    onClick,
  };
};
