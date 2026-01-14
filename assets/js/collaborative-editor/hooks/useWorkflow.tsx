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

import React, {
  useCallback,
  useContext,
  useMemo,
  useSyncExternalStore,
} from 'react';

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
  useIsNewWorkflow,
  useLatestSnapshotLockVersion,
  useLimits,
  usePermissions,
  useUser,
  useWorkflowTemplate,
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
export const useWorkflowSelector = <T,>(
  selector: (state: Workflow.State, store: WorkflowStoreInstance) => T,
  deps: React.DependencyList = []
): T => {
  const store = useWorkflowStoreContext();

  const stableSelector = useCallback(
    (state: Workflow.State) => selector(state, store),
    [store, selector, ...deps]
  );

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
export const useWorkflowState = <T,>(
  selector: (state: Workflow.State) => T,
  deps: React.DependencyList = []
): T => {
  const store = useWorkflowStoreContext();

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
  const { params, updateSearchParams } = useURLState();

  // Get current node ID from URL
  const { job: jobId, trigger: triggerId, edge: edgeId } = params;
  const currentNodeId = jobId || triggerId || edgeId;

  const stableData = useWorkflowState(
    state => {
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
    [currentNodeId, jobId, triggerId, edgeId]
  );

  const store = useWorkflowStoreContext();
  const selectNode = useCallback(
    (id: string | null) => {
      const currentPanel = params['panel'] ?? null;

      if (!id) {
        updateSearchParams({ job: null, trigger: null, edge: null });
        return;
      }

      const state = store.getSnapshot();

      const foundJob = state.jobs.find(job => job.id === id);
      const foundTrigger = state.triggers.find(trigger => trigger.id === id);
      const foundEdge = state.edges.find(edge => edge.id === id);

      // If node doesn't exist and we're already viewing it (e.g., viewing a run from different version),
      // don't update URL - let the IDE show the "job missing" message instead of closing
      const {
        job: currentJobId,
        trigger: currentTriggerId,
        edge: currentEdgeId,
      } = params;
      if (!foundJob && !foundTrigger && !foundEdge) {
        if (
          id === currentJobId ||
          id === currentTriggerId ||
          id === currentEdgeId
        ) {
          // Already viewing this missing node - don't clear URL
          return;
        }
      }

      // nodePanels are panels, while open, we can switch from one node to another
      const nodePanels = ['editor', 'run'];
      const updates: Record<string, string | null> = {
        job: null,
        trigger: null,
        edge: null,
        panel: nodePanels.includes(currentPanel) ? currentPanel : null,
      };

      if (foundJob) {
        updates['job'] = id;
      } else if (foundTrigger) {
        updates['trigger'] = id;
      } else if (foundEdge) {
        updates['edge'] = id;
      }

      updateSearchParams(updates);
    },
    [updateSearchParams, store, params]
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
  const uiStore = context.uiStore;

  return {
    updateJob: store.updateJob,
    updateJobName: store.updateJobName,
    updateJobBody: store.updateJobBody,
    addJob: store.addJob,
    removeJob: store.removeJob,

    updateWorkflow: store.updateWorkflow,

    addEdge: store.addEdge,
    updateEdge: store.updateEdge,
    removeEdge: store.removeEdge,

    updateTrigger: store.updateTrigger,
    setEnabled: store.setEnabled,

    updatePositions: store.updatePositions,
    updatePosition: store.updatePosition,

    selectJob: store.selectJob,
    selectTrigger: store.selectTrigger,
    selectEdge: store.selectEdge,
    clearSelection: store.clearSelection,
    removeJobAndClearSelection: store.removeJobAndClearSelection,

    setError: store.setError,
    setClientErrors: (...args: Parameters<typeof store.setClientErrors>) => {
      // Note: there was something stale here
      store.setClientErrors(...args);
    },

    saveWorkflow: (() => {
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
            // Update URL to include project_id and remove template-related params
            const url = new URL(window.location.href);
            const searchParams = new URLSearchParams(url.search);
            searchParams.delete('method'); // Close left panel
            searchParams.delete('template'); // Clear template selection
            searchParams.delete('search'); // Clear template search
            const queryString = searchParams.toString();
            const newUrl = `/projects/${projectId}/w/${workflowId}/legacy${queryString ? `?${queryString}` : ''}`;
            window.history.replaceState(null, '', newUrl);

            // Clear template state in UI store
            uiStore.selectTemplate(null);
            uiStore.setTemplateSearchQuery('');
            uiStore.collapseCreateWorkflowPanel();

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
            errors: error.errors as { base?: string[] } & Record<
              string,
              string[]
            >,
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
            // Update URL to include project_id and remove method param (closes left panel)
            const url = new URL(window.location.href);
            const searchParams = new URLSearchParams(url.search);
            searchParams.delete('method'); // Close left panel
            const queryString = searchParams.toString();
            const newUrl = `/projects/${projectId}/w/${workflowId}/legacy${queryString ? `?${queryString}` : ''}`;
            window.history.pushState({}, '', newUrl);
            // Mark workflow as no longer new after first save
            sessionContextStore.clearIsNewWorkflow();
          }
        }

        // Show success toast
        const successOptions: {
          title: string;
          description?: React.ReactNode;
        } = {
          title: 'Workflow saved and synced to GitHub',
        };

        if (response.repo) {
          const actionsUrl = `https://github.com/${response.repo}/actions`;
          successOptions.description = (
            <span>
              Changes pushed to {response.repo}. Check the{' '}
              <a
                href={actionsUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="underline"
              >
                GitHub actions
              </a>{' '}
              for result
            </span>
          );
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
            errors: error.errors as { base?: string[] } & Record<
              string,
              string[]
            >,
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

    requestTriggerAuthMethods: store.requestTriggerAuthMethods,

    // AI workflow apply coordination
    startApplyingWorkflow: store.startApplyingWorkflow,
    doneApplyingWorkflow: store.doneApplyingWorkflow,

    // AI job code apply coordination
    startApplyingJobCode: store.startApplyingJobCode,
    doneApplyingJobCode: store.doneApplyingJobCode,
  };
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
 * - isPinnedVersion: Viewing a pinned version (any ?v parameter in URL)
 *
 * @internal This is shared logic between useCanSave and useCanRun
 */
const useWorkflowConditions = () => {
  const { isSynced } = useSession();
  const permissions = usePermissions();
  const workflow = useWorkflowState(state => state.workflow);
  const { params } = useURLState();

  const hasEditPermission = permissions?.can_edit_workflow ?? false;
  const hasRunPermission = permissions?.can_run_workflow ?? false;
  const isConnected = isSynced;
  const isDeleted = workflow !== null && workflow.deleted_at !== null;

  // Check if version is pinned via URL parameter
  const isPinnedVersion = params['v'] !== undefined && params['v'] !== null;

  return {
    hasEditPermission,
    hasRunPermission,
    isConnected,
    isDeleted,
    isPinnedVersion,
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
 * 3. Version pinning (any ?v parameter in URL)
 * 4. Workflow deletion state (deleted_at)
 */
export const useCanSave = (): { canSave: boolean; tooltipMessage: string } => {
  const { hasEditPermission, isConnected, isDeleted, isPinnedVersion } =
    useWorkflowConditions();

  // Check if any apply operation in progress
  const isApplyingJobCode = useWorkflowState(state => state.isApplyingJobCode);
  const isApplyingWorkflow = useWorkflowState(
    state => state.isApplyingWorkflow
  );

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
  } else if (isPinnedVersion) {
    canSave = false;
    tooltipMessage = 'You are viewing a pinned version of this workflow';
  } else if (isApplyingJobCode) {
    canSave = false;
    tooltipMessage = 'Applying AI-generated code...';
  } else if (isApplyingWorkflow) {
    canSave = false;
    tooltipMessage = 'Applying AI-generated workflow...';
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
 * 1. User permissions (can_edit_workflow or can_run_workflow)
 * 2. Connection state (isSynced)
 * 3. Version pinning (any ?v parameter in URL)
 * 4. Workflow deletion state (deleted_at)
 * 5. Run limits (from session context)
 */
export const useCanRun = (): { canRun: boolean; tooltipMessage: string } => {
  const {
    hasEditPermission,
    hasRunPermission,
    isConnected,
    isDeleted,
    isPinnedVersion,
  } = useWorkflowConditions();

  // Get run limits from session context (defaults to allowed if missing)
  const limits = useLimits();
  const runLimits = limits.runs ?? { allowed: true, message: null };

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
  } else if (isPinnedVersion) {
    canRun = false;
    tooltipMessage = 'You are viewing a pinned version of this workflow';
  } else if (!runLimits.allowed && runLimits.message) {
    canRun = false;
    tooltipMessage = runLimits.message;
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
 * 3. Version pinning (any ?v parameter in URL)
 * 4. Template preview (new workflow with selected template)
 *
 * Note: Connection state does not affect read-only status. Offline editing
 * is fully supported - Y.Doc buffers transactions locally and syncs when
 * reconnected.
 */
export const useWorkflowReadOnly = (): {
  isReadOnly: boolean;
  tooltipMessage: string;
} => {
  // Get permissions and workflow state
  const permissions = usePermissions();
  const workflow = useWorkflowState(state => state.workflow);
  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  const { params } = useURLState();

  // Check if version is pinned via URL parameter
  const isPinnedVersion = params['v'] !== undefined && params['v'] !== null;

  // Check if this is a new workflow with content (from template or AI)
  // Users must click "Create" before they can edit
  const isNewWorkflow = useIsNewWorkflow();
  const hasWorkflowContent = jobs.length > 0 || triggers.length > 0;
  const isUnsavedNewWorkflow = isNewWorkflow && hasWorkflowContent;

  // Don't show read-only state until permissions are loaded
  // This prevents flickering during initial load
  if (permissions === null) {
    return { isReadOnly: false, tooltipMessage: '' };
  }

  // Compute read-only conditions
  const hasPermission = permissions.can_edit_workflow;
  const isDeleted = workflow !== null && workflow.deleted_at !== null;

  // Priority order: deleted > permissions > pinned version > unsaved new workflow
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
  if (isPinnedVersion) {
    return {
      isReadOnly: true,
      tooltipMessage: 'You are viewing a pinned version of this workflow',
    };
  }
  if (isUnsavedNewWorkflow) {
    return {
      isReadOnly: true,
      tooltipMessage: 'Click "Create" to edit this workflow',
    };
  }

  return { isReadOnly: false, tooltipMessage: '' };
};

/**
 * Hook to check if workflow settings have validation errors
 *
 * Returns object with:
 * - hasErrors: boolean - true if name or concurrency have validation
 * Used by Header component to display error indication on settings
 * button
 */
export const useWorkflowSettingsErrors = (): {
  hasErrors: boolean;
} => {
  const validationErrors = useWorkflowState(state => state.workflow?.errors);
  const errors = Object.values(validationErrors || {}).flat();
  const hasErrors = !!errors.length;
  return { hasErrors };
};

/**
 * Hook to determine if user can publish workflow as template
 *
 * Returns object with:
 * - canPublish: boolean - whether publish action is available
 *   (based on support_user)
 * - buttonDisabled: boolean - whether button should be disabled
 *   (based on unsaved changes)
 * - tooltipMessage: string - message explaining button state
 * - buttonText: string - "Publish Template" or "Update Template"
 *
 * Template publishing is only available to support users (superusers).
 * The button is disabled when there are unsaved changes (workflow
 * lock_version differs from latestSnapshotLockVersion).
 */
export const useCanPublishTemplate = (): {
  canPublish: boolean;
  buttonDisabled: boolean;
  tooltipMessage: string;
  buttonText: string;
} => {
  const user = useUser();
  const workflowTemplate = useWorkflowTemplate();
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();
  const workflow = useWorkflowState(state => state.workflow);

  // Only support users can publish templates
  const canPublish = user?.support_user ?? false;

  // Check if workflow has unsaved changes by comparing lock versions
  const hasUnsavedChanges =
    workflow?.lock_version !== latestSnapshotLockVersion;

  const buttonText = workflowTemplate ? 'Update Template' : 'Publish Template';

  const buttonDisabled = hasUnsavedChanges;

  const tooltipMessage = hasUnsavedChanges
    ? `You must save your workflow first before ${workflowTemplate ? 'updating' : 'publishing'} a template.`
    : '';

  return {
    canPublish,
    buttonDisabled,
    tooltipMessage,
    buttonText,
  };
};
