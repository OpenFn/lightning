import React, { useCallback, useEffect, useMemo } from 'react';
import JobNode from './nodes/JobNode';
import OperationNode from './nodes/OperationNode';
import TriggerWorkflowNode from './nodes/TriggerWorkflowNode';
import type { ProjectSpace } from './types';

import EmptyWorkflowNode from './nodes/EmptyWorkflowNode';
import ReactFlow, { Node, ReactFlowProvider } from 'react-flow-renderer';
import './main.css';
import * as Store from './store';
import { NodeData } from './layout/types';

const nodeTypes = {
  job: JobNode,
  operation: OperationNode,
  trigger: TriggerWorkflowNode,
  workflow: EmptyWorkflowNode,
};

const WorkflowDiagram: React.FC<{
  projectSpace: ProjectSpace;
  onJobAddClick?: (node: Node<NodeData>) => void;
  onNodeClick?: (event: React.MouseEvent, node: Node<NodeData>) => void;
  onPaneClick?: (event: React.MouseEvent) => void;
}> = ({ projectSpace, onNodeClick, onPaneClick, onJobAddClick }) => {
  const { nodes, edges, onNodesChange, onEdgesChange } = Store.useStore();

  const handleNodeClick = useCallback(
    (event: React.MouseEvent, node: Node<NodeData>) => {
      const plusIds = new Set(['plusButton', 'plusIcon']);
      if (plusIds.has(event.target.id) && onJobAddClick) {
        event.stopPropagation();

        onJobAddClick(node);
      } else {
        if (onNodeClick) {
          onNodeClick(event, node);
        }
      }
    },
    [onJobAddClick, onNodeClick]
  );

  useEffect(() => {
    if (projectSpace) {
      Store.setProjectSpace(projectSpace);
    }
  }, [projectSpace]);

  return (
    <ReactFlowProvider>
      <ReactFlow
        // Thank you, Christopher Möller, for explaining that we can use this...
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
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
        fitView
      />
    </ReactFlowProvider>
  );
};

export { Store };
export default WorkflowDiagram;
