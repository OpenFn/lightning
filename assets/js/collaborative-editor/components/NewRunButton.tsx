import { useCanRun } from '../hooks/useWorkflow';

import { Button } from './Button';
import { ShortcutKeys } from './ShortcutKeys';
import { Tooltip } from './Tooltip';

interface NewRunButtonProps {
  onClick: () => void;
  disabled?: boolean;
  tooltipSide?: 'top' | 'bottom';
}

/**
 * NewRunButton - Standardized button for opening the manual run panel.
 *
 * Displays a play-circle outline icon with "Run" text.
 * Shows keyboard shortcut tooltip when enabled, error message when disabled.
 *
 * Used in:
 * - Header (canvas)
 * - TriggerInspector
 * - JobInspector
 * - FullScreenIDE (before panel open)
 */
export function NewRunButton({
  onClick,
  disabled: disabledProp,
  tooltipSide = 'bottom',
}: NewRunButtonProps) {
  const { canRun, tooltipMessage } = useCanRun();

  // Disable if parent requests OR if canRun is false
  const isDisabled = disabledProp || !canRun;

  const tooltip = canRun ? (
    <ShortcutKeys keys={['mod', 'enter']} />
  ) : (
    tooltipMessage
  );

  return (
    <Tooltip content={tooltip} side={tooltipSide}>
      <span className="inline-block">
        <Button variant="primary" onClick={onClick} disabled={isDisabled}>
          <span className="flex items-center gap-1">
            <span className="hero-play h-4 w-4" />
            Run
          </span>
        </Button>
      </span>
    </Tooltip>
  );
}
