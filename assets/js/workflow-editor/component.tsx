import React from 'react';
import { createRoot } from 'react-dom/client';
import { createWorkflowStore } from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';

type Store = ReturnType<typeof createWorkflowStore>;

export function mount(
  el: HTMLElement,
  workflowStore: Store,
  onSelectionChange: (id: string | null) => void
) {
  const componentRoot = createRoot(el);

  const initialSelection = new URL(window.location.href).searchParams.get('s');
  render(initialSelection);

  function render(selection?: string | null) {
    componentRoot.render(
      <WorkflowDiagram
        ref={el}
        selection={selection || null}
        store={workflowStore}
        onSelectionChange={onSelectionChange}
      />
    );
  }

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount, render };
}
