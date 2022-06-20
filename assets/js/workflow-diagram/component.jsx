import React from "react";
import { createRoot } from "react-dom/client";
import WorkflowDiagram from "@openfn/workflow-diagram";

export function mount(el) {
  const componentRoot = createRoot(el);

  function update({ projectSpace, onNodeClick, onPaneClick }) {
    return componentRoot.render(
      <WorkflowDiagram
        className="h-8"
        projectSpace={projectSpace}
        onNodeClick={onNodeClick}
        onPaneClick={onPaneClick}
      />
    );
  }

  function unmount() {
    return componentRoot.unmount();
  }

  componentRoot.render(<h1>Loading</h1>);

  return { update, unmount };
}
