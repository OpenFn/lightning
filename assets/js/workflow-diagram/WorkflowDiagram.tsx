import React, { useRef, useCallback, useState, useEffect } from 'react';
import ReactFlow, { Node, ReactFlowProvider, applyEdgeChanges, applyNodeChanges, ReactFlowInstance } from 'reactflow';
import layout, { animate } from './layout'
import nodeTypes from './nodes';
import { Workflow } from './types';
import * as placeholder from './util/add-placeholder';
import fromWorkflow from './util/from-workflow';
import toWorkflow from './util/to-workflow';

type WorkflowDiagramProps = {
  workflow: Workflow;
  onSelectionChange: (id: string) => void;
  requestChange: (id: string) => void;
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
  
  // Track positions and selection on a ref, as a passive cache, to prevent re-renders
  // If I push the store in here and use it more, will I have to do this less...?
  const chartCache = useRef({
    positions: {},
    selectedId: undefined,
    ignoreNextSelection: undefined, // awful workaround because I can't control selection
  })

  const [flow, setFlow] = useState<ReactFlowInstance>();

  const setFlowInstance = useCallback((s) => {
    setFlow(s)
  }, [setFlow])

  // Respond to changes pushed into the component from outside
  // This usually means the workflow has changed or its the first load, so we don't want to animate
  // Later, if responding to changes from other users live, we may want to animate
  useEffect(() => {
    const { positions, selectedId } = chartCache.current;
    const newModel = fromWorkflow(workflow, positions, selectedId);

    console.log('UPDATING WORKFLOW', newModel);
    if (flow && newModel.nodes.length) {
      layout(newModel, setModel, flow, 200, (positions) => {
        // Bit of a hack - don't update positions until the animation has finished
        chartCache.current.positions = positions;
      });
    } else {
      chartCache.current.positions = {}
    }
  }, [workflow, flow])
  
  const onNodesChange = useCallback(
    (changes) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });
    }, [setModel, model]);

  const handleNodeClick = useCallback((event: React.MouseEvent, node: Node<NodeData>) => {
    event.stopPropagation();
    event.preventDefault()
    if (event.target.closest('[name=add-node]')) {
      addNode(node);
      // TODO how do I stop selection changing here?
    }
  }, [model])
  
  const addNode = useCallback((parentNode: Node) => {
    // Generate a placeholder node and edge
    const diff = placeholder.add(model, parentNode);
    const newNode = diff.nodes[0];
    
    // reactflow will fire a selection change event after the click
    // (regardless of whether the node is selected)
    // We essentially want to ignore that change and set the new placeholder as the selection
    chartCache.current.ignoreNextSelection = true
    chartCache.current.selectedId = newNode.id;
    requestChange?.(toWorkflow(diff));
  }, [requestChange]);

  // Note that we only support a single selection
  const handleSelectionChange = useCallback(({ nodes }) => {
    const { selectedId, ignoreNextSelection } = chartCache.current;
    const newSelectedId = nodes.length ? nodes[0].id : undefined
    if (ignoreNextSelection) {
      // do nothing as the ignore flag was set
    }
    else if (newSelectedId !== selectedId) {
      chartCache.current.selectedId = newSelectedId;
      onSelectionChange(newSelectedId);
    }
    chartCache.current.ignoreNextSelection = undefined;
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