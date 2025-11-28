/**
 * RunChip - Displays selected run with dismiss action
 *
 * Reusable component showing a compact chip with run ID (truncated UUID)
 * and a close button to deselect the run.
 *
 * Used in:
 * - Canvas MiniHistory (collapsed state)
 * - IDE FullScreenIDE (run selection indicator)
 */

import Pill from '#/manual-run-panel/Pill';

interface RunChipProps {
  runId: string;
  onClose: () => void;
  className?: string;
  variant?: 'default' | 'warning';
}

export function RunChip({
  runId,
  onClose,
  className,
  variant = 'default',
}: RunChipProps) {
  return (
    <Pill onClose={onClose} variant={variant} className={className}>
      Run {runId.slice(0, 7)}
    </Pill>
  );
}
