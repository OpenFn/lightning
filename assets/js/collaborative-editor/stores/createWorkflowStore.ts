/**
 * # WorkflowStore
 *
 * This store implements a pattern combining useSyncExternalStore + Immer + Y.Doc
 * for optimal performance in collaborative editing scenarios.
 *
 * ## Core Principles:
 * - Y.Doc as the single source of truth for collaborative data
 * - Immer for referentially stable state updates
 * - Clear separation between collaborative data and local UI state
 * - Command Query Separation (CQS) for predictable state mutations
 *
 * ## Three Update Patterns:
 *
 * ### Pattern 1: Y.Doc → Observer → Immer → Notify (Collaborative Data)
 * **When to use**: All collaborative workflow data (jobs, triggers, edges, workflow metadata)
 * **Flow**: User action → Y.Doc transaction → Y.js observer fires → Immer update → React notification
 * **Benefits**: Automatic conflict resolution, real-time collaboration, persistence
 *
 * ```typescript
 * // Example: Update a job name
 * const updateJobName = (id: string, name: string) => {
 *   if (!ydoc) return;
 *
 *   const jobsArray = ydoc.getArray("jobs");
 *   const job = findJobById(jobsArray, id);
 *
 *   ydoc.transact(() => {
 *     job.set("name", name);  // Y.Doc update
 *   });
 *   // Observer automatically handles: Y.Doc → Immer → notify()
 * };
 * ```
 *
 * ### Pattern 2: Y.Doc + Immediate Immer → Notify (Hybrid Operations)
 * **When to use**: Operations that affect both collaborative data AND local UI state
 * **Flow**: Y.Doc transaction + immediate local state update + notify
 * **Benefits**: Atomic operations, immediate UI feedback, maintains consistency
 * **Note**: This pattern should be used sparingly - evaluate if Pattern 1 or 3 is more appropriate
 *
 * ```typescript
 * // Example: Remove job and clear selection if it was selected
 * const removeJobAndClearSelection = (id: string) => {
 *   // 1. Update Y.Doc first (will trigger observer)
 *   removeJob(id);
 *
 *   // 2. Immediately update local UI state
 *   state = produce(state, (draft) => {
 *     if (draft.selectedJobId === id) {
 *       draft.selectedJobId = null;
 *       updateDerivedState(draft);
 *     }
 *   });
 *   notify();
 *
 *   // Note: Y.Doc observer will also fire and update the jobs array
 * };
 * ```
 *
 * ### Pattern 3: Direct Immer → Notify (Local UI State)
 * **When to use**: Local UI state that doesn't need collaboration (selections, UI preferences)
 * **Flow**: Direct Immer update → React notification
 * **Benefits**: Immediate response, no network overhead, simple implementation
 *
 * ```typescript
 * // Example: Select a job (local UI state only)
 * const selectJob = (id: string | null) => {
 *   state = produce(state, (draft) => {
 *     draft.selectedJobId = id;
 *     draft.selectedTriggerId = null; // Clear other selections
 *     draft.selectedEdgeId = null;
 *     updateDerivedState(draft); // Update computed properties
 *   });
 *   notify(); // Trigger React re-renders
 * };
 * ```
 *
 * ## Pattern Selection Guidelines:
 *
 * **Use Pattern 1 for:**
 * - Job body content (collaborative editing with Y.Text)
 * - Job/trigger/edge names and properties
 * - Workflow metadata
 * - Any data that needs to be shared between users
 *
 * **Use Pattern 2 for:**
 * - Operations that span collaborative + local state
 * - Atomic operations requiring immediate UI feedback
 * - Complex workflows where Pattern 1 + Pattern 3 would be insufficient
 * - **Evaluate carefully** - often Pattern 1 or 3 alone is better
 *
 * **Use Pattern 3 for:**
 * - Node selection (selectedJobId, selectedTriggerId, selectedEdgeId)
 * - UI preferences and local settings
 * - Computed derived state (selectedNode, selectedEdge)
 * - Any state that should NOT be synchronized between users
 *
 * ## Implementation Notes:
 * - All patterns use Immer for immutable updates and referential stability
 * - Y.Doc observers use `observeDeep()` for nested object changes
 * - `updateDerivedState()` maintains computed properties consistently
 * - The store is designed for use with `useSyncExternalStore` hook
 *
 * @see ../hooks/Workflow.ts for React hook implementations
 * @see ../contexts/StoreProvider.tsx for provider setup
 */

/**
 * ## Redux DevTools Integration
 *
 * This store integrates with Redux DevTools for debugging in
 * development and test environments.
 *
 * **Features:**
 * - Real-time state inspection
 * - Action history with timestamps
 * - Time-travel debugging (jump to previous states)
 * - State export/import for reproducing bugs
 *
 * **Usage:**
 * 1. Install Redux DevTools browser extension
 * 2. Open DevTools and select the "WorkflowStore" instance
 * 3. Perform actions in the app and watch them appear in DevTools
 *
 * **Note:** DevTools is automatically disabled in production builds.
 *
 * **Excluded from DevTools:**
 * Y.Doc, Provider (too large/circular)
 */

import { produce } from 'immer';
import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import * as Y from 'yjs';
import { z } from 'zod';

import _logger from '#/utils/logger';

import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { YAMLStateToYDoc } from '../adapters/YAMLStateToYDoc';
import { channelRequest } from '../hooks/useChannel';
import { EdgeSchema } from '../types/edge';
import { JobSchema } from '../types/job';
import type { Session } from '../types/session';
import type { Workflow } from '../types/workflow';
import { WorkflowSchema } from '../types/workflow';
import { getIncomingEdgeIndices } from '../utils/workflowGraph';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('WorkflowStore').seal();

const JobShape = JobSchema.shape;
const EdgeShape = EdgeSchema.shape;

/**
 * Validates workflow data and returns errors for name and concurrency
 * fields.
 * Returns null if workflow is not loaded, empty object if no errors
 */
function validateWorkflowSettings(
  workflow: Session.Workflow | null
): { name?: string[]; concurrency?: string[] } | null {
  if (!workflow) return null;

  try {
    WorkflowSchema.parse({
      id: workflow.id,
      name: workflow.name,
      lock_version: workflow.lock_version,
      deleted_at: workflow.deleted_at,
      concurrency: workflow.concurrency,
      enable_job_logs: workflow.enable_job_logs,
    });
    // No validation errors
    return {};
  } catch (error) {
    if (error instanceof z.ZodError) {
      const errors: { name?: string[]; concurrency?: string[] } = {};

      // Extract only name and concurrency errors
      error.issues.forEach(err => {
        const field = err.path[0];
        if (field === 'name' || field === 'concurrency') {
          if (!errors[field]) {
            errors[field] = [];
          }
          errors[field]!.push(err.message);
        }
      });

      return errors;
    }
    // Unknown error type - return null
    return null;
  }
}

// Helper to update derived state (defined first to avoid hoisting issues)
function updateDerivedState(draft: Workflow.State) {
  // Compute enabled from triggers
  draft.enabled =
    draft.triggers.length > 0 ? draft.triggers.some(t => t.enabled) : null;

  // Compute selected node
  if (draft.selectedJobId) {
    draft.selectedNode =
      draft.jobs.find(j => j.id === draft.selectedJobId) || null;
  } else if (draft.selectedTriggerId) {
    draft.selectedNode =
      draft.triggers.find(t => t.id === draft.selectedTriggerId) || null;
  } else {
    draft.selectedNode = null;
  }

  // Compute selected edge
  draft.selectedEdge = draft.selectedEdgeId
    ? draft.edges.find(e => e.id === draft.selectedEdgeId) || null
    : null;
}

function produceInitialState() {
  return produce(
    {
      // Initialize with empty data (Y.Doc will sync when connected)
      workflow: null,
      jobs: [],
      triggers: [],
      edges: [],
      positions: {},

      // Initialize UndoManager
      undoManager: null,

      // Initialize UI state
      selectedJobId: null,
      selectedTriggerId: null,
      selectedEdgeId: null,

      // Initialize computed state
      enabled: null,
      selectedNode: null,
      selectedEdge: null,

      // Active trigger webhook auth methods (loaded on-demand)
      activeTriggerAuthMethods: null,
      // Initialize validation state
      validationErrors: null,
    } as Workflow.State,
    draft => {
      // Compute derived state on initialization
      updateDerivedState(draft);
    }
  );
}

export const createWorkflowStore = () => {
  // Y.Doc will be connected externally via SessionProvider
  let ydoc: Session.WorkflowDoc | null = null;
  let observerCleanups: (() => void)[] = [];
  let provider: (PhoenixChannelProvider & { channel: Channel }) | null = null;

  // Flag to suppress notifications during initial sync
  // This prevents multiple React renders when connect() populates state
  let isSyncing = false;

  let state = produceInitialState();

  const listeners = new Set<() => void>();

  // Debounce state for setClientErrors
  const debounceTimeouts = new Map<string, NodeJS.Timeout>();

  // Redux DevTools integration (development/test only)
  const devtools = wrapStoreWithDevTools<Workflow.State>({
    name: 'WorkflowStore',
    excludeKeys: ['ydoc', 'provider', 'undoManager'], // Exclude Y.Doc, provider, and undoManager (too large/circular)
    maxAge: 200, // Higher limit to prevent history loss from frequent updates
    trace: true,
  });

  /**
   * Ensures Y.Doc and provider are connected before mutation operations.
   *
   * This guard centralizes error handling for operations that require
   * a connected Y.Doc. All mutation methods should call this before
   * accessing ydoc or provider.
   *
   * @throws {Error} If Y.Doc or provider is not connected
   * @returns Object containing ydoc and provider instances
   */
  const ensureConnected = () => {
    if (!ydoc || !provider) {
      throw new Error(
        'Cannot save workflow: Connection lost. Please wait for reconnection.'
      );
    }
    return { ydoc, provider };
  };

  /**
   * Ensures Y.Doc exists before mutation operations.
   *
   * Simplified check for offline editing - only verifies ydoc exists,
   * not provider. Y.Doc can accept transactions without provider
   * (offline editing), with changes automatically syncing on reconnection.
   *
   * @throws {Error} If Y.Doc is not initialized
   * @returns Y.Doc instance
   */
  const ensureYDoc = (): Y.Doc => {
    if (!ydoc) {
      throw new Error(
        'Cannot modify workflow: Y.Doc not initialized. ' +
          'This is likely a bug - mutations should not be called ' +
          'before connection.'
      );
    }
    return ydoc;
  };

  const notify = (actionName: string = 'stateChange') => {
    logger.debug('notify', {
      action: actionName,
      workflow: state.workflow,
      jobs: state.jobs.length,
      triggers: state.triggers.length,
      edges: state.edges.length,
      positions: Object.keys(state.positions).length,
    });

    // Send to Redux DevTools
    devtools.notifyWithAction(actionName, () => state);

    // Notify React subscribers
    listeners.forEach(listener => {
      listener();
    });
  };

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  let lastState: Workflow.State = state;
  const updateState = (
    updater: (draft: Workflow.State) => void,
    actionName: string = 'updateState'
  ) => {
    const nextState = produce(state, draft => {
      updater(draft);
      updateDerivedState(draft);
    });
    if (nextState !== lastState) {
      lastState = nextState;
      state = nextState;
      // Skip notification if we're in the middle of a batch sync
      if (!isSyncing) {
        notify(actionName);
      } else {
        logger.debug('skipping notify due to isSyncing', { actionName });
      }
    }
  };

  // Returns the current Immer state (referentially stable)
  const getSnapshot = (): Workflow.State => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  /**
   * Helper to check if errors actually changed (shallow comparison)
   * This prevents unnecessary object updates in Immer when errors haven't
   * changed, maintaining referential stability for React memoization.
   */
  function areErrorsEqual(
    a: Record<string, string[]>,
    b: Record<string, string[]>
  ): boolean {
    const keysA = Object.keys(a);
    const keysB = Object.keys(b);

    if (keysA.length !== keysB.length) return false;

    return keysA.every(key => {
      const valsA = a[key];
      const valsB = b[key];
      if (!valsA || !valsB) return false;
      if (valsA.length !== valsB.length) return false;
      return valsA.every((val, i) => val === valsB[i]);
    });
  }

  /**
   * Merges Y.Doc entity data with preserved error state from existing entities.
   * This ensures errors set by errorsObserver survive entity observer updates.
   *
   * When entity observers fire (jobs, triggers, edges), they reconstruct the
   * entity arrays from Y.Doc. This helper preserves the `errors` field from
   * the existing entities to maintain error state set by errorsObserver.
   *
   * @param yjsEntities - Array of Y.Map entities from Y.Doc
   * @param existingEntities - Current entities from Immer state
   * @returns Array of entities with preserved error state
   */
  function mergeWithPreservedErrors<
    T extends { id: string; errors?: Record<string, string[]> },
  >(yjsEntities: Y.Map<unknown>[], existingEntities: T[]): T[] {
    return yjsEntities.map(yjsEntity => {
      const entity = yjsEntity.toJSON() as T;
      const existing = existingEntities.find(e => e.id === entity.id);
      return { ...entity, errors: existing?.errors } as T;
    });
  }

  // Helper to create trigger auth methods handler
  // Extracted for reuse in connect() and reconnection path
  const createTriggerAuthMethodsHandler = (triggersArray: Y.Array<unknown>) => {
    return (payload: unknown) => {
      logger.debug('Received trigger_auth_methods_updated broadcast', payload);

      // Type guard and validation
      if (
        typeof payload === 'object' &&
        payload !== null &&
        'trigger_id' in payload &&
        'webhook_auth_methods' in payload
      ) {
        const { trigger_id, webhook_auth_methods } = payload as {
          trigger_id: string;
          webhook_auth_methods: Array<{
            id: string;
            name: string;
            auth_type: string;
          }>;
        };

        // Update has_auth_method flag in Y.Doc (outside updateState to avoid side effects)
        const triggers = triggersArray.toArray() as Y.Map<unknown>[];
        const triggerIndex = triggers.findIndex(
          t => t.get('id') === trigger_id
        );

        if (triggerIndex >= 0 && ydoc) {
          const yjsTrigger = triggers[triggerIndex];
          const hasAuthMethod = webhook_auth_methods.length > 0;
          ydoc.transact(() => {
            yjsTrigger.set('has_auth_method', hasAuthMethod);
          });
        }

        // Update activeTriggerAuthMethods if this broadcast matches the active trigger
        updateState(draft => {
          if (
            draft.activeTriggerAuthMethods?.trigger_id === trigger_id &&
            Array.isArray(webhook_auth_methods)
          ) {
            draft.activeTriggerAuthMethods = {
              trigger_id,
              webhook_auth_methods,
            };
          }
        }, 'trigger_auth_methods_updated');
      }
    };
  };

  // Connect Y.Doc and set up observers
  const connect = (d: Session.WorkflowDoc, p: PhoenixChannelProvider) => {
    // Clean up previous connection's channel observers
    disconnect();
    if (p.channel === undefined) {
      throw new Error('Provider must have a channel');
    }

    provider = p as PhoenixChannelProvider & { channel: Channel };

    // Check if this is a reconnection (same ydoc) or new connection
    const isReconnection = ydoc === d;
    ydoc = d;

    // Skip observer setup if reconnecting with same ydoc
    // Observers are still attached from previous connection
    if (isReconnection && observerCleanups.length > 0) {
      logger.debug('Reconnecting - Y.Doc observers still active', {
        observerCount: observerCleanups.length,
      });

      // Re-attach channel observer only
      const triggersArray = ydoc.getArray('triggers');
      const triggerAuthMethodsHandler =
        createTriggerAuthMethodsHandler(triggersArray);

      provider.channel.on(
        'trigger_auth_methods_updated',
        triggerAuthMethodsHandler
      );

      // Update channelCleanups reference
      const channelCleanups = [
        () => {
          if (provider?.channel) {
            provider.channel.off(
              'trigger_auth_methods_updated',
              triggerAuthMethodsHandler
            );
          }
        },
      ];

      // Update channel cleanups reference
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (observerCleanups as any).channelCleanups = channelCleanups;

      // Initialize DevTools connection
      devtools.connect();

      // Send reconnection notification
      notify('reconnected');

      return;
    }

    // Get Y.js maps and arrays
    const workflowMap = ydoc.getMap('workflow');
    const jobsArray = ydoc.getArray('jobs');
    const triggersArray = ydoc.getArray('triggers');
    const edgesArray = ydoc.getArray('edges');
    const positionsMap = ydoc.getMap('positions');
    const errorsMap = ydoc.getMap('errors'); // NEW: Get errors map

    // Create UndoManager tracking all workflow collections
    // NOTE: Job body Y.Text instances are intentionally NOT tracked here.
    // Monaco Editor has its own undo/redo (Cmd+Z) that handles text editing.
    // Including job bodies here would create conflicts and lead to jobs being
    // deleted when undoing body edits.
    const undoManager = new Y.UndoManager(
      [workflowMap, jobsArray, triggersArray, edgesArray, positionsMap],
      {
        captureTimeout: 500, // Merge edits within 500ms
        trackedOrigins: new Set([null]), // Track local changes only
      }
    );

    // Set up observers
    const workflowObserver = () => {
      updateState(draft => {
        const workflowData = workflowMap.toJSON() as Session.Workflow;
        draft.workflow = workflowData;

        // Recompute validation errors whenever workflow changes
        draft.validationErrors = validateWorkflowSettings(workflowData);
      }, 'workflow/observerUpdate');
    };

    const jobsObserver = (
      jobs?: Y.YArrayEvent<Y.Map<unknown>>[],
      transaction?: Y.Transaction
    ) => {
      if (jobs && transaction) {
        logger.debug('jobsObserver', {
          jobs,
          transaction,
          sameOrigin: transaction.origin === provider,
        });
      }

      updateState(draft => {
        const yjsJobs = jobsArray.toArray() as Y.Map<unknown>[];
        draft.jobs = mergeWithPreservedErrors(yjsJobs, draft.jobs);
      }, 'jobs/observerUpdate');
    };

    const triggersObserver = () => {
      updateState(draft => {
        const yjsTriggers = triggersArray.toArray() as Y.Map<unknown>[];
        draft.triggers = mergeWithPreservedErrors(yjsTriggers, draft.triggers);
      }, 'triggers/observerUpdate');
    };

    const edgesObserver = () => {
      updateState(draft => {
        const yjsEdges = edgesArray.toArray() as Y.Map<unknown>[];
        draft.edges = mergeWithPreservedErrors(yjsEdges, draft.edges);
      }, 'edges/observerUpdate');
    };

    const positionsObserver = () => {
      updateState(draft => {
        draft.positions = positionsMap.toJSON() as Workflow.Positions;
      }, 'positions/observerUpdate');
    };

    // Enhanced errors observer with denormalization
    // This observer reads the nested error structure from Y.Doc and
    // denormalizes errors directly onto the corresponding entities in
    // the store.
    // Using Immer's structural sharing, only entities with changed errors
    // get new object references, minimizing React re-renders.
    const errorsObserver = () => {
      const errorsJSON = errorsMap.toJSON() as {
        workflow?: Record<string, string[]>;
        jobs?: Record<string, Record<string, string[]>>;
        triggers?: Record<string, Record<string, string[]>>;
        edges?: Record<string, Record<string, string[]>>;
      };

      logger.debug('errorsObserver fired', {
        errorsJSON,
        jobCount: Object.keys(errorsJSON.jobs || {}).length,
        triggerCount: Object.keys(errorsJSON.triggers || {}).length,
        edgeCount: Object.keys(errorsJSON.edges || {}).length,
      });

      updateState(draft => {
        // Extract nested error structures
        const workflowErrors = errorsJSON.workflow || {};
        const jobErrors = errorsJSON.jobs || {};
        const triggerErrors = errorsJSON.triggers || {};
        const edgeErrors = errorsJSON.edges || {};

        // Denormalize workflow errors onto workflow object
        if (draft.workflow) {
          const newErrors = workflowErrors;
          if (!areErrorsEqual(draft.workflow.errors || {}, newErrors)) {
            draft.workflow.errors = newErrors;
          }
        }

        // Efficiently update job errors using Immer
        // Only touches jobs that have changes
        draft.jobs.forEach(job => {
          const newErrors = jobErrors[job.id] || {};
          if (!areErrorsEqual(job.errors || {}, newErrors)) {
            job.errors = newErrors;
          }
        });

        // Same for triggers
        draft.triggers.forEach(trigger => {
          const newErrors = triggerErrors[trigger.id] || {};
          if (!areErrorsEqual(trigger.errors || {}, newErrors)) {
            trigger.errors = newErrors;
          }
        });

        // Same for edges
        draft.edges.forEach(edge => {
          const newErrors = edgeErrors[edge.id] || {};
          if (!areErrorsEqual(edge.errors || {}, newErrors)) {
            edge.errors = newErrors;
          }
        });
      }, 'errors/observerUpdate');
    };

    // Attach observers with deep observation for nested changes
    workflowMap.observeDeep(workflowObserver);
    jobsArray.observeDeep(jobsObserver);
    triggersArray.observeDeep(triggersObserver);
    edgesArray.observeDeep(edgesObserver);
    positionsMap.observeDeep(positionsObserver);
    errorsMap.observeDeep(errorsObserver);

    // Set up channel listener for trigger auth methods updates
    const triggerAuthMethodsHandler =
      createTriggerAuthMethodsHandler(triggersArray);

    provider.channel.on(
      'trigger_auth_methods_updated',
      triggerAuthMethodsHandler
    );

    // Store cleanup functions
    // CRITICAL: Separate Y.Doc observer cleanups from channel cleanups
    // Y.Doc observers must persist during disconnection for offline editing
    // Channel observers only need cleanup when fully destroying the store
    logger.debug('Attaching observers');
    const ydocObserverCleanups = [
      () => workflowMap.unobserveDeep(workflowObserver),
      () => jobsArray.unobserveDeep(jobsObserver),
      () => triggersArray.unobserveDeep(triggersObserver),
      () => edgesArray.unobserveDeep(edgesObserver),
      () => positionsMap.unobserveDeep(positionsObserver),
      () => errorsMap.unobserveDeep(errorsObserver),
    ];

    const channelObserverCleanups = [
      () => {
        if (provider?.channel) {
          provider.channel.off(
            'trigger_auth_methods_updated',
            triggerAuthMethodsHandler
          );
        }
      },
    ];

    // Y.Doc observers persist across disconnection for offline editing
    // Channel observers only cleaned up on disconnect
    observerCleanups = [...ydocObserverCleanups, ...channelObserverCleanups];

    // Store references for disconnect() to selectively clean up
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (observerCleanups as any).ydocCleanups = ydocObserverCleanups;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (observerCleanups as any).channelCleanups = channelObserverCleanups;

    // NOTE: UndoManager cleanup intentionally omitted
    // UndoManager persists during disconnection for offline undo/redo
    // It will be cleaned up only when the entire store is destroyed

    state = produce(state, draft => {
      updateDerivedState(draft);
    });

    // Initial sync from Y.Doc to state - batch all updates
    // This prevents 7 intermediate React renders with incomplete data
    isSyncing = true;
    workflowObserver();
    jobsObserver();
    triggersObserver();
    edgesObserver();
    positionsObserver();
    errorsObserver();

    // Update state with undoManager (still batched)
    updateState(draft => {
      draft.undoManager = undoManager;
    }, 'undoManager/initialized');
    isSyncing = false;

    // Initialize DevTools connection
    devtools.connect();

    // Send initial state - this is the ONLY notification/render
    notify('connected');
  };

  // Disconnect and clean up channel observers only
  // Y.Doc observers persist for offline editing
  const disconnect = () => {
    // Only clean up channel observers (not Y.Doc observers!)
    // Y.Doc observers must remain active for offline editing to work
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const channelCleanups = (observerCleanups as any).channelCleanups || [];
    logger.debug('Cleaning up channel observers only', {
      channelCleanups: channelCleanups.length,
      totalObservers: observerCleanups.length,
    });

    channelCleanups.forEach((cleanup: () => void) => {
      cleanup();
    });

    // Keep ydoc reference alive for offline editing
    // Keep Y.Doc observers alive for offline editing
    // Only null out provider since it's network-dependent
    provider = null;

    // Disconnect DevTools
    devtools.disconnect();

    // Keep undoManager alive - it works offline too
    // Note: undoManager tracks Y.Doc transactions, which work offline
    // We don't reset it here so undo/redo remains functional during disconnection
  };

  // =============================================================================
  // PATTERN 1: Y.Doc → Observer → Immer → Notify (Collaborative Data)
  // =============================================================================
  // These methods update Y.Doc, which triggers observers that update Immer state

  const updateJob = (id: string, updates: Partial<Session.Job>) => {
    const ydoc = ensureYDoc();

    // TODO: parse through zod to throw out extra fields
    // if (!ydoc) {
    //   // Fallback to direct state update if Y.Doc not connected
    //   state = produce(state, draft => {
    //     const job = draft.jobs.find(j => j.id === id);
    //     if (job) {
    //       Object.assign(job, updates);
    //     }
    //     updateDerivedState(draft);
    //   });
    //   notify();
    //   return;
    // }

    const jobsArray = ydoc.getArray('jobs');
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const jobIndex = jobs.findIndex(job => job.get('id') === id);

    if (jobIndex >= 0) {
      const yjsJob = jobs[jobIndex];
      ydoc.transact(() => {
        Object.entries(updates)
          .filter(([key]) => key in JobShape)
          .forEach(([key, value]) => {
            if (key === 'body' && typeof value === 'string') {
              const ytext = yjsJob.get('body') as Y.Text;
              ytext.delete(0, ytext.length);
              ytext.insert(0, value);
            } else {
              yjsJob.set(key, value);
            }
          });
      });
    }

    // Observer handles the rest: Y.Doc → immer → notify
  };

  const updateJobName = (id: string, name: string) => {
    updateJob(id, { name });
  };

  const updateJobBody = (id: string, body: string) => {
    updateJob(id, { body });
  };

  /**
   * Update workflow properties
   *
   * @param updates - Partial workflow properties to update
   *
   * Pattern 1: Y.Doc → Observer → Immer → Notify
   * - Updates workflowMap in Y.Doc
   * - Observer automatically syncs to Immer state
   */
  const updateWorkflow = (
    updates: Partial<
      Omit<Session.Workflow, 'id' | 'lock_version' | 'deleted_at'>
    >
  ) => {
    const ydoc = ensureYDoc();

    const workflowMap = ydoc.getMap('workflow');

    ydoc.transact(() => {
      (
        Object.entries(updates) as [
          keyof typeof updates,
          (typeof updates)[keyof typeof updates],
        ][]
      ).forEach(([key, value]) => {
        if (value !== undefined) {
          workflowMap.set(key, value);
        }
      });
    });

    // Observer handles the rest: Y.Doc → immer → notify
  };

  const addJob = (job: Partial<Session.Job>) => {
    const ydoc = ensureYDoc();
    if (!job.id || !job.name) return;

    const jobsArray = ydoc.getArray('jobs');
    const jobMap = new Y.Map();

    // Default body text shown in the Monaco editor for new jobs
    const defaultBody = `// Check out the Job Writing Guide for help getting started:
// https://docs.openfn.org/documentation/jobs/job-writing-guide
`;

    ydoc.transact(() => {
      jobMap.set('id', job.id);
      jobMap.set('name', job.name);
      // Always initialize body as Y.Text with default if empty
      jobMap.set('body', new Y.Text(job.body || defaultBody));
      // Set adaptor field (defaults to common if not provided)
      jobMap.set('adaptor', job.adaptor);
      // Initialize credential fields to null
      jobMap.set('project_credential_id', job.project_credential_id || null);
      jobMap.set('keychain_credential_id', job.keychain_credential_id || null);

      jobsArray.push([jobMap]);
    });
  };

  const removeJob = (id: string) => {
    const ydoc = ensureYDoc();

    const jobsArray = ydoc.getArray('jobs');
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const jobIndex = jobs.findIndex(job => job.get('id') === id);

    if (jobIndex >= 0) {
      const edgesArray = ydoc.getArray('edges');
      const edges = edgesArray.toArray() as Y.Map<unknown>[];

      // Find all incoming edges (where this job is the target)
      const incomingEdgeIndices = getIncomingEdgeIndices(edges, id);

      ydoc.transact(() => {
        // Delete incoming edges first (highest index to lowest)
        incomingEdgeIndices.forEach(edgeIndex => {
          edgesArray.delete(edgeIndex, 1);
        });

        // Then delete the job
        jobsArray.delete(jobIndex, 1);
      });
    }
    // Observer handles: Y.Doc → Immer → notify
  };

  const addEdge = (edge: Partial<Session.Edge>) => {
    const ydoc = ensureYDoc();
    if (!edge.id || !edge.target_job_id) return;

    const edgesArray = ydoc.getArray('edges');
    const edgeMap = new Y.Map();

    ydoc.transact(() => {
      edgeMap.set('id', edge.id);
      edgeMap.set('source_job_id', edge.source_job_id || null);
      edgeMap.set('source_trigger_id', edge.source_trigger_id || null);
      edgeMap.set('target_job_id', edge.target_job_id);
      edgeMap.set('condition_type', edge.condition_type || 'on_job_success');
      edgeMap.set('condition_label', edge.condition_label || null);
      edgeMap.set('condition_expression', edge.condition_expression || null);
      edgeMap.set('enabled', edge.enabled !== undefined ? edge.enabled : true);
      edgesArray.push([edgeMap]);
    });
  };

  const updateEdge = (id: string, updates: Partial<Session.Edge>) => {
    const ydoc = ensureYDoc();

    const edgesArray = ydoc.getArray('edges');
    const edges = edgesArray.toArray() as Y.Map<unknown>[];
    const edgeIndex = edges.findIndex(edge => edge.get('id') === id);

    if (edgeIndex >= 0) {
      const yjsEdge = edges[edgeIndex];
      if (yjsEdge) {
        ydoc.transact(() => {
          Object.entries(updates)
            .filter(([key]) => key in EdgeShape)
            .forEach(([key, value]) => {
              yjsEdge.set(key, value);
            });
        });
      }
    }
    // Observer handles the rest: Y.Doc → immer → notify
  };

  const removeEdge = (id: string) => {
    const ydoc = ensureYDoc();

    const edgesArray = ydoc.getArray('edges');
    const edges = edgesArray.toArray() as Y.Map<unknown>[];
    const edgeIndex = edges.findIndex(edge => edge.get('id') === id);

    if (edgeIndex >= 0) {
      ydoc.transact(() => {
        edgesArray.delete(edgeIndex, 1);
      });
    }
    // Observer handles: Y.Doc → Immer → notify
  };

  const updateTrigger = (id: string, updates: Partial<Session.Trigger>) => {
    const ydoc = ensureYDoc();

    const triggersArray = ydoc.getArray('triggers');
    const triggers = triggersArray.toArray() as Y.Map<unknown>[];
    const triggerIndex = triggers.findIndex(
      trigger => trigger.get('id') === id
    );

    if (triggerIndex >= 0) {
      const yjsTrigger = triggers[triggerIndex];
      ydoc.transact(() => {
        Object.entries(updates).forEach(([key, value]) => {
          yjsTrigger.set(key, value);
        });
      });
    }
  };

  const setEnabled = (enabled: boolean) => {
    const ydoc = ensureYDoc();

    const triggersArray = ydoc.getArray('triggers');
    const triggers = triggersArray.toArray() as Y.Map<unknown>[];

    ydoc.transact(() => {
      triggers.forEach(trigger => {
        trigger.set('enabled', enabled);
      });
    });
  };

  const getJobBodyYText = (id: string): Y.Text | null => {
    if (!ydoc) return null;

    const jobsArray = ydoc.getArray('jobs');
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const yjsJob = jobs.find(job => job.get('id') === id);

    return yjsJob ? (yjsJob.get('body') as Y.Text) : null;
  };

  const updatePositions = (positions: Workflow.Positions | null) => {
    const ydoc = ensureYDoc();

    const positionsMap = ydoc.getMap('positions');

    ydoc.transact(() => {
      if (positions === null) {
        // Clear all positions to switch to auto layout
        positionsMap.clear();
      } else {
        // Update positions with new values
        Object.entries(positions).forEach(([id, position]) => {
          positionsMap.set(id, position);
        });
      }
    });
  };

  const updatePosition = (id: string, position: { x: number; y: number }) => {
    const ydoc = ensureYDoc();

    const positionsMap = ydoc.getMap('positions');
    ydoc.transact(() => {
      positionsMap.set(id, position);
    });
  };

  /**
   * Set validation errors for an entity or entity field
   *
   * Supports nested paths:
   * - "workflow" → sets workflow-level errors
   * - "jobs.abc-123" → sets all errors for job abc-123
   * - "jobs.abc-123.name" → sets error for specific field
   *   (NOT IMPLEMENTED YET)
   *
   * Pattern 1: Y.Doc → Observer → Immer → Notify
   */
  const setError = (path: string, errors: Record<string, string[]>) => {
    if (!ydoc) throw new Error('Y.Doc not connected');

    logger.debug('setError called', {
      path,
      errors,
      errorCount: Object.keys(errors).length,
      stack: new Error().stack?.split('\n').slice(2, 5).join('\n'),
    });

    const errorsMap = ydoc.getMap('errors');

    // Parse path to determine error location
    const parts = path.split('.');

    // 1. Read current errors from Y.Doc (outside transaction)
    const currentErrors = (() => {
      if (parts.length === 1) {
        // Top-level: "workflow" or entity collection
        return (
          (errorsMap.get(
            path as 'workflow' | 'jobs' | 'triggers' | 'edges'
          ) as Record<string, string[]>) || {}
        );
      } else if (parts.length === 2) {
        // Entity-level: "jobs.abc-123"
        const entityType = parts[0];
        const entityId = parts[1];

        if (!entityId) {
          throw new Error(`Missing entity ID in path: ${path}`);
        }

        // Validate entity type (runtime check for path parsing)
        if (
          entityType !== 'jobs' &&
          entityType !== 'triggers' &&
          entityType !== 'edges'
        ) {
          throw new Error(`Invalid entity type in path: ${entityType}`);
        }

        const entityErrors =
          (errorsMap.get(entityType) as Record<
            string,
            Record<string, string[]>
          >) || {};

        return entityErrors[entityId] || {};
      } else {
        // Field-level not implemented yet - would need more complex structure
        throw new Error(`Unsupported error path: ${path}`);
      }
    })();

    // 2. Check if actually different (avoid unnecessary transactions)
    if (areErrorsEqual(currentErrors, errors)) {
      logger.debug('setError: no changes detected, skipping transaction', {
        path,
      });
      return; // why this causes the issue.
    }

    // 3. Apply changes in transaction
    ydoc.transact(() => {
      if (parts.length === 1) {
        // Top-level: "workflow" or entity collection
        errorsMap.set(
          path as 'workflow' | 'jobs' | 'triggers' | 'edges',
          errors
        );
      } else if (parts.length === 2) {
        // Entity-level: "jobs.abc-123"
        const entityType = parts[0];
        const entityId = parts[1];

        // These are already validated above in currentErrors extraction
        if (!entityId || !entityType) return;

        // Validate entity type (runtime check for path parsing)
        if (
          entityType !== 'jobs' &&
          entityType !== 'triggers' &&
          entityType !== 'edges'
        ) {
          return;
        }

        const entityErrors = errorsMap.get(entityType);
        // Type assertion needed because Y.Map.get returns unknown
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
        const typedEntityErrors = entityErrors as
          | Record<string, Record<string, string[]>>
          | undefined;

        const updatedEntityErrors = {
          ...(typedEntityErrors ?? {}),
          [entityId]: errors,
        };

        errorsMap.set(entityType, updatedEntityErrors);
      }
    });

    // Observer handles the rest: Y.Doc → immer → notify
  };

  /**
   * Set client validation errors with debouncing and replace logic
   *
   * This is the primary method for client-side validation errors (from TanStack Form).
   * Server validation errors should use setError() directly.
   *
   * Features:
   * - Debounced 500ms to avoid excessive Y.Doc updates
   * - REPLACES server errors for touched fields (client takes precedence)
   * - Deduplicates error messages within client errors
   * - Empty array clears field errors
   *
   * Behavior:
   * - When user touches a field with server errors, client errors replace them
   * - When field is valid (empty array), both client and server errors are cleared
   * - When field has client errors, only client errors are shown
   * - Server can re-validate on save and overwrite client errors
   *
   * Pattern 1: Y.Doc → Observer → Immer → Notify (after debounce)
   *
   * @param path - Dot-separated path (e.g., "workflow", "jobs.abc-123")
   * @param errors - Field errors { fieldName: ["error1", "error2"] }
   *                 Empty array [] clears that field
   */
  const setClientErrors = (
    path: string,
    errors: Record<string, string[]>,
    isEditing: boolean
  ) => {
    // Capture isEditing value at call time for the debounced execution

    logger.debug('setClientErrors called (before debounce)', {
      path,
      errors,
      errorCount: Object.keys(errors).length,
      stack: new Error(),
    });

    // Set new debounced timeout
    logger.debug('setClientErrors executing (after debounce)', {
      path,
      errors,
    });

    if (!ydoc) {
      logger.warn('Cannot set client errors: Y.Doc not connected');
      return;
    }

    const errorsMap = ydoc.getMap('errors');
    const parts = path.split('.');

    // 1. Read current errors from Y.Doc (outside transaction)
    const currentErrors = (() => {
      if (parts.length === 1 || !path) {
        // Top-level: "workflow"
        const entityKey = path || 'workflow';
        const errors = errorsMap.get(
          entityKey as 'workflow' | 'jobs' | 'triggers' | 'edges'
        ) as Record<string, string[]> | undefined;
        return errors ?? {};
      } else if (parts.length === 2) {
        // Entity-level: "jobs.abc-123"
        const entityType = parts[0];
        const entityId = parts[1];

        if (!entityId || !entityType) return {};

        // Validate entity type (runtime check for path parsing)
        if (
          entityType !== 'jobs' &&
          entityType !== 'triggers' &&
          entityType !== 'edges'
        ) {
          return {};
        }

        const entityErrors = errorsMap.get(entityType);
        // Type assertion needed because Y.Map.get returns unknown
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
        const typedEntityErrors = entityErrors as
          | Record<string, Record<string, string[]>>
          | undefined;

        return typedEntityErrors?.[entityId] ?? {};
      }
      return {};
    })();

    logger.debug('setClientErrors before merge', {
      path,
      currentErrors,
      incomingErrors: errors,
    });

    // 2. Use Immer to replace client errors (or clear if empty)
    // Client errors REPLACE server errors for that field, not merge with them
    // This ensures that when a user edits a field with server errors,
    // their client validation takes precedence
    const mergedErrors = isEditing
      ? produce(currentErrors, draft => {
          Object.entries(errors).forEach(([fieldName, newMessages]) => {
            if (newMessages.length === 0) {
              // Empty array clears the field
              delete draft[fieldName];
            } else {
              // Replace with client errors (deduplicate within client errors)
              draft[fieldName] = Array.from(new Set(newMessages));
            }
          });
        })
      : currentErrors;

    logger.debug('setClientErrors after merge', {
      path,
      mergedErrors,
      mergedCount: Object.keys(mergedErrors).length,
    });

    // 3. Write to Y.Doc using setError (which checks if different before transacting)
    try {
      setError(path || 'workflow', mergedErrors);
    } catch (error) {
      logger.error('Failed to set client errors', { path, error });
    }
  };

  // =============================================================================
  // PATTERN 3: Direct Immer → Notify (Local UI State)
  // =============================================================================
  // These methods directly update Immer state without Y.Doc involvement

  const selectJob = (id: string | null) => {
    updateState(draft => {
      draft.selectedJobId = id;
      draft.selectedTriggerId = null;
      draft.selectedEdgeId = null;
    }, 'selectJob');
  };

  const selectTrigger = (id: string | null) => {
    updateState(draft => {
      draft.selectedTriggerId = id;
      draft.selectedJobId = null;
      draft.selectedEdgeId = null;
    }, 'selectTrigger');
  };

  const selectEdge = (id: string | null) => {
    updateState(draft => {
      draft.selectedEdgeId = id;
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
    }, 'selectEdge');
  };

  const clearSelection = () => {
    updateState(draft => {
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
      draft.selectedEdgeId = null;
    }, 'clearSelection');
  };

  const saveWorkflow = async (): Promise<{
    saved_at?: string;
    lock_version?: number;
  } | null> => {
    const { ydoc, provider } = ensureConnected();

    const workflow = ydoc.getMap('workflow').toJSON();

    const jobs = ydoc.getArray('jobs').toJSON();
    const triggers = ydoc.getArray('triggers').toJSON();
    const edges = ydoc.getArray('edges').toJSON();
    const positions = ydoc.getMap('positions').toJSON();

    const payload = {
      ...workflow,
      jobs,
      triggers,
      edges,
      positions,
    };

    logger.debug('Saving workflow', payload);

    try {
      const response = await channelRequest<{
        saved_at: string;
        lock_version: number;
      }>(provider.channel, 'save_workflow', payload);

      logger.debug('Saved workflow', response);

      return response;
    } catch (error) {
      logger.error('Failed to save workflow', error);
      throw error;
    }
  };

  const saveAndSyncWorkflow = async (
    commitMessage: string
  ): Promise<{
    saved_at?: string;
    lock_version?: number;
    repo?: string;
  } | null> => {
    const { ydoc, provider } = ensureConnected();

    const workflow = ydoc.getMap('workflow').toJSON();

    const jobs = ydoc.getArray('jobs').toJSON();
    const triggers = ydoc.getArray('triggers').toJSON();
    const edges = ydoc.getArray('edges').toJSON();
    const positions = ydoc.getMap('positions').toJSON();

    const payload = {
      ...workflow,
      jobs,
      triggers,
      edges,
      positions,
      commit_message: commitMessage,
    };

    logger.debug('Saving and syncing workflow to GitHub', payload);

    try {
      const response = await channelRequest<{
        saved_at: string;
        lock_version: number;
        repo: string;
      }>(provider.channel, 'save_and_sync', payload);

      logger.debug('Saved and synced workflow to GitHub', response);

      return response;
    } catch (error) {
      logger.error('Failed to save and sync workflow', error);
      throw error;
    }
  };

  const resetWorkflow = async (): Promise<void> => {
    const { provider } = ensureConnected();

    logger.debug('Resetting workflow');

    try {
      const response = await channelRequest<{
        lock_version: number;
        workflow_id: string;
      }>(provider.channel, 'reset_workflow', {});

      // Y.Doc will automatically update from server broadcast
      logger.debug('Reset workflow successfully', response);
    } catch (error) {
      logger.error('Failed to reset workflow', error);
      throw error;
    }
  };

  /**
   * Validate workflow name uniqueness via Phoenix Channel
   *
   * Sends workflow name to server for validation and receives a
   * guaranteed unique name back. The server applies the same
   * uniqueness logic used in the LiveView path.
   *
   * @param workflowState - Workflow state with name to validate
   * @returns Promise resolving to workflow state with unique name
   */
  const validateWorkflowName = async (
    workflowState: YAMLWorkflowState
  ): Promise<YAMLWorkflowState> => {
    if (!provider) {
      logger.warn('No provider available for name validation');
      return workflowState;
    }

    try {
      const response = await channelRequest<{ workflow: { name: string } }>(
        provider.channel,
        'validate_workflow_name',
        { workflow: { name: workflowState.name } }
      );

      logger.debug('Validated workflow name', {
        original: workflowState.name,
        validated: response.workflow.name,
      });

      // Return state with validated unique name
      return {
        ...workflowState,
        name: response.workflow.name,
      };
    } catch (error) {
      logger.error('Failed to validate workflow name', error);
      throw error;
    }
  };

  /**
   * Import workflow from YAML WorkflowState
   *
   * Uses Pattern 1 (Y.Doc → Observer → Immer):
   * - Single transact() for atomic bulk updates
   * - Observers automatically sync Immer state
   * - No manual notify() calls needed
   *
   * @param workflowState - Parsed YAML workflow state
   */
  const importWorkflow = (workflowState: YAMLWorkflowState) => {
    const ydoc = ensureYDoc();

    try {
      // Use adapter to apply transformations and update Y.Doc
      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      logger.info('Workflow imported successfully', {
        workflowId: workflowState.id,
        jobs: workflowState.jobs.length,
        triggers: workflowState.triggers.length,
        edges: workflowState.edges.length,
      });

      // Note: Observers will automatically trigger Immer updates and notify React
    } catch (error) {
      logger.error('Failed to import workflow', error);
      throw error;
    }
  };

  // =============================================================================
  // PATTERN 2: Y.Doc + Immediate Immer → Notify (Hybrid Operations)
  // =============================================================================
  // These methods combine Y.Doc updates with immediate local state updates
  // Use sparingly - consider if Pattern 1 or 3 alone would be better

  const removeJobAndClearSelection = (id: string) => {
    // Update Y.Doc first
    removeJob(id);

    // Immediately clear selection if this job was selected
    updateState(draft => {
      if (draft.selectedJobId === id) {
        draft.selectedJobId = null;
      }
    }, 'removeJobAndClearSelection');

    // Note: Y.Doc observer will also fire and update the jobs array
  };

  // =============================================================================
  // Trigger Auth Methods Management (Pattern 3 - Local State)
  // =============================================================================

  const requestTriggerAuthMethods = async (triggerId: string) => {
    if (!provider?.channel) {
      logger.warn('Cannot request trigger auth methods - no channel available');
      return;
    }

    try {
      const response = await channelRequest(
        provider.channel,
        'request_trigger_auth_methods',
        { trigger_id: triggerId }
      );

      if (
        response &&
        typeof response === 'object' &&
        'trigger_id' in response &&
        'webhook_auth_methods' in response
      ) {
        updateState(draft => {
          draft.activeTriggerAuthMethods = response as {
            trigger_id: string;
            webhook_auth_methods: Array<{
              id: string;
              name: string;
              auth_type: string;
            }>;
          };
        }, 'requestTriggerAuthMethods');
      }
    } catch (error) {
      logger.error('Failed to request trigger auth methods', error);
    }
  };

  // Undo/Redo Commands
  // =============================================================================
  // These commands trigger Y.Doc changes via UndoManager, which then flow
  // through the normal observer pattern (Pattern 1)
  //
  // Note: UndoManager tracks local changes only (trackedOrigins: new Set([null])).
  // Remote changes from other collaborators are NOT undoable by this client,
  // since they represent other users' intentional actions.

  const undo = () => {
    const undoManager = state.undoManager;
    if (undoManager && undoManager.undoStack.length > 0) {
      undoManager.undo();
    }
  };

  const redo = () => {
    const undoManager = state.undoManager;
    if (undoManager && undoManager.redoStack.length > 0) {
      undoManager.redo();
    }
  };

  const canUndo = (): boolean => {
    const undoManager = state.undoManager;
    return undoManager ? undoManager.undoStack.length > 0 : false;
  };

  const canRedo = (): boolean => {
    const undoManager = state.undoManager;
    return undoManager ? undoManager.redoStack.length > 0 : false;
  };

  const clearHistory = () => {
    const undoManager = state.undoManager;
    if (undoManager) {
      undoManager.clear();
    }
  };

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Y.Doc connection management
    connect,
    disconnect,
    get isConnected() {
      return ydoc !== null;
    },
    get ydoc() {
      return ydoc;
    },

    // =============================================================================
    // PATTERN 1: Y.Doc → Observer → Immer → Notify (Collaborative Data)
    // =============================================================================
    updateJob,
    updateJobName,
    updateJobBody,
    updateWorkflow,
    addJob,
    removeJob,
    addEdge,
    updateEdge,
    removeEdge,
    updateTrigger,
    setEnabled,
    getJobBodyYText,
    updatePositions,
    updatePosition,
    importWorkflow,
    setError,
    setClientErrors,

    // =============================================================================
    // PATTERN 2: Y.Doc + Immediate Immer → Notify (Hybrid Operations - Use Sparingly)
    // =============================================================================
    removeJobAndClearSelection,

    // =============================================================================
    // PATTERN 3: Direct Immer → Notify (Local UI State)
    // =============================================================================
    selectJob,
    selectTrigger,
    selectEdge,
    clearSelection,
    saveWorkflow,
    saveAndSyncWorkflow,
    resetWorkflow,
    validateWorkflowName,

    // Trigger auth methods
    requestTriggerAuthMethods,
    // =============================================================================
    // Undo/Redo Commands
    // =============================================================================
    undo,
    redo,
    canUndo,
    canRedo,
    clearHistory,
  };
};

export type WorkflowStoreInstance = ReturnType<typeof createWorkflowStore>;
