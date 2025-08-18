/**
 * React hooks for adaptor management
 *
 * Provides convenient hooks for components to access adaptor functionality
 * from the SessionProvider context using the useSyncExternalStore pattern.
 */

import { useCallback, useMemo, useSyncExternalStore } from "react";

import { useSession } from "../contexts/SessionProvider";
import type { CredentialState } from "../types/credential";

type ProjectAndKeychainCredentials = Pick<
  CredentialState,
  "projectCredentials" | "keychainCredentials"
>;

function defaultSelector(
  state: CredentialState
): ProjectAndKeychainCredentials {
  return {
    projectCredentials: state.projectCredentials,
    keychainCredentials: state.keychainCredentials,
  };
}

export function useCredentials(): ProjectAndKeychainCredentials;
export function useCredentials<T>(
  selector: (state: CredentialState) => T,
  deps?: React.DependencyList
): T;

export function useCredentials<T = ProjectAndKeychainCredentials>(
  selector: (state: CredentialState) => T = defaultSelector as (
    state: CredentialState
  ) => T,
  deps: React.DependencyList = []
): T {
  const { credentialStore } = useSession();

  const memoizedSelector = useMemo(() => {
    let lastState: CredentialState | undefined;
    let lastResult: T;

    return (state: CredentialState): T => {
      if (state !== lastState) {
        lastResult = selector(state);
        lastState = state;
      }
      return lastResult;
    };
  }, [selector, ...deps]);

  const getSnapshot = useCallback(
    () => memoizedSelector(credentialStore.getSnapshot()),
    [credentialStore, memoizedSelector]
  );

  return useSyncExternalStore(credentialStore.subscribe, getSnapshot);
}

/**
 * Hook to get error state
 */
export const useCredentialsError = (): string | null => {
  const { credentialStore } = useSession();

  const selector = credentialStore.withSelector(state => state.error);

  return useSyncExternalStore(
    credentialStore.subscribe,
    selector,
    selector // SSR snapshot
  );
};

/**
 * Hook to get adaptor commands for triggering actions
 */
export const useCredentialsCommands = () => {
  const { credentialStore } = useSession();

  return {
    requestCredentials: credentialStore.requestCredentials,
    clearError: credentialStore.clearError,
  };
};
