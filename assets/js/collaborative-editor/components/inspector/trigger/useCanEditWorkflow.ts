import { usePermissions } from '../../../hooks/useSessionContext';
import { useWorkflowReadOnly } from '../../../hooks/useWorkflow';

/**
 * Resolves whether the current user may edit the workflow, plus the tooltip to
 * show when they may not. Shared by the trigger show panels so the
 * `permissions + !isReadOnly` gating and its message live in one place.
 */
export function useCanEditWorkflow(): {
  canEdit: boolean;
  tooltipMessage: string;
} {
  const permissions = usePermissions();
  const { isReadOnly, tooltipMessage } = useWorkflowReadOnly();
  const canEdit = Boolean(permissions?.can_edit_workflow) && !isReadOnly;
  return { canEdit, tooltipMessage };
}
