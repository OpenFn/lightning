import React, { createContext, useContext } from 'react';
import { createRoot } from 'react-dom/client';
import { StoreApi, useStore } from 'zustand';
import { WorkflowState, createWorkflowStore, WorkflowProps } from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram'

export const WorkflowContext = createContext<StoreApi<WorkflowState> | null>(null);

type Store = ReturnType<typeof createWorkflowStore>;
type Workflow = Pick<WorkflowProps, 'jobs' | 'edges' | 'triggers'>;

// This will take a store passed from the server and do some light transformation
// Specifically it identifies placeholder nodes
const identifyPlaceholders = (store: Store) => {
  const { jobs, triggers, edges } = store;
  
  const newJobs = jobs.map((item) => {
    // TODO placeholder triggers don't have a cron/webhook type yet
    if (!item.name && !item.expression) {
      return {
        ...item,
        placeholder: true
      }
    }
    return item;
  });
  
  const newEdges = edges.map((edge) => {
    const target = newJobs.find(({ id }) => edge.target_job_id === id);
    if (target?.placeholder) {
      return {
        ...edge,
        placeholder: true
      }
    }
    return edge;
  });

  const result = {
    triggers,
    jobs: newJobs,
    edges: newEdges,
  }

  return result;
}

export function mount(
  el: Element | DocumentFragment,
  workflowStore: Store,
  onSelectionChange: (id?: string) => void
) {
  const componentRoot = createRoot(el);

  function unmount() {
    unsubscribe();
    return componentRoot.unmount();
  }

  function render(model: Workflow) {
    const { add, change } = workflowStore.getState();

    const handleSelectionChange = (id: string) => {
      onSelectionChange?.(id);
    }

    const handleRequestChange = (type: 'add' | 'update', diff) => {
      if (type === 'add') {
        add(diff)
      } else {
        // TODO this needs cleaning up
        change(...diff)
      }
    }

    componentRoot.render(
      <WorkflowContext.Provider value={workflowStore}>
        <WorkflowDiagram
          ref={el}
          workflow={identifyPlaceholders(model)}
          onSelectionChange={handleSelectionChange}
          requestChange={handleRequestChange}/>
      </WorkflowContext.Provider>
    );
  }

  const unsubscribe = workflowStore.subscribe(render)

  return { unmount, render };
}
