/**
 * React hooks for workflow execution history management
 *
 * Provides convenient hooks for components to access history functionality
 * from the StoreProvider context using the useSyncExternalStore pattern.
 */

import { useSyncExternalStore, useContext } from "react";

import { StoreContext } from "../contexts/StoreProvider";
import type { HistoryStore, WorkflowRunHistory } from "../types/history";

/**
 * Main hook for accessing the HistoryStore instance
 * Handles context access and error handling once
 */
const useHistoryStore = (): HistoryStore => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error("useHistoryStore must be used within a StoreProvider");
  }
  return context.historyStore;
};

/**
 * Hook to get workflow execution history
 * Returns referentially stable array that only changes when history
 * actually changes
 */
export const useHistory = (): WorkflowRunHistory => {
  const historyStore = useHistoryStore();
  const selectHistory = historyStore.withSelector(state => state.history);
  return useSyncExternalStore(historyStore.subscribe, selectHistory);
};

/**
 * Hook to get loading state
 */
export const useHistoryLoading = (): boolean => {
  const historyStore = useHistoryStore();
  const selectLoading = historyStore.withSelector(state => state.isLoading);
  return useSyncExternalStore(historyStore.subscribe, selectLoading);
};

/**
 * Hook to get error state
 */
export const useHistoryError = (): string | null => {
  const historyStore = useHistoryStore();
  const selectError = historyStore.withSelector(state => state.error);
  return useSyncExternalStore(historyStore.subscribe, selectError);
};

/**
 * Hook to check if history store channel is connected
 */
export const useHistoryChannelConnected = (): boolean => {
  const historyStore = useHistoryStore();
  const selectConnected = historyStore.withSelector<boolean>(
    state => state.isChannelConnected
  );
  return useSyncExternalStore(historyStore.subscribe, selectConnected);
};

/**
 * Hook to get history commands for triggering actions
 */
export const useHistoryCommands = () => {
  const historyStore = useHistoryStore();

  // These are already stable function references from the store
  return {
    requestHistory: historyStore.requestHistory,
    clearError: historyStore.clearError,
  };
};
