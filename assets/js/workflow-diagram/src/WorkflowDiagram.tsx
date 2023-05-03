import React, { useMemo, useCallback, useState, useEffect } from 'react';
import ReactFlow, { Node, ReactFlowProvider, applyEdgeChanges, applyNodeChanges } from 'react-flow-renderer';
import layout, { animate } from './layout'
import nodeTypes from './nodes';
import { Workflow } from './types';
import addPlaceholder from './util/add-placeholder';

type WorkflowDiagramProps = {
  workflow: Workflow;
  onNodeSelected: (id: string) => void;
}

// TODO pass in the currently selected items so that we can maintain selection
const fromWorkflow = (workflow: Workflow, selection: Record<string, true>) => {
  if (workflow.jobs.length == 0) {
    return { nodes: [], edges: [] }
  }

  const nodes = [] as any[];
  const edges = [] as any[];

  const process = (items: any[], collection: any[], type: 'job' | 'trigger' | 'edge') => {
    items.forEach((item) => {
      const model = {
        id: item.id
      }
      if (/(job|trigger)/.test(type)) {
        model.type = type;
      } else {
        model.source = item.source_trigger || item.source_job;
        model.target = item.target_job;
      }

      model.data = {
        ...item,
        label: item.label || item.id,
        // TMP
        trigger:  {
          type: 'webhook'
        },
      }
      collection.push(model)
    });
  };

  process(workflow.jobs, nodes, 'job')
  process(workflow.triggers, nodes, 'trigger')
  process(workflow.edges, edges, 'edge')
  return layout({ nodes, edges })
};

// Convert a react flow model back into a workflow
// We do this to report changes out of the component
const toWorkflow = () => {

}

// Not sure on the relationship to the store
// I kinda just want the component to do visalusation and fir eevents
// Does it even know about zustand? Any benefit?

// So in controlled mode things get difficult
// the component has to track internal chart state, like selection,
// as well as incoming changes from the server (like node state change)
export default ({ workflow, onSelectionChange }: WorkflowDiagramProps) => {
  const [model, setModel] = useState({ nodes: [], edges: [] });

  // TODO can selection just be a flat object? Easier to maintain state this way
  const [selected, setSelected] = useState({ nodes: {}, edges: {} });
  const [flow, setFlow] = useState()

  const setFlowInstance = useCallback((s) => {
    setFlow(s)
  }, [setFlow])

  // respond to changes pushed into the component
  // For now this just means the job has changed
  // but later it might mean syncing back with the server
  useEffect(() => {
    console.log('UPDATING WORKFLOW')
    const newModel = fromWorkflow(workflow);
    setModel(newModel)
  }, [workflow])
  
  // TODO this will fight animation
  // useEffect(() => {
  //   console.log('FIT')
  //   if (flow) {
  //     // TODO there's a timing issue here
  //     setTimeout(() => {
  //       flow.fitView({ duration: 250 });
  //     }, 50)
  //   }
  // }, [model])
  
  const onNodesChange = useCallback(
    (changes) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });
    }, [setModel, model]);

  const handleNodeClick = useCallback((event: React.MouseEvent, node: Node<NodeData>) => {
    event.stopPropagation();
    if (event.target.closest('[name=add-node]')) {
      const startModel = addPlaceholder(model, node)
      const endModel = layout(startModel)
      //setModel(newModelWithPositions)

      // animate to the new bound at the same time as we
      animate(startModel, endModel, setModel, flow, 500)
      // flow.fitView({ duration: 500, padding: 0.4 });
      
      // TODO publish the change outside the component, converting back to the original format

    }
  }, [model])

  const handleSelectionChange = useCallback(({ nodes, edges }) => {
    const everything = nodes.concat(edges);
    const selection = everything.map(({ id }) => id);
    onSelectionChange(selection);
  }, [onSelectionChange]);
  
  return <ReactFlowProvider>
      <ReactFlow
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={model.nodes}
        edges={model.edges}
        onSelectionChange={handleSelectionChange}
        onNodesChange={onNodesChange}
        // onEdgesChange={onEdgesChange}
        // // onSelectionChange={onSelectedNodeChange}
        // // onConnect={onConnect}
        // // If we let folks drag, we have to save new visual configuration...
        nodesDraggable={false}
        // // No interaction for this yet...
        // nodesConnectable={false}
        nodeTypes={nodeTypes}
        // snapToGrid={true}
        // snapGrid={[10, 10]}
        onNodeClick={handleNodeClick}
        // onPaneClick={onPaneClick}
        onInit={setFlowInstance}
        fitView
      />
    </ReactFlowProvider>
}