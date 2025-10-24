/**
 * Inspector - Side panel component for displaying node details
 * Shows details for jobs, triggers, and edges when selected
 */

import { useHotkeys } from "react-hotkeys-hook";
import _logger from "#/utils/logger";
import { useURLState } from "../../../react/lib/use-url-state";
import type { Workflow } from "../../types/workflow";
import { EdgeInspector } from "./EdgeInspector";
import { InspectorLayout } from "./InspectorLayout";
import { JobInspector } from "./JobInspector";
import { TriggerInspector } from "./TriggerInspector";
import { WorkflowSettings } from "./WorkflowSettings";

export { InspectorLayout } from "./InspectorLayout";

const logger = _logger.ns("Inspector").seal();

interface InspectorProps {
  workflow: Workflow;
  currentNode: {
    node: Workflow.Node | null;
    type: Workflow.NodeType | null;
    id: string | null;
  };
  onClose: () => void;
  onOpenRunPanel: (context: { jobId?: string; triggerId?: string }) => void;
}

export function Inspector({
  workflow,
  currentNode,
  onClose,
  onOpenRunPanel,
}: InspectorProps) {
  const { hash, updateHash } = useURLState();

  const hasSelectedNode = currentNode.node && currentNode.type;

  // Settings hash takes precedence, then node inspector
  const mode =
    hash === "settings" ? "settings" : hasSelectedNode ? "node" : null;

  const handleClose = () => {
    if (mode === "settings") {
      updateHash(null);
    } else {
      onClose(); // Clears node selection
    }
  };

  useHotkeys(
    "escape",
    () => {
      logger.debug("Escape triggered");
      onClose();
    },
    {
      enabled: true,
      scopes: ["panel"],
      enableOnFormTags: true, // Allow Escape even in form fields
    },
    [onClose]
  );

  // Don't render if no mode selected
  if (!mode) return null;

  // Settings mode
  if (mode === "settings") {
    return (
      <InspectorLayout title="Workflow settings" onClose={handleClose}>
        <WorkflowSettings workflow={workflow} />
      </InspectorLayout>
    );
  }

  // Node inspector mode
  if (currentNode.type === "job") {
    return (
      <JobInspector
        key={`job-${currentNode.id}`}
        job={currentNode.node as Workflow.Job}
        onClose={handleClose}
        onOpenRunPanel={onOpenRunPanel}
      />
    );
  }

  if (currentNode.type === "trigger") {
    return (
      <TriggerInspector
        key={`trigger-${currentNode.id}`}
        trigger={currentNode.node as Workflow.Trigger}
        onClose={handleClose}
        onOpenRunPanel={onOpenRunPanel}
      />
    );
  }

  if (currentNode.type === "edge") {
    return (
      <EdgeInspector
        key={`edge-${currentNode.id}`}
        edge={currentNode.node as Workflow.Edge}
        onClose={handleClose}
      />
    );
  }

  return null;
}

// Helper function to open workflow settings from external components
export const openWorkflowSettings = () => {
  const newURL =
    window.location.pathname + window.location.search + "#settings";
  history.pushState({}, "", newURL);
};
