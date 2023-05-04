import React, { createContext, useContext } from 'react';
import { createRoot } from 'react-dom/client';
import { StoreApi, useStore } from 'zustand';
import { WorkflowState, createWorkflowStore } from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram'

export function mount(
  el: Element | DocumentFragment,
  workflowStore: ReturnType<typeof createWorkflowStore>
) {
  const componentRoot = createRoot(el);

  function unmount() {
    return componentRoot.unmount();
  }

  function render() {
    // Note that object diffing won't work welll ike this
    const { edges, jobs, triggers } = workflowStore.getState();
    const workflow = { edges, jobs, triggers };
    console.log(workflow)
    componentRoot.render(
      // TODO listen to change events from the diagram and upadte the store accordingly
      <WorkflowDiagram workflow={workflow} onSelectionChange={()=>{}}/>
    );
  }

  workflowStore.subscribe(() => {
    render()
  })

  render()


  return { unmount };
}
