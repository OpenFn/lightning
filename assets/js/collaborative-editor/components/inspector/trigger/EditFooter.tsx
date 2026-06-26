import { Tooltip } from '../../../../components/Tooltip';
import { Button } from '../../Button';
import { InspectorFooter } from '../InspectorFooter';

interface EditFooterProps {
  /** Whether the Edit action is available to the user. */
  canEdit: boolean;
  /** Tooltip shown when editing is disabled (read-only / viewer). */
  tooltipMessage: string;
  /** Enter the edit wizard. */
  onEdit: () => void;
}

/**
 * The shared "resting panel" footer: a single secondary **Edit** action on the
 * left, gated by `canEdit` with a tooltip explaining why it is disabled. Used by
 * every trigger show panel so the gating markup lives in one place.
 */
export function EditFooter({
  canEdit,
  tooltipMessage,
  onEdit,
}: EditFooterProps) {
  return (
    <InspectorFooter
      leftButtons={
        <Tooltip content={canEdit ? 'Edit trigger' : tooltipMessage}>
          <span className="inline-block">
            <Button
              variant="secondary"
              onClick={() => onEdit()}
              disabled={!canEdit}
              aria-label="Edit trigger"
            >
              Edit
            </Button>
          </span>
        </Tooltip>
      }
    />
  );
}
