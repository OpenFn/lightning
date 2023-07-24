import React, { useCallback, useEffect, useMemo, useRef } from 'react';
import JobNode from './nodes/JobNode';
import OperationNode from './nodes/OperationNode';
import TriggerWorkflowNode from './nodes/TriggerWorkflowNode';

import EmptyWorkflowNode from './nodes/EmptyWorkflowNode';
import ReactFlow, { Node, ReactFlowProvider } from 'reactflow';
import './main.css';
import * as Store from './store';
import { NodeData } from './layout/types';

const nodeTypes = {
  job: JobNode,
  operation: OperationNode,
  trigger: TriggerWorkflowNode,
  workflow: EmptyWorkflowNode,
};

const WorkflowDiagram = React.forwardRef<
  Element,
  {
    onJobAddClick?: (node: Node<NodeData>) => void;
    onNodeClick?: (event: React.MouseEvent, node: Node<NodeData>) => void;
    onPaneClick?: (event: React.MouseEvent) => void;
  }
>(({ onNodeClick, onPaneClick, onJobAddClick }, ref) => {
  const { nodes, edges, onNodesChange, onEdgesChange } = Store.useStore();

  const handleNodeClick = useCallback(
    (event: React.MouseEvent, node: Node<NodeData>) => {
      const plusIds = new Set(['plusButton', 'plusIcon']);
      event.stopPropagation();

      if (plusIds.has(event.target.id) && onJobAddClick) {
        onJobAddClick(node);
      } else {
        if (onNodeClick) {
          onNodeClick(event, node);
        }
      }
    },
    [onJobAddClick, onNodeClick]
  );

  // Observe any changes to the parent div, and trigger
  // a `fitView` to recenter the diagram.
  useEffect(() => {
    if (ref) {
      const resizeOb = new ResizeObserver(function (_entries) {
        Store.fitView();
      });
      resizeOb.observe(ref);
      return () => {
        resizeOb.unobserve(ref);
      };
    }
  }, [ref]);

  // TODO: Remove workflow nodes properly in https://github.com/OpenFn/Lightning/issues/316
  // Note: this is TD's ugly hack to solve https://github.com/OpenFn/Lightning/issues/733
  const nakedNodes = nodes
    .filter(node => !(node.type == 'workflow'))
    .map(node => {
      return { ...node, parentNode: null };
    });

  return (
    <ReactFlowProvider>
      <ReactFlow
        // Thank you, Christopher Möller, for explaining that we can use this...
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={nakedNodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        // onSelectionChange={onSelectedNodeChange}
        // onConnect={onConnect}
        // If we let folks drag, we have to save new visual configuration...
        nodesDraggable={false}
        // No interaction for this yet...
        nodesConnectable={false}
        nodeTypes={nodeTypes}
        snapToGrid={true}
        snapGrid={[10, 10]}
        onNodeClick={handleNodeClick}
        onPaneClick={onPaneClick}
        onInit={Store.setReactFlowInstance}
        fitView
      />
    </ReactFlowProvider>
  );
});

export { Store };
export default WorkflowDiagram;
