import { useEffect, useMemo, useState } from 'react';

import {
  deriveVersionTiers,
  resolveVersionRange,
} from '#/collaborative-editor/utils/adaptorUtils';
import { cn } from '#/utils/cn';

import { VersionPicker } from './VersionPicker';

const EXACT_VERSION_REGEX = /^\d+\.\d+\.\d+$/;

type TierKind = 'major' | 'minor' | 'exact' | 'latest';

/**
 * Maps a stored version token to the tier radio it represents.
 * Caret ranges behave like a major lock, tilde ranges like a minor lock.
 */
function tierKindForVersion(version: string): TierKind | null {
  if (/^\d+\.x$/.test(version) || version.startsWith('^')) return 'major';
  if (/^\d+\.\d+\.x$/.test(version) || version.startsWith('~')) return 'minor';
  if (version === 'latest') return 'latest';
  if (EXACT_VERSION_REGEX.test(version)) return 'exact';
  return null;
}

/** Sorts concrete versions newest-first (numeric, not lexicographic). */
function sortVersionsDescending(versions: string[]): string[] {
  return [...versions].sort((a, b) => {
    const aParts = a.split('.').map(Number);
    const bParts = b.split('.').map(Number);
    for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
      const aNum = aParts[i] || 0;
      const bNum = bParts[i] || 0;
      if (aNum !== bNum) return bNum - aNum;
    }
    return 0;
  });
}

interface TierOptionProps {
  value: TierKind;
  checked: boolean;
  onSelect: () => void;
  icon: string;
  iconClassName?: string;
  title: string;
  badge?: string | undefined;
  description: string;
  hint?: string | null | undefined;
  /** Rendered below the label row, outside the <label> so interacting with
   * it (e.g. the embedded version picker) does not toggle the radio. */
  children?: React.ReactNode;
}

/**
 * A single version-tier radio row with icon, title, optional badge and a
 * one-line description.
 */
function TierOption({
  value,
  checked,
  onSelect,
  icon,
  iconClassName,
  title,
  badge,
  description,
  hint,
  children,
}: TierOptionProps) {
  return (
    <div
      className={cn(
        'rounded-md border',
        checked ? 'border-primary-400 bg-primary-50/50' : 'border-gray-200'
      )}
    >
      <label className="flex items-start gap-3 p-3 cursor-pointer hover:bg-gray-50 rounded-md">
        <input
          type="radio"
          name="adaptor-version-tier"
          value={value}
          checked={checked}
          onChange={onSelect}
          aria-label={title}
          className="mt-0.5 h-4 w-4 text-primary-600 focus:ring-primary-500 border-gray-300"
        />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span
              className={cn(icon, 'h-4 w-4', iconClassName ?? 'text-gray-500')}
              aria-hidden="true"
              role="img"
            />
            <span className="text-sm font-medium text-gray-900">{title}</span>
            {badge && (
              <span className="text-xs font-medium text-primary-700 bg-primary-50 rounded-full px-2 py-0.5">
                {badge}
              </span>
            )}
          </div>
          <p className="mt-0.5 text-sm text-gray-500">
            {description}
            {hint && <span className="text-gray-400"> Currently {hint}.</span>}
          </p>
        </div>
      </label>
      {children && <div className="px-3 pb-3 pl-10">{children}</div>}
    </div>
  );
}

interface VersionTierSelectorProps {
  /** Concrete versions known for the adaptor (unsorted is fine) */
  versions: string[];
  /** Stored version token: "6.x", "6.4.x", "6.4.2" or "latest" */
  currentVersion: string;
  /** Called with the new stored token whenever the user picks one */
  onVersionChange: (version: string) => void;
}

/**
 * Tiered version selection guiding users toward semver range locking:
 *
 * - Major lock ("6.x", recommended): improvements and security fixes
 * - Minor lock ("6.4.x"): bugfixes only
 * - Advanced (collapsed unless in use): exact pin or "latest"
 *
 * Tiers derive from the CURRENT selection's major/minor so a job sitting on
 * an older major is never pushed into a breaking upgrade; a subtle upsell
 * line offers the newer major instead.
 */
export function VersionTierSelector({
  versions,
  currentVersion,
  onVersionChange,
}: VersionTierSelectorProps) {
  const tiers = useMemo(
    () => deriveVersionTiers(currentVersion, versions),
    [currentVersion, versions]
  );

  const majorTier = tiers.major;
  const minorTier = tiers.minor;

  const selectedKind = tierKindForVersion(currentVersion);
  const selectionIsAdvanced =
    selectedKind === 'exact' || selectedKind === 'latest';
  // With no derivable tiers (e.g. unknown adaptor), the advanced options are
  // all we have to offer.
  const forceAdvanced = selectionIsAdvanced || !majorTier;

  // Advanced starts (and stays) expanded whenever the stored selection lives
  // there; the user may also expand it manually.
  const [advancedOpen, setAdvancedOpen] = useState(forceAdvanced);
  useEffect(() => {
    if (forceAdvanced) setAdvancedOpen(true);
  }, [forceAdvanced]);

  const sortedVersions = useMemo(
    () => sortVersionsDescending(versions.filter(v => v !== 'latest')),
    [versions]
  );

  // The concrete version shown in the exact-pin picker: the pinned version
  // itself, or what the current range resolves to, or the newest known.
  const exactPickerValue = EXACT_VERSION_REGEX.test(currentVersion)
    ? currentVersion
    : (resolveVersionRange(currentVersion, versions) ??
      sortedVersions[0] ??
      '');

  const newerMajorTier = tiers.newerMajor;
  const newerMajorLabel = newerMajorTier
    ? `v${newerMajorTier.token.replace(/\.x$/, '')}`
    : null;

  return (
    <div className="space-y-2">
      {majorTier && (
        <TierOption
          value="major"
          checked={selectedKind === 'major'}
          onSelect={() => onVersionChange(majorTier.token)}
          icon="hero-sparkles"
          iconClassName="text-primary-600"
          title={`v${majorTier.token.replace(/\.x$/, '')}`}
          badge="Recommended"
          description={`Gets v${majorTier.token.replace(/\.x$/, '')} improvements & security fixes automatically.`}
          hint={majorTier.resolved}
        />
      )}

      {minorTier && (
        <TierOption
          value="minor"
          checked={selectedKind === 'minor'}
          onSelect={() => onVersionChange(minorTier.token)}
          icon="hero-shield-check"
          iconClassName="text-gray-500"
          title={`v${minorTier.token.replace(/\.x$/, '')}`}
          badge="Bugfixes only"
          description={`Only patch updates within ${minorTier.token.replace(/\.x$/, '')}.`}
          hint={minorTier.resolved}
        />
      )}

      {newerMajorTier && newerMajorLabel && (
        <p className="text-xs text-gray-500 px-1">
          {newerMajorLabel} is available. Upgrading majors may require code
          changes.{' '}
          <button
            type="button"
            onClick={() => onVersionChange(newerMajorTier.token)}
            className="text-primary-600 hover:text-primary-700 font-medium underline focus:outline-none"
          >
            Switch to {newerMajorLabel}
          </button>
        </p>
      )}

      <button
        type="button"
        onClick={() => setAdvancedOpen(open => !open)}
        aria-expanded={advancedOpen}
        className="flex items-center gap-1 text-sm font-medium text-gray-600
          hover:text-gray-900 focus:outline-none"
      >
        <span
          className={cn(
            'hero-chevron-right h-4 w-4 transition-transform',
            advancedOpen && 'rotate-90'
          )}
          aria-hidden="true"
          role="img"
        />
        Advanced
      </button>

      {advancedOpen && (
        <div className="space-y-2">
          <TierOption
            value="exact"
            checked={selectedKind === 'exact'}
            onSelect={() => {
              if (exactPickerValue) onVersionChange(exactPickerValue);
            }}
            icon="hero-map-pin"
            iconClassName="text-gray-500"
            title="Pin exact version"
            description="Never changes. You own updates."
          >
            <VersionPicker
              versions={sortedVersions}
              selectedVersion={exactPickerValue}
              onVersionChange={onVersionChange}
            />
          </TierOption>

          <TierOption
            value="latest"
            checked={selectedKind === 'latest'}
            onSelect={() => onVersionChange('latest')}
            icon="hero-exclamation-triangle"
            iconClassName="text-amber-500"
            title="Always newest (latest)"
            description="Major releases may break this step."
          />
        </div>
      )}
    </div>
  );
}
