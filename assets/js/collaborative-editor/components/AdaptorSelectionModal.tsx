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

  // Filter out project adaptors from all adaptors to avoid duplicates
  const projectAdaptorNames = new Set(filteredProjectAdaptors.map(a => a.name));
  let filteredAllAdaptors = filterAdaptors(allAdaptors).filter(
    adaptor => !projectAdaptorNames.has(adaptor.name)
  );

  // Always ensure HTTP adaptor is available as fallback
  const hasResults =
    filteredProjectAdaptors.length > 0 || filteredAllAdaptors.length > 0;

  if (!hasResults && searchQuery) {
    // Show HTTP adaptor as fallback when no results
    const httpAdaptor = allAdaptors.find(a => a.name.includes("language-http"));
    if (httpAdaptor) {
      filteredAllAdaptors = [httpAdaptor];
    }
  }

  const handleRowClick = (adaptorName: string) => {
    // Immediately select and close (Figma design - no Continue button)
    onSelect(adaptorName);
    onClose();
  };

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
                >
                  {!hasResults && searchQuery && (
                    <div className="mb-4 px-3 py-4 bg-blue-50 rounded-lg border border-blue-100">
                      <p className="text-sm text-gray-700 mb-1">
                        <span className="font-medium">No adaptor found</span>{" "}
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
                          title={
                            extractAdaptorName(adaptor.name) || adaptor.name
                          }
                          description={`Latest: ${adaptor.latest}`}
                          icon={<AdaptorIcon name={adaptor.name} size="md" />}
                          onClick={() => handleRowClick(adaptor.name)}
                        />
                      ))}
                    </ListSection>
                  )}

                  {filteredAllAdaptors.length > 0 && (
                    <ListSection
                      title={
                        filteredProjectAdaptors.length > 0
                          ? "All adaptors"
                          : "Available adaptors"
                      }
                    >
                      {filteredAllAdaptors.map(adaptor => (
                        <ListRow
                          key={adaptor.name}
                          title={
                            extractAdaptorName(adaptor.name) || adaptor.name
                          }
                          description={`Latest: ${adaptor.latest}`}
                          icon={<AdaptorIcon name={adaptor.name} size="sm" />}
                          onClick={() => handleRowClick(adaptor.name)}
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
