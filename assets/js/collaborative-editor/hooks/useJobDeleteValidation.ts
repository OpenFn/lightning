import { useMemo } from 'react';

import {
  getOutgoingJobEdges,
  isFirstJobInWorkflow,
  removeGhostEdges,
} from '../utils/workflowGraph';

import { usePermissions } from './useSessionContext';
import { useWorkflowState } from './useWorkflow';

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
    return removeGhostEdges(getOutgoingJobEdges(edges, jobId), jobs);
  }, [edges, jobs, jobId]);

  const hasChildEdges = childEdges.length > 0;
  const isFirstJob = isFirstJobInWorkflow(edges, jobId);

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
      disableReason = 'Cannot delete: other jobs depend on this step';
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
