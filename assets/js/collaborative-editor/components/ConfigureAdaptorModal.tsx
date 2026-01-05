import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { useEffect, useMemo, useRef, useState } from 'react';

import {
  useCredentialQueries,
  useCredentials,
} from '#/collaborative-editor/hooks/useCredentials';
import { useKeyboardShortcut } from '#/collaborative-editor/keyboard';
import { useUser } from '#/collaborative-editor/hooks/useSessionContext';
import type { Adaptor } from '#/collaborative-editor/types/adaptor';
import type { CredentialWithType } from '#/collaborative-editor/types/credential';
import {
  extractAdaptorDisplayName,
  extractAdaptorName,
  extractPackageName,
} from '#/collaborative-editor/utils/adaptorUtils';
import { cn } from '#/utils/cn';

import { AdaptorIcon } from './AdaptorIcon';
import { Tooltip } from './Tooltip';
import { VersionPicker } from './VersionPicker';

interface ConfigureAdaptorModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAdaptorChange: (adaptorPackage: string) => void; // Immediately sync adaptor to Y.Doc
  onVersionChange: (version: string) => void; // Immediately sync version to Y.Doc
  onCredentialChange: (credentialId: string | null) => void; // Immediately sync credential to Y.Doc
  onOpenAdaptorPicker: () => void; // Notify parent to manage modal switching to adaptor picker
  onOpenCredentialModal: (adaptorName: string, credentialId?: string) => void; // Notify parent to manage modal switching to credential modal (for create or edit)
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
  onAdaptorChange: _onAdaptorChange,
  onVersionChange,
  onCredentialChange,
  onOpenAdaptorPicker,
  onOpenCredentialModal,
  currentAdaptor,
  currentVersion,
  currentCredentialId,
  allAdaptors,
}: ConfigureAdaptorModalProps) {
  // UI state (not synced to Y.Doc)
  const [showOtherCredentials, setShowOtherCredentials] = useState(false);

  // Get current user and credentials from store
  const currentUser = useUser();
  const { projectCredentials, keychainCredentials } = useCredentials();
  const { credentialExists, getCredentialId } = useCredentialQueries();

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

  // When adaptor changes externally (from Y.Doc or adaptor picker),
  // automatically update to newest version and clear invalid credentials
  const prevAdaptorRef = useRef(currentAdaptor);

  useEffect(() => {
    if (!isOpen) return;

    const adaptorChanged = currentAdaptor !== prevAdaptorRef.current;

    if (adaptorChanged) {
      // When adaptor changes, update to newest version automatically
      const packageName = extractPackageName(currentAdaptor);
      const adaptor = allAdaptors.find(a => a.name === packageName);

      if (adaptor) {
        const sortedVersions = adaptor.versions
          .map(v => v.version)
          .filter(v => v !== 'latest')
          .sort((a, b) => {
            const aParts = a.split('.').map(Number);
            const bParts = b.split('.').map(Number);
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
          onVersionChange(sortedVersions[0]);
        }
      }

      // Clear credential if it no longer exists
      if (currentCredentialId && !credentialExists(currentCredentialId)) {
        onCredentialChange(null);
      }

      prevAdaptorRef.current = currentAdaptor;
    }
  }, [
    isOpen,
    currentAdaptor,
    currentCredentialId,
    allAdaptors,
    credentialExists,
    onVersionChange,
    onCredentialChange,
  ]);

  // Check if the adaptor requires credentials
  const adaptorNeedsCredentials = useMemo(() => {
    const adaptorName = extractAdaptorName(currentAdaptor);
    // Common adaptor doesn't require credentials
    return adaptorName !== 'common';
  }, [currentAdaptor]);

  // Filter credentials into sections
  const credentialSections = useMemo(() => {
    const adaptorName = extractAdaptorName(currentAdaptor);
    if (!adaptorName) {
      return {
        schemaMatched: [],
        universal: [],
        keychain: [],
      };
    }

    // Schema-matched project credentials (exact match or OAuth smart matching)
    const schemaMatched: CredentialWithType[] = projectCredentials
      .filter(c => {
        // Exact schema match
        if (c.schema === adaptorName) return true;

        // For HTTP adaptor, all OAuth credentials are considered matching
        // (OAuth can be used for authenticated API calls via HTTP)
        if (adaptorName === 'http' && c.schema === 'oauth') return true;

        // Smart OAuth matching: if credential is OAuth, check oauth_client_name
        if (c.schema === 'oauth' && c.oauth_client_name) {
          // Normalize both strings: lowercase, remove spaces/hyphens/underscores
          const normalizeString = (str: string) =>
            str.toLowerCase().replace(/[\s\-_]/g, '');

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
      .map(c => ({ ...c, type: 'project' as const }));

    // Universal project credentials (http and raw work with all adaptors)
    // Only show if not already in schemaMatched (avoid duplicates)
    const universal: CredentialWithType[] = projectCredentials
      .filter(c => {
        const isUniversal = c.schema === 'http' || c.schema === 'raw';
        // Only exclude if this specific credential is already in schemaMatched
        const alreadyInSchemaMatched = schemaMatched.some(
          matched => matched.id === c.id
        );
        return isUniversal && !alreadyInSchemaMatched;
      })
      .map(c => ({ ...c, type: 'project' as const }));

    // All keychain credentials (can't reliably filter by schema)
    const keychain: CredentialWithType[] = keychainCredentials.map(c => ({
      ...c,
      type: 'keychain' as const,
    }));

    return { schemaMatched, universal, keychain };
  }, [currentAdaptor, projectCredentials, keychainCredentials]);

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
      currentCredentialId &&
      (credentialSections.universal.some(
        c => getCredentialId(c) === currentCredentialId
      ) ||
        credentialSections.keychain.some(
          c => getCredentialId(c) === currentCredentialId
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
  }, [isOpen, currentAdaptor, currentCredentialId]);

  // Get version options for current adaptor
  const versionOptions = useMemo(() => {
    // Extract package name without version using utility function
    const packageName = extractPackageName(currentAdaptor);

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
      .filter(v => v !== 'latest')
      .sort((a, b) => {
        // Split version strings into parts [major, minor, patch]
        const aParts = a.split('.').map(Number);
        const bParts = b.split('.').map(Number);

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
    return ['latest', ...sortedVersions];
  }, [currentAdaptor, allAdaptors]);

  // Extract adaptor display name
  const adaptorDisplayName = useMemo(() => {
    return extractAdaptorDisplayName(currentAdaptor);
  }, [currentAdaptor]);

  // Handle "Change" button click - notify parent to switch modals
  const handleChangeClick = () => {
    onClose(); // Close ConfigureAdaptorModal
    onOpenAdaptorPicker(); // Let parent open AdaptorSelectionModal
  };

  // Open LiveView credential modal with adaptor schema (notifies parent)
  const handleCreateCredential = () => {
    const adaptorName = extractAdaptorName(currentAdaptor);
    if (adaptorName) {
      onOpenCredentialModal(adaptorName);
    }
  };

  // Open LiveView credential modal for editing (notifies parent)
  const handleEditCredential = (cred: CredentialWithType) => {
    const adaptorName = extractAdaptorName(currentAdaptor);
    if (adaptorName && cred.type === 'project') {
      // For editing, we need the actual credential.id, not project_credential_id
      onOpenCredentialModal(adaptorName, cred.id);
    }
  };

  // Render action buttons for a credential (edit and clear)
  const renderCredentialActions = (
    cred: CredentialWithType,
    isSelected: boolean
  ) => {
    const isOwner =
      cred.type === 'project' &&
      cred.owner &&
      currentUser &&
      cred.owner.id === currentUser.id;
    const canEdit = cred.type === 'project' && isOwner;

    return (
      <div className="flex items-center gap-2 flex-shrink-0 ml-2">
        {/* Edit button - only for project credentials owned by current user */}
        {cred.type === 'project' && cred.owner && (
          <Tooltip
            content={
              canEdit
                ? 'Edit credential'
                : `This credential can only be edited by the owner: ${cred.owner.email}`
            }
            side="top"
          >
            <button
              type="button"
              onClick={e => {
                e.preventDefault();
                if (canEdit) {
                  handleEditCredential(cred);
                }
              }}
              disabled={!canEdit}
              className={cn(
                'focus:outline-none',
                canEdit
                  ? 'text-gray-400 hover:text-gray-600 cursor-pointer'
                  : 'text-gray-300 cursor-not-allowed opacity-50'
              )}
              aria-label={
                canEdit
                  ? 'Edit credential'
                  : `Cannot edit credential owned by ${cred.owner.email}`
              }
            >
              <span
                className="hero-pencil-square h-5 w-5"
                aria-hidden="true"
                role="img"
              />
            </button>
          </Tooltip>
        )}

        {/* Clear selection button - only shown when selected */}
        {isSelected && (
          <button
            type="button"
            onClick={e => {
              e.preventDefault();
              onCredentialChange(null);
            }}
            className="text-gray-400 hover:text-gray-600
              focus:outline-none"
            aria-label="Clear credential selection"
          >
            <span
              className="hero-x-mark h-5 w-5"
              aria-hidden="true"
              role="img"
            />
          </button>
        )}
      </div>
    );
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
                <DialogTitle className="text-lg font-bold leading-5 text-zinc-800">
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
                      <Tooltip
                        content="Choose an adaptor to perform operations (via helper functions) in a specific application. Pick 'http' for generic REST APIs or the 'common' adaptor if this job only performs data manipulation."
                        side="top"
                      >
                        <span
                          className="hero-information-circle h-4 w-4
                          text-gray-400"
                          aria-label="Information"
                          role="img"
                        />
                      </Tooltip>
                    </label>
                    <div
                      className="flex items-center justify-between p-3
                      border border-gray-200 rounded-md bg-white"
                    >
                      <div className="flex items-center gap-2 min-w-0 flex-1">
                        <AdaptorIcon name={currentAdaptor} size="md" />
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
                      selectedVersion={currentVersion}
                      onVersionChange={onVersionChange}
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
                      <Tooltip
                        content="If the system you're working with requires authentication, choose a credential with login details (secrets) that will allow this job to connect. If you're not connecting to an external system you don't need a credential."
                        side="top"
                      >
                        <span
                          className="hero-information-circle h-4 w-4
                          text-gray-400"
                          aria-label="Information"
                          role="img"
                        />
                      </Tooltip>
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
                          const isSelected = currentCredentialId === credId;
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
                                onChange={() => onCredentialChange(credId)}
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
                                {cred.type === 'project' && cred.owner && (
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
                              {renderCredentialActions(cred, isSelected)}
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
                                  currentCredentialId === credId;
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
                                      checked={currentCredentialId === credId}
                                      onChange={() =>
                                        onCredentialChange(credId)
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
                                      {cred.type === 'project' &&
                                        cred.owner && (
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
                                    {renderCredentialActions(cred, isSelected)}
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
                                  currentCredentialId === credId;
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
                                        onCredentialChange(credId)
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
                                    {renderCredentialActions(cred, isSelected)}
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
                  onClick={onClose}
                  aria-label="Close modal"
                  className="rounded-md text-sm font-semibold shadow-xs px-3 py-2
                  bg-primary-600 hover:bg-primary-500 text-white
                  focus-visible:outline-2 focus-visible:outline-offset-2
                  focus-visible:outline-primary-600"
                >
                  Close
                </button>
              </div>
            </DialogPanel>
          </div>
        </div>
      </Dialog>
    </>
  );
}
