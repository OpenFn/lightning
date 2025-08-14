/**
 * WorkflowStoreProvider - New useSyncExternalStore + Immer + Y.Doc implementation
 * Provides referentially stable workflow state management with proper separation
 * between collaborative data and local UI state.
 */

import type React from "react";
import { createContext, useContext, useEffect, useRef } from "react";
import { createWorkflowStore, type WorkflowStoreInstance } from "../stores/createWorkflowStore";
import type { Session } from "../types/session";
import { useSession } from "./SessionProvider";

const WorkflowStoreContext = createContext<WorkflowStoreInstance | null>(null);

export const useWorkflowStoreContext = () => {
  const store = useContext(WorkflowStoreContext);
  if (!store) {
    throw new Error("useWorkflowStore must be used within WorkflowStoreProvider");
  }
  return store;
};

// Legacy Zustand-style hook for backward compatibility during migration
export const useWorkflowStore = <T,>(
  selector: (state: any) => T,
): T => {
  const store = useWorkflowStoreContext();
  const { useSyncExternalStore } = require("react");
  
  return useSyncExternalStore(
    store.subscribe,
    () => selector(store.getSnapshot())
  );
};

// Legacy hooks for backward compatibility
export const useCurrentJob = () => {
  const store = useWorkflowStoreContext();
  const { useSyncExternalStore } = require("react");

  return useSyncExternalStore(store.subscribe, () => {
    const state = store.getSnapshot();
    return {
      job: state.selectedNode && state.selectedJobId ? state.selectedNode : null,
      ytext: state.selectedJobId ? store.getJobBodyYText(state.selectedJobId) : null,
    };
  });
};

export const useTriggerFormActions = () => {
  const store = useWorkflowStoreContext();
  const { useMemo } = require("react");

  return useMemo(
    () => ({
      createTriggerForm: (trigger: any) => {
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

export const useNodeSelection = () => {
  const { useURLState } = require("#/react/lib/use-url-state");
  const { searchParams, updateSearchParams } = useURLState();
  const { useMemo, useCallback, useSyncExternalStore } = require("react");
  
  const store = useWorkflowStoreContext();
  const { jobs, triggers, edges } = useSyncExternalStore(store.subscribe, () => {
    const state = store.getSnapshot();
    return {
      jobs: state.jobs,
      triggers: state.triggers,
      edges: state.edges,
    };
  });

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
      const node = jobs.find((job: any) => job.id === jobId) || null;
      return { node, type: "job" as const, id: jobId };
    } else if (triggerId) {
      const node = triggers.find((trigger: any) => trigger.id === triggerId) || null;
      return { node, type: "trigger" as const, id: triggerId };
    } else if (edgeId) {
      const node = edges.find((edge: any) => edge.id === edgeId) || null;
      return { node, type: "edge" as const, id: edgeId };
    } else {
      return { node: null, type: null, id: null };
    }
  }, [currentNodeId, jobId, triggerId, edgeId, jobs, triggers, edges]);

  // Selection function
  const selectNode = useCallback(
    (id: string | null) => {
      if (!id) {
        updateSearchParams({ job: null, trigger: null, edge: null });
        return;
      }

      // Determine node type and update appropriate URL parameter
      const foundJob = jobs.find((job: any) => job.id === id);
      const foundTrigger = triggers.find((trigger: any) => trigger.id === id);
      const foundEdge = edges.find((edge: any) => edge.id === id);

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

interface WorkflowStoreProviderProps {
  children: React.ReactNode;
}

export const WorkflowStoreProvider: React.FC<WorkflowStoreProviderProps> = ({
  children,
}) => {
  const { ydoc, users } = useSession();
  
  // Create store only once using lazy ref initialization
  const storeRef = useRef<WorkflowStoreInstance>();
  const store = (storeRef.current ||= createWorkflowStore());

  // Connect/disconnect Y.Doc when session changes
  useEffect(() => {
    if (ydoc && users) {
      store.connectYDoc(ydoc as Session.WorkflowDoc, users);
      return () => store.disconnectYDoc();
    } else {
      store.disconnectYDoc();
      return undefined;
    }
  }, [store, ydoc, users]);

  return (
    <WorkflowStoreContext.Provider value={store}>
      {children}
    </WorkflowStoreContext.Provider>
  );
};
