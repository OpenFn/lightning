import React, { createContext, useContext } from 'react';
import { createRoot } from 'react-dom/client';
import { StoreApi, useStore } from 'zustand';
import { WorkflowState, createWorkflowStore } from './store';

const WorkflowContext = createContext<StoreApi<WorkflowState> | null>(null);

function WorkflowEditor() {
  const store = useContext(WorkflowContext);
  if (!store) throw new Error('Missing WorkflowContext.Provider in the tree');

  const { edges, jobs, triggers, addJob, addTrigger, addEdge, editJobUrl } =
    useStore(store);

  // Maybe pull editJobUrl and the data-phx-* attributes into a provider
  // and component?

  return (
    <div>
      <h1 className="text-lg font-bold">Workflow Diagram</h1>
      <h3 className="font-bold">Triggers</h3>
      {triggers.map(({ id, errors }) => (
        <li key={id} className="text-sm font-mono">
          {id} - {JSON.stringify(errors, null, 2)}
        </li>
      ))}
      <button
        className={
          'px-4 py-2 font-semibold text-sm bg-cyan-500 text-white rounded-full shadow-sm'
        }
        onClick={() => addTrigger()}
      >
        Add Trigger
      </button>

      <h3 className="font-bold">Jobs</h3>
      {jobs.map(({ id, ...rest }) => (
        <li key={id} className="text-sm font-mono">
          <a
            data-phx-link="patch"
            data-phx-link-state="push"
            href={editJobUrl.replace(':job_id', id)}
          >
            {id}
          </a>
          - {JSON.stringify(rest, null, 2)}
        </li>
      ))}
      <button
        className={
          'px-4 py-2 font-semibold text-sm bg-cyan-500 text-white rounded-full shadow-sm'
        }
        onClick={() => addJob()}
      >
        Add Job
      </button>

      <h3 className="font-bold">Edges</h3>
      {edges.map(({ id, errors }) => (
        <li key={id} className="text-sm font-mono">
          {id} - {JSON.stringify(errors)}
        </li>
      ))}
      <button
        className={
          'px-4 py-2 font-semibold text-sm bg-cyan-500 text-white rounded-full shadow-sm'
        }
        onClick={() => addEdge()}
      >
        Add Edge
      </button>
    </div>
  );
}

export function mount(
  el: Element | DocumentFragment,
  workflowStore: ReturnType<typeof createWorkflowStore>
) {
  const componentRoot = createRoot(el);

  // TODO: we may not need this if we are doing all communication through the store
  function update() {
    return componentRoot.render(
      <WorkflowContext.Provider value={workflowStore}>
        <WorkflowEditor />
      </WorkflowContext.Provider>
    );
  }

  function unmount() {
    return componentRoot.unmount();
  }

  componentRoot.render(
    <WorkflowContext.Provider value={workflowStore}>
      <WorkflowEditor />
    </WorkflowContext.Provider>
  );

  return { update, unmount };
}
