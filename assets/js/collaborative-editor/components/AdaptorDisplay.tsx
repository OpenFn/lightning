import { useMemo } from 'react';

import { cn } from '#/utils/cn';

import { extractAdaptorDisplayName } from '../utils/adaptorUtils';

import { AdaptorIcon } from './AdaptorIcon';

type AdaptorDisplaySize = 'xs' | 'sm' | 'md' | 'lg' | 'xl';

interface AdaptorDisplayProps {
  /** Full adaptor string like "@openfn/language-common@latest" */
  adaptor: string | null | undefined;
  /** Optional credential ID to show credential indicator */
  credentialId?: string | null;
  /** Callback when Edit button is clicked */
  onEdit?: () => void;
  /** Callback when adaptor icon/name is clicked (opens adaptor picker) */
  onChangeAdaptor?: () => void;
  /** Size variant - defaults to "md" */
  size?: AdaptorDisplaySize;
  /** Whether the workflow is read-only (hides Edit/Change buttons) */
  isReadOnly?: boolean;
}

/**
 * Resolves an adaptor specifier into its package name and version
 * @param adaptor - Full NPM package string like "@openfn/language-common@1.4.3"
 * @returns Tuple of package name and version, or null if parsing fails
 */
function resolveAdaptor(adaptor: string | null | undefined): {
  package: string | null;
  version: string | null;
} {
  if (!adaptor) return { package: null, version: null };
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
  size = 'md',
  isReadOnly = false,
}: AdaptorDisplayProps) {
  // Parse adaptor package and version
  const { package: adaptorPackage, version: adaptorVersion } = useMemo(
    () => resolveAdaptor(adaptor),
    [adaptor]
  );

  // Get display name from package
  const adaptorDisplayName = useMemo(() => {
    return extractAdaptorDisplayName(adaptorPackage || '');
  }, [adaptorPackage]);

  // Safe package name for icon (fallback to empty string)
  const safeAdaptorPackage = adaptorPackage || '';

  // Check if credential is connected
  const hasCredential = !!credentialId;

  // Check if adaptor is language-common (shouldn't pulse for common)
  const isLanguageCommon = adaptorPackage === '@openfn/language-common';

  // Should pulse when: no credential AND not language-common
  const shouldPulse = !hasCredential && !isLanguageCommon;

  // World-class size system with perfect proportions
  // Each size variant maintains visual harmony with consistent spacing ratios
  const sizeConfig: Record<
    AdaptorDisplaySize,
    {
      iconSize: 'sm' | 'md';
      textSize: string;
      versionTextSize: string;
      containerPadding: string;
      adaptorButton: string;
      editButton: string;
      badgeSize: string;
      badgeIconSize: string;
      gap: string;
    }
  > = {
    xs: {
      iconSize: 'sm',
      textSize: 'text-xs',
      versionTextSize: 'text-[10px]',
      containerPadding: 'p-1.5',
      adaptorButton: 'pl-1 pr-1.5 py-0.5 h-6',
      editButton: 'px-2 py-0.5 h-6',
      badgeSize: 'w-4 h-4',
      badgeIconSize: 'h-2.5 w-2.5',
      gap: 'gap-2',
    },
    sm: {
      iconSize: 'sm',
      textSize: 'text-sm',
      versionTextSize: 'text-xs',
      containerPadding: 'p-2',
      adaptorButton: 'pl-1.5 pr-2 py-1 h-7',
      editButton: 'px-2.5 py-1 h-7',
      badgeSize: 'w-5 h-5',
      badgeIconSize: 'h-3 w-3',
      gap: 'gap-2',
    },
    md: {
      iconSize: 'md',
      textSize: 'text-sm',
      versionTextSize: 'text-xs',
      containerPadding: 'p-2',
      adaptorButton: 'pl-2 pr-3 py-1.5 h-8',
      editButton: 'px-3 py-1.5 h-8',
      badgeSize: 'w-6 h-6',
      badgeIconSize: 'h-4 w-4',
      gap: 'gap-3',
    },
    lg: {
      iconSize: 'md',
      textSize: 'text-base',
      versionTextSize: 'text-sm',
      containerPadding: 'p-3',
      adaptorButton: 'pl-2.5 pr-4 py-2 h-10',
      editButton: 'px-4 py-2 h-10',
      badgeSize: 'w-7 h-7',
      badgeIconSize: 'h-4.5 w-4.5',
      gap: 'gap-3',
    },
    xl: {
      iconSize: 'md',
      textSize: 'text-lg',
      versionTextSize: 'text-base',
      containerPadding: 'p-4',
      adaptorButton: 'pl-3 pr-5 py-2.5 h-12',
      editButton: 'px-5 py-2.5 h-12',
      badgeSize: 'w-8 h-8',
      badgeIconSize: 'h-5 w-5',
      gap: 'gap-4',
    },
  };

  const config = sizeConfig[size];

  return (
    <div
      className={`flex items-center justify-between ${config.gap} w-full rounded-lg border border-slate-300 sm:text-sm sm:leading-6 ${config.containerPadding}`}
    >
      <div className={`flex items-center ${config.gap} min-w-0 flex-1`}>
        {onChangeAdaptor && !isReadOnly ? (
          <button
            type="button"
            onClick={onChangeAdaptor}
            className={`flex items-center gap-2 ${config.adaptorButton} border border-gray-300 bg-white rounded-md font-medium text-gray-700 hover:bg-gray-50 focus:outline-none transition-colors`}
            aria-label="Change adaptor"
          >
            <AdaptorIcon name={safeAdaptorPackage} size={config.iconSize} />
            <span
              className={`font-medium text-gray-900 truncate ${config.textSize}`}
            >
              {adaptorDisplayName}
            </span>
          </button>
        ) : (
          <div className="flex items-center gap-2 opacity-50">
            <AdaptorIcon name={safeAdaptorPackage} size={config.iconSize} />
            <span
              className={`font-medium text-gray-500 truncate ${config.textSize}`}
            >
              {adaptorDisplayName}
            </span>
          </div>
        )}
        <span
          className={`${config.versionTextSize} ${isReadOnly ? 'text-gray-400' : 'text-gray-500'} whitespace-nowrap`}
        >
          {adaptorVersion === 'latest'
            ? 'latest'
            : adaptorVersion
              ? `v${adaptorVersion}`
              : ''}
        </span>
        {hasCredential && (
          <span
            className={`inline-flex items-center justify-center ${config.badgeSize} rounded-full bg-green-100 text-green-800 flex-shrink-0`}
            title="Credential connected"
            aria-label="Credential connected"
          >
            <span className={`hero-key ${config.badgeIconSize}`} />
          </span>
        )}
      </div>
      {onEdit && !isReadOnly && (
        <button
          type="button"
          onClick={onEdit}
          className={cn(
            config.editButton,
            'rounded-md font-medium focus:outline-none flex-shrink-0 transition-colors relative',
            config.textSize,
            hasCredential
              ? 'border border-gray-300 bg-white text-gray-700 hover:bg-gray-50'
              : 'bg-primary-600 hover:bg-primary-500 text-white shadow-xs focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600'
          )}
          aria-label={hasCredential ? 'Edit adaptor' : 'Connect credential'}
        >
          {hasCredential ? 'Edit' : 'Connect'}
          {shouldPulse && (
            <span className="absolute -top-1 -right-1 flex h-3 w-3">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-3 w-3 bg-red-500"></span>
            </span>
          )}
        </button>
      )}
    </div>
  );
}
