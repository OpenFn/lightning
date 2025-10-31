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

import { produce } from "immer";
import type { Channel } from "phoenix";
import type { PhoenixChannelProvider } from "y-phoenix-channel";
import * as Y from "yjs";

import _logger from "#/utils/logger";

import type { WorkflowState as YAMLWorkflowState } from "../../yaml/types";
import { YAMLStateToYDoc } from "../adapters/YAMLStateToYDoc";
import { channelRequest } from "../hooks/useChannel";
import { EdgeSchema } from "../types/edge";
import { JobSchema } from "../types/job";
import type { Session } from "../types/session";
import type { Workflow } from "../types/workflow";

import { createWithSelector } from "./common";
import { wrapStoreWithDevTools } from "./devtools";

const logger = _logger.ns("WorkflowStore").seal();

const JobShape = JobSchema.shape;
const EdgeShape = EdgeSchema.shape;
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

      // Initialize UI state
      selectedJobId: null,
      selectedTriggerId: null,
      selectedEdgeId: null,

      // Initialize computed state
      enabled: null,
      selectedNode: null,
      selectedEdge: null,
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

  let state = produceInitialState();

  const listeners = new Set<() => void>();

  // Redux DevTools integration (development/test only)
  const devtools = wrapStoreWithDevTools<Workflow.State>({
    name: "WorkflowStore",
    excludeKeys: ["ydoc", "provider"], // Exclude Y.Doc and provider (too large/circular)
    maxAge: 200, // Higher limit to prevent history loss from frequent updates
    trace: false,
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
        "Cannot modify workflow: Y.Doc not connected. " +
          "This is likely a bug - mutations should not be called before sync."
      );
    }
    return { ydoc, provider };
  };

  const notify = (actionName: string = "stateChange") => {
    logger.debug("notify", {
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
    actionName: string = "updateState"
  ) => {
    const nextState = produce(state, draft => {
      updater(draft);
      updateDerivedState(draft);
    });
    if (nextState !== lastState) {
      lastState = nextState;
      state = nextState;
      notify(actionName);
    }
  };

  // Returns the current Immer state (referentially stable)
  const getSnapshot = (): Workflow.State => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  // Connect Y.Doc and set up observers
  const connect = (d: Session.WorkflowDoc, p: PhoenixChannelProvider) => {
    // Clean up previous connection
    disconnect();
    if (p.channel === undefined) {
      throw new Error("Provider must have a channel");
    }

    provider = p as PhoenixChannelProvider & { channel: Channel };
    ydoc = d;

    // Get Y.js maps and arrays
    const workflowMap = ydoc.getMap("workflow");
    const jobsArray = ydoc.getArray("jobs");
    const triggersArray = ydoc.getArray("triggers");
    const edgesArray = ydoc.getArray("edges");
    const positionsMap = ydoc.getMap("positions");
    const errorsMap = ydoc.getMap("errors"); // NEW: Get errors map

    // Set up observers
    const workflowObserver = () => {
      updateState(draft => {
        draft.workflow = workflowMap.toJSON() as Session.Workflow;
      }, "workflow/observerUpdate");
    };

    const jobsObserver = (
      jobs?: Y.YArrayEvent<Y.Map<unknown>>[],
      transaction?: Y.Transaction
    ) => {
      if (jobs && transaction) {
        logger.debug("jobsObserver", {
          jobs,
          transaction,
          sameOrigin: transaction.origin === provider,
        });
      }
      updateState(draft => {
        const yjsJobs = jobsArray.toArray() as Y.Map<unknown>[];
        draft.jobs = yjsJobs.map(yjsJob => yjsJob.toJSON() as Workflow.Job);
      }, "jobs/observerUpdate");
    };

    const triggersObserver = () => {
      updateState(draft => {
        const yjsTriggers = triggersArray.toArray() as Y.Map<unknown>[];
        draft.triggers = yjsTriggers.map(
          yjsTrigger => yjsTrigger.toJSON() as Workflow.Trigger
        );
      }, "triggers/observerUpdate");
    };

    const edgesObserver = () => {
      updateState(draft => {
        const yjsEdges = edgesArray.toArray() as Y.Map<unknown>[];
        draft.edges = yjsEdges.map(
          yjsEdge => yjsEdge.toJSON() as Workflow.Edge
        );
      }, "edges/observerUpdate");
    };

    const positionsObserver = () => {
      updateState(draft => {
        draft.positions = positionsMap.toJSON() as Workflow.Positions;
      }, "positions/observerUpdate");
    };

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
        if (!valsB) return false;
        if (valsA.length !== valsB.length) return false;
        return valsA.every((val, i) => val === valsB[i]);
      });
    }

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
      }, "errors/observerUpdate");
    };

    // Attach observers with deep observation for nested changes
    workflowMap.observeDeep(workflowObserver);
    jobsArray.observeDeep(jobsObserver);
    triggersArray.observeDeep(triggersObserver);
    edgesArray.observeDeep(edgesObserver);
    positionsMap.observeDeep(positionsObserver);
    errorsMap.observeDeep(errorsObserver); // NEW: Attach errors observer

    // Store cleanup functions
    logger.debug("Attaching observers");
    observerCleanups = [
      () => workflowMap.unobserveDeep(workflowObserver),
      () => jobsArray.unobserveDeep(jobsObserver),
      () => triggersArray.unobserveDeep(triggersObserver),
      () => edgesArray.unobserveDeep(edgesObserver),
      () => positionsMap.unobserveDeep(positionsObserver),
      () => errorsMap.unobserveDeep(errorsObserver), // NEW: Cleanup function
    ];

    state = produce(state, draft => {
      updateDerivedState(draft);
    });

    // Initial sync from Y.Doc to state
    workflowObserver();
    jobsObserver();
    triggersObserver();
    edgesObserver();
    positionsObserver();
    errorsObserver(); // NEW: Initial sync

    // Initialize DevTools connection
    devtools.connect();

    // Send initial state
    notify("connected");
  };

  // Disconnect Y.Doc and clean up observers
  const disconnect = () => {
    logger.debug("Cleaning up observers", observerCleanups.length);
    observerCleanups.forEach(cleanup => {
      cleanup();
    });
    observerCleanups = [];
    ydoc = null;
    provider = null;

    // Disconnect DevTools
    devtools.disconnect();

    // Update collaboration status
    updateState(_draft => {}, "disconnected");
  };

  // =============================================================================
  // PATTERN 1: Y.Doc → Observer → Immer → Notify (Collaborative Data)
  // =============================================================================
  // These methods update Y.Doc, which triggers observers that update Immer state

  const updateJob = (id: string, updates: Partial<Session.Job>) => {
    const { ydoc } = ensureConnected();

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

    const jobsArray = ydoc.getArray("jobs");
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const jobIndex = jobs.findIndex(job => job.get("id") === id);

    if (jobIndex >= 0) {
      const yjsJob = jobs[jobIndex];
      ydoc.transact(() => {
        Object.entries(updates)
          .filter(([key]) => key in JobShape)
          .forEach(([key, value]) => {
            if (key === "body" && typeof value === "string") {
              const ytext = yjsJob.get("body") as Y.Text;
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
      Omit<Session.Workflow, "id" | "lock_version" | "deleted_at">
    >
  ) => {
    const { ydoc } = ensureConnected();

    const workflowMap = ydoc.getMap("workflow");

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
    const { ydoc } = ensureConnected();
    if (!job.id || !job.name) return;

    const jobsArray = ydoc.getArray("jobs");
    const jobMap = new Y.Map();

    // Default body text shown in the Monaco editor for new jobs
    const defaultBody = `// Check out the Job Writing Guide for help getting started:
// https://docs.openfn.org/documentation/jobs/job-writing-guide
`;

    ydoc.transact(() => {
      jobMap.set("id", job.id);
      jobMap.set("name", job.name);
      // Always initialize body as Y.Text with default if empty
      jobMap.set("body", new Y.Text(job.body || defaultBody));
      // Set adaptor field (defaults to common if not provided)
      jobMap.set("adaptor", job.adaptor);
      // Initialize credential fields to null
      jobMap.set("project_credential_id", job.project_credential_id || null);
      jobMap.set("keychain_credential_id", job.keychain_credential_id || null);

      jobsArray.push([jobMap]);
    });
  };

  const removeJob = (id: string) => {
    const { ydoc } = ensureConnected();

    const jobsArray = ydoc.getArray("jobs");
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const jobIndex = jobs.findIndex(job => job.get("id") === id);

    if (jobIndex >= 0) {
      ydoc.transact(() => {
        jobsArray.delete(jobIndex, 1);
      });
    }
  };

  const addEdge = (edge: Partial<Session.Edge>) => {
    const { ydoc } = ensureConnected();
    if (!edge.id || !edge.target_job_id) return;

    const edgesArray = ydoc.getArray("edges");
    const edgeMap = new Y.Map();

    ydoc.transact(() => {
      edgeMap.set("id", edge.id);
      edgeMap.set("source_job_id", edge.source_job_id || null);
      edgeMap.set("source_trigger_id", edge.source_trigger_id || null);
      edgeMap.set("target_job_id", edge.target_job_id);
      edgeMap.set("condition_type", edge.condition_type || "on_job_success");
      edgeMap.set("condition_label", edge.condition_label || null);
      edgeMap.set("condition_expression", edge.condition_expression || null);
      edgeMap.set("enabled", edge.enabled !== undefined ? edge.enabled : true);
      edgesArray.push([edgeMap]);
    });
  };

  const updateEdge = (id: string, updates: Partial<Session.Edge>) => {
    const { ydoc } = ensureConnected();

    const edgesArray = ydoc.getArray("edges");
    const edges = edgesArray.toArray() as Y.Map<unknown>[];
    const edgeIndex = edges.findIndex(edge => edge.get("id") === id);

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
    const { ydoc } = ensureConnected();

    const edgesArray = ydoc.getArray("edges");
    const edges = edgesArray.toArray() as Y.Map<unknown>[];
    const edgeIndex = edges.findIndex(edge => edge.get("id") === id);

    if (edgeIndex >= 0) {
      ydoc.transact(() => {
        edgesArray.delete(edgeIndex, 1);
      });
    }
    // Observer handles: Y.Doc → Immer → notify
  };

  const updateTrigger = (id: string, updates: Partial<Session.Trigger>) => {
    const { ydoc } = ensureConnected();

    const triggersArray = ydoc.getArray("triggers");
    const triggers = triggersArray.toArray() as Y.Map<unknown>[];
    const triggerIndex = triggers.findIndex(
      trigger => trigger.get("id") === id
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
    const { ydoc } = ensureConnected();

    const triggersArray = ydoc.getArray("triggers");
    const triggers = triggersArray.toArray() as Y.Map<unknown>[];

    ydoc.transact(() => {
      triggers.forEach(trigger => {
        trigger.set("enabled", enabled);
      });
    });
  };

  const getJobBodyYText = (id: string): Y.Text | null => {
    if (!ydoc) return null;

    const jobsArray = ydoc.getArray("jobs");
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const yjsJob = jobs.find(job => job.get("id") === id);

    return yjsJob ? (yjsJob.get("body") as Y.Text) : null;
  };

  const updatePositions = (positions: Workflow.Positions | null) => {
    const { ydoc } = ensureConnected();

    const positionsMap = ydoc.getMap("positions");

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
    const { ydoc } = ensureConnected();

    const positionsMap = ydoc.getMap("positions");
    ydoc.transact(() => {
      positionsMap.set(id, position);
    });
  };

  /**
   * Clear a specific validation error
   *
   * Pattern 1: Y.Doc → Observer → Immer → Notify
   * - Removes error key from errorsMap in Y.Doc
   * - Observer automatically syncs to Immer state
   */
  const clearError = (key: string) => {
    if (!ydoc) {
      throw new Error("Y.Doc not connected");
    }

    const errorsMap = ydoc.getMap("errors");

    ydoc.transact(() => {
      errorsMap.delete(key);
    });

    // Observer handles the rest: Y.Doc → immer → notify
  };

  /**
   * Clear all validation errors
   *
   * Pattern 1: Y.Doc → Observer → Immer → Notify
   * - Clears all keys from errorsMap in Y.Doc
   * - Observer automatically syncs to Immer state
   */
  const clearAllErrors = () => {
    if (!ydoc) {
      throw new Error("Y.Doc not connected");
    }

    const errorsMap = ydoc.getMap("errors");

    ydoc.transact(() => {
      // Get all keys and delete them
      const keys = Array.from(errorsMap.keys());
      keys.forEach(key => errorsMap.delete(key));
    });

    // Observer handles the rest: Y.Doc → immer → notify
  };

  /**
   * Set a validation error (for testing purposes)
   *
   * Pattern 1: Y.Doc → Observer → Immer → Notify
   * - Sets error key in errorsMap in Y.Doc
   * - Observer automatically syncs to Immer state
   *
   * Note: In production, errors are set by the server during save
   * validation
   */
  const setError = (key: string, messages: string[]) => {
    if (!ydoc) {
      throw new Error("Y.Doc not connected");
    }

    const errorsMap = ydoc.getMap("errors");

    ydoc.transact(() => {
      errorsMap.set(key, messages);
    });

    // Observer handles the rest: Y.Doc → immer → notify
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
    }, "selectJob");
  };

  const selectTrigger = (id: string | null) => {
    updateState(draft => {
      draft.selectedTriggerId = id;
      draft.selectedJobId = null;
      draft.selectedEdgeId = null;
    }, "selectTrigger");
  };

  const selectEdge = (id: string | null) => {
    updateState(draft => {
      draft.selectedEdgeId = id;
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
    }, "selectEdge");
  };

  const clearSelection = () => {
    updateState(draft => {
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
      draft.selectedEdgeId = null;
    }, "clearSelection");
  };

  const saveWorkflow = async (): Promise<{
    saved_at?: string;
    lock_version?: number;
  } | null> => {
    const { ydoc, provider } = ensureConnected();

    const workflow = ydoc.getMap("workflow").toJSON();

    const jobs = ydoc.getArray("jobs").toJSON();
    const triggers = ydoc.getArray("triggers").toJSON();
    const edges = ydoc.getArray("edges").toJSON();
    const positions = ydoc.getMap("positions").toJSON();

    const payload = {
      ...workflow,
      jobs,
      triggers,
      edges,
      positions,
    };

    logger.debug("Saving workflow", payload);

    try {
      const response = await channelRequest<{
        saved_at: string;
        lock_version: number;
      }>(provider.channel, "save_workflow", payload);

      logger.debug("Saved workflow", response);

      return response;
    } catch (error) {
      logger.error("Failed to save workflow", error);
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

    const workflow = ydoc.getMap("workflow").toJSON();

    const jobs = ydoc.getArray("jobs").toJSON();
    const triggers = ydoc.getArray("triggers").toJSON();
    const edges = ydoc.getArray("edges").toJSON();
    const positions = ydoc.getMap("positions").toJSON();

    const payload = {
      ...workflow,
      jobs,
      triggers,
      edges,
      positions,
      commit_message: commitMessage,
    };

    logger.debug("Saving and syncing workflow to GitHub", payload);

    try {
      const response = await channelRequest<{
        saved_at: string;
        lock_version: number;
        repo: string;
      }>(provider.channel, "save_and_sync", payload);

      logger.debug("Saved and synced workflow to GitHub", response);

      return response;
    } catch (error) {
      logger.error("Failed to save and sync workflow", error);
      throw error;
    }
  };

  const resetWorkflow = async (): Promise<void> => {
    const { provider } = ensureConnected();

    logger.debug("Resetting workflow");

    try {
      const response = await channelRequest<{
        lock_version: number;
        workflow_id: string;
      }>(provider.channel, "reset_workflow", {});

      // Y.Doc will automatically update from server broadcast
      logger.debug("Reset workflow successfully", response);
    } catch (error) {
      logger.error("Failed to reset workflow", error);
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
      logger.warn("No provider available for name validation");
      return workflowState;
    }

    try {
      const response = await channelRequest<{ workflow: { name: string } }>(
        provider.channel,
        "validate_workflow_name",
        { workflow: { name: workflowState.name } }
      );

      logger.debug("Validated workflow name", {
        original: workflowState.name,
        validated: response.workflow.name,
      });

      // Return state with validated unique name
      return {
        ...workflowState,
        name: response.workflow.name,
      };
    } catch (error) {
      logger.error("Failed to validate workflow name", error);
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
    const { ydoc } = ensureConnected();

    try {
      // Use adapter to apply transformations and update Y.Doc
      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      logger.info("Workflow imported successfully", {
        workflowId: workflowState.id,
        jobs: workflowState.jobs.length,
        triggers: workflowState.triggers.length,
        edges: workflowState.edges.length,
      });

      // Note: Observers will automatically trigger Immer updates and notify React
    } catch (error) {
      logger.error("Failed to import workflow", error);
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
    }, "removeJobAndClearSelection");

    // Note: Y.Doc observer will also fire and update the jobs array
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
    clearError,
    clearAllErrors,

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
  };
};

export type WorkflowStoreInstance = ReturnType<typeof createWorkflowStore>;
