import React, { useState, useEffect, useCallback, useMemo } from 'react';

import WorkflowDiagram from '../../js/workflow-diagram/WorkflowDiagram'
// import useStore from './store'
import { createWorkflowStore } from '../../js/workflow-editor/store'
import './main.css'


const chart1 = {
  id: 'chart1',
  jobs: [{
    id: 'a',
    adaptor: 'common',
    expression: 'fn(s => s)',
  }, {
    id: 'b',
    adaptor: 'salesforce',
    expression: 'fn(s => s)',
  },
  {
    id: 'c',
    adaptor: 'http',
    expression: 'fn(s => s)',
  }],
  triggers: [{
    id: 'z',
    type: 'cron',
    cronExpression: '0 0 0',
  }],
  edges: [
    { id: 'z-a', label: 'on success', source_trigger_id: 'z', target_job_id: 'a' },
    { id: 'a-b', label: 'on success', source_job_id: 'a', target_job_id: 'b' },
    { id: 'a-c', label: 'on success', source_job_id: 'a', target_job_id: 'c' },
  ],
};

const chart2 = {
  id: 'chart2',
  jobs: [{ id: 'a' }],
  triggers: [{ id: 'z' }],
  edges: [
    { id: 'z-a', source_trigger_id: 'z', target_job_id: 'a' },
  ],
};

const chart3 = {
  id: 'chart3',
  jobs: [{ id: 'a' }, { id: 'b', label: 'this is a very long node name oh yes' }, { id: 'c' }],
  triggers: [],
  edges: [
    // { id: 'z-a', source_trigger_id: 'z', target_job_id: 'a' },
    { id: 'a-b', source_job: 'a', target_job_id: 'b' },
    { id: 'b-c', source_job: 'b', target_job_id: 'c' },
  ],
};

const Form = ({ node }) => {
  if (!node) {
    return <div>No node selected</div>
  }
  return  (<>
            <p>{`id: ${node.id}`}</p>
            {node.adaptor && <p>{`adaptor: ${node.adaptor}`}</p>}
            {node.type && <p>{`type: ${node.type}`}</p>}
            <p>{`expression: ${node.cronExpression || node.expression}`}</p>
          </>);
}

export default () => {
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

    const s = createWorkflowStore(chart1, onChange)

    const unsubscribe = s.subscribe(({ jobs, edges, triggers }) => {
      console.log('sub: ', { jobs, edges, triggers })
      setWorkflow({ jobs, edges, triggers });
    });

    const { jobs, edges, triggers } = s.getState();
    setWorkflow({ jobs, edges, triggers });
    setStore(s);

    return () => unsubscribe();
  }, [])
  // console.log(store)
  // console.log(workflow)

  // const { setWorkflow, workflow } = useStore(
  //     ({ workflow, setWorkflow }) => ({ workflow, setWorkflow })
  // );

  // useEffect(() => {
  //   setWorkflow(chart1)
  // }, [])

  const handleSelectionChange = (ids: string[]) => {
    const [first] = ids;
    const node = workflow.triggers.find(t => t.id === first) || workflow.jobs.find(t => t.id === first)
    setSelectedNode(node)
  }

  const addJob = useCallback(() => {
    console.log(store)
    const { add, addJob } = store.getState();

    // TODO ideally these should be batched up to trigger fewer updates
    const newNodeId = crypto.randomUUID();
    // addJob()
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
        onSelectionChange={handleSelectionChange}
      />
    </div>
    <div className="flex-1 flex flex-col h-full w-1/3">
      <div className="border-2 border-slate-200 m-2 p-2">
        {/*
          Options to control data flow from outside the chart
          These must write to the store and push to the component
        */}
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white" onClick={() => setWorkflow(chart1)}>Load chart 1</button>
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white" onClick={() => setWorkflow(chart2)}>Load chart 2</button>
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white" onClick={() => addJob()}>Add Job</button>
      </div>
      <div className="flex-1 border-2 border-slate-200 m-2 p-2">
        <h2 className="text-center">Selected Node</h2>
        <Form node={selectedNode} />
      </div>
      <div className="flex-1 border-2 border-slate-200 m-2 p-2 overflow-y-auto">
        <h2 className="text-center">Changes Events</h2>
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