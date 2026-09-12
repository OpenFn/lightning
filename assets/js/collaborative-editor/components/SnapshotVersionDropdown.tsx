/**
 * The version picker for a user without experimental features.
 *
 * Lists every saved snapshot, numbered by its own `lock_version`, and pins one
 * with `?v=`. This is the editor's older contract, kept whole rather than
 * folded into `VersionDropdown` as a second mode: that component lists the
 * publish trail, numbers by release, and offers Restore per row, and one
 * component answering both would have to be read twice to be understood once.
 *
 * The two share nothing but their shape on screen. `?v=` and `?release=` build
 * different collaboration rooms on purpose (see `lib/pinnedView.ts`), so the
 * picker a user sees decides which numbering the whole session uses.
 */

import { useEffect, useRef, useState } from 'react';

import { cn } from '../../utils/cn';
import {
  useRequestVersions,
  useVersions,
  useVersionsError,
  useVersionsLoaded,
  useVersionsLoading,
} from '../hooks/useSessionContext';
import { notifications } from '../lib/notifications';
import { usePinnedView } from '../lib/pinnedView';
import type { Version } from '../types/sessionContext';

interface SnapshotVersionDropdownProps {
  currentVersion: number | null;
  latestVersion: number | null;
  onVersionSelect: (version: number | 'latest') => void;
}

export function SnapshotVersionDropdown({
  currentVersion,
  latestVersion,
  onVersionSelect,
}: SnapshotVersionDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const versions = useVersions();
  const isLoaded = useVersionsLoaded();
  const isLoading = useVersionsLoading();
  const versionsError = useVersionsError();
  const requestVersions = useRequestVersions();

  const { isPinnedSnapshot } = usePinnedView();

  // Show placeholder while loading version information
  const isLoadingVersion = currentVersion === null || latestVersion === null;

  // Viewing latest only when we have both numbers AND nothing is pinned
  const isLatestVersion =
    !isLoadingVersion && currentVersion === latestVersion && !isPinnedSnapshot;

  const currentVersionDisplay = isLoadingVersion
    ? '•'
    : isLatestVersion
      ? 'latest'
      : `v${String(currentVersion).substring(0, 7)}`;

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

    if (!isOpen) return undefined;

    // Use capture phase to catch events before they're stopped by React Flow
    document.addEventListener('mousedown', handleClickOutside, true);
    document.addEventListener('keydown', handleEscape);

    return () => {
      document.removeEventListener('mousedown', handleClickOutside, true);
      document.removeEventListener('keydown', handleEscape);
    };
  }, [isOpen]);

  // Fetch versions when the dropdown opens, once. Keyed on whether the request
  // has finished rather than on the list being empty: a workflow with no
  // snapshots answers with an empty list, and reading that as "not fetched yet"
  // asks again on every render for as long as the menu is open.
  useEffect(() => {
    if (isOpen && !isLoaded && !isLoading) {
      void requestVersions();
    }
  }, [isOpen, isLoaded, isLoading, requestVersions]);

  useEffect(() => {
    if (versionsError) {
      notifications.alert({
        title: 'Failed to load versions',
        description: 'Please try again',
      });
    }
  }, [versionsError]);

  const handleVersionClick = (version: Version | 'latest') => {
    if (version === 'latest') {
      onVersionSelect('latest');
    } else {
      onVersionSelect(version.lock_version);
    }
    setIsOpen(false);
  };

  const newest = versions[0];

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
            ) : versionsError ? (
              <div className="px-4 py-2 text-sm text-red-600">
                {versionsError}
              </div>
            ) : versions.length === 0 ? (
              <div className="px-4 py-2 text-sm text-gray-500">
                No versions available
              </div>
            ) : (
              <>
                {/* "latest" removes the pin rather than pinning to itself */}
                {newest?.is_latest && (
                  <button
                    key="latest"
                    type="button"
                    onClick={() => handleVersionClick('latest')}
                    className={cn(
                      'w-full text-left px-4 py-2 text-sm hover:bg-gray-100 flex items-center justify-between',
                      isLatestVersion
                        ? 'bg-primary-50 text-primary-900'
                        : 'text-gray-700'
                    )}
                    role="menuitem"
                  >
                    <div className="flex flex-col">
                      <span className="font-medium">latest</span>
                      <span className="text-xs text-gray-500">
                        {new Date(newest.inserted_at).toLocaleString()}
                      </span>
                    </div>
                    {isLatestVersion && (
                      <span className="hero-check h-4 w-4 text-primary-600" />
                    )}
                  </button>
                )}

                {versions.map(version => {
                  const isSelected =
                    !isLatestVersion && version.lock_version === currentVersion;

                  const displayText = `v${String(version.lock_version).substring(0, 7)}`;

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
                })}
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
