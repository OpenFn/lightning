import { useMemo } from "react";

import { extractAdaptorDisplayName } from "../utils/adaptorUtils";

import { AdaptorIcon } from "./AdaptorIcon";

interface AdaptorDisplayProps {
  /** Full adaptor string like "@openfn/language-common@latest" */
  adaptor: string;
  /** Optional credential ID to show credential indicator */
  credentialId?: string | null | undefined;
  /** Callback when Edit button is clicked */
  onEdit?: (() => void) | undefined;
  /** Callback when adaptor icon/name is clicked (opens adaptor picker) */
  onChangeAdaptor?: (() => void) | undefined;
  /** Optional size variant for the component */
  size?: "sm" | "md" | undefined;
}

/**
 * Resolves an adaptor specifier into its package name and version
 * @param adaptor - Full NPM package string like "@openfn/language-common@1.4.3"
 * @returns Tuple of package name and version, or null if parsing fails
 */
function resolveAdaptor(adaptor: string): {
  package: string | null;
  version: string | null;
} {
  const regex = /^(@[^@]+)@(.+)$/;
  const match = adaptor.match(regex);
  if (!match) return { package: null, version: null };
  const [, packageName, version] = match;

  return {
    package: packageName || null,
    version: version || null,
  };
}

/**
 * Reusable adaptor display component
 *
 * Shows adaptor icon, name, version, and optional credential indicator.
 * Supports two interaction modes:
 * - With onEdit: Shows Edit button (for JobForm)
 * - Without onEdit: Simplified display (for IDE Header)
 */
export function AdaptorDisplay({
  adaptor,
  credentialId,
  onEdit,
  onChangeAdaptor,
  size = "md",
}: AdaptorDisplayProps) {
  // Parse adaptor package and version
  const { package: adaptorPackage, version: adaptorVersion } = useMemo(
    () => resolveAdaptor(adaptor),
    [adaptor]
  );

  // Get display name from package
  const adaptorDisplayName = useMemo(() => {
    return extractAdaptorDisplayName(adaptorPackage || "");
  }, [adaptorPackage]);

  // Check if credential is connected
  const hasCredential = !!credentialId;

  // Size variants - ensure consistent button heights
  const iconSize = size === "sm" ? "sm" : "md";
  const textSize = size === "sm" ? "text-xs" : "text-sm";
  const buttonClasses = size === "sm" ? "px-2 py-1 h-7" : "px-3 py-1.5 h-8";

  return (
    <div className="flex items-center justify-between gap-3 border border-gray-300 p-1 rounded-md">
      <div className="flex items-center gap-2 min-w-0 flex-1">
        {onChangeAdaptor ? (
          <button
            type="button"
            onClick={onChangeAdaptor}
            className={`flex items-center gap-2 ${buttonClasses} border
            border-gray-300 bg-white rounded-md ${textSize} font-medium
            text-gray-700 hover:bg-gray-50 focus:outline-none`}
            aria-label="Change adaptor"
          >
            <AdaptorIcon name={adaptorPackage || ""} size={iconSize} />
            <span className="font-medium text-gray-900 truncate">
              {adaptorDisplayName}
            </span>
          </button>
        ) : (
          <div className={`flex items-center gap-2 ${buttonClasses}`}>
            <AdaptorIcon name={adaptorPackage || ""} size={iconSize} />
            <span className={`font-medium text-gray-900 truncate ${textSize}`}>
              {adaptorDisplayName}
            </span>
          </div>
        )}
        <span className="text-xs text-gray-500">
          {adaptorVersion === "latest" ? "latest" : `v${adaptorVersion}`}
        </span>
        {hasCredential && (
          <span
            className="inline-flex items-center justify-center w-6 h-6 rounded-full
            bg-green-100 text-green-800"
            title="Credential connected"
            aria-label="Credential connected"
          >
            <span className="hero-key h-4 w-4" />
          </span>
        )}
      </div>
      {onEdit && (
        <button
          type="button"
          onClick={onEdit}
          className={`${buttonClasses} border border-gray-300 bg-white rounded-md
          ${textSize} font-medium text-gray-700 hover:bg-gray-50
          focus:outline-none flex-shrink-0`}
          aria-label="Edit adaptor"
        >
          Edit
        </button>
      )}
    </div>
  );
}
