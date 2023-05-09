import React, { createContext, useContext } from 'react';
import { createRoot } from 'react-dom/client';
import { StoreApi, useStore } from 'zustand';
import { WorkflowState, createWorkflowStore, WorkflowProps } from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram'

type Store = ReturnType<typeof createWorkflowStore>;
type Workflow = Pick<WorkflowProps, 'jobs' | 'edges' | 'triggers'>;

export function mount(
  el: Element | DocumentFragment,
  workflowStore: Store,
  onSelectionChange: (id?: string) => void
) {
  const componentRoot = createRoot(el);

  function unmount() {
    return componentRoot.unmount();
  }

  function render(model: Workflow) {
    const { add } = workflowStore.getState();

    const handleSelectionChange = (id: string) => {
      onSelectionChange?.(id);
    }

    const handleRequestChange = (diff) => {
      add(diff)
    }

    componentRoot.render(
      // TODO listen to change events from the diagram and upadte the store accordingly
      <WorkflowDiagram
        ref={el}
        workflow={model}
        onSelectionChange={handleSelectionChange}
        requestChange={handleRequestChange}/>
    );
  }

  workflowStore.subscribe(() => {
    // TODO: only re-render if its a change we care about?
    // ie ignore changes to the expression
    // The component itself could do a deep diff
    // OTOH rendering is going to be extremely cheap
    render(workflowStore.getState())
  })

  return { unmount, render };
}
