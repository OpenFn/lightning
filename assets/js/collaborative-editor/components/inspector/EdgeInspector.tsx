import { useCallback, useState } from 'react';

import {
  useWorkflowActions,
  useWorkflowReadOnly,
} from '../../hooks/useWorkflow';
import type { Workflow } from '../../types/workflow';
import { Button } from '../Button';
import { Toggle } from '../Toggle';
import { Tooltip } from '../../../components/Tooltip';

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
  const { isReadOnly } = useWorkflowReadOnly();
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

  // The footer holds edit-only actions (enable/disable and delete path). On a
  // read-only workflow both are hidden, matching the canvas and other
  // inspectors, so the footer collapses entirely. Trigger edges never show a
  // footer. The edge's config fields (label, condition, JS expression) stay
  // visible-but-disabled in EdgeForm so a live workflow can still be read.
  const footer =
    !edge.source_trigger_id && !isReadOnly ? (
      <InspectorFooter
        leftButtons={
          <Tooltip content="Enable or disable this path" side="top">
            <span className="inline-block">
              <Toggle
                id={`edge-enabled-${edge.id}`}
                checked={edge.enabled ?? true}
                onChange={handleEnabledChange}
                label="Enabled"
              />
            </span>
          </Tooltip>
        }
        rightButtons={
          <Tooltip content="Delete this path" side="top">
            <span className="inline-block">
              <Button
                variant="danger"
                onClick={handleDelete}
                disabled={isDeleting}
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
