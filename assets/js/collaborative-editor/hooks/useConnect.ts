import type * as F from '@xyflow/react';
import React, { useCallback, useState } from 'react';

import { randomUUID } from '../../common';
import Connection from '../../workflow-diagram/edges/Connection';
import type { Flow } from '../../workflow-diagram/types';
import { getDropTargetError } from '../../workflow-diagram/useConnect';
import type { Session } from '../types/session';

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

interface WorkflowStoreActions {
  addEdge: (edge: Partial<Session.Edge>) => void;
}

export default (
  model: Flow.Model,
  setModel: React.Dispatch<React.SetStateAction<Flow.Model>>,
  addPlaceholder: (node: Flow.Node, where?: F.XYPosition) => void,
  bgClick: () => void,
  flow: F.ReactFlowInstance,
  workflowStore: WorkflowStoreActions
) => {
  const [dragActive, setDragActive] = useState<string | false>(false);

  const onConnect: F.OnConnect = useCallback(
    args => {
      // TODO: This edge creation logic is duplicated in WorkflowDiagram.tsx
      // (handleCommit function). Consider extracting to a shared helper like
      // createEdgeForSource() to avoid inconsistencies.

      // Generate edge data
      const newEdge: Partial<Session.Edge> = {
        id: randomUUID(),
        source_job_id: null,
        source_trigger_id: null,
        target_job_id: args.target,
        condition_type: 'on_job_success',
        enabled: true,
      };

      // Determine if source is job or trigger
      const sourceNode = model.nodes.find(n => n.id === args.source);
      if (sourceNode?.type === 'trigger') {
        newEdge.source_trigger_id = args.source;
      } else {
        newEdge.source_job_id = args.source;
      }

      // Add to Y.Doc store
      workflowStore.addEdge(newEdge);

      setDragActive(false);
    },
    [model, workflowStore]
  );

  const onConnectStart: F.OnConnectStart = useCallback(
    (_evt, args) => {
      if (!args.nodeId) return;
      setDragActive(args.nodeId);
      setModel(setValidDropTargets(model, args.nodeId));
    },
    [model, setModel]
  );

  const onClick = useCallback(
    (event: React.MouseEvent) => {
      if (
        event.target instanceof HTMLElement &&
        event.target.classList.contains('react-flow__pane') &&
        !dragActive
      ) {
        bgClick();
      }
    },
    [dragActive, bgClick]
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
            // dropped connect line on empty space -> show adaptor modal
            // & deactivate drag.
            addPlaceholder(node, position);
            setDragActive(false);
          }
        }, 0);
      }
    },
    [model, addPlaceholder, flow, setModel]
  );

  const onNodeMouseEnter: F.NodeMouseHandler = useCallback(
    (_evt, args) => {
      if (dragActive) {
        setModel(setActiveDropTarget(model, args.id));
      }
    },
    [model, dragActive, setModel]
  );

  const onNodeMouseLeave: F.NodeMouseHandler = useCallback(
    (_evt, _args) => {
      if (dragActive) {
        setModel(setActiveDropTarget(model, ''));
      }
    },
    [model, dragActive, setModel]
  );

  const isValidConnection = useCallback(
    ({ source, target }: F.Connection): boolean => {
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
