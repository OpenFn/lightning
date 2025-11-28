/**
 * RunBadge - Displays selected run with dismiss action
 *
 * Reusable component showing a compact badge with run ID (truncated UUID)
 * and a close button to deselect the run.
 *
 * Used in:
 * - Canvas MiniHistory (collapsed state)
 * - IDE FullScreenIDE (run selection indicator)
 */

import Badge from '#/manual-run-panel/Badge';

interface RunBadgeProps {
  runId: string;
  onClose: () => void;
  className?: string;
  variant?: 'default' | 'warning';
}

export function RunBadge({
  runId,
  onClose,
  className,
  variant = 'default',
}: RunBadgeProps) {
  return (
    <Badge
      onClose={onClose}
      variant={variant}
      {...(className && { className })}
    >
      Run {runId.slice(0, 7)}
    </Badge>
  );
}
