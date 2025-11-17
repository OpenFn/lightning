/**
 * React hooks for workflow execution history management
 *
 * Provides convenient hooks for components to access history functionality
 * from the StoreProvider context using the useSyncExternalStore pattern.
 */

import {
  useSyncExternalStore,
  useContext,
  useMemo,
  useEffect,
  useId,
} from 'react';

import _logger from '#/utils/logger';
import type { RunInfo } from '#/workflow-store/store';

import { StoreContext } from '../contexts/StoreProvider';
import type {
  HistoryStore,
  WorkflowRunHistory,
  RunStepsData,
} from '../types/history';
import { transformToRunInfo } from '../utils/runStepsTransformer';

import { useWorkflowState } from './useWorkflow';

const logger = _logger.ns('useHistory').seal();

/**
 * Main hook for accessing the HistoryStore instance
 * Handles context access and error handling once
 *
 * TypeScript note: We assert the return type explicitly to avoid
 * propagating the error type from the throw statement through the
 * entire call chain. This is safe because the throw only happens
 * during development/testing when the hook is used incorrectly.
 */
const useHistoryStore = (): HistoryStore => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useHistoryStore must be used within a StoreProvider');
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
 *
 * TypeScript note: We use useMemo to wrap the return object,
 * which prevents error type propagation from useHistoryStore's
 * throw statement (following the same pattern as useWorkflowActions).
 */
export const useHistoryCommands = () => {
  const historyStore = useHistoryStore();

  // These are already stable function references from the store
  // useMemo prevents error type propagation through the return object
  return useMemo(
    () => ({
      requestHistory: historyStore.requestHistory,
      requestRunSteps: historyStore.requestRunSteps,
      getRunSteps: historyStore.getRunSteps,
      clearError: historyStore.clearError,
    }),
    [historyStore]
  );
};

/**
 * Hook to get run steps for a specific run with automatic subscription
 * management
 *
 * This hook:
 * - Subscribes to run steps on mount
 * - Fetches run steps if not cached
 * - Automatically refetches when run updates (via store invalidation)
 * - Unsubscribes and cleans up on unmount
 * - Transforms backend data to RunInfo format for visualization
 *
 * @param runId - The run ID to get steps for (or null for no selection)
 * @returns RunInfo object for visualization, or null if no run selected or
 * loading
 *
 * @example
 * function MyComponent({ selectedRunId }) {
 *   const runSteps = useRunSteps(selectedRunId);
 *
 *   if (!runSteps) return <Spinner />;
 *
 *   return <RunVisualization steps={runSteps} />;
 * }
 */
export const useRunSteps = (runId: string | null): RunInfo | null => {
  const historyStore = useHistoryStore();
  const workflow = useWorkflowState(state => state.workflow);
  const workflowId = workflow?.id || '';

  // Generate stable component ID for subscription tracking
  // React's useId provides a stable identifier per component instance
  const componentId = useId();

  // Subscribe to run steps with automatic cleanup
  useEffect(() => {
    if (!runId) return;

    logger.debug('useRunSteps: Subscribing', { runId, componentId });
    historyStore.subscribeToRunSteps(runId, componentId);

    return () => {
      logger.debug('useRunSteps: Unsubscribing', { runId, componentId });
      historyStore.unsubscribeFromRunSteps(runId, componentId);
    };
  }, [runId, componentId, historyStore]);

  // Get raw data from store with subscription
  const selectRunSteps = useMemo(
    () =>
      historyStore.withSelector((state): RunStepsData | null => {
        if (!runId) return null;
        return state.runStepsCache[runId] || null;
      }),
    [historyStore, runId]
  );

  const rawRunSteps = useSyncExternalStore(
    historyStore.subscribe,
    selectRunSteps
  );

  // Transform to RunInfo format for visualization
  return useMemo(() => {
    if (!rawRunSteps || !workflowId) return null;
    return transformToRunInfo(rawRunSteps, workflowId);
  }, [rawRunSteps, workflowId]);
};
