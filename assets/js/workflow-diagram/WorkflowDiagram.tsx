import React, { useRef, useCallback, useState, useEffect } from 'react';
import ReactFlow, { Node, ReactFlowProvider, applyEdgeChanges, applyNodeChanges, ReactFlowInstance } from 'reactflow';
import layout from './layout'
import nodeTypes from './nodes';
import { Workflow } from './types';
import { FIT_DURATION, FIT_PADDING } from './constants';
import * as placeholder from './util/add-placeholder';
import fromWorkflow from './util/from-workflow';
import toWorkflow from './util/to-workflow';
import throttle from './util/throttle';

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

    console.log('UPDATING WORKFLOW', newModel, selectedId);
    if (flow && newModel.nodes.length) {
      layout(newModel, setModel, flow, 200, (positions) => {
        
        // trigger selection on new nodes once they've been passed back through to us
        if (chartCache.current.deferSelection) {
          console.log('defer selection')
          onSelectionChange(chartCache.current.deferSelection)
          delete chartCache.current.deferSelection;
        }

        // Bit of a hack - don't update positions until the animation has finished
        chartCache.current.positions = positions;
      });
    } else {
      chartCache.current.positions = {}
    }
  }, [chartCache, workflow, flow])
  
  const onNodesChange = useCallback(
    (changes) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });
    }, [setModel, model]);

  const handleKeyDown = useCallback((evt) => {
    if (evt.code === 'Enter') {
      const id = evt.target.dataset.placeholder;
      console.log('trap enter', id)
      if (id) {
        // This is so messy.... we're fighting react-flow's native selection
        // After ENTER was pressed on a placeholder, but before the change is commited,
        // When the next chart comes in, we need to ensure this new node is selected
        chartCache.current.selectedId = id;
        chartCache.current.deferSelection = id;
        // ... but we also need to ignore the event that comes out of react-flow itself
        chartCache.current.ignoreNextSelection = true
      }
    }
  }, [chartCache]);

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
    // const newNode = diff.nodes[0];

    // Don't change selection right now until the placeholder is converted
    
    // reactflow will fire a selection change event after the click
    // (regardless of whether the node is selected)
    // We essentially want to ignore that change and set the new placeholder as the selection
    chartCache.current.ignoreNextSelection = true
    // chartCache.current.selectedId = newNode.id;

    // Request a selection change when the node is passed back in
    // We have to do this because of how Lightning handles selection through the URL
    // (if we send the change too early, Lightning won't see the node and can't select it)
    // chartCache.current.deferSelection = newNode.id;

    // Push the changes to Lightning
    requestChange?.(toWorkflow(diff));
  }, [requestChange]);

  // Note that we only support a single selection
  const handleSelectionChange = useCallback(({ nodes, edges }) => {
    console.log('> handleSelectionChange', nodes.map(({ id }) => id))
    const { selectedId, ignoreNextSelection } = chartCache.current;
    const newSelectedId = nodes.length ? nodes[0].id : (edges.length ? edges[0].id : undefined)
    if (ignoreNextSelection) {
      // do nothing as the ignore flag was set
    }
    else if (newSelectedId !== selectedId) {
      chartCache.current.selectedId = newSelectedId;
      onSelectionChange(newSelectedId);
    }
    chartCache.current.ignoreNextSelection = undefined;
  }, [onSelectionChange]);

  // Trigger a fit when the parent div changes size
  useEffect(() => {
    if (flow && ref) {
      let isFirstCallback = true;

      const throttledResize = throttle(() => {
        flow.fitView({ duration: FIT_DURATION, padding: FIT_PADDING })
      }, FIT_DURATION * 2);

      const resizeOb = new ResizeObserver(function (entries) {
        if (!isFirstCallback) {
          // Don't fit when the listener attaches (it callsback immediately)
          throttledResize();
        }
        isFirstCallback = false;
      });
      resizeOb.observe(ref);
    
      return () => {
        throttledResize.cancel();
        resizeOb.unobserve(ref);
      };
    }
  }, [flow, ref]);
  
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
        onKeyUp={handleKeyDown}
        onInit={setFlowInstance}
        deleteKeyCode={null}
        fitView
        fitViewOptions={{ padding: FIT_PADDING }}
      />
    </ReactFlowProvider>
})