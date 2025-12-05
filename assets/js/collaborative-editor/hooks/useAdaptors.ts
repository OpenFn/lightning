/**
 * React hooks for adaptor management
 *
 * Provides convenient hooks for components to access adaptor functionality
 * from the StoreProvider context using the useSyncExternalStore pattern.
 */

import { useSyncExternalStore, useContext, useMemo } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { AdaptorStoreInstance } from '../stores/createAdaptorStore';
import type { Adaptor } from '../types/adaptor';
import type { Job } from '../types/workflow';

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
 * Extracts adaptor package name from a full adaptor specifier
 * e.g., "@openfn/language-common@1.0.0" -> "@openfn/language-common"
 */
const getAdaptorPackageName = (adaptor: string | undefined): string | null => {
  if (!adaptor) return null;
  const match = adaptor.match(/^(@[^@]+)@/);
  return match ? match[1] : null;
};

/**
 * Hook to get project-specific adaptors and all adaptors
 * Returns both project adaptors and all adaptors from backend endpoint
 *
 * Project adaptors are merged from two sources:
 * 1. Backend DB (saved jobs)
 * 2. Y.Doc state (unsaved jobs in collaborative editor)
 *
 * This ensures newly added adaptors appear in projectAdaptors before saving.
 */
export const useProjectAdaptors = (): {
  projectAdaptors: Adaptor[];
  allAdaptors: Adaptor[];
  isLoading: boolean;
} => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useProjectAdaptors must be used within a StoreProvider');
  }

  const { adaptorStore, workflowStore } = context;

  // Get adaptor state from adaptor store
  const selectAdaptorData = adaptorStore.withSelector(state => ({
    backendProjectAdaptors: state.projectAdaptors || [],
    allAdaptors: state.adaptors,
    isLoading: state.isLoading,
  }));

  const adaptorData = useSyncExternalStore(
    adaptorStore.subscribe,
    selectAdaptorData
  );

  // Get jobs from workflow store (Y.Doc state)
  const selectJobs = workflowStore.withSelector(state => state.jobs);
  const jobs: Job[] = useSyncExternalStore(workflowStore.subscribe, selectJobs);

  // Merge backend project adaptors with Y.Doc job adaptors
  const projectAdaptors = useMemo(() => {
    const { backendProjectAdaptors, allAdaptors } = adaptorData;

    // Get adaptor names already in backend list
    const backendAdaptorNames = new Set(
      backendProjectAdaptors.map(a => a.name)
    );

    // Find adaptors used in Y.Doc jobs that aren't in backend list
    const ydocAdaptorNames = new Set<string>();
    for (const job of jobs) {
      const packageName = getAdaptorPackageName(job.adaptor);
      if (packageName && !backendAdaptorNames.has(packageName)) {
        ydocAdaptorNames.add(packageName);
      }
    }

    // If no new adaptors from Y.Doc, return backend list as-is
    if (ydocAdaptorNames.size === 0) {
      return backendProjectAdaptors;
    }

    // Find full adaptor objects from allAdaptors for Y.Doc adaptors
    const ydocAdaptors = allAdaptors.filter(a => ydocAdaptorNames.has(a.name));

    // Merge and sort
    return [...backendProjectAdaptors, ...ydocAdaptors].sort((a, b) =>
      a.name.localeCompare(b.name)
    );
  }, [adaptorData, jobs]);

  return {
    projectAdaptors,
    allAdaptors: adaptorData.allAdaptors,
    isLoading: adaptorData.isLoading,
  };
};
