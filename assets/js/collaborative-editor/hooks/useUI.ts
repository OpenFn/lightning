/**
 * React hooks for UI store management
 *
 * Provides convenient hooks for components to access UI state
 * from the StoreProvider context using the useSyncExternalStore pattern.
 */

import { useContext, useSyncExternalStore } from "react";

import { StoreContext } from "../contexts/StoreProvider";
import type { UIStoreInstance } from "../stores/createUIStore";
import type { UIState } from "../types/ui";

/**
 * Main hook for accessing the UIStore instance
 * Handles context access and error handling once
 */
const useUIStore = (): UIStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error("useUIStore must be used within a StoreProvider");
  }
  return context.uiStore;
};

/**
 * Hook to get currently active panel
 * Returns null when no panel is open
 */
export const useActivePanel = (): UIState["activePanel"] => {
  const uiStore = useUIStore();

  const selectActivePanel = uiStore.withSelector(state => state.activePanel);

  return useSyncExternalStore(uiStore.subscribe, selectActivePanel);
};

/**
 * Hook to get run panel context
 * Returns null when run panel is not open
 */
export const useRunPanelContext = (): UIState["runPanelContext"] => {
  const uiStore = useUIStore();

  const selectRunPanelContext = uiStore.withSelector(
    state => state.runPanelContext
  );

  return useSyncExternalStore(uiStore.subscribe, selectRunPanelContext);
};

/**
 * Hook to get UI commands for triggering actions
 * Returns stable function references
 */
export const useUICommands = () => {
  const uiStore = useUIStore();

  // These are already stable function references from the store
  return {
    openRunPanel: uiStore.openRunPanel,
    closeRunPanel: uiStore.closeRunPanel,
  };
};

/**
 * Hook to check if run panel is open
 * Convenience helper that returns boolean
 */
export const useIsRunPanelOpen = (): boolean => {
  const uiStore = useUIStore();

  const selectIsOpen = uiStore.withSelector(state => state.runPanelOpen);

  return useSyncExternalStore(uiStore.subscribe, selectIsOpen);
};
