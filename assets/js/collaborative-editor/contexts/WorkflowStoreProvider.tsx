/**
 * WorkflowStoreProvider - Yjs WorkflowStore for workflow-specific operations
 * Uses SessionProvider for shared Yjs/Phoenix Channel infrastructure
 */

import type React from "react";
import { createContext, useContext, useRef } from "react";
import { useStore } from "zustand";
import { useURLJobSync } from "../hooks/useURLJobSync";
import { useYjsWorkflowSync } from "../hooks/useYjsWorkflowSync";
import { createWorkflowStore } from "../stores/WorkflowStore";
import type { Workflow } from "../types";
import type { Session } from "../types/session";
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

  // Set up URL ↔ Store sync for selected job
  useURLJobSync(store);

  // Set up Yjs ↔ Store sync for workflow data
  useYjsWorkflowSync(ydoc, store);

  return (
    <WorkflowStoreContext.Provider value={store}>
      {children}
    </WorkflowStoreContext.Provider>
  );
};
