/**
 * Workflow State Management Hooks
 *
 * This module provides React hooks for interacting with the WorkflowStore using the
 * useSyncExternalStore + Immer + Y.Doc pattern. These hooks offer optimal performance
 * through proper memoization and referential stability.
 *
 * ## Hook Categories:
 *
 * ### Core Selector Hooks:
 * - `useWorkflowSelector` - For complex selections needing store method access (YJS)
 * - `useWorkflowState` - For simple state-only selections
 *
 * ### Specialized Hooks:
 * - `useCurrentJob` - Current selected job with YText body
 * - `useNodeSelection` - URL-based node selection with type-safe resolution
 * - `useSelectedJobBody` - Selected job's YText body for collaborative editing
 * - `useWorkflowJobs/Triggers/Enabled` - Simple state property accessors
 *
 * ### Action Hooks:
 * - `useWorkflowActions` - All workflow manipulation commands
 * - `useTriggerFormActions` - TanStack Form integration for triggers
 *
 * ## Store Architecture:
 * The underlying store implements three distinct update patterns for optimal performance
 * and collaboration support. For detailed pattern documentation with examples:
 *
 * @see ../stores/createWorkflowStore.ts - Complete pattern documentation and architecture
 * @see ../contexts/StoreProvider.tsx - Provider setup and context management
 */

import type React from "react";
import { useCallback, useContext, useMemo, useSyncExternalStore } from "react";

import { useURLState } from "#/react/lib/use-url-state";

import { StoreContext } from "../contexts/StoreProvider";
import type { WorkflowStoreInstance } from "../stores/createWorkflowStore";
import type { Workflow } from "../types/workflow";

/**
 * Hook to access the WorkflowStore context.
 *
 * This is primarily for internal use by hooks in the Workflow.ts module.
 * Most components should use the specialized hooks instead.
 *
 * @internal Use hooks from ../hooks/Workflow.ts instead
 */
export const useWorkflowStoreContext = () => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error("useWorkflowStore must be used within StoreProvider");
  }
  return context.workflowStore;
};

/**
 * Core selector hook that eliminates boilerplate and provides optimal performance.
 *
 * This hook combines the best of both worlds:
 * - React's built-in memoization (useMemo + useCallback)
 * - Store-level referential stability (withSelector)
 * - Automatic dependency management
 *
 * Use this hook when your selector needs access to store methods (e.g., getJobBodyYText).
 * For simple state-only selections, use useWorkflowState instead.
 *
 * @template T The return type of your selector function
 * @param selector Function that receives (state, store) and returns selected data
 * @param deps Optional dependency array for React memoization (like useMemo)
 *
 * @example
 * // Complex selection with store method access
 * const currentJob = useWorkflowSelector(
 *   (state, store) => ({
 *     job: state.selectedNode as Workflow.Job,
 *     ytext: state.selectedJobId ? store.getJobBodyYText(state.selectedJobId) : null,
 *   })
 * );
 *
 * @example
 * // Selection with external dependencies
 * const jobEditor = useWorkflowSelector(
 *   (state, store) => ({
 *     job: state.jobs.find(j => j.id === jobId),
 *     ytext: store.getJobBodyYText(jobId),
 *   }),
 *   [jobId] // jobId is external dependency
 * );
 *
 * @returns T The memoized result of your selector, with referential stability
 */
export const useWorkflowSelector = <T>(
  selector: (state: Workflow.State, store: WorkflowStoreInstance) => T,
  deps: React.DependencyList = []
): T => {
  const store = useWorkflowStoreContext();

  // Create stable selector function using useCallback
  const stableSelector = useCallback(
    (state: Workflow.State) => selector(state, store),
    [store, selector, ...deps]
  );

  // Use store's optimized withSelector method
  const getSnapshot = useMemo(() => {
    return store.withSelector(stableSelector);
  }, [store, stableSelector]);

  return useSyncExternalStore(store.subscribe, getSnapshot);
};

/**
 * Optimized selector hook for simple state-only selections.
 *
 * This hook is designed for pure state reads that don't require store method access.
 * It uses component-level memoization for optimal performance on lightweight operations
 * and provides better type safety for simple selectors.
 *
 * **Use this hook when:**
 * - Reading basic state properties (e.g., jobs, triggers, enabled status)
 * - Performing read-only computations on state data
 * - You don't need YJS collaborative features like YText access
 * - Simple selectors that benefit from fine-grained dependency control
 *
 * **Use `useWorkflowSelector` instead when:**
 * - You need store method access (e.g., `getJobBodyYText()` for collaborative editing)
 * - Complex selections that benefit from store-level memoization
 * - Integrating with YJS collaborative features
 *
 * @template T The return type of your selector function
 * @param selector Pure function that receives state and returns selected data
 * @param deps Optional dependency array for React memoization (like useMemo)
 *
 * @example
 * // Simple state selections - ideal use cases
 * const jobs = useWorkflowState(state => state.jobs);
 * const enabled = useWorkflowState(state => state.enabled);
 * const triggers = useWorkflowState(state => state.triggers);
 *
 * @example
 * // Complex read-only computation with external dependencies
 * const filteredJobs = useWorkflowState(
 *   state => state.jobs.filter(job =>
 *     job.name.toLowerCase().includes(searchTerm.toLowerCase())
 *   ),
 *   [searchTerm] // External dependency
 * );
 *
 * @example
 * // Computed state with type-safe selection
 * const workflowStatus = useWorkflowState(state => ({
 *   hasJobs: state.jobs.length > 0,
 *   hasTriggers: state.triggers.length > 0,
 *   isReady: state.jobs.length > 0 && state.triggers.some(t => t.enabled),
 * }));
 *
 * @performance
 * - Uses component-level memoization for fine-grained control
 * - Lower memory footprint compared to useWorkflowSelector
 * - Optimal for simple, frequently-accessed state properties
 * - Manual result caching prevents unnecessary re-renders
 *
 * @returns T The memoized result of your selector with referential stability
 */
export const useWorkflowState = <T>(
  selector: (state: Workflow.State) => T,
  deps: React.DependencyList = []
): T => {
  const store = useWorkflowStoreContext();

  // Use store's optimized withSelector method combined with useMemo
  const getSnapshot = useMemo(() => {
    return store.withSelector(selector);
  }, [store, selector, ...deps]);

  return useSyncExternalStore(store.subscribe, getSnapshot);
};

export const usePositions = () => {
  const store = useWorkflowStoreContext();

  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => ({
      positions: state.positions,
      updatePosition: store.updatePosition,
      updatePositions: store.updatePositions,
    }))
  );
};

// =============================================================================
// SPECIALIZED HOOKS
// =============================================================================

export const useWorkflowEnabled = () => {
  return useWorkflowSelector(
    (state, store) => ({
      enabled: state.enabled,
      setEnabled: store.setEnabled,
    }),
    []
  );
};

/**
 * Hook for accessing current selected job with YText body.
 * Uses useWorkflowSelector for store access (YText retrieval).
 */
export const useCurrentJob = () => {
  return useWorkflowSelector(
    (state, store) => ({
      job:
        state.selectedNode && state.selectedJobId
          ? (state.selectedNode as Workflow.Job)
          : null,
      ytext: state.selectedJobId
        ? store.getJobBodyYText(state.selectedJobId)
        : null,
    }),
    []
  );
};

/**
 * Hook for URL-based node selection with type-safe node resolution.
 * Demonstrates complex selector with external dependencies (URL state).
 */
export const useNodeSelection = () => {
  const { searchParams, updateSearchParams } = useURLState();

  // Get current node ID from URL
  const jobId = searchParams.get("job");
  const triggerId = searchParams.get("trigger");
  const edgeId = searchParams.get("edge");
  const currentNodeId = jobId || triggerId || edgeId;

  // Use useWorkflowState for simple state selection (no store methods needed)
  const stableData = useWorkflowState(
    state => {
      // Resolve current selection with proper typing
      let currentNode: {
        node: Workflow.Job | Workflow.Trigger | Workflow.Edge | null;
        type: "job" | "trigger" | "edge" | null;
        id: string | null;
      };

      if (!currentNodeId) {
        currentNode = { node: null, type: null, id: null };
      } else if (jobId) {
        const node = state.jobs.find(job => job.id === jobId) || null;
        currentNode = { node, type: "job" as const, id: jobId };
      } else if (triggerId) {
        const node =
          state.triggers.find(trigger => trigger.id === triggerId) || null;
        currentNode = { node, type: "trigger" as const, id: triggerId };
      } else if (edgeId) {
        const node = state.edges.find(edge => edge.id === edgeId) || null;
        currentNode = { node, type: "edge" as const, id: edgeId };
      } else {
        currentNode = { node: null, type: null, id: null };
      }

      return { currentNode };
    },
    // Dependencies: URL parameters that affect selection
    [currentNodeId, jobId, triggerId, edgeId]
  );

  // Selection function with stable reference and store access
  const store = useWorkflowStoreContext();
  const selectNode = useCallback(
    (id: string | null) => {
      if (!id) {
        updateSearchParams({ job: null, trigger: null, edge: null });
        return;
      }

      // Use current state to determine node type
      const state = store.getSnapshot();

      const foundJob = state.jobs.find(job => job.id === id);
      const foundTrigger = state.triggers.find(trigger => trigger.id === id);
      const foundEdge = state.edges.find(edge => edge.id === id);

      if (foundJob) {
        updateSearchParams({ job: id, trigger: null, edge: null });
      } else if (foundTrigger) {
        updateSearchParams({ trigger: id, job: null, edge: null });
      } else if (foundEdge) {
        updateSearchParams({ edge: id, job: null, trigger: null });
      }
    },
    [updateSearchParams, store]
  );

  return {
    ...stableData,
    selectNode,
  };
};

// =============================================================================
// ACTION HOOKS (COMMANDS)
// =============================================================================

export const useWorkflowActions = () => {
  const store = useWorkflowStoreContext();

  return useMemo(
    () => ({
      // Job actions
      updateJob: store.updateJob,
      updateJobName: store.updateJobName,
      updateJobBody: store.updateJobBody,
      addJob: store.addJob,
      removeJob: store.removeJob,

      // Trigger actions
      updateTrigger: store.updateTrigger,
      setEnabled: store.setEnabled,

      // Position actions
      updatePositions: store.updatePositions,
      updatePosition: store.updatePosition,

      // Selection actions (local UI state)
      selectJob: store.selectJob,
      selectTrigger: store.selectTrigger,
      selectEdge: store.selectEdge,
      clearSelection: store.clearSelection,
      removeJobAndClearSelection: store.removeJobAndClearSelection,

      // Workflow actions
      saveWorkflow: store.saveWorkflow,
    }),
    [store]
  );
};
