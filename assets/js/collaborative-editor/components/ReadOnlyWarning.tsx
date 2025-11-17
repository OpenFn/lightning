import { cn } from '../../utils/cn';
import { useIsNewWorkflow } from '../hooks/useSessionContext';
import { useWorkflowReadOnly } from '../hooks/useWorkflow';

import { Tooltip } from './Tooltip';

interface ReadOnlyWarningProps {
  id?: string;
  className?: string;
}

/**
 * ReadOnlyWarning component for collaborative workflow editor
 * Shows information icon with tooltip when workflow is read-only
 *
 * Automatically determines read-only state and displays appropriate
 * tooltip message
 *
 * Note: Uses Tailwind heroicons plugin for icon rendering instead of
 * @heroicons/react
 */
export const ReadOnlyWarning: React.FC<ReadOnlyWarningProps> = ({
  id = 'edit-disabled-warning',
  className = '',
}) => {
  const { isReadOnly, tooltipMessage } = useWorkflowReadOnly();
  const isNewWorkflow = useIsNewWorkflow();

  // Don't show warning during new workflow creation
  if (!isReadOnly || isNewWorkflow) return null;

  return (
    <Tooltip content={tooltipMessage} side="bottom">
      <span
        id={id}
        className={cn('cursor-pointer text-xs flex items-center', className)}
      >
        <span
          className="hero-information-circle-solid h-4 w-4
          text-primary-600 opacity-50"
        />
        <span className="ml-1">Read-only</span>
      </span>
    </Tooltip>
  );
};
