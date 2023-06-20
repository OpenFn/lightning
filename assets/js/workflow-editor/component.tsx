import React, { createContext } from 'react';
import { createRoot } from 'react-dom/client';
import { StoreApi } from 'zustand';
import {
  WorkflowState,
  createWorkflowStore
} from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';

export const WorkflowContext = createContext<StoreApi<WorkflowState> | null>(
  null
);

type Store = ReturnType<typeof createWorkflowStore>;

export function mount(
  el: Element | DocumentFragment,
  workflowStore: Store,
  onSelectionChange: (id?: string) => void
) {
  const componentRoot = createRoot(el);

  function unmount() {
    console.log('unmount');

    return componentRoot.unmount();
  }

  console.log('render');
  componentRoot.render(
    <WorkflowContext.Provider value={workflowStore}>
      <WorkflowDiagram ref={el} onSelectionChange={onSelectionChange} />
    </WorkflowContext.Provider>
  );

  return { unmount };
}
