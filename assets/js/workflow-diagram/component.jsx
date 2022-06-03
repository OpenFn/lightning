import WorkflowDiagram from "@openfn/workflow-diagram";
import React from "react";
import { createRoot } from "react-dom/client";

export function mount(el) {
  const componentRoot = createRoot(el);

  function update(projectSpace) {
    return componentRoot.render(
      <WorkflowDiagram className="h-8" projectSpace={projectSpace} />
    );
  }

  function unmount() {
    return componentRoot.unmount();
  }

  componentRoot.render(<h1>Loading</h1>);

  return { update, unmount };
}
