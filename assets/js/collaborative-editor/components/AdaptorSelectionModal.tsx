import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import { useEffect, useMemo, useState } from 'react';

import { useKeyboardShortcut } from '../keyboard';

import { useAdaptors } from '../hooks/useAdaptors';
import type { Adaptor } from '../types/adaptor';
import { getAdaptorDisplayName } from '../utils/adaptorUtils';

import { AdaptorIcon } from './AdaptorIcon';
import { ListRow, ListSection, SearchableList } from './SearchableList';

interface AdaptorSelectionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (adaptorSpec: string) => void;
  projectAdaptors?: Adaptor[];
}

interface AdaptorWithDisplayName extends Adaptor {
  displayName: string;
}

export function AdaptorSelectionModal({
  isOpen,
  onClose,
  onSelect,
  projectAdaptors = [],
}: AdaptorSelectionModalProps) {
  const allAdaptors = useAdaptors();
  const [searchQuery, setSearchQuery] = useState('');
  const [focusedIndex, setFocusedIndex] = useState<number>(0);

  // Reset state when modal closes
  useEffect(() => {
    if (!isOpen) {
      setSearchQuery('');
      setFocusedIndex(0);
    }
  }, [isOpen]);

  // Reset focused index when search query changes
  useEffect(() => {
    setFocusedIndex(0);
  }, [searchQuery]);

  // High-priority Escape handler to prevent closing parent IDE/inspector
  // Priority 100 (MODAL) ensures this runs before IDE handler (priority 50)
  useKeyboardShortcut(
    'Escape',
    () => {
      onClose();
    },
    100,
    { enabled: isOpen }
  );

  const httpAdaptor = useMemo(
    () => allAdaptors.find(a => a.name.includes('language-http')),
    [allAdaptors]
  );

  const projectAdaptorsWithDisplayNames = useMemo<
    AdaptorWithDisplayName[]
  >(() => {
    return projectAdaptors.map(adaptor => ({
      ...adaptor,
      displayName: getAdaptorDisplayName(adaptor.name, {
        titleCase: true,
        fallback: adaptor.name,
      }),
    }));
  }, [projectAdaptors]);

  const allAdaptorsWithDisplayNames = useMemo<AdaptorWithDisplayName[]>(() => {
    return allAdaptors.map(adaptor => ({
      ...adaptor,
      displayName: getAdaptorDisplayName(adaptor.name, {
        titleCase: true,
        fallback: adaptor.name,
      }),
    }));
  }, [allAdaptors]);

  // Memoize filtered results based on search query
  const { filteredProjectAdaptors, filteredAllAdaptors, showingHttpFallback } =
    useMemo(() => {
      const lowerQuery = searchQuery.toLowerCase();

      // Filter project adaptors
      const filteredProject = searchQuery
        ? projectAdaptorsWithDisplayNames.filter(adaptor =>
            adaptor.displayName.toLowerCase().includes(lowerQuery)
          )
        : projectAdaptorsWithDisplayNames;

      // Filter all adaptors and exclude duplicates from project adaptors
      const projectAdaptorNames = new Set(filteredProject.map(a => a.name));
      let filteredAll = allAdaptorsWithDisplayNames.filter(
        adaptor => !projectAdaptorNames.has(adaptor.name)
      );

      if (searchQuery) {
        filteredAll = filteredAll.filter(adaptor =>
          adaptor.displayName.toLowerCase().includes(lowerQuery)
        );
      }

      const hasMatchingResults =
        filteredProject.length > 0 || filteredAll.length > 0;

      // Show HTTP adaptor as fallback when no results
      const showingFallback =
        !hasMatchingResults && !!searchQuery && !!httpAdaptor;
      if (showingFallback) {
        const httpWithDisplay: AdaptorWithDisplayName = {
          ...httpAdaptor,
          displayName: getAdaptorDisplayName(httpAdaptor.name, {
            titleCase: true,
            fallback: httpAdaptor.name,
          }),
        };
        filteredAll = [httpWithDisplay];
      }

      return {
        filteredProjectAdaptors: filteredProject,
        filteredAllAdaptors: filteredAll,
        showingHttpFallback: showingFallback,
      };
    }, [
      searchQuery,
      projectAdaptorsWithDisplayNames,
      allAdaptorsWithDisplayNames,
      httpAdaptor,
    ]);

  // Create flat list of all visible adaptors for keyboard navigation
  const allVisibleAdaptors = useMemo<AdaptorWithDisplayName[]>(() => {
    return [...filteredProjectAdaptors, ...filteredAllAdaptors];
  }, [filteredProjectAdaptors, filteredAllAdaptors]);

  const handleRowClick = (adaptor: AdaptorWithDisplayName) => {
    // Construct full adaptor spec with semantic version
    const adaptorSpec = `${adaptor.name}@${adaptor.latest}`;

    // Immediately select and close (Figma design - no Continue button)
    onSelect(adaptorSpec);
    onClose();
  };

  // Keyboard navigation handlers
  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    const totalItems = allVisibleAdaptors.length;
    if (totalItems === 0) return;

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setFocusedIndex(prev => (prev + 1) % totalItems);
        break;
      case 'ArrowUp':
        e.preventDefault();
        setFocusedIndex(prev => (prev - 1 + totalItems) % totalItems);
        break;
      case 'Enter': {
        e.preventDefault();
        const focusedAdaptor = allVisibleAdaptors[focusedIndex];
        handleRowClick(focusedAdaptor);
        break;
      }
    }
  };

  // Generate ID for focused item (for aria-activedescendant)
  const activeDescendantId =
    focusedIndex >= 0 && focusedIndex < allVisibleAdaptors.length
      ? `adaptor-option-${allVisibleAdaptors[focusedIndex].name}`
      : undefined;

  // Helper to check if an adaptor is currently focused
  const isAdaptorFocused = (
    adaptor: AdaptorWithDisplayName,
    sectionOffset: number
  ) => {
    const adaptorIndex =
      sectionOffset +
      (sectionOffset === 0
        ? filteredProjectAdaptors.indexOf(adaptor)
        : filteredAllAdaptors.indexOf(adaptor));
    return adaptorIndex === focusedIndex;
  };

  return (
    <Dialog open={isOpen} onClose={onClose} className="relative z-50">
      <DialogBackdrop
        transition
        className="fixed inset-0 bg-gray-900/60 backdrop-blur-sm transition-opacity
        data-closed:opacity-0 data-enter:duration-300
        data-enter:ease-out data-leave:duration-200
        data-leave:ease-in"
      />

      <div className="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div
          className="flex min-h-full items-end justify-center p-4
          text-center sm:items-center sm:p-0"
        >
          <DialogPanel
            transition
            className="relative transform overflow-hidden rounded-lg
            bg-white px-4 pb-4 pt-5 text-left shadow-xl
            transition-all data-closed:translate-y-4
            data-closed:opacity-0 data-enter:duration-300
            data-enter:ease-out data-leave:duration-200
            data-leave:ease-in sm:my-8 sm:w-full sm:max-w-lg
            sm:p-6"
          >
            <div className="flex items-start gap-3">
              <div className="flex-1">
                <SearchableList
                  placeholder="Search for an adaptor to connect..."
                  onSearch={setSearchQuery}
                  onKeyDown={handleKeyDown}
                  listboxId="adaptor-listbox"
                  {...(activeDescendantId && { activeDescendantId })}
                >
                  {showingHttpFallback && (
                    <div className="mb-4 px-3 py-4 bg-blue-50 rounded-lg border border-blue-100">
                      <p className="text-sm text-gray-700 mb-1">
                        <span className="font-medium">No adaptor found</span>{' '}
                        for "{searchQuery}"
                      </p>
                      <p className="text-sm text-gray-600">
                        Try the HTTP adaptor below to connect to any system with
                        a REST API.
                      </p>
                    </div>
                  )}

                  {filteredProjectAdaptors.length > 0 && (
                    <ListSection title="Adaptors in this project">
                      {filteredProjectAdaptors.map(adaptor => (
                        <ListRow
                          key={adaptor.name}
                          id={`adaptor-option-${adaptor.name}`}
                          title={adaptor.displayName}
                          description={`Latest: ${adaptor.latest}`}
                          icon={<AdaptorIcon name={adaptor.name} size="md" />}
                          onClick={() => handleRowClick(adaptor)}
                          focused={isAdaptorFocused(adaptor, 0)}
                        />
                      ))}
                    </ListSection>
                  )}

                  {filteredAllAdaptors.length > 0 && (
                    <ListSection
                      title={
                        filteredProjectAdaptors.length > 0
                          ? 'All adaptors'
                          : 'Available adaptors'
                      }
                    >
                      {filteredAllAdaptors.map(adaptor => (
                        <ListRow
                          key={adaptor.name}
                          id={`adaptor-option-${adaptor.name}`}
                          title={adaptor.displayName}
                          description={`Latest: ${adaptor.latest}`}
                          icon={<AdaptorIcon name={adaptor.name} size="sm" />}
                          onClick={() => handleRowClick(adaptor)}
                          focused={isAdaptorFocused(
                            adaptor,
                            filteredProjectAdaptors.length
                          )}
                        />
                      ))}
                    </ListSection>
                  )}
                </SearchableList>
              </div>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
