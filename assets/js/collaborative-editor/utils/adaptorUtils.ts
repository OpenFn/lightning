/**
 * Utility functions for adaptor name extraction and formatting
 */

/**
 * Extracts the package name without version from a full package string
 * @example "@openfn/language-salesforce@latest" → "@openfn/language-salesforce"
 * @example "@openfn/language-http@1.2.3" → "@openfn/language-http"
 * @example "@openfn/language-http" → "@openfn/language-http"
 * @example "language-common@latest" → "language-common"
 */
export function extractPackageName(adaptorString: string): string {
  // Handle scoped packages (@scope/package@version)
  if (adaptorString.startsWith('@')) {
    // Find the last @ which separates package from version
    const lastAtIndex = adaptorString.lastIndexOf('@');
    // If there's only one @ (the scoped package prefix), return as-is
    if (lastAtIndex === 0) {
      return adaptorString;
    }
    // Otherwise, return everything before the last @
    return adaptorString.substring(0, lastAtIndex);
  }

  // Handle unscoped packages (package@version)
  const atIndex = adaptorString.indexOf('@');
  if (atIndex === -1) {
    return adaptorString;
  }
  return adaptorString.substring(0, atIndex);
}

/**
 * Extracts the adaptor name from a full adaptor string.
 *
 * @example
 * extractAdaptorName("@openfn/language-salesforce@2.0.0") // "salesforce"
 * extractAdaptorName("language-http") // "http"
 * extractAdaptorName("invalid") // null
 */
export function extractAdaptorName(adaptorString: string): string | null {
  const match = adaptorString.match(/language-(.+?)(@|$)/);
  return match?.[1] ?? null;
}

/**
 * Formats an adaptor name for display by converting to title case.
 * This is a presentation concern - use only in UI components.
 *
 * @example
 * toTitleCase("salesforce") // "Salesforce"
 * toTitleCase("google-sheets") // "Google Sheets"
 * toTitleCase("my_custom_adaptor") // "My Custom Adaptor"
 */
export function toTitleCase(name: string): string {
  return name
    .split(/[-_]/)
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
}

/**
 * Gets the display name for an adaptor, with optional title case formatting.
 * Returns the full adaptor string as fallback if extraction fails.
 *
 * @param adaptorString - Full adaptor string (e.g., "@openfn/language-http@1.0.0")
 * @param options - Configuration options
 * @param options.titleCase - Whether to apply title case formatting (default: false)
 * @param options.fallback - Fallback value if extraction fails (default: adaptorString)
 *
 * @example
 * getAdaptorDisplayName("@openfn/language-salesforce@2.0.0")
 * // "salesforce"
 *
 * getAdaptorDisplayName("@openfn/language-salesforce@2.0.0", { titleCase: true })
 * // "Salesforce"
 *
 * getAdaptorDisplayName("invalid", { fallback: "Unknown" })
 * // "Unknown"
 */
export function getAdaptorDisplayName(
  adaptorString: string,
  options: { titleCase?: boolean; fallback?: string } = {}
): string {
  const { titleCase = false, fallback = adaptorString } = options;

  const name = extractAdaptorName(adaptorString);

  if (!name) {
    return fallback;
  }

  return titleCase ? toTitleCase(name) : name;
}

/**
 * Combined: Extract and format adaptor display name from package
 * @example "@openfn/language-salesforce@latest" → "Salesforce"
 * @example "@openfn/language-http@1.0.0" → "Http"
 * @example "@openfn/language-dhis-2" → "Dhis 2"
 */
export function extractAdaptorDisplayName(adaptorPackage: string): string {
  const name = extractAdaptorName(adaptorPackage);
  return name ? toTitleCase(name) : adaptorPackage;
}
