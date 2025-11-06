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

import { cn } from "#/utils/cn";

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
        "alert-warning flex items-start gap-3 px-4 py-3 rounded-md border",
        className
      )}
      role="alert"
      aria-live="polite"
    >
      <span
        className="hero-exclamation-triangle h-5 w-5 flex-shrink-0"
        aria-hidden="true"
      />
      <div className="text-sm">
        <p className="font-medium mb-1">Version mismatch</p>
        <p>
          This run was executed on version {runVersion}, but you're viewing
          version {currentVersion}. Steps shown may not match the current
          workflow structure.
        </p>
      </div>
    </div>
  );
}
