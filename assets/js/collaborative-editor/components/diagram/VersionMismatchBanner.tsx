/**
 * VersionMismatchBanner - Warning when viewing latest workflow but selected run used older version
 *
 * Displays when:
 * - A run is selected
 * - Viewing "latest" workflow (not a specific snapshot)
 * - The run was executed on a different version than currently displayed
 *
 * This prevents confusion when the workflow structure has changed since the run executed.
 */

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
  return (
    <div
      className={cn('rounded-md bg-yellow-50 p-4', className)}
      role="alert"
      aria-live="polite"
    >
      <div className="flex">
        <div className="shrink-0">
          <span
            className="hero-exclamation-triangle h-5 w-5 text-yellow-400"
            aria-hidden="true"
          />
        </div>
        <div className="ml-3">
          <h3 className="text-sm font-medium text-yellow-800">
            Version mismatch
          </h3>
          <div className="mt-2 text-sm text-yellow-700">
            <p>
              This run was executed with version {runVersion}, but you're
              viewing version {currentVersion}. Not all steps executed in the
              run will appear on the canvas if the workflow structure has
              changed.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
