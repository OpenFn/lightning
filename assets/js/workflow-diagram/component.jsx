import WorkflowDiagram from "@openfn/workflow-diagram";
import React from "react";
import { createRoot } from "react-dom/client";

let dummy = {
  jobs: [
    {
      id: "A",
      name: "Job A",
      adaptor: "@openfn/language-salesforce@2.8.1",
      trigger: { type: "webhook" },
      operations: [
        { id: "115", label: "create", comment: "Create an object" },
        { id: "25", label: "fn", comment: "Map out new records" },
        { id: "35", label: "upsert", comment: "Upsert results" },
      ],
    },
    {
      id: "B",
      name: "Job B",
      adaptor: "@openfn/language-salesforce@0.2.2",
      trigger: { type: "on_job_failure", upstreamJob: "E" },
    },
    {
      id: "C",
      name: "Job C",
      adaptor: "@openfn/language-dhis2@0.3.5",
      trigger: { type: "on_job_success", upstreamJob: "A" },
    },
    {
      id: "E",
      name: "Job E",
      adaptor: "@openfn/language-dhis2@0.3.5",
      trigger: { type: "on_job_failure", upstreamJob: "A" },
    },
  ],
};

export function mount(el) {
  const componentRoot = createRoot(el);

  console.log({ offsetHeight: el.offsetHeight, offsetWidth: el.offsetWidth });
  function update(args) {
    return componentRoot.render(<WorkflowDiagram className="h-8" projectSpace={dummy} />);
    // return componentRoot.render(<h1>{JSON.stringify(args)}</h1>);
  }

  function unmount() {
    return componentRoot.unmount();
  }

  componentRoot.render(<h1>I'm react!</h1>);

  return { update, unmount };
}
