/**
 * VersionMismatchBanner - Informational banner when canvas version differs from selected run version
 *
 * Displays when:
 * - A run is selected
 * - The canvas is showing a different workflow version than the run was executed on
 *
 * Alerts users that the canvas layout may differ from the actual run execution,
 * as the workflow structure may have changed between versions.
 *
 * Features:
 * - Compact design with version information
 * - Action button to navigate to the correct version
 * - Positioned at bottom of MiniHistory panel
 */

import { cn } from '#/utils/cn';

import { Tooltip } from '../Tooltip';

interface VersionMismatchBannerProps {
  runVersion: number;
  currentVersion: number;
  onGoToVersion: () => void;
  className?: string;
  compact?: boolean;
}

export function VersionMismatchBanner({
  runVersion,
  currentVersion,
  onGoToVersion,
  className,
  compact = false,
}: VersionMismatchBannerProps) {
  const tooltipText = `This run was executed on v${runVersion}, but you're visualizing it on v${currentVersion} of the workflow. Big things may have changed.`;

  return (
    <div
      className={cn('bg-yellow-50', className)}
      role="alert"
      aria-live="polite"
    >
      <div className="flex items-center gap-2 px-3 py-2">
        <Tooltip content={tooltipText} side="top">
          <span
            className="hero-information-circle h-4 w-4 text-yellow-800 shrink-0"
            aria-hidden="true"
          />
        </Tooltip>
        {!compact && (
          <span className="text-xs text-yellow-800">
            This run took place on version {runVersion}.
          </span>
        )}
        <span className="flex-grow" />
        <button
          type="button"
          onClick={onGoToVersion}
          className="text-xs font-medium text-yellow-900 hover:text-yellow-950 whitespace-nowrap"
        >
          View as executed <span aria-hidden="true">&rarr;</span>
        </button>
      </div>
    </div>
  );
}
