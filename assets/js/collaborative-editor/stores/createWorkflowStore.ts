/**
 * New workflow store implementation using useSyncExternalStore + Immer + Y.Doc pattern
 * 
 * This replaces the Zustand + YjsBridge anti-pattern with a clean composition that:
 * - Uses Y.Doc as the authoritative source for workflow data
 * - Provides referentially stable state through Immer
 * - Separates collaborative data from local UI state
 * - Implements three clear update patterns
 */

import { produce } from "immer";
import * as Y from "yjs";
import type { AwarenessUser, Session } from "../types/session";
import type { Workflow } from "../types/workflow";

export const createWorkflowStore = () => {
  // Y.Doc will be connected externally via SessionProvider
  let ydoc: Session.WorkflowDoc | null = null;
  let observerCleanups: (() => void)[] = [];

  // Helper to update derived state (defined first to avoid hoisting issues)
  const updateDerivedState = (draft: Workflow.WorkflowState) => {
    // Compute enabled from triggers
    draft.enabled = draft.triggers.length > 0
      ? draft.triggers.some((t) => t.enabled)
      : null;

    // Compute selected node
    if (draft.selectedJobId) {
      draft.selectedNode = draft.jobs.find((j) => j.id === draft.selectedJobId) || null;
    } else if (draft.selectedTriggerId) {
      draft.selectedNode = draft.triggers.find((t) => t.id === draft.selectedTriggerId) || null;
    } else {
      draft.selectedNode = null;
    }

    // Compute selected edge
    draft.selectedEdge = draft.selectedEdgeId
      ? draft.edges.find((e) => e.id === draft.selectedEdgeId) || null
      : null;

    // Compute collaboration status  
    draft.isCollaborating = draft.connectedUsers.length > 1;
  };

  // Single Immer-managed state object (referentially stable)
  let state: Workflow.WorkflowState = produce(
    {
      // Initialize with empty data (Y.Doc will sync when connected)
      workflow: null,
      jobs: [],
      triggers: [],
      edges: [],

      // Initialize UI state
      selectedJobId: null,
      selectedTriggerId: null,
      selectedEdgeId: null,

      // Initialize computed state
      enabled: null,
      selectedNode: null,
      selectedEdge: null,
      isCollaborating: false,
      connectedUsers: [],
    } as Workflow.WorkflowState,
    (draft) => {
      // Compute derived state on initialization
      updateDerivedState(draft);
    }
  );

  const listeners = new Set<() => void>();

  const notify = () => {
    listeners.forEach((listener) => listener());
  };

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  // Returns the current Immer state (referentially stable)
  const getSnapshot = (): Workflow.WorkflowState => state;

  // Connect Y.Doc and set up observers
  const connectYDoc = (doc: Session.WorkflowDoc, users: AwarenessUser[]) => {
    // Clean up previous connection
    disconnectYDoc();

    ydoc = doc;

    // Get Y.js maps and arrays
    const workflowMap = doc.getMap("workflow");
    const jobsArray = doc.getArray("jobs");
    const triggersArray = doc.getArray("triggers");
    const edgesArray = doc.getArray("edges");

    // Set up observers
    const workflowObserver = () => {
      state = produce(state, (draft) => {
        draft.workflow = workflowMap.toJSON() as Session.Workflow;
        updateDerivedState(draft);
      });
      notify();
    };

    const jobsObserver = () => {
      state = produce(state, (draft) => {
        const yjsJobs = jobsArray.toArray() as Y.Map<unknown>[];
        draft.jobs = yjsJobs.map((yjsJob) => yjsJob.toJSON() as Workflow.Job);
        updateDerivedState(draft);
      });
      notify();
    };

    const triggersObserver = () => {
      state = produce(state, (draft) => {
        const yjsTriggers = triggersArray.toArray() as Y.Map<unknown>[];
        draft.triggers = yjsTriggers.map((yjsTrigger) => yjsTrigger.toJSON() as Workflow.Trigger);
        updateDerivedState(draft);
      });
      notify();
    };

    const edgesObserver = () => {
      state = produce(state, (draft) => {
        const yjsEdges = edgesArray.toArray() as Y.Map<unknown>[];
        draft.edges = yjsEdges.map((yjsEdge) => yjsEdge.toJSON() as Workflow.Edge);
        updateDerivedState(draft);
      });
      notify();
    };

    // Attach observers with deep observation for nested changes
    workflowMap.observeDeep(workflowObserver);
    jobsArray.observeDeep(jobsObserver);
    triggersArray.observeDeep(triggersObserver);
    edgesArray.observeDeep(edgesObserver);

    // Store cleanup functions
    observerCleanups = [
      () => workflowMap.unobserveDeep(workflowObserver),
      () => jobsArray.unobserveDeep(jobsObserver),
      () => triggersArray.unobserveDeep(triggersObserver),
      () => edgesArray.unobserveDeep(edgesObserver),
    ];

    // Update connected users
    state = produce(state, (draft) => {
      draft.connectedUsers = users;
      updateDerivedState(draft);
    });
    notify();

    // Initial sync from Y.Doc to state
    workflowObserver();
    jobsObserver();
    triggersObserver();
    edgesObserver();
  };

  // Disconnect Y.Doc and clean up observers
  const disconnectYDoc = () => {
    observerCleanups.forEach((cleanup) => cleanup());
    observerCleanups = [];
    ydoc = null;

    // Update collaboration status
    state = produce(state, (draft) => {
      draft.connectedUsers = [];
      updateDerivedState(draft);
    });
    notify();
  };

  // Pattern 1: Y.Doc update → observer → immer update → notify
  const updateJob = (id: string, updates: Partial<Session.Job>) => {
    if (!ydoc) {
      // Fallback to direct state update if Y.Doc not connected
      state = produce(state, (draft) => {
        const job = draft.jobs.find((j) => j.id === id);
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
    const jobIndex = jobs.findIndex((job) => job.get("id") === id);

    if (jobIndex >= 0) {
      const yjsJob = jobs[jobIndex];
      if (yjsJob) {
        ydoc.transact(() => {
          Object.entries(updates).forEach(([key, value]) => {
            if (key === "body" && typeof value === "string") {
              const ytext = yjsJob.get("body") as Y.Text;
              if (ytext) {
                ytext.delete(0, ytext.length);
                ytext.insert(0, value);
              }
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
    const jobIndex = jobs.findIndex((job) => job.get("id") === id);

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
    const triggerIndex = triggers.findIndex((trigger) => trigger.get("id") === id);

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
      triggers.forEach((trigger) => {
        trigger.set("enabled", enabled);
      });
    });
  };

  const getJobBodyYText = (id: string): Y.Text | null => {
    if (!ydoc) return null;

    const jobsArray = ydoc.getArray("jobs");
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    const yjsJob = jobs.find((job) => job.get("id") === id);

    return yjsJob ? (yjsJob.get("body") as Y.Text) : null;
  };

  // Pattern 3: Direct immer update → notify (local UI state)
  const selectJob = (id: string | null) => {
    state = produce(state, (draft) => {
      draft.selectedJobId = id;
      draft.selectedTriggerId = null;
      draft.selectedEdgeId = null;
      updateDerivedState(draft);
    });
    notify();
  };

  const selectTrigger = (id: string | null) => {
    state = produce(state, (draft) => {
      draft.selectedTriggerId = id;
      draft.selectedJobId = null;
      draft.selectedEdgeId = null;
      updateDerivedState(draft);
    });
    notify();
  };

  const selectEdge = (id: string | null) => {
    state = produce(state, (draft) => {
      draft.selectedEdgeId = id;
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
      updateDerivedState(draft);
    });
    notify();
  };

  const clearSelection = () => {
    state = produce(state, (draft) => {
      draft.selectedJobId = null;
      draft.selectedTriggerId = null;
      draft.selectedEdgeId = null;
      updateDerivedState(draft);
    });
    notify();
  };

  // Pattern 2: Y.Doc + immediate immer update → notify (rare)
  const removeJobAndClearSelection = (id: string) => {
    // Update Y.Doc first
    removeJob(id);

    // Immediately clear selection if this job was selected
    state = produce(state, (draft) => {
      if (draft.selectedJobId === id) {
        draft.selectedJobId = null;
        updateDerivedState(draft);
      }
    });
    notify();

    // Note: Y.Doc observer will also fire and update the jobs array
  };

  return {
    subscribe,
    getSnapshot, // Returns current Immer state (referentially stable)

    // Y.Doc connection management
    connectYDoc,
    disconnectYDoc,
    get isConnected() {
      return ydoc !== null;
    },
    get ydoc() {
      return ydoc;
    },

    // Pattern 1: Y.Doc → observer → immer
    updateJob,
    updateJobName,
    updateJobBody,
    addJob,
    removeJob,
    updateTrigger,
    setEnabled,
    getJobBodyYText,

    // Pattern 3: Direct immer
    selectJob,
    selectTrigger,
    selectEdge,
    clearSelection,

    // Pattern 2: Y.Doc + immediate immer (rare)
    removeJobAndClearSelection,
  };
};

export type WorkflowStoreInstance = ReturnType<typeof createWorkflowStore>;