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
  return (
    <div
      className={cn('bg-yellow-50', className)}
      role="alert"
      aria-live="polite"
    >
      <div className="flex items-start gap-2 px-3 py-2">
        <span
          className="hero-information-circle h-4 w-4 text-yellow-800 shrink-0 mt-0.5"
          aria-hidden="true"
        />
        <div className={cn('flex-1 min-w-0', compact && 'max-w-[150px]')}>
          <div className="text-xs text-yellow-800">
            You're viewing a run from v{runVersion} on workflow v
            {currentVersion}.{' '}
            <button
              type="button"
              onClick={onGoToVersion}
              className="font-medium text-yellow-900 hover:text-yellow-950 whitespace-nowrap"
            >
              Go to v{runVersion} <span aria-hidden="true"> &rarr;</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
