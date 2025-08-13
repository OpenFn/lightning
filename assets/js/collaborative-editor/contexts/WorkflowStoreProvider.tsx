/**
 * WorkflowStoreProvider - Yjs WorkflowStore for workflow-specific operations
 * Uses SessionProvider for shared Yjs/Phoenix Channel infrastructure
 */

import type React from "react";
import { createContext, useCallback, useContext, useMemo, useRef } from "react";
import { useStore } from "zustand";
import { useURLState } from "#/react/lib/use-url-state";
import { useYjsWorkflowSync } from "../hooks/useYjsWorkflowSync";
import { createWorkflowStore } from "../stores/WorkflowStore";
import type { Workflow } from "../types";
import type { Session } from "../types/session";
import {
  createDefaultTrigger,
  TriggerValidation,
  type ValidatedTrigger,
} from "../validation/TriggerValidation";
import { useSession } from "./SessionProvider";

const WorkflowStoreContext = createContext<ReturnType<
  typeof createWorkflowStore
> | null>(null);

export const useWorkflowStore = <T,>(
  selector: (state: Workflow.Store) => T,
): T => {
  const store = useContext(WorkflowStoreContext);
  if (!store) {
    throw new Error(
      "useWorkflowStore must be used within a WorkflowStoreProvider",
    );
  }
  return useStore(store, selector);
};

/**
 * Hook for accessing the currently selected job and its collaborative Y.Text body.
 *
 * @returns Object containing:
 *   - job: The currently selected job object, or null if none selected
 *   - ytext: The Y.Text object for the job's body (for collaborative editing), or null
 *
 * @example
 * ```typescript
 * const { job, ytext } = useCurrentJob();
 *
 * if (job && ytext) {
 *   console.log(`Editing job: ${job.name}`);
 *   // Use ytext with Monaco collaborative editor
 * }
 * ```
 */
export const useCurrentJob = () => {
  const { selectedJobId, jobs, getJobBodyYText } = useWorkflowStore(
    (state) => ({
      selectedJobId: state.selectedJobId,
      jobs: state.jobs,
      getJobBodyYText: state.getJobBodyYText,
    }),
  );

  const job = selectedJobId
    ? jobs.find((job) => job.id === selectedJobId) || null
    : null;

  const ytext = job ? getJobBodyYText(job.id) : null;

  return { job, ytext };
};

/**
 * Hook for trigger form actions following CQS pattern.
 * Provides command functions for managing trigger forms.
 *
 * @returns Object containing:
 *   - createTriggerForm: Function that creates a TanStack Form instance for triggers
 *
 * @example
 * ```typescript
 * const { createTriggerForm } = useTriggerFormActions();
 * const form = createTriggerForm(currentTrigger);
 * ```
 */
export const useTriggerFormActions = () => {
  const { updateTrigger } = useWorkflowStore((state) => ({
    updateTrigger: state.updateTrigger,
  }));

  const createTriggerForm = useCallback(
    (trigger: Workflow.Trigger | null) => {
      // Create default values based on trigger type or default to webhook
      const triggerType =
        (trigger?.type as "webhook" | "cron" | "kafka") || "webhook";

      const defaultValues = trigger || createDefaultTrigger(triggerType);

      // Return form factory function with Yjs integration
      return {
        defaultValues: defaultValues as ValidatedTrigger,
        listeners: {
          onChange: ({ formApi }) => {
            if (trigger?.id) {
              const values = formApi.state.values;
              updateTrigger(trigger.id, values);
            }
          },
        },
        validators: {
          onChange: TriggerValidation,
        },
      };
    },
    [updateTrigger],
  );

  return { createTriggerForm };
};

/**
 * Hook for managing workflow node selection (jobs, triggers, edges) via URL parameters.
 *
 * This hook provides both the current selection state and a function to change selection.
 * Selection state is persisted in URL parameters (?job=id, ?trigger=id, or ?edge=id)
 * and survives page refreshes.
 *
 * @returns Object containing:
 *   - currentNode: Object with the selected node data, type, and id
 *   - selectNode: Function to change the current selection by node id
 *
 * @example
 * ```typescript
 * const { currentNode, selectNode } = useNodeSelection();
 *
 * // Check current selection
 * if (currentNode.type === 'job') {
 *   console.log(`Selected job: ${currentNode.node?.name}`);
 * }
 *
 * // Change selection (updates URL and triggers re-renders)
 * selectNode('some-job-id'); // Sets ?job=some-job-id
 * selectNode(null);         // Clears all selection params
 *
 * // Usage in diagram components
 * <WorkflowDiagram
 *   selection={currentNode.id}
 *   onSelectionChange={selectNode}
 * />
 * ```
 */
export const useNodeSelection = (): {
  currentNode: {
    node: Workflow.Node | null;
    type: Workflow.NodeType | null;
    id: string | null;
  };
  selectNode: (id: string | null) => void;
} => {
  const { searchParams, updateSearchParams } = useURLState();

  const { jobs, triggers, edges } = useWorkflowStore((state) => ({
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
  }));

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

  // IDEA: if selectNode took a 'currentNode' object we wouldn't need to do the
  // find-by-id logic in the selectNode function. That would arguably require us
  // to keep the currentNode in the store and set/update it using immer.

  // Selection function
  const selectNode = useCallback(
    (id: string | null) => {
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
    [updateSearchParams, jobs, triggers, edges],
  );

  return { currentNode, selectNode };
};

interface WorkflowStoreProviderProps {
  children: React.ReactNode;
}

export const WorkflowStoreProvider: React.FC<WorkflowStoreProviderProps> = ({
  children,
}) => {
  const { ydoc: ydoc_ } = useSession();
  const ydoc = ydoc_ as Session.WorkflowDoc;

  // Create store only once using lazy ref initialization
  const storeRef = useRef<ReturnType<typeof createWorkflowStore>>();
  const store = (storeRef.current ||= createWorkflowStore());

  // Set up Yjs ↔ Store sync for workflow data
  useYjsWorkflowSync(ydoc, store);

  return (
    <WorkflowStoreContext.Provider value={store}>
      {children}
    </WorkflowStoreContext.Provider>
  );
};
