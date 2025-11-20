/**
 * React hooks for adaptor management
 *
 * Provides convenient hooks for components to access adaptor functionality
 * from the StoreProvider context using the useSyncExternalStore pattern.
 */

import { useSyncExternalStore, useContext } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { AdaptorStoreInstance } from '../stores/createAdaptorStore';
import type { Adaptor } from '../types/adaptor';

/**
 * Main hook for accessing the AdaptorStore instance
 * Handles context access and error handling once
 */
const useAdaptorStore = (): AdaptorStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useAdaptorStore must be used within a StoreProvider');
  }
  return context.adaptorStore;
};

/**
 * Hook to get all adaptors
 * Returns referentially stable array that only changes when adaptors actually change
 */
export const useAdaptors = (): Adaptor[] => {
  const adaptorStore = useAdaptorStore();

  const selectAdaptors = adaptorStore.withSelector(state => state.adaptors);

  return useSyncExternalStore(adaptorStore.subscribe, selectAdaptors);
};
/**
 * Hook to get loading state
 */
export const useAdaptorsLoading = (): boolean => {
  const adaptorStore = useAdaptorStore();

  const selectLoading = adaptorStore.withSelector(state => state.isLoading);

  return useSyncExternalStore(adaptorStore.subscribe, selectLoading);
};

/**
 * Hook to get error state
 */
export const useAdaptorsError = (): string | null => {
  const adaptorStore = useAdaptorStore();

  const selectError = adaptorStore.withSelector(state => state.error);

  return useSyncExternalStore(adaptorStore.subscribe, selectError);
};

/**
 * Hook to get adaptor commands for triggering actions
 */
export const useAdaptorCommands = () => {
  const adaptorStore = useAdaptorStore();

  // These are already stable function references from the store
  return {
    requestAdaptors: adaptorStore.requestAdaptors,
    setAdaptors: adaptorStore.setAdaptors,
    clearError: adaptorStore.clearError,
  };
};

/**
 * Hook to find a specific adaptor by name
 * Memoized for performance
 */
export const useAdaptor = (name: string): Adaptor | null => {
  const adaptorStore = useAdaptorStore();

  const selectAdaptor = adaptorStore.withSelector(
    state => state.adaptors.find(adaptor => adaptor.name === name) || null
  );

  return useSyncExternalStore(adaptorStore.subscribe, selectAdaptor);
};

/**
 * Hook to get project-specific adaptors and all adaptors
 * Returns both project adaptors and all adaptors from backend endpoint
 */
export const useProjectAdaptors = (): {
  projectAdaptors: Adaptor[];
  allAdaptors: Adaptor[];
  isLoading: boolean;
} => {
  const adaptorStore = useAdaptorStore();

  const selectProjectData = adaptorStore.withSelector(state => ({
    projectAdaptors: state.projectAdaptors || [],
    allAdaptors: state.adaptors,
    isLoading: state.isLoading,
  }));

  return useSyncExternalStore(adaptorStore.subscribe, selectProjectData);
};
