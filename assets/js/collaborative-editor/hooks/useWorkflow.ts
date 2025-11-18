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

import type React from 'react';
import { useCallback, useContext, useMemo, useSyncExternalStore } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { StoreContext } from '../contexts/StoreProvider';
import {
  formatChannelErrorMessage,
  isChannelRequestError,
} from '../lib/errors';
import { notifications } from '../lib/notifications';
import type { WorkflowStoreInstance } from '../stores/createWorkflowStore';
import type { Workflow } from '../types/workflow';

import { useSession } from './useSession';
import {
  useLatestSnapshotLockVersion,
  usePermissions,
} from './useSessionContext';

// import _logger from "#/utils/logger";
// const logger = _logger.ns("useWorkflow").seal();

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
    throw new Error('useWorkflowStore must be used within StoreProvider');
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
  const jobId = searchParams.get('job');
  const triggerId = searchParams.get('trigger');
  const edgeId = searchParams.get('edge');
  const currentNodeId = jobId || triggerId || edgeId;

  // Use useWorkflowState for simple state selection (no store methods needed)
  const stableData = useWorkflowState(
    state => {
      // Resolve current selection with proper typing
      let currentNode: {
        node: Workflow.Job | Workflow.Trigger | Workflow.Edge | null;
        type: 'job' | 'trigger' | 'edge' | null;
        id: string | null;
      };

      if (!currentNodeId) {
        currentNode = { node: null, type: null, id: null };
      } else if (jobId) {
        const node = state.jobs.find(job => job.id === jobId) || null;
        currentNode = { node, type: 'job' as const, id: jobId };
      } else if (triggerId) {
        const node =
          state.triggers.find(trigger => trigger.id === triggerId) || null;
        currentNode = { node, type: 'trigger' as const, id: triggerId };
      } else if (edgeId) {
        const node = state.edges.find(edge => edge.id === edgeId) || null;
        currentNode = { node, type: 'edge' as const, id: edgeId };
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
  const context = useContext(StoreContext);

  if (!context) {
    throw new Error('useWorkflowActions must be used within StoreProvider');
  }

  const sessionContextStore = context.sessionContextStore;

  return useMemo(
    () => ({
      // Job actions
      updateJob: store.updateJob,
      updateJobName: store.updateJobName,
      updateJobBody: store.updateJobBody,
      addJob: store.addJob,
      removeJob: store.removeJob,

      // Workflow actions (Pattern 1: Y.Doc sync)
      updateWorkflow: store.updateWorkflow,

      // Edge actions
      addEdge: store.addEdge,
      updateEdge: store.updateEdge,
      removeEdge: store.removeEdge,

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

      // Error management actions
      setError: store.setError,
      setClientErrors: store.setClientErrors,

      // Workflow actions - wrapped to handle lock version updates
      saveWorkflow: (() => {
        // Helper: Handle successful save operations
        const handleSaveSuccess = (
          response: Awaited<ReturnType<typeof store.saveWorkflow>>,
          silent = false
        ) => {
          if (!response) return;

          // Update session context with new lock version if present
          if (response.lock_version !== undefined) {
            sessionContextStore.setLatestSnapshotLockVersion(
              response.lock_version
            );
          }

          // Check if this is a new workflow and update URL
          const currentState = sessionContextStore.getSnapshot();
          if (currentState.isNewWorkflow) {
            const workflowState = store.getSnapshot();
            const workflowId = workflowState.workflow?.id;
            const projectId = currentState.project?.id;

            if (workflowId && projectId) {
              // Update URL to include project_id
              const newUrl = `/projects/${projectId}/w/${workflowId}/collaborate`;
              window.history.replaceState(null, '', newUrl);

              // Clear isNewWorkflow flag after successful save
              sessionContextStore.clearIsNewWorkflow();
            }
          }

          // Show success notification unless silent mode
          if (!silent) {
            notifications.info({
              title: 'Workflow saved',
              description: response.saved_at
                ? `Last saved at ${new Date(response.saved_at).toLocaleTimeString()}`
                : 'All changes have been synced',
            });
          }
        };

        // Helper: Handle save errors with appropriate notifications
        const handleSaveError = (
          error: unknown,
          retrySaveWorkflow: () => Promise<unknown>
        ) => {
          // Format channel errors into user-friendly messages
          if (isChannelRequestError(error)) {
            error.message = formatChannelErrorMessage({
              errors: error.errors,
              type: error.type,
            });

            if (error.type === 'unauthorized') {
              notifications.alert({
                title: 'Permission Denied',
                description: error.message,
              });
            } else if (error.type === 'validation_error') {
              notifications.alert({
                title: 'Unable to save workflow',
                description: error.message,
              });
            } else {
              notifications.alert({
                title: 'Failed to save workflow',
                description: error.message,
                action: {
                  label: 'Retry',
                  onClick: () => {
                    void retrySaveWorkflow();
                  },
                },
              });
            }
          } else {
            // Handle non-channel errors
            notifications.alert({
              title: 'Failed to save workflow',
              description:
                error instanceof Error
                  ? error.message
                  : 'Please check your connection and try again',
              action: {
                label: 'Retry',
                onClick: () => {
                  void retrySaveWorkflow();
                },
              },
            });
          }
        };

        // Main wrapped saveWorkflow function
        const wrappedSaveWorkflow = async (options?: { silent?: boolean }) => {
          try {
            const response = await store.saveWorkflow();

            if (!response) {
              // saveWorkflow returns null when not connected
              // Connection status is already shown in UI, no toast needed
              return null;
            }

            handleSaveSuccess(response, options?.silent);
            return response;
          } catch (error) {
            handleSaveError(error, wrappedSaveWorkflow);
            // Re-throw error for any upstream error handling
            throw error;
          }
        };

        return wrappedSaveWorkflow;
      })(),

      // GitHub save and sync action - wrapped to handle lock version updates and errors
      saveAndSyncWorkflow: (commitMessage: string) => {
        // Helper: Handle successful save and sync operations
        const handleSaveAndSyncSuccess = (
          response: Awaited<ReturnType<typeof store.saveAndSyncWorkflow>>
        ) => {
          if (!response) return;

          // Update session context with new lock version if present
          if (response.lock_version !== undefined) {
            sessionContextStore.setLatestSnapshotLockVersion(
              response.lock_version
            );
          }

          // Check if this is a new workflow and update URL
          const currentState = sessionContextStore.getSnapshot();
          if (currentState.isNewWorkflow) {
            const workflowState = store.getSnapshot();
            const workflowId = workflowState.workflow?.id;
            const projectId = currentState.project?.id;

            if (workflowId && projectId) {
              // Update URL to include project_id
              const newUrl = `/projects/${projectId}/w/${workflowId}/collaborate`;
              window.history.pushState({}, '', newUrl);
              // Mark workflow as no longer new after first save
              sessionContextStore.clearIsNewWorkflow();
            }
          }

          // Show success toast
          const successOptions: { title: string; description?: string } = {
            title: 'Workflow saved and synced to GitHub',
          };
          if (response.repo) {
            successOptions.description = `Changes pushed to ${response.repo}`;
          }
          notifications.success(successOptions);
        };

        // Helper: Handle save and sync errors
        const handleSaveAndSyncError = (
          error: unknown,
          retrySaveAndSync: () => Promise<unknown>
        ) => {
          // Format channel errors into user-friendly messages
          if (isChannelRequestError(error)) {
            error.message = formatChannelErrorMessage({
              errors: error.errors,
              type: error.type,
            });

            if (error.type === 'unauthorized') {
              notifications.alert({
                title: 'Permission denied',
                description: error.message,
              });
              return;
            }

            if (error.type === 'validation_error') {
              notifications.alert({
                title: 'Unable to save and sync workflow',
                description: error.message,
              });
              return;
            }
          }

          notifications.alert({
            title: 'Failed to save and sync workflow',
            description:
              error instanceof Error
                ? error.message
                : 'Please check your connection and try again',
            action: {
              label: 'Retry',
              onClick: () => {
                void retrySaveAndSync();
              },
            },
          });
        };

        // Main wrapped saveAndSyncWorkflow function
        const wrappedSaveAndSyncWorkflow = async () => {
          try {
            const response = await store.saveAndSyncWorkflow(commitMessage);

            if (!response) {
              // saveAndSyncWorkflow returns null when not connected
              // Connection status is already shown in UI, no toast needed
              return null;
            }

            handleSaveAndSyncSuccess(response);
            return response;
          } catch (error) {
            handleSaveAndSyncError(error, wrappedSaveAndSyncWorkflow);
            // Re-throw error for any upstream error handling
            throw error;
          }
        };

        return wrappedSaveAndSyncWorkflow();
      },

      resetWorkflow: store.resetWorkflow,
      importWorkflow: store.importWorkflow,

      // Trigger auth methods
      requestTriggerAuthMethods: store.requestTriggerAuthMethods,
    }),
    [store, sessionContextStore]
  );
};

/**
 * Internal hook that computes workflow state conditions used by both
 * useCanSave and useCanRun.
 *
 * Extracts common logic to avoid duplication following DRY principles.
 * This hook computes four core conditions that determine whether
 * workflow operations (save/run) are permitted:
 *
 * @returns Object with condition flags:
 * - hasPermission: User has can_edit_workflow permission
 * - isConnected: Session is synced with backend
 * - isDeleted: Workflow has been deleted
 * - isOldSnapshot: Viewing an old snapshot (not latest version)
 *
 * @internal This is shared logic between useCanSave and useCanRun
 */
const useWorkflowConditions = () => {
  const { isSynced } = useSession();
  const permissions = usePermissions();
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();
  const workflow = useWorkflowState(state => state.workflow);

  const hasEditPermission = permissions?.can_edit_workflow ?? false;
  const hasRunPermission = permissions?.can_run_workflow ?? false;
  const isConnected = isSynced;
  const isDeleted = workflow !== null && workflow.deleted_at !== null;

  // Only consider it an old snapshot if workflow is loaded, latest
  // snapshot lock version is available AND different from workflow
  // lock version
  const isOldSnapshot =
    workflow !== null &&
    latestSnapshotLockVersion !== null &&
    workflow.lock_version !== latestSnapshotLockVersion;

  return {
    hasEditPermission,
    hasRunPermission,
    isConnected,
    isDeleted,
    isOldSnapshot,
  };
};

/**
 * Hook to determine if workflow can be saved and provide tooltip message
 *
 * Returns object with:
 * - canSave: boolean - whether save button should be enabled
 * - tooltipMessage: string - message explaining button state
 *
 * Checks:
 * 1. User permissions (can_edit_workflow)
 * 2. Connection state (isSynced)
 * 3. Lock version (viewing latest snapshot)
 * 4. Workflow deletion state (deleted_at)
 */
export const useCanSave = (): { canSave: boolean; tooltipMessage: string } => {
  const { hasEditPermission, isConnected, isDeleted, isOldSnapshot } =
    useWorkflowConditions();

  // Determine tooltip message (check in priority order)
  let tooltipMessage = '';
  let canSave = true;

  if (!isConnected) {
    canSave = false;
    tooltipMessage = 'You are disconnected. Reconnecting...';
  } else if (!hasEditPermission) {
    canSave = false;
    tooltipMessage = 'You do not have permission to edit this workflow';
  } else if (isDeleted) {
    canSave = false;
    tooltipMessage = 'Workflow has been deleted';
  } else if (isOldSnapshot) {
    canSave = false;
    tooltipMessage = 'You cannot edit an old snapshot of a workflow';
  }

  return { canSave, tooltipMessage };
};

/**
 * Hook to determine if workflow can be run and provide tooltip message
 *
 * Returns object with:
 * - canRun: boolean - whether run button should be enabled
 * - tooltipMessage: string - message explaining button state
 *
 * Checks:
 * 1. User permissions (can_edit_workflow)
 * 2. Connection state (isSynced)
 * 3. Lock version (viewing latest snapshot)
 * 4. Workflow deletion state (deleted_at)
 */
export const useCanRun = (): { canRun: boolean; tooltipMessage: string } => {
  const {
    hasEditPermission,
    hasRunPermission,
    isConnected,
    isDeleted,
    isOldSnapshot,
  } = useWorkflowConditions();

  // User can run if they have EITHER edit OR run permission (matches WorkflowEdit)
  const hasPermission = hasEditPermission || hasRunPermission;

  // Determine tooltip message (check in priority order)
  let tooltipMessage = '';
  let canRun = true;

  if (!isConnected) {
    canRun = false;
    tooltipMessage = 'You are disconnected. Reconnecting...';
  } else if (!hasPermission) {
    canRun = false;
    tooltipMessage = 'You do not have permission to run workflows';
  } else if (isDeleted) {
    canRun = false;
    tooltipMessage = 'Workflow has been deleted';
  } else if (isOldSnapshot) {
    canRun = false;
    tooltipMessage = 'You cannot run an old snapshot of a workflow';
  }

  return { canRun, tooltipMessage };
};

/**
 * Hook to determine if workflow is read-only and provide tooltip message
 *
 * Returns object with:
 * - isReadOnly: boolean - whether workflow should be read-only
 * - tooltipMessage: string - message explaining read-only state
 *
 * Checks (in priority order):
 * 1. Workflow deletion state (deleted_at)
 * 2. User permissions (can_edit_workflow)
 * 3. Snapshot version (viewing old snapshot)
 */
export const useWorkflowReadOnly = (): {
  isReadOnly: boolean;
  tooltipMessage: string;
} => {
  // Get session state and permissions (same pattern as useCanSave)
  const permissions = usePermissions();
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();
  const workflow = useWorkflowState(state => state.workflow);

  // Don't show read-only state until permissions are loaded
  // This prevents flickering during initial load
  if (permissions === null) {
    return { isReadOnly: false, tooltipMessage: '' };
  }

  // Compute read-only conditions
  const hasPermission = permissions.can_edit_workflow;
  const isDeleted = workflow !== null && workflow.deleted_at !== null;
  const isOldSnapshot =
    workflow !== null &&
    latestSnapshotLockVersion !== null &&
    workflow.lock_version !== latestSnapshotLockVersion;

  // Priority order: deleted > permissions > snapshot
  if (isDeleted) {
    return {
      isReadOnly: true,
      tooltipMessage: 'This workflow has been deleted and cannot be edited',
    };
  }
  if (!hasPermission) {
    return {
      isReadOnly: true,
      tooltipMessage: 'You do not have permission to edit this workflow',
    };
  }
  if (isOldSnapshot) {
    return {
      isReadOnly: true,
      tooltipMessage: 'You cannot edit or run an old snapshot of a workflow',
    };
  }

  return { isReadOnly: false, tooltipMessage: '' };
};

/**
 * Hook to check if workflow settings have validation errors
 *
 * Returns object with:
 * - hasErrors: boolean - true if name or concurrency have validation
 *   errors
 * - errors: validation error object or null
 *
 * Used by Header component to display error indication on settings
 * button
 */
export const useWorkflowSettingsErrors = (): {
  hasErrors: boolean;
  errors: { name?: string[]; concurrency?: string[] } | null;
} => {
  const validationErrors = useWorkflowState(state => state.validationErrors);

  const hasErrors =
    validationErrors !== null &&
    (validationErrors.name !== undefined ||
      validationErrors.concurrency !== undefined);

  return { hasErrors, errors: validationErrors };
};
