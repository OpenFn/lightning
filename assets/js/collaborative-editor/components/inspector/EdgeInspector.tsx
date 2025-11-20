import { useCallback, useState } from 'react';

import {
  useWorkflowActions,
  useWorkflowReadOnly,
} from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { Button } from '../Button';
import { Toggle } from '../Toggle';
import { Tooltip } from '../Tooltip';

import { EdgeForm } from './EdgeForm';
import { InspectorFooter } from './InspectorFooter';
import { InspectorLayout } from './InspectorLayout';

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
  const { isReadOnly, tooltipMessage } = useWorkflowReadOnly();
  const [isDeleting, setIsDeleting] = useState(false);

  const handleDelete = useCallback(() => {
    if (
      window.confirm(
        'Are you sure you want to delete this edge? This action cannot be undone.'
      )
    ) {
      setIsDeleting(true);
      try {
        removeEdge(edge.id);
        clearSelection();
      } catch (error) {
        console.error('Delete failed:', error);
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

  // Determine tooltip messages for disabled states
  const toggleTooltip = isReadOnly
    ? tooltipMessage
    : 'Enable or disable this path';
  const deleteTooltip = isReadOnly ? tooltipMessage : 'Delete this path';

  // Only show footer for job edges (not trigger edges)
  const footer = !edge.source_trigger_id ? (
    <InspectorFooter
      leftButtons={
        <Tooltip content={toggleTooltip} side="top">
          <span className="inline-block">
            <Toggle
              id={`edge-enabled-${edge.id}`}
              checked={edge.enabled ?? true}
              onChange={handleEnabledChange}
              label="Enabled"
              disabled={isReadOnly}
            />
          </span>
        </Tooltip>
      }
      rightButtons={
        <Tooltip content={deleteTooltip} side="top">
          <span className="inline-block">
            <Button
              variant="danger"
              onClick={handleDelete}
              disabled={isDeleting || isReadOnly}
            >
              {isDeleting ? 'Deleting...' : 'Delete'}
            </Button>
          </span>
        </Tooltip>
      }
    />
  ) : undefined;

  return (
    <InspectorLayout title="Path" onClose={onClose} footer={footer}>
      <EdgeForm edge={edge} />
    </InspectorLayout>
  );
}
