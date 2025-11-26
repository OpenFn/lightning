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
 * - Compact two-line design with version information
 * - Dismissible via X button
 * - Positioned at top-center of canvas
 */

import { useState } from 'react';

import { cn } from '#/utils/cn';

interface VersionMismatchBannerProps {
  runVersion: number;
  currentVersion: number;
  className?: string;
}

export function VersionMismatchBanner({
  runVersion,
  currentVersion,
  className,
}: VersionMismatchBannerProps) {
  const [dismissed, setDismissed] = useState(false);

  if (dismissed) {
    return null;
  }

  return (
    <div
      className={cn('bg-yellow-50 rounded-md shadow-sm', className)}
      role="alert"
      aria-live="polite"
    >
      <div className="flex items-start gap-2 p-3">
        <span
          className="hero-information-circle h-5 w-5 text-yellow-800 shrink-0"
          aria-hidden="true"
        />
        <div className="flex-1 min-w-0">
          <div className="text-xs text-yellow-800 font-medium">
            Canvas shows v{currentVersion} (Selected run: v{runVersion})
          </div>
          <div className="text-xs text-yellow-700 mt-0.5">
            Canvas layout may differ from actual run
          </div>
        </div>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          className="shrink-0 text-yellow-700 cursor-pointer hover:text-yellow-800 transition-colors"
          aria-label="Dismiss version mismatch warning"
        >
          <span className="hero-x-mark h-4 w-4 -mt-3" />
        </button>
      </div>
    </div>
  );
}
