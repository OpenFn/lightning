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

import { cn } from '#/utils/cn';

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
    <div
      className={cn(
        'inline-flex justify-between items-center gap-x-1',
        'rounded-md px-2 py-1 text-xs font-medium',
        variant === 'default' && 'bg-blue-100 text-blue-700',
        variant === 'warning' && 'bg-yellow-100 text-yellow-800',
        className
      )}
    >
      <span>Run {runId.slice(0, 7)}</span>
      <button
        onClick={onClose}
        className={cn(
          'group relative -mr-1 -mt-1 h-3.5 w-3.5 rounded-sm',
          variant === 'default' && 'hover:bg-blue-600/20',
          variant === 'warning' && 'hover:bg-yellow-700/20'
        )}
        aria-label="Close run"
        title="Close run"
      >
        <span className="sr-only">Remove</span>
        <span className="hero-x-mark h-3.5 w-3.5" />
      </button>
    </div>
  );
}
