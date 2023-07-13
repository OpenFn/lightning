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

  let initialSelection;
  const hash = window.location.hash;
  if (hash && hash.match('id=')) {
    initialSelection = hash.split('id=')[1];
  }

  componentRoot.render(
    <WorkflowDiagram
      ref={el}
      initialSelection={initialSelection}
      store={workflowStore}
      onSelectionChange={onSelectionChange}
    />
  );

  return { unmount };
}
