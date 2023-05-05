import React, { useMemo, useCallback, useState, useEffect } from 'react';
import ReactFlow, { Node, ReactFlowProvider, applyEdgeChanges, applyNodeChanges } from 'reactflow';
import layout, { animate } from './layout'
import nodeTypes from './nodes';
import { Workflow } from './types';
import addPlaceholder from './util/add-placeholder';
import fromWorkflow from './util/from-workflow';
import toWorkflow from './util/to-workflow';

type WorkflowDiagramProps = {
  workflow: Workflow;
  onNodeSelected: (id: string) => void;
}

// Not sure on the relationship to the store
// I kinda just want the component to do visalusation and fir eevents
// Does it even know about zustand? Any benefit?

// So in controlled mode things get difficult
// the component has to track internal chart state, like selection,
// as well as incoming changes from the server (like node state change)
export default React.forwardRef<Element, WorkflowDiagramProps>((props, ref) => {
  const { workflow, requestChange, onSelectionChange } = props;
  const [model, setModel] = useState({ nodes: [], edges: [] });
  
  // Track positions internally, so that when incoming changes come in,
  // we can preserve positions and/or animate properly
  const [positions, setPositions] = useState({});

  // TODO can selection just be a flat object? Easier to maintain state this way
  const [selected, setSelected] = useState({ nodes: {}, edges: {} });
  
  const [flow, setFlow] = useState();

  const setFlowInstance = useCallback((s) => {
    setFlow(s)
  }, [setFlow])

  // Respond to changes pushed into the component from outside
  // This usually means the workflow has changed or its the first load, so we don't want to animate
  // Later, if responding to changes from other users live, we may want to animate
  useEffect(() => {
    const newModel = fromWorkflow(workflow, positions);

    console.log('UPDATING WORKFLOW', newModel);
    if (flow && newModel.nodes.length) {
      const positions = layout(newModel, setModel, flow, 500)
      setPositions(positions)
    } else {
      setPositions({})
    }
  }, [workflow, flow, setModel])
  
  const onNodesChange = useCallback(
    (changes) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });
    }, [setModel, model]);

  const handleNodeClick = useCallback((event: React.MouseEvent, node: Node<NodeData>) => {
    event.stopPropagation();
    if (event.target.closest('[name=add-node]')) {
      addNode(node);
    }
  }, [model])
  
  const addNode = useCallback((parentNode: Node) => {
    // Generate a placeholder node and edge
    const diff = addPlaceholder(model, parentNode);
    requestChange?.(toWorkflow(diff));
  }, [requestChange]);

  const handleSelectionChange = useCallback(({ nodes, edges }) => {
    const everything = nodes.concat(edges);
    console.log('selection change', everything)
    const selection = everything.map(({ id }) => id);
    onSelectionChange(selection);
  }, [onSelectionChange]);

    // Observe any changes to the parent div, and trigger
  // a `fitView` to recenter the diagram.
  useEffect(() => {
    if (ref && flow) {
      const resizeOb = new ResizeObserver(function (_entries) {
        // Animate? I think I prefer it without...
        flow.fitView();
      });
      resizeOb.observe(ref);
      return () => {
        resizeOb.unobserve(ref);
      };
    }
  }, [ref, flow]);
  
  return <ReactFlowProvider>
      <ReactFlow
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={model.nodes}
        edges={model.edges}
        onSelectionChange={handleSelectionChange}
        onNodesChange={onNodesChange}
        nodesDraggable={false}
        nodeTypes={nodeTypes}
        onNodeClick={handleNodeClick}
        onInit={setFlowInstance}
        fitView
      />
    </ReactFlowProvider>
})