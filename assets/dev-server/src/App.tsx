import { useState, useEffect, useCallback, useRef, useMemo } from 'react';

import WorkflowDiagram from '../../js/workflow-diagram/WorkflowDiagram';
// import useStore from './store'
import { createWorkflowStore } from '../../js/workflow-store/store';
import { randomUUID } from '../../js/common';
import workflows from './workflows';
import './main.css';
import '@xyflow/react/dist/style.css';

const Form = ({ nodeId, store, onChange }) => {
  if (!nodeId) {
    return <div>Nothing selected</div>;
  }
  const { jobs, edges, triggers } = store.getState();
  const item =
    jobs.find(({ id }) => id == nodeId) ||
    edges.find(({ id }) => id == nodeId) ||
    triggers.find(({ id }) => id == nodeId);
  return (
    <>
      <p>
        <span>Name</span>
        <input
          value={item.name || item.id}
          className="border-1 border-slate-200 ml-2 p-2"
          onChange={evt => onChange({ name: evt.target.value })}
        />
      </p>
      {item.adaptor && <p>{`adaptor: ${item.adaptor}`}</p>}
      {item.type && <p>{`type: ${item.type}`}</p>}
      {item.target_job_id ? (
        <p>{`condition_type: ${item.condition_type}`}</p>
      ) : (
        <p>{`expression: ${item.cronExpression || item.expression}`}</p>
      )}
    </>
  );
};

const allWorkflows = Object.keys(workflows);

export default () => {
  const [workflowId, setWorkflowId] = useState(allWorkflows[0]);
  const [history, setHistory] = useState([]);

  const onChange = evt => {
    // what do we do on change, and how do we call this safely?
    console.log('CHANGE', evt.id, evt.patches);
    setHistory(h => [evt, ...h]);
  };

  const [store, setStore] = useState(() => createWorkflowStore({}, () => {}));

  const [selectedId, setSelectedId] = useState<string>();
  const ref = useRef(null);

  const hasMoreWorkflows = useMemo(() => {
    const idx = allWorkflows.indexOf(workflowId);
    return idx < allWorkflows.length - 1;
  }, [workflowId]);

  const next = useCallback(() => {
    const idx = allWorkflows.indexOf(workflowId);
    setWorkflowId(allWorkflows[idx + 1]);
  }, [workflowId]);

  // on startup (or on workflow id change) create a store
  // on change, set the state back into the app.
  // Now if the store changes, we can deal with it
  useEffect(() => {
    const s = createWorkflowStore(workflows[workflowId], onChange);

    setStore(s);
  }, [workflowId]);

  const handleSelectionChange = useCallback((id: string) => {
    setSelectedId(id);
  }, []);

  const handleNameChange = useCallback(
    ({ name }) => {
      const { jobs, edges, change } = store.getState();
      const diff = { name, placeholder: false };

      const node = jobs.find(j => j.id === selectedId);
      if (node.placeholder) {
        diff.placeholder = false;

        const edge = edges.find(e => e.target_job_id === selectedId);
        change(edge.id, 'edges', { placeholder: false });
      }

      change(selectedId, 'jobs', diff);
    },
    [store, selectedId]
  );

  // Adding a job in the store will push the new workflow structure through to the inner component
  // Selection should be preserved (but probably isn't right now)
  // At the moment this doesn't animate, which is fine and expected
  const addJob = useCallback(() => {
    const { add } = store.getState();

    const newNodeId = randomUUID();
    add({
      jobs: [
        {
          id: newNodeId,
          type: 'job',
        },
      ],
      edges: [
        {
          source_job_id: selectedId?.id ?? 'a',
          target_job_id: newNodeId,
        },
      ],
    });
  }, [store, selectedId]);

  const rerunLayout = useCallback(() => {
    const id = workflowId;
    setWorkflowId('empty');
    setTimeout(() => {
      setWorkflowId(id);
    }, 100);
  }, [workflowId]);

  const handleRequestChange = useCallback(
    diff => {
      const { add } = store.getState();
      add(diff);
    },
    [store]
  );

  return (
    <div className="flex flex-row h-full w-full overflow-hidden">
      <div
        className="flex-1 border-2 border-slate-200 m-2 bg-secondary-100"
        style={{ flexBasis: '66%' }}
        ref={ref}
      >
        <WorkflowDiagram
          ref={ref.current}
          store={store}
          requestChange={handleRequestChange}
          onSelectionChange={handleSelectionChange}
          layoutDuration={0}
          forceFit
        />
      </div>
      <div
        className={'flex flex-1 flex-col h-full'}
        style={{ flexBasis: '33%' }}
      >
        <div className="border-2 border-slate-200 m-2 p-2">
          <select
            id="select-workflow"
            onChange={e => setWorkflowId(e.target.value)}
            value={workflowId}
          >
            {Object.keys(workflows).map(wf_id => (
              <option>{wf_id}</option>
            ))}
          </select>
          <button
            id="next-workflow"
            className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-xs rounded-md text-white"
            onClick={() => next()}
            disabled={!hasMoreWorkflows}
          >
            Next
          </button>
          <button
            id="reload-workflow"
            className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-xs rounded-md text-white"
            onClick={() => rerunLayout()}
            disabled={!hasMoreWorkflows}
          >
            Re-run
          </button>
          <button
            className="bg-primary-500 mx-2 py-2 px-4 border border-transparent shadow-xs rounded-md text-white"
            onClick={() => addJob()}
          >
            Add Job
          </button>
        </div>
        <div className="flex-1 border-2 border-slate-200 m-2 p-2">
          <h2 className="text-center">Selected</h2>
          <Form store={store} nodeId={selectedId} onChange={handleNameChange} />
        </div>
        <div className="flex-1 border-2 border-slate-200 m-2 p-2 overflow-y-auto">
          <h2 className="text-center">Change Events</h2>
          <ul className="ml-4">
            {history.map(change => {
              return (
                <li
                  key={change.id}
                  className="border border-slate-50 border-1 p-4 m-2"
                >
                  <h3>{change.id}</h3>
                  <ul className="list-disc ml-4">
                    {change.patches.map(p => (
                      <li key={p.path}>{`${p.op} ${p.path}`}</li>
                    ))}
                  </ul>
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </div>
  );
};
