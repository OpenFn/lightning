import { useCallback, useState } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { useJobDeleteValidation } from '../../hooks/useJobDeleteValidation';
import { usePermissions } from '../../hooks/useSessionContext';
import {
  useWorkflowActions,
  useCanSave,
  useWorkflowReadOnly,
} from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { AlertDialog } from '../AlertDialog';
import { Button } from '../Button';
import { NewRunButton } from '../NewRunButton';
import { ShortcutKeys } from '../ShortcutKeys';
import { Tooltip } from '../Tooltip';

import { InspectorFooter } from './InspectorFooter';
import { InspectorLayout } from './InspectorLayout';
import { JobForm } from './JobForm';

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
  const { isReadOnly } = useWorkflowReadOnly();
  const validation = useJobDeleteValidation(job.id);
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  // URL state for Edit button
  const { params, updateSearchParams } = useURLState();
  const isIDEOpen = params.panel === 'editor';

  const handleDelete = useCallback(async () => {
    setIsDeleting(true);
    try {
      removeJobAndClearSelection(job.id);
      setIsDeleteDialogOpen(false);
      // Y.Doc sync provides immediate visual feedback
    } catch (error) {
      console.error('Delete failed:', error);
    } finally {
      setIsDeleting(false);
    }
  }, [job.id, removeJobAndClearSelection]);

  const { canSave, tooltipMessage: saveTooltipMessage } = useCanSave();

  // Determine delete button state
  const canDelete = canSave && validation.canDelete && !isDeleting;
  const deleteTooltipMessage = !canSave
    ? saveTooltipMessage
    : validation.disableReason || 'Delete this job';

  // Determine if Delete should be disabled
  const canEdit = permissions?.can_edit_workflow && !isReadOnly;

  // Build footer with edit, run, and delete buttons
  const footer = (
    <InspectorFooter
      leftButtons={
        <>
          <Tooltip
            content={
              <>
                {isIDEOpen
                  ? 'IDE is already open'
                  : isReadOnly
                    ? 'Cannot edit in read-only mode'
                    : 'Open full-screen code editor '}
                {!isIDEOpen && !isReadOnly && (
                  <>
                    {' '}
                    {'( '}
                    <ShortcutKeys keys={['mod', 'e']} />
                    {' )'}
                  </>
                )}
              </>
            }
            side="top"
          >
            <span className="inline-block">
              <Button
                variant="primary"
                onClick={() => updateSearchParams({ panel: 'editor' })}
                disabled={isIDEOpen || isReadOnly}
              >
                Code
              </Button>
            </span>
          </Tooltip>
          <NewRunButton
            onClick={() => onOpenRunPanel({ jobId: job.id })}
            tooltipSide="top"
            disabled={isReadOnly}
          />
        </>
      }
      rightButtons={
        <Tooltip content={deleteTooltipMessage}>
          <span className="inline-block">
            <Button
              variant="danger"
              onClick={() => setIsDeleteDialogOpen(true)}
              disabled={!canDelete || !canEdit}
            >
              {isDeleting ? 'Deleting...' : 'Delete'}
            </Button>
          </span>
        </Tooltip>
      }
    />
  );

  return (
    <>
      <InspectorLayout
        title={job.name}
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
        confirmLabel={isDeleting ? 'Deleting...' : 'Delete Job'}
        cancelLabel="Cancel"
        variant="danger"
      />
    </>
  );
}
