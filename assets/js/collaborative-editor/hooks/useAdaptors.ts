/**
 * React hooks for adaptor management
 *
 * Provides convenient hooks for components to access adaptor functionality
 * from the SessionProvider context using the useSyncExternalStore pattern.
 */

import { useMemo, useSyncExternalStore } from "react";

import { useSession } from "../contexts/SessionProvider";
import type { Adaptor, AdaptorState } from "../types/adaptor";

function defaultSelector(state: AdaptorState): Adaptor[] {
  return state.adaptors;
}

export function useAdaptors(): Adaptor[];
export function useAdaptors<T>(
  selector: (state: AdaptorState) => T,
  deps?: React.DependencyList
): T;

export function useAdaptors<T = Adaptor[]>(
  selector: (state: AdaptorState) => T = defaultSelector as (
    state: AdaptorState
  ) => T,
  deps: React.DependencyList = []
): T {
  const { adaptorStore } = useSession();

  const getSnapshot = useMemo(() => {
    return adaptorStore.withSelector(selector);
  }, [adaptorStore, selector, ...deps]);

  return useSyncExternalStore(adaptorStore.subscribe, getSnapshot);
}
/**
 * Hook to get loading state
 */
export const useAdaptorsLoading = (): boolean => {
  const { adaptorStore } = useSession();

  const selector = adaptorStore.withSelector(state => state.isLoading);

  return useSyncExternalStore(adaptorStore.subscribe, selector, selector);
};

/**
 * Hook to get error state
 */
export const useAdaptorsError = (): string | null => {
  const { adaptorStore } = useSession();

  const selector = adaptorStore.withSelector(state => state.error);

  return useSyncExternalStore(adaptorStore.subscribe, selector, selector);
};

/**
 * Hook to get adaptor commands for triggering actions
 */
export const useAdaptorCommands = () => {
  const { adaptorStore } = useSession();

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
  const { adaptorStore } = useSession();

  const selector = adaptorStore.withSelector(
    state => state.adaptors.find(adaptor => adaptor.name === name) || null
  );

  return useSyncExternalStore(adaptorStore.subscribe, selector, selector);
};
