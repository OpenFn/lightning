import React, { useState, useEffect, useCallback, useMemo } from 'react';

import WorkflowDiagram from '../../js/workflow-diagram/WorkflowDiagram'
// import useStore from './store'
import { createWorkflowStore } from '../../js/workflow-editor/store'
import workflows from './workflows';
import './main.css'

const Form = ({ node }) => {
  if (!node) {
    return <div>No node selected</div>
  }
  return  (<>
            <p>{`name: ${node.label || node.id}`}</p>
            {node.adaptor && <p>{`adaptor: ${node.adaptor}`}</p>}
            {node.type && <p>{`type: ${node.type}`}</p>}
            <p>{`expression: ${node.cronExpression || node.expression}`}</p>
          </>);
}

export default () => {
  const [workflowId, setWorkflowId] = useState('chart1');
  const [history, setHistory ] = useState([])
  const [store, setStore ] = useState({});
  const [selectedNode, setSelectedNode ] = useState(null)


  const [workflow, setWorkflow] = useState({ jobs: [], triggers: [], edges: [] })

  // on startup (or on workflow id change) create a store
  // on change, set the state back into the app.
  // Now if the store changes, we can deal with it
  useEffect(() => {
    const onChange = (evt) => {
      // what do we do on change, and how do we call this safely?
      console.log('CHANGE', evt.id, evt.patches)
      setHistory((h) => [evt, ...h])
    }

    const s = createWorkflowStore(workflows[workflowId], onChange)

    const unsubscribe = s.subscribe(({ jobs, edges, triggers }) => {
      console.log('store change: ', { jobs, edges, triggers })
      setWorkflow({ jobs, edges, triggers });
    });

    const { jobs, edges, triggers } = s.getState();
    // Set the chart to null to reset its positions
    setWorkflow({ jobs: [], edges: [], triggers: [] });
    
    // now set the chart properly
    // use a timeout to make sure its applied
    setTimeout( () =>  {
      setWorkflow({ jobs, edges, triggers });
      setStore(s);
    }, 1)

    return () => unsubscribe();
  }, [workflowId])

  const handleSelectionChange = (ids: string[]) => {
    const [first] = ids;
    const node = workflow.triggers.find(t => t.id === first) || workflow.jobs.find(t => t.id === first)
    setSelectedNode(node)
  }

  // Adding a job in the store will push the new workflow structure through to the inner component
  // Selection should be preserved (but probably isn't right now)
  // At the moment this doesn't animate, which is fine and expected
  const addJob = useCallback(() => {
    const { add } = store.getState();

    const newNodeId = crypto.randomUUID();
    add({
      jobs: [{
        id: newNodeId,
        type: 'job',
      }],
      edges: [{
        source_job_id: selectedNode?.id ?? 'a', target_job_id: newNodeId
      }]
    })
  }, [store, selectedNode]);

  const handleRequestChange = useCallback((diff) => {
    const { add } = store.getState();
    add(diff)
  }, [store]);

  // Right now the diagram just supports the adding and removing of nodes,
  // so lets respect that
  const onNodeAdded = (from, data) => {
    // Add a node and a link to the store
  }

  const onNodeRemoved = (id) => {
    // remove a node and link from the store
  }
  const onChanged = () => {
    // notify when the model has changed
  }

  return (<div className="flex flex-row h-full w-full">
    <div className="flex-1 border-2 border-slate-200 m-2 bg-secondary-100">
      <WorkflowDiagram 
        workflow={workflow}
        requestChange={handleRequestChange}
        onSelectionChange={handleSelectionChange}
      />
    </div>
    <div className="flex-1 flex flex-col h-full w-1/3">
      <div className="border-2 border-slate-200 m-2 p-2">
        {/*
          Options to control data flow from outside the chart
          These must write to the store and push to the component
        */}
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white" onClick={() => setWorkflowId('chart1')}>Workflow 1</button>
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white" onClick={() => setWorkflowId('chart2')}>Workflow 2</button>
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white" onClick={() => addJob()}>Add Job</button>
      </div>
      <div className="flex-1 border-2 border-slate-200 m-2 p-2">
        <h2 className="text-center">Selected Node</h2>
        <Form node={selectedNode} />
      </div>
      <div className="flex-1 border-2 border-slate-200 m-2 p-2 overflow-y-auto">
        <h2 className="text-center">Change Events</h2>
        <ul className="ml-4">{
          history.map((change) => {
          return (<li key={change.id} className="border border-slate-50 border-1 p-4 m-2">
            <h3>{change.id}</h3>
            <ul className="list-disc ml-4">
              {change.patches.map((p) => <li key={p.path}>{`${p.op} ${p.path}`}</li>)}
            </ul>
          </li>)
          })
        }</ul>
      </div>
    </div>
  </div>
  );
};