import React from 'react';
import { createRoot } from 'react-dom/client';
import { createWorkflowStore } from './store';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';

type Store = ReturnType<typeof createWorkflowStore>;

export function mount(
  el: HTMLElement,
  workflowStore: Store,
  onSelectionChange: (id?: string) => void
) {
  const componentRoot = createRoot(el);

  function unmount() {
    return componentRoot.unmount();
  }

  let initialSelection;
  const currentUrl = new URL(window.location.href);
  initialSelection = currentUrl.searchParams.get('s');

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
