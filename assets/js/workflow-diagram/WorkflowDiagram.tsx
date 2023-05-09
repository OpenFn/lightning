import React, { useRef, useCallback, useState, useEffect } from 'react';
import ReactFlow, { Node, ReactFlowProvider, applyEdgeChanges, applyNodeChanges, ReactFlowInstance } from 'reactflow';
import layout, { animate } from './layout'
import nodeTypes from './nodes';
import { Workflow } from './types';
import * as placeholder from './util/add-placeholder';
import fromWorkflow from './util/from-workflow';
import toWorkflow from './util/to-workflow';

const FIT_DURATION = 180;

type WorkflowDiagramProps = {
  workflow: Workflow;
  onSelectionChange: (id: string) => void;
  requestChange: (id: string) => void;
}
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

  const fitRef = useRef({
    isFitting: false,
    fitAgain: false,
  });

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
      fitRef.isFitting = true;
      layout(newModel, setModel, flow, 200, (positions) => {
        
        // trigger selection on new nodes once they've been passed back through to us
        if (chartCache.current.deferSelection) {
          onSelectionChange(chartCache.current.deferSelection)
          delete chartCache.current.deferSelection;
        }

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

    // Request a selection change when the node is passed back in
    // We have to do this because of how Lightning handles selection through the URL
    // (if we send the change too early, Lightning won't see the node and can't select it)
    chartCache.current.deferSelection = newNode.id;

    // Push the changes to Lightning
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

  // TODO this is super intricate because I was trying some stuff
  // We can probably replace it with a nice debounce or throttle now
  const doFit = useCallback(() => {
    if (fitRef.current.isFitting) {
      fitRef.current.fitAgain = true;
    } else {
      fitRef.current.isFitting = true;
      fitRef.current.fitAgain = false;
      flow.fitView({ duration: FIT_DURATION });
      fitRef.current.timeout = setTimeout(() => {
        fitRef.current.isFitting = false;
        if (fitRef.current.fitAgain) {
          doFit();
        }
      }, FIT_DURATION * 2);
    }

    return () => {
      clearTimeout(fitRef.current.timeout)
    }
  }, [flow, fitRef]);

  // Observe any changes to the parent div, and trigger
  // a `fitView` to recenter the diagram.
  // TODO if a request comes in during a resize, wait for the previous to finish
  // (and add a delay) before resuming
  useEffect(() => {
    if (ref) {
      const resizeOb = new ResizeObserver(function (_entries) {
        doFit()
      });
      resizeOb.observe(ref);
    
      return () => {
        resizeOb.unobserve(ref);
      };
    }
  }, [ref, doFit]);
  
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