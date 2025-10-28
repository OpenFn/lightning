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
  const isSandbox = !!parentProjectId;
  const sandboxName = projectName || "sandbox";

  if (!isSandbox) {
    return null;
  }

  const positionClasses = position === "absolute" ? "absolute z-5" : "relative";

  return (
    <div
      id="sandbox-mode-alert"
      className={`bg-primary-100 text-primary-800 w-full flex items-center gap-x-6 px-6 py-2.5 sm:px-3.5 sm:before:flex-1 ${positionClasses}`}
      data-testid="sandbox-indicator-banner"
    >
      <p className="text-sm leading-6">
        <span className="hero-beaker h-5 w-5 inline-block align-middle mr-2" />{" "}
        {variant === "compact" ? (
          <>
            sandbox: <span className="font-bold">{sandboxName}</span>
          </>
        ) : (
          <>
            You are currently working in the sandbox{" "}
            <span className="font-bold">{sandboxName}</span>
          </>
        )}
      </p>
      <div className="flex flex-1 justify-end"></div>
    </div>
  );
}
