import { useStore } from "@tanstack/react-form";
import { useCallback, useEffect, useMemo, useState } from "react";

import { useAppForm } from "#/collaborative-editor/components/form";
import { useAdaptors } from "#/collaborative-editor/hooks/useAdaptors";
import { useCredentials } from "#/collaborative-editor/hooks/useCredentials";
import { useWorkflowActions } from "#/collaborative-editor/hooks/useWorkflow";
import { useWatchFields } from "#/collaborative-editor/stores/common";
import { JobSchema } from "#/collaborative-editor/types/job";
import type { Workflow } from "#/collaborative-editor/types/workflow";

import { useJobDeleteValidation } from "../../hooks/useJobDeleteValidation";
import { usePermissions } from "../../hooks/useSessionContext";
import { notifications } from "../../lib/notifications";
import { AlertDialog } from "../AlertDialog";
import { Button } from "../Button";
import { createZodValidator } from "../form/createZodValidator";
import { Tooltip } from "../Tooltip";

interface JobInspectorProps {
  job: Workflow.Job;
  renderFooter?: (buttons: React.ReactNode) => void;
}

/**
 * Resolves an adaptor specifier into its package name and version
 * @param adaptor - Full NPM package string like "@openfn/language-common@1.4.3"
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

function extractAdaptorName(str: string): string | null {
  const match = str.match(/language-(.+)$/);
  return match ? match[1] || null : null;
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

const useCredentialOptions = () => {
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
        return { project_credential_id: null, keychain_credential_id: null };
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
};

export function JobInspector({ job, renderFooter }: JobInspectorProps) {
  const { updateJob, removeJobAndClearSelection } = useWorkflowActions();
  const { credentialOptions, resolveCredentialId } = useCredentialOptions();

  // Delete button state and validation
  const permissions = usePermissions();
  const validation = useJobDeleteValidation(job.id);
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  // Parse initial adaptor value to get separate package and version
  const initialAdaptor = job.adaptor || "@openfn/language-common@latest";
  const { package: initialAdaptorPackage } = resolveAdaptor(initialAdaptor);

  // Determine initial credential_id for the dropdown
  const initialCredentialId =
    job.project_credential_id || job.keychain_credential_id || null;

  const defaultValues = useMemo(
    () => ({
      id: job.id,
      name: job.name,
      body: job.body,
      adaptor: initialAdaptor,
      // Virtual fields for UI only
      adaptor_package: initialAdaptorPackage,
      credential_id: initialCredentialId,
      delete: job.delete || false,

      project_credential_id: job.project_credential_id,
      keychain_credential_id: job.keychain_credential_id,
    }),
    [job, initialAdaptor, initialAdaptorPackage, initialCredentialId]
  );

  const form = useAppForm(
    {
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
    },
    `jobs.${job.id}` // Server validation automatically filtered to this job
  );

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

  // Subscribe to changes for the adaptor package
  const adaptorPackage = useStore(
    form.store,
    state => state.values.adaptor_package
  );

  const { adaptorVersionOptions, adaptorPackageOptions, getLatestVersion } =
    useAdaptorVersionOptions(adaptorPackage);

  useEffect(() => {
    if (!adaptorPackage) return;
    const latestVersion = getLatestVersion(adaptorPackage);
    if (latestVersion) {
      form.setFieldValue("adaptor", latestVersion);
      updateJob(job.id, form.state.values);
    }
  }, [adaptorPackage, getLatestVersion, form, job.id, updateJob]);

  // Delete handler
  const handleDelete = useCallback(async () => {
    setIsDeleting(true);
    try {
      removeJobAndClearSelection(job.id);
      // Success - Y.Doc sync provides immediate visual feedback
      // No success toast needed - job disappears from diagram
      setIsDeleteDialogOpen(false);
    } catch (error) {
      console.error("Delete failed:", error);

      // Show error toast to inform user
      notifications.alert({
        title: "Failed to delete job",
        description:
          error instanceof Error
            ? error.message
            : "An unexpected error occurred. Please try again.",
      });

      // Keep dialog open so user can retry
    } finally {
      setIsDeleting(false);
    }
  }, [job.id, removeJobAndClearSelection]);

  // Pass delete button to parent footer via renderFooter callback
  useEffect(() => {
    if (renderFooter && permissions?.can_edit_workflow) {
      const deleteButton = (
        <Tooltip
          content={validation.disableReason || "Delete this job"}
          side="top"
        >
          <span className="inline-block">
            <Button
              variant="danger"
              onClick={() => setIsDeleteDialogOpen(true)}
              disabled={isDeleting || !validation.canDelete}
            >
              {isDeleting ? "Deleting..." : "Delete"}
            </Button>
          </span>
        </Tooltip>
      );
      renderFooter(deleteButton);
    }

    // Cleanup: remove button when component unmounts
    return () => {
      if (renderFooter) {
        renderFooter(null);
      }
    };
  }, [
    renderFooter,
    permissions,
    validation.disableReason,
    validation.canDelete,
    isDeleting,
  ]);

  return (
    <div data-testid="job-inspector">
      <div className="-mt-6 md:grid md:grid-cols-6 md:gap-4 p-2 @container">
        <div className="col-span-6">
          <form.AppField name="name">
            {field => <field.TextField label="Name" />}
          </form.AppField>
        </div>

        {/* Adaptor Package Dropdown */}
        <div className="col-span-6">
          <form.AppField name="adaptor_package">
            {field => (
              <field.SelectField
                label="Adaptor"
                options={adaptorPackageOptions}
              />
            )}
          </form.AppField>
        </div>

        {/* Adaptor Version Dropdown - dependent on package selection */}
        <div className="col-span-6">
          <form.AppField name="adaptor">
            {field => {
              return (
                <field.SelectField
                  label="Version"
                  options={adaptorVersionOptions}
                />
              );
            }}
          </form.AppField>
        </div>

        <div className="col-span-6">
          <form.AppField
            name="credential_id"
            listeners={{
              onChange: ({ value, fieldApi }) => {
                const resolved = resolveCredentialId(value);
                fieldApi.form.setFieldValue(
                  "project_credential_id",
                  resolved.project_credential_id
                );
                fieldApi.form.setFieldValue(
                  "keychain_credential_id",
                  resolved.keychain_credential_id
                );
                // Manually trigger updateJob to persist credentials to Y.Doc
                updateJob(job.id, {
                  project_credential_id: resolved.project_credential_id,
                  keychain_credential_id: resolved.keychain_credential_id,
                });
              },
            }}
          >
            {field => {
              return (
                <field.SelectField
                  label="Credential"
                  placeholder=" "
                  options={credentialOptions}
                />
              );
            }}
          </form.AppField>
        </div>
      </div>

      <AlertDialog
        isOpen={isDeleteDialogOpen}
        onClose={() => !isDeleting && setIsDeleteDialogOpen(false)}
        onConfirm={handleDelete}
        title="Delete Job?"
        description={
          `This will permanently remove "${job.name}" from the ` +
          `workflow. This action cannot be undone.`
        }
        confirmLabel={isDeleting ? "Deleting..." : "Delete Job"}
        cancelLabel="Cancel"
        variant="danger"
      />
    </div>
  );
}
