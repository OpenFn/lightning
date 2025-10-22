/**
 * # Sandbox Indicator Banner
 *
 * Displays a warning banner when working in a sandbox environment.
 * Shows only when the current project has a parent (is a sandbox).
 *
 * Matches the Phoenix Common.banner component structure exactly.
 * Can be positioned absolutely (canvas overlay) or relatively (inspector panel).
 *
 * Note: parentProjectId/parentProjectName props actually contain the ROOT project
 * (top-most ancestor), not the immediate parent. This is computed via Projects.root_of/1
 * in Phoenix to handle arbitrarily deep sandbox hierarchies.
 *
 * Variants:
 * - full: Shows full message with "Switch to root project" link (for canvas)
 * - compact: Shows only "sandbox: name" (for inspector panel)
 */

interface SandboxIndicatorBannerProps {
  parentProjectId?: string | null | undefined;
  parentProjectName?: string | null | undefined;
  projectName?: string | null | undefined;
  position?: "absolute" | "relative";
  variant?: "full" | "compact";
}

export function SandboxIndicatorBanner({
  parentProjectId,
  parentProjectName,
  projectName,
  position = "absolute",
  variant = "full",
}: SandboxIndicatorBannerProps) {
  // Determine if we're in a sandbox using props
  const isSandbox = !!parentProjectId;
  const rootProjectName = parentProjectName || "root project";
  const sandboxName = projectName || "sandbox";

  // Don't show banner if not in a sandbox
  if (!isSandbox) {
    return null;
  }

  const positionClasses = position === "absolute" ? "absolute z-5" : "relative";

  // Switch to workflows list (/w) of root project
  const switchUrl = `/projects/${parentProjectId}/w`;

  return (
    <div
      id="sandbox-mode-alert"
      className={`alert-warning w-full flex items-center gap-x-6 px-6 py-2.5 sm:px-3.5 sm:before:flex-1 ${positionClasses}`}
      data-testid="sandbox-indicator-banner"
    >
      <p className="text-sm leading-6">
        <span className="hero-exclamation-triangle h-5 w-5 inline-block align-middle mr-2" />{" "}
        {variant === "compact" ? (
          `sandbox: ${sandboxName}`
        ) : (
          <>
            You are currently working in the sandbox {sandboxName}.{" "}
            <a href={switchUrl} className="whitespace-nowrap font-semibold">
              Switch to {rootProjectName}
              <span aria-hidden="true"> &rarr;</span>
            </a>
          </>
        )}
      </p>
      <div className="flex flex-1 justify-end"></div>
    </div>
  );
}
