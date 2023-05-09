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
    const { edges, jobs, triggers, add } = workflowStore.getState();
    const workflow = { edges, jobs, triggers };


    const handleSelectionChange = (id) => {
      onSelectionChange?.(id);
    }

    const handleRequestChange = (diff) => {
      add(diff)
    }

    componentRoot.render(
      // TODO listen to change events from the diagram and upadte the store accordingly
      <WorkflowDiagram
        ref={el}
        workflow={workflow}
        onSelectionChange={handleSelectionChange}
        requestChange={handleRequestChange}/>
    );
  }

  workflowStore.subscribe(() => {
    console.log('> subscribe')
    render()
  })

  render()


  return { unmount };
}
