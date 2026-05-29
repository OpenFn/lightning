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
import type { Workflow } from '../types/workflow';
import { extractPackageName } from '../utils/adaptorUtils';

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
 * Hook to read an adaptor's square-shape icon URL from the AdaptorStore.
 *
 * Accepts a full adaptor specifier (with or without version suffix). When no
 * StoreProvider is mounted (e.g. the LiveView workflow-editor path), returns
 * `null` rather than throwing so consumers fall back to their string label.
 */
export const useAdaptorIconUrl = (
  adaptor: string | null | undefined
): string | null => {
  const context = useContext(StoreContext);
  const adaptorStore = context?.adaptorStore ?? null;

  const packageName = adaptor ? extractPackageName(adaptor) : null;

  const selectIconUrl = useMemo(() => {
    if (!adaptorStore) return () => null;
    return adaptorStore.withSelector(state => {
      if (!packageName) return null;
      const found = state.adaptors.find(a => a.name === packageName);
      return found?.icon_urls?.square ?? null;
    });
  }, [adaptorStore, packageName]);

  const noopSubscribe = useMemo(() => () => () => {}, []);

  return useSyncExternalStore(
    adaptorStore?.subscribe ?? noopSubscribe,
    selectIconUrl
  );
};

/**
 * Hook to derive the subset of the adaptor catalogue that is referenced by jobs
 * in the current Y.Doc workflow. Pure selector — the catalogue comes from
 * `request_adaptors` and the jobs come from the collaborative workflow store.
 */
export const useAdaptorsInUse = (): {
  adaptorsInUse: Adaptor[];
  allAdaptors: Adaptor[];
  isLoading: boolean;
} => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useAdaptorsInUse must be used within a StoreProvider');
  }

  const { adaptorStore, workflowStore } = context;

  const selectAdaptors = adaptorStore.withSelector(state => state.adaptors);
  const selectIsLoading = adaptorStore.withSelector(state => state.isLoading);
  const selectJobs = workflowStore.withSelector(state => state.jobs);

  const allAdaptors = useSyncExternalStore(
    adaptorStore.subscribe,
    selectAdaptors
  );
  const isLoading = useSyncExternalStore(
    adaptorStore.subscribe,
    selectIsLoading
  );
  const jobs: Workflow.Job[] = useSyncExternalStore(
    workflowStore.subscribe,
    selectJobs
  );

  const adaptorsInUse = useMemo(() => {
    if (jobs.length === 0) return [];

    const names = new Set<string>();
    for (const job of jobs) {
      if (!job.adaptor) continue;
      names.add(extractPackageName(job.adaptor));
    }

    return allAdaptors
      .filter(a => names.has(a.name))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [allAdaptors, jobs]);

  return {
    adaptorsInUse,
    allAdaptors,
    isLoading,
  };
};
