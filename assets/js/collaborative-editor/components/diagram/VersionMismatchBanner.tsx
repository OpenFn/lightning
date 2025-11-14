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
      className={cn(
        'w-full bg-yellow-50 text-yellow-700 justify-center flex items-center gap-x-2 px-6 py-2.5 sm:px-3.5',
        className
      )}
      role="alert"
      aria-live="polite"
    >
      <span
        className="hero-exclamation-triangle h-5 w-5 inline-block"
        aria-hidden="true"
      />
      <p className="text-sm leading-6">
        This run was executed on version {runVersion}, but you're viewing
        version {currentVersion}. Steps shown may not match the current workflow
        structure.
      </p>
    </div>
  );
}
