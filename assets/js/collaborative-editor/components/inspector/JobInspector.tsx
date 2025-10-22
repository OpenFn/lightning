import { useCallback, useState } from "react";

import { useJobDeleteValidation } from "../../hooks/useJobDeleteValidation";
import { usePermissions } from "../../hooks/useSessionContext";
import { useWorkflowActions } from "../../hooks/useWorkflow";
import { notifications } from "../../lib/notifications";
import type { Workflow } from "../../types/workflow";
import { AlertDialog } from "../AlertDialog";
import { Button } from "../Button";
import { Tooltip } from "../Tooltip";

import { InspectorFooter } from "./InspectorFooter";
import { InspectorLayout } from "./InspectorLayout";
import { JobForm } from "./JobForm";

interface JobInspectorProps {
  job: Workflow.Job;
  onClose: () => void;
}

/**
 * JobInspector - Composition layer combining layout, form, and actions.
 * Responsibilities:
 * - Compose InspectorLayout + JobForm + delete button
 * - Handle delete validation and modal
 * - Manage delete permissions
 */
export function JobInspector({ job, onClose }: JobInspectorProps) {
  const { removeJobAndClearSelection } = useWorkflowActions();
  const permissions = usePermissions();
  const validation = useJobDeleteValidation(job.id);
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  const handleDelete = useCallback(async () => {
    setIsDeleting(true);
    try {
      removeJobAndClearSelection(job.id);
      setIsDeleteDialogOpen(false);
      // Y.Doc sync provides immediate visual feedback
    } catch (error) {
      console.error("Delete failed:", error);
      notifications.alert({
        title: "Failed to delete job",
        description:
          error instanceof Error
            ? error.message
            : "An unexpected error occurred. Please try again.",
      });
    } finally {
      setIsDeleting(false);
    }
  }, [job.id, removeJobAndClearSelection]);

  // Build footer with delete button (only if user has permission)
  const footer = permissions?.can_edit_workflow ? (
    <InspectorFooter
      rightButtons={
        <Tooltip content={validation.disableReason || "Delete this job"}>
          <span className="inline-block">
            <Button
              variant="danger"
              onClick={() => setIsDeleteDialogOpen(true)}
              disabled={!validation.canDelete || isDeleting}
            >
              {isDeleting ? "Deleting..." : "Delete"}
            </Button>
          </span>
        </Tooltip>
      }
    />
  ) : undefined;

  return (
    <div data-testid="job-inspector">
      <InspectorLayout
        title="Inspector"
        nodeType="job"
        onClose={onClose}
        footer={footer}
      >
        <JobForm job={job} />
      </InspectorLayout>

      <AlertDialog
        isOpen={isDeleteDialogOpen}
        onClose={() => !isDeleting && setIsDeleteDialogOpen(false)}
        onConfirm={handleDelete}
        title="Delete Job?"
        description={
          `This will permanently remove "${job.name}" from the ` +
          `workflow. This action cannot be undone.`
        }
        confirmLabel={isDeleting ? "Deleting..." : "Delete Job"}
        cancelLabel="Cancel"
        variant="danger"
      />
    </div>
  );
}
