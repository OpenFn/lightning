/**
 * New workflow store hooks using useSyncExternalStore pattern
 * 
 * These hooks provide referentially stable state slices and replace the 
 * Zustand-based hooks with useSyncExternalStore for optimal React integration.
 * All hooks return data from the same Immer-managed state object.
 */

import { useMemo } from "react";
import { useSyncExternalStore } from "react";
import type { Workflow } from "../types/workflow";
import { useWorkflowStoreContext } from "../contexts/WorkflowStoreProvider";

// Main hook that returns full state and actions
export const useWorkflowStore = () => {
  const store = useWorkflowStoreContext();

  // Returns the referentially stable Immer state
  const state = useSyncExternalStore(store.subscribe, store.getSnapshot);

  return {
    // State (referentially stable)
    ...state,

    // Actions
    updateJob: store.updateJob,
    updateJobName: store.updateJobName,
    updateJobBody: store.updateJobBody,
    addJob: store.addJob,
    removeJob: store.removeJob,
    updateTrigger: store.updateTrigger,
    setEnabled: store.setEnabled,
    selectJob: store.selectJob,
    selectTrigger: store.selectTrigger,
    selectEdge: store.selectEdge,
    clearSelection: store.clearSelection,
    removeJobAndClearSelection: store.removeJobAndClearSelection,
    getJobBodyYText: store.getJobBodyYText,
  };
};

// Specialized hooks return slices of the same referentially stable state
export const useWorkflowData = () => {
  const store = useWorkflowStoreContext();

  return useSyncExternalStore(store.subscribe, () => {
    const state = store.getSnapshot();
    return {
      workflow: state.workflow,
      jobs: state.jobs,
      triggers: state.triggers,
      edges: state.edges,
    };
  });
};

export const useWorkflowSelection = () => {
  const store = useWorkflowStoreContext();

  return useSyncExternalStore(store.subscribe, () => {
    const state = store.getSnapshot();
    return {
      selectedJobId: state.selectedJobId,
      selectedTriggerId: state.selectedTriggerId,
      selectedEdgeId: state.selectedEdgeId,
      selectedNode: state.selectedNode,
      selectedEdge: state.selectedEdge,
    };
  });
};

// High-level hook equivalent to current useCurrentJob
export const useCurrentJob = () => {
  const store = useWorkflowStoreContext();

  return useSyncExternalStore(store.subscribe, () => {
    const state = store.getSnapshot();
    return {
      job: state.selectedNode && state.selectedJobId ? state.selectedNode as Workflow.Job : null,
      ytext: state.selectedJobId ? store.getJobBodyYText(state.selectedJobId) : null,
    };
  });
};

// TriggerForm actions hook with CQS pattern
export const useTriggerFormActions = () => {
  const store = useWorkflowStoreContext();

  return useMemo(
    () => ({
      createTriggerForm: (trigger: Workflow.Trigger | null) => {
        // Import here to avoid circular dependency
        const { createDefaultTrigger, TriggerValidation } = require("../validation/TriggerValidation");
        
        return {
          defaultValues: trigger || createDefaultTrigger("webhook"),
          listeners: {
            onChange: ({ formApi }: { formApi: any }) => {
              if (trigger?.id) {
                const values = formApi.state.values;
                store.updateTrigger(trigger.id, values);
              }
            },
          },
          validators: {
            onChange: TriggerValidation,
          },
        };
      },
    }),
    [store]
  );
};

// Node selection hook with URL integration (re-implemented to use new store)
export const useNodeSelection = (): {
  currentNode: {
    node: Workflow.Node | null;
    type: Workflow.NodeType | null;
    id: string | null;
  };
  selectNode: (id: string | null) => void;
} => {
  // Import URL state hook (assuming it exists)
  const { useURLState } = require("#/react/lib/use-url-state");
  const { searchParams, updateSearchParams } = useURLState();

  const { jobs, triggers, edges } = useWorkflowData();

  // Get current node ID from URL
  const jobId = searchParams.get("job");
  const triggerId = searchParams.get("trigger");
  const edgeId = searchParams.get("edge");

  const currentNodeId = jobId || triggerId || edgeId;

  // Resolve current selection with memoization
  const currentNode = useMemo(() => {
    if (!currentNodeId) {
      return { node: null, type: null, id: null };
    } else if (jobId) {
      const node = jobs.find((job) => job.id === jobId) || null;
      return { node, type: "job" as const, id: jobId };
    } else if (triggerId) {
      const node = triggers.find((trigger) => trigger.id === triggerId) || null;
      return { node, type: "trigger" as const, id: triggerId };
    } else if (edgeId) {
      const node = edges.find((edge) => edge.id === edgeId) || null;
      return { node, type: "edge" as const, id: edgeId };
    } else {
      return { node: null, type: null, id: null };
    }
  }, [currentNodeId, jobId, triggerId, edgeId, jobs, triggers, edges]);

  // Selection function
  const selectNode = useMemo(
    () => (id: string | null) => {
      if (!id) {
        updateSearchParams({ job: null, trigger: null, edge: null });
        return;
      }

      // Determine node type and update appropriate URL parameter
      const foundJob = jobs.find((job) => job.id === id);
      const foundTrigger = triggers.find((trigger) => trigger.id === id);
      const foundEdge = edges.find((edge) => edge.id === id);

      if (foundJob) {
        updateSearchParams({ job: id, trigger: null, edge: null });
      } else if (foundTrigger) {
        updateSearchParams({ trigger: id, job: null, edge: null });
      } else if (foundEdge) {
        updateSearchParams({ edge: id, job: null, trigger: null });
      }
    },
    [updateSearchParams, jobs, triggers, edges]
  );

  return { currentNode, selectNode };
};