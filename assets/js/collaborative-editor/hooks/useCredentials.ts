/**
 * React hooks for credential management
 *
 * Provides convenient hooks for components to access credential functionality
 * from the StoreProvider context using the useSyncExternalStore pattern.
 */

import { useSyncExternalStore, useContext } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { CredentialStoreInstance } from '../stores/createCredentialStore';
import type { CredentialState } from '../types/credential';

/**
 * Main hook for accessing the CredentialStore instance
 * Handles context access and error handling once
 */
const useCredentialStore = (): CredentialStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useCredentialStore must be used within a StoreProvider');
  }
  return context.credentialStore;
};

type ProjectAndKeychainCredentials = Pick<
  CredentialState,
  'projectCredentials' | 'keychainCredentials'
>;

/**
 * Hook to get project and keychain credentials
 * Returns referentially stable object that only changes when credentials actually change
 */
export const useCredentials = (): ProjectAndKeychainCredentials => {
  const credentialStore = useCredentialStore();

  const selectCredentials = credentialStore.withSelector(state => ({
    projectCredentials: state.projectCredentials,
    keychainCredentials: state.keychainCredentials,
  }));

  return useSyncExternalStore(credentialStore.subscribe, selectCredentials);
};

/**
 * Hook to get error state
 */
export const useCredentialsError = (): string | null => {
  const credentialStore = useCredentialStore();

  const selectError = credentialStore.withSelector(state => state.error);

  return useSyncExternalStore(credentialStore.subscribe, selectError);
};

/**
 * Hook to get credential commands for triggering actions
 */
export const useCredentialsCommands = () => {
  const credentialStore = useCredentialStore();

  // These are already stable function references from the store
  return {
    requestCredentials: credentialStore.requestCredentials,
    clearError: credentialStore.clearError,
  };
};

/**
 * Hook to get credential query utilities
 * These are stable function references for looking up credentials
 */
export const useCredentialQueries = () => {
  const credentialStore = useCredentialStore();

  // These are already stable function references from the store
  return {
    findCredentialById: credentialStore.findCredentialById,
    credentialExists: credentialStore.credentialExists,
    getCredentialId: credentialStore.getCredentialId,
  };
};
