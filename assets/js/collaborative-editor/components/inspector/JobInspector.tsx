import { useCallback, useState } from "react";

import { useURLState } from "#/react/lib/use-url-state";
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
  onOpenRunPanel: (context: { jobId?: string; triggerId?: string }) => void;
}

/**
 * JobInspector - Composition layer combining layout, form, and actions.
 * Responsibilities:
 * - Compose InspectorLayout + JobForm + delete button
 * - Handle delete validation and modal
 * - Manage delete permissions
 */
export function JobInspector({
  job,
  onClose,
  onOpenRunPanel,
}: JobInspectorProps) {
  const { removeJobAndClearSelection } = useWorkflowActions();
  const permissions = usePermissions();
  const validation = useJobDeleteValidation(job.id);
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  // URL state for Edit button
  const { searchParams, updateSearchParams } = useURLState();
  const isIDEOpen = searchParams.get("editor") === "open";

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

  // Permission checks for Run button
  // Note: can_run_workflow doesn't exist yet in permissions type
  // For Phase 2, we'll just use can_edit_workflow as a placeholder
  const canRun = permissions?.can_edit_workflow;

  // Build footer with run, edit, and delete buttons (only if permission)
  const footer = permissions?.can_edit_workflow ? (
    <InspectorFooter
      leftButtons={
        <>
          <Tooltip
            content={
              !canRun
                ? "You do not have permission to run workflows"
                : "Run from this job"
            }
            side="top"
          >
            <span className="inline-block">
              <Button
                variant="secondary"
                onClick={() => onOpenRunPanel({ jobId: job.id })}
                disabled={!canRun}
              >
                Run
              </Button>
            </span>
          </Tooltip>
          <Tooltip
            content={
              isIDEOpen ? "IDE is already open" : "Open full-screen code editor"
            }
            side="top"
          >
            <span className="inline-block">
              <Button
                variant="primary"
                onClick={() => updateSearchParams({ editor: "open" })}
                disabled={isIDEOpen}
              >
                <span
                  className="hero-code-bracket size-4 inline-block mr-1"
                  aria-hidden="true"
                />
                Edit
              </Button>
            </span>
          </Tooltip>
        </>
      }
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
    <>
      <InspectorLayout
        title="Inspector"
        nodeType="job"
        onClose={onClose}
        footer={footer}
        data-testid="job-inspector"
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
    </>
  );
}
