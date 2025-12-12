import { useStore } from '@tanstack/react-form';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { useAppForm } from '#/collaborative-editor/components/form';
import { useCredentialModal } from '#/collaborative-editor/contexts/CredentialModalContext';
import { useProjectAdaptors } from '#/collaborative-editor/hooks/useAdaptors';
import {
  useCredentials,
  useCredentialsCommands,
} from '#/collaborative-editor/hooks/useCredentials';
import {
  useWorkflowActions,
  useWorkflowReadOnly,
} from '#/collaborative-editor/hooks/useWorkflow';
import { useWatchFields } from '#/collaborative-editor/stores/common';
import { JobSchema } from '#/collaborative-editor/types/job';
import type { Workflow } from '#/collaborative-editor/types/workflow';

import { AdaptorDisplay } from '../AdaptorDisplay';
import { AdaptorSelectionModal } from '../AdaptorSelectionModal';
import { ConfigureAdaptorModal } from '../ConfigureAdaptorModal';
import { createZodValidator } from '../form/createZodValidator';
import { Tooltip } from '../Tooltip';

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
  const { isReadOnly } = useWorkflowReadOnly();

  // Modal state for adaptor configuration
  const [isConfigureModalOpen, setIsConfigureModalOpen] = useState(false);
  const [isAdaptorPickerOpen, setIsAdaptorPickerOpen] = useState(false);
  // Track if adaptor picker was opened from configure modal (to return there on close)
  const [adaptorPickerFromConfigure, setAdaptorPickerFromConfigure] =
    useState(false);

  // Credential modal is managed by the context
  const { openCredentialModal, onModalClose, onCredentialSaved } =
    useCredentialModal();

  // Parse initial adaptor value
  const initialAdaptor = job.adaptor || '@openfn/language-common@latest';
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

  // Y.Doc sync
  useWatchFields(
    job,
    changedFields => {
      Object.entries(changedFields).forEach(([key, value]) => {
        if (key in form.state.values) {
          if (key === 'adaptor' && value) {
            const { package: adaptorPackage } = resolveAdaptor(value);
            if (adaptorPackage) {
              form.setFieldValue('adaptor_package', adaptorPackage);
            }
          }
          form.setFieldValue(key as keyof typeof form.state.values, value);

          // Also update the derived credential_id field when credential fields change
          if (
            key === 'project_credential_id' ||
            key === 'keychain_credential_id'
          ) {
            const newCredentialId =
              changedFields.project_credential_id ??
              job.project_credential_id ??
              changedFields.keychain_credential_id ??
              job.keychain_credential_id ??
              null;
            form.setFieldValue('credential_id', newCredentialId);
          }
        }
      });
    },
    ['name', 'adaptor', 'project_credential_id', 'keychain_credential_id']
  );

  // Register callback to reopen configure modal when credential modal closes (only when opened from inspector)
  useEffect(() => {
    return onModalClose('inspector', () => {
      setIsConfigureModalOpen(true);
    });
  }, [onModalClose]);

  // Register callback to handle credential saved - update form and job (only when opened from inspector)
  useEffect(() => {
    return onCredentialSaved('inspector', payload => {
      const { credential, is_project_credential } = payload;
      const credentialId = is_project_credential
        ? credential.project_credential_id
        : credential.id;

      // Select the credential immediately - we have the data from the server
      form.setFieldValue('credential_id', credentialId);

      if (is_project_credential) {
        form.setFieldValue('project_credential_id', credentialId);
        form.setFieldValue('keychain_credential_id', null);
      } else {
        form.setFieldValue('keychain_credential_id', credentialId);
        form.setFieldValue('project_credential_id', null);
      }

      // Persist to Y.Doc
      updateJob(job.id, {
        project_credential_id: is_project_credential ? credentialId : null,
        keychain_credential_id: is_project_credential ? null : credentialId,
      });

      // Reload credentials in the background so the list is up to date
      void requestCredentials();
    });
  }, [onCredentialSaved, form, job.id, updateJob, requestCredentials]);

  // Get current adaptor and credential for display
  const currentAdaptor = useStore(form.store, state => state.values.adaptor);
  const currentCredentialId = useStore(
    form.store,
    state => state.values.credential_id
  );

  // Called from ConfigureAdaptorModal "Change" button
  const handleOpenAdaptorPickerFromConfigure = useCallback(() => {
    setIsConfigureModalOpen(false);
    setIsAdaptorPickerOpen(true);
    setAdaptorPickerFromConfigure(true);
  }, []);

  // Called from AdaptorDisplay (direct open)
  const handleOpenAdaptorPickerDirect = useCallback(() => {
    setIsAdaptorPickerOpen(true);
    setAdaptorPickerFromConfigure(false);
  }, []);

  // Handle opening credential modal from ConfigureAdaptorModal
  const handleOpenCredentialModal = useCallback(
    (adaptorName: string, credentialId?: string) => {
      setIsConfigureModalOpen(false);
      openCredentialModal(adaptorName, credentialId, 'inspector');
    },
    [openCredentialModal]
  );

  // Handle adaptor selection from picker
  const handleAdaptorSelect = useCallback(
    (adaptorName: string) => {
      // Update the adaptor package in form
      const packageMatch = adaptorName.match(/(.+?)(@|$)/);
      const newPackage = packageMatch ? packageMatch[1] : adaptorName;
      form.setFieldValue('adaptor_package', newPackage || null);

      // Set version to "latest" by default when picking an adaptor
      const fullAdaptor = `${newPackage}@latest`;
      form.setFieldValue('adaptor', fullAdaptor);

      // Close adaptor picker and always open configure modal
      setIsAdaptorPickerOpen(false);
      setAdaptorPickerFromConfigure(false);
      setIsConfigureModalOpen(true);
    },
    [form]
  );

  // Handler for adaptor changes - immediately syncs to Y.Doc
  const handleAdaptorChange = useCallback(
    (adaptorPackage: string) => {
      // Get current version from form
      const currentAdaptorValue = form.getFieldValue('adaptor') as string;
      const { version: currentVersion } = resolveAdaptor(currentAdaptorValue);

      // Build new adaptor string with current version
      const newAdaptor = `${adaptorPackage}@${currentVersion || 'latest'}`;

      // Update form state
      form.setFieldValue('adaptor_package', adaptorPackage);
      form.setFieldValue('adaptor', newAdaptor);

      // Persist to Y.Doc
      updateJob(job.id, { adaptor: newAdaptor });
    },
    [form, job.id, updateJob]
  );

  // Handler for version changes - immediately syncs to Y.Doc
  const handleVersionChange = useCallback(
    (version: string) => {
      // Get current adaptor package from form
      const adaptorPackage = form.getFieldValue('adaptor_package') as
        | string
        | null;

      // Build new adaptor string with new version
      const newAdaptor = `${adaptorPackage ?? '@openfn/language-common'}@${version}`;

      // Update form state
      form.setFieldValue('adaptor', newAdaptor);

      // Persist to Y.Doc
      updateJob(job.id, { adaptor: newAdaptor });
    },
    [form, job.id, updateJob]
  );

  // Handler for credential changes - immediately syncs to Y.Doc
  const handleCredentialChange = useCallback(
    (credentialId: string | null) => {
      // Build the Y.Doc updates
      const jobUpdates: {
        project_credential_id: string | null;
        keychain_credential_id: string | null;
      } = {
        project_credential_id: null,
        keychain_credential_id: null,
      };

      // Update credential if selected
      if (credentialId) {
        // Determine if it's a project or keychain credential
        const isProjectCredential = projectCredentials.some(
          c => c.project_credential_id === credentialId
        );

        const isKeychainCredential = keychainCredentials.some(
          c => c.id === credentialId
        );

        if (isProjectCredential) {
          jobUpdates.project_credential_id = credentialId;
        } else if (isKeychainCredential) {
          jobUpdates.keychain_credential_id = credentialId;
        }
      }

      // Update form state
      form.setFieldValue('credential_id', credentialId);
      form.setFieldValue(
        'project_credential_id',
        jobUpdates.project_credential_id
      );
      form.setFieldValue(
        'keychain_credential_id',
        jobUpdates.keychain_credential_id
      );

      // Persist to Y.Doc
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
          {field => <field.TextField label="Job Name" disabled={isReadOnly} />}
        </form.AppField>
      </div>

      {/* Adaptor Section */}
      <div className="col-span-6">
        <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-2">
          Adaptor
          <Tooltip
            content="Choose an adaptor to perform operations (via helper functions) in a specific application. Pick 'http' for generic REST APIs or the 'common' adaptor if this job only performs data manipulation."
            side="top"
          >
            <span
              className="hero-information-circle h-4 w-4 text-gray-400"
              aria-label="Information"
              role="img"
            />
          </Tooltip>
        </label>
        <AdaptorDisplay
          adaptor={currentAdaptor}
          credentialId={currentCredentialId}
          onEdit={() => setIsConfigureModalOpen(true)}
          onChangeAdaptor={handleOpenAdaptorPickerDirect}
          size="sm"
          isReadOnly={isReadOnly}
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
        onAdaptorChange={handleAdaptorChange}
        onVersionChange={handleVersionChange}
        onCredentialChange={handleCredentialChange}
        onOpenAdaptorPicker={handleOpenAdaptorPickerFromConfigure}
        onOpenCredentialModal={handleOpenCredentialModal}
        currentAdaptor={
          resolveAdaptor(currentAdaptor).package || '@openfn/language-common'
        }
        currentVersion={resolveAdaptor(currentAdaptor).version || 'latest'}
        currentCredentialId={currentCredentialId}
        allAdaptors={allAdaptors}
      />

      {/* Adaptor Selection Modal (opened from ConfigureAdaptorModal) */}
      <AdaptorSelectionModal
        isOpen={isAdaptorPickerOpen}
        onClose={() => {
          setIsAdaptorPickerOpen(false);
          // Only return to configure modal if opened from there
          if (adaptorPickerFromConfigure) {
            setIsConfigureModalOpen(true);
          }
          setAdaptorPickerFromConfigure(false);
        }}
        onSelect={handleAdaptorSelect}
        projectAdaptors={projectAdaptors}
      />
    </div>
  );
}
