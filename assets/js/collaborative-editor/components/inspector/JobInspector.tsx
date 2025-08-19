import { useStore } from "@tanstack/react-form";
import { useCallback, useEffect, useMemo } from "react";
import type { ZodSchema } from "zod";

import { useAppForm } from "#/collaborative-editor/components/form";
import { useAdaptors } from "#/collaborative-editor/hooks/useAdaptors";
import { useCredentials } from "#/collaborative-editor/hooks/useCredentials";
import { useWorkflowActions } from "#/collaborative-editor/hooks/Workflow";
import { JobSchema } from "#/collaborative-editor/types/job";
import type { Workflow } from "#/collaborative-editor/types/workflow";

interface JobInspectorProps {
  job: Workflow.Job;
}

/**
 * Creates a TanStack Form validator function using a Zod schema.
 * This approach provides full Zod validation while maintaining TanStack Form compatibility.
 *
 * @param schema - Zod schema to use for validation
 * @returns TanStack Form compatible validator function
 */
const createZodValidator = <T, S extends ZodSchema>(schema: S) => {
  return ({ value }: { value: T }) => {
    const result = schema.safeParse(value);
    if (!result.success) {
      // Convert Zod errors to TanStack Form format
      const formErrors: Record<string, string> = {};
      result.error.issues.forEach((issue: any) => {
        const path = issue.path.join(".");
        formErrors[path] = issue.message;
      });
      return { fields: formErrors };
    }
    return undefined;
  };
};

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
  const { keychainCredentials, projectCredentials, isLoading } = useCredentials(
    state => ({
      keychainCredentials: state.keychainCredentials,
      projectCredentials: state.projectCredentials,
      isLoading: state.isLoading,
    })
  );

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
      isLoading,
      resolveCredentialId,
    }),
    [credentialOptions, isLoading, resolveCredentialId]
  );
};

export function JobInspector({ job }: JobInspectorProps) {
  const { updateJob } = useWorkflowActions();
  const { credentialOptions, isLoading, resolveCredentialId } =
    useCredentialOptions();

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

  // Reset form when job changes
  useEffect(() => {
    form.reset();
  }, [job.id, form]);

  const adaptorPackage = useStore(
    form.store,
    state => state.values.adaptor_package
  );

  const { adaptorVersionOptions, adaptorPackageOptions, getLatestVersion } =
    useAdaptorVersionOptions(adaptorPackage);

  return (
    <div className="">
      <div className="-mt-6 md:grid md:grid-cols-6 md:gap-4 p-2 @container">
        <div className="col-span-6">
          <form.AppField name="name">
            {field => <field.TextField label="Name" />}
          </form.AppField>
        </div>

        {/* Adaptor Package Dropdown */}
        <div className="col-span-6">
          <form.AppField
            name="adaptor_package"
            listeners={{
              onChange: ({ value, fieldApi }) => {
                if (value) {
                  const latestVersion = getLatestVersion(value);
                  if (latestVersion) {
                    fieldApi.form.setFieldValue("adaptor", latestVersion);
                  }
                }
              },
            }}
          >
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
              },
            }}
          >
            {field => {
              return (
                <field.SelectField
                  label="Credential"
                  placeholder=" "
                  options={credentialOptions}
                  disabled={isLoading}
                />
              );
            }}
          </form.AppField>
        </div>

        {/* Display current full adaptor specifier for debugging */}
        <div className="col-span-6">
          <span className="text-xs text-gray-500 mb-1 block">
            Current Adaptor Specifier
          </span>
          <div className="bg-gray-50 p-2 rounded text-xs font-mono">
            <code className="text-gray-700">{form.state.values.adaptor}</code>
          </div>
        </div>
      </div>

      <div className="col-span-6">
        <label htmlFor="body" className="text-xs text-gray-500 mb-1 block">
          Body Preview
        </label>
        <div className="bg-gray-50 p-2 rounded text-xs font-mono max-h-32 overflow-y-auto">
          <pre className="whitespace-pre-wrap text-gray-700">
            {job.body || "// No code yet"}
          </pre>
        </div>
      </div>
    </div>
  );
}
