import { useStore } from "@tanstack/react-form";
import { useCallback, useEffect, useMemo } from "react";

import { useAppForm } from "#/collaborative-editor/components/form";
import { useAdaptors } from "#/collaborative-editor/hooks/useAdaptors";
import { useCredentials } from "#/collaborative-editor/hooks/useCredentials";
import { useWorkflowActions } from "#/collaborative-editor/hooks/useWorkflow";
import { useWatchFields } from "#/collaborative-editor/stores/common";
import { JobSchema } from "#/collaborative-editor/types/job";
import type { Workflow } from "#/collaborative-editor/types/workflow";
import { extractAdaptorName } from "#/collaborative-editor/utils/adaptorUtils";

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
};

/**
 * Pure form component for job configuration.
 * Handles all form fields, adaptor selection, credential selection.
 * Does NOT include delete functionality - that's in JobInspector.
 */
export function JobForm({ job }: JobFormProps) {
  const { updateJob } = useWorkflowActions();
  const { credentialOptions, resolveCredentialId } = useCredentialOptions();

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

  return (
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

      {/* Adaptor Version Dropdown */}
      <div className="col-span-6">
        <form.AppField name="adaptor">
          {field => (
            <field.SelectField
              label="Version"
              options={adaptorVersionOptions}
            />
          )}
        </form.AppField>
      </div>

      {/* Credential Dropdown */}
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
            },
          }}
        >
          {field => (
            <field.SelectField
              label="Credential"
              placeholder=" "
              options={credentialOptions}
            />
          )}
        </form.AppField>
      </div>
    </div>
  );
}
