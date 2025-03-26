import { createRoot } from 'react-dom/client';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';

export function mount(
  el: HTMLElement,
  onSelectionChange: (id: string | null) => void
) {
  const componentRoot = createRoot(el);

  const initialSelection = new URL(window.location.href).searchParams.get('s');
  render(initialSelection);

  function render(selection?: string | null) {
    componentRoot.render(
      <WorkflowDiagram
        el={el}
        selection={selection || null}
        onSelectionChange={onSelectionChange}
      />
    );
  }

  function unmount() {
    componentRoot.unmount();
  }

  return { unmount, render };
}
