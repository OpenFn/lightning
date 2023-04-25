import React, { useMemo, useCallback } from 'react';
import ReactFlow, { Node, ReactFlowProvider, applyEdgeChanges, applyNodeChanges } from 'react-flow-renderer';
import layout from './layout'
import nodeTypes from './types';

type WorkflowDiagramProps = {
  workflow: Workflow;
  onNodeSelected: (id: string) => void;
}

interface Node {
  id: string;
  name: string,
  workflowId: string;

}

interface Trigger extends Node {
  // TODO trigger type data
}

interface Job extends Node {
  
}

interface Edge {
  id: string;
  condition: string;
  source_job?: string;
  source_trigger?: string;
  target_job?: string;
}

type Workflow = {
  id: string;
  changeId?: string;
  triggers: Trigger[],
  jobs: Job[],
  edges: Edge[],
};


const convertWorkflow  = (workflow: Workflow) => {
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
        label: item.id,
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
  // const [nodes, setNodes] = useState([]);
  // const [edges, setEdges] = useState([]);
  // const [selected, setSelected] = useState({ nodes, edge });

  // useEffect(() => convertWorkflow(workflow), [workflow], [workflow])

  const { nodes, edges } = useMemo(() => convertWorkflow(workflow), [workflow])


  // const handleNodeChange = useCallback((evts) => {
  //   const selectionChangeEvents = evts.filter(({ type }) => type === 'select' )
  //   console.log(evts)
  //   if (selectionChangeEvents.length > 0) {
  //     // Publish a nice clean event of the currently selected things
  //     const selected = selectionChangeEvents.filter(({ selected }) => selected).map(({id}) => id)
  //     onSelectionChange(selected)
  //   }
  // }, [onSelectionChange]);
  const handleSelectionChange = ({ nodes, edges }) => {
    const everything = nodes.concat(edges);
    const selection = everything.map(({ id }) => id)
    onSelectionChange(selection)
  };

  return <ReactFlowProvider>
      <ReactFlow
        // proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={nodes}
        edges={edges}
        onSelectionChange={handleSelectionChange}
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
        // onInit={Store.setReactFlowInstance}
        fitView
      />
    </ReactFlowProvider>
}