import { useMemo } from "react";

import { usePermissions } from "./useSessionContext";
import { useWorkflowState } from "./useWorkflow";

interface DeleteValidation {
  canDelete: boolean;
  disableReason: string | null;
  hasChildEdges: boolean;
  isFirstJob: boolean;
}

/**
 * Validates whether a job can be deleted and provides
 *  messages for disabled states.
 *
 * @param jobId - The ID of the job to validate
 * @returns Validation state with tooltip message
 */
export const useJobDeleteValidation = (jobId: string): DeleteValidation => {
  const permissions = usePermissions();

  const edges = useWorkflowState(state => state.edges, []);

  const childEdges = useMemo(
    () => edges.filter(edge => edge.source_job_id === jobId),
    [edges, jobId]
  );

  const parentEdges = useMemo(
    () => edges.filter(edge => edge.target_job_id === jobId),
    [edges, jobId]
  );

  const hasChildEdges = childEdges.length > 0;

  // Check if job is first in workflow (has ONLY triggers as parents, no job parents)
  const hasTriggerParent = parentEdges.some(
    edge => edge.source_trigger_id !== undefined
  );
  const hasJobParent = parentEdges.some(
    edge => edge.source_job_id !== undefined
  );
  const isFirstJob = hasTriggerParent && !hasJobParent;

  return useMemo(() => {
    const canEdit = permissions?.can_edit_workflow ?? false;
    let canDelete = true;
    let disableReason: string | null = null;

    // Check in priority order
    if (!canEdit) {
      canDelete = false;
      disableReason = "You don't have permission to edit this workflow";
    } else if (hasChildEdges) {
      canDelete = false;
      disableReason = "Cannot delete: other jobs depend on this step";
    } else if (isFirstJob) {
      canDelete = false;
      disableReason = "Cannot delete: this is the first job in the workflow";
    }

    return {
      canDelete,
      disableReason,
      hasChildEdges,
      isFirstJob,
    };
  }, [permissions, hasChildEdges, isFirstJob]);
};
