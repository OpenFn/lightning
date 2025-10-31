import { useStore } from "@tanstack/react-form";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useHotkeysContext } from "react-hotkeys-hook";

import { useAppForm } from "#/collaborative-editor/components/form";
import { useLiveViewActions } from "#/collaborative-editor/contexts/LiveViewActionsContext";
import { useProjectAdaptors } from "#/collaborative-editor/hooks/useAdaptors";
import {
  useCredentials,
  useCredentialsCommands,
} from "#/collaborative-editor/hooks/useCredentials";
import { useWorkflowActions } from "#/collaborative-editor/hooks/useWorkflow";
import { useWatchFields } from "#/collaborative-editor/stores/common";
import { JobSchema } from "#/collaborative-editor/types/job";
import type { Workflow } from "#/collaborative-editor/types/workflow";

import { AdaptorDisplay } from "../AdaptorDisplay";
import { AdaptorSelectionModal } from "../AdaptorSelectionModal";
import { ConfigureAdaptorModal } from "../ConfigureAdaptorModal";
import { createZodValidator } from "../form/createZodValidator";

interface JobFormProps {
  job: Workflow.Job;
}

/**
 * Resolves an adaptor specifier into its package name and version
 * @param adaptor - Full NPM package string like
 * "@openfn/language-common@1.4.3"
 * @returns Tuple of package name and version, or null if parsing fails
 */
function resolveAdaptor(adaptor: string): {
  package: string | null;
  version: string | null;
} {
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
 * Pure form component for job configuration.
 * Handles all form fields, adaptor selection, credential selection.
 * Does NOT include delete functionality - that's in JobInspector.
 */
export function JobForm({ job }: JobFormProps) {
  const { updateJob } = useWorkflowActions();
  const { projectCredentials, keychainCredentials } = useCredentials();
  const { requestCredentials } = useCredentialsCommands();
  const { projectAdaptors, allAdaptors } = useProjectAdaptors();
  const { pushEvent, handleEvent } = useLiveViewActions();
  const { enableScope, disableScope } = useHotkeysContext();

  // Modal state for adaptor configuration
  const [isConfigureModalOpen, setIsConfigureModalOpen] = useState(false);
  const [isAdaptorPickerOpen, setIsAdaptorPickerOpen] = useState(false);
  const [isCredentialModalOpen, setIsCredentialModalOpen] = useState(false);

  // Disable panel hotkeys when credential modal is open
  useEffect(() => {
    if (isCredentialModalOpen) {
      disableScope("panel");
    } else {
      enableScope("panel");
    }
  }, [isCredentialModalOpen, enableScope, disableScope]);

  // Parse initial adaptor value
  const initialAdaptor = job.adaptor || "@openfn/language-common@latest";
  const { package: initialAdaptorPackage } = resolveAdaptor(initialAdaptor);

  // Determine initial credential_id
  const initialCredentialId =
    job.project_credential_id || job.keychain_credential_id || null;

  const defaultValues = useMemo(
    () => ({
      id: job.id,
      name: job.name,
      body: job.body,
      adaptor: initialAdaptor,
      adaptor_package: initialAdaptorPackage,
      credential_id: initialCredentialId,
      delete: job.delete || false,
      project_credential_id: job.project_credential_id,
      keychain_credential_id: job.keychain_credential_id,
    }),
    [job, initialAdaptor, initialAdaptorPackage, initialCredentialId]
  );

  const form = useAppForm({
    defaultValues,
    listeners: {
      onChange: ({ formApi }) => {
        if (job.id) {
          updateJob(job.id, formApi.state.values);
        }
      },
    },
    validators: {
      onChange: createZodValidator(JobSchema),
    },
  });

  // Y.Doc sync
  useWatchFields(
    job,
    changedFields => {
      Object.entries(changedFields).forEach(([key, value]) => {
        if (key in form.state.values) {
          if (key === "adaptor" && value) {
            const { package: adaptorPackage } = resolveAdaptor(value);
            if (adaptorPackage) {
              form.setFieldValue("adaptor_package", adaptorPackage);
            }
          }
          form.setFieldValue(key as keyof typeof form.state.values, value);
        }
      });
    },
    ["name", "adaptor", "project_credential_id", "keychain_credential_id"]
  );

  // Reset form when job changes
  useEffect(() => {
    form.reset();
  }, [job.id, form]);

  // Listen for credential modal close event to reopen configure modal
  useEffect(() => {
    const handleModalClose = () => {
      setIsCredentialModalOpen(false);
      // Reopen configure modal after a short delay to avoid flash during transition
      // Phoenix.JS dispatches the close event at ~250ms, so 200ms feels instant
      setTimeout(() => {
        setIsConfigureModalOpen(true);
      }, 200);
      // Notify server after modal is fully closed to reset state
      // 500ms accounts for: Phoenix.JS animation (250ms) + LiveView update time + buffer
      // This prevents race conditions if user quickly reopens modal
      setTimeout(() => {
        pushEvent("close_credential_modal_complete", {});
      }, 500);
    };

    const element = document.getElementById("collaborative-editor-react");
    element?.addEventListener("close_credential_modal", handleModalClose);

    return () => {
      element?.removeEventListener("close_credential_modal", handleModalClose);
    };
  }, [pushEvent]);

  // Listen for credential saved event from LiveView
  useEffect(() => {
    const cleanup = handleEvent("credential_saved", (payload: any) => {
      setIsCredentialModalOpen(false);

      const { credential, is_project_credential } = payload;
      const credentialId = is_project_credential
        ? credential.project_credential_id
        : credential.id;

      // Select the credential immediately - we have the data from the server
      form.setFieldValue("credential_id", credentialId);

      if (is_project_credential) {
        form.setFieldValue("project_credential_id", credentialId);
        form.setFieldValue("keychain_credential_id", null);
      } else {
        form.setFieldValue("keychain_credential_id", credentialId);
        form.setFieldValue("project_credential_id", null);
      }

      // Persist to Y.Doc
      updateJob(job.id, {
        project_credential_id: is_project_credential ? credentialId : null,
        keychain_credential_id: is_project_credential ? null : credentialId,
      });

      // Reload credentials in the background so the list is up to date
      void requestCredentials();

      // Reopen configure modal after a brief delay for the close animation
      setTimeout(() => {
        setIsConfigureModalOpen(true);
      }, 200);
    });

    return cleanup;
  }, [handleEvent, form, job.id, updateJob, requestCredentials]);

  // Get current adaptor and credential for display
  const currentAdaptor = useStore(form.store, state => state.values.adaptor);
  const currentCredentialId = useStore(
    form.store,
    state => state.values.credential_id
  );

  // Handle opening adaptor picker from ConfigureAdaptorModal
  const handleOpenAdaptorPicker = useCallback(() => {
    setIsConfigureModalOpen(false);
    setIsAdaptorPickerOpen(true);
  }, []);

  // Handle opening credential modal from ConfigureAdaptorModal
  const handleOpenCredentialModal = useCallback(
    (adaptorName: string) => {
      setIsConfigureModalOpen(false);
      setIsCredentialModalOpen(true);
      pushEvent("open_credential_modal", { schema: adaptorName });
    },
    [pushEvent]
  );

  // Handle adaptor selection from picker
  const handleAdaptorSelect = useCallback(
    (adaptorName: string) => {
      // Update the adaptor package in form
      const packageMatch = adaptorName.match(/(.+?)(@|$)/);
      const newPackage = packageMatch ? packageMatch[1] : adaptorName;
      form.setFieldValue("adaptor_package", newPackage || null);

      // Set version to "latest" by default when picking an adaptor
      const fullAdaptor = `${newPackage}@latest`;
      form.setFieldValue("adaptor", fullAdaptor);

      // Close adaptor picker and reopen configure modal
      setIsAdaptorPickerOpen(false);
      setIsConfigureModalOpen(true);
    },
    [form]
  );

  // Handler for configure save from modal
  const handleConfigureSave = useCallback(
    (config: {
      adaptorPackage: string;
      adaptorVersion: string;
      credentialId: string | null;
    }) => {
      // Build the Y.Doc updates (only Job schema fields)
      const jobUpdates: {
        adaptor: string;
        project_credential_id: string | null;
        keychain_credential_id: string | null;
      } = {
        adaptor: `${config.adaptorPackage}@${config.adaptorVersion}`,
        project_credential_id: null,
        keychain_credential_id: null,
      };

      // Update credential if selected
      if (config.credentialId) {
        // Determine if it's a project or keychain credential
        // Check project credentials first
        const isProjectCredential = projectCredentials.some(
          c => c.project_credential_id === config.credentialId
        );

        const isKeychainCredential = keychainCredentials.some(
          c => c.id === config.credentialId
        );

        if (isProjectCredential) {
          jobUpdates.project_credential_id = config.credentialId;
        } else if (isKeychainCredential) {
          jobUpdates.keychain_credential_id = config.credentialId;
        }
        // If neither match, leave both as null (credential might have been deleted)
      }

      // Update form state (includes UI-only fields like adaptor_package and credential_id)
      form.setFieldValue("adaptor_package", config.adaptorPackage);
      form.setFieldValue("adaptor", jobUpdates.adaptor);
      form.setFieldValue("credential_id", config.credentialId);
      form.setFieldValue(
        "project_credential_id",
        jobUpdates.project_credential_id
      );
      form.setFieldValue(
        "keychain_credential_id",
        jobUpdates.keychain_credential_id
      );

      // Persist to Y.Doc (only Job schema fields)
      updateJob(job.id, jobUpdates);
    },
    [form, job.id, projectCredentials, keychainCredentials, updateJob]
  );

  // COMMENTED OUT (Phase 2R): Credential display removed from inspector
  // Phase 3R will move this to ConfigureAdaptorModal
  // const selectedCredentialId = useStore(
  //   form.store,
  //   state => state.values.credential_id
  // );

  // const { projectCredentials, keychainCredentials } = useCredentials();

  // const selectedCredential = useMemo(() => {
  //   if (!selectedCredentialId) return null;

  //   // Check project credentials
  //   const projectCred = projectCredentials.find(
  //     c => c.project_credential_id === selectedCredentialId
  //   );
  //   if (projectCred) return { ...projectCred, type: "project" as const };

  //   // Check keychain credentials
  //   const keychainCred = keychainCredentials.find(
  //     c => c.id === selectedCredentialId
  //   );
  //   if (keychainCred) return { ...keychainCred, type: "keychain" as const };

  //   return null;
  // }, [selectedCredentialId, projectCredentials, keychainCredentials]);

  return (
    <div className="px-6 py-6 md:grid md:grid-cols-6 md:gap-4 @container">
      {/* Job Name Field */}
      <div className="col-span-6">
        <form.AppField name="name">
          {field => <field.TextField label="Job Name" />}
        </form.AppField>
      </div>

      {/* Adaptor Section */}
      <div className="col-span-6">
        <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-2">
          Adaptor
          <span
            className="hero-information-circle h-4 w-4 text-gray-400"
            aria-label="Information"
            role="img"
          />
        </label>
        <AdaptorDisplay
          adaptor={currentAdaptor}
          credentialId={currentCredentialId}
          onEdit={() => setIsConfigureModalOpen(true)}
          onChangeAdaptor={handleOpenAdaptorPicker}
          size="sm"
        />
      </div>

      {/* REMOVED: Version dropdown (Phase 2R) */}
      {/* Phase 3R will add ConfigureAdaptorModal with version selection */}

      {/* REMOVED: Credential section (Phase 2R) */}
      {/* Phase 3R will add credential selection to ConfigureAdaptorModal */}

      {/* Configure Adaptor Modal */}
      <ConfigureAdaptorModal
        isOpen={isConfigureModalOpen}
        onClose={() => setIsConfigureModalOpen(false)}
        onSave={handleConfigureSave}
        onOpenAdaptorPicker={handleOpenAdaptorPicker}
        onOpenCredentialModal={handleOpenCredentialModal}
        currentAdaptor={
          resolveAdaptor(currentAdaptor).package || "@openfn/language-common"
        }
        currentVersion={resolveAdaptor(currentAdaptor).version || "latest"}
        currentCredentialId={currentCredentialId}
        allAdaptors={allAdaptors}
      />

      {/* Adaptor Selection Modal (opened from ConfigureAdaptorModal) */}
      <AdaptorSelectionModal
        isOpen={isAdaptorPickerOpen}
        onClose={() => setIsAdaptorPickerOpen(false)}
        onSelect={handleAdaptorSelect}
        projectAdaptors={projectAdaptors}
      />
    </div>
  );
}
