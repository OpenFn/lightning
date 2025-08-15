/**
 * React hooks for adaptor management
 *
 * Provides convenient hooks for components to access adaptor functionality
 * from the SessionProvider context using the useSyncExternalStore pattern.
 */

import { useSyncExternalStore } from "react";
import { useSession } from "../contexts/SessionProvider";
import type { Adaptor, AdaptorState } from "../types/adaptor";

/**
 * Hook to access the full adaptor state
 * Uses useSyncExternalStore for optimal performance and referential stability
 */
export const useAdaptorState = (): AdaptorState | null => {
  const { adaptorStore } = useSession();

  return useSyncExternalStore(
    adaptorStore?.subscribe ?? (() => () => {}),
    adaptorStore?.getSnapshot ?? (() => null),
    adaptorStore?.getSnapshot ?? (() => null), // SSR snapshot
  );
};

/**
 * Hook to get just the adaptors list
 * Automatically memoized for referential stability
 */
export const useAdaptors = () => {
  const { adaptorStore } = useSession();

  const selector = adaptorStore?.withSelector((state) => state.adaptors);

  return useSyncExternalStore(
    adaptorStore?.subscribe ?? (() => () => {}),
    selector ?? (() => []),
    selector ?? (() => []), // SSR snapshot
  );
};

/**
 * Hook to get loading state
 */
export const useAdaptorsLoading = (): boolean => {
  const { adaptorStore } = useSession();

  const selector = adaptorStore?.withSelector((state) => state.isLoading);

  return useSyncExternalStore(
    adaptorStore?.subscribe ?? (() => () => {}),
    selector ?? (() => false),
    selector ?? (() => false), // SSR snapshot
  );
};

/**
 * Hook to get error state
 */
export const useAdaptorsError = (): string | null => {
  const { adaptorStore } = useSession();

  const selector = adaptorStore?.withSelector((state) => state.error);

  return useSyncExternalStore(
    adaptorStore?.subscribe ?? (() => () => {}),
    selector ?? (() => null),
    selector ?? (() => null), // SSR snapshot
  );
};

/**
 * Hook to get adaptor commands for triggering actions
 */
export const useAdaptorCommands = () => {
  const { adaptorStore } = useSession();

  return {
    requestAdaptors: adaptorStore?.requestAdaptors ?? (() => {}),
    setAdaptors: adaptorStore?.setAdaptors ?? (() => {}),
    clearError: adaptorStore?.clearError ?? (() => {}),
  };
};

/**
 * Hook to get adaptor query functions
 */
export const useAdaptorQueries = () => {
  const { adaptorStore } = useSession();

  return {
    findAdaptorByName: adaptorStore?.findAdaptorByName ?? (() => null),
    getLatestVersion: adaptorStore?.getLatestVersion ?? (() => null),
    getVersions: adaptorStore?.getVersions ?? (() => []),
  };
};

/**
 * Hook to find a specific adaptor by name
 * Memoized for performance
 */
export const useAdaptor = (name: string): Adaptor | null => {
  const { adaptorStore } = useSession();

  const selector = adaptorStore?.withSelector(
    (state) => state.adaptors.find((adaptor) => adaptor.name === name) || null,
  );

  return useSyncExternalStore(
    adaptorStore?.subscribe ?? (() => () => {}),
    selector ?? (() => null),
    selector ?? (() => null), // SSR snapshot
  );
};

/**
 * Convenience hook that combines all adaptor functionality
 * Use this when you need multiple pieces of adaptor state/functionality
 */
export const useAdaptorManager = () => {
  const state = useAdaptorState();
  const commands = useAdaptorCommands();
  const queries = useAdaptorQueries();

  return {
    // State
    ...state,

    // Commands
    ...commands,

    // Queries
    ...queries,

    // Convenience computed properties
    hasAdaptors: state?.adaptors.length ? state.adaptors.length > 0 : false,
    isReady: state
      ? !state.isLoading && !state.error && state.adaptors.length > 0
      : false,
  };
};
