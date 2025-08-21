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
 * @see ../contexts/WorkflowStoreProvider.tsx for provider setup
 */

import { produce } from "immer";
import * as Y from "yjs";

import { JobSchema } from "../types/job";
import type { Session } from "../types/session";
import type { Workflow } from "../types/workflow";

import { createWithSelector } from "./common";

const JobShape = JobSchema.shape;

export const createWorkflowStore = () => {
  // Y.Doc will be connected externally via SessionProvider
  let ydoc: Session.WorkflowDoc | null = null;
  let observerCleanups: (() => void)[] = [];

  // Helper to update derived state (defined first to avoid hoisting issues)
  const updateDerivedState = (draft: Workflow.State) => {
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
  };

  // Single Immer-managed state object (referentially stable)
  let state: Workflow.State = produce(
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

  const listeners = new Set<() => void>();

  const notify = () => {
    listeners.forEach(listener => {
      listener();
    });
  };

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  // Returns the current Immer state (referentially stable)
  const getSnapshot = (): Workflow.State => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  // Connect Y.Doc and set up observers
  const connectYDoc = (doc: Session.WorkflowDoc) => {
    // Clean up previous connection
    disconnectYDoc();

    ydoc = doc;

    // Get Y.js maps and arrays
    const workflowMap = ydoc.getMap("workflow");
    const jobsArray = ydoc.getArray("jobs");
    const triggersArray = ydoc.getArray("triggers");
    const edgesArray = ydoc.getArray("edges");
    const positionsMap = ydoc.getMap("positions");

    // Set up observers
    const workflowObserver = () => {
      state = produce(state, draft => {
        draft.workflow = workflowMap.toJSON() as Session.Workflow;
        updateDerivedState(draft);
      });
      notify();
    };

    const jobsObserver = () => {
      state = produce(state, draft => {
        const yjsJobs = jobsArray.toArray() as Y.Map<unknown>[];
        draft.jobs = yjsJobs.map(yjsJob => yjsJob.toJSON() as Workflow.Job);
        updateDerivedState(draft);
      });
      notify();
    };

    const triggersObserver = () => {
      state = produce(state, draft => {
        const yjsTriggers = triggersArray.toArray() as Y.Map<unknown>[];
        draft.triggers = yjsTriggers.map(
          yjsTrigger => yjsTrigger.toJSON() as Workflow.Trigger
        );
        updateDerivedState(draft);
      });
      notify();
    };

    const edgesObserver = () => {
      state = produce(state, draft => {
        const yjsEdges = edgesArray.toArray() as Y.Map<unknown>[];
        draft.edges = yjsEdges.map(
          yjsEdge => yjsEdge.toJSON() as Workflow.Edge
        );
        updateDerivedState(draft);
      });
      notify();
    };

    const positionsObserver = () => {
      state = produce(state, draft => {
        draft.positions = positionsMap.toJSON() as Workflow.Positions;
        updateDerivedState(draft);
      });
      notify();
    };

    // Attach observers with deep observation for nested changes
    workflowMap.observeDeep(workflowObserver);
    jobsArray.observeDeep(jobsObserver);
    triggersArray.observeDeep(triggersObserver);
    edgesArray.observeDeep(edgesObserver);
    positionsMap.observeDeep(positionsObserver);

    // Store cleanup functions
    observerCleanups = [
      () => workflowMap.unobserveDeep(workflowObserver),
      () => jobsArray.unobserveDeep(jobsObserver),
      () => triggersArray.unobserveDeep(triggersObserver),
      () => edgesArray.unobserveDeep(edgesObserver),
      () => positionsMap.unobserveDeep(positionsObserver),
    ];

    state = produce(state, draft => {
      updateDerivedState(draft);
    });
    notify();

    // Initial sync from Y.Doc to state
    workflowObserver();
    jobsObserver();
    triggersObserver();
    edgesObserver();
    positionsObserver();
  };

  // Disconnect Y.Doc and clean up observers
  const disconnectYDoc = () => {
    observerCleanups.forEach(cleanup => {
      cleanup();
    });
    observerCleanups = [];
    ydoc = null;

    // Update collaboration status
    state = produce(state, draft => {
      updateDerivedState(draft);
    });
    notify();
  };

  // =============================================================================
  // PATTERN 1: Y.Doc → Observer → Immer → Notify (Collaborative Data)
  // =============================================================================
  // These methods update Y.Doc, which triggers observers that update Immer state

  const updateJob = (id: string, updates: Partial<Session.Job>) => {
    // TODO: parse through zod to throw out extra fields
    if (!ydoc) {
      // Fallback to direct state update if Y.Doc not connected
      state = produce(state, draft => {
        const job = draft.jobs.find(j => j.id === id);
        if (job) {
          Object.assign(job, updates);
        }
        updateDerivedState(draft);
      });
      notify();
      return;
    }

    const jobsArray = ydoc.getArray("jobs");
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const jobIndex = jobs.findIndex(job => job.get("id") === id);

    if (jobIndex >= 0) {
      const yjsJob = jobs[jobIndex];
      if (yjsJob) {
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
    }

    // Observer handles the rest: Y.Doc → immer → notify
  };

  const updateJobName = (id: string, name: string) => {
    updateJob(id, { name });
  };

  const updateJobBody = (id: string, body: string) => {
    updateJob(id, { body });
  };

  const addJob = (job: Partial<Session.Job>) => {
    if (!ydoc || !job.id || !job.name) return;

    const jobsArray = ydoc.getArray("jobs");
    const jobMap = new Y.Map();

    ydoc.transact(() => {
      jobMap.set("id", job.id);
      jobMap.set("name", job.name);
      if (job.body) {
        jobMap.set("body", new Y.Text(job.body));
      }
      jobsArray.push([jobMap]);
    });
  };

  const removeJob = (id: string) => {
    if (!ydoc) return;

    const jobsArray = ydoc.getArray("jobs");
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const jobIndex = jobs.findIndex(job => job.get("id") === id);

    if (jobIndex >= 0) {
      ydoc.transact(() => {
        jobsArray.delete(jobIndex, 1);
      });
    }
  };

  const updateTrigger = (id: string, updates: Partial<Session.Trigger>) => {
    if (!ydoc) return;

    const triggersArray = ydoc.getArray("triggers");
    const triggers = triggersArray.toArray() as Y.Map<unknown>[];
    const triggerIndex = triggers.findIndex(
      trigger => trigger.get("id") === id
    );

    if (triggerIndex >= 0) {
      const yjsTrigger = triggers[triggerIndex];
      if (yjsTrigger) {
        ydoc.transact(() => {
          Object.entries(updates).forEach(([key, value]) => {
            yjsTrigger.set(key, value);
          });
        });
      }
    }
  };

  const setEnabled = (enabled: boolean) => {
    if (!ydoc) return;

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
    if (!ydoc) return;

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
    if (!ydoc) return;

    const positionsMap = ydoc.getMap("positions");
    ydoc.transact(() => {
      positionsMap.set(id, position);
    });
  };

  // =============================================================================
  // PATTERN 3: Direct Immer → Notify (Local UI State)
  // =============================================================================
  // These methods directly update Immer state without Y.Doc involvement

  const selectJob = (id: string | null) => {
    state = produce(state, draft => {
      draft.selectedJobId = id;
      draft.selectedTriggerId = null;
      draft.selectedEdgeId = null;
      updateDerivedState(draft);
    });
    notify();
  };

  const selectTrigger = (id: string | null) => {
    state = produce(state, draft => {
      draft.selectedTriggerId = id;
      draft.selectedJobId = null;
      draft.selectedEdgeId = null;
      updateDerivedState(draft);
    });
    notify();
  };

  const selectEdge = (id: string | null) => {
    state = produce(state, draft => {
      draft.selectedEdgeId = id;
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
      updateDerivedState(draft);
    });
    notify();
  };

  const clearSelection = () => {
    state = produce(state, draft => {
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
      draft.selectedEdgeId = null;
      updateDerivedState(draft);
    });
    notify();
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
    state = produce(state, draft => {
      if (draft.selectedJobId === id) {
        draft.selectedJobId = null;
        updateDerivedState(draft);
      }
    });
    notify();

    // Note: Y.Doc observer will also fire and update the jobs array
  };

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Y.Doc connection management
    connectYDoc,
    disconnectYDoc,
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
    addJob,
    removeJob,
    updateTrigger,
    setEnabled,
    getJobBodyYText,
    updatePositions,
    updatePosition,

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
  };
};

export type WorkflowStoreInstance = ReturnType<typeof createWorkflowStore>;
