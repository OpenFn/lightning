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

// =============================================================================
// Semver version range helpers
//
// Jobs may lock their adaptor to a version *range* instead of an exact
// version: "6.x" (highest available 6.*) or "6.4.x" (highest available
// 6.4.*). The backend resolves ranges to concrete versions at run time;
// these helpers let the frontend do the same against a known versions list
// (e.g. for fetching type definitions from jsDelivr, which does not
// understand range syntax).
// =============================================================================

type ParsedVersion = [major: number, minor: number, patch: number];

const EXACT_VERSION_REGEX = /^(\d+)\.(\d+)\.(\d+)$/;

/** Parses "N.M.P" into numeric parts; returns null for anything else. */
function parseVersion(version: string): ParsedVersion | null {
  const match = version.match(EXACT_VERSION_REGEX);
  if (!match) return null;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

/** Numeric semver comparison: negative if a < b, positive if a > b. */
function compareParsedVersions(a: ParsedVersion, b: ParsedVersion): number {
  if (a[0] !== b[0]) return a[0] - b[0];
  if (a[1] !== b[1]) return a[1] - b[1];
  return a[2] - b[2];
}

/**
 * Returns true when a version token is a range that needs resolution to a
 * concrete version: "N.x", "N.M.x", "^N.M.P", or "~N.M.P".
 * Exact versions ("1.2.3") and "latest" are NOT ranges.
 */
export function isVersionRange(version: string): boolean {
  return /^(\d+\.x|\d+\.\d+\.x|[\^~]\d+\.\d+\.\d+)$/.test(version);
}

/**
 * Builds a predicate that tests whether a parsed version satisfies a range.
 * Returns null for unrecognized range syntax.
 */
function buildRangeMatcher(
  range: string
): ((version: ParsedVersion) => boolean) | null {
  const majorMatch = range.match(/^(\d+)\.x$/);
  if (majorMatch) {
    const major = Number(majorMatch[1]);
    return v => v[0] === major;
  }

  const minorMatch = range.match(/^(\d+)\.(\d+)\.x$/);
  if (minorMatch) {
    const major = Number(minorMatch[1]);
    const minor = Number(minorMatch[2]);
    return v => v[0] === major && v[1] === minor;
  }

  const caretMatch = range.match(/^\^(\d+)\.(\d+)\.(\d+)$/);
  if (caretMatch) {
    const base: ParsedVersion = [
      Number(caretMatch[1]),
      Number(caretMatch[2]),
      Number(caretMatch[3]),
    ];
    // npm caret: same major, >= base. For 0.x majors the minor is the
    // compatibility boundary (^0.2.3 → >=0.2.3 <0.3.0).
    return v =>
      compareParsedVersions(v, base) >= 0 &&
      v[0] === base[0] &&
      (base[0] !== 0 || v[1] === base[1]);
  }

  const tildeMatch = range.match(/^~(\d+)\.(\d+)\.(\d+)$/);
  if (tildeMatch) {
    const base: ParsedVersion = [
      Number(tildeMatch[1]),
      Number(tildeMatch[2]),
      Number(tildeMatch[3]),
    ];
    // npm tilde: same major.minor, >= base.
    return v =>
      compareParsedVersions(v, base) >= 0 &&
      v[0] === base[0] &&
      v[1] === base[1];
  }

  return null;
}

/**
 * Resolves a version or version range against a list of concrete versions,
 * returning the highest matching version.
 *
 * Behavior by input:
 * - Exact version ("6.4.2"): returned as-is (pass-through, no list check).
 * - "latest": resolved to the highest parseable version in `versions`.
 *   Callers whose downstream consumers understand "latest" natively (e.g.
 *   jsDelivr dist-tags) may skip resolution for it.
 * - Ranges ("6.x", "6.4.x", "^6.4.2", "~6.4.2"): highest version in
 *   `versions` satisfying the range.
 * - Anything unrecognized, or no matching version: null.
 *
 * Unparseable entries in `versions` (e.g. "1.0.0-beta.1") are skipped.
 * The list does not need to be sorted.
 */
export function resolveVersionRange(
  versionOrRange: string,
  versions: string[]
): string | null {
  if (EXACT_VERSION_REGEX.test(versionOrRange)) {
    return versionOrRange;
  }

  const matcher =
    versionOrRange === 'latest'
      ? () => true
      : buildRangeMatcher(versionOrRange);
  if (!matcher) return null;

  let best: { raw: string; parsed: ParsedVersion } | null = null;
  for (const raw of versions) {
    const parsed = parseVersion(raw);
    if (!parsed || !matcher(parsed)) continue;
    if (!best || compareParsedVersions(parsed, best.parsed) > 0) {
      best = { raw, parsed };
    }
  }
  return best?.raw ?? null;
}

/**
 * Builds a descending version option list with range entries interleaved so
 * that each range sits directly above the concrete versions it covers:
 *
 *   ["6.4.2", "6.4.1", "6.3.0", "5.1.0"]
 *   → ["6.x", "6.4.x", "6.4.2", "6.4.1", "6.3.x", "6.3.0",
 *      "5.x", "5.1.x", "5.1.0"]
 *
 * A range entry is only emitted when it covers at least one known version.
 * Unparseable versions are appended at the end without range entries.
 * Input does not need to be sorted; "latest" is NOT included (callers
 * prepend it if desired).
 */
export function interleaveVersionRanges(versions: string[]): string[] {
  const parseable: { raw: string; parsed: ParsedVersion }[] = [];
  const unparseable: string[] = [];

  for (const raw of versions) {
    if (raw === 'latest') continue;
    const parsed = parseVersion(raw);
    if (parsed) {
      parseable.push({ raw, parsed });
    } else {
      unparseable.push(raw);
    }
  }

  parseable.sort((a, b) => compareParsedVersions(b.parsed, a.parsed));

  const result: string[] = [];
  let currentMajor: number | null = null;
  let currentMinorKey: string | null = null;

  for (const { raw, parsed } of parseable) {
    const [major, minor] = parsed;
    if (major !== currentMajor) {
      result.push(`${major}.x`);
      currentMajor = major;
      currentMinorKey = null;
    }
    const minorKey = `${major}.${minor}`;
    if (minorKey !== currentMinorKey) {
      result.push(`${minorKey}.x`);
      currentMinorKey = minorKey;
    }
    result.push(raw);
  }

  return [...result, ...unparseable];
}
