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
  useCallback,
} from 'react';

import _logger from '#/utils/logger';
import type { RunInfo } from '#/workflow-store/store';

import { StoreContext } from '../contexts/StoreProvider';
import type {
  HistoryStore,
  WorkflowRunHistory,
  RunStepsData,
  RunDetail,
  StepDetail,
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
      // View history commands
      requestHistory: historyStore.requestHistory,
      requestRunSteps: historyStore.requestRunSteps,
      getRunSteps: historyStore.getRunSteps,
      clearError: historyStore.clearError,
      // Active run commands
      selectStep: historyStore.selectStep,
      clearActiveRunError: historyStore.clearActiveRunError,
    }),
    [historyStore]
  );
};

/**
 * Hook to follow (connect to) a specific run
 * Handles channel connection/disconnection automatically
 *
 * This is the primary hook for following runs - it manages lifecycle
 * so components don't need to manually connect/disconnect
 *
 * @param runId - Run ID to follow, or null to stop following
 * @returns RunDetail for the followed run, or null if not
 * following/loading
 *
 * @example
 * // In FullScreenIDE:
 * const runId = useRunIdFromURL(); // string | null
 * const run = useFollowRun(runId); // Automatic connect/disconnect
 */
export const useFollowRun = (runId: string | null) => {
  const historyStore: HistoryStore = useHistoryStore();
  const run = useActiveRun();

  useEffect(() => {
    if (runId) {
      // Connect to run when runId provided
      historyStore._viewRun(runId);
    }
  }, [runId]);

  // There are no dependencies here - stable function reference from store and
  // clearRun is triggered by a user action.
  const clearRun = useCallback(() => {
    historyStore._closeRunViewer();
  }, []);

  return { run, clearRun };
};

/**
 * Hook to get currently active run (without managing lifecycle)
 * Use this in child components that don't control the connection
 */
export const useActiveRun = (): RunDetail | null => {
  const historyStore = useHistoryStore();
  const selectActiveRun = historyStore.withSelector(state => state.activeRun);
  return useSyncExternalStore(historyStore.subscribe, selectActiveRun);
};

/**
 * Hook to get active run loading state
 */
export const useActiveRunLoading = (): boolean => {
  const historyStore = useHistoryStore();
  const selectLoading = historyStore.withSelector(
    state => state.activeRunLoading
  );
  return useSyncExternalStore(historyStore.subscribe, selectLoading);
};

/**
 * Hook to get active run error state
 */
export const useActiveRunError = (): string | null => {
  const historyStore = useHistoryStore();
  const selectError = historyStore.withSelector(state => state.activeRunError);
  return useSyncExternalStore(historyStore.subscribe, selectError);
};

/**
 * Hook to get currently selected step ID
 */
export const useSelectedStepId = (): string | null => {
  const historyStore = useHistoryStore();
  const selectStepId = historyStore.withSelector(state => state.selectedStepId);
  return useSyncExternalStore(historyStore.subscribe, selectStepId);
};

/**
 * Hook to get currently selected step (with lookup)
 */
export const useSelectedStep = (): StepDetail | null => {
  const historyStore = useHistoryStore();
  const selectStep = historyStore.withSelector(state => {
    if (!state.selectedStepId || !state.activeRun) {
      return null;
    }
    return (
      state.activeRun.steps.find(step => step.id === state.selectedStepId) ||
      null
    );
  });
  return useSyncExternalStore(historyStore.subscribe, selectStep);
};

/**
 * Hook to check if the currently selected job has a corresponding step
 * in the active run.
 *
 * Returns true if:
 * - No run is loaded (null case)
 * - The selected job has at least one step in the active run
 *
 * Returns false if:
 * - A run is loaded AND the selected job has no steps in that run
 *
 * @param selectedJobId - The ID of the currently selected job
 * @returns boolean indicating if the job matches the run
 */
export const useJobMatchesRun = (selectedJobId: string | null): boolean => {
  const historyStore = useHistoryStore();
  const selectMatch = historyStore.withSelector(state => {
    // If no run is loaded, consider it a match (no visual indication needed)
    if (!state.activeRun) {
      return true;
    }

    // If no job is selected, consider it a match
    if (!selectedJobId) {
      return true;
    }

    // Check if any step in the run matches the selected job
    return state.activeRun.steps.some(step => step.job_id === selectedJobId);
  });

  return useSyncExternalStore(historyStore.subscribe, selectMatch);
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
