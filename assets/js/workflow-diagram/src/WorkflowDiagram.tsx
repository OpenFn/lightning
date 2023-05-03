import React, { useMemo, useCallback, useState, useEffect } from 'react';
import ReactFlow, { Node, ReactFlowProvider, applyEdgeChanges, applyNodeChanges } from 'react-flow-renderer';
import layout from './layout'
import nodeTypes from './nodes';
import { Workflow } from './types';

type WorkflowDiagramProps = {
  workflow: Workflow;
  onNodeSelected: (id: string) => void;
}

// TODO pass in the currently selected items so that we can maintain selection
const convertWorkflow  = (workflow: Workflow, selection: Record<string, true>) => {
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
    console.log('UPDATING MODEL')
    const data = convertWorkflow(workflow);
    setModel(data)
  }, [workflow])
  
  useEffect(() => {
    console.log('FIT')
    if (flow) {
      // TODO there's a timing issue here
      setTimeout(() => {
        flow.fitView({ duration: 250 });
      }, 50)
    }
  }, [model])
  
  const onNodesChange = useCallback(
    (changes) => {
      // const newNodes = applyNodeChanges(changes, model.nodes);
      // setModel({ nodes: newNodes, links: model.links });
    }, [setModel, model]);

  // const onEdgesChange = useCallback(
  //   (changes) => setModel((eds) => {
  //     const newLinks = applyEdgeChanges(changes, eds)
  //     setModel({ links: newLinks, nodes: model.nodes })
  //   },
  //   [setModel]
  // );

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
        // onNodeClick={handleNodeClick}
        // onPaneClick={onPaneClick}
        onInit={setFlowInstance}
        fitView
      />
    </ReactFlowProvider>
}