import { format } from 'date-fns';
import { useEffect, useRef, useState } from 'react';

import { Tooltip } from '../../components/Tooltip';
import { cn } from '../../utils/cn';
import { useRunSummary } from '../hooks/useHistory';
import {
  useLatestSnapshotId,
  useRequestVersions,
  useVersions,
  useVersionsError,
  useVersionsLoaded,
  useVersionsLoading,
} from '../hooks/useSessionContext';
import { notifications } from '../lib/notifications';
import { usePinnedView } from '../lib/pinnedView';
import type { Version } from '../types/sessionContext';
import { releaseActionLabel } from '../utils/releaseLabel';

interface VersionDropdownProps {
  currentVersion: number | null;
  latestVersion: number | null;
  onVersionSelect: (version: number | 'latest') => void;
  /**
   * Offered per row, because restore is about the version being read rather
   * than the workflow on screen. Omitted when the viewer cannot edit.
   */
  onVersionRestore?: (version: number) => void;
}

export function VersionDropdown({
  currentVersion,
  latestVersion,
  onVersionSelect,
  onVersionRestore,
}: VersionDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Get versions state from SessionContextStore
  const versions = useVersions();
  const latestSnapshotId = useLatestSnapshotId();
  const isLoaded = useVersionsLoaded();
  const isLoading = useVersionsLoading();
  const versionsError = useVersionsError();
  const requestVersions = useRequestVersions();

  // `?release=` carries a release version_number, not a snapshot lock_version.
  const {
    release: pinnedParam,
    isPinnedRelease,
    asRun: asRunParam,
    isViewingAsExecuted: isAsRun,
  } = usePinnedView();
  const pinnedVersionNumber = isPinnedRelease ? Number(pinnedParam) : null;

  // `?as_run=` opens the workflow as one run executed it, so the chip names the
  // version that run executed against. A run whose snapshot was never
  // published has no number to name it by. It is not called a draft here: the
  // lifecycle badge alongside already uses that word for a workflow that is not
  // live, and this is a statement about content, not about the workflow.
  const asRun = useRunSummary(asRunParam);
  const asRunVersionNumber =
    asRun === undefined ? undefined : (asRun.version_number ?? null);

  // Show placeholder while loading version information
  const isLoadingVersion = currentVersion === null || latestVersion === null;

  // With neither param set the client joined the live room, so the document is
  // the current one whatever the store's lock_version says. Comparing lock
  // versions here used to render one as `v1`, a release number that does not
  // exist, next to a list that correctly said nothing had been published.
  const isLatestVersion = !isLoadingVersion && !isPinnedRelease && !isAsRun;

  // The content on screen, whichever way it was reached. The list ticks the
  // version that published it and ticks nothing when no version did, so the
  // chip and the tick are two readings of one value and cannot disagree.
  const viewedSnapshotId = isPinnedRelease
    ? (versions.find(version => version.version_number === pinnedVersionNumber)
        ?.snapshot_id ?? null)
    : isAsRun
      ? (asRun?.snapshot_id ?? null)
      : latestSnapshotId;

  const currentVersionDisplay = isLoadingVersion
    ? '•'
    : isPinnedRelease
      ? `v${pinnedParam}`
      : isAsRun
        ? asRunVersionNumber === undefined
          ? '•'
          : asRunVersionNumber === null
            ? 'unpublished'
            : `v${asRunVersionNumber}`
        : 'latest';

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

  // Fetch versions when the dropdown opens, once. Asking because the list is
  // empty asks forever on a workflow that has never been published, since the
  // answer to that question is an empty list.
  useEffect(() => {
    if (isOpen && !isLoaded && !isLoading) {
      void requestVersions();
    }
  }, [isOpen, isLoaded, isLoading, requestVersions]);

  // Show error notification when versionsError is set
  useEffect(() => {
    if (versionsError) {
      notifications.alert({
        title: 'Failed to load versions',
        description: 'Please try again',
      });
    }
  }, [versionsError]);

  // The newest release means "follow live", so it clears the pin rather than
  // pinning to itself.
  const handleVersionClick = (version: Version) => {
    if (version.is_latest) {
      onVersionSelect('latest');
    } else {
      onVersionSelect(version.version_number);
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
        <div className="absolute left-0 mt-2 w-72 rounded-md bg-white shadow-lg outline-1 outline-black/5 z-50 max-h-80 overflow-y-auto">
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
                No published versions
              </div>
            ) : (
              <>
                <p className="px-4 pt-1 pb-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Version history
                </p>

                {versions.map(version => {
                  // Ticked when this version published the content on screen.
                  // Reading it as "nothing pinned, so it must be the newest"
                  // ticked a version you were not looking at: in a run view, and
                  // on a live document that has been saved since it went live.
                  const isActive =
                    version.snapshot_id != null &&
                    version.snapshot_id === viewedSnapshotId;

                  const date = new Date(version.inserted_at);
                  const validDate = !Number.isNaN(date.getTime());
                  const absolute = validDate ? format(date, 'd MMM yyyy') : '';
                  const exact = validDate
                    ? format(date, 'd MMM yyyy, HH:mm')
                    : '';

                  return (
                    <div
                      key={version.lock_version}
                      className={cn(
                        'group flex items-start hover:bg-gray-100',
                        isActive ? 'bg-primary-50' : ''
                      )}
                    >
                      <button
                        type="button"
                        onClick={() => handleVersionClick(version)}
                        className={cn(
                          'min-w-0 flex-1 text-left px-4 py-2.5 text-sm flex items-start gap-3',
                          isActive ? 'text-primary-900' : 'text-gray-700'
                        )}
                        role="menuitem"
                      >
                        <span
                          className={cn(
                            'mt-0.5 shrink-0 rounded px-1.5 py-0.5 text-xs font-medium ring-1 ring-inset',
                            version.is_latest
                              ? 'bg-green-100 text-green-800 ring-green-600/20'
                              : 'bg-gray-100 text-gray-600 ring-gray-500/10'
                          )}
                        >
                          v{version.version_number}
                        </span>

                        <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                          <span className="truncate">
                            {releaseActionLabel(version)}
                          </span>
                          <span className="flex min-w-0 items-center gap-1 text-xs text-gray-500">
                            {version.published_by && (
                              <>
                                <span className="min-w-0 truncate">
                                  {version.published_by}
                                </span>
                                <span aria-hidden="true">·</span>
                              </>
                            )}
                            <Tooltip content={exact} side="top">
                              <span className="whitespace-nowrap">
                                {absolute}
                              </span>
                            </Tooltip>
                          </span>
                        </span>

                        {isActive && (
                          <span className="hero-check mt-0.5 h-4 w-4 shrink-0 text-primary-600" />
                        )}
                      </button>

                      {/* The newest release is what is live, so there is nothing
                        to put back. */}
                      {onVersionRestore && !version.is_latest && (
                        <button
                          type="button"
                          onClick={() => {
                            onVersionRestore(version.version_number);
                            setIsOpen(false);
                          }}
                          className="shrink-0 self-center px-3 py-2.5 text-xs
                          font-medium text-primary-700 opacity-0
                          hover:underline focus:opacity-100
                          group-hover:opacity-100"
                          data-testid={`restore-version-${version.version_number}`}
                        >
                          Restore
                        </button>
                      )}
                    </div>
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
