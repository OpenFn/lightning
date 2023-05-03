import React, { useState, useEffect } from 'react';

import WorkflowDiagram from '../../js/workflow-diagram/src/WorkflowDiagram'
import useStore from './store'
import './main.css'


const chart1 = {
  id: 'chart1',
  jobs: [{ id: 'a' }, { id: 'b' }, { id: 'c' }],
  triggers: [{ id: 'z' }],
  edges: [
    { id: 'z-a', source_trigger: 'z', target_job: 'a' },
    { id: 'a-b', source_job: 'a', target_job: 'b' },
    { id: 'a-c', source_job: 'a', target_job: 'c' },
  ],
};

const chart2 = {
  id: 'chart2',
  jobs: [{ id: 'a' }],
  triggers: [{ id: 'z' }],
  edges: [
    { id: 'z-a', source_trigger: 'z', target_job: 'a' },
  ],
};

const chart3 = {
  id: 'chart3',
  jobs: [{ id: 'a' }, { id: 'b', label: 'this is a very long node name oh yes' }, { id: 'c' }],
  triggers: [],
  edges: [
    // { id: 'z-a', source_trigger: 'z', target_job: 'a' },
    { id: 'a-b', source_job: 'a', target_job: 'b' },
    { id: 'b-c', source_job: 'b', target_job: 'c' },
  ],
};

export default () => {
  const [history, setHistory ] = useState([])
  const [selectedNodes, setSelectedNodes ] = useState('')

  const { setWorkflow, workflow } = useStore(
      ({ workflow, setWorkflow }) => ({ workflow, setWorkflow })
  );

  // Initialise the store
  useEffect(() => {
    setWorkflow(chart1)
  }, [])

  const handleSelectionChange = (ids: string[]) => {
    setSelectedNodes(ids)
  }

  // Right now the diagram just supports the adding and removing of nodes,
  // so lets respect that
  const onNodeAdded = (from, data) => {
    // Add a node and a link to the store
  }

  const onNodeRemoved = (id) => {
    // remove a node and link from the store
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
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white" onClick={() => setWorkflow(chart3)}>Load chart 3</button>
        <button className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-sm rounded-md text-white">Add random node</button>
      </div>
      <div className="flex-1 border-2 border-slate-200 m-2 p-2">
        <h2>Selected Node</h2>
        {/* Just show the node id here, it's more honest really */}
        { selectedNodes && <p>{selectedNodes}</p>}
      </div>
      <div className="flex-1 border-2 border-slate-200 m-2 p-2">Changes</div>
    </div>
  </div>
  );
};