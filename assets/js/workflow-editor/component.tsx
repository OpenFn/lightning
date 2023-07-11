import React from 'react';
import { createRoot } from 'react-dom/client';
import { createWorkflowStore } from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';

type Store = ReturnType<typeof createWorkflowStore>;

export function mount(
  el: Element | DocumentFragment,
  workflowStore: Store,
  onSelectionChange: (id?: string) => void
) {
  const componentRoot = createRoot(el);

  function unmount() {
    return componentRoot.unmount();
  }

  componentRoot.render(
    <WorkflowDiagram
      ref={el}
      store={workflowStore}
      onSelectionChange={onSelectionChange}
    />
  );

  return { unmount };
}
