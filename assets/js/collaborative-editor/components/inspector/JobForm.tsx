import { useStore } from "@tanstack/react-form";
import { useCallback, useEffect, useMemo, useState } from "react";

import { useAppForm } from "#/collaborative-editor/components/form";
import {
  useAdaptors,
  useProjectAdaptors,
} from "#/collaborative-editor/hooks/useAdaptors";
import { useCredentials } from "#/collaborative-editor/hooks/useCredentials";
import { useWorkflowActions } from "#/collaborative-editor/hooks/useWorkflow";
import { useWatchFields } from "#/collaborative-editor/stores/common";
import { JobSchema } from "#/collaborative-editor/types/job";
import type { Workflow } from "#/collaborative-editor/types/workflow";
import {
  extractAdaptorDisplayName,
  extractAdaptorName,
} from "#/collaborative-editor/utils/adaptorUtils";

import { ConfigureAdaptorModal } from "../ConfigureAdaptorModal";
import { AdaptorSelectionModal } from "../AdaptorSelectionModal";
import { AdaptorIcon } from "../AdaptorIcon";
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

function useAdaptorVersionOptions(adaptorPackage: string | null) {
  const adaptors = useAdaptors();

  const adaptor = useMemo(() => {
    if (!adaptorPackage) return null;
    return adaptors.find(adaptor => adaptor.name === adaptorPackage) || null;
  }, [adaptorPackage, adaptors]);

  const adaptorVersionOptions = useMemo(() => {
    if (!adaptorPackage || !adaptor) return [];

    return [
      {
        value: `${adaptor.name}@latest`,
        label: `latest (≥ ${adaptor.latest})`,
      },
      ...adaptor.versions.map(({ version }) => ({
        value: `${adaptor.name}@${version}`,
        label: version,
      })),
    ];
  }, [adaptorPackage, adaptor]);

  const getLatestVersion = useCallback(
    (packageName: string) => {
      const adaptor = adaptors.find(adaptor => adaptor.name === packageName);
      if (!adaptor) return null;
      return `${adaptor.name}@${adaptor.latest}`;
    },
    [adaptors]
  );

  const adaptorPackageOptions = useMemo(() => {
    return adaptors
      .map(adaptor => {
        const label = extractAdaptorName(adaptor.name);
        if (!label) return null;
        return {
          value: adaptor.name,
          label,
        };
      })
      .filter(option => option !== null);
  }, [adaptors]);

  return { adaptorVersionOptions, adaptorPackageOptions, getLatestVersion };
}

// COMMENTED OUT (Phase 2R): Moved to ConfigureAdaptorModal in Phase 3R
/* const useCredentialOptions = () => {
  const { keychainCredentials, projectCredentials } = useCredentials();

  const credentialOptions = useMemo(() => {
    return [
      ...projectCredentials.map(credential => ({
        value: credential.project_credential_id,
        label: credential.name,
      })),
      ...keychainCredentials.map(credential => ({
        value: credential.id,
        label: credential.name,
        group: "Keychain Credentials",
      })),
    ];
  }, [projectCredentials, keychainCredentials]);

  const resolveCredentialId = useCallback(
    (credentialId: string | null) => {
      if (!credentialId) {
        return {
          project_credential_id: null,
          keychain_credential_id: null,
        };
      }

      const isProjectCredential = projectCredentials.some(
        c => c.project_credential_id === credentialId
      );
      const isKeychainCredential = keychainCredentials.some(
        c => c.id === credentialId
      );

      return {
        project_credential_id: isProjectCredential ? credentialId : null,
        keychain_credential_id: isKeychainCredential ? credentialId : null,
      };
    },
    [projectCredentials, keychainCredentials]
  );

  return useMemo(
    () => ({
      credentialOptions,
      resolveCredentialId,
    }),
    [credentialOptions, resolveCredentialId]
  );
}; */

/**
 * Pure form component for job configuration.
 * Handles all form fields, adaptor selection, credential selection.
 * Does NOT include delete functionality - that's in JobInspector.
 */
export function JobForm({ job }: JobFormProps) {
  const { updateJob } = useWorkflowActions();
  const { projectCredentials, keychainCredentials } = useCredentials();
  const { projectAdaptors, allAdaptors } = useProjectAdaptors();

  // Modal state for adaptor configuration
  const [isConfigureModalOpen, setIsConfigureModalOpen] = useState(false);
  const [isAdaptorPickerOpen, setIsAdaptorPickerOpen] = useState(false);

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

  // Adaptor package logic
  const adaptorPackage = useStore(
    form.store,
    state => state.values.adaptor_package
  );

  // COMMENTED OUT (Phase 2R): Version options moved to ConfigureAdaptorModal
  const { /* adaptorVersionOptions, */ getLatestVersion } =
    useAdaptorVersionOptions(adaptorPackage);

  useEffect(() => {
    if (!adaptorPackage) return;
    const latestVersion = getLatestVersion(adaptorPackage);
    if (latestVersion) {
      form.setFieldValue("adaptor", latestVersion);
      updateJob(job.id, form.state.values);
    }
  }, [adaptorPackage, getLatestVersion, form, job.id, updateJob]);

  // Get current adaptor display name
  const adaptorDisplayName = useMemo(() => {
    return extractAdaptorDisplayName(adaptorPackage || "");
  }, [adaptorPackage]);

  // Check if a credential is selected
  const selectedCredentialId = useStore(
    form.store,
    state => state.values.credential_id
  );
  const hasCredential = !!selectedCredentialId;

  // Handle opening adaptor picker from ConfigureAdaptorModal
  const handleOpenAdaptorPicker = useCallback(() => {
    setIsConfigureModalOpen(false);
    setIsAdaptorPickerOpen(true);
  }, []);

  // Handle adaptor selection from picker
  const handleAdaptorSelect = useCallback(
    (adaptorName: string) => {
      // Update the adaptor package in form
      const packageMatch = adaptorName.match(/(.+?)(@|$)/);
      const newPackage = packageMatch ? packageMatch[1] : adaptorName;
      form.setFieldValue("adaptor_package", newPackage || null);

      // Find the adaptor in allAdaptors to get its newest version
      const adaptor = allAdaptors.find(a => a.name === newPackage);

      // Get the newest version (first in the versions array after filtering "latest")
      const newestVersion =
        adaptor?.versions
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
          })[0] ||
        adaptor?.latest ||
        "latest";

      // Update the full adaptor string with newest version
      const fullAdaptor = `${newPackage}@${newestVersion}`;
      form.setFieldValue("adaptor", fullAdaptor);

      // Close adaptor picker and reopen configure modal
      setIsAdaptorPickerOpen(false);
      setIsConfigureModalOpen(true);
    },
    [form, allAdaptors]
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

        if (isProjectCredential) {
          jobUpdates.project_credential_id = config.credentialId;
        } else {
          // Must be a keychain credential
          jobUpdates.keychain_credential_id = config.credentialId;
        }
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
    <div className="md:grid md:grid-cols-6 md:gap-4 @container">
      {/* Job Name Field */}
      <div className="col-span-6">
        <form.AppField name="name">
          {field => <field.TextField label="Job Name" />}
        </form.AppField>
      </div>

      {/* Adaptor Section - Simplified to match design */}
      <div className="col-span-6">
        <label
          className="flex items-center gap-1 text-sm font-medium
          text-gray-700 mb-2"
        >
          Adaptor
          <span
            className="hero-information-circle h-4 w-4 text-gray-400"
            aria-label="Information"
            role="img"
          />
        </label>
        <div
          className="flex items-center justify-between gap-3 p-3 border
          border-gray-200 rounded-md bg-white"
        >
          <div className="flex items-center gap-2 min-w-0 flex-1">
            <AdaptorIcon name={adaptorPackage || ""} size="md" />
            <span className="font-medium text-gray-900 truncate">
              {adaptorDisplayName}
            </span>
          </div>
          <button
            type="button"
            onClick={() => setIsConfigureModalOpen(true)}
            className="px-3 py-1.5 border border-gray-300 bg-white rounded-md
            text-sm font-medium text-gray-700 hover:bg-gray-50
            focus:outline-none flex-shrink-0 flex items-center gap-2"
            aria-label={
              hasCredential ? "Credential connected" : "Configure adaptor"
            }
          >
            {hasCredential && (
              <span
                className="w-2 h-2 bg-green-500 rounded-full flex-shrink-0"
                aria-hidden="true"
              />
            )}
            {hasCredential ? "Connected" : "Connect"}
          </button>
        </div>
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
        currentAdaptor={adaptorPackage || "@openfn/language-common"}
        currentVersion={
          resolveAdaptor(form.state.values.adaptor).version || "latest"
        }
        currentCredentialId={form.state.values.credential_id}
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
