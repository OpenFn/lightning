import { useEffect, useRef, useState } from 'react';

import { cn } from '../../utils/cn';
import { channelRequest } from '../hooks/useChannel';
import { useSession } from '../hooks/useSession';
import { notifications } from '../lib/notifications';

interface Version {
  lock_version: number;
  inserted_at: string;
  is_latest: boolean;
}

interface VersionDropdownProps {
  currentVersion: number | null;
  latestVersion: number | null;
  onVersionSelect: (version: number | 'latest') => void;
}

export function VersionDropdown({
  currentVersion,
  latestVersion,
  onVersionSelect,
}: VersionDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [versions, setVersions] = useState<Version[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const { provider } = useSession();
  const channel = provider?.channel;

  // Show placeholder while loading version information
  const isLoadingVersion = currentVersion === null || latestVersion === null;

  // Determine if viewing latest version (only when we have both values)
  const isLatestVersion = !isLoadingVersion && currentVersion === latestVersion;

  // Format version display
  const currentVersionDisplay = isLoadingVersion
    ? '•'
    : isLatestVersion
      ? 'latest'
      : `v${String(currentVersion).substring(0, 7)}`;

  // Style based on version (matching snapshot_version_chip)
  const buttonStyles = isLoadingVersion
    ? 'bg-gray-100 text-gray-600 hover:bg-gray-200'
    : isLatestVersion
      ? 'bg-primary-100 text-primary-800 hover:bg-primary-200'
      : 'bg-yellow-100 text-yellow-800 hover:bg-yellow-200';

  // Close dropdown when clicking outside or pressing Escape
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setIsOpen(false);
      }
    }

    function handleEscape(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        setIsOpen(false);
      }
    }

    if (isOpen) {
      // Use capture phase to catch events before they're stopped by React Flow
      document.addEventListener('mousedown', handleClickOutside, true);
      document.addEventListener('keydown', handleEscape);
      return () => {
        document.removeEventListener('mousedown', handleClickOutside, true);
        document.removeEventListener('keydown', handleEscape);
      };
    }
  }, [isOpen]);

  // Fetch versions when dropdown opens
  useEffect(() => {
    if (isOpen && channel) {
      // Only fetch if we don't already have versions OR if we're not already loading
      if (versions.length === 0 && !isLoading) {
        setIsLoading(true);
        setError(null);

        channelRequest<{ versions: Version[] }>(channel, 'request_versions', {})
          .then(response => {
            console.log('Received versions response:', response);
            console.log('Versions array:', response.versions);
            console.log('Versions length:', response.versions.length);
            setVersions(response.versions || []);
            setIsLoading(false);
            return;
          })
          .catch(err => {
            console.error('Failed to fetch versions:', err);
            notifications.alert({
              title: 'Failed to load versions',
              description: 'Please try again',
            });
            setError('Failed to load versions');
            setIsLoading(false);
          });
      }
    }
  }, [isOpen, versions.length, channel, isLoading]);

  // Clear version cache when latest version changes
  // This makes the component reactive to state (SessionContextStore) instead of
  // directly listening to channel events, providing better separation of concerns
  //
  // When latestVersion changes, ALL users (even those viewing snapshots) should
  // clear their cache so the dropdown shows the updated version list with the
  // new latest version when they open it.
  const prevLatestVersionRef = useRef<number | null>(latestVersion);

  useEffect(() => {
    const prevLatestVersion = prevLatestVersionRef.current;

    // Only clear if we had a previous value and it changed
    // This prevents clearing on initial mount (when prevLatestVersion is null)
    if (
      prevLatestVersion !== null &&
      latestVersion !== null &&
      prevLatestVersion !== latestVersion
    ) {
      setVersions([]);
    }

    prevLatestVersionRef.current = latestVersion;
  }, [latestVersion]);

  const handleVersionClick = (version: Version) => {
    if (version.is_latest) {
      onVersionSelect('latest');
    } else {
      onVersionSelect(version.lock_version);
    }
    setIsOpen(false);
  };

  return (
    <div ref={dropdownRef} className="relative inline-block">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className={cn(
          'inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-xs font-medium transition-colors',
          buttonStyles
        )}
        aria-expanded={isOpen}
        aria-haspopup="true"
      >
        <span>{currentVersionDisplay}</span>
        <span
          className={cn(
            'hero-chevron-down h-3 w-3 transition-transform',
            isOpen && 'rotate-180'
          )}
        />
      </button>

      {isOpen && (
        <div className="absolute left-0 mt-2 w-56 rounded-md bg-white shadow-lg outline-1 outline-black/5 z-50 max-h-80 overflow-y-auto">
          <div
            className="py-1"
            role="menu"
            aria-orientation="vertical"
            aria-labelledby="options-menu"
          >
            {isLoading ? (
              <div className="px-4 py-2 text-sm text-gray-500">
                Loading versions...
              </div>
            ) : error ? (
              <div className="px-4 py-2 text-sm text-red-600">{error}</div>
            ) : versions.length === 0 ? (
              <div className="px-4 py-2 text-sm text-gray-500">
                No versions available
              </div>
            ) : (
              versions.map((version, index) => {
                const isSelected = version.is_latest
                  ? isLatestVersion
                  : version.lock_version === currentVersion;

                // Show "latest" for the latest version, otherwise show version number
                // For the first item (which is latest), show "latest"
                // For subsequent items, show version number even if they have is_latest=true
                const displayText =
                  index === 0 && version.is_latest
                    ? 'latest'
                    : `v${String(version.lock_version).substring(0, 7)}`;

                return (
                  <button
                    key={version.lock_version}
                    type="button"
                    onClick={() => handleVersionClick(version)}
                    className={cn(
                      'w-full text-left px-4 py-2 text-sm hover:bg-gray-100 flex items-center justify-between',
                      isSelected
                        ? 'bg-primary-50 text-primary-900'
                        : 'text-gray-700'
                    )}
                    role="menuitem"
                  >
                    <div className="flex flex-col">
                      <span className="font-medium">{displayText}</span>
                      <span className="text-xs text-gray-500">
                        {new Date(version.inserted_at).toLocaleString()}
                      </span>
                    </div>
                    {isSelected && (
                      <span className="hero-check h-4 w-4 text-primary-600" />
                    )}
                  </button>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}
