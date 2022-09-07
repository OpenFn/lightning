import React, { MouseEvent } from 'react';
import { createRoot } from 'react-dom/client';
import WorkflowDiagram, { Store } from '@openfn/workflow-diagram';

type UpdateParams = {
  onNodeClick(event: MouseEvent, node: any): void;
  onPaneClick(event: MouseEvent): void;
}

export function mount(el: Element | DocumentFragment) {
  const componentRoot = createRoot(el);

  function update({ onNodeClick, onPaneClick }: UpdateParams) {
    return componentRoot.render(
      <WorkflowDiagram
        className="h-8"
        onNodeClick={onNodeClick}
        onPaneClick={onPaneClick}
      />
    );
  }

  function unmount() {
    return componentRoot.unmount();
  }

  componentRoot.render(<h1>Loading</h1>);

  return { update, unmount, setProjectSpace: Store.setProjectSpace };
}
