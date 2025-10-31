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
  const jobs = useWorkflowState(state => state.jobs, []);

  const childEdges = useMemo(() => {
    // Get all edges where this job is the source
    const edgesFromThisJob = edges.filter(edge => edge.source_job_id === jobId);

    // Filter out ghost edges - edges pointing to non-existent jobs
    const validEdges = edgesFromThisJob.filter(edge => {
      // If target is a job, verify it exists
      if (edge.target_job_id) {
        return jobs.some(job => job.id === edge.target_job_id);
      }
      // If target is a trigger, it's valid (we don't check trigger existence here)
      return true;
    });

    return validEdges;
  }, [edges, jobs, jobId]);

  const parentEdges = useMemo(
    () => edges.filter(edge => edge.target_job_id === jobId),
    [edges, jobId]
  );

  const hasChildEdges = childEdges.length > 0;

  // Check if job is first in workflow (has ONLY triggers as parents, no job parents)
  const hasTriggerParent = parentEdges.some(
    edge =>
      edge.source_trigger_id !== undefined && edge.source_trigger_id !== null
  );
  const hasJobParent = parentEdges.some(
    edge => edge.source_job_id !== undefined && edge.source_job_id !== null
  );
  const isFirstJob = hasTriggerParent && !hasJobParent;

  return useMemo(() => {
    const canEdit = permissions?.can_edit_workflow ?? false;
    let canDelete = true;
    let disableReason: string | null = null;

    // Check in priority order (must match WorkflowEdit rules)
    if (!canEdit) {
      canDelete = false;
      disableReason = "You don't have permission to edit this workflow";
    } else if (hasChildEdges) {
      canDelete = false;
      disableReason = "Cannot delete: other jobs depend on this step";
    } else if (isFirstJob) {
      canDelete = false;
      disableReason = "You can't delete the first step in a workflow.";
    }

    return {
      canDelete,
      disableReason,
      hasChildEdges,
      isFirstJob,
    };
  }, [permissions, hasChildEdges, isFirstJob]);
};
