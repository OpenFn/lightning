import React from "react";
import { createRoot } from "react-dom/client";
import WorkflowDiagram from "@openfn/workflow-diagram";
import md5 from "blueimp-md5";

export function mount(el) {
  const componentRoot = createRoot(el);

  function update({ projectSpace, onNodeClick, onPaneClick }) {
    // Naively force a re-render when the project space is different by
    // calculating the MD5 of projectSpace and invalidate the mounted component
    // via `key`.
    const checkSum = md5(JSON.stringify(projectSpace));
    return componentRoot.render(
      <WorkflowDiagram
        className="h-8"
        key={checkSum}
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
