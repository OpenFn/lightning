import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from "@headlessui/react";
import { useEffect, useMemo, useState, useRef } from "react";
import { useHotkeysContext } from "react-hotkeys-hook";

import { useCredentials } from "#/collaborative-editor/hooks/useCredentials";
import type { Adaptor } from "#/collaborative-editor/types/adaptor";
import type {
  ProjectCredential,
  KeychainCredential,
} from "#/collaborative-editor/types/credential";
import {
  extractAdaptorName,
  extractAdaptorDisplayName,
  extractPackageName,
} from "#/collaborative-editor/utils/adaptorUtils";
import { getEnvironmentBadgeColor } from "#/collaborative-editor/utils/credentialUtils";

import { AdaptorIcon } from "./AdaptorIcon";
import { VersionPicker } from "./VersionPicker";

/**
 * Extended credential type with metadata fields from the backend
 */
type CredentialWithMetadata = (ProjectCredential | KeychainCredential) & {
  owner?: { name: string } | null;
  type: "project" | "keychain";
};

interface ConfigureAdaptorModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (config: {
    adaptorPackage: string;
    adaptorVersion: string;
    credentialId: string | null;
  }) => void;
  onOpenAdaptorPicker: () => void; // Notify parent to manage modal switching to adaptor picker
  onOpenCredentialModal: (adaptorName: string) => void; // Notify parent to manage modal switching to credential modal
  currentAdaptor: string;
  currentVersion: string;
  currentCredentialId: string | null;
  allAdaptors: Adaptor[]; // All available adaptors for version selection
}

/**
 * Modal for configuring adaptor, version, and credential together
 * Matches the Figma design with three sections:
 * 1. Adaptor selection (left) with "Change" button
 * 2. Version selection (right) in dropdown
 * 3. Credential selection with radio buttons
 */
export function ConfigureAdaptorModal({
  isOpen,
  onClose,
  onSave,
  onOpenAdaptorPicker,
  onOpenCredentialModal,
  currentAdaptor,
  currentVersion,
  currentCredentialId,
  allAdaptors,
}: ConfigureAdaptorModalProps) {
  // Local state for modal form
  const [selectedAdaptor, setSelectedAdaptor] = useState(currentAdaptor);
  const [selectedVersion, setSelectedVersion] = useState(currentVersion);
  const [selectedCredentialId, setSelectedCredentialId] = useState<
    string | null
  >(currentCredentialId);
  const [showOtherCredentials, setShowOtherCredentials] = useState(false);

  // Get credentials from store
  const { projectCredentials, keychainCredentials } = useCredentials();

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

  // Reset state when modal opens or adaptor changes
  // We use refs to track previous values
  const isOpenRef = useRef(isOpen);
  const prevAdaptorRef = useRef(currentAdaptor);

  useEffect(() => {
    // Reset when modal transitions from closed to open
    const modalJustOpened = isOpen && !isOpenRef.current;
    // OR when adaptor changes while modal is open
    const adaptorChanged = isOpen && currentAdaptor !== prevAdaptorRef.current;

    if (modalJustOpened) {
      setSelectedAdaptor(currentAdaptor);
      setSelectedVersion(currentVersion);

      // Validate that currentCredentialId exists in available credentials
      // This prevents using credentials that were deleted or don't belong to this project
      if (currentCredentialId) {
        const credentialExists =
          projectCredentials.some(
            c => c.project_credential_id === currentCredentialId
          ) || keychainCredentials.some(c => c.id === currentCredentialId);

        setSelectedCredentialId(credentialExists ? currentCredentialId : null);
      } else {
        setSelectedCredentialId(null);
      }

      isOpenRef.current = isOpen;
      prevAdaptorRef.current = currentAdaptor;
    } else if (adaptorChanged) {
      setSelectedAdaptor(currentAdaptor);
      // When adaptor changes, compute newest version inline
      const packageName = extractPackageName(currentAdaptor);
      const adaptor = allAdaptors.find(a => a.name === packageName);

      if (adaptor) {
        const sortedVersions = adaptor.versions
          .map(v => v.version)
          .filter(v => v !== "latest")
          .sort((a, b) => {
            const aParts = a.split(".").map(Number);
            const bParts = b.split(".").map(Number);
            for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
              const aNum = aParts[i] || 0;
              const bNum = bParts[i] || 0;
              if (aNum !== bNum) {
                return bNum - aNum;
              }
            }
            return 0;
          });

        if (sortedVersions.length > 0 && sortedVersions[0]) {
          setSelectedVersion(sortedVersions[0]);
        } else {
          setSelectedVersion(currentVersion);
        }
      } else {
        setSelectedVersion(currentVersion);
      }

      // Validate credential when adaptor changes
      if (currentCredentialId) {
        const credentialExists =
          projectCredentials.some(
            c => c.project_credential_id === currentCredentialId
          ) || keychainCredentials.some(c => c.id === currentCredentialId);

        setSelectedCredentialId(credentialExists ? currentCredentialId : null);
      } else {
        setSelectedCredentialId(null);
      }

      prevAdaptorRef.current = currentAdaptor;
    } else {
      // Update refs even when no action is taken
      isOpenRef.current = isOpen;
      prevAdaptorRef.current = currentAdaptor;
    }
  }, [
    isOpen,
    currentAdaptor,
    currentVersion,
    currentCredentialId,
    allAdaptors,
  ]);

  // Check if the adaptor requires credentials
  const adaptorNeedsCredentials = useMemo(() => {
    const adaptorName = extractAdaptorName(selectedAdaptor);
    // Common adaptor doesn't require credentials
    return adaptorName !== "common";
  }, [selectedAdaptor]);

  // Filter credentials into sections
  const credentialSections = useMemo(() => {
    const adaptorName = extractAdaptorName(selectedAdaptor);
    if (!adaptorName) {
      return {
        schemaMatched: [],
        universal: [],
        keychain: [],
      };
    }

    // Schema-matched project credentials (exact match or OAuth smart matching)
    const schemaMatched = projectCredentials
      .filter(c => {
        // Exact schema match
        if (c.schema === adaptorName) return true;

        // Smart OAuth matching: if credential is OAuth, check oauth_client_name
        if (c.schema === "oauth" && c.oauth_client_name) {
          // Normalize both strings: lowercase, remove spaces/hyphens/underscores
          const normalizeString = (str: string) =>
            str.toLowerCase().replace(/[\s\-_]/g, "");

          const normalizedClientName = normalizeString(c.oauth_client_name);
          const normalizedAdaptorName = normalizeString(adaptorName);

          // Match if normalized OAuth client name contains normalized adaptor name
          // This handles variations like:
          // - "Google Drive" matches "googledrive"
          // - "google-sheets" matches "googlesheets"
          // - "Sales Force" matches "salesforce"
          return normalizedClientName.includes(normalizedAdaptorName);
        }

        return false;
      })
      .map(
        c =>
          ({
            ...c,
            type: "project" as const,
          }) as CredentialWithMetadata
      );

    // Universal project credentials (http and raw work with all adaptors)
    // Only show if not already in schemaMatched (avoid duplicates)
    const universal = projectCredentials
      .filter(c => {
        const isUniversal = c.schema === "http" || c.schema === "raw";
        const alreadyMatched = adaptorName === "http" || adaptorName === "raw";
        return isUniversal && !alreadyMatched;
      })
      .map(
        c =>
          ({
            ...c,
            type: "project" as const,
          }) as CredentialWithMetadata
      );

    // All keychain credentials (can't reliably filter by schema)
    const keychain = keychainCredentials.map(
      c =>
        ({
          ...c,
          type: "keychain" as const,
        }) as CredentialWithMetadata
    );

    return { schemaMatched, universal, keychain };
  }, [selectedAdaptor, projectCredentials, keychainCredentials]);

  // Automatically show "other credentials" when:
  // 1. No schema matches found, OR
  // 2. Currently selected credential is in "other credentials" section
  useEffect(() => {
    // Only run when modal is open
    if (!isOpen) return;

    const hasSchemaMatches = credentialSections.schemaMatched.length > 0;
    const hasOtherCredentials =
      credentialSections.universal.length > 0 ||
      credentialSections.keychain.length > 0;

    // Check if currently selected credential is in "other credentials"
    const selectedCredentialInOther =
      selectedCredentialId &&
      (credentialSections.universal.some(
        c => getCredentialId(c) === selectedCredentialId
      ) ||
        credentialSections.keychain.some(
          c => getCredentialId(c) === selectedCredentialId
        ));

    // Show "other credentials" if:
    // - Selected credential is in that section, OR
    // - No schema matches but we have other credentials
    if (
      selectedCredentialInOther ||
      (!hasSchemaMatches && hasOtherCredentials)
    ) {
      setShowOtherCredentials(true);
    }
    // If we have schema matches and no credential selected in "other" section, show schema matches
    else if (hasSchemaMatches) {
      setShowOtherCredentials(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, selectedAdaptor, selectedCredentialId]);

  // Get version options for selected adaptor
  const versionOptions = useMemo(() => {
    // Extract package name without version using utility function
    const packageName = extractPackageName(selectedAdaptor);

    // Use allAdaptors to get versions (not projectAdaptors)
    // This ensures we show all versions even for adaptors not yet used in the project
    const adaptor = allAdaptors.find(a => a.name === packageName);

    if (!adaptor) {
      // Adaptor not in registry, return empty array
      return [];
    }

    // Sort versions using semantic versioning (newest first)
    const sortedVersions = adaptor.versions
      .map(v => v.version)
      .filter(v => v !== "latest")
      .sort((a, b) => {
        // Split version strings into parts [major, minor, patch]
        const aParts = a.split(".").map(Number);
        const bParts = b.split(".").map(Number);

        // Compare major, minor, patch in order
        for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
          const aNum = aParts[i] || 0;
          const bNum = bParts[i] || 0;
          if (aNum !== bNum) {
            return bNum - aNum; // Descending order (newest first)
          }
        }
        return 0;
      });

    // Add "latest" as the first option
    return ["latest", ...sortedVersions];
  }, [selectedAdaptor, allAdaptors]);

  // Extract adaptor display name
  const adaptorDisplayName = useMemo(() => {
    return extractAdaptorDisplayName(selectedAdaptor);
  }, [selectedAdaptor]);

  // Handle "Change" button click - notify parent to switch modals
  const handleChangeClick = () => {
    onClose(); // Close ConfigureAdaptorModal
    onOpenAdaptorPicker(); // Let parent open AdaptorSelectionModal
  };

  // Update selected adaptor (called from parent after adaptor picker closes)
  // This will be triggered when the modal reopens with a new currentAdaptor
  // NOTE: This effect is redundant with the reset effect above (lines 107-158)
  // and can cause issues. Commenting out for now.
  // useEffect(() => {
  //   if (isOpen && currentAdaptor !== selectedAdaptor) {
  //     setSelectedAdaptor(currentAdaptor);
  //     // Reset version to newest (first in sorted array)
  //     if (versionOptions.length > 0) {
  //       setSelectedVersion(versionOptions[0]);
  //     }
  //     setSelectedCredentialId(null); // Clear credential selection
  //   }
  // }, [isOpen, currentAdaptor, selectedAdaptor, versionOptions]);

  // Handle save button click
  const handleSave = () => {
    onSave({
      adaptorPackage: selectedAdaptor,
      adaptorVersion: selectedVersion,
      credentialId: selectedCredentialId,
    });
    onClose();
  };

  // Get credential ID for comparison (handle both project and keychain)
  const getCredentialId = (cred: CredentialWithMetadata): string => {
    return cred.type === "project"
      ? (cred as ProjectCredential).project_credential_id
      : (cred as KeychainCredential).id;
  };

  // Open LiveView credential modal with adaptor schema (notifies parent)
  const handleCreateCredential = () => {
    const adaptorName = extractAdaptorName(selectedAdaptor);
    if (adaptorName) {
      onOpenCredentialModal(adaptorName);
    }
  };

  return (
    <>
      <Dialog open={isOpen} onClose={onClose} className="relative z-50">
        <DialogBackdrop
          transition
          className="fixed inset-0 bg-black/30 transition-opacity
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
              bg-white text-left shadow-xl transition-all
              data-closed:translate-y-4 data-closed:opacity-0
              data-enter:duration-300 data-enter:ease-out
              data-leave:duration-200 data-leave:ease-in sm:my-8
              sm:w-full sm:max-w-2xl"
            >
              {/* Header */}
              <div
                className="flex items-center justify-between px-6 py-4
                border-b border-gray-200"
              >
                <DialogTitle className="text-xl font-medium text-gray-900">
                  Configure connection
                </DialogTitle>
                <button
                  type="button"
                  onClick={onClose}
                  className="text-gray-400 hover:text-gray-500
                  focus:outline-none"
                  aria-label="Close"
                >
                  <span
                    className="hero-x-mark h-6 w-6"
                    aria-hidden="true"
                    role="img"
                  />
                </button>
              </div>

              {/* Body */}
              <div className="px-6 py-6 space-y-6">
                {/* Adaptor + Version Row */}
                <div className="grid grid-cols-3 gap-4 items-end">
                  {/* Adaptor Section - takes 2 columns */}
                  <div className="col-span-2">
                    <label
                      className="flex items-center gap-1 text-sm
                      font-medium text-gray-700 mb-2"
                    >
                      Adaptor
                      <span
                        className="hero-information-circle h-4 w-4
                        text-gray-400"
                        aria-label="Information"
                        role="img"
                      />
                    </label>
                    <div
                      className="flex items-center justify-between p-3
                      border border-gray-200 rounded-md bg-white"
                    >
                      <div className="flex items-center gap-2 min-w-0 flex-1">
                        <AdaptorIcon name={selectedAdaptor} size="md" />
                        <span className="font-medium text-gray-900 truncate">
                          {adaptorDisplayName}
                        </span>
                      </div>
                      <button
                        type="button"
                        onClick={handleChangeClick}
                        aria-label="Change adaptor"
                        className="px-3 py-1.5 border border-gray-300
                        bg-white rounded-md text-sm font-medium
                        text-gray-700 hover:bg-gray-50
                        focus:outline-none focus:ring-2
                        focus:ring-offset-2 focus:ring-primary-500
                        flex-shrink-0"
                      >
                        Change
                      </button>
                    </div>
                  </div>

                  {/* Version Section - takes 1 column */}
                  <div className="col-span-1">
                    <label
                      className="block text-sm font-medium text-gray-700
                      mb-2"
                    >
                      Version
                    </label>
                    <VersionPicker
                      versions={versionOptions}
                      selectedVersion={selectedVersion}
                      onVersionChange={setSelectedVersion}
                    />
                  </div>
                </div>

                {/* Credentials Section */}
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <label
                      className="flex items-center gap-1 text-sm
                      font-medium text-gray-700"
                    >
                      Credentials
                      <span
                        className="hero-information-circle h-4 w-4
                        text-gray-400"
                        aria-label="Information"
                        role="img"
                      />
                    </label>
                    {adaptorNeedsCredentials && (
                      <button
                        type="button"
                        aria-label="Create new credential"
                        className="text-primary-600 hover:text-primary-700
                        text-sm font-medium underline focus:outline-none"
                        onClick={handleCreateCredential}
                      >
                        New Credential
                      </button>
                    )}
                  </div>

                  {/* Show message if adaptor doesn't need credentials */}
                  {!adaptorNeedsCredentials ? (
                    <div
                      className="border border-gray-200 rounded-md p-6
                      text-center bg-gray-50"
                    >
                      <p className="text-gray-600 text-sm">
                        This adaptor does not require credentials.
                      </p>
                    </div>
                  ) : /* Check if we have any credentials at all */
                  credentialSections.schemaMatched.length === 0 &&
                    credentialSections.universal.length === 0 &&
                    credentialSections.keychain.length === 0 ? (
                    /* No credentials at all - show empty state */
                    <div className="border border-gray-200 rounded-md p-6 text-center">
                      <p className="text-gray-500 mb-3">
                        No credentials found in this project
                      </p>
                      <button
                        type="button"
                        onClick={handleCreateCredential}
                        className="text-primary-600 hover:text-primary-700
                        text-sm font-medium underline focus:outline-none"
                      >
                        Create a new credential
                      </button>
                    </div>
                  ) : !showOtherCredentials &&
                    credentialSections.schemaMatched.length > 0 ? (
                    <>
                      {/* Schema-matched credentials */}
                      <div className="border border-gray-200 rounded-md divide-y">
                        {credentialSections.schemaMatched.map(cred => {
                          const credId = getCredentialId(cred);
                          const isSelected = selectedCredentialId === credId;
                          return (
                            <label
                              key={credId}
                              htmlFor={`credential-${credId}`}
                              className="flex items-start gap-3 p-4
                                hover:bg-gray-50 cursor-pointer"
                            >
                              <input
                                id={`credential-${credId}`}
                                type="radio"
                                name="credential"
                                value={credId}
                                checked={isSelected}
                                onChange={() => setSelectedCredentialId(credId)}
                                aria-label={`Select ${cred.name} credential`}
                                className="mt-1 h-4 w-4 text-primary-600
                                  focus:ring-primary-500 border-gray-300"
                              />
                              <div className="flex-1 min-w-0">
                                <div className="mb-1">
                                  <span
                                    className="font-medium text-gray-900
                                      truncate"
                                  >
                                    {cred.name}
                                  </span>
                                </div>
                                {cred.owner && (
                                  <div className="flex items-center gap-1 text-sm text-gray-500">
                                    <span
                                      className="hero-user-solid h-4 w-4"
                                      aria-hidden="true"
                                      role="img"
                                    />
                                    {cred.owner.name}
                                  </div>
                                )}
                              </div>
                              {isSelected && (
                                <button
                                  type="button"
                                  onClick={e => {
                                    e.preventDefault();
                                    setSelectedCredentialId(null);
                                  }}
                                  className="text-gray-400 hover:text-gray-600
                                    focus:outline-none flex-shrink-0 ml-2"
                                  aria-label="Clear credential selection"
                                >
                                  <span
                                    className="hero-x-mark h-5 w-5"
                                    aria-hidden="true"
                                  />
                                </button>
                              )}
                            </label>
                          );
                        })}
                      </div>

                      {/* Toggle to other credentials */}
                      {(credentialSections.universal.length > 0 ||
                        credentialSections.keychain.length > 0) && (
                        <div className="mt-3">
                          <button
                            type="button"
                            onClick={() => setShowOtherCredentials(true)}
                            className="text-sm text-primary-600 hover:text-primary-700
                            font-medium underline focus:outline-none"
                          >
                            Other credentials
                          </button>
                        </div>
                      )}
                    </>
                  ) : (
                    <>
                      {/* Other credentials (HTTP, Raw, Keychain) */}
                      <div className="space-y-4">
                        {/* Universal credentials (HTTP and Raw) */}
                        {credentialSections.universal.length > 0 && (
                          <div>
                            {/* Divider with label */}
                            <div className="relative flex items-center pb-3">
                              <div className="flex-grow border-t border-gray-200"></div>
                              <span className="flex-shrink mx-4 text-xs font-normal text-gray-400 uppercase tracking-wide">
                                Generic Credentials
                              </span>
                              <div className="flex-grow border-t border-gray-200"></div>
                            </div>
                            <div className="border border-gray-200 rounded-md divide-y">
                              {credentialSections.universal.map(cred => {
                                const credId = getCredentialId(cred);
                                const isSelected =
                                  selectedCredentialId === credId;
                                return (
                                  <label
                                    key={credId}
                                    htmlFor={`credential-${credId}`}
                                    className="flex items-start gap-3 p-4
                                    hover:bg-gray-50 cursor-pointer"
                                  >
                                    <input
                                      id={`credential-${credId}`}
                                      type="radio"
                                      name="credential"
                                      value={credId}
                                      checked={selectedCredentialId === credId}
                                      onChange={() =>
                                        setSelectedCredentialId(credId)
                                      }
                                      aria-label={`Select ${cred.name} credential`}
                                      className="mt-1 h-4 w-4 text-primary-600
                                      focus:ring-primary-500 border-gray-300"
                                    />
                                    <div className="flex-1 min-w-0">
                                      <div className="mb-1">
                                        <span
                                          className="font-medium text-gray-900
                                          truncate"
                                        >
                                          {cred.name}
                                        </span>
                                      </div>
                                      {cred.owner && (
                                        <div className="flex items-center gap-1 text-sm text-gray-500">
                                          <span
                                            className="hero-user-solid h-4 w-4"
                                            aria-hidden="true"
                                            role="img"
                                          />
                                          {cred.owner.name}
                                        </div>
                                      )}
                                    </div>
                                    {isSelected && (
                                      <button
                                        type="button"
                                        onClick={e => {
                                          e.preventDefault();
                                          setSelectedCredentialId(null);
                                        }}
                                        className="text-gray-400 hover:text-gray-600
                                        focus:outline-none flex-shrink-0 ml-2"
                                        aria-label="Clear credential selection"
                                      >
                                        <span
                                          className="hero-x-mark h-5 w-5"
                                          aria-hidden="true"
                                        />
                                      </button>
                                    )}
                                  </label>
                                );
                              })}
                            </div>
                          </div>
                        )}

                        {/* Keychain credentials */}
                        {credentialSections.keychain.length > 0 && (
                          <div>
                            {/* Divider with label */}
                            <div className="relative flex items-center py-4">
                              <div className="flex-grow border-t border-gray-200"></div>
                              <span className="flex-shrink mx-4 text-xs font-normal text-gray-400 uppercase tracking-wide">
                                Keychain Credentials
                              </span>
                              <div className="flex-grow border-t border-gray-200"></div>
                            </div>
                            <div className="border border-gray-200 rounded-md divide-y">
                              {credentialSections.keychain.map(cred => {
                                const credId = getCredentialId(cred);
                                const isSelected =
                                  selectedCredentialId === credId;
                                return (
                                  <label
                                    key={credId}
                                    htmlFor={`credential-${credId}`}
                                    className="flex items-start gap-3 p-4
                                    hover:bg-gray-50 cursor-pointer"
                                  >
                                    <input
                                      id={`credential-${credId}`}
                                      type="radio"
                                      name="credential"
                                      value={credId}
                                      checked={isSelected}
                                      onChange={() =>
                                        setSelectedCredentialId(credId)
                                      }
                                      aria-label={`Select ${cred.name} credential`}
                                      className="mt-1 h-4 w-4 text-primary-600
                                      focus:ring-primary-500 border-gray-300"
                                    />
                                    <div className="flex-1 min-w-0">
                                      <div className="flex items-center gap-2 mb-1">
                                        <span
                                          className="font-medium text-gray-900
                                          truncate"
                                        >
                                          {cred.name}
                                        </span>
                                      </div>
                                    </div>
                                    {isSelected && (
                                      <button
                                        type="button"
                                        onClick={e => {
                                          e.preventDefault();
                                          setSelectedCredentialId(null);
                                        }}
                                        className="text-gray-400 hover:text-gray-600
                                        focus:outline-none flex-shrink-0 ml-2"
                                        aria-label="Clear credential selection"
                                      >
                                        <span
                                          className="hero-x-mark h-5 w-5"
                                          aria-hidden="true"
                                        />
                                      </button>
                                    )}
                                  </label>
                                );
                              })}
                            </div>
                          </div>
                        )}
                      </div>

                      {/* Toggle back to schema-matched (only if there are matching credentials) */}
                      {credentialSections.schemaMatched.length > 0 && (
                        <div className="mt-3">
                          <button
                            type="button"
                            onClick={() => setShowOtherCredentials(false)}
                            className="text-sm text-primary-600 hover:text-primary-700
                            font-medium underline focus:outline-none"
                          >
                            Back to matching credentials
                          </button>
                        </div>
                      )}
                    </>
                  )}
                </div>
              </div>

              {/* Footer */}
              <div className="flex justify-end px-6 py-4 border-t">
                <button
                  type="button"
                  onClick={handleSave}
                  aria-label="Save adaptor configuration"
                  className="px-6 py-2.5 bg-primary-600 text-white
                  rounded-md font-medium hover:bg-primary-700
                  focus:outline-none focus:ring-2 focus:ring-offset-2
                  focus:ring-primary-500"
                >
                  Save
                </button>
              </div>
            </DialogPanel>
          </div>
        </div>
      </Dialog>
    </>
  );
}
