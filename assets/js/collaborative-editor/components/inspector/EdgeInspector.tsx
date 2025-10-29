import { useCallback, useState } from "react";

import { useWorkflowActions } from "../../hooks/useWorkflow";
import type { Workflow } from "../../types/workflow";
import { Button } from "../Button";
import { Toggle } from "../Toggle";

import { EdgeForm } from "./EdgeForm";
import { InspectorFooter } from "./InspectorFooter";
import { InspectorLayout } from "./InspectorLayout";

interface EdgeInspectorProps {
  edge: Workflow.Edge;
  onClose: () => void;
}

/**
 * EdgeInspector - Composition layer for edge configuration.
 * Combines layout, form, and delete action.
 */
export function EdgeInspector({ edge, onClose }: EdgeInspectorProps) {
  const { removeEdge, clearSelection, updateEdge } = useWorkflowActions();
  const [isDeleting, setIsDeleting] = useState(false);

  const handleDelete = useCallback(async () => {
    if (
      window.confirm(
        "Are you sure you want to delete this edge? This action cannot be undone."
      )
    ) {
      setIsDeleting(true);
      try {
        removeEdge(edge.id);
        clearSelection();
      } catch (error) {
        console.error("Delete failed:", error);
      } finally {
        setIsDeleting(false);
      }
    }
  }, [edge.id, removeEdge, clearSelection]);

  const handleEnabledChange = useCallback(
    (enabled: boolean) => {
      updateEdge(edge.id, { enabled });
    },
    [edge.id, updateEdge]
  );

  // Only show footer for job edges (not trigger edges)
  const footer = !edge.source_trigger_id ? (
    <InspectorFooter
      leftButtons={
        <Toggle
          id={`edge-enabled-${edge.id}`}
          checked={edge.enabled ?? true}
          onChange={handleEnabledChange}
          label="Enabled"
        />
      }
      rightButtons={
        <Button variant="danger" onClick={handleDelete} disabled={isDeleting}>
          {isDeleting ? "Deleting..." : "Delete"}
        </Button>
      }
    />
  ) : undefined;

  return (
    <InspectorLayout
      title="Path"
      nodeType="edge"
      onClose={onClose}
      footer={footer}
    >
      <EdgeForm edge={edge} />
    </InspectorLayout>
  );
}
