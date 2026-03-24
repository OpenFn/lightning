/**
 * React hooks for metadata management
 *
 * Provides hooks to automatically fetch and subscribe to metadata
 * for the currently selected job. Metadata is fetched when the job's
 * adaptor or credential changes.
 */

import { useContext, useEffect, useSyncExternalStore } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { MetadataStoreInstance } from '../stores/createMetadataStore';
import type { Metadata } from '../types/metadata';

import { useCurrentJob } from './useWorkflow';

/**
 * Main hook for accessing the MetadataStore instance
 * Handles context access and error handling once
 */
const useMetadataStore = (): MetadataStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useMetadataStore must be used within a StoreProvider');
  }
  return context.metadataStore;
};

/**
 * Hook to fetch and subscribe to metadata for the currently selected job
 *
 * Auto-fetches metadata when:
 * - Job is selected
 * - Adaptor changes
 * - Credential changes
 *
 * Returns metadata state with loading and error indicators.
 */
export const useMetadata = () => {
  const metadataStore = useMetadataStore();
  const { job } = useCurrentJob();

  // Subscribe to metadata state for the current job
  const metadata = useSyncExternalStore(
    metadataStore.subscribe,
    metadataStore.withSelector(() =>
      job ? metadataStore.getMetadataForJob(job.id) : null
    )
  );

  const isLoading = useSyncExternalStore(
    metadataStore.subscribe,
    metadataStore.withSelector(() =>
      job ? metadataStore.isLoadingForJob(job.id) : false
    )
  );

  const error = useSyncExternalStore(
    metadataStore.subscribe,
    metadataStore.withSelector(() =>
      job ? metadataStore.getErrorForJob(job.id) : null
    )
  );

  // Auto-fetch metadata when job selection or adaptor/credential changes
  useEffect(() => {
    if (!job) return;

    const { id, adaptor, project_credential_id, keychain_credential_id } = job;
    const credentialId =
      project_credential_id || keychain_credential_id || null;

    if (adaptor) {
      void metadataStore.requestMetadata(id, adaptor, credentialId);
    }
  }, [
    job?.id,
    job?.adaptor,
    job?.project_credential_id,
    job?.keychain_credential_id,
    metadataStore,
  ]);

  // Provide a refetch function for manual refresh
  const refetch = job
    ? () => {
        const credentialId =
          job.project_credential_id || job.keychain_credential_id || null;
        return metadataStore.requestMetadata(job.id, job.adaptor, credentialId);
      }
    : undefined;

  return {
    metadata,
    isLoading,
    error,
    refetch,
  };
};

/**
 * Hook to get metadata for a specific job ID
 * Useful when you need to access metadata for a job that isn't currently selected
 */
export const useMetadataForJob = (jobId: string | null): Metadata | null => {
  const metadataStore = useMetadataStore();

  return useSyncExternalStore(
    metadataStore.subscribe,
    metadataStore.withSelector(() =>
      jobId ? metadataStore.getMetadataForJob(jobId) : null
    )
  );
};

/**
 * Hook to get metadata commands for manual control
 */
export const useMetadataCommands = () => {
  const metadataStore = useMetadataStore();

  return {
    requestMetadata: metadataStore.requestMetadata,
    clearMetadata: metadataStore.clearMetadata,
    clearAllMetadata: metadataStore.clearAllMetadata,
  };
};
