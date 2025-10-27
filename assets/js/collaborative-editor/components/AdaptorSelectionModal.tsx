import React, { useEffect, useState } from "react";
import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from "@headlessui/react";
import { useHotkeysContext } from "react-hotkeys-hook";

import { useAdaptors } from "../hooks/useAdaptors";
import { SearchableList, ListSection, ListRow } from "./SearchableList";
import { AdaptorIcon } from "./AdaptorIcon";
import type { Adaptor } from "../types/adaptor";

interface AdaptorSelectionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (adaptorName: string) => void;
  projectAdaptors?: Adaptor[];
}

function extractAdaptorName(str: string): string | null {
  const match = str.match(/language-(.+?)(@|$)/);
  return match?.[1] ?? null;
}

export function AdaptorSelectionModal({
  isOpen,
  onClose,
  onSelect,
  projectAdaptors = [],
}: AdaptorSelectionModalProps) {
  const allAdaptors = useAdaptors();
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedAdaptor, setSelectedAdaptor] = useState<string | null>(null);

  // Keyboard scope management
  const { enableScope, disableScope } = useHotkeysContext();

  useEffect(() => {
    if (isOpen) {
      enableScope("modal");
      disableScope("panel");
    } else {
      disableScope("modal");
      enableScope("panel");
    }

    return () => {
      disableScope("modal");
    };
  }, [isOpen, enableScope, disableScope]);

  // Reset state when modal closes
  useEffect(() => {
    if (!isOpen) {
      setSearchQuery("");
      setSelectedAdaptor(null);
    }
  }, [isOpen]);

  // Filter adaptors based on search query
  const filterAdaptors = (adaptors: Adaptor[]) => {
    if (!searchQuery) return adaptors;

    const lowerQuery = searchQuery.toLowerCase();
    return adaptors.filter(adaptor => {
      const displayName = extractAdaptorName(adaptor.name) || "";
      return (
        displayName.toLowerCase().includes(lowerQuery) ||
        adaptor.name.toLowerCase().includes(lowerQuery)
      );
    });
  };

  const filteredProjectAdaptors = filterAdaptors(projectAdaptors);
  const filteredAllAdaptors = filterAdaptors(allAdaptors);

  const handleConfirm = () => {
    if (selectedAdaptor) {
      onSelect(selectedAdaptor);
      onClose();
    }
  };

  const handleRowClick = (adaptorName: string) => {
    setSelectedAdaptor(adaptorName);
  };

  // Allow Enter key to confirm selection
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && selectedAdaptor) {
      e.preventDefault();
      handleConfirm();
    }
  };

  const hasResults =
    filteredProjectAdaptors.length > 0 || filteredAllAdaptors.length > 0;

  return (
    <Dialog open={isOpen} onClose={onClose} className="relative z-50">
      <DialogBackdrop
        transition
        className="fixed inset-0 bg-gray-500/75 transition-opacity
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
            onKeyDown={handleKeyDown}
            className="relative transform overflow-hidden rounded-lg
            bg-white px-4 pb-4 pt-5 text-left shadow-xl
            transition-all data-closed:translate-y-4
            data-closed:opacity-0 data-enter:duration-300
            data-enter:ease-out data-leave:duration-200
            data-leave:ease-in sm:my-8 sm:w-full sm:max-w-2xl
            sm:p-6"
          >
            <div>
              <DialogTitle
                as="h3"
                className="text-lg font-semibold text-gray-900 mb-4"
              >
                Select Adaptor
              </DialogTitle>

              <SearchableList
                placeholder="Search adaptors..."
                onSearch={setSearchQuery}
              >
                {!hasResults && (
                  <div className="text-center py-8">
                    <span
                      className="hero-magnifying-glass h-12 w-12
                      text-gray-300 mx-auto block mb-2"
                    />
                    <p className="text-sm text-gray-500">
                      No adaptors match your search
                    </p>
                  </div>
                )}

                {filteredProjectAdaptors.length > 0 && (
                  <ListSection title="Project Adaptors">
                    {filteredProjectAdaptors.map(adaptor => (
                      <ListRow
                        key={adaptor.name}
                        title={extractAdaptorName(adaptor.name) || adaptor.name}
                        description={`Latest: ${adaptor.latest}`}
                        icon={<AdaptorIcon name={adaptor.name} size="sm" />}
                        selected={selectedAdaptor === adaptor.name}
                        onClick={() => handleRowClick(adaptor.name)}
                      />
                    ))}
                  </ListSection>
                )}

                {filteredAllAdaptors.length > 0 && (
                  <ListSection
                    title={
                      filteredProjectAdaptors.length > 0
                        ? "All Adaptors"
                        : "Available Adaptors"
                    }
                  >
                    {filteredAllAdaptors.map(adaptor => (
                      <ListRow
                        key={adaptor.name}
                        title={extractAdaptorName(adaptor.name) || adaptor.name}
                        description={`Latest: ${adaptor.latest}`}
                        icon={<AdaptorIcon name={adaptor.name} size="sm" />}
                        selected={selectedAdaptor === adaptor.name}
                        onClick={() => handleRowClick(adaptor.name)}
                      />
                    ))}
                  </ListSection>
                )}
              </SearchableList>
            </div>

            <div
              className="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense
              sm:grid-cols-2 sm:gap-3"
            >
              <button
                type="button"
                onClick={handleConfirm}
                disabled={!selectedAdaptor}
                className="inline-flex w-full justify-center
                rounded-md px-3 py-2 text-sm font-semibold text-white
                shadow-xs focus-visible:outline-2
                focus-visible:outline-offset-2 sm:col-start-2
                bg-primary-600 hover:bg-primary-500
                focus-visible:outline-primary-600 disabled:opacity-50
                disabled:cursor-not-allowed"
              >
                Continue
              </button>
              <button
                type="button"
                onClick={onClose}
                className="mt-3 inline-flex w-full justify-center
                rounded-md bg-white px-3 py-2 text-sm font-semibold
                text-gray-900 shadow-xs inset-ring inset-ring-gray-300
                hover:inset-ring-gray-400 sm:col-start-1 sm:mt-0"
              >
                Cancel
              </button>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
