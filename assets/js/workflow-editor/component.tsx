import React, { createContext, useContext } from 'react';
import { createRoot } from 'react-dom/client';
import { StoreApi, useStore } from 'zustand';
import { WorkflowState, createWorkflowStore } from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram'

export function mount(
  el: Element | DocumentFragment,
  workflowStore: ReturnType<typeof createWorkflowStore>,
  onSelectionChange: (id?: string) => void
) {
  const componentRoot = createRoot(el);

  function unmount() {
    return componentRoot.unmount();
  }

  function render() {
    const { edges, jobs, triggers, editJobUrl } = workflowStore.getState();
    const workflow = { edges, jobs, triggers };


    const handleSelectionChange = (ids) => {
      const id = ids[0]
      onSelectionChange?.(id);
    }

    componentRoot.render(
      // TODO listen to change events from the diagram and upadte the store accordingly
      <WorkflowDiagram
        ref={el}
        workflow={workflow}
        onSelectionChange={handleSelectionChange}
        handleRequestChange={()=>{}}/>
    );
  }

  workflowStore.subscribe(() => {
    render()
  })

  render()


  return { unmount };
}
